import 'package:flutter/material.dart';
import 'ai_page.dart';
import 'state.dart';
import 'widgets.dart';

const _pad = EdgeInsets.fromLTRB(16, 12, 16, 24);

// ======================= JADWAL =======================
const _dn = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _bit = [1, 2, 3, 4, 5, 6, 0];

String _days(int d) {
  if (d == 127) return 'Setiap hari';
  final r = <String>[for (var k = 0; k < 7; k++) if (((d >> _bit[k]) & 1) == 1) _dn[k]];
  return r.isEmpty ? '-' : r.join(', ');
}

class SchedulePage extends StatelessWidget {
  final AppState s;
  const SchedulePage(this.s, {super.key});

  void _edit(BuildContext c, int i) {
    var h = s.sched[i].h, m = s.sched[i].m, days = s.sched[i].days;
    var dur = s.sched[i].dur.toDouble();
    showModalBottomSheet(
      context: c,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Jadwal ${i + 1}', style: Theme.of(ctx).textTheme.titleLarge),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text('${two(h)}:${two(m)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: h, minute: m));
                if (t != null) set(() {
                  h = t.hour;
                  m = t.minute;
                });
              },
            ),
            Wrap(spacing: 6, children: [
              for (var k = 0; k < 7; k++)
                FilterChip(
                  label: Text(_dn[k]),
                  selected: ((days >> _bit[k]) & 1) == 1,
                  onSelected: (v) => set(() => days = v ? (days | (1 << _bit[k])) : (days & ~(1 << _bit[k]))),
                ),
            ]),
            const SizedBox(height: 8),
            Text('Durasi siram: ${dur.round()} detik'),
            Slider(value: dur, min: 1, max: 60, divisions: 59, onChanged: (v) => set(() => dur = v)),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final x = s.sched[i];
                  x.h = h;
                  x.m = m;
                  x.dur = dur.round();
                  x.days = days == 0 ? 127 : days;
                  x.en = true;
                  s.pushSched(i);
                  Navigator.pop(ctx);
                },
                child: const Text('Simpan & aktifkan'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    return ListView(padding: _pad, children: [
      heading(c, 'Jadwal siram'),
      if (s.connected && !s.timeOk)
        Panel(
          color: cs.errorContainer,
          child: const Text('Jam alat belum sinkron. Jadwal belum berjalan sampai jam tersinkron (otomatis saat terhubung).'),
        ),
      Panel(
        color: cs.secondaryContainer.withValues(alpha: .5),
        child: Row(children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Jadwal berjalan di mode Otomatis dan dilewati bila tanah sudah ≥ 85% (hemat air).'),
          ),
        ]),
      ),
      for (var i = 0; i < 4; i++)
        Panel(
          onTap: s.connected ? () => _edit(c, i) : null,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${two(s.sched[i].h)}:${two(s.sched[i].m)}',
                    style: tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: s.sched[i].en ? null : cs.outline,
                    )),
                Text('${_days(s.sched[i].days)} - ${s.sched[i].dur} dtk', style: tt.bodySmall),
              ]),
            ),
            Switch(
              value: s.sched[i].en,
              onChanged: s.connected
                  ? (v) {
                      s.sched[i].en = v;
                      s.pushSched(i);
                    }
                  : null,
            ),
          ]),
        ),
    ]);
  }
}

// ======================= RIWAYAT =======================
class HistoryPage extends StatefulWidget {
  final AppState s;
  const HistoryPage(this.s, {super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int _range = 1, _metric = 0;
  static const _secs = [3600, 21600, 86400];

  @override
  Widget build(BuildContext c) {
    final s = widget.s, cs = Theme.of(c).colorScheme;
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - _secs[_range];
    final data = s.samples.where((e) => e.t >= since).toList();
    final f = [(Sample e) => e.soil.toDouble(), (Sample e) => e.temp, (Sample e) => e.hum.toDouble()][_metric];
    final hi = _metric == 1 ? 50.0 : 100.0;
    final vals = data.map(f).toList();
    String stat(String l, double v) => '$l ${v.toStringAsFixed(_metric == 1 ? 1 : 0)}';
    return ListView(padding: _pad, children: [
      heading(c, 'Riwayat'),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Tanah')),
          ButtonSegment(value: 1, label: Text('Suhu')),
          ButtonSegment(value: 2, label: Text('Udara')),
        ],
        selected: {_metric},
        onSelectionChanged: (v) => setState(() => _metric = v.first),
      ),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('1 jam')),
          ButtonSegment(value: 1, label: Text('6 jam')),
          ButtonSegment(value: 2, label: Text('24 jam')),
        ],
        selected: {_range},
        onSelectionChanged: (v) => setState(() => _range = v.first),
      ),
      const SizedBox(height: 12),
      Panel(
        child: data.length < 2
            ? const SizedBox(
                height: 180,
                child: Center(child: Text('Belum ada data.\nBiarkan alat terhubung beberapa menit.', textAlign: TextAlign.center)),
              )
            : Column(children: [
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: ChartPainter(
                      data,
                      f,
                      0,
                      hi,
                      _metric == 0 ? s.minSoil.toDouble() : null,
                      cs.primary,
                      cs.outlineVariant,
                      cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  Text(stat('Min', vals.reduce((a, b) => a < b ? a : b))),
                  Text(stat('Rata-rata', vals.reduce((a, b) => a + b) / vals.length)),
                  Text(stat('Maks', vals.reduce((a, b) => a > b ? a : b))),
                ]),
              ]),
      ),
      Row(children: [
        Expanded(child: heading(c, 'Kejadian')),
        TextButton.icon(onPressed: s.clearHistory, icon: const Icon(Icons.delete_outline), label: const Text('Hapus')),
      ]),
      if (s.events.isEmpty) const Panel(child: Text('Belum ada kejadian.')),
      for (final e in s.events.take(50))
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.only(bottom: 8),
          onTap: e.kind == 2
              ? () => openAi(c, s, prompt: 'Jelaskan kemungkinan penyebab dan langkah cek untuk peringatan ini: "${e.text}".')
              : null,
          child: Row(children: [
            Icon(
              e.kind == 1 ? Icons.water_drop : (e.kind == 2 ? Icons.warning_amber_rounded : Icons.info_outline),
              color: e.kind == 1 ? Colors.blue : (e.kind == 2 ? cs.error : cs.outline),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(e.text)),
            Text(fmtEv(e.t), style: Theme.of(c).textTheme.bodySmall),
          ]),
        ),
    ]);
  }
}

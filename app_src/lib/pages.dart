import 'package:flutter/material.dart';
import 'state.dart';
import 'widgets.dart';

const _pad = EdgeInsets.fromLTRB(16, 12, 16, 24);

// ======================= BERANDA =======================
class HomePage extends StatelessWidget {
  final AppState s;
  final VoidCallback toSettings;
  const HomePage(this.s, this.toSettings, {super.key});

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    final dry = s.soil < s.minSoil;
    final gc = !s.connected
        ? cs.outline
        : dry
            ? Colors.orange.shade700
            : (s.soil > 85 ? Colors.blue : Colors.green.shade600);
    final done = s.events.where((e) => e.text.startsWith('Penyiraman selesai')).toList();
    return ListView(padding: _pad, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AgriBot', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(s.plant.isEmpty ? 'Pilih tanaman di tab Tanaman' : '${presetEmoji(s.plant)} ${s.plant}'),
          ]),
        ),
        ConnChip(s),
      ]),
      const SizedBox(height: 16),
      if (!s.connected)
        Panel(
          color: cs.primaryContainer.withValues(alpha: .5),
          child: Column(children: [
            Icon(netIcon(s.net), size: 36, color: cs.primary),
            const SizedBox(height: 8),
            Text(s.status, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: s.busy ? null : s.connect,
                  icon: s.busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: Text('Hubungkan (${netNames[s.net]})'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: toSettings, child: const Text('Mode')),
            ]),
          ]),
        ),
      if (s.connected && s.net == Net.cloud && !s.online)
        Panel(
          color: cs.errorContainer,
          child: Row(children: [
            Icon(Icons.cloud_off, color: cs.error),
            const SizedBox(width: 12),
            Expanded(child: Text('Alat offline - terakhir terlihat ${s.offAge} dtk lalu. Data di bawah adalah data terakhir.')),
          ]),
        ),
      if (s.connected && !s.water)
        Panel(
          color: cs.errorContainer,
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: cs.error),
            const SizedBox(width: 12),
            const Expanded(child: Text('Tangki air habis! Pompa dikunci sampai tangki diisi.')),
          ]),
        ),
      Panel(
        child: Column(children: [
          SizedBox(
            height: 230,
            child: Stack(alignment: Alignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: s.soil / 100),
                duration: const Duration(milliseconds: 700),
                builder: (_, v, __) => CustomPaint(
                  size: const Size(230, 230),
                  painter: GaugePainter(v, s.minSoil / 100, cs.surfaceContainerHighest, gc, cs.onSurface),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${s.soil}%', style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: gc)),
                Text('Kelembaban tanah', style: tt.bodySmall),
              ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: gc.withValues(alpha: .14), borderRadius: BorderRadius.circular(30)),
            child: Text(
              !s.connected ? 'Tidak terhubung' : (dry ? 'Kering - batas siram ${s.minSoil}%' : 'Lembab - batas siram ${s.minSoil}%'),
              style: TextStyle(color: gc, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
      Row(children: [
        Stat(Icons.thermostat, 'Suhu', s.temp < -50 ? '--' : '${s.temp.toStringAsFixed(1)}°C'),
        Stat(Icons.water_drop_outlined, 'Udara', '${s.hum}%'),
        Stat(Icons.water, 'Tangki', s.water ? 'Aman' : 'Habis', color: s.water ? Colors.blue : cs.error),
      ]),
      const SizedBox(height: 8),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(s.pump ? Icons.water_drop : Icons.water_drop_outlined, color: s.pump ? Colors.blue : cs.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.pump ? 'Pompa menyala - sisa ${s.remain} dtk' : 'Pompa mati', style: tt.titleMedium),
            ),
          ]),
          if (s.pump) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
          if (s.connected && s.cfg.containsKey('tot'))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Air terpakai total ≈ ${(s.cfgInt('tot', 0) * s.cfgInt('flow', 30) / 1000).toStringAsFixed(1)} L'
                ' - hari ini ${s.cfgInt('dc', 0)}x siram otomatis',
                style: tt.bodySmall,
              ),
            ),
          if (done.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Terakhir disiram: ${fmtEv(done.first.t)}', style: tt.bodySmall),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Otomatis'), icon: Icon(Icons.autorenew)),
                ButtonSegment(value: false, label: Text('Manual'), icon: Icon(Icons.pan_tool_alt)),
              ],
              selected: {s.auto},
              onSelectionChanged: s.connected ? (v) => s.setAuto(v.first) : null,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: s.connected && (s.water || s.pump) ? s.togglePump : null,
              icon: Icon(s.pump ? Icons.stop_circle_outlined : Icons.shower),
              label: Text(s.pump ? 'Matikan pompa' : 'Siram sekarang'),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ======================= TANAMAN =======================
class PlantsPage extends StatefulWidget {
  final AppState s;
  const PlantsPage(this.s, {super.key});
  @override
  State<PlantsPage> createState() => _PlantsPageState();
}

class _PlantsPageState extends State<PlantsPage> {
  double _m = 55, _r = 5, _w = 60;
  bool _synced = false;

  @override
  Widget build(BuildContext c) {
    final s = widget.s, cs = Theme.of(c).colorScheme;
    if (s.connected && !_synced) {
      _m = s.minSoil.toDouble().clamp(10.0, 90.0).toDouble();
      _r = s.run.toDouble().clamp(1.0, 30.0).toDouble();
      _w = s.wait.toDouble().clamp(10.0, 600.0).toDouble();
      _synced = true;
    }
    if (!s.connected) _synced = false;
    final cur = presets.where((p) => p.name == s.plant);
    return ListView(padding: _pad, children: [
      heading(c, 'Preset tanaman'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.3,
        children: [
          for (final p in presets)
            Panel(
              margin: EdgeInsets.zero,
              border: s.plant == p.name ? cs.primary : null,
              color: s.plant == p.name ? cs.primaryContainer.withValues(alpha: .4) : null,
              onTap: () {
                if (!s.connected) {
                  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Hubungkan alat dulu')));
                  return;
                }
                setState(() {
                  _m = p.min.toDouble();
                  _r = p.run.toDouble();
                  _w = p.wait.toDouble();
                });
                s.applyPreset(p);
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.emoji, style: const TextStyle(fontSize: 28)),
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('< ${p.min}% - ${p.run} dtk', style: Theme.of(c).textTheme.bodySmall),
              ]),
            ),
        ],
      ),
      if (cur.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Panel(
            color: cs.tertiaryContainer.withValues(alpha: .5),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline),
              const SizedBox(width: 12),
              Expanded(child: Text(cur.first.tip)),
            ]),
          ),
        ),
      heading(c, 'Atur manual'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Siram jika kelembaban di bawah ${_m.round()}%'),
          Slider(value: _m, min: 10, max: 90, divisions: 80, onChanged: (v) => setState(() => _m = v)),
          Text('Lama siram: ${_r.round()} detik'),
          Slider(value: _r, min: 1, max: 30, divisions: 29, onChanged: (v) => setState(() => _r = v)),
          Text('Jeda antar siram: ${_w.round()} detik'),
          Slider(value: _w, min: 10, max: 600, divisions: 59, onChanged: (v) => setState(() => _w = v)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: s.connected ? () => s.tune(_m.round(), _r.round(), _w.round()) : null,
              child: const Text('Terapkan'),
            ),
          ),
        ]),
      ),
    ]);
  }
}

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

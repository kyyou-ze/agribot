import 'package:flutter/material.dart';
import 'ai_page.dart';
import 'setup_page.dart';
import 'state.dart';
import 'widgets.dart';

void openSetup(BuildContext c, AppState s) => Navigator.push(c, MaterialPageRoute(builder: (_) => SetupPage(s)));

class HomePage extends StatelessWidget {
  final AppState s;
  final VoidCallback toSettings;
  const HomePage(this.s, this.toSettings, {super.key});

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    final on = cs.onPrimary;
    final dry = s.connected && s.soil < s.effMin;
    final done = s.events.where((e) => e.text.startsWith('Penyiraman selesai')).toList();
    final hero = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, .6)!],
    );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Akar Siaga', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
            Text(
              s.usingSim ? 'Mode uji - alat virtual' : s.cfgStr('name', 'Penyiram tanaman otomatis'),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        ConnChip(s),
      ]),
      const SizedBox(height: 16),

      // ---------- belum dipasang / belum terhubung ----------
      if (!s.hasPaired && !s.connected)
        Panel(
          color: cs.primaryContainer,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.eco, size: 36, color: cs.onPrimaryContainer),
            const SizedBox(height: 10),
            Text('Selamat datang!', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
            const SizedBox(height: 6),
            Text('Pasang alat dalam 3 langkah singkat. Semuanya terisi otomatis.', style: TextStyle(color: cs.onPrimaryContainer)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: FilledButton(onPressed: () => openSetup(c, s), child: const Text('Pasang alat baru'))),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: toSettings, child: const Text('Setelan')),
            ]),
          ]),
        )
      else if (!s.connected)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.link_off, color: cs.outline),
              const SizedBox(width: 10),
              Expanded(child: Text(s.status)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: s.busy ? null : s.connect,
                  icon: s.busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: const Text('Hubungkan'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(onPressed: () => openSetup(c, s), child: const Text('Pasang alat baru')),
            ]),
          ]),
        ),
      if (s.needsSetup)
        Panel(
          color: cs.tertiaryContainer,
          child: Row(children: [
            Icon(Icons.wifi_find, color: cs.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(child: Text('Alat masih di mode pemasangan (belum masuk WiFi rumah).', style: TextStyle(color: cs.onTertiaryContainer))),
            TextButton(onPressed: () => openSetup(c, s), child: const Text('Pasang')),
          ]),
        ),
      if (s.connected && s.via == Net.cloud && !s.online)
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

      // ---------- kartu utama ----------
      Panel(
        gradient: hero,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(children: [
          Row(children: [
            InkWell(
              onTap: () => showPlantSheet(c, s),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(color: on.withValues(alpha: .18), borderRadius: BorderRadius.circular(22)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.plant.isEmpty ? '🌱' : presetEmoji(s.plant), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(s.plant.isEmpty ? 'Pilih tanaman' : s.plant, style: TextStyle(color: on, fontWeight: FontWeight.w700)),
                  Icon(Icons.expand_more, color: on, size: 20),
                ]),
              ),
            ),
            const Spacer(),
            Text('Batas siram ${s.effMin}%', style: TextStyle(color: on.withValues(alpha: .85), fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 230,
            child: Stack(alignment: Alignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: s.soil / 100),
                duration: const Duration(milliseconds: 700),
                builder: (_, v, __) => CustomPaint(
                  size: const Size(230, 230),
                  painter: GaugePainter(v, s.effMin / 100, on.withValues(alpha: .22), on, cs.tertiaryContainer),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${s.soil}%', style: TextStyle(fontSize: 58, fontWeight: FontWeight.w800, color: on, height: 1)),
                const SizedBox(height: 4),
                Text(
                  !s.connected ? 'Tidak terhubung' : (dry ? 'Perlu disiram' : 'Cukup lembab'),
                  style: TextStyle(color: on.withValues(alpha: .9), fontWeight: FontWeight.w600),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 4),
          Row(children: [
            MiniStat(Icons.thermostat, 'Suhu', s.temp < -50 ? '--' : '${s.temp.toStringAsFixed(1)}°', on),
            const SizedBox(width: 8),
            MiniStat(Icons.water_drop_outlined, 'Udara', '${s.hum}%', on),
            const SizedBox(width: 8),
            MiniStat(Icons.water, 'Tangki', s.water ? 'Aman' : 'Habis', on),
          ]),
        ]),
      ),

      // ---------- kontrol ----------
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: s.pump ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(s.pump ? Icons.water_drop : Icons.water_drop_outlined, color: s.pump ? cs.onPrimary : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.pump ? 'Menyiram - sisa ${s.remain} dtk' : 'Pompa siap', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  done.isNotEmpty ? 'Terakhir disiram ${fmtEv(done.first.t)}' : 'Belum ada penyiraman tercatat',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
            ),
          ]),
          if (s.pump) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(borderRadius: BorderRadius.all(Radius.circular(8)))),
          if (s.connected && s.cfg.containsKey('tot'))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Air terpakai ≈ ${(s.cfgInt('tot', 0) * s.cfgInt('flow', 30) / 1000).toStringAsFixed(1)} L - hari ini ${s.cfgInt('dc', 0)}x siram otomatis',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
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
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: s.connected && (s.water || s.pump) ? s.togglePump : null,
              icon: Icon(s.pump ? Icons.stop_circle_outlined : Icons.shower),
              label: Text(s.pump ? 'Matikan pompa' : 'Siram sekarang'),
            ),
          ),
        ]),
      ),

      // ---------- asisten AI ----------
      Panel(
        color: cs.tertiaryContainer.withValues(alpha: .55),
        onTap: () => openAi(c, s),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: cs.tertiary, borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.auto_awesome, color: cs.onTertiary),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Asisten AI', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('Tanya soal tanaman, minta saran pengaturan'),
            ]),
          ),
          const Icon(Icons.chevron_right),
        ]),
      ),
    ]);
  }
}

// ======================= pilih tanaman =======================
void showPlantSheet(BuildContext c, AppState s) =>
    showModalBottomSheet(context: c, isScrollControlled: true, showDragHandle: true, builder: (_) => _PlantSheet(s));

class _PlantSheet extends StatefulWidget {
  final AppState s;
  const _PlantSheet(this.s);
  @override
  State<_PlantSheet> createState() => _PlantSheetState();
}

class _PlantSheetState extends State<_PlantSheet> {
  late double _m, _r, _w;
  AppState get s => widget.s;

  @override
  void initState() {
    super.initState();
    _m = s.minSoil.toDouble().clamp(10.0, 90.0).toDouble();
    _r = s.run.toDouble().clamp(1.0, 30.0).toDouble();
    _w = s.wait.toDouble().clamp(10.0, 600.0).toDouble();
  }

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    final cur = presets.where((p) => p.name == s.plant);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pilih tanaman', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Pengaturan siram terisi otomatis sesuai tanaman.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              for (final p in presets)
                Panel(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(14),
                  color: s.plant == p.name ? cs.primaryContainer : cs.surfaceContainerHigh,
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
                    Text(p.emoji, style: const TextStyle(fontSize: 26)),
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('< ${p.min}% - ${p.run} dtk', style: tt.bodySmall),
                  ]),
                ),
            ],
          ),
          if (cur.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Icon(Icons.lightbulb_outline, color: cs.tertiary),
                const SizedBox(width: 10),
                Expanded(child: Text(cur.first.tip)),
              ]),
            ),
          const SizedBox(height: 18),
          Text('Atur manual', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text('Siram jika kelembaban di bawah ${_m.round()}%'),
          Slider(value: _m, min: 10, max: 90, divisions: 80, onChanged: (v) => setState(() => _m = v)),
          Text('Lama siram: ${_r.round()} detik'),
          Slider(value: _r, min: 1, max: 30, divisions: 29, onChanged: (v) => setState(() => _r = v)),
          Text('Jeda antar siram: ${_w.round()} detik'),
          Slider(value: _w, min: 10, max: 600, divisions: 59, onChanged: (v) => setState(() => _w = v)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: s.connected
                  ? () {
                      s.tune(_m.round(), _r.round(), _w.round());
                      Navigator.pop(c);
                    }
                  : null,
              child: const Text('Terapkan'),
            ),
          ),
        ]),
      ),
    );
  }
}

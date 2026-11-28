import 'package:flutter/material.dart';
import 'home.dart';
import 'push/push_service.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

class _SliderSet extends StatefulWidget {
  final String title, unit;
  final int value, min, max;
  final bool enabled;
  final ValueChanged<int> onSave;
  final String Function(int)? fmt;
  final String? help;
  const _SliderSet({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onSave,
    this.unit = '',
    this.enabled = true,
    this.fmt,
    this.help,
  });
  @override
  State<_SliderSet> createState() => _SliderSetState();
}

class _SliderSetState extends State<_SliderSet> {
  late double _v;
  bool _drag = false;

  @override
  void initState() {
    super.initState();
    _v = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(_SliderSet o) {
    super.didUpdateWidget(o);
    if (!_drag) _v = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext c) {
    final r = _v.round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(widget.title)),
        Text(widget.fmt != null ? widget.fmt!(r) : '$r${widget.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      Slider(
        value: _v.clamp(widget.min.toDouble(), widget.max.toDouble()).toDouble(),
        min: widget.min.toDouble(),
        max: widget.max.toDouble(),
        divisions: widget.max - widget.min,
        onChanged: widget.enabled
            ? (x) => setState(() {
                  _v = x;
                  _drag = true;
                })
            : null,
        onChangeEnd: (x) {
          _drag = false;
          widget.onSave(x.round());
        },
      ),
      if (widget.help != null) Text(widget.help!, style: Theme.of(c).textTheme.bodySmall),
      const SizedBox(height: 6),
    ]);
  }
}

class SettingsPage extends StatefulWidget {
  final AppState s;
  const SettingsPage(this.s, {super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url, _key, _id, _name, _apw, _ntfy, _tg;
  AppState get s => widget.s;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: s.serverUrl);
    _key = TextEditingController(text: s.apiKey);
    _id = TextEditingController(text: s.devId);
    _name = TextEditingController(text: s.cfgStr('name', 'Akar Siaga'));
    _apw = TextEditingController();
    _ntfy = TextEditingController(text: s.ntfy);
    _tg = TextEditingController(text: s.tg);
    s.loadSim();
    s.loadServerNotify().then((_) {
      if (mounted) {
        _ntfy.text = s.ntfy;
        _tg.text = s.tg;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_url, _key, _id, _name, _apw, _ntfy, _tg]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  void _syncFields() {
    _url.text = s.serverUrl;
    _key.text = s.apiKey;
    _id.text = s.devId;
  }

  Future<bool> _ask(String title, String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Lanjut')),
          ],
        ),
      ) ??
      false;

  Widget _sub(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t, style: Theme.of(c).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.primary)),
      );

  Widget _sw(String title, bool v, ValueChanged<bool>? f) =>
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(title), value: v, onChanged: f);

  Widget _row(BuildContext c, TextEditingController ctl, String label, String btn, VoidCallback onTap, {bool obscure = false, bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: TextField(controller: ctl, obscureText: obscure, decoration: dec(c, label: label))),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: enabled ? onTap : null, child: Text(btn)),
        ]),
      );

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    final en = s.connected;
    String hh(int v) => '${two(v)}:00';
    final modeHelp = {
      ConnMode.auto: 'Mencoba Wi-Fi (satu jaringan) lebih dulu, lalu otomatis pindah ke Cloud.',
      ConnMode.lan: 'Hanya lewat WiFi yang sama dengan alat. Tanpa internet.',
      ConnMode.cloud: 'Lewat internet dari mana saja, memakai server kamu.',
    }[s.mode]!;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Text('Setelan', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
      ),

      // ===================== ALAT =====================
      heading(c, 'Alat'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.eco, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.usingSim ? 'Alat uji (simulator)' : s.cfgStr('name', 'Akar Siaga'), style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  s.connected ? (s.online ? 'Online via ${netNames[s.via]}' : 'Alat offline') : s.status,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: s.connected
                  ? OutlinedButton(onPressed: s.disconnect, child: const Text('Putus'))
                  : FilledButton(onPressed: s.busy ? null : s.connect, child: const Text('Hubungkan')),
            ),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.tonal(onPressed: () => openSetup(c, s), child: const Text('Pasang alat baru'))),
          ]),
        ]),
      ),

      // ===================== KONEKSI =====================
      heading(c, 'Koneksi'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ConnMode>(
              showSelectedIcon: false,
              segments: [for (final m in ConnMode.values) ButtonSegment(value: m, label: Text(modeNames[m]!))],
              selected: {s.mode},
              onSelectionChanged: (v) => s.setMode(v.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(modeHelp, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const Divider(height: 28),
          Row(children: [
            Icon(s.serverReady ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: s.serverReady ? cs.primary : cs.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.serverReady
                    ? 'Server: ${s.serverHost}\n${s.devId.isEmpty ? 'Alat belum dipilih' : 'Alat: ${s.devId}'}'
                    : 'Server belum diatur. Dibutuhkan untuk Cloud dan notifikasi.',
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () async {
                  final m = await s.pasteCode();
                  if (mounted) {
                    setState(_syncFields);
                    _snack(m);
                  }
                },
                child: const Text('Tempel kode sambung'),
              ),
            ),
            if (s.serverReady) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final m = await s.autoSelectDevice();
                  if (mounted) {
                    setState(_syncFields);
                    _snack(m ?? 'Alat dipilih otomatis: ${s.devId}');
                  }
                },
                child: const Text('Cari alat'),
              ),
            ],
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Salin baris "Kode sambung" dari log server, lalu tekan Tempel. URL & kunci terisi sendiri.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          if (s.simEnabled) ...[
            const Divider(height: 24),
            _sw('Pakai alat uji (simulator)', s.usingSim, (v) async {
              final m = await s.setUseSim(v);
              if (m != null && mounted) _snack(m);
            }),
            Text('Alat virtual di server untuk mencoba semua fitur sebelum alat asli jadi.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ]),
      ),

      // ===================== NOTIFIKASI =====================
      heading(c, 'Notifikasi'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sw('Tangki air habis', s.nWater, (v) => s.setNotif(w: v)),
          _sw('Penyiraman selesai', s.nPump, (v) => s.setNotif(p: v)),
          _sw('Tanah kering / penyiraman kurang efektif', s.nDry, (v) => s.setNotif(d: v)),
          _sw('Alat offline / koneksi terputus', s.nConn, (v) => s.setNotif(c: v)),
          const Divider(height: 24),
          if (pushAvailable)
            _sw('Terima push di HP ini (walau aplikasi ditutup)', s.pushOn, (v) async {
              final m = await s.registerPush(enable: v);
              if (mounted) _snack(m);
            })
          else
            Row(children: [
              Icon(Icons.info_outline, size: 18, color: cs.outline),
              const SizedBox(width: 8),
              Expanded(child: Text('Push saat aplikasi ditutup butuh Firebase (belum aktif di build ini).', style: tt.bodySmall)),
            ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('Kirim tes'),
              onPressed: () async {
                final m = await s.testServerNotify();
                if (mounted) _snack(m);
              },
            ),
          ),
        ]),
      ),

      // ===================== TAMPILAN =====================
      heading(c, 'Tampilan'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Warna', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < palettes.length; i++)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: palettes[i].seed, radius: 8),
                label: Text(palettes[i].name),
                selected: s.paletteIdx == i,
                onSelected: (_) => s.setPalette(i),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Mode', style: tt.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Sistem')),
                ButtonSegment(value: 1, label: Text('Terang')),
                ButtonSegment(value: 2, label: Text('Gelap')),
              ],
              selected: {s.themeIdx},
              onSelectionChanged: (v) => s.setTheme(v.first),
            ),
          ),
        ]),
      ),

      // ===================== LANJUTAN =====================
      Panel(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            title: const Text('Pengaturan lanjutan', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Penyiraman, sensor, server manual, uji'),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!en) Text('Hubungkan ke alat untuk mengubah pengaturan alat.', style: tt.bodySmall),
              _sub(c, 'Penyiraman'),
              _SliderSet(title: 'Maks. penyiraman manual', unit: ' dtk', value: s.cfgInt('manrun', 30), min: 5, max: 60, enabled: en, help: 'Pompa mati otomatis setelah waktu ini.', onSave: (v) => s.setCfg('manrun', '$v')),
              _SliderSet(title: 'Batas siram otomatis per hari', value: s.cfgInt('maxday', 0), min: 0, max: 30, enabled: en, fmt: (v) => v == 0 ? 'Tanpa batas' : '$v kali', help: 'Mencegah kebanjiran bila sensor error.', onSave: (v) => s.setCfg('maxday', '$v')),
              _SliderSet(title: 'Lewati jadwal jika tanah ≥', unit: '%', value: s.cfgInt('skip', 85), min: 40, max: 100, enabled: en, onSave: (v) => s.setCfg('skip', '$v')),
              _SliderSet(title: 'Debit pompa', unit: ' ml/dtk', value: s.cfgInt('flow', 30), min: 1, max: 100, enabled: en, help: 'Ukur: pompa 10 detik ke gelas ukur, bagi 10.', onSave: (v) => s.setCfg('flow', '$v')),
              _SliderSet(title: 'Smart panas: aktif saat suhu ≥', value: s.cfgInt('hT', 0), min: 0, max: 45, enabled: en, fmt: (v) => v == 0 ? 'Mati' : '$v°C', help: 'Saat panas tanah cepat kering, batas siram dinaikkan.', onSave: (v) => s.setCfg('hT', '$v')),
              _SliderSet(title: 'Tambahan batas siram saat panas', unit: '%', value: s.cfgInt('hB', 10), min: 0, max: 30, enabled: en, onSave: (v) => s.setCfg('hB', '$v')),

              _sub(c, 'Alarm & sensor'),
              _sw('Buzzer alat', s.cfgInt('buzz', 1) == 1, en ? (v) => s.setCfg('buzz', v ? '1' : '0') : null),
              _SliderSet(title: 'Buzzer diam mulai jam', value: s.cfgInt('qs', 22), min: 0, max: 23, enabled: en, fmt: hh, onSave: (v) => s.setCfg('qs', '$v')),
              _SliderSet(title: 'Buzzer aktif lagi jam', value: s.cfgInt('qe', 6), min: 0, max: 23, enabled: en, fmt: hh, help: 'Jam mulai = jam aktif lagi berarti jam tenang mati.', onSave: (v) => s.setCfg('qe', '$v')),
              const Text('Float switch'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 0, label: Text('Normal')), ButtonSegment(value: 1, label: Text('Terbalik'))],
                selected: {s.cfgInt('fpol', 0)},
                onSelectionChanged: en ? (v) => s.setCfg('fpol', '${v.first}') : null,
              ),
              Padding(padding: const EdgeInsets.only(top: 4, bottom: 12), child: Text('Pilih "Terbalik" bila air ada tapi terbaca habis.', style: tt.bodySmall)),
              const Text('Sensor suhu'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 11, label: Text('DHT11')), ButtonSegment(value: 22, label: Text('DHT22'))],
                selected: {s.cfgInt('dht', 11)},
                onSelectionChanged: en ? (v) => s.setCfg('dht', '${v.first}') : null,
              ),
              Padding(padding: const EdgeInsets.only(top: 4, bottom: 12), child: Text('Berlaku setelah alat di-restart.', style: tt.bodySmall)),
              Text('Kalibrasi sensor tanah - nilai mentah: ${s.raw}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('Sensor di udara -> KERING. Celup ke air sampai garis batas -> BASAH.', style: tt.bodySmall)),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: en ? () => s.calibrate(true) : null, child: const Text('Set KERING'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: en ? () => s.calibrate(false) : null, child: const Text('Set BASAH'))),
              ]),

              _sub(c, 'Server (manual)'),
              TextField(controller: _url, keyboardType: TextInputType.url, decoration: dec(c, label: 'URL server', hint: 'https://akar.domainmu.com')),
              const SizedBox(height: 8),
              TextField(controller: _key, obscureText: true, decoration: dec(c, label: 'Kunci API')),
              const SizedBox(height: 8),
              TextField(controller: _id, decoration: dec(c, label: 'ID alat')),
              const SizedBox(height: 8),
              if (s.knownDevices.length > 1)
                Wrap(spacing: 8, children: [
                  for (final d in s.knownDevices)
                    ChoiceChip(
                      label: Text('${d.name.isEmpty ? d.id : d.name}${d.online ? '' : ' (offline)'}'),
                      selected: s.devId == d.id,
                      onSelected: (_) {
                        s.setDevId(d.id);
                        setState(_syncFields);
                      },
                    ),
                ]),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () {
                    s.saveNet(s.ssid, s.pass, _url.text.trim(), _key.text.trim(), _id.text.trim());
                    _snack('Tersimpan');
                  },
                  child: const Text('Simpan server'),
                ),
              ),

              _sub(c, 'Notifikasi tambahan'),
              TextField(controller: _ntfy, decoration: dec(c, label: 'Topik ntfy', helper: 'Pasang aplikasi ntfy, subscribe topik ini. Pakai nama sulit ditebak.'), onChanged: (v) => s.ntfy = v),
              const SizedBox(height: 8),
              TextField(controller: _tg, keyboardType: TextInputType.number, decoration: dec(c, label: 'Chat ID Telegram', helper: 'Kirim /start ke bot server dulu.'), onChanged: (v) => s.tg = v),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () async {
                    s.ntfy = _ntfy.text;
                    s.tg = _tg.text;
                    final m = await s.saveServerNotify();
                    if (mounted) _snack(m);
                  },
                  child: const Text('Simpan'),
                ),
              ),

              _sub(c, 'Alat'),
              _row(c, _name, 'Nama alat', 'Simpan', () {
                s.setCfg('name', _name.text.trim());
                _snack('Nama disimpan');
              }, enabled: en),
              _row(c, _apw, 'Sandi WiFi pemasangan baru (min. 8)', 'Simpan', () {
                if (_apw.text.length < 8) {
                  _snack('Sandi minimal 8 karakter');
                  return;
                }
                s.setCfg('apw', _apw.text);
                _apw.clear();
                _snack('Berlaku setelah alat restart. Catat sandi barunya!');
              }, obscure: true, enabled: en),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Restart'),
                    onPressed: en ? () async { if (await _ask('Restart alat?', 'Koneksi terputus sebentar.')) await s.restartDevice(); } : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Reset'),
                    onPressed: en
                        ? () async {
                            if (await _ask('Reset alat?', 'Semua pengaturan, jadwal, WiFi, dan server di alat dihapus. Alat kembali ke mode pemasangan.')) await s.resetDevice();
                          }
                        : null,
                  ),
                ),
              ]),

              if (s.simEnabled) ...[
                _sub(c, 'Uji (simulator)'),
                Text('Picu kejadian pada alat virtual untuk mencoba notifikasi, riwayat, dan AI.', style: tt.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final e in const {
                    'Tanah kering': 'dry',
                    'Tanah basah': 'wet',
                    'Air habis': 'tank_empty',
                    'Isi tangki': 'refill',
                    'Selang bocor': 'ineffective',
                    'Alat offline': 'offline',
                    'Reset': 'reset',
                  }.entries)
                    ActionChip(
                      label: Text(e.key),
                      onPressed: () async {
                        final m = await s.simScenario(e.value);
                        if (mounted) _snack(m);
                      },
                    ),
                ]),
              ],

              _sub(c, 'Data'),
              OutlinedButton.icon(
                icon: const Icon(Icons.history_toggle_off),
                label: const Text('Hapus riwayat di HP'),
                onPressed: () async {
                  if (await _ask('Hapus riwayat?', 'Grafik dan daftar kejadian di HP dihapus.')) s.clearHistory();
                },
              ),
            ],
          ),
        ),
      ),
      Center(child: Text('Akar Siaga v5.0 - Persimanu 2 Jawa Tengah', style: tt.bodySmall)),
    ]);
  }
}

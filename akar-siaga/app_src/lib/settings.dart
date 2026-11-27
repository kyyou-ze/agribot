import 'package:flutter/material.dart';
import 'push/push_service.dart';
import 'state.dart';
import 'widgets.dart';

const _pad = EdgeInsets.fromLTRB(16, 12, 16, 24);

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
  late final TextEditingController _ssid, _pass, _url, _key, _id, _host, _name, _apw, _ntfy, _tg;

  @override
  void initState() {
    super.initState();
    final s = widget.s;
    _ssid = TextEditingController(text: s.ssid);
    _pass = TextEditingController(text: s.pass);
    _url = TextEditingController(text: s.serverUrl);
    _key = TextEditingController(text: s.apiKey);
    _id = TextEditingController(text: s.devId);
    _host = TextEditingController(text: s.host);
    _name = TextEditingController(text: s.cfgStr('name', 'Akar Siaga'));
    _apw = TextEditingController();
    _ntfy = TextEditingController(text: s.ntfy);
    _tg = TextEditingController(text: s.tg);
    s.loadServerNotify().then((_) {
      if (mounted) {
        _ntfy.text = s.ntfy;
        _tg.text = s.tg;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_ssid, _pass, _url, _key, _id, _host, _name, _apw, _ntfy, _tg]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _saveNet() => widget.s.saveNet(_ssid.text.trim(), _pass.text, _url.text.trim(), _key.text.trim(), _id.text.trim(), _host.text.trim());

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

  Widget _mode(Net n, String sub) {
    final s = widget.s, cs = Theme.of(context).colorScheme;
    final sel = s.net == n;
    return Panel(
      onTap: () => s.setNet(n),
      border: sel ? cs.primary : null,
      color: sel ? cs.primaryContainer.withValues(alpha: .4) : null,
      child: Row(children: [
        Icon(netIcon(n), size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(netNames[n]!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(sub, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (sel) Icon(Icons.check_circle, color: cs.primary),
      ]),
    );
  }

  Widget _row(TextEditingController c, String label, String btn, VoidCallback onTap, {bool obscure = false, bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: TextField(controller: c, obscureText: obscure, decoration: InputDecoration(labelText: label))),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: enabled ? onTap : null, child: Text(btn)),
        ]),
      );

  @override
  Widget build(BuildContext c) {
    final s = widget.s, cs = Theme.of(c).colorScheme, tt = Theme.of(c).textTheme;
    final en = s.connected;
    String hh(int v) => '${two(v)}:00';
    return ListView(padding: _pad, children: [
      // ===================== KONEKSI =====================
      heading(c, 'Koneksi HP ke alat'),
      _mode(Net.ap, 'Alat membuat WiFi sendiri (AkarSiaga-XXXX, sandi akarsiaga123). Tanpa router & internet.'),
      _mode(Net.sta, 'Alat dan HP di WiFi yang sama (router/hotspot HP lain).'),
      _mode(Net.cloud, 'Lewat internet dari mana saja, via server kamu. Notifikasi push & riwayat 24 jam.'),
      if (s.net == Net.ap)
        Panel(
          color: cs.tertiaryContainer.withValues(alpha: .5),
          child: const Text('Sambungkan HP ke WiFi "AkarSiaga-XXXX", pilih "tetap terhubung" bila diminta, matikan data seluler, lalu tekan Hubungkan.'),
        ),
      Panel(
        child: Row(children: [
          Expanded(child: Text(s.status, style: tt.bodyMedium)),
          const SizedBox(width: 8),
          s.connected
              ? OutlinedButton(onPressed: s.disconnect, child: const Text('Putus'))
              : FilledButton(onPressed: s.busy ? null : s.connect, child: const Text('Hubungkan')),
        ]),
      ),
      heading(c, 'Jaringan & server'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Isi lalu simpan. Mode Cloud memakai URL, kunci, dan ID di bawah.', style: tt.bodySmall),
          const SizedBox(height: 10),
          TextField(controller: _ssid, decoration: const InputDecoration(labelText: 'Nama WiFi (SSID) - 2,4 GHz')),
          const SizedBox(height: 10),
          TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Sandi WiFi')),
          const SizedBox(height: 10),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL server (opsional)', hintText: 'https://akarsiaga.domainmu.com'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'Kunci API server')),
          const SizedBox(height: 10),
          TextField(controller: _id, decoration: const InputDecoration(labelText: 'ID alat', hintText: 'terisi otomatis saat terhubung langsung')),
          const SizedBox(height: 10),
          TextField(controller: _host, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IP alat manual (opsional, mode Router)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _saveNet();
                  _snack('Tersimpan di aplikasi');
                },
                child: const Text('Simpan'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: en
                    ? () async {
                        _saveNet();
                        if (s.ssid.isEmpty) {
                          _snack('Isi nama WiFi (SSID) dulu');
                          return;
                        }
                        if (await _ask('Kirim ke alat?', 'Alat akan restart dan masuk ke WiFi "${s.ssid}"${s.serverReady ? ' dengan sinkron ke server' : ''}.')) {
                          await s.provision();
                        }
                      }
                    : null,
                child: const Text('Kirim ke alat'),
              ),
            ),
          ]),
          if (en && s.devNet == 'S')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  if (await _ask('Kembali ke Hotspot?', 'Alat akan restart dan membuat WiFi sendiri.')) await s.toHotspot();
                },
                child: const Text('Kembalikan alat ke Hotspot'),
              ),
            ),
          if (!en) Text('Tombol "Kirim ke alat" aktif setelah HP terhubung ke alat.', style: tt.bodySmall),
          Text('Cadangan: tahan tombol di alat >3 detik untuk ganti Hotspot <-> Router (1 bip = Hotspot, 2 = Router).', style: tt.bodySmall),
        ]),
      ),

      // ===================== PENYIRAMAN =====================
      heading(c, 'Penyiraman'),
      if (!en) Text('Hubungkan ke alat untuk mengubah pengaturan di bawah.', style: tt.bodySmall),
      Panel(
        child: Column(children: [
          _SliderSet(
            title: 'Maks. penyiraman manual', unit: ' dtk', value: s.cfgInt('manrun', 30), min: 5, max: 60, enabled: en,
            help: 'Pompa mati otomatis setelah waktu ini bila lupa dimatikan.',
            onSave: (v) => s.setCfg('manrun', '$v'),
          ),
          _SliderSet(
            title: 'Batas siram otomatis per hari', value: s.cfgInt('maxday', 0), min: 0, max: 30, enabled: en,
            fmt: (v) => v == 0 ? 'Tanpa batas' : '$v kali',
            help: 'Mencegah tanaman kebanjiran bila sensor error.',
            onSave: (v) => s.setCfg('maxday', '$v'),
          ),
          _SliderSet(
            title: 'Lewati jadwal jika tanah ≥', unit: '%', value: s.cfgInt('skip', 85), min: 40, max: 100, enabled: en,
            onSave: (v) => s.setCfg('skip', '$v'),
          ),
          _SliderSet(
            title: 'Debit pompa', unit: ' ml/dtk', value: s.cfgInt('flow', 30), min: 1, max: 100, enabled: en,
            help: 'Ukur: pompa 10 detik ke gelas ukur, bagi 10. Untuk estimasi pemakaian air.',
            onSave: (v) => s.setCfg('flow', '$v'),
          ),
          _SliderSet(
            title: 'Smart panas: aktif saat suhu ≥', value: s.cfgInt('hT', 0), min: 0, max: 45, enabled: en,
            fmt: (v) => v == 0 ? 'Mati' : '$v°C',
            help: 'Saat panas, tanah cepat kering, jadi batas siram dinaikkan.',
            onSave: (v) => s.setCfg('hT', '$v'),
          ),
          _SliderSet(
            title: 'Tambahan batas siram saat panas', unit: '%', value: s.cfgInt('hB', 10), min: 0, max: 30, enabled: en,
            onSave: (v) => s.setCfg('hB', '$v'),
          ),
          if (en) Align(alignment: Alignment.centerLeft, child: Text('Batas siram efektif sekarang: ${s.effMin}%', style: tt.bodySmall)),
        ]),
      ),

      // ===================== ALARM & SENSOR =====================
      heading(c, 'Alarm & sensor'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Buzzer alat'),
            value: s.cfgInt('buzz', 1) == 1,
            onChanged: en ? (v) => s.setCfg('buzz', v ? '1' : '0') : null,
          ),
          _SliderSet(
            title: 'Buzzer diam mulai jam', value: s.cfgInt('qs', 22), min: 0, max: 23, enabled: en, fmt: hh,
            onSave: (v) => s.setCfg('qs', '$v'),
          ),
          _SliderSet(
            title: 'Buzzer aktif lagi jam', value: s.cfgInt('qe', 6), min: 0, max: 23, enabled: en, fmt: hh,
            help: 'Jam mulai = jam aktif lagi berarti jam tenang dimatikan. Butuh jam alat sinkron.',
            onSave: (v) => s.setCfg('qe', '$v'),
          ),
          const Text('Float switch'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Normal')),
              ButtonSegment(value: 1, label: Text('Terbalik')),
            ],
            selected: {s.cfgInt('fpol', 0)},
            onSelectionChanged: en ? (v) => s.setCfg('fpol', '${v.first}') : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text('Pilih "Terbalik" bila air ada tapi terbaca habis.', style: tt.bodySmall),
          ),
          const Text('Sensor suhu'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 11, label: Text('DHT11')), ButtonSegment(value: 22, label: Text('DHT22'))],
            selected: {s.cfgInt('dht', 11)},
            onSelectionChanged: en ? (v) => s.setCfg('dht', '${v.first}') : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text('Berlaku setelah alat di-restart.', style: tt.bodySmall),
          ),
          const Divider(),
          Text('Kalibrasi sensor tanah - nilai mentah: ${s.raw}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Sensor di udara -> KERING. Celup ke air sampai garis batas -> BASAH.', style: tt.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: en ? () => s.calibrate(true) : null, child: const Text('Set KERING'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: en ? () => s.calibrate(false) : null, child: const Text('Set BASAH'))),
          ]),
        ]),
      ),

      // ===================== NOTIFIKASI =====================
      heading(c, 'Notifikasi di HP'),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          SwitchListTile(title: const Text('Tangki air habis'), value: s.nWater, onChanged: (v) => s.setNotif(w: v)),
          SwitchListTile(title: const Text('Penyiraman selesai'), value: s.nPump, onChanged: (v) => s.setNotif(p: v)),
          SwitchListTile(title: const Text('Tanah kering (mode manual)'), value: s.nDry, onChanged: (v) => s.setNotif(d: v)),
          SwitchListTile(title: const Text('Koneksi terputus'), value: s.nConn, onChanged: (v) => s.setNotif(c: v)),
        ]),
      ),
      Text('Muncul selama aplikasi masih berjalan. Untuk notifikasi saat aplikasi ditutup, pakai push dari server di bawah.', style: tt.bodySmall),
      heading(c, 'Notifikasi push dari server'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Real-time walau aplikasi ditutup. Butuh server (URL, kunci, ID alat terisi). Pilih salah satu atau keduanya:', style: tt.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Icon(pushAvailable ? Icons.check_circle : Icons.info_outline, size: 18, color: pushAvailable ? Colors.green : cs.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pushAvailable ? 'Firebase aktif di build ini: push masuk langsung ke aplikasi.' : 'Build ini tanpa Firebase. Pakai ntfy atau Telegram di bawah.',
                style: tt.bodySmall,
              ),
            ),
          ]),
          if (pushAvailable)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Terima push di HP ini'),
              value: s.pushOn,
              onChanged: (v) async {
                final m = await s.registerPush(enable: v);
                if (mounted) _snack(m);
              },
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _ntfy,
            decoration: const InputDecoration(labelText: 'Topik ntfy', helperText: 'Pasang app "ntfy", lalu subscribe topik ini. Pakai nama yang sulit ditebak.'),
            onChanged: (v) => s.ntfy = v,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tg,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Chat ID Telegram', helperText: 'Kirim /start ke bot server dulu. Cek ID lewat @userinfobot.'),
            onChanged: (v) => s.tg = v,
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tangki air habis'), value: s.sw, onChanged: (v) => setState(() => s.sw = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Penyiraman selesai'), value: s.sp, onChanged: (v) => setState(() => s.sp = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tanah kering & penyiraman kurang efektif'), value: s.sd, onChanged: (v) => setState(() => s.sd = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Alat offline / online kembali'), value: s.so, onChanged: (v) => setState(() => s.so = v)),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  s.ntfy = _ntfy.text;
                  s.tg = _tg.text;
                  final m = await s.saveServerNotify();
                  if (mounted) _snack(m);
                },
                child: const Text('Simpan ke server'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final m = await s.testServerNotify();
                if (mounted) _snack(m);
              },
              child: const Text('Kirim tes'),
            ),
          ]),
        ]),
      ),

      // ===================== ALAT =====================
      heading(c, 'Alat'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(_name, 'Nama alat', 'Simpan', () {
            s.setCfg('name', _name.text.trim());
            _snack('Nama disimpan');
          }, enabled: en),
          _row(_apw, 'Sandi Hotspot baru (min. 8 karakter)', 'Simpan', () {
            if (_apw.text.length < 8) {
              _snack('Sandi minimal 8 karakter');
              return;
            }
            s.setCfg('apw', _apw.text);
            _apw.clear();
            _snack('Sandi Hotspot baru berlaku setelah alat restart');
          }, obscure: true, enabled: en),
          if (en) Text('ID alat: ${s.cfgStr('id', '-')}', style: tt.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: en
                    ? () async {
                        if (await _ask('Restart alat?', 'Alat restart dan koneksi terputus sebentar.')) await s.restartDevice();
                      }
                    : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restart'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                onPressed: en
                    ? () async {
                        if (await _ask('Reset pengaturan alat?', 'Semua pengaturan, jadwal, WiFi, dan server di alat dihapus. Alat kembali ke mode Hotspot.')) {
                          await s.resetDevice();
                        }
                      }
                    : null,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Reset'),
              ),
            ),
          ]),
        ]),
      ),

      // ===================== APLIKASI =====================
      heading(c, 'Aplikasi'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tema'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Sistem')),
              ButtonSegment(value: 1, label: Text('Terang')),
              ButtonSegment(value: 2, label: Text('Gelap')),
            ],
            selected: {s.themeIdx},
            onSelectionChanged: (v) => s.setTheme(v.first),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              if (await _ask('Hapus riwayat?', 'Grafik dan daftar kejadian di HP dihapus.')) s.clearHistory();
            },
            icon: const Icon(Icons.history_toggle_off),
            label: const Text('Hapus riwayat di HP'),
          ),
        ]),
      ),
      Center(child: Text('Akar Siaga v4.0 - Persimanu 2 Jawa Tengah', style: tt.bodySmall)),
    ]);
  }
}

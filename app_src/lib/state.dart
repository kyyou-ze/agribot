import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai.dart';
import 'link.dart';
import 'push/push_service.dart';

/// Jalur yang sedang dipakai.
enum Net { lan, cloud }

/// Pilihan pengguna: otomatis = coba Wi-Fi dulu, lalu Cloud.
enum ConnMode { auto, lan, cloud }

const netNames = {Net.lan: 'Wi-Fi', Net.cloud: 'Cloud'};
const modeNames = {ConnMode.auto: 'Otomatis', ConnMode.lan: 'Wi-Fi', ConnMode.cloud: 'Cloud'};

/// Alat baru / belum punya WiFi menyalakan hotspot sementara untuk pemasangan.
const setupHost = '192.168.4.1';
const setupPassword = 'akarsiaga123';

class Preset {
  final String name, emoji, tip;
  final int min, run, wait; // batas kering (%), lama siram (dtk), jeda (dtk)
  const Preset(this.name, this.emoji, this.min, this.run, this.wait, this.tip);
}

// Nilai awal - sesuaikan dengan debit pompa & ukuran pot saat uji.
// Emoji dipilih yang didukung semua Android (lidah buaya memakai kaktus; 🪴 hanya ada di Android 11+).
const presets = [
  Preset('Cabai', '🌶', 55, 5, 90, 'Suka tanah lembab tapi tidak tergenang. Hindari daun basah.'),
  Preset('Tomat', '🍅', 55, 6, 90, 'Kelembaban stabil mencegah buah pecah dan busuk ujung buah.'),
  Preset('Kangkung', '🥬', 70, 6, 60, 'Haus air: tanah harus selalu lembab.'),
  Preset('Selada', '🥗', 65, 4, 60, 'Akar dangkal: siram sering dengan volume kecil.'),
  Preset('Bayam', '🌿', 60, 4, 60, 'Jaga tanah lembab merata, jangan sampai kering total.'),
  Preset('Kemangi', '🍃', 55, 4, 90, 'Tanah lembab dengan drainase baik agar akar tidak busuk.'),
  Preset('Lidah Buaya', '🌵', 25, 4, 180, 'Sukulen: biarkan kering di antara penyiraman.'),
];

String presetEmoji(String n) => presets.firstWhere((p) => p.name == n, orElse: () => presets.first).emoji;

class Sched {
  bool en;
  int h, m, dur, days; // days: bit0=Minggu ... bit6=Sabtu
  Sched(this.en, this.h, this.m, this.dur, this.days);
}

class Sample {
  final int t, soil, hum;
  final double temp;
  Sample(this.t, this.soil, this.temp, this.hum);
}

class Ev {
  final int t, kind; // kind: 0 info, 1 siram, 2 peringatan
  final String text;
  Ev(this.t, this.text, this.kind);
}

/// Alat yang dikenal server.
class DevInfo {
  final String id, name;
  final bool online, sim;
  DevInfo(this.id, this.name, this.online, this.sim);
}

int _i(String s, int d) => int.tryParse(s.trim()) ?? d;
int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  final _np = FlutterLocalNotificationsPlugin();

  // ---- pengaturan pengguna ----
  ConnMode mode = ConnMode.auto;
  String ssid = '', pass = '', plant = '', serverUrl = '', apiKey = '', devId = '', ntfy = '', tg = '';
  bool nWater = true, nPump = true, nConn = true, nDry = true; // satu set: dipakai di HP & server
  int themeIdx = 0, paletteIdx = 0;
  bool pushOn = true;
  String? fcmToken;

  // ---- koneksi ----
  Net via = Net.lan;
  Link? _link;
  StreamSubscription<String>? _ls;
  Timer? _retry, _hist, _notifT;
  bool connected = false, busy = false, online = true;
  bool _got = false, _want = false, _cancelWait = false;
  int _retries = 0, _nid = 1, _lastSample = 0, _lastDry = 0;
  String status = 'Belum terhubung', _lastClip = '', _realId = '';
  ConnMode _modeBefore = ConnMode.auto;

  // ---- data alat ----
  int soil = 0, raw = 0, hum = 0, minSoil = 55, run = 5, wait = 60, remain = 0, effMin = 55, offAge = 0, cloudState = 0;
  double temp = -99;
  bool water = true, pump = false, auto = true, timeOk = false;
  String devNet = ''; // 'A' = alat masih di mode pemasangan, 'S' = sudah di WiFi rumah
  final cfg = <String, String>{};
  final sched = List.generate(4, (i) => Sched(false, 6 + i * 4, 0, 5, 127));
  final samples = <Sample>[];
  final events = <Ev>[];
  final aiMsgs = <AiMsg>[];
  List<DevInfo> knownDevices = [];

  // ---- mode uji (simulator di server) ----
  bool simEnabled = false;
  String simId = '';

  String cfgStr(String k, [String d = '']) => (cfg[k] ?? '').isEmpty ? d : cfg[k]!;
  int cfgInt(String k, int d) => int.tryParse(cfg[k] ?? '') ?? d;
  bool get serverReady => normUrl(serverUrl).isNotEmpty && apiKey.isNotEmpty;
  bool get hasPaired => ssid.isNotEmpty || serverReady || devId.isNotEmpty;
  bool get needsSetup => connected && devNet == 'A';
  bool get usingSim => simEnabled && devId.isNotEmpty && devId == simId;
  String get serverHost => Uri.tryParse(normUrl(serverUrl))?.host ?? serverUrl;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    mode = ConnMode.values[(_p.getInt('mode') ?? 0) % 3];
    _modeBefore = ConnMode.values[(_p.getInt('modeBefore') ?? 0) % 3];
    ssid = _p.getString('ssid') ?? '';
    pass = _p.getString('pass') ?? '';
    plant = _p.getString('plant') ?? '';
    serverUrl = _p.getString('srv') ?? '';
    apiKey = _p.getString('key') ?? '';
    devId = _p.getString('did') ?? '';
    _realId = _p.getString('realId') ?? '';
    ntfy = _p.getString('ntfy') ?? '';
    tg = _p.getString('tg') ?? '';
    themeIdx = _p.getInt('theme') ?? 0;
    paletteIdx = _p.getInt('pal') ?? 0;
    nWater = _p.getBool('nW') ?? true;
    nPump = _p.getBool('nP') ?? true;
    nConn = _p.getBool('nC') ?? true;
    nDry = _p.getBool('nD') ?? true;
    pushOn = _p.getBool('pushOn') ?? true;
    try {
      for (final e in jsonDecode(_p.getString('hist') ?? '[]') as List) {
        samples.add(Sample(e[0], e[1], (e[2] as num).toDouble(), e[3]));
      }
      for (final e in jsonDecode(_p.getString('ev') ?? '[]') as List) {
        events.add(Ev(e[0], e[1], e[2]));
      }
    } catch (_) {}
    await _np.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    Permission.notification.request();
    await _np
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel('akarsiaga_push', 'Notifikasi Akar Siaga (push)',
            importance: Importance.high));
    _initPush();
    loadSim();
  }

  // =================== koneksi otomatis ===================
  Future<void> connect() async {
    _want = true;
    _retries = 0;
    await _connect();
  }

  void _attach(Link l, Net v) {
    _link = l;
    via = v;
    _ls = l.lines.listen(_onLine);
  }

  Future<void> _detach(Link l) async {
    await _ls?.cancel();
    await l.close();
    _link = null;
  }

  /// Otomatis: coba Wi-Fi (alat ditemukan di jaringan yang sama), kalau tidak ada pindah ke Cloud.
  Future<void> _openLink() async {
    String lanMsg = '';
    if (mode != ConnMode.cloud) {
      final h = await discoverHost();
      if (h != null) {
        final l = LocalLink(h, _dropped);
        _attach(l, Net.lan);
        try {
          await l.open();
          return;
        } catch (e) {
          await _detach(l);
          lanMsg = e is String ? e : 'Gagal terhubung lewat Wi-Fi.';
        }
      } else {
        lanMsg = 'Alat tidak ditemukan di Wi-Fi ini.';
      }
      if (mode == ConnMode.lan) throw lanMsg;
    }
    if (!serverReady || devId.isEmpty) {
      throw mode == ConnMode.cloud
          ? 'Cloud belum diatur. Tempel kode sambung di Setelan.'
          : '$lanMsg Pasang alat baru, atau atur Cloud di Setelan.';
    }
    final l = CloudLink(CloudApi(normUrl(serverUrl), apiKey), devId, _dropped);
    _attach(l, Net.cloud);
    try {
      await l.open();
    } catch (_) {
      await _detach(l);
      rethrow;
    }
  }

  Future<void> _connect() async {
    if (busy || connected) return;
    busy = true;
    status = mode == ConnMode.cloud ? 'Menghubungi server...' : 'Mencari alat...';
    notifyListeners();
    try {
      await _openLink();
      connected = true;
      _retries = 0;
      online = true;
      status = 'Terhubung';
      _ev('Terhubung via ${netNames[via]}', 0);
      registerPush();
      if (via == Net.cloud) {
        _loadCloud();
        _hist = Timer.periodic(const Duration(seconds: 60), (_) => _loadCloud());
      }
      final n = DateTime.now();
      await send('Z:${n.millisecondsSinceEpoch ~/ 1000},${n.timeZoneOffset.inSeconds}');
    } catch (e) {
      status = e is String ? e : 'Gagal terhubung: $e';
      _scheduleRetry();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _scheduleRetry() {
    if (!_want || _retries >= 5) return;
    _retries++;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), _connect);
  }

  void _dropped() {
    if (!connected) return;
    connected = false;
    _got = false;
    _hist?.cancel();
    status = 'Koneksi terputus - mencoba lagi...';
    _ev('Koneksi terputus', 2);
    _notify('Koneksi terputus', 'Akar Siaga tidak lagi terhubung dengan HP.', nConn);
    _ls?.cancel();
    _link?.close();
    _link = null;
    _scheduleRetry();
    notifyListeners();
  }

  Future<void> disconnect({bool quiet = false}) async {
    _want = false;
    _retry?.cancel();
    _hist?.cancel();
    await _ls?.cancel();
    await _link?.close();
    _link = null;
    if (connected && !quiet) _ev('Diputus oleh pengguna', 0);
    connected = false;
    _got = false;
    online = true;
    status = 'Belum terhubung';
    notifyListeners();
  }

  Future<void> send(String c) async {
    try {
      await _link?.send(c);
    } catch (_) {}
  }

  Future<void> _loadCloud() async {
    final l = _link;
    if (l is! CloudLink) return;
    try {
      final j = await l.api.getJson('/api/app/history', {'id': devId, 'hours': '24'});
      samples
        ..clear()
        ..addAll((j['s'] as List).map((e) => Sample(e[0], e[1], (e[2] as num).toDouble(), e[3])));
      events
        ..clear()
        ..addAll((j['e'] as List).map((e) => Ev(e[0], e[1], e[2])));
      notifyListeners();
    } catch (_) {}
  }

  void setMode(ConnMode m) {
    mode = m;
    _p.setInt('mode', m.index);
    notifyListeners();
    if (connected) {
      disconnect(quiet: true).then((_) => connect());
    }
  }

  // =================== pemasangan alat baru ===================
  /// Apakah alat (mode pemasangan) terjangkau di 192.168.4.1? Sekalian membaca ID alat.
  Future<bool> probeSetup() async {
    final t = await fetchLocalAll(setupHost);
    if (t == null) return false;
    for (final l in t.split('\n')) {
      if (l.startsWith('C:')) _parseCfg(l.substring(2));
    }
    notifyListeners();
    return true;
  }

  /// Kirim WiFi rumah (+ server bila sudah diatur) ke alat, lalu alat restart ke WiFi itu.
  Future<String?> provisionFromWizard(String s, String pw) async {
    ssid = s;
    pass = pw;
    _p.setString('ssid', s);
    _p.setString('pass', pw);
    final cloud = serverReady;
    final cmds = [
      'W:$s\t$pw',
      if (cloud) 'V:${normUrl(serverUrl)}\t$apiKey',
      'C:cloud=${cloud ? 1 : 0}',
      'N:S',
    ];
    for (final c in cmds) {
      if (!await sendLocal(setupHost, c)) {
        return 'Gagal mengirim ke alat. Pastikan HP masih tersambung ke WiFi "AkarSiaga-XXXX".';
      }
    }
    return null;
  }

  void cancelWait() => _cancelWait = true;

  /// Setelah alat dipasang: coba terhubung berulang sampai alat muncul di WiFi rumah / Cloud.
  Future<bool> waitForDevice({int seconds = 110}) async {
    _cancelWait = false;
    await disconnect(quiet: true);
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end) && !_cancelWait) {
      await _connect();
      if (connected && devNet == 'S') {
        _want = true;
        _retries = 0;
        return true;
      }
      if (connected) await disconnect(quiet: true); // masih mode pemasangan / belum siap
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  // =================== kode sambung & alat ===================
  /// Kode sambung "AKS1.<base64>" berisi URL + kunci server. Dibuat server (lihat log server).
  String? applyPairCode(String code) {
    code = code.trim();
    if (!code.startsWith('AKS1.')) return 'Kode tidak dikenali. Salin ulang baris "Kode sambung" dari log server.';
    try {
      final j = jsonDecode(utf8.decode(base64Url.decode(base64.normalize(code.substring(5))))) as Map<String, dynamic>;
      final u = (j['u'] ?? '').toString(), k = (j['k'] ?? '').toString();
      if (u.isEmpty || k.isEmpty) return 'Kode tidak lengkap.';
      serverUrl = u;
      apiKey = k;
      _p.setString('srv', u);
      _p.setString('key', k);
      notifyListeners();
      loadSim();
      return null;
    } catch (_) {
      return 'Kode rusak. Salin ulang dari log server.';
    }
  }

  /// Kode baru di clipboard (sekali saja per kode) - untuk dialog "pakai kode ini?".
  Future<String?> clipboardCode() async {
    try {
      final t = ((await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '').trim();
      if (t.startsWith('AKS1.') && t != _lastClip) {
        _lastClip = t;
        return t;
      }
    } catch (_) {}
    return null;
  }

  /// Tombol "Tempel kode sambung": baca clipboard, pakai, lalu pilih alat otomatis.
  Future<String> pasteCode() async {
    String t = '';
    try {
      t = ((await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '').trim();
    } catch (_) {}
    if (!t.startsWith('AKS1.')) return 'Clipboard tidak berisi kode sambung. Salin dulu dari log server.';
    final err = applyPairCode(t);
    if (err != null) return err;
    final pick = await autoSelectDevice();
    return pick ?? 'Server terhubung. Alat dipilih otomatis ($devId).';
  }

  CloudApi? _srv() => serverReady ? CloudApi(normUrl(serverUrl), apiKey) : null;
  CloudApi? _api() => (serverReady && devId.isNotEmpty) ? CloudApi(normUrl(serverUrl), apiKey) : null;

  Future<List<DevInfo>> fetchDevices() async {
    final a = _srv();
    if (a == null) return [];
    final j = jsonDecode(await a.getText('/api/app/devices', {})) as List;
    return [for (final e in j) DevInfo(e['id'].toString(), (e['name'] ?? '').toString(), e['online'] == true, e['sim'] == true)];
  }

  /// Pilih alat otomatis dari daftar server. Mengembalikan pesan bila belum bisa memilih (null = berhasil).
  Future<String?> autoSelectDevice() async {
    try {
      final all = await fetchDevices();
      knownDevices = all;
      final real = all.where((d) => !d.sim).toList();
      final pool = real.isNotEmpty ? real : all; // alat asli diutamakan dibanding simulator
      if (pool.isEmpty) {
        notifyListeners();
        return 'Belum ada alat yang pernah tersambung ke server.';
      }
      final online = pool.where((d) => d.online).toList();
      final pick = online.length == 1 ? online.first : (pool.length == 1 ? pool.first : null);
      if (pick == null) {
        notifyListeners();
        return 'Ada ${pool.length} alat. Pilih salah satu di Setelan > Pengaturan lanjutan > Server.';
      }
      setDevId(pick.id);
      return null;
    } catch (e) {
      return 'Server tidak bisa dihubungi: ${e is ApiError ? e.message : 'periksa URL dan kunci'}';
    }
  }

  void setDevId(String id) {
    devId = id;
    _p.setString('did', id);
    notifyListeners();
  }

  void saveNet(String s, String pw, String url, String key, String id) {
    ssid = s;
    pass = pw;
    serverUrl = url;
    apiKey = key;
    devId = id;
    _p.setString('ssid', s);
    _p.setString('pass', pw);
    _p.setString('srv', url);
    _p.setString('key', key);
    _p.setString('did', id);
    notifyListeners();
    loadSim();
    registerPush();
  }

  // =================== mode uji (simulator) ===================
  Future<void> loadSim() async {
    final a = _srv();
    if (a == null) return;
    try {
      final j = await a.getJson('/api/sim/status', {});
      simEnabled = j['enabled'] == true;
      simId = (j['id'] ?? '').toString();
      notifyListeners();
    } catch (_) {}
  }

  Future<String?> setUseSim(bool on) async {
    if (on) {
      await loadSim();
      if (!simEnabled) return 'Mode uji belum aktif di server (set SIMULATOR=1).';
      if (devId != simId) {
        _realId = devId;
        _p.setString('realId', devId);
      }
      _modeBefore = mode;
      _p.setInt('modeBefore', mode.index);
      devId = simId;
      mode = ConnMode.cloud;
    } else {
      devId = _realId;
      mode = _modeBefore;
    }
    _p.setString('did', devId);
    _p.setInt('mode', mode.index);
    await disconnect(quiet: true);
    notifyListeners();
    if (devId.isNotEmpty) connect();
    return null;
  }

  Future<String> simScenario(String name) async {
    final a = _srv();
    if (a == null) return 'Server belum diatur.';
    try {
      await a.post('/api/sim/scenario', {'name': name}, '');
      return 'Skenario dijalankan. Perubahan muncul dalam beberapa detik.';
    } catch (e) {
      return 'Gagal: ${e is ApiError ? e.message : e}';
    }
  }

  // =================== data masuk ===================
  void _parseCfg(String body) {
    for (final kv in body.split(';')) {
      final i = kv.indexOf('=');
      if (i > 0) cfg[kv.substring(0, i)] = kv.substring(i + 1);
    }
    final id = cfg['id'] ?? '';
    if (id.isNotEmpty && id != devId && !usingSim) {
      devId = id;
      _p.setString('did', id);
    }
  }

  void _onLine(String l) {
    l = l.trim();
    if (l.startsWith('S:')) {
      final p = l.substring(2).split(',');
      final i = p.length == 6 ? _i(p[0], -1) : -1;
      if (i >= 0 && i < 4) {
        sched[i] = Sched(p[1] == '1', _i(p[2], 6), _i(p[3], 0), _i(p[4], 5), _i(p[5], 127));
        notifyListeners();
      }
      return;
    }
    if (l.startsWith('C:')) {
      _parseCfg(l.substring(2));
      notifyListeners();
      return;
    }
    if (l.startsWith('O:')) {
      final p = l.substring(2).split(',');
      online = p[0] == '1';
      offAge = p.length > 1 ? _i(p[1], 0) : 0;
      notifyListeners();
      return;
    }
    final p = l.split(',');
    if (p.length < 10) return;
    final ow = water, op = pump;
    soil = _i(p[0], soil);
    raw = _i(p[1], raw);
    temp = double.tryParse(p[2]) ?? temp;
    hum = _i(p[3], hum);
    water = p[4] == '1';
    pump = p[5] == '1';
    auto = p[6] == 'A';
    minSoil = _i(p[7], minSoil);
    run = _i(p[8], run);
    wait = _i(p[9], wait);
    if (p.length >= 13) {
      devNet = p[10];
      timeOk = p[11] == '1';
      remain = _i(p[12], 0);
    }
    if (p.length >= 15) {
      effMin = _i(p[13], minSoil);
      cloudState = _i(p[14], 0);
    }
    _track(ow, op);
    _got = true;
    notifyListeners();
  }

  void _track(bool ow, bool op) {
    if (!_got) {
      if (!water) {
        _ev('Tangki air habis', 2);
        _notify('Tangki air habis', 'Isi tangki agar penyiraman bisa berjalan.', nWater);
      }
    } else {
      if (ow && !water) {
        _ev('Tangki air habis', 2);
        _notify('Tangki air habis', 'Isi tangki agar penyiraman bisa berjalan.', nWater);
      }
      if (!ow && water) _ev('Tangki terisi kembali', 0);
      if (!op && pump) _ev(auto ? 'Penyiraman dimulai (otomatis)' : 'Penyiraman dimulai (manual)', 1);
      if (op && !pump) {
        _ev('Penyiraman selesai', 1);
        _notify('Penyiraman selesai', 'Kelembaban tanah sekarang $soil%.', nPump);
      }
    }
    final now = _now();
    if (!auto && !pump && soil < minSoil - 10 && now - _lastDry > 3600) {
      _lastDry = now;
      _notify('Tanah kering', 'Kelembaban $soil%. Mode manual aktif - siram sekarang?', nDry);
    }
    // Di jalur Cloud, riwayat & kejadian dicatat server (24 jam non-stop), bukan HP.
    if (via == Net.lan && now - _lastSample >= 30) {
      _lastSample = now;
      samples.add(Sample(now, soil, temp, hum));
      if (samples.length > 2000) samples.removeAt(0);
      _p.setString('hist', jsonEncode(samples.map((s) => [s.t, s.soil, s.temp, s.hum]).toList()));
    }
  }

  void _ev(String t, int k) {
    if (via == Net.cloud) return;
    events.insert(0, Ev(_now(), t, k));
    if (events.length > 100) events.removeLast();
    _p.setString('ev', jsonEncode(events.map((e) => [e.t, e.text, e.kind]).toList()));
  }

  void _notify(String t, String b, bool on) {
    if (!on) return;
    _np.show(
      _nid++,
      t,
      b,
      const NotificationDetails(
        android: AndroidNotificationDetails('akarsiaga', 'Peringatan Akar Siaga',
            importance: Importance.high, priority: Priority.high),
      ),
    );
  }

  // =================== aksi ===================
  Future<void> setAuto(bool a) => send(a ? 'M:A' : 'M:M');
  Future<void> togglePump() => send(pump ? 'P:0' : 'P:1');
  Future<void> tune(int m, int r, int w) => send('T:$m,$r,$w');
  Future<void> calibrate(bool dry) => send(dry ? 'K:D' : 'K:W');
  Future<void> restartDevice() => send('R:1');
  Future<void> resetDevice() => send('R:F');

  /// Ubah satu pengaturan alat (tampilan langsung berubah, alat menyimpan permanen).
  Future<void> setCfg(String k, String v) {
    cfg[k] = v;
    notifyListeners();
    return send('C:$k=$v');
  }

  Future<void> applyPreset(Preset p) {
    plant = p.name;
    _p.setString('plant', p.name);
    notifyListeners();
    return tune(p.min, p.run, p.wait);
  }

  Future<void> pushSched(int i) {
    final s = sched[i];
    notifyListeners();
    return send('S:$i,${s.en ? 1 : 0},${s.h},${s.m},${s.dur},${s.days}');
  }

  void setTheme(int i) {
    themeIdx = i;
    _p.setInt('theme', i);
    notifyListeners();
  }

  void setPalette(int i) {
    paletteIdx = i;
    _p.setInt('pal', i);
    notifyListeners();
  }

  // =================== notifikasi (satu set untuk HP & server) ===================
  void setNotif({bool? w, bool? p, bool? c, bool? d}) {
    nWater = w ?? nWater;
    nPump = p ?? nPump;
    nConn = c ?? nConn;
    nDry = d ?? nDry;
    _p.setBool('nW', nWater);
    _p.setBool('nP', nPump);
    _p.setBool('nC', nConn);
    _p.setBool('nD', nDry);
    notifyListeners();
    _notifT?.cancel(); // simpan ke server otomatis (tanpa tombol)
    _notifT = Timer(const Duration(milliseconds: 900), () => saveServerNotify());
  }

  Future<void> loadServerNotify() async {
    final a = _api();
    if (a == null) return;
    try {
      final j = await a.getJson('/api/app/notify', {'id': devId});
      ntfy = (j['ntfy'] ?? '').toString();
      tg = (j['tg'] ?? '').toString();
      nWater = j['w'] != false;
      nPump = j['p'] != false;
      nDry = j['d'] != false;
      nConn = j['o'] != false;
      notifyListeners();
    } catch (_) {}
  }

  Future<String> saveServerNotify() async {
    final a = _api();
    if (a == null) return 'Isi URL server, kunci API, dan ID alat dulu.';
    try {
      await a.post('/api/app/notify', {'id': devId},
          jsonEncode({'ntfy': ntfy.trim(), 'tg': tg.trim(), 'w': nWater, 'p': nPump, 'd': nDry, 'o': nConn}));
      _p.setString('ntfy', ntfy.trim());
      _p.setString('tg', tg.trim());
      return 'Tersimpan di server.';
    } catch (e) {
      return 'Gagal menyimpan: $e';
    }
  }

  Future<String> testServerNotify() async {
    final a = _api();
    if (a == null) return 'Hubungkan ke server dulu (Setelan > Koneksi).';
    try {
      final r = await a.post('/api/app/test', {'id': devId}, '');
      return r.startsWith('0/')
          ? 'Belum ada tujuan push yang aktif. Aktifkan Firebase, atau isi ntfy/Telegram di Pengaturan lanjutan.'
          : 'Tes terkirim ($r berhasil).';
    } catch (e) {
      return 'Gagal: $e';
    }
  }

  // =================== push Firebase ===================
  Future<void> _initPush() async {
    if (!pushAvailable) return;
    fcmToken = await initPush((t) {
      fcmToken = t;
      registerPush();
    });
    registerPush();
  }

  /// Daftarkan (atau cabut) token Firebase HP ini di server. Mengembalikan pesan untuk pengguna.
  Future<String> registerPush({bool? enable}) async {
    if (enable != null) {
      pushOn = enable;
      _p.setBool('pushOn', enable);
      notifyListeners();
    }
    if (!pushAvailable) return 'Build ini belum memakai Firebase.';
    final t = fcmToken, a = _api();
    if (t == null) return 'Token Firebase belum tersedia (cek izin notifikasi dan konfigurasi Firebase).';
    if (a == null) return 'Hubungkan ke server dulu.';
    try {
      await a.post('/api/app/push', {'id': devId}, jsonEncode({'token': t, 'enabled': pushOn}));
      return pushOn ? 'HP ini terdaftar untuk push.' : 'Push untuk HP ini dimatikan.';
    } catch (e) {
      return 'Gagal mendaftar push: $e';
    }
  }

  // =================== asisten AI ===================
  AiService? aiService() =>
      (serverReady && devId.isNotEmpty) ? AiService(CloudApi(normUrl(serverUrl), apiKey), devId) : null;

  String _p2(int n) => n.toString().padLeft(2, '0');

  /// Ringkasan kondisi alat untuk AI (tanpa WiFi/kunci).
  Map<String, dynamic> aiContext() {
    final since = _now() - 86400;
    final d = samples.where((e) => e.t >= since).toList();
    Map<String, dynamic>? stat;
    if (d.isNotEmpty) {
      final so = d.map((e) => e.soil).toList();
      final tm = d.map((e) => e.temp).where((t) => t > -50).toList();
      stat = {
        'jumlah_sampel': d.length,
        'tanah_min': so.reduce((a, b) => a < b ? a : b),
        'tanah_maks': so.reduce((a, b) => a > b ? a : b),
        'tanah_rata2': (so.reduce((a, b) => a + b) / so.length).round(),
        if (tm.isNotEmpty) 'suhu_maks': tm.reduce((a, b) => a > b ? a : b),
      };
    }
    final step = d.length <= 24 ? 1 : (d.length / 24).ceil();
    final ev24 = events.where((e) => e.t >= since).toList();
    String fmt(int t) {
      final x = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      return '${_p2(x.day)}/${_p2(x.month)} ${_p2(x.hour)}:${_p2(x.minute)}';
    }

    return {
      'tanaman': plant.isEmpty ? 'belum dipilih' : plant,
      'terhubung_ke_alat': connected,
      'sekarang': {
        'tanah_persen': soil,
        'suhu_c': temp < -50 ? null : temp,
        'udara_persen': hum,
        'tangki_ada_air': water,
        'pompa_menyala': pump,
        'mode': auto ? 'otomatis' : 'manual',
      },
      'pengaturan': {
        'batas_siram_persen': minSoil,
        'batas_efektif_persen': effMin,
        'lama_siram_dtk': run,
        'jeda_dtk': wait,
        'batas_per_hari': cfgInt('maxday', 0),
        'debit_ml_per_dtk': cfgInt('flow', 30),
        'smart_panas_suhu_c': cfgInt('hT', 0),
        'smart_panas_tambahan_persen': cfgInt('hB', 10),
      },
      'jadwal_aktif': [
        for (final x in sched)
          if (x.en) '${_p2(x.h)}:${_p2(x.m)} selama ${x.dur} dtk (hari-bit ${x.days})'
      ],
      'statistik_24_jam': stat,
      'tren_tanah_persen': [for (var i = 0; i < d.length; i += step) d[i].soil],
      'jumlah_siram_24_jam': ev24.where((e) => e.text.startsWith('Penyiraman selesai')).length,
      'jumlah_tangki_habis_24_jam': ev24.where((e) => e.text == 'Tangki air habis').length,
      'air_total_liter': double.parse((cfgInt('tot', 0) * cfgInt('flow', 30) / 1000).toStringAsFixed(1)),
      'kejadian_terakhir': [for (final e in events.take(8)) '${fmt(e.t)} ${e.text}'],
    };
  }

  void clearHistory() {
    samples.clear();
    events.clear();
    _p.remove('hist');
    _p.remove('ev');
    notifyListeners();
  }
}

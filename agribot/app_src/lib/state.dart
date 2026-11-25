import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'link.dart';

enum Net { ap, sta, cloud }

const netNames = {Net.ap: 'Hotspot AgriBot', Net.sta: 'Wi-Fi Router', Net.cloud: 'Cloud (Internet)'};
const netCodes = {Net.ap: 'A', Net.sta: 'S', Net.cloud: 'S'};

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

int _i(String s, int d) => int.tryParse(s.trim()) ?? d;
int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  final _np = FlutterLocalNotificationsPlugin();

  Net net = Net.ap;
  String host = '', ssid = '', pass = '', plant = '', serverUrl = '', apiKey = '', devId = '', ntfy = '', tg = '';
  bool nWater = true, nPump = true, nConn = true, nDry = true; // notifikasi di HP (saat app terbuka)
  bool sw = true, sp = true, sd = true, so = true; // notifikasi push dari server
  int themeIdx = 0; // 0 sistem, 1 terang, 2 gelap

  Link? _link;
  StreamSubscription<String>? _ls;
  Timer? _retry, _hist;
  bool connected = false, busy = false, _got = false, _want = false, online = true;
  int _retries = 0, _nid = 1, _lastSample = 0, _lastDry = 0;
  String status = 'Belum terhubung';

  int soil = 0, raw = 0, hum = 0, minSoil = 55, run = 5, wait = 60, remain = 0, effMin = 55, offAge = 0, cloudState = 0;
  double temp = -99;
  bool water = true, pump = false, auto = true, timeOk = false;
  String devNet = 'A';

  final cfg = <String, String>{};
  final sched = List.generate(4, (i) => Sched(false, 6 + i * 4, 0, 5, 127));
  final samples = <Sample>[];
  final events = <Ev>[];

  String get devNetName => devNet == 'S' ? netNames[Net.sta]! : netNames[Net.ap]!;
  String cfgStr(String k, [String d = '']) => cfg[k] ?? d;
  int cfgInt(String k, int d) => int.tryParse(cfg[k] ?? '') ?? d;
  bool get serverReady => normUrl(serverUrl).isNotEmpty && apiKey.isNotEmpty;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    net = Net.values[(_p.getInt('net2') ?? 0) % 3];
    host = _p.getString('host') ?? '';
    ssid = _p.getString('ssid') ?? '';
    pass = _p.getString('pass') ?? '';
    plant = _p.getString('plant') ?? '';
    serverUrl = _p.getString('srv') ?? '';
    apiKey = _p.getString('key') ?? '';
    devId = _p.getString('did') ?? '';
    ntfy = _p.getString('ntfy') ?? '';
    tg = _p.getString('tg') ?? '';
    themeIdx = _p.getInt('theme') ?? 0;
    nWater = _p.getBool('nW') ?? true;
    nPump = _p.getBool('nP') ?? true;
    nConn = _p.getBool('nC') ?? true;
    nDry = _p.getBool('nD') ?? true;
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
  }

  // ---------- koneksi ----------
  Future<void> connect() async {
    _want = true;
    _retries = 0;
    await _connect();
  }

  Future<void> _connect() async {
    if (busy || connected) return;
    busy = true;
    status = net == Net.cloud ? 'Menghubungi server...' : 'Mencari AgriBot di jaringan...';
    notifyListeners();
    try {
      Link l;
      if (net == Net.cloud) {
        if (!serverReady || devId.isEmpty) {
          throw 'Isi URL server, kunci API, dan ID alat di Setelan > Koneksi.';
        }
        l = CloudLink(CloudApi(normUrl(serverUrl), apiKey), devId, _dropped);
      } else {
        String? h = await discoverHost();
        h ??= net == Net.ap ? '192.168.4.1' : (host.isEmpty ? null : host);
        if (h == null) throw 'AgriBot tidak ditemukan. Pastikan HP satu WiFi dengan alat, atau isi IP manual di Setelan.';
        l = LocalLink(h, _dropped);
      }
      _link = l;
      _ls = l.lines.listen(_onLine);
      try {
        await l.open();
      } catch (_) {
        await _ls?.cancel();
        await l.close();
        _link = null;
        rethrow;
      }
      connected = true;
      _retries = 0;
      online = true;
      status = 'Terhubung';
      _ev('Terhubung via ${netNames[net]}', 0);
      if (net == Net.cloud) {
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
    _notify('Koneksi terputus', 'AgriBot tidak lagi terhubung dengan HP.', nConn);
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

  // ---------- data masuk ----------
  void _parseCfg(String body) {
    for (final kv in body.split(';')) {
      final i = kv.indexOf('=');
      if (i > 0) cfg[kv.substring(0, i)] = kv.substring(i + 1);
    }
    final id = cfg['id'] ?? '';
    if (id.isNotEmpty && id != devId) {
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
    // Di mode Cloud, riwayat & kejadian dicatat server (24 jam non-stop), bukan HP.
    if (net != Net.cloud && now - _lastSample >= 30) {
      _lastSample = now;
      samples.add(Sample(now, soil, temp, hum));
      if (samples.length > 2000) samples.removeAt(0);
      _p.setString('hist', jsonEncode(samples.map((s) => [s.t, s.soil, s.temp, s.hum]).toList()));
    }
  }

  void _ev(String t, int k) {
    if (net == Net.cloud) return;
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
        android: AndroidNotificationDetails('agribot', 'Peringatan AgriBot',
            importance: Importance.high, priority: Priority.high),
      ),
    );
  }

  // ---------- aksi ----------
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

  void setNet(Net n) {
    net = n;
    _p.setInt('net2', n.index);
    notifyListeners();
  }

  void setTheme(int i) {
    themeIdx = i;
    _p.setInt('theme', i);
    notifyListeners();
  }

  void saveNet(String s, String pw, String url, String key, String id, String h) {
    ssid = s;
    pass = pw;
    serverUrl = url;
    apiKey = key;
    devId = id;
    host = h;
    _p.setString('ssid', s);
    _p.setString('pass', pw);
    _p.setString('srv', url);
    _p.setString('key', key);
    _p.setString('did', id);
    _p.setString('host', h);
    notifyListeners();
  }

  /// Kirim WiFi (+ server) ke alat lalu restart ke mode Router/Cloud.
  Future<void> provision() async {
    final useCloud = serverReady;
    if (ssid.isNotEmpty) await send('W:$ssid\t$pass');
    if (useCloud) await send('V:${normUrl(serverUrl)}\t$apiKey');
    await send('C:cloud=${useCloud ? 1 : 0}');
    await send('N:S');
    await _afterSwitch(useCloud ? Net.cloud : Net.sta,
        'Alat restart & masuk WiFi "$ssid". Tunggu ±20 detik, lalu tekan Hubungkan.');
  }

  Future<void> toHotspot() async {
    await send('N:A');
    await _afterSwitch(Net.ap, 'Alat restart ke Hotspot. Sambungkan HP ke WiFi "AgriBot-XXXX", lalu tekan Hubungkan.');
  }

  Future<void> _afterSwitch(Net n, String msg) async {
    await Future.delayed(const Duration(milliseconds: 700));
    await disconnect(quiet: true);
    setNet(n);
    status = msg;
    notifyListeners();
  }

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
  }

  // ---------- notifikasi push dari server ----------
  CloudApi? _api() => (serverReady && devId.isNotEmpty) ? CloudApi(normUrl(serverUrl), apiKey) : null;

  Future<void> loadServerNotify() async {
    final a = _api();
    if (a == null) return;
    try {
      final j = await a.getJson('/api/app/notify', {'id': devId});
      ntfy = (j['ntfy'] ?? '').toString();
      tg = (j['tg'] ?? '').toString();
      sw = j['w'] != false;
      sp = j['p'] != false;
      sd = j['d'] != false;
      so = j['o'] != false;
      notifyListeners();
    } catch (_) {}
  }

  Future<String> saveServerNotify() async {
    final a = _api();
    if (a == null) return 'Isi URL server, kunci API, dan ID alat dulu.';
    try {
      await a.post('/api/app/notify', {'id': devId},
          jsonEncode({'ntfy': ntfy.trim(), 'tg': tg.trim(), 'w': sw, 'p': sp, 'd': sd, 'o': so}));
      _p.setString('ntfy', ntfy.trim());
      _p.setString('tg', tg.trim());
      return 'Tersimpan di server.';
    } catch (e) {
      return 'Gagal menyimpan: $e';
    }
  }

  Future<String> testServerNotify() async {
    final a = _api();
    if (a == null) return 'Isi URL server, kunci API, dan ID alat dulu.';
    try {
      final r = await a.post('/api/app/test', {'id': devId}, '');
      return r.startsWith('0/') ? 'Tidak ada tujuan yang aktif. Isi topik ntfy atau Chat ID Telegram, lalu Simpan.' : 'Tes terkirim ($r berhasil).';
    } catch (e) {
      return 'Gagal: $e';
    }
  }

  void clearHistory() {
    samples.clear();
    events.clear();
    _p.remove('hist');
    _p.remove('ev');
    notifyListeners();
  }
}

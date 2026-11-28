import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Satu antarmuka untuk semua mode: alat mengirim baris teks, aplikasi mengirim perintah teks.
abstract class Link {
  Stream<String> get lines;
  Future<void> open();
  Future<void> send(String cmd);
  Future<void> close();
}

String normUrl(String u) {
  u = u.trim();
  if (u.isEmpty) return '';
  if (!u.startsWith('http')) u = 'https://$u';
  return u.replaceAll(RegExp(r'/+$'), '');
}

/// Galat dari server (kode HTTP + isi). [message] mengambil pesan ramah dari JSON {"error": ...}.
class ApiError implements Exception {
  final int code;
  final String body;
  ApiError(this.code, this.body);

  String get message {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] != null) return j['error'].toString();
    } catch (_) {}
    return 'HTTP $code';
  }

  @override
  String toString() => 'HTTP $code';
}

/// Klien API server (dipakai Cloud, riwayat, notifikasi push, dan asisten AI).
class CloudApi {
  final String base, key;
  CloudApi(this.base, this.key);
  Map<String, String> get _h => {'x-api-key': key};
  Uri _u(String p, Map<String, String> q) => Uri.parse('$base$p').replace(queryParameters: q);

  Future<String> getText(String p, Map<String, String> q, {Duration timeout = const Duration(seconds: 5)}) async {
    final r = await http.get(_u(p, q), headers: _h).timeout(timeout);
    if (r.statusCode != 200) throw ApiError(r.statusCode, utf8.decode(r.bodyBytes));
    return utf8.decode(r.bodyBytes);
  }

  Future<Map<String, dynamic>> getJson(String p, Map<String, String> q) async =>
      jsonDecode(await getText(p, q)) as Map<String, dynamic>;

  Future<String> post(String p, Map<String, String> q, String body, {Duration timeout = const Duration(seconds: 8)}) async {
    final r = await http.post(_u(p, q), headers: _h, body: body).timeout(timeout);
    if (r.statusCode != 200) throw ApiError(r.statusCode, utf8.decode(r.bodyBytes));
    return utf8.decode(r.bodyBytes);
  }
}

/// Polling berkala; 3 kali gagal beruntun = koneksi dianggap putus.
abstract class PollLink implements Link {
  final void Function() onDrop;
  final Duration every;
  PollLink(this.onDrop, this.every);
  final _ctl = StreamController<String>.broadcast();
  Timer? _t;
  int _fail = 0;

  String get failMsg;
  Future<String> poll();

  @override
  Stream<String> get lines => _ctl.stream;

  void _emit(String body) {
    for (final l in body.split('\n')) {
      if (l.trim().isNotEmpty && !_ctl.isClosed) _ctl.add(l.trim());
    }
  }

  @override
  Future<void> open() async {
    try {
      _emit(await poll());
    } catch (_) {
      throw failMsg;
    }
    _t = Timer.periodic(every, (_) => _tick());
  }

  Future<void> _tick() async {
    try {
      _emit(await poll());
      _fail = 0;
    } catch (_) {
      if (++_fail >= 3) {
        _t?.cancel();
        onDrop();
      }
    }
  }

  @override
  Future<void> close() async {
    _t?.cancel();
    await _ctl.close();
  }
}

/// HP <-> alat langsung (Hotspot atau satu WiFi router).
class LocalLink extends PollLink {
  final String host;
  LocalLink(this.host, void Function() onDrop) : super(onDrop, const Duration(milliseconds: 1500));

  @override
  String get failMsg => 'Tidak bisa menjangkau alat di $host. Pastikan HP satu WiFi dengan alat dan matikan data seluler.';

  @override
  Future<String> poll() async {
    final r = await http.get(Uri.http(host, '/api/all')).timeout(const Duration(seconds: 2));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return r.body;
  }

  @override
  Future<void> send(String c) async {
    await http.get(Uri.http(host, '/api/cmd', {'c': c})).timeout(const Duration(seconds: 3));
  }
}

/// HP <-> server <-> alat (lewat internet).
class CloudLink extends PollLink {
  final CloudApi api;
  final String id;
  CloudLink(this.api, this.id, void Function() onDrop) : super(onDrop, const Duration(seconds: 2));

  @override
  String get failMsg =>
      'Server tidak bisa dijangkau, atau kunci API / ID alat salah / alat belum pernah mengirim data. Periksa di Setelan > Koneksi.';

  @override
  Future<String> poll() => api.getText('/api/app/state', {'id': id});

  @override
  Future<void> send(String c) async {
    await api.post('/api/app/cmd', {'id': id}, c);
  }
}

/// Cari alat di jaringan lewat UDP broadcast. Mengembalikan alamat IP atau null.
Future<String?> discoverHost() async {
  RawDatagramSocket? s;
  try {
    s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    final c = Completer<String?>();
    s.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = s!.receive();
        if (d == null) return;
        final m = utf8.decode(d.data, allowMalformed: true);
        if (m.startsWith('AKARSIAGA,') && !c.isCompleted) c.complete(m.substring(10).trim());
      }
    });
    for (var i = 0; i < 3 && !c.isCompleted; i++) {
      s.send(utf8.encode('AKARSIAGA?'), InternetAddress('255.255.255.255'), 4210);
      s.send(utf8.encode('AKARSIAGA?'), InternetAddress('192.168.4.1'), 4210);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    return await c.future.timeout(const Duration(milliseconds: 600), onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    s?.close();
  }
}

/// Pemasangan alat baru: ambil semua baris langsung dari alat (mis. 192.168.4.1). null bila tidak terjangkau.
Future<String?> fetchLocalAll(String host) async {
  try {
    final r = await http.get(Uri.http(host, '/api/all')).timeout(const Duration(seconds: 2));
    return r.statusCode == 200 ? r.body : null;
  } catch (_) {
    return null;
  }
}

Future<bool> sendLocal(String host, String cmd) async {
  try {
    final r = await http.get(Uri.http(host, '/api/cmd', {'c': cmd})).timeout(const Duration(seconds: 4));
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

import 'dart:convert';
import 'link.dart';

/// Satu pesan di percakapan. [user] = true bila dari pengguna.
class AiMsg {
  final bool user;
  final String text;
  final bool error;
  AiMsg(this.user, this.text, {this.error = false});
}

class AiAnswer {
  final String text;
  final int left; // sisa kuota harian, -1 bila tidak diketahui
  AiAnswer(this.text, this.left);
}

class AiAdvice {
  final String summary, reason;
  final List<String> tips;
  final int? minSoil, runSec, waitSec;
  final int left;
  AiAdvice(this.summary, this.tips, this.minSoil, this.runSec, this.waitSec, this.reason, this.left);
  bool get hasSuggestion => minSoil != null || runSec != null || waitSec != null;
}

/// Pesan galat yang ramah dari error jaringan/server.
String aiErr(Object e) {
  if (e is ApiError) return e.message;
  return 'Tidak bisa menghubungi server. Periksa koneksi internet dan pengaturan server.';
}

int? _int(Object? v) => v is num ? v.toInt() : null;

/// Klien asisten AI. Kunci Gemini ada di server, bukan di aplikasi.
class AiService {
  final CloudApi api;
  final String id;
  AiService(this.api, this.id);

  Future<Map<String, dynamic>> status() => api.getJson('/api/ai/status', {});

  Future<AiAnswer> chat(List<AiMsg> history, Map<String, dynamic> ctx) async {
    final msgs = history.where((m) => !m.error).toList();
    final last = msgs.length > 10 ? msgs.sublist(msgs.length - 10) : msgs;
    final body = jsonEncode({
      'messages': [
        for (final m in last) {'role': m.user ? 'user' : 'model', 'text': m.text}
      ],
      'ctx': ctx,
    });
    final r = await api.post('/api/app/ai/chat', {'id': id}, body, timeout: const Duration(seconds: 40));
    final j = jsonDecode(r) as Map<String, dynamic>;
    return AiAnswer((j['reply'] ?? '').toString(), _int(j['left']) ?? -1);
  }

  Future<AiAdvice> advice(Map<String, dynamic> ctx) async {
    final r = await api.post('/api/app/ai/advice', {'id': id}, jsonEncode({'ctx': ctx}),
        timeout: const Duration(seconds: 40));
    final j = jsonDecode(r) as Map<String, dynamic>;
    final s = j['saran'] is Map ? j['saran'] as Map<String, dynamic> : <String, dynamic>{};
    return AiAdvice(
      (j['ringkasan'] ?? '').toString(),
      [for (final t in (j['tips'] as List? ?? [])) t.toString()],
      _int(s['batas_siram_persen']),
      _int(s['lama_siram_dtk']),
      _int(s['jeda_dtk']),
      (s['alasan'] ?? '').toString(),
      _int(j['left']) ?? -1,
    );
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Versi Firebase: notifikasi push masuk walau aplikasi ditutup.
/// Pesan berisi "notification", jadi sistem Android yang menampilkannya (tanpa kode latar belakang).
const bool pushAvailable = true;

/// Mengembalikan token FCM, atau null bila Firebase gagal (mis. izin ditolak / konfigurasi salah).
Future<String?> initPush(void Function(String token) onToken) async {
  try {
    await Firebase.initializeApp();
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();
    fm.onTokenRefresh.listen(onToken);
    return await fm.getToken();
  } catch (_) {
    return null;
  }
}

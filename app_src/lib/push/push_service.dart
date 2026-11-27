/// Versi bawaan: tanpa Firebase (build tetap berjalan; notifikasi push lewat ntfy/Telegram).
/// Saat secret GOOGLE_SERVICES_JSON ada, workflow menimpa file ini dengan app_firebase/lib/push/push_service.dart.
const bool pushAvailable = false;

Future<String?> initPush(void Function(String token) onToken) async => null;

# Akar Siaga

Penyiram tanaman otomatis berbasis ESP32 + aplikasi Android, dengan asisten AI dan notifikasi push.

| Cara HP terhubung | Cara kerja | Perlu internet? |
|---|---|---|
| **Hotspot Akar Siaga** | Alat membuat WiFi `AkarSiaga-XXXX` (sandi bawaan `akarsiaga123`) | Tidak |
| **Wi-Fi Router** | Alat & HP satu WiFi, alat ditemukan otomatis | Tidak |
| **Cloud** | Alat → server → aplikasi, dari mana saja | Ya |

Fitur: kontrol manual/otomatis, preset tanaman, jadwal (4 slot), riwayat & grafik, smart panas, batas siram per hari,
estimasi pemakaian air, deteksi penyiraman tidak efektif, notifikasi push (Firebase / ntfy / Telegram), asisten AI (Gemini).

## Struktur

```
firmware/akar_siaga_esp32/   sketch Arduino untuk ESP32
app_src/                     aplikasi Flutter (dasar, tanpa Firebase)
app_firebase/                overlay Firebase (dipakai otomatis bila secret ada)
server/                      server Node.js (Pterodactyl): src/ + test/
scripts/                     patch_android.py, deploy-panel.js, test_patch_android.py
.github/workflows/           build-apk.yml, deploy-server.yml
```

## 1. Alat (ESP32)
Wiring: lihat dua gambar rangkaian (sensor/input dan daya/pompa).
Pin: soil `GPIO34`, relay `26`, float switch `27`, DHT `4`, buzzer `25`, tombol `13`, LED `2`.
Library Arduino: *DHT sensor library*, *Adafruit Unified Sensor*. Buka `akar_siaga_esp32.ino`, pilih board **ESP32 Dev Module**, upload.
Bip saat menyala: 1 = Hotspot, 2 = Router. Tahan tombol >3 detik untuk ganti mode.
DHT22: pilih di aplikasi (Setelan > Alarm & sensor) lalu restart alat, atau ubah default `dhtType` di `loadCfg()`.

## 2. Server di panel Pterodactyl
Egg Node.js 18+, startup file `server.js`, tanpa `npm install`. Isi pengaturan lewat `config.json`
(salin `server/config.example.json`) atau variabel environment:

| Kunci | Fungsi |
|---|---|
| `API_KEY` | **Wajib**, ≥ 8 karakter, panjang dan acak |
| `GEMINI_API_KEY` | Kunci dari Google AI Studio (mengaktifkan fitur AI) |
| `GEMINI_MODEL` | Nama model; bawaan `gemini-flash-latest`. Cek daftar model terbaru di AI Studio |
| `AI_DAILY_LIMIT` | Batas pemakaian AI per alat per hari (bawaan 30) |
| `TG_BOT_TOKEN` | Bot Telegram (opsional) |
| `NTFY_SERVER` | Server ntfy (bawaan `https://ntfy.sh`) |
| `FIREBASE_SA_FILE` | Nama file service account Firebase (bawaan `firebase-service-account.json`) |

Kunci AI hanya ada di server, tidak pernah di aplikasi. `config.json`, `data.json`, dan service account **tidak** di-commit (`.gitignore`)
dan **tidak** ikut terunggah oleh skrip deploy. Log startup menunjukkan fitur mana yang aktif.

**HTTPS (Cloudflare Tunnel):** jalankan `cloudflared` di mesin yang bisa menjangkau `IP:PORT` server, arahkan hostname ke `http://IP:PORT`.
Alat memakai TLS tanpa verifikasi sertifikat (cukup untuk prototipe/lomba).

## 3. Deploy otomatis ke panel (GitHub Actions)
Buat **kunci API Client baru** di panel (Account > API Credentials), lalu di GitHub: *Settings > Secrets and variables > Actions*:

| Secret | Isi |
|---|---|
| `PTERO_URL` | domain panel, mis. `panel.contoh.com` |
| `PTERO_CLIENT_KEY` | kunci API Client (`ptlc_...`) |
| `PTERO_SERVER_ID` | ID server (UUID di URL panel) |

Push yang mengubah `server/**` → uji otomatis → unggah file → restart server. Jangan pernah menempel kunci di chat atau di file repo.

## 4. Aplikasi (APK) dan push Firebase
Push ke repo → tab **Actions** → **Build APK** → unduh artifact `AkarSiaga-apk`.
Tanpa Firebase, build berjalan normal (notifikasi lewat ntfy/Telegram dan notifikasi lokal).

Untuk mengaktifkan push langsung ke aplikasi:
1. Firebase Console → buat proyek → tambah aplikasi **Android** dengan package persis `id.akarsiaga.akar_siaga`.
2. Unduh `google-services.json` → isi seluruh isinya ke GitHub Secret **`GOOGLE_SERVICES_JSON`** → jalankan ulang build.
3. Project settings > Service accounts > *Generate new private key* → unggah file ke folder server di panel sebagai
   `firebase-service-account.json` (lewat File Manager; **jangan** lewat GitHub atau chat).
4. Aplikasi > Setelan > Notifikasi push: HP terdaftar otomatis, tekan **Kirim tes**.

## 5. Setup pertama
1. Nyalakan alat → WiFi `AkarSiaga-XXXX` muncul. Sambungkan HP (matikan data seluler), aplikasi > Setelan > mode Hotspot > Hubungkan.
2. Isi WiFi rumah (2,4 GHz), URL server, kunci API > **Kirim ke alat**. ID alat terisi otomatis.
3. Pilih mode **Cloud** > Hubungkan.

## Asisten AI
Beranda > **Asisten AI**: tanya jawab (konteks otomatis: kelembaban, suhu, riwayat 24 jam, pengaturan), saran pengaturan
(tombol Terapkan), ringkasan 24 jam, dan penjelasan peringatan (ketuk peringatan di Riwayat).
AI hanya **menyarankan**. Usulannya dipangkas server ke rentang aman (batas siram ±15 poin, lama/jeda maks 2× dan min ½ nilai sekarang),
dan pompa tetap dikendalikan aturan + pengaman di alat.

## Pengujian
```
cd server && node test/smoke.js          # 33 uji: Firebase (JWT RSA), Gemini, kuota, validasi
python3 scripts/test_patch_android.py    # 20 uji: patch gradle Kotlin DSL & Groovy
```
Belum teruji di lingkungan pengembangan ini: kompilasi Dart/Flutter, firmware di ESP32, panel Pterodactyl dan Firebase/Gemini sungguhan.
Bila build pertama gagal, kirim log Actions-nya.

## Protokol perintah (dokumentasi)
`M:A/M:M` mode · `P:1/P:0` pompa · `T:min,siram,jeda` · `S:i,en,h,m,dur,hari` jadwal · `C:kunci=nilai` pengaturan · `K:D/K:W` kalibrasi ·
`Z:epoch,offset` jam · `W:ssid⇥sandi` · `V:url⇥kunci` · `N:A/N:S` jaringan · `R:1` restart · `R:F` reset.

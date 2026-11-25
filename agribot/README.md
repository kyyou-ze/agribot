# AgriBot v3

Penyiram tanaman otomatis berbasis ESP32 + aplikasi Android. Tiga cara menghubungkan HP ke alat:

| Mode | Cara kerja | Perlu internet? |
|---|---|---|
| **Hotspot AgriBot** | Alat membuat WiFi `AgriBot-XXXX` (sandi `agribot123`) | Tidak |
| **Wi-Fi Router** | Alat & HP di WiFi yang sama, alat ditemukan otomatis | Tidak |
| **Cloud** | Alat → server → aplikasi, dari mana saja | Ya |

```
firmware/agribot_esp32/   → Arduino IDE → ESP32
app_src/                  → kode aplikasi Flutter (dibuild GitHub Actions)
server/                   → server Node.js (Pterodactyl)
.github/workflows/        → build APK otomatis
```

## 1. Alat (ESP32)
Pin: soil `GPIO34`, relay `26`, float switch `27`↔GND, DHT `4`, buzzer `25`, tombol `13`↔GND, LED `2`.
Pompa: 5V → relay COM, relay NO → pompa (+), pompa (−) → GND, dioda 1N4007 paralel pompa (garis putih di sisi +).
Library Arduino: *DHT sensor library*, *Adafruit Unified Sensor*. Upload `agribot_esp32.ino`.
Bunyi bip saat menyala: 1 = Hotspot, 2 = Router. Tahan tombol >3 dtk untuk ganti mode.

## 2. Aplikasi (APK)
Upload semua isi folder ini ke GitHub → tab **Actions** → **Build APK** → unduh artifact `AgriBot-apk`.

## 3. Server (Pterodactyl, egg Node.js)
1. Upload isi folder `server/` ke panel; startup file: `server.js` (Node 18+). Tidak perlu `npm install`.
2. Isi **API_KEY** (wajib, ≥8 karakter, acak & panjang). Lewat variabel environment, atau salin `config.example.json` → `config.json`.
3. Opsional: `TG_BOT_TOKEN` (bot Telegram dari @BotFather), `NTFY_SERVER` (default `https://ntfy.sh`).
4. Data tersimpan di `data.json` (±3 hari riwayat per alat). Pastikan folder bisa ditulis.

### HTTPS dengan Cloudflare Tunnel
Tunnel hanya perlu bisa menjangkau port server. Jalankan `cloudflared` di mesin mana pun yang bisa mengakses `IP:PORT` server (bisa juga PC/VPS lain), arahkan hostname ke `http://IP:PORT`. Bila hosting mengizinkan, tanpa tunnel pun bisa: pakai `http://IP:PORT` langsung (aplikasi & alat mendukung HTTP).
Alat memakai TLS **tanpa verifikasi sertifikat** (cukup untuk lomba/prototipe; untuk produksi tambahkan sertifikat root).

## 4. Setup pertama kali
1. Nyalakan alat → WiFi `AgriBot-XXXX` muncul. Sambungkan HP, matikan data seluler.
2. Aplikasi → Setelan → mode **Hotspot** → **Hubungkan**. ID alat terisi otomatis.
3. Isi WiFi rumah (2,4 GHz), URL server, kunci API → **Kirim ke alat**. Alat restart & masuk WiFi.
4. Pilih mode **Cloud** → **Hubungkan**. Selesai; bisa dari mana saja.

## 5. Notifikasi real-time tanpa aplikasi terbuka
Server mengirim push langsung (≈2–5 detik): tangki habis, siram selesai, tanah kering, penyiraman kurang efektif, alat offline/online.
- **ntfy**: pasang aplikasi *ntfy*, subscribe ke topik yang sama dengan di Setelan (pakai nama sulit ditebak, topik publik bisa dibaca siapa pun).
- **Telegram**: kirim `/start` ke bot, isi Chat ID di Setelan.

Notifikasi bawaan APK (tanpa aplikasi tambahan) saat aplikasi **tertutup** butuh Firebase Cloud Messaging — belum disertakan.

## Perintah protokol (untuk dokumentasi)
`M:A/M:M` mode · `P:1/P:0` pompa · `T:min,siram,jeda` · `S:i,en,h,m,dur,hari` jadwal · `C:kunci=nilai` pengaturan · `K:D/K:W` kalibrasi · `Z:epoch,offset` jam · `W:ssid⇥sandi` · `V:url⇥kunci` · `N:A/N:S` jaringan · `R:1` restart · `R:F` reset.

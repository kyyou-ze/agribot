'use strict';
// Logika data dari alat: deteksi kejadian, riwayat, dan alat offline.
const { db, rt, now, dev } = require('./store');
const { pushTo } = require('./push');
const cfg = require('./config');

function ev(id, text, kind) {
  const d = dev(id);
  d.events.unshift([now(), text, kind]);
  if (d.events.length > 200) d.events.length = 200;
}

function alert(id, flag, title, body, kind) {
  ev(id, title, kind);
  const d = dev(id);
  if (d.notify[flag]) pushTo(d, title, body).catch(() => {});
}

const validStatus = line => {
  const p = line.split(',');
  return p.length >= 10 && p.slice(0, 4).every(x => x !== '' && Number.isFinite(+x)) && p[4].length === 1 && p[5].length === 1;
};

function onStatus(id, d, line) {
  const p = line.split(',');
  const cur = { soil: +p[0], temp: +p[2], hum: +p[3], water: p[4] === '1', pump: p[5] === '1', auto: p[6] === 'A', min: +p[7] };
  const r = (rt[id] ||= {});
  const old = r.prev;
  r.prev = cur;
  if (!d.online) {
    d.online = true;
    if (r.seen) alert(id, 'o', 'Alat online kembali', 'Akar Siaga tersambung lagi ke server.', 0);
  }
  r.seen = true;
  if (old) {
    if (old.water && !cur.water) alert(id, 'w', 'Tangki air habis', 'Isi tangki agar penyiraman bisa berjalan.', 2);
    if (!old.water && cur.water) ev(id, 'Tangki terisi kembali', 0);
    if (!old.pump && cur.pump) { ev(id, cur.auto ? 'Penyiraman dimulai (otomatis)' : 'Penyiraman dimulai (manual)', 1); r.base = old.soil; }
    if (old.pump && !cur.pump) {
      alert(id, 'p', 'Penyiraman selesai', `Kelembaban tanah ${cur.soil}%.`, 1);
      const base = r.base;
      setTimeout(() => { // penyiraman tidak berpengaruh -> selang/pompa bermasalah
        const n = r.prev;
        if (n && base != null && n.water && n.soil < base + 2) {
          alert(id, 'd', 'Penyiraman kurang efektif', 'Kelembaban tidak naik setelah disiram. Cek selang, pompa, dan posisi sensor.', 2);
        }
      }, cfg.INEFFECTIVE_CHECK_S * 1000);
    }
  } else if (!cur.water) alert(id, 'w', 'Tangki air habis', 'Isi tangki agar penyiraman bisa berjalan.', 2);
  if (!cur.auto && !cur.pump && cur.soil < cur.min - 10 && Date.now() - d.lastDry > 3600e3) {
    d.lastDry = Date.now();
    alert(id, 'd', 'Tanah kering', `Kelembaban ${cur.soil}%. Mode manual aktif - siram sekarang?`, 2);
  }
  if (now() - d.lastSample >= 30) {
    d.lastSample = now();
    d.samples.push([now(), cur.soil, cur.temp, cur.hum]);
    if (d.samples.length > 8640) d.samples.shift(); // ±3 hari
  }
}

/** Satu pintu data dari alat (asli maupun simulator): simpan, deteksi kejadian, kembalikan perintah menunggu. */
function ingest(id, lines) {
  const d = dev(id);
  d.ts = Date.now(); d.status = lines[0]; d.extra = lines.slice(1);
  onStatus(id, d, lines[0]);
  return d.q.splice(0);
}

function startWatchdog() { // tidak ada data > OFFLINE_AFTER_S detik = offline
  return setInterval(() => {
    for (const [id, d] of Object.entries(db)) {
      if (d.online && Date.now() - d.ts > cfg.OFFLINE_AFTER_S * 1000) {
        d.online = false;
        alert(id, 'o', 'Alat offline', 'Tidak ada data dari alat lebih dari 90 detik. Cek listrik dan WiFi.', 2);
      }
    }
  }, Math.min(15000, cfg.OFFLINE_AFTER_S * 500));
}

module.exports = { validStatus, onStatus, ingest, startWatchdog };

'use strict';
// AgriBot server - tanpa dependensi (Node.js 18+). Jalankan di panel Pterodactyl (egg Node.js, file: server.js)
const http = require('http'), fs = require('fs'), path = require('path');

let fileCfg = {};
try { fileCfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8')); } catch {}
const env = (k, d = '') => process.env[k] || fileCfg[k] || d;

const PORT = +env('SERVER_PORT') || +env('PORT') || 3000;
const API_KEY = String(env('API_KEY'));
const TG = String(env('TG_BOT_TOKEN'));
const NTFY = String(env('NTFY_SERVER', 'https://ntfy.sh')).replace(/\/+$/, '');
if (API_KEY.length < 8) {
  console.error('API_KEY wajib diisi (minimal 8 karakter): lewat variabel environment atau config.json');
  process.exit(1);
}

const FILE = path.join(__dirname, 'data.json');
let db = {};
try { db = JSON.parse(fs.readFileSync(FILE, 'utf8')); } catch {}
const rt = {}; // data sementara (tidak disimpan)
const now = () => Math.floor(Date.now() / 1000);
const save = () => {
  try { fs.writeFileSync(FILE + '.tmp', JSON.stringify(db)); fs.renameSync(FILE + '.tmp', FILE); }
  catch (e) { console.error('gagal menyimpan:', e.message); }
};

function dev(id) {
  return (db[id] ||= {
    ts: 0, online: false, status: '', extra: [], q: [], samples: [], events: [], lastSample: 0, lastDry: 0,
    notify: { ntfy: '', tg: '', w: true, p: true, d: true, o: true },
  });
}

// ---------- Notifikasi push (ntfy + Telegram) ----------
async function pushTo(d, title, body) {
  const n = d.notify, jobs = [];
  if (n.ntfy) jobs.push(fetch(`${NTFY}/${encodeURIComponent(n.ntfy)}`, {
    method: 'POST', body, headers: { Title: title, Priority: 'high', Tags: 'seedling' },
  }));
  if (n.tg && TG) jobs.push(fetch(`https://api.telegram.org/bot${TG}/sendMessage`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ chat_id: n.tg, text: `🌱 ${title}\n${body}` }),
  }));
  const r = await Promise.allSettled(jobs);
  return `${r.filter(x => x.status === 'fulfilled' && x.value.ok).length}/${r.length}`;
}
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

// ---------- Pemrosesan data dari alat ----------
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
    if (r.seen) alert(id, 'o', 'Alat online kembali', 'AgriBot tersambung lagi ke server.', 0);
  }
  r.seen = true;
  if (old) {
    if (old.water && !cur.water) alert(id, 'w', 'Tangki air habis', 'Isi tangki agar penyiraman bisa berjalan.', 2);
    if (!old.water && cur.water) ev(id, 'Tangki terisi kembali', 0);
    if (!old.pump && cur.pump) { ev(id, cur.auto ? 'Penyiraman dimulai (otomatis)' : 'Penyiraman dimulai (manual)', 1); r.base = old.soil; }
    if (old.pump && !cur.pump) {
      alert(id, 'p', 'Penyiraman selesai', `Kelembaban tanah ${cur.soil}%.`, 1);
      const base = r.base;
      setTimeout(() => {   // deteksi penyiraman tidak berpengaruh (selang/pompa bermasalah)
        const n = r.prev;
        if (n && base != null && n.water && n.soil < base + 2) {
          alert(id, 'd', 'Penyiraman kurang efektif', 'Kelembaban tidak naik setelah disiram. Cek selang, pompa, dan posisi sensor.', 2);
        }
      }, 60000);
    }
  } else if (!cur.water) alert(id, 'w', 'Tangki air habis', 'Isi tangki agar penyiraman bisa berjalan.', 2);
  if (!cur.auto && !cur.pump && cur.soil < cur.min - 10 && Date.now() - d.lastDry > 3600e3) {
    d.lastDry = Date.now();
    alert(id, 'd', 'Tanah kering', `Kelembaban ${cur.soil}%. Mode manual aktif - siram sekarang?`, 2);
  }
  if (now() - d.lastSample >= 30) {
    d.lastSample = now();
    d.samples.push([now(), cur.soil, cur.temp, cur.hum]);
    if (d.samples.length > 8640) d.samples.shift();   // ±3 hari
  }
}

setInterval(() => {   // alat dianggap offline bila tidak mengirim data > 90 detik
  for (const [id, d] of Object.entries(db)) {
    if (d.online && Date.now() - d.ts > 90000) {
      d.online = false;
      alert(id, 'o', 'Alat offline', 'Tidak ada data dari alat lebih dari 90 detik. Cek listrik dan WiFi.', 2);
    }
  }
}, 15000);
setInterval(save, 30000);
for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => { save(); process.exit(0); });

// ---------- HTTP ----------
const readBody = req => new Promise(res => {
  let b = '';
  req.on('data', c => { b += c; if (b.length > 20000) req.destroy(); });
  req.on('end', () => res(b));
  req.on('error', () => res(''));
});

http.createServer(async (req, res) => {
  const send = (code, body, type = 'text/plain') => { res.writeHead(code, { 'content-type': type + '; charset=utf-8' }); res.end(body); };
  try {
    const u = new URL(req.url, 'http://x');
    if (u.pathname === '/') return send(200, 'AgriBot server OK');
    if ((req.headers['x-api-key'] || '') !== API_KEY) return send(401, 'unauthorized');
    const body = req.method === 'POST' ? await readBody(req) : '';

    if (u.pathname === '/api/device/sync' && req.method === 'POST') {
      const id = String(req.headers['x-device-id'] || '');
      if (!/^[\w-]{3,40}$/.test(id)) return send(400, 'bad id');
      const lines = body.split('\n').map(s => s.trim()).filter(Boolean);
      if (!lines.length || !validStatus(lines[0])) return send(400, 'bad status');
      const d = dev(id);
      d.ts = Date.now(); d.status = lines[0]; d.extra = lines.slice(1);
      onStatus(id, d, lines[0]);
      return send(200, d.q.splice(0).join('\n'));
    }

    const id = u.searchParams.get('id') || '';
    if (!/^[\w-]{3,40}$/.test(id)) return send(400, 'bad id');

    if (u.pathname === '/api/app/state') {
      const d = db[id];
      if (!d || !d.status) return send(404, 'unknown device');
      const age = Math.round((Date.now() - d.ts) / 1000);
      return send(200, [`O:${d.online ? 1 : 0},${age}`, d.status, ...d.extra].join('\n'));
    }
    if (u.pathname === '/api/app/cmd' && req.method === 'POST') {
      const d = db[id];
      const cmd = body.trim();
      if (!d || !/^[A-Z]:/.test(cmd) || cmd.length > 160) return send(400, 'bad');
      d.q.push(cmd);
      if (d.q.length > 30) d.q.shift();
      return send(200, 'OK');
    }
    if (u.pathname === '/api/app/history') {
      const d = db[id];
      if (!d) return send(404, 'unknown device');
      const since = now() - Math.min(72, +u.searchParams.get('hours') || 24) * 3600;
      return send(200, JSON.stringify({ s: d.samples.filter(x => x[0] >= since), e: d.events.slice(0, 100) }), 'application/json');
    }
    if (u.pathname === '/api/app/notify') {
      if (req.method === 'GET') return send(200, JSON.stringify((db[id] || dev(id)).notify), 'application/json');
      const j = JSON.parse(body || '{}'), d = dev(id);
      d.notify = {
        ntfy: String(j.ntfy || '').trim().slice(0, 64), tg: String(j.tg || '').trim().slice(0, 32),
        w: !!j.w, p: !!j.p, d: !!j.d, o: !!j.o,
      };
      save();
      return send(200, 'OK');
    }
    if (u.pathname === '/api/app/test' && req.method === 'POST') {
      const r = await pushTo(dev(id), 'Tes notifikasi AgriBot', 'Jika pesan ini masuk, notifikasi server sudah aktif.');
      return send(200, r);
    }
    send(404, 'not found');
  } catch (e) {
    send(500, 'error');
  }
}).listen(PORT, () => console.log(`AgriBot server berjalan di port ${PORT}`));

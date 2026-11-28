'use strict';
// Semua endpoint HTTP. Semua (kecuali "/") wajib header x-api-key.
const cfg = require('./config');
const { db, now, dev, save } = require('./store');
const { validStatus, ingest } = require('./device');
const { pushTo } = require('./push');
const ai = require('./ai');
const sim = require('./simulator');

const ID_RE = /^[\w-]{3,40}$/;
const TOKEN_RE = /^[\w:.\-]{8,400}$/;

const readBody = req => new Promise(res => {
  let b = '';
  req.on('data', c => { b += c; if (b.length > 60000) req.destroy(); });
  req.on('end', () => res(b));
  req.on('error', () => res(''));
});

module.exports = async function handle(req, res) {
  const send = (code, body, type = 'text/plain') => { res.writeHead(code, { 'content-type': type + '; charset=utf-8' }); res.end(body); };
  const json = (code, obj) => send(code, JSON.stringify(obj), 'application/json');
  const parse = s => { try { return JSON.parse(s || '{}'); } catch { return null; } };

  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/') return send(200, 'Akar Siaga server OK');
  if ((req.headers['x-api-key'] || '') !== cfg.API_KEY) return send(401, 'unauthorized');
  const post = req.method === 'POST';
  const body = post ? await readBody(req) : '';

  // ---- dari alat ----
  if (u.pathname === '/api/device/sync' && post) {
    const id = String(req.headers['x-device-id'] || '');
    if (!ID_RE.test(id)) return send(400, 'bad id');
    const lines = body.split('\n').map(s => s.trim()).filter(Boolean);
    if (!lines.length || !validStatus(lines[0])) return send(400, 'bad status');
    return send(200, ingest(id, lines).join('\n'));
  }

  if (u.pathname === '/api/ai/status') return json(200, ai.status());

  // ---- tanpa ?id= : daftar alat & mode uji ----
  if (u.pathname === '/api/app/devices') { // aplikasi memilih alat otomatis
    const nameOf = d => { const c = d.extra.find(l => l.startsWith('C:')); const m = c && /name=([^;]*)/.exec(c); return m ? m[1] : ''; };
    return json(200, Object.entries(db).filter(([, d]) => d.status)
      .map(([id, d]) => ({ id, name: nameOf(d), online: !!d.online, sim: id === sim.ID })));
  }
  if (u.pathname === '/api/sim/status') return json(200, { enabled: sim.enabled(), id: sim.ID });
  if (u.pathname === '/api/sim/scenario' && post) {
    if (!sim.enabled()) return json(404, { error: 'Mode uji (SIMULATOR) belum aktif di server.' });
    const r = sim.scenario(u.searchParams.get('name') || '', +u.searchParams.get('secs') || 0);
    return json(r.ok ? 200 : 400, r);
  }

  // ---- dari aplikasi (butuh ?id=) ----
  const id = u.searchParams.get('id') || '';
  if (!ID_RE.test(id)) return send(400, 'bad id');

  if (u.pathname === '/api/app/state') {
    const d = db[id];
    if (!d || !d.status) return send(404, 'unknown device');
    const age = Math.round((Date.now() - d.ts) / 1000);
    return send(200, [`O:${d.online ? 1 : 0},${age}`, d.status, ...d.extra].join('\n'));
  }

  if (u.pathname === '/api/app/cmd' && post) {
    const d = db[id], cmd = body.trim();
    if (!d || !/^[A-Z]:/.test(cmd) || cmd.length > 160) return send(400, 'bad');
    d.q.push(cmd);
    if (d.q.length > 30) d.q.shift();
    return send(200, 'OK');
  }

  if (u.pathname === '/api/app/history') {
    const d = db[id];
    if (!d) return send(404, 'unknown device');
    const since = now() - Math.min(72, +u.searchParams.get('hours') || 24) * 3600;
    return json(200, { s: d.samples.filter(x => x[0] >= since), e: d.events.slice(0, 100) });
  }

  if (u.pathname === '/api/app/notify') {
    if (!post) return json(200, (db[id] || dev(id)).notify);
    const j = parse(body);
    if (!j) return send(400, 'bad json');
    dev(id).notify = {
      ntfy: String(j.ntfy || '').trim().slice(0, 64), tg: String(j.tg || '').trim().slice(0, 32),
      w: !!j.w, p: !!j.p, d: !!j.d, o: !!j.o,
    };
    save();
    return send(200, 'OK');
  }

  if (u.pathname === '/api/app/push' && post) { // daftar / cabut token Firebase HP ini
    const j = parse(body), t = j && String(j.token || '').trim();
    if (!t || !TOKEN_RE.test(t)) return send(400, 'bad token');
    const d = dev(id);
    d.tokens = d.tokens.filter(x => x !== t);
    if (j.enabled !== false) { d.tokens.push(t); if (d.tokens.length > 5) d.tokens.shift(); }
    save();
    return send(200, 'OK');
  }

  if (u.pathname === '/api/app/test' && post) {
    return send(200, await pushTo(dev(id), 'Tes notifikasi Akar Siaga', 'Jika pesan ini masuk, notifikasi server sudah aktif.'));
  }

  // ---- AI ----
  if ((u.pathname === '/api/app/ai/chat' || u.pathname === '/api/app/ai/advice') && post) {
    const b = parse(body);
    if (!b) return json(400, { error: 'JSON tidak valid.' });
    try {
      return json(200, u.pathname.endsWith('chat') ? await ai.chat(id, b) : await ai.advice(id, b));
    } catch (e) {
      if (e instanceof ai.AiError) return json(e.status, { error: e.message });
      throw e;
    }
  }

  send(404, 'not found');
};

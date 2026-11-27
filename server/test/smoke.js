'use strict';
// Uji asap: jalankan server asli dengan server palsu untuk Google OAuth, FCM, dan Gemini.
//   cd server && node test/smoke.js
const http = require('http'), crypto = require('crypto'), fs = require('fs'), os = require('os'), path = require('path');
const { spawn } = require('child_process');

const KEY = 'kunci-uji-12345';
let fails = 0;
const ok = (c, m) => { console.log(`${c ? 'PASS' : 'FAIL'}  ${m}`); if (!c) fails++; };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const readBody = req => new Promise(r => { let b = ''; req.on('data', c => (b += c)); req.on('end', () => r(b)); });
const listen = handler => new Promise(res => {
  const s = http.createServer(handler);
  s.listen(0, '127.0.0.1', () => res({ s, port: s.address().port }));
});

(async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'akarsiaga-'));
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048, publicKeyEncoding: { type: 'spki', format: 'pem' }, privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  fs.writeFileSync(path.join(tmp, 'sa.json'), JSON.stringify({ client_email: 'bot@test-proj.iam.gserviceaccount.com', private_key: privateKey, project_id: 'test-proj' }));

  // --- server palsu: OAuth Google ---
  const oauth = { ok: false, reason: '' };
  const O = await listen(async (req, res) => {
    const p = new URLSearchParams(await readBody(req));
    const [h, c, sig] = (p.get('assertion') || '').split('.');
    const verified = crypto.createVerify('RSA-SHA256').update(`${h}.${c}`).verify(publicKey, sig, 'base64url');
    const claim = JSON.parse(Buffer.from(c, 'base64url').toString());
    oauth.ok = verified && p.get('grant_type') === 'urn:ietf:params:oauth:grant-type:jwt-bearer' &&
      claim.iss === 'bot@test-proj.iam.gserviceaccount.com' && claim.scope.endsWith('firebase.messaging') &&
      claim.aud === `http://127.0.0.1:${O.port}/token` && claim.exp - claim.iat === 3600;
    oauth.reason = `verified=${verified}`;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ access_token: 'at-123', expires_in: 3600 }));
  });

  // --- server palsu: FCM ---
  const fcm = [];
  const F = await listen(async (req, res) => {
    const b = JSON.parse(await readBody(req));
    fcm.push({ path: req.url, auth: req.headers.authorization, token: b.message.token, title: b.message.notification.title, ch: b.message.android.notification.channel_id });
    if (b.message.token === 'tok-dead-00001') {
      res.writeHead(404, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }));
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{"name":"projects/test-proj/messages/1"}');
  });

  // --- server palsu: Gemini ---
  const gem = { last: null };
  const G = await listen(async (req, res) => {
    const b = JSON.parse(await readBody(req));
    gem.last = { url: req.url, key: req.headers['x-goog-api-key'], body: b };
    const text = b.contents.map(c => c.parts[0].text).join(' ') + ' ' + JSON.stringify(b.systemInstruction || '');
    const reply = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); };
    const cand = t => ({ candidates: [{ content: { parts: [{ text: t }] } }] });
    if (text.includes('SIMULASI_429')) return reply(429, { error: { message: 'quota' } });
    if (text.includes('Analisis data alat')) {
      return reply(200, cand(text.includes('SIMULASI_RUSAK') ? 'bukan json' : JSON.stringify({
        ringkasan: 'Tanah sering kering sore hari.', tips: ['Cek selang', 'Naikkan batas', 'a', 'b', 'c', 'terlalu banyak'],
        saran: { batas_siram_persen: 95, lama_siram_dtk: 100, jeda_dtk: 5, alasan: 'Sering kering.' },
      })));
    }
    reply(200, cand('Jawaban **uji**.'));
  });

  // --- jalankan server asli ---
  const free = await listen(() => {}); const PORT = free.port; free.s.close();
  const env = {
    ...process.env, API_KEY: KEY, SERVER_PORT: String(PORT), DATA_FILE: path.join(tmp, 'data.json'),
    FIREBASE_SA_FILE: path.join(tmp, 'sa.json'), FCM_TOKEN_URL: `http://127.0.0.1:${O.port}/token`, FCM_API_BASE: `http://127.0.0.1:${F.port}`,
    GEMINI_API_KEY: 'gem-key', GEMINI_BASE: `http://127.0.0.1:${G.port}`, GEMINI_MODEL: 'model-uji', AI_DAILY_LIMIT: '5',
  };
  const proc = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], { env });
  let log = '';
  proc.stdout.on('data', d => (log += d)); proc.stderr.on('data', d => (log += d));
  for (let i = 0; i < 50 && !log.includes('berjalan'); i++) await sleep(100);

  const call = async (method, p, { body, key = KEY, headers = {}, port = PORT } = {}) => {
    const r = await fetch(`http://127.0.0.1:${port}${p}`, { method, headers: { 'x-api-key': key, ...headers }, body });
    const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch {}
    return { status: r.status, text: t, json: j };
  };
  const ST = (water, pump = 0) => `40,2100,28.5,70,${water},${pump},A,55,5,60,S,1,0,55,1`;
  const sync = (id, line) => call('POST', '/api/device/sync', { body: line, headers: { 'x-device-id': id } });
  const ID = 'AkarSiaga-TEST';

  console.log('== dasar & keamanan ==');
  ok(log.includes('Push Firebase : aktif') && log.includes('AI Gemini     : aktif'), 'log startup menampilkan Firebase & AI aktif');
  ok((await call('GET', '/', { key: '' })).status === 200, 'health check tanpa kunci = 200');
  ok((await call('GET', `/api/app/state?id=${ID}`, { key: 'salah' })).status === 401, 'kunci salah = 401');
  ok((await sync(ID, '$42,abc')).status === 400, 'data alat rusak ditolak (400)');
  ok((await sync(ID, ST(1))).status === 200, 'sinkron alat valid = 200');

  console.log('== push Firebase ==');
  ok((await call('POST', `/api/app/push?id=${ID}`, { body: JSON.stringify({ token: 'x' }) })).status === 400, 'token pendek ditolak');
  ok((await call('POST', `/api/app/push?id=${ID}`, { body: JSON.stringify({ token: 'tok-alive-12345' }) })).status === 200, 'daftar token HP hidup');
  ok((await call('POST', `/api/app/push?id=${ID}`, { body: JSON.stringify({ token: 'tok-dead-00001' }) })).status === 200, 'daftar token HP mati');
  await sync(ID, ST(0)); // air habis -> kirim push
  await sleep(600);
  const a1 = fcm.filter(x => x.token === 'tok-alive-12345'), d1 = fcm.filter(x => x.token === 'tok-dead-00001');
  ok(oauth.ok, `JWT service account valid & tertandatangani RSA (${oauth.reason})`);
  ok(a1.length === 1 && a1[0].title === 'Tangki air habis', 'push "Tangki air habis" sampai ke token hidup');
  ok(a1[0] && a1[0].auth === 'Bearer at-123' && a1[0].path === '/v1/projects/test-proj/messages:send' && a1[0].ch === 'akarsiaga_push', 'header Bearer, path proyek, channel_id benar');
  ok(d1.length === 1, 'token mati juga dicoba sekali');
  await sync(ID, ST(1)); await sync(ID, ST(0)); // air habis lagi
  await sleep(600);
  ok(fcm.filter(x => x.token === 'tok-alive-12345').length === 2, 'push kedua sampai ke token hidup');
  ok(fcm.filter(x => x.token === 'tok-dead-00001').length === 1, 'token UNREGISTERED otomatis dihapus (tidak dicoba lagi)');
  const t = await call('POST', `/api/app/test?id=${ID}`);
  ok(t.text === '1/1', `tes notifikasi: ${t.text} (hanya token hidup tersisa)`);
  await call('POST', `/api/app/push?id=${ID}`, { body: JSON.stringify({ token: 'tok-alive-12345', enabled: false }) });
  const t2 = await call('POST', `/api/app/test?id=${ID}`);
  ok(t2.text === '0/0', 'cabut token: tidak ada tujuan push lagi');

  console.log('== AI: chat ==');
  ok((await call('GET', '/api/ai/status')).json.enabled === true, 'status AI aktif');
  const c1 = await call('POST', `/api/app/ai/chat?id=${ID}`, {
    body: JSON.stringify({ messages: [{ role: 'model', text: 'sisa lama' }, { role: 'user', text: 'Halo' }], ctx: { tanaman: 'Cabai', sekarang: { tanah_persen: 40 } } }),
  });
  ok(c1.status === 200 && c1.json.reply === 'Jawaban **uji**.' && c1.json.left === 4, 'chat berhasil, sisa kuota 4');
  ok(gem.last.url === '/v1beta/models/model-uji:generateContent' && gem.last.key === 'gem-key', 'path model & header x-goog-api-key benar');
  ok(gem.last.body.contents.length === 1 && gem.last.body.contents[0].role === 'user', 'pesan "model" di awal dibuang');
  ok(gem.last.body.systemInstruction.parts[0].text.includes('DATA ALAT') && gem.last.body.systemInstruction.parts[0].text.includes('Cabai'), 'konteks alat masuk ke system prompt');
  ok((await call('POST', `/api/app/ai/chat?id=${ID}`, { body: JSON.stringify({ messages: [] }) })).status === 400, 'pesan kosong ditolak (400)');
  const c2 = await call('POST', `/api/app/ai/chat?id=${ID}`, { body: JSON.stringify({ messages: [{ role: 'user', text: 'SIMULASI_429' }] }) });
  ok(c2.status === 429 && /Kuota Gemini/.test(c2.json.error), 'Gemini 429 -> pesan ramah, bukan crash');

  console.log('== AI: saran pengaturan (dengan pagar pengaman) ==');
  const ctx = { pengaturan: { batas_siram_persen: 55, lama_siram_dtk: 5, jeda_dtk: 60 } };
  const v = await call('POST', `/api/app/ai/advice?id=${ID}`, { body: JSON.stringify({ ctx }) });
  ok(v.status === 200 && v.json.saran.batas_siram_persen === 70, 'batas siram 95 dipangkas ke 70 (maks +15 dari 55)');
  ok(v.json.saran.lama_siram_dtk === 10, 'lama siram 100 dipangkas ke 10 (maks 2x dari 5)');
  ok(v.json.saran.jeda_dtk === 30, 'jeda 5 dinaikkan ke 30 (min setengah dari 60)');
  ok(v.json.tips.length === 5, 'tips dibatasi 5 butir');
  const bad = await call('POST', `/api/app/ai/advice?id=${ID}`, { body: JSON.stringify({ ctx: { x: 'SIMULASI_RUSAK' } }) });
  ok(bad.status === 502 && /tidak bisa dibaca/.test(bad.json.error), 'jawaban AI bukan JSON -> 502 dengan pesan jelas');

  console.log('== AI: kuota harian ==');
  const last = await call('POST', `/api/app/ai/chat?id=${ID}`, { body: JSON.stringify({ messages: [{ role: 'user', text: 'lagi' }] }) });
  ok(last.status === 200 && last.json.left === 0, 'pemakaian ke-5 berhasil, sisa 0');
  const over = await call('POST', `/api/app/ai/chat?id=${ID}`, { body: JSON.stringify({ messages: [{ role: 'user', text: 'lagi' }] }) });
  ok(over.status === 429 && /harian/.test(over.json.error), 'pemakaian ke-6 ditolak (batas harian)');

  // --- server kedua tanpa GEMINI_API_KEY ---
  console.log('== AI nonaktif ==');
  const free2 = await listen(() => {}); const P2 = free2.port; free2.s.close();
  const p2 = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], { env: { ...env, SERVER_PORT: String(P2), GEMINI_API_KEY: '', DATA_FILE: path.join(tmp, 'd2.json'), FIREBASE_SA_FILE: path.join(tmp, 'tidak-ada.json') } });
  let log2 = ''; p2.stdout.on('data', d => (log2 += d));
  for (let i = 0; i < 50 && !log2.includes('berjalan'); i++) await sleep(100);
  const n1 = await call('POST', `/api/app/ai/chat?id=${ID}`, { port: P2, body: JSON.stringify({ messages: [{ role: 'user', text: 'x' }] }) });
  ok(n1.status === 503 && /belum diaktifkan/.test(n1.json.error), 'tanpa GEMINI_API_KEY: chat = 503 dengan pesan jelas');
  ok((await call('GET', '/api/ai/status', { port: P2 })).json.enabled === false, 'status AI = nonaktif');
  ok(log2.includes('Push Firebase : mati'), 'tanpa service account: Firebase tercatat mati (server tetap jalan)');
  const stop = p => new Promise(r => { p.once('exit', r); p.kill(); });
  await Promise.all([stop(p2), stop(proc)]);
  for (const x of [O, F, G]) x.s.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(fails ? `\n${fails} UJI GAGAL` : '\nSEMUA UJI LOLOS');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error('uji error:', e); process.exit(2); });

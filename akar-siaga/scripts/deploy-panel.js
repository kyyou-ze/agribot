'use strict';
// Unggah isi folder server/ ke panel Pterodactyl lewat Client API, lalu restart server.
// Rahasia dibaca dari environment (GitHub Secrets): PTERO_URL, PTERO_CLIENT_KEY, PTERO_SERVER_ID
// Tidak pernah menimpa: data.json, config.json, firebase-service-account.json (berisi rahasia / data).
const fs = require('fs'), path = require('path');

const { PTERO_URL, PTERO_CLIENT_KEY, PTERO_SERVER_ID } = process.env;
if (!PTERO_URL || !PTERO_CLIENT_KEY || !PTERO_SERVER_ID) {
  console.error('Secret belum lengkap. Buat di GitHub: Settings > Secrets and variables > Actions:\n  PTERO_URL, PTERO_CLIENT_KEY, PTERO_SERVER_ID');
  process.exit(1);
}
const base = (/^https?:\/\//.test(PTERO_URL) ? PTERO_URL : `https://${PTERO_URL}`).replace(/\/+$/, '');
const api = `${base}/api/client/servers/${PTERO_SERVER_ID}`;
const headers = { Authorization: `Bearer ${PTERO_CLIENT_KEY}`, Accept: 'Application/vnd.pterodactyl.v1+json' };

const SRC = path.join(__dirname, '..', 'server');
const SKIP = new Set(['data.json', 'config.json', 'firebase-service-account.json', 'node_modules', '.git']);
const skip = n => SKIP.has(n) || n.endsWith('.tmp');

function walk(dir, rel = '') {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (skip(e.name)) continue;
    const r = rel ? `${rel}/${e.name}` : e.name;
    if (e.isDirectory()) out.push(...walk(path.join(dir, e.name), r));
    else out.push(r);
  }
  return out;
}

async function call(method, p, { body, json } = {}) {
  const h = { ...headers };
  if (json) h['Content-Type'] = 'application/json';
  const r = await fetch(`${api}${p}`, { method, headers: h, body: json ? JSON.stringify(json) : body, signal: AbortSignal.timeout(30000) });
  return r;
}

(async () => {
  const files = walk(SRC);
  const dirs = [...new Set(files.filter(f => f.includes('/')).flatMap(f => {
    const parts = f.split('/').slice(0, -1);
    return parts.map((_, i) => parts.slice(0, i + 1).join('/'));
  }))].sort();

  for (const d of dirs) { // folder yang sudah ada tidak masalah
    const i = d.lastIndexOf('/');
    await call('POST', '/files/create-folder', { json: { root: '/' + (i < 0 ? '' : d.slice(0, i)), name: d.slice(i + 1) } });
  }
  let n = 0;
  for (const f of files) {
    const r = await call('POST', `/files/write?file=${encodeURIComponent('/' + f)}`, { body: fs.readFileSync(path.join(SRC, f)) });
    if (!r.ok) { console.error(`GAGAL mengunggah ${f}: HTTP ${r.status}`); process.exit(1); }
    console.log(`ok  ${f}`); n++;
  }
  if (process.env.DEPLOY_RESTART === 'false') return console.log(`${n} file terunggah (tanpa restart).`);
  const r = await call('POST', '/power', { json: { signal: 'restart' } });
  if (!r.ok) { console.error(`File terunggah, tetapi restart gagal: HTTP ${r.status}`); process.exit(1); }
  console.log(`${n} file terunggah, server di-restart.`);
})().catch(e => { console.error('Deploy gagal:', e.message); process.exit(1); });

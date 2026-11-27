'use strict';
// Firebase Cloud Messaging (HTTP v1) tanpa library: JWT service account -> access token -> kirim.
const fs = require('fs'), crypto = require('crypto');
const cfg = require('./config');

let sa = null;
let tok = { v: '', exp: 0 };

function loadSa() {
  if (sa !== null) return sa;
  try {
    const j = JSON.parse(fs.readFileSync(cfg.FIREBASE_SA_FILE, 'utf8'));
    sa = j.client_email && j.private_key && j.project_id ? j : false;
  } catch { sa = false; }
  return sa;
}
const enabled = () => !!loadSa();
const b64u = s => Buffer.from(s).toString('base64url');

async function accessToken() {
  if (tok.v && Date.now() < tok.exp - 60000) return tok.v;
  const s = loadSa(), iat = Math.floor(Date.now() / 1000);
  const head = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64u(JSON.stringify({
    iss: s.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: cfg.FCM_TOKEN_URL, iat, exp: iat + 3600,
  }));
  const sig = crypto.createSign('RSA-SHA256').update(`${head}.${claim}`).sign(s.private_key, 'base64url');
  const r = await fetch(cfg.FCM_TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${head}.${claim}.${sig}` }),
    signal: AbortSignal.timeout(10000),
  });
  if (!r.ok) throw new Error('oauth ' + r.status);
  const j = await r.json();
  tok = { v: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000 };
  return tok.v;
}

/** Kirim ke satu token. dead=true bila token sudah tidak berlaku (harus dihapus). */
async function send(token, title, body) {
  try {
    const at = await accessToken();
    const r = await fetch(`${cfg.FCM_API_BASE}/v1/projects/${loadSa().project_id}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${at}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        message: {
          token, notification: { title, body },
          android: { priority: 'HIGH', notification: { channel_id: 'akarsiaga_push' } },
        },
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (r.ok) return { ok: true };
    const t = await r.text();
    return { ok: false, dead: r.status === 404 || t.includes('UNREGISTERED') };
  } catch { return { ok: false }; }
}

module.exports = { enabled, send };

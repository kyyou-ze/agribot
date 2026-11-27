'use strict';
// Penyimpanan sederhana: satu file JSON (data.json) yang disimpan berkala.
const fs = require('fs');
const cfg = require('./config');

let db = {};
try { db = JSON.parse(fs.readFileSync(cfg.DATA_FILE, 'utf8')); } catch {}
const rt = {}; // data sementara (tidak disimpan)
const now = () => Math.floor(Date.now() / 1000);

function dev(id) {
  const d = (db[id] ||= {
    ts: 0, online: false, status: '', extra: [], q: [], samples: [], events: [], lastSample: 0, lastDry: 0,
    notify: { ntfy: '', tg: '', w: true, p: true, d: true, o: true },
  });
  d.tokens ||= [];            // token Firebase (HP yang terdaftar)
  d.ai ||= { day: '', n: 0 }; // kuota AI harian
  return d;
}

function save() {
  try {
    fs.writeFileSync(cfg.DATA_FILE + '.tmp', JSON.stringify(db));
    fs.renameSync(cfg.DATA_FILE + '.tmp', cfg.DATA_FILE);
  } catch (e) { console.error('gagal menyimpan:', e.message); }
}

module.exports = { db, rt, now, dev, save };

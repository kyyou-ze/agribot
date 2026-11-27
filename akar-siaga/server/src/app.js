'use strict';
const http = require('http');
const cfg = require('./config');
const { save } = require('./store');
const handle = require('./routes');
const { startWatchdog } = require('./device');
const fcm = require('./fcm');

function start() {
  if (cfg.API_KEY.length < 8) {
    console.error('API_KEY wajib diisi (minimal 8 karakter): lewat variabel environment atau config.json');
    process.exit(1);
  }
  const server = http.createServer((req, res) => {
    handle(req, res).catch(e => {
      console.error('error:', e.message);
      try { res.writeHead(500); res.end('error'); } catch {}
    });
  });
  server.listen(cfg.PORT, () => {
    console.log(`Akar Siaga server berjalan di port ${cfg.PORT}`);
    console.log(`  Push Firebase : ${fcm.enabled() ? 'aktif' : 'mati (file firebase-service-account.json tidak ada)'}`);
    console.log(`  Telegram      : ${cfg.TG_BOT_TOKEN ? 'aktif' : 'mati'}`);
    console.log(`  AI Gemini     : ${cfg.GEMINI_API_KEY ? `aktif (model ${cfg.GEMINI_MODEL}, ${cfg.AI_DAILY_LIMIT}x/hari per alat)` : 'mati (GEMINI_API_KEY kosong)'}`);
  });
  startWatchdog();
  setInterval(save, 30000);
  for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => { save(); process.exit(0); });
}

module.exports = { start };

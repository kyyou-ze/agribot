'use strict';
// Satu pintu untuk semua saluran notifikasi: ntfy, Telegram, dan Firebase (push ke aplikasi).
const cfg = require('./config');
const fcm = require('./fcm');

async function pushTo(d, title, body) {
  const n = d.notify, jobs = [];
  if (n.ntfy) {
    jobs.push(fetch(`${cfg.NTFY_SERVER}/${encodeURIComponent(n.ntfy)}`, {
      method: 'POST', body, headers: { Title: title, Priority: 'high', Tags: 'seedling' },
    }));
  }
  if (n.tg && cfg.TG_BOT_TOKEN) {
    jobs.push(fetch(`https://api.telegram.org/bot${cfg.TG_BOT_TOKEN}/sendMessage`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ chat_id: n.tg, text: `🌱 ${title}\n${body}` }),
    }));
  }
  if (fcm.enabled()) {
    for (const t of d.tokens) {
      jobs.push(fcm.send(t, title, body).then(r => {
        if (r.dead) d.tokens = d.tokens.filter(x => x !== t);
        return r;
      }));
    }
  }
  const r = await Promise.allSettled(jobs);
  return `${r.filter(x => x.status === 'fulfilled' && x.value.ok).length}/${r.length}`;
}

module.exports = { pushTo };

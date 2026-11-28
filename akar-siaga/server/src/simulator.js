'use strict';
// Simulator alat virtual ("Mode uji"): dipakai saat alat asli belum jadi.
// Memakai jalur yang SAMA dengan alat asli (ingest -> deteksi kejadian -> push -> AI),
// jadi seluruh aplikasi bisa diuji dari ujung ke ujung. Aktifkan dengan SIMULATOR=1.
const cfg = require('./config');
const { ingest } = require('./device');

const ID = 'AkarSiaga-DEMO';
const RAW_DRY = 3000, RAW_WET = 1300, TANK_ML = 2000;
const RANGE = { manrun: [5, 60], maxday: [0, 50], skip: [40, 100], flow: [1, 500], buzz: [0, 1], qs: [0, 23], qe: [0, 23], fpol: [0, 1], hT: [0, 60], hB: [0, 40], dht: [11, 22], cloud: [0, 1] };
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const enabled = () => cfg.SIMULATOR;

function fresh() {
  return {
    soil: 62, tank: 100, pump: false, pumpLeft: 0, auto: true, min: 55, run: 5, wait: 60,
    c: { manrun: 30, maxday: 0, skip: 85, flow: 30, buzz: 1, qs: 22, qe: 6, fpol: 0, hT: 0, hB: 10, dht: 22, cloud: 1 },
    name: 'Akar Siaga (uji)', temp: 28, hum: 70,
    sched: [0, 1, 2, 3].map(i => ({ en: 0, h: 6 + i * 4, m: 0, dur: 5, days: 127 })),
    tz: 25200, tot: 0, dayCount: 0, dayKey: -1, sinceRun: 1e9, hasRun: false, lastMin: -1,
    ineffectiveUntil: 0, offlineUntil: 0,
  };
}
let st = fresh(), timer = null, tickAt = Date.now();

const waterOk = () => st.tank > 0;
const effMin = () => clamp(st.min + (st.c.hT > 0 && st.temp >= st.c.hT ? st.c.hB : 0), 5, 98);

function startPump(sec, counted) {
  if (!waterOk() || st.pump) return;
  st.pump = true; st.pumpLeft = sec;
  if (counted) st.dayCount++;
}
function stopPump() {
  if (!st.pump) return;
  st.pump = false; st.pumpLeft = 0; st.sinceRun = 0; st.hasRun = true;
}

function envNow() { // suhu/kelembaban udara mengikuti jam (puncak ±15.00)
  const t = new Date(Date.now() + st.tz * 1000);
  const h = t.getUTCHours() + t.getUTCMinutes() / 60;
  const temp = 28 + 6 * Math.sin(((h - 9) / 24) * 2 * Math.PI) + (Math.random() - 0.5) * 0.6;
  return { t, temp, hum: clamp(72 - (temp - 28) * 2.2 + (Math.random() - 0.5) * 2, 30, 95) };
}

function checkSched(t) {
  const minute = Math.floor((Date.now() + st.tz * 1000) / 60000);
  if (minute === st.lastMin) return;
  st.lastMin = minute;
  if (!st.auto || st.soil >= st.c.skip) return;
  const s = st.sched.find(x => x.en && x.h === t.getUTCHours() && x.m === t.getUTCMinutes() && ((x.days >> t.getUTCDay()) & 1));
  if (s) startPump(s.dur, true);
}

function tick(dt) {
  const e = envNow();
  st.temp = e.temp; st.hum = e.hum;
  st.soil = clamp(st.soil - (0.8 / 60) * dt * cfg.SIM_SPEED * (1 + Math.max(0, st.temp - 28) * 0.08), 0, 100); // penguapan
  st.sinceRun += dt;
  const dk = Math.floor((Date.now() + st.tz * 1000) / 86400000);
  if (dk !== st.dayKey) { st.dayKey = dk; st.dayCount = 0; }
  if (st.pump) {
    st.pumpLeft -= dt; st.tot += dt;
    st.tank = Math.max(0, st.tank - (dt * st.c.flow) / (TANK_ML / 100));
    if (Date.now() >= st.ineffectiveUntil) st.soil = Math.min(100, st.soil + dt * 2.5 * (st.c.flow / 30));
    if (!waterOk() || st.pumpLeft <= 0) stopPump();
  } else if (st.auto && st.soil < effMin() && waterOk() && (!st.hasRun || st.sinceRun >= st.wait) && (st.c.maxday === 0 || st.dayCount < st.c.maxday)) {
    startPump(st.run, true);
  }
  checkSched(e.t);
}

function lines() {
  const raw = Math.round(RAW_DRY - (st.soil * (RAW_DRY - RAW_WET)) / 100);
  const status = [Math.round(st.soil), raw, st.temp.toFixed(1), Math.round(st.hum), waterOk() ? 1 : 0, st.pump ? 1 : 0,
    st.auto ? 'A' : 'M', st.min, st.run, st.wait, 'S', 1, Math.max(0, Math.ceil(st.pumpLeft)), effMin(), 1].join(',');
  const c = st.c;
  return [status, ...st.sched.map((x, i) => `S:${i},${x.en},${x.h},${x.m},${x.dur},${x.days}`),
    `C:id=${ID};name=${st.name};manrun=${c.manrun};maxday=${c.maxday};skip=${c.skip};flow=${c.flow};buzz=${c.buzz};qs=${c.qs};qe=${c.qe};` +
    `fpol=${c.fpol};hT=${c.hT};hB=${c.hB};dht=${c.dht};cloud=${c.cloud};tot=${Math.round(st.tot)};dc=${st.dayCount}`];
}

function apply(cmd) { // meniru perintah firmware
  if (cmd === 'M:A') st.auto = true;
  else if (cmd === 'M:M') { st.auto = false; stopPump(); }
  else if (cmd === 'P:1') startPump(st.c.manrun, false);
  else if (cmd === 'P:0') stopPump();
  else if (cmd.startsWith('T:')) {
    const [a, b, c] = cmd.slice(2).split(',').map(Number);
    if ([a, b, c].every(Number.isFinite)) { st.min = clamp(a, 5, 95); st.run = clamp(b, 1, 30); st.wait = clamp(c, 10, 600); }
  } else if (cmd.startsWith('S:')) {
    const [i, en, h, m, d, k] = cmd.slice(2).split(',').map(Number);
    if ([i, en, h, m, d, k].every(Number.isFinite) && i >= 0 && i < 4) st.sched[i] = { en: en ? 1 : 0, h: clamp(h, 0, 23), m: clamp(m, 0, 59), dur: clamp(d, 1, 60), days: k & 127 };
  } else if (cmd.startsWith('Z:')) {
    const o = Number(cmd.slice(2).split(',')[1]);
    if (Number.isFinite(o)) st.tz = o;
  } else if (cmd.startsWith('C:')) {
    const i = cmd.indexOf('=');
    const k = cmd.slice(2, i), v = cmd.slice(i + 1);
    if (k === 'name') st.name = v.replace(/[;=,]/g, '').trim().slice(0, 20) || st.name;
    else if (RANGE[k] && Number.isFinite(+v)) st.c[k] = clamp(Math.round(+v), ...RANGE[k]);
  } else if (cmd === 'R:F' || cmd === 'R:1') {
    if (cmd === 'R:F') st = fresh();
  } // K:D / K:W / W: / V: / N: : tidak berlaku untuk alat virtual
}

function scenario(name, secs) {
  switch (name) {
    case 'tank_empty': st.tank = 0; stopPump(); break;
    case 'refill': st.tank = 100; break;
    case 'dry': st.soil = Math.min(st.soil, Math.max(5, st.min - 25)); break;
    case 'wet': st.soil = 92; break;
    case 'ineffective': // selang lepas: pompa jalan tapi tanah tidak basah
      st.ineffectiveUntil = Date.now() + 10 * 60000; st.soil = Math.min(st.soil, Math.max(5, st.min - 20)); st.sinceRun = 1e9; break;
    case 'offline': st.offlineUntil = Date.now() + (secs > 0 ? secs : 120) * 1000; break;
    case 'reset': st = fresh(); break;
    default: return { ok: false, error: 'Skenario tidak dikenal.' };
  }
  return { ok: true, name };
}

function start() {
  if (timer) return;
  const sync = () => {
    const now = Date.now(), dt = Math.min(5, (now - tickAt) / 1000);
    tickAt = now;
    tick(dt);
    if (now < st.offlineUntil) return; // pura-pura mati: tidak mengirim data
    for (const c of ingest(ID, lines())) apply(c);
  };
  sync();
  timer = setInterval(sync, cfg.SIM_TICK_MS);
}
function stop() { clearInterval(timer); timer = null; }

module.exports = { ID, enabled, start, stop, scenario };

'use strict';
// Semua pengaturan dibaca dari variabel environment, atau dari config.json (salin config.example.json).
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');

let file = {};
try { file = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8')); } catch {}
const env = (k, d = '') => String(process.env[k] || file[k] || d);

module.exports = {
  PORT: +env('SERVER_PORT') || +env('PORT') || 3000,
  API_KEY: env('API_KEY'),
  DATA_FILE: path.resolve(ROOT, env('DATA_FILE', 'data.json')),
  // notifikasi
  TG_BOT_TOKEN: env('TG_BOT_TOKEN'),
  NTFY_SERVER: env('NTFY_SERVER', 'https://ntfy.sh').replace(/\/+$/, ''),
  FIREBASE_SA_FILE: path.resolve(ROOT, env('FIREBASE_SA_FILE', 'firebase-service-account.json')),
  FCM_TOKEN_URL: env('FCM_TOKEN_URL', 'https://oauth2.googleapis.com/token'),
  FCM_API_BASE: env('FCM_API_BASE', 'https://fcm.googleapis.com').replace(/\/+$/, ''),
  // AI (Google AI Studio / Gemini)
  GEMINI_API_KEY: env('GEMINI_API_KEY'),
  GEMINI_MODEL: env('GEMINI_MODEL', 'gemini-flash-latest'),
  GEMINI_BASE: env('GEMINI_BASE', 'https://generativelanguage.googleapis.com').replace(/\/+$/, ''),
  AI_DAILY_LIMIT: +env('AI_DAILY_LIMIT', '30') || 30,
};

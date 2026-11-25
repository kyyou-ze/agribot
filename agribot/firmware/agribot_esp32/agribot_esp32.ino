// AgriBot v3 - ESP32 DevKit V1 (tanpa Bluetooth)
// Jaringan: AP  = alat membuat WiFi "AgriBot-XXXX" (default, sandi agribot123)
//           STA = masuk WiFi router; bila server diisi, data disinkronkan ke server (Cloud)
// Library: "DHT sensor library" + "Adafruit Unified Sensor". Sisanya bawaan core ESP32.
// Bila muncul "Sketch too big": Tools > Partition Scheme > "Huge APP (3MB No OTA/1MB SPIFFS)"
#include <WiFi.h>
#include <WebServer.h>
#include <WiFiUdp.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Preferences.h>
#include <sys/time.h>

// ---------- PIN ----------
#define PIN_SOIL   34
#define PIN_RELAY  26   // relay low trigger
#define PIN_FLOAT  27   // float switch ke GND
#define PIN_DHT    4
#define PIN_BUZZER 25
#define PIN_LED    2
#define PIN_BTN    13   // push button ke GND
#define MAX_PUMP_MS 60000UL

enum { NET_AP = 1, NET_STA = 2 };
struct Sched { uint8_t en, h, m, dur, days; };   // days: bit0=Minggu ... bit6=Sabtu

DHT *dht;
Preferences prefs;
WebServer server(80);
WiFiUDP udp;

int netMode = NET_AP, activeNet = NET_AP;
String staSsid, staPass, apSsid, apPass = "agribot123", devName = "AgriBot", cloudUrl, cloudKey;
long tzOff = 25200;
Sched sch[4];
long lastSchedKey = -1;
unsigned long restartAt = 0;

bool autoMode = true, pumpOn = false, sensorOk = true, hasRun = false;
int minSoil = 55, runSec = 5, waitSec = 60, rawDry = 3000, rawWet = 1300;
// pengaturan (bisa diubah dari aplikasi)
int manRun = 30, maxDay = 0, skipAbove = 85, flowMl = 30, buzzOn = 1, qs = 22, qe = 6;
int fpol = 0, hT = 0, hB = 10, dhtType = 11, cloudOn = 0;
unsigned long totSec = 0;
int dayCount = 0; long dayKey = -1;
volatile int cloudState = 0;                      // 0 mati, 1 tersambung, 2 gagal

int soilPct = 0, rawSoil = 0, hum = 0;
float temp = -99;
unsigned long pumpStart = 0, pumpLimit = 0, lastRun = 0, lastSense = 0, lastBeep = 0;

void handleCmd(String s);

bool timeOk() { return time(nullptr) > 1700000000; }
bool waterOk() { return digitalRead(PIN_FLOAT) == (fpol ? HIGH : LOW); }

bool quiet() {
  if (qs == qe || !timeOk()) return false;
  time_t t = time(nullptr) + tzOff; struct tm tm; gmtime_r(&t, &tm);
  int h = tm.tm_hour;
  return qs < qe ? (h >= qs && h < qe) : (h >= qs || h < qe);
}
void beepRaw(int n, int ms) {
  if (!buzzOn) return;
  for (int i = 0; i < n; i++) { digitalWrite(PIN_BUZZER, HIGH); delay(ms); digitalWrite(PIN_BUZZER, LOW); delay(ms); }
}
void alarmBeep(int n, int ms) { if (!quiet()) beepRaw(n, ms); }

int effMin() {                                     // "smart panas": batas siram naik saat suhu tinggi
  int m = minSoil;
  if (hT > 0 && temp > -50 && temp >= hT) m += hB;
  return constrain(m, 5, 98);
}

void saveCfg() {
  prefs.putInt("min", minSoil); prefs.putInt("run", runSec); prefs.putInt("wait", waitSec);
  prefs.putInt("dry", rawDry); prefs.putInt("wet", rawWet); prefs.putBool("auto", autoMode);
  prefs.putInt("manrun", manRun); prefs.putInt("maxday", maxDay); prefs.putInt("skip", skipAbove);
  prefs.putInt("flow", flowMl); prefs.putInt("buzz", buzzOn); prefs.putInt("qs", qs); prefs.putInt("qe", qe);
  prefs.putInt("fpol", fpol); prefs.putInt("hT", hT); prefs.putInt("hB", hB); prefs.putInt("dht", dhtType);
  prefs.putInt("cloud", cloudOn);
}

void loadCfg() {
  prefs.begin("agribot", false);
  minSoil = prefs.getInt("min", 55); runSec = prefs.getInt("run", 5); waitSec = prefs.getInt("wait", 60);
  rawDry = prefs.getInt("dry", 3000); rawWet = prefs.getInt("wet", 1300); autoMode = prefs.getBool("auto", true);
  manRun = prefs.getInt("manrun", 30); maxDay = prefs.getInt("maxday", 0); skipAbove = prefs.getInt("skip", 85);
  flowMl = prefs.getInt("flow", 30); buzzOn = prefs.getInt("buzz", 1); qs = prefs.getInt("qs", 22); qe = prefs.getInt("qe", 6);
  fpol = prefs.getInt("fpol", 0); hT = prefs.getInt("hT", 0); hB = prefs.getInt("hB", 10);
  dhtType = prefs.getInt("dht", 11); cloudOn = prefs.getInt("cloud", 0); totSec = prefs.getULong("tot", 0);
  netMode = prefs.getInt("net", NET_AP); if (netMode != NET_STA) netMode = NET_AP;
  staSsid = prefs.getString("ssid", ""); staPass = prefs.getString("pass", "");
  devName = prefs.getString("name", "AgriBot"); apPass = prefs.getString("apw", "agribot123");
  cloudUrl = prefs.getString("curl", ""); cloudKey = prefs.getString("ckey", "");
  if (prefs.getBytesLength("sch") == sizeof(sch)) prefs.getBytes("sch", sch, sizeof(sch));
  else for (int i = 0; i < 4; i++) sch[i] = Sched{0, (uint8_t)(6 + i * 4), 0, 5, 127};
}

void setPump(bool on, unsigned long limitMs) {
  if (on && !waterOk()) return;
  if (on && !pumpOn) { pumpStart = millis(); pumpLimit = limitMs; }
  if (!on && pumpOn) {
    lastRun = millis(); hasRun = true;
    totSec += (millis() - pumpStart) / 1000; prefs.putULong("tot", totSec);
  }
  pumpOn = on;
  digitalWrite(PIN_RELAY, on ? LOW : HIGH);
  digitalWrite(PIN_LED, on ? HIGH : LOW);
}

void autoStart(unsigned long ms) {                 // penyiraman otomatis/jadwal, dibatasi per hari
  if (maxDay > 0 && dayCount >= maxDay) return;
  setPump(true, ms);
  if (pumpOn) dayCount++;
}

// ---------- Format data (dipakai lokal & cloud) ----------
String schedLine(int i) {
  char b[32];
  snprintf(b, sizeof(b), "S:%d,%d,%d,%d,%d,%d", i, sch[i].en, sch[i].h, sch[i].m, sch[i].dur, sch[i].days);
  return String(b);
}
String statusLine() {
  char b[112];
  unsigned long el = millis() - pumpStart;
  unsigned long rem = (pumpOn && pumpLimit > el) ? (pumpLimit - el) / 1000 : 0;
  snprintf(b, sizeof(b), "%d,%d,%.1f,%d,%d,%d,%c,%d,%d,%d,%c,%d,%lu,%d,%d",
           soilPct, rawSoil, temp, hum, waterOk() ? 1 : 0, pumpOn ? 1 : 0, autoMode ? 'A' : 'M',
           minSoil, runSec, waitSec, "?AS"[activeNet], timeOk() ? 1 : 0, rem, effMin(), (int)cloudState);
  return String(b);
}
String cfgLine() {
  char b[300];
  snprintf(b, sizeof(b),
           "C:id=%s;name=%s;manrun=%d;maxday=%d;skip=%d;flow=%d;buzz=%d;qs=%d;qe=%d;fpol=%d;hT=%d;hB=%d;dht=%d;cloud=%d;tot=%lu;dc=%d",
           apSsid.c_str(), devName.c_str(), manRun, maxDay, skipAbove, flowMl, buzzOn, qs, qe, fpol, hT, hB,
           dhtType, cloudOn, totSec, dayCount);
  return String(b);
}
String allLines() {
  String s = statusLine(); s += '\n';
  for (int i = 0; i < 4; i++) { s += schedLine(i); s += '\n'; }
  s += cfgLine();
  return s;
}

// ---------- Perintah ----------
// M:A/M:M mode | P:1/P:0 pompa | T:min,siram,jeda | K:D/K:W kalibrasi | S:i,en,h,m,dur,hari
// Z:epoch,offset sinkron jam | W:ssid<TAB>pass | V:url<TAB>kunci | N:A/N:S jaringan | C:kunci=nilai pengaturan
// R:1 restart | R:F reset pengaturan
void setCfg(String k, String v) {
  int n = v.toInt();
  if (k == "name") {
    v.replace(";", ""); v.replace("=", ""); v.replace(",", ""); v.trim();
    if (v.length() == 0) return;
    devName = v.substring(0, 20); prefs.putString("name", devName); return;
  }
  if (k == "apw") { if (v.length() >= 8 && v.length() <= 32) { apPass = v; prefs.putString("apw", v); } return; }
  if (k == "manrun") manRun = constrain(n, 5, 60);
  else if (k == "maxday") maxDay = constrain(n, 0, 50);
  else if (k == "skip") skipAbove = constrain(n, 40, 100);
  else if (k == "flow") flowMl = constrain(n, 1, 500);
  else if (k == "buzz") buzzOn = n ? 1 : 0;
  else if (k == "qs") qs = constrain(n, 0, 23);
  else if (k == "qe") qe = constrain(n, 0, 23);
  else if (k == "fpol") fpol = n ? 1 : 0;
  else if (k == "hT") hT = constrain(n, 0, 60);
  else if (k == "hB") hB = constrain(n, 0, 40);
  else if (k == "dht") dhtType = (n == 22) ? 22 : 11;
  else if (k == "cloud") cloudOn = n ? 1 : 0;
  else return;
  saveCfg();
}

void handleCmd(String s) {
  s.trim();
  if (s == "M:A") autoMode = true;
  else if (s == "M:M") { autoMode = false; setPump(false, 0); }
  else if (s == "P:1") setPump(true, (unsigned long)manRun * 1000UL);
  else if (s == "P:0") setPump(false, 0);
  else if (s == "K:D") rawDry = rawSoil;
  else if (s == "K:W") rawWet = rawSoil;
  else if (s.startsWith("T:")) {
    int a, b, c;
    if (sscanf(s.c_str() + 2, "%d,%d,%d", &a, &b, &c) == 3) {
      minSoil = constrain(a, 5, 95); runSec = constrain(b, 1, 30); waitSec = constrain(c, 10, 600);
    }
  } else if (s.startsWith("C:")) {
    int i = s.indexOf('=');
    if (i > 2) setCfg(s.substring(2, i), s.substring(i + 1));
    return;
  } else if (s.startsWith("S:")) {
    int i, e, h, m, d, k;
    if (sscanf(s.c_str() + 2, "%d,%d,%d,%d,%d,%d", &i, &e, &h, &m, &d, &k) == 6 && i >= 0 && i < 4) {
      sch[i] = Sched{(uint8_t)(e ? 1 : 0), (uint8_t)constrain(h, 0, 23), (uint8_t)constrain(m, 0, 59),
                     (uint8_t)constrain(d, 1, 60), (uint8_t)(k & 127)};
      prefs.putBytes("sch", sch, sizeof(sch));
    }
    return;
  } else if (s.startsWith("Z:")) {
    long long e; long o;
    if (sscanf(s.c_str() + 2, "%lld,%ld", &e, &o) == 2) {
      struct timeval tv; tv.tv_sec = (time_t)e; tv.tv_usec = 0;
      settimeofday(&tv, NULL); tzOff = o;
    }
    return;
  } else if (s.startsWith("W:")) {
    String b = s.substring(2); int i = b.indexOf('\t');
    staSsid = (i < 0) ? b : b.substring(0, i);
    staPass = (i < 0) ? "" : b.substring(i + 1);
    prefs.putString("ssid", staSsid); prefs.putString("pass", staPass);
    return;
  } else if (s.startsWith("V:")) {
    String b = s.substring(2); int i = b.indexOf('\t');
    cloudUrl = (i < 0) ? b : b.substring(0, i);
    cloudKey = (i < 0) ? "" : b.substring(i + 1);
    while (cloudUrl.endsWith("/")) cloudUrl.remove(cloudUrl.length() - 1);
    prefs.putString("curl", cloudUrl); prefs.putString("ckey", cloudKey);
    return;
  } else if (s.startsWith("N:")) {
    char m = s.charAt(2);
    if (m == 'A' || m == 'S') { prefs.putInt("net", m == 'A' ? NET_AP : NET_STA); restartAt = millis() + 800; }
    return;
  } else if (s == "R:1") { restartAt = millis() + 500; return; }
  else if (s == "R:F") { prefs.clear(); restartAt = millis() + 500; return; }
  else return;
  saveCfg();
}

// ---------- Jaringan ----------
void startWeb() {
  server.on("/api/all", []() { server.send(200, "text/plain", allLines()); });
  server.on("/api/status", []() { server.send(200, "text/plain", statusLine()); });
  server.on("/api/cmd", []() { handleCmd(server.arg("c")); server.send(200, "text/plain", "OK"); });
  server.begin();
  udp.begin(4210);
}

void startAp() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(apSsid.c_str(), apPass.c_str());
  activeNet = NET_AP;
  startWeb();
}

void startSta() {
  if (staSsid.length() == 0) { beepRaw(3, 100); startAp(); return; }
  WiFi.mode(WIFI_STA);
  WiFi.begin(staSsid.c_str(), staPass.c_str());
  unsigned long t = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t < 15000) { delay(250); digitalWrite(PIN_LED, !digitalRead(PIN_LED)); }
  digitalWrite(PIN_LED, LOW);
  if (WiFi.status() == WL_CONNECTED) {
    activeNet = NET_STA;
    configTime(0, 0, "pool.ntp.org", "time.google.com");
    startWeb();
  } else {
    beepRaw(3, 100);                               // gagal -> cadangan: hotspot sendiri
    WiFi.disconnect(true);
    startAp();
  }
}

void udpLoop() {                                   // aplikasi mencari alat lewat broadcast "AGRIBOT?"
  int n = udp.parsePacket();
  if (n <= 0) return;
  char b[16] = {0};
  udp.read(b, n < 15 ? n : 15);
  if (strncmp(b, "AGRIBOT?", 8) != 0) return;
  IPAddress ip = (activeNet == NET_AP) ? WiFi.softAPIP() : WiFi.localIP();
  udp.beginPacket(udp.remoteIP(), udp.remotePort());
  udp.print("AGRIBOT," + ip.toString());
  udp.endPacket();
}

// ---------- Cloud (task terpisah agar kontrol pompa tidak terblokir) ----------
bool cloudSync() {
  String url = cloudUrl + "/api/device/sync";
  HTTPClient http;
  WiFiClientSecure sc;
  WiFiClient pc;
  if (url.startsWith("https")) { sc.setInsecure(); http.begin(sc, url); }   // TLS tanpa verifikasi sertifikat
  else http.begin(pc, url);
  http.setTimeout(4000);
  http.addHeader("x-api-key", cloudKey);
  http.addHeader("x-device-id", apSsid);
  http.addHeader("Content-Type", "text/plain");
  int code = http.POST(allLines());
  if (code == 200) {
    String resp = http.getString();
    int st = 0;
    while (st < (int)resp.length()) {
      int e = resp.indexOf('\n', st);
      if (e < 0) e = resp.length();
      String l = resp.substring(st, e); l.trim();
      if (l.length()) handleCmd(l);
      st = e + 1;
    }
  }
  http.end();
  return code == 200;
}

void cloudTask(void *) {
  for (;;) {
    if (cloudOn && activeNet == NET_STA && cloudUrl.length() > 8 && WiFi.status() == WL_CONNECTED) {
      bool ok = cloudSync();
      cloudState = ok ? 1 : 2;
      vTaskDelay((ok ? 2000 : 8000) / portTICK_PERIOD_MS);
    } else {
      cloudState = 0;
      vTaskDelay(1000 / portTICK_PERIOD_MS);
    }
  }
}

// ---------- Sensor & kontrol ----------
void readSensors() {
  long sum = 0;
  for (int i = 0; i < 16; i++) { sum += analogRead(PIN_SOIL); delay(2); }
  rawSoil = sum / 16;
  sensorOk = rawSoil > 200 && rawSoil < 4000;
  soilPct = (rawDry == rawWet) ? 0 : constrain(map(rawSoil, rawDry, rawWet, 0, 100), 0, 100);
  float t = dht->readTemperature(), h = dht->readHumidity();
  if (!isnan(t)) temp = t;
  if (!isnan(h)) hum = (int)h;
}

void control() {
  unsigned long now = millis();
  long dk = timeOk() ? (time(nullptr) + tzOff) / 86400 : (long)(now / 86400000UL);
  if (dk != dayKey) { dayKey = dk; dayCount = 0; }
  if (pumpOn) {
    if (!waterOk() || now - pumpStart >= pumpLimit || now - pumpStart >= MAX_PUMP_MS) setPump(false, 0);
  } else if (autoMode && sensorOk && waterOk() && soilPct < effMin() &&
             (!hasRun || now - lastRun >= (unsigned long)waitSec * 1000UL)) {
    autoStart((unsigned long)runSec * 1000UL);
  }
}

void checkSched() {
  if (!timeOk()) return;
  time_t t = time(nullptr) + tzOff;
  struct tm tm; gmtime_r(&t, &tm);
  long key = (long)tm.tm_yday * 1440 + tm.tm_hour * 60 + tm.tm_min;
  if (key == lastSchedKey) return;                 // sekali per menit
  lastSchedKey = key;
  if (!autoMode || !sensorOk || soilPct >= skipAbove) return;
  for (int i = 0; i < 4; i++) {
    if (sch[i].en && sch[i].h == tm.tm_hour && sch[i].m == tm.tm_min && ((sch[i].days >> tm.tm_wday) & 1)) {
      autoStart((unsigned long)sch[i].dur * 1000UL);
      break;
    }
  }
}

void alarms() {
  if (!waterOk()) {
    if (!pumpOn) digitalWrite(PIN_LED, (millis() / 500) % 2);
    if (millis() - lastBeep > 10000) { lastBeep = millis(); alarmBeep(2, 150); }
  } else if (!pumpOn) digitalWrite(PIN_LED, LOW);
}

// Singkat = ganti Auto/Manual | tahan 1-3 dtk = pompa | tahan >3 dtk = ganti jaringan (Hotspot <-> Router)
void button() {
  static bool last = HIGH; static unsigned long t0 = 0;
  bool now = digitalRead(PIN_BTN);
  if (last == HIGH && now == LOW) t0 = millis();
  if (last == LOW && now == HIGH) {
    unsigned long d = millis() - t0;
    if (d > 50 && d < 800) { autoMode = !autoMode; if (!autoMode) setPump(false, 0); saveCfg(); beepRaw(1, 60); }
    else if (d >= 800 && d < 3000) { setPump(!pumpOn, (unsigned long)manRun * 1000UL); beepRaw(1, 200); }
    else if (d >= 3000) { prefs.putInt("net", netMode == NET_AP ? NET_STA : NET_AP); beepRaw(3, 80); restartAt = millis() + 300; }
  }
  last = now;
}

void setup() {
  pinMode(PIN_RELAY, OUTPUT); digitalWrite(PIN_RELAY, HIGH);   // pompa OFF
  pinMode(PIN_BUZZER, OUTPUT); pinMode(PIN_LED, OUTPUT);
  pinMode(PIN_FLOAT, INPUT_PULLUP); pinMode(PIN_BTN, INPUT_PULLUP);
  analogReadResolution(12);
  analogSetPinAttenuation(PIN_SOIL, ADC_11db);
  loadCfg();
  dht = new DHT(PIN_DHT, dhtType);
  dht->begin();
  char nm[24];
  snprintf(nm, sizeof(nm), "AgriBot-%04X", (uint16_t)(ESP.getEfuseMac() >> 32));
  apSsid = String(nm);

  if (netMode == NET_STA) startSta(); else startAp();
  xTaskCreatePinnedToCore(cloudTask, "cloud", 12288, NULL, 1, NULL, 0);

  readSensors();
  beepRaw(activeNet, 80);                          // 1 bip = Hotspot, 2 bip = Router
}

void loop() {
  button(); control(); alarms(); checkSched();
  if (millis() - lastSense >= 2000) { lastSense = millis(); readSensors(); }
  server.handleClient();
  udpLoop();
  if (restartAt && millis() > restartAt) ESP.restart();
  delay(20);
}

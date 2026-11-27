#!/usr/bin/env python3
"""Uji patch_android.py pada proyek Android tiruan (Kotlin DSL & Groovy). Jalankan: python3 scripts/test_patch_android.py"""
import json, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "patch_android.py")
PKG = re.search(r'PACKAGE = "([^"]+)"', open(SCRIPT).read()).group(1)

MANIFEST = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <application\n        android:label="x"\n        android:name="${applicationName}">\n    </application>\n</manifest>\n'
APP = {"kts": 'plugins {\n    id("com.android.application")\n    id("kotlin-android")\n}\nandroid {\n    compileOptions {\n        sourceCompatibility = JavaVersion.VERSION_11\n    }\n    defaultConfig {\n        minSdk = flutter.minSdkVersion\n    }\n}\n',
       "grv": 'plugins {\n    id "com.android.application"\n    id "kotlin-android"\n}\nandroid {\n    compileOptions {\n        sourceCompatibility JavaVersion.VERSION_1_8\n    }\n    defaultConfig {\n        minSdkVersion flutter.minSdkVersion\n    }\n}\n'}
SET = {"kts": 'plugins {\n    id("com.android.application") version "8.7.3" apply false\n}\n',
       "grv": 'plugins {\n    id "com.android.application" version "8.1.0" apply false\n}\n'}
gs = lambda pkg: json.dumps({"client": [{"client_info": {"android_client_info": {"package_name": pkg}}}]})

def build(kind, google=None, settings=None):
    d = tempfile.mkdtemp(); sfx = ".kts" if kind == "kts" else ""
    os.makedirs(f"{d}/android/app/src/main")
    open(f"{d}/android/app/src/main/AndroidManifest.xml", "w").write(MANIFEST)
    open(f"{d}/android/app/build.gradle{sfx}", "w").write(APP[kind])
    open(f"{d}/android/settings.gradle{sfx}", "w").write(settings or SET[kind])
    if google is not None: open(f"{d}/android/app/google-services.json", "w").write(google)
    return d

def run(d, *f): return subprocess.run([sys.executable, SCRIPT, d, *f], capture_output=True, text=True)
def read(d, kind):
    s = ".kts" if kind == "kts" else ""
    return [open(p).read() for p in (f"{d}/android/app/src/main/AndroidManifest.xml", f"{d}/android/app/build.gradle{s}", f"{d}/android/settings.gradle{s}")]

fails = 0
def check(name, cond, extra=""):
    global fails
    print(("PASS  " if cond else "FAIL  ") + name + (f"  [{extra.strip()}]" if not cond and extra else ""))
    fails += (not cond)

for kind in ("kts", "grv"):
    print(f"== {kind}: tanpa Firebase ==")
    d = build(kind); r = run(d); m, a, s = read(d, kind)
    check("exit 0", r.returncode == 0, r.stderr)
    check("izin, cleartext, label 'Akar Siaga'", "permission.INTERNET" in m and "POST_NOTIFICATIONS" in m and 'usesCleartextTraffic="true"' in m and 'label="Akar Siaga"' in m)
    check("desugaring aktif", "desugar_jdk_libs:2.1.4" in a)
    check("gradle Firebase tidak disentuh", "google-services" not in a + s and "flutter.minSdkVersion" in a and "maxOf" not in a and "Math.max" not in a)
    print(f"== {kind}: dengan Firebase ==")
    d = build(kind, gs(PKG)); r = run(d, "--firebase"); m, a, s = read(d, kind)
    check("exit 0", r.returncode == 0, r.stderr)
    check("minSdk >= 23 tanpa menurunkan bawaan Flutter", ("maxOf(flutter.minSdkVersion, 23)" if kind == "kts" else "Math.max(flutter.minSdkVersion, 23)") in a)
    check("plugin google-services di app & settings", "com.google.gms.google-services" in a and 'version "4.4.2" apply false' in s)
    check("urutan plugin app: setelah com.android.application", a.index("com.android.application") < a.index("google-services") < a.index("kotlin-android"))

print("== harus GAGAL dengan pesan jelas ==")
r = run(build("kts", gs("com.lain.app")), "--firebase")
check(f"package salah -> exit 1, menyebut {PKG}", r.returncode == 1 and PKG in r.stderr and "com.lain.app" in r.stderr, r.stderr)
r = run(build("kts", "{ bukan json"), "--firebase")
check("JSON rusak -> exit 1", r.returncode == 1 and "bukan JSON" in r.stderr, r.stderr)
r = run(build("kts", gs(PKG), settings='plugins { id("x") }\n'), "--firebase")
check("settings.gradle tak dikenali -> exit 1 (tidak lolos diam-diam)", r.returncode == 1 and "tidak ditemukan" in r.stderr, r.stderr)
r = run(build("kts"), "--firebase")
check("--firebase tanpa google-services.json -> exit 1", r.returncode == 1 and "google-services.json" in r.stderr, r.stderr)
print("\nSEMUA LOLOS" if not fails else f"\n{fails} GAGAL"); sys.exit(1 if fails else 0)

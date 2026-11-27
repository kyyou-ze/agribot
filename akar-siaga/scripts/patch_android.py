#!/usr/bin/env python3
"""Patch proyek Android hasil `flutter create` agar siap membangun Akar Siaga.

Pemakaian:  python3 scripts/patch_android.py <folder_proyek> [--firebase]

Selalu:
  - izin INTERNET & POST_NOTIFICATIONS, izinkan HTTP lokal (alat), nama aplikasi "Akar Siaga"
  - core library desugaring (dibutuhkan flutter_local_notifications)
Dengan --firebase (hanya bila google-services.json tersedia):
  - validasi google-services.json (JSON sah + package id.akarsiaga.akarsiaga)
  - minSdk minimal 23, plugin com.google.gms.google-services
Gagal dengan pesan jelas (exit 1) bila format file gradle tidak dikenali.
"""
import json
import os
import re
import sys

PACKAGE = "id.akarsiaga.akar_siaga"
GMS_VERSION = "4.4.2"


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def first_existing(*paths):
    return next((p for p in paths if os.path.exists(p)), None)


def patch_manifest(root):
    p = os.path.join(root, "android/app/src/main/AndroidManifest.xml")
    s = read(p)
    if "<application" not in s:
        die("AndroidManifest.xml tidak punya tag <application>")
    perms = (
        '\n    <uses-permission android:name="android.permission.INTERNET"/>'
        '\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    '
    )
    s = s.replace("<application", perms + '<application android:usesCleartextTraffic="true"', 1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="Akar Siaga"', s, count=1)
    write(p, s)


def patch_app_gradle(root, firebase):
    p = first_existing(os.path.join(root, "android/app/build.gradle.kts"), os.path.join(root, "android/app/build.gradle"))
    if not p:
        die("android/app/build.gradle(.kts) tidak ditemukan")
    kts = p.endswith(".kts")
    g = read(p)

    if "compileOptions {" not in g:
        die(f"{os.path.basename(p)}: blok compileOptions tidak ditemukan (format gradle baru?)")
    if kts:
        g = g.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        g = g.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"

    if firebase:
        # minSdk minimal 23 (syarat Firebase), tanpa menurunkan nilai bawaan Flutter bila sudah lebih tinggi
        if kts:
            g, n = re.subn(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = maxOf(flutter.minSdkVersion, 23)", g, count=1)
        else:
            g, n = re.subn(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion Math.max(flutter.minSdkVersion, 23)", g, count=1)
        if n == 0:
            print("PERINGATAN: baris minSdk tidak dikenali; pastikan minSdk >= 23 untuk Firebase.")
        # plugin google-services di blok plugins { } aplikasi
        pat = r'(\n[ \t]*)id\(\s*"com\.android\.application"\s*\)' if kts else r'(\n[ \t]*)id\s+"com\.android\.application"'
        add = 'id("com.google.gms.google-services")' if kts else 'id "com.google.gms.google-services"'
        g, n = re.subn(pat, lambda m: m.group(0) + m.group(1) + add, g, count=1)
        if n == 0:
            die(f"{os.path.basename(p)}: blok plugins dengan com.android.application tidak ditemukan")
    write(p, g)


def patch_settings_gradle(root):
    p = first_existing(os.path.join(root, "android/settings.gradle.kts"), os.path.join(root, "android/settings.gradle"))
    if not p:
        die("android/settings.gradle(.kts) tidak ditemukan")
    kts = p.endswith(".kts")
    s = read(p)
    pat = r'(\n[ \t]*)id\(\s*"com\.android\.application"\s*\)[^\n]*apply false' if kts else \
          r'(\n[ \t]*)id\s+"com\.android\.application"[^\n]*apply false'
    add = f'id("com.google.gms.google-services") version "{GMS_VERSION}" apply false' if kts else \
          f'id "com.google.gms.google-services" version "{GMS_VERSION}" apply false'
    s, n = re.subn(pat, lambda m: m.group(0) + m.group(1) + add, s, count=1)
    if n == 0:
        die(f"{os.path.basename(p)}: deklarasi plugin com.android.application ... apply false tidak ditemukan "
            "(template Flutter berbeda). Kirim isi file ini agar skrip disesuaikan.")
    write(p, s)


def validate_google_services(root):
    p = os.path.join(root, "android/app/google-services.json")
    if not os.path.exists(p):
        die("android/app/google-services.json tidak ada")
    try:
        j = json.loads(read(p))
    except ValueError:
        die("google-services.json bukan JSON yang sah. Isi secret GOOGLE_SERVICES_JSON dengan isi file utuh.")
    pkgs = [c.get("client_info", {}).get("android_client_info", {}).get("package_name") for c in j.get("client", [])]
    if PACKAGE not in pkgs:
        die(f"google-services.json tidak memuat aplikasi Android '{PACKAGE}' (ditemukan: {pkgs}). "
            f"Daftarkan aplikasi Android dengan package persis '{PACKAGE}' di Firebase lalu unduh ulang file-nya.")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    firebase = "--firebase" in sys.argv
    if len(args) != 1:
        die(__doc__)
    root = args[0]
    if firebase:
        validate_google_services(root)
    patch_manifest(root)
    patch_app_gradle(root, firebase)
    if firebase:
        patch_settings_gradle(root)
    print("Patch Android selesai" + (" (dengan Firebase)" if firebase else ""))


if __name__ == "__main__":
    main()

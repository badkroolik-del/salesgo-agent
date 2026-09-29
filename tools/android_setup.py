"""`flutter create` dan keyin Android loyihasini Google Play talablariga moslash (CI da ishlaydi).

- applicationId: uz.salesgo.agent, targetSdk/compileSdk 36 (Android 16), minSdk 23
- release imzo: android/key.properties (GitHub Secrets dan yoziladi) bo'lsa — upload key, bo'lmasa debug
- Manifest: ilova nomi «SalesGO SFA», kerakli ruxsatlar, fonda GPS foreground-servis (turi: location)
"""
import os
import re
import sys

APP_ID = "uz.salesgo.agent"
SDK = 36
MIN_SDK = 23
LABEL = "SalesGO SFA"

root = sys.argv[1] if len(sys.argv) > 1 else "."
app = os.path.join(root, "android", "app")

# ---------------- build.gradle(.kts) ----------------
kts = os.path.join(app, "build.gradle.kts")
gro = os.path.join(app, "build.gradle")
if os.path.exists(kts):
    p = kts
    s = open(p, encoding="utf-8").read()
    if "keystorePropertiesFile" not in s:
        s = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s
        s = s.replace("android {", '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {''', 1)
        s = re.sub(r"(android \{\n)", r'''\1    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
''', s, count=1)
        s = re.sub(r'signingConfig = signingConfigs\.getByName\("debug"\)',
                   'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")', s)
    s = re.sub(r'applicationId = "[^"]*"', f'applicationId = "{APP_ID}"', s)
    s = re.sub(r"compileSdk = [^\n]+", f"compileSdk = {SDK}", s)
    s = re.sub(r"minSdk = [^\n]+", f"minSdk = {MIN_SDK}", s)
    s = re.sub(r"targetSdk = [^\n]+", f"targetSdk = {SDK}", s)
    open(p, "w", encoding="utf-8").write(s)
    print("build.gradle.kts patched")
elif os.path.exists(gro):
    p = gro
    s = open(p, encoding="utf-8").read()
    if "keystorePropertiesFile" not in s:
        s = s.replace("android {", '''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {''', 1)
        s = re.sub(r"(android \{\n)", r'''\1    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }
''', s, count=1)
        s = re.sub(r"signingConfig signingConfigs\.debug",
                   "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug", s)
    s = re.sub(r'applicationId "[^"]*"', f'applicationId "{APP_ID}"', s)
    s = re.sub(r"compileSdk(Version)? [^\n]+", f"compileSdk {SDK}", s)
    s = re.sub(r"minSdk(Version)? [^\n]+", f"minSdk {MIN_SDK}", s)
    s = re.sub(r"targetSdk(Version)? [^\n]+", f"targetSdk {SDK}", s)
    open(p, "w", encoding="utf-8").write(s)
    print("build.gradle patched")
else:
    sys.exit("android/app/build.gradle(.kts) topilmadi")

# ---------------- AndroidManifest.xml ----------------
mp = os.path.join(app, "src", "main", "AndroidManifest.xml")
s = open(mp, encoding="utf-8").read()
if 'xmlns:tools=' not in s:
    s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android"',
                  '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools"', 1)
perms = [
    "INTERNET", "ACCESS_NETWORK_STATE",
    "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "ACCESS_BACKGROUND_LOCATION",
    "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_LOCATION",
    "POST_NOTIFICATIONS", "RECEIVE_BOOT_COMPLETED", "WAKE_LOCK", "CAMERA",
]
block = "".join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms if f"android.permission.{p}\"" not in s)
if block:
    s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n" + block, s, count=1)
QI = '''
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="geo"/></intent>
        <intent><action android:name="android.media.action.IMAGE_CAPTURE"/></intent>'''
if "<queries>" not in s:
    s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n    <queries>" + QI + "\n    </queries>", s, count=1)
elif 'android:scheme="geo"' not in s:
    s = s.replace("<queries>", "<queries>" + QI, 1)
s = re.sub(r'android:label="[^"]*"', f'android:label="{LABEL}"', s, count=1)
if "flutter_background_service.BackgroundService" not in s:
    svc = '''
        <!-- Fonda GPS trek: ilova yopilganda ham ishlaydigan foreground-servis (turi: location) -->
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="location"
            android:exported="false"
            android:stopWithTask="false"
            tools:replace="android:foregroundServiceType,android:exported,android:stopWithTask" />
'''
    s = s.replace("</application>", svc + "    </application>", 1)
open(mp, "w", encoding="utf-8").write(s)
print("manifest patched")

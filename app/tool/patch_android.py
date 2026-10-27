#!/usr/bin/env python3
"""Patches the freshly generated Flutter android/ folder for MedLog.

usage: patch_android.py <android_dir> <tool_dir>

1. MainActivity.kt  -> adds the FLAG_SECURE channel (screenshot / recent-apps protection)
2. AndroidManifest  -> app label "MedLog" + allowBackup=false (no cloud auto-backup of patient data)
3. app/build.gradle(.kts) -> release signing from android/key.properties
4. root build.gradle(.kts) -> compileSdk 36 for all plugin modules (AndroidX lifecycle needs it)
5. system features:
   - MainActivity extends FlutterFragmentActivity (local_auth biometric prompt)
   - permissions USE_BIOMETRIC, POST_NOTIFICATIONS, VIBRATE, RECEIVE_BOOT_COMPLETED, RECORD_AUDIO (voice dictation)
   - <queries> android.speech.RecognitionService (voice dictation, Android 11+)
   - flutter_local_notifications receivers (scheduled + boot) in <application>
   - core library desugaring (compileOptions flag + desugar_jdk_libs dependency)
Every step is idempotent: running the script twice changes nothing the second time.
"""
import pathlib
import re
import sys

android = pathlib.Path(sys.argv[1])
tool = pathlib.Path(sys.argv[2])


def fail(msg):
    print("::error::" + msg)
    sys.exit(1)


# ---------------------------------------------------------------- 1. MainActivity
src_root = android / "app" / "src" / "main"
found = list(src_root.glob("**/MainActivity.kt")) + list(src_root.glob("**/MainActivity.java"))
if not found:
    fail("MainActivity not found in generated android project")
old = found[0]
m = re.search(r"^\s*package\s+([\w.]+)", old.read_text(), re.M)
if not m:
    fail("could not read package name from MainActivity")
package = m.group(1)
tpl = (tool / "MainActivity.kt.tpl").read_text().replace("__PACKAGE__", package)
target = old.with_suffix(".kt")
if old.suffix == ".java":
    old.unlink()
target.write_text(tpl)
print("MainActivity patched:", target, "package", package)

# ---------------------------------------------------------------- 2. Manifest
manifest = src_root / "AndroidManifest.xml"
x = manifest.read_text()
x = re.sub(r'android:label="[^"]*"', 'android:label="MedLog"', x, count=1)
if "android:allowBackup" in x:
    x = re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', x, count=1)
else:
    x = x.replace("<application", '<application\n        android:allowBackup="false"', 1)
if "android.permission.INTERNET" not in x:
    x = x.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
https_intent = '<intent>\n            <action android:name="android.intent.action.VIEW"/>\n            <data android:scheme="https"/>\n        </intent>'
if 'android:scheme="https"' in x:
    pass  # already patched
elif "<queries>" in x:
    x = x.replace("<queries>", "<queries>\n        " + https_intent, 1)
else:
    x = x.replace("<application", "<queries>\n        " + https_intent + "\n    </queries>\n    <application", 1)

# system features: permissions
for perm in ("USE_BIOMETRIC", "POST_NOTIFICATIONS", "VIBRATE", "RECEIVE_BOOT_COMPLETED", "RECORD_AUDIO"):
    if "android.permission." + perm + '"' not in x:
        x = x.replace("<application", '<uses-permission android:name="android.permission.%s"/>\n    <application' % perm, 1)
        print("Manifest: added permission", perm)

# voice dictation (speech_to_text): the app must be allowed to see the phone's speech recogniser (Android 11+)
if "android.speech.RecognitionService" not in x:
    speech_intent = '<intent>\n            <action android:name="android.speech.RecognitionService"/>\n        </intent>'
    if "<queries>" in x:
        x = x.replace("<queries>", "<queries>\n        " + speech_intent, 1)
    else:
        x = x.replace("<application", "<queries>\n        " + speech_intent + "\n    </queries>\n    <application", 1)
    print("Manifest: added RecognitionService query")

# flutter_local_notifications receivers (needed to show scheduled notifications / re-arm after reboot)
if "ScheduledNotificationReceiver" not in x:
    receivers = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
    if "</application>" not in x:
        fail("</application> not found in manifest")
    x = x.replace("</application>", receivers + "    </application>", 1)
    print("Manifest: added notification receivers")

manifest.write_text(x)
print("Manifest patched")

# ---------------------------------------------------------------- 3. Gradle signing
gradle = None
for name in ("build.gradle.kts", "build.gradle"):
    p = android / "app" / name
    if p.exists():
        gradle = p
        break
if gradle is None:
    fail("app/build.gradle(.kts) not found")

txt = gradle.read_text()
already_signed = "key.properties" in txt
if gradle.suffix == ".kts":
    block = '''    signingConfigs {
        create("release") {
            val props = Properties()
            val kp = rootProject.file("key.properties")
            if (kp.exists()) {
                val input = kp.inputStream()
                props.load(input)
                input.close()
            }
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
            val sf: String? = props.getProperty("storeFile")
            if (sf != null) {
                storeFile = file(sf)
            }
            storePassword = props.getProperty("storePassword")
        }
    }

'''
    if not already_signed:
        txt = "import java.util.Properties\n\n" + txt
    txt = txt.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
    ok = 'signingConfigs.getByName("release")' in txt
else:
    block = '''    signingConfigs {
        release {
            def props = new Properties()
            def kp = rootProject.file("key.properties")
            if (kp.exists()) {
                kp.withInputStream { props.load(it) }
            }
            keyAlias props["keyAlias"]
            keyPassword props["keyPassword"]
            storeFile props["storeFile"] ? file(props["storeFile"]) : null
            storePassword props["storePassword"]
        }
    }

'''
    txt = txt.replace("signingConfigs.debug", "signingConfigs.release")
    ok = "signingConfigs.release" in txt

if already_signed:
    print("Gradle: signing already patched, skipped")
else:
    mm = re.search(r"^[ \t]*buildTypes\s*\{", txt, re.M)
    if not mm:
        fail("buildTypes block not found in gradle file")
    txt = txt[: mm.start()] + block + txt[mm.start():]
    if not ok:
        fail("release signingConfig line not found in gradle file (template changed?)")

# core library desugaring (flutter_local_notifications needs it for scheduled notifications)
DESUGAR = "com.android.tools:desugar_jdk_libs:2.1.4"
if "coreLibraryDesugaring" in txt:
    print("Gradle: desugaring already enabled, skipped")
else:
    kts = gradle.suffix == ".kts"
    flag = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
    dep = ('dependencies {\n    coreLibraryDesugaring("%s")\n}\n' if kts else
           "dependencies {\n    coreLibraryDesugaring '%s'\n}\n") % DESUGAR
    co = re.search(r"^([ \t]*)compileOptions\s*\{", txt, re.M)
    if co:
        ind = co.group(1) + "    "
        txt = txt[: co.end()] + "\n" + ind + flag + txt[co.end():]
    else:
        an = re.search(r"^android\s*\{", txt, re.M)
        if not an:
            fail("android { block not found in app gradle file")
        txt = txt[: an.end()] + "\n    compileOptions {\n        " + flag + "\n    }" + txt[an.end():]
    txt = txt.rstrip("\n") + "\n\n" + dep
    print("Gradle: core library desugaring enabled")
gradle.write_text(txt)
print("Gradle patched:", gradle)

# ---------------------------------------------------------------- 4. compileSdk for plugins
root = None
for name in ("build.gradle.kts", "build.gradle"):
    p = android / name
    if p.exists():
        root = p
        break
if root is None:
    fail("root build.gradle(.kts) not found")

if root.suffix == ".kts":
    extra = '''
subprojects {
    if (name != "app") {
        val forceSdk = {
            val ext = extensions.findByName("android")
            if (ext != null) {
                ext.javaClass.getMethod("setCompileSdk", Integer::class.javaObjectType).invoke(ext, 36)
            }
        }
        if (state.executed) forceSdk() else afterEvaluate { forceSdk() }
    }
}
'''
else:
    extra = '''
subprojects {
    if (project.name != "app") {
        def forceSdk = {
            def ext = project.extensions.findByName("android")
            if (ext != null) {
                ext.compileSdkVersion(36)
            }
        }
        if (project.state.executed) { forceSdk() } else { project.afterEvaluate { forceSdk() } }
    }
}
'''
rtxt = root.read_text()
if "forceSdk" in rtxt:
    print("Root gradle: compileSdk override already present, skipped")
else:
    root.write_text(rtxt + extra)
    print("Root gradle patched:", root)

# ---------------------------------------------------------------- 6. Kotlin/Java target validation
# Some plugins (flutter_timezone, share_plus) compile Kotlin for JVM 1.8 while Java uses 11;
# KGP then fails with "Inconsistent JVM Target Compatibility". Downgrade the check to a warning.
gp = android / "gradle.properties"
line = "kotlin.jvm.target.validation.mode=warning"
gtxt = gp.read_text() if gp.exists() else ""
if line in gtxt:
    print("gradle.properties: jvm target validation already relaxed, skipped")
else:
    gp.write_text(gtxt.rstrip("\n") + "\n" + line + "\n")
    print("gradle.properties: added", line)

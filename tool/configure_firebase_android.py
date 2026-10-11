#!/usr/bin/env python3
"""Idempotently align generated Flutter Android runner with supplied Firebase app.
No service-account credentials are read. Uses Android client google-services.json.
"""
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'firebase_config/android/google-services.json'
TARGET = ROOT / 'android/app/google-services.json'
APP_DIR = ROOT / 'android/app'
if not (APP_DIR / 'src/main/AndroidManifest.xml').is_file():
    raise SystemExit('Run flutter create --platforms=android . first')
info = json.loads(SOURCE.read_text(encoding='utf-8'))
packages = {client['client_info']['android_client_info']['package_name']
            for client in info.get('client', [])}
package = 'com.performance.tracker'
if package not in packages:
    raise SystemExit('The supplied google-services.json is not for ' + package)
TARGET.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(SOURCE, TARGET)
# Firebase requests require INTERNET even in Android release builds.
manifest = APP_DIR / 'src/main/AndroidManifest.xml'
manifest_text = manifest.read_text(encoding='utf-8')
if 'android.permission.INTERNET' not in manifest_text:
    manifest_text = re.sub(r'(<manifest\b[^>]*>)',
        r'\1\n    <uses-permission android:name="android.permission.INTERNET" />',
        manifest_text, count=1, flags=re.DOTALL)
# Android 13+ local notifications require runtime permission for open-app alerts.
if 'android.permission.POST_NOTIFICATIONS' not in manifest_text:
    manifest_text = re.sub(r'(<manifest\b[^>]*>)',
        r'\1\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
        manifest_text, count=1, flags=re.DOTALL)
# Avoid restoring encrypted password storage without its Android Keystore key
# (which may be device-bound). Apply idempotently to the generated runner.
if 'android:allowBackup=' not in manifest_text:
    manifest_text = manifest_text.replace('<application', '<application android:allowBackup="false"', 1)
else:
    manifest_text = re.sub(r'android:allowBackup="[^"]+"',
        'android:allowBackup="false"', manifest_text, count=1)
# Use the public app name on device launcher (Flutter create defaults to package name).
if 'android:label=' in manifest_text:
    manifest_text = re.sub(r'android:label="[^"]*"',
        'android:label="Performance Tracker"', manifest_text, count=1)
else:
    manifest_text = manifest_text.replace('<application',
        '<application android:label="Performance Tracker"', 1)
manifest.write_text(manifest_text, encoding='utf-8')

build_file = next((f for f in (APP_DIR/'build.gradle.kts', APP_DIR/'build.gradle') if f.exists()), None)
if build_file is None:
    raise SystemExit('Missing android/app/build.gradle(.kts)')
text = build_file.read_text(encoding='utf-8')
kotlin = build_file.suffix == '.kts'
if kotlin:
    text = re.sub(r'namespace\s*=\s*"[^"]+"', 'namespace = "com.performance.tracker"', text)
    text = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.performance.tracker"', text)
    plugin = '    id("com.google.gms.google-services") version "4.4.4"'
else:
    text = re.sub(r'namespace\s+(?:["\'])[^"\']+["\']', "namespace 'com.performance.tracker'", text)
    text = re.sub(r'applicationId\s+(?:["\'])[^"\']+["\']', "applicationId 'com.performance.tracker'", text)
    plugin = "    id 'com.google.gms.google-services' version '4.4.4'"
if 'com.google.gms.google-services' not in text:
    text = re.sub(r'(plugins\s*\{)', r'\1\n' + plugin, text, count=1)
if 'com.performance.tracker' not in text or 'com.google.gms.google-services' not in text:
    raise SystemExit('Could not patch Android Gradle configuration')
build_file.write_text(text, encoding='utf-8')

# MainActivity package must agree with manifest .MainActivity and applicationId.
for file in (APP_DIR/'src/main/kotlin').rglob('MainActivity.kt'):
    txt = file.read_text(encoding='utf-8')
    txt = re.sub(r'^package\s+[^\s]+', 'package com.performance.tracker', txt, count=1, flags=re.MULTILINE)
    file.write_text(txt, encoding='utf-8')
for file in (APP_DIR/'src/main/java').rglob('MainActivity.java'):
    txt = file.read_text(encoding='utf-8')
    txt = re.sub(r'^package\s+[^;]+;', 'package com.performance.tracker;', txt, count=1, flags=re.MULTILINE)
    file.write_text(txt, encoding='utf-8')
print('Firebase Android configured: com.performance.tracker')
print('Client project: ' + info['project_info']['project_id'])

# Generated Android runner is disposable in CI. Implement the Flutter channel
# every build so Firestore inbox messages can show Android local notifications
# WHEN THE APP IS RUNNING. This is NOT background FCM push delivery.
main_activity = next((f for f in (APP_DIR / 'src/main/kotlin').rglob('MainActivity.kt')), None)
if main_activity is not None:
    main_activity.write_text(r'''package com.performance.tracker

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "performance_tracker/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 5010)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "notify" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED) {
                            result.success(null)
                        } else {
                            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val channelId = "performance_reminders"
                            if (Build.VERSION.SDK_INT >= 26) {
                                manager.createNotificationChannel(NotificationChannel(
                                    channelId, "Performance reminders", NotificationManager.IMPORTANCE_DEFAULT))
                            }
                            val builder = if (Build.VERSION.SDK_INT >= 26)
                                Notification.Builder(this, channelId) else Notification.Builder(this)
                            val notification = builder
                                .setSmallIcon(android.R.drawable.ic_dialog_info)
                                .setContentTitle(call.argument<String>("title") ?: "Performance Tracker")
                                .setContentText(call.argument<String>("body") ?: "")
                                .setAutoCancel(true)
                                .build()
                            manager.notify((System.currentTimeMillis() % 1000000L).toInt(), notification)
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
''', encoding='utf-8')

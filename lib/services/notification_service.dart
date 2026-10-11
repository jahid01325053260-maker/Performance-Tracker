import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android OS alerts when a signed-in, running client receives Firestore messages.
/// Spark Free does not provide background FCM sending from an untrusted client.
class DeviceAlerts {
  static const _channel = MethodChannel('performance_tracker/notifications');

  static Future<bool> requestPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException { return false; }
    on PlatformException { return false; }
  }

  static Future<bool> notify(String title, String body) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('notify',
        {'title': title, 'body': body}) ?? false;
    } on MissingPluginException { return false; }
    on PlatformException { return false; }
  }
}

/// Remembers which alert IDs have already triggered an OS notification.
/// Scope keys to the signed-in identity: different employees sharing the same
/// phone must not suppress each other's notifications. Only IDs are stored.
class DeliveredAlertStore {
  DeliveredAlertStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String uid) => 'pt_delivered_alert_ids_v1_$uid';

  Future<Set<String>> read(String uid) async {
    if (uid.isEmpty) return <String>{};
    try {
      final raw = await _storage.read(key: _key(uid));
      if (raw == null || raw.isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      // KeyStore unavailable (e.g. restored app on a new device); the inbox
      // remains usable and a future notification can still be retried.
      return <String>{};
    }
  }

  Future<void> write(String uid, Set<String> seen) async {
    if (uid.isEmpty) return;
    try {
      final recent = seen.toList();
      // Stored entries are appended chronologically; cap encrypted local data.
      final bounded = recent.length > 120
          ? recent.sublist(recent.length - 120) : recent;
      await _storage.write(key: _key(uid), value: jsonEncode(bounded));
    } catch (_) {
      // Never block access to the user's inbox due to local storage errors.
    }
  }
}

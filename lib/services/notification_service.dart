import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  static Future<void> notify(String title, String body) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('notify', {'title': title, 'body': body});
    } on MissingPluginException { /* Unsupported platform. Inbox still works. */ }
    on PlatformException { /* Permission/device denied; inbox still works. */ }
  }
}

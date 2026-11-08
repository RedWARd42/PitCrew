import 'package:flutter/services.dart';

/// Thin guarded wrapper over MethodChannel 'swarm/native' (Kotlin side owned by android-native).
class Native {
  static const _ch = MethodChannel('swarm/native');

  static Future<void> openAccessibilitySettings() async {
    try {
      await _ch.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// null = unknown (native method missing).
  static Future<bool?> isAccessibilityEnabled() async {
    try {
      return await _ch.invokeMethod<bool>('isAccessibilityEnabled');
    } catch (_) {
      return null;
    }
  }
}

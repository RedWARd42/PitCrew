/// Bridges to the Android side of Swat.
///
/// Two platform channels, both implemented in `MainActivity.kt`:
///
///  * `swat/sms` — reads the device's real SMS inbox
///    (`content://sms/inbox`) after the user grants READ_SMS, so the fleet
///    can analyze genuine texts on an Android phone/emulator. Any failure
///    (permission denied, not Android, empty store) falls back to the
///    synthetic demo inbox — the demo never hard-depends on it.
///
///  * `swat/overlay` — the "over the Messages app" half, and the primary
///    surface: a Kotlin foreground service draws the fleet over other apps
///    (Google Messages included) using the system alert window. When a
///    text arrives, a native receiver wakes the service and the scan panel
///    opens right over Messages — the Kotlin port of the engine
///    (`KotlinScamAnalyzer.kt`) runs it there. Tapping the floating badge
///    scans the latest text on demand. Android only — iOS has no
///    equivalent, which is a platform limit, not an app limit.
///
/// Message content never leaves the device: analysis is on-device Dart.
library;

import 'package:flutter/services.dart';

import '../data/demo_inbox.dart';
import '../models/message.dart';

class SmsService {
  static const MethodChannel _channel = MethodChannel('swat/sms');

  /// Real inbox if we can get it, demo inbox otherwise.
  /// Returns (messages, fromRealStore).
  static Future<(List<ChatMessage>, bool)> loadInbox() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('readInbox');
      if (raw != null && raw.isNotEmpty) {
        final messages = <ChatMessage>[];
        for (var i = 0; i < raw.length; i++) {
          final map = Map<dynamic, dynamic>.from(raw[i] as Map);
          final body = (map['body'] as String?) ?? '';
          if (body.trim().isEmpty) continue;
          messages.add(
            ChatMessage(
              id: 'real-$i',
              sender: (map['address'] as String?) ?? 'Unknown',
              body: body,
              timeLabel: (map['timeLabel'] as String?) ?? '',
              isFromRealStore: true,
            ),
          );
        }
        if (messages.isNotEmpty) return (messages, true);
      }
    } on PlatformException {
      // Permission denied or not Android — fall through to demo data.
    } on MissingPluginException {
      // Non-Android platform or channel not registered — demo data.
    }
    return (demoInbox, false);
  }
}

/// Real ways to reach the trusted contact from inside the app: hand off to
/// the phone's dialer / SMS composer via the `swat/comms` channel. The
/// in-app Family thread is for scan-sharing and calm async checks; when it
/// is actually urgent, one tap puts the user in a real call or text with
/// the real person.
class CommsService {
  static const MethodChannel _channel = MethodChannel('swat/comms');

  static Future<bool> openDialer(String phone) async {
    try {
      return await _channel.invokeMethod<bool>('dial', {'phone': phone}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> openSmsComposer(String phone, String body) async {
    try {
      return await _channel.invokeMethod<bool>('sms', {
            'phone': phone,
            'body': body,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class OverlayService {
  static const MethodChannel _channel = MethodChannel('swat/overlay');

  static Future<bool> canDrawOverlays() async {
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system settings page where the user grants
  /// "display over other apps" to Swat.
  static Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } on PlatformException {
      // Non-Android: nothing to open.
    } on MissingPluginException {
      // Non-Android: nothing to open.
    }
  }

  static Future<bool> startOverlay() async {
    try {
      return await _channel.invokeMethod<bool>('startOverlay') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stopOverlay() async {
    try {
      await _channel.invokeMethod<void>('stopOverlay');
    } on PlatformException {
      // Already stopped / non-Android.
    } on MissingPluginException {
      // Already stopped / non-Android.
    }
  }

  /// Asks for READ_SMS + RECEIVE_SMS — the pair the overlay patrol needs
  /// (receive triggers the over-Messages scan; read powers badge-tap
  /// scans of the store). Fire-and-forget: the OS dialog is the answer.
  static Future<void> requestSmsPermissions() async {
    try {
      await _channel.invokeMethod<void>('requestSmsPermissions');
    } on PlatformException {
      // Non-Android.
    } on MissingPluginException {
      // Non-Android.
    }
  }

  /// Senders blocked from the overlay's Block & Report button, written
  /// natively to SharedPreferences so the Blocked tab can show them.
  /// Each map: sender, snippet, risk, at (epoch millis as string).
  static Future<List<Map<String, String>>> nativeBlocks() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('getNativeBlocks');
      if (raw == null) return const [];
      return [
        for (final item in raw)
          Map<String, String>.from(
            (item as Map).map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
            ),
          ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

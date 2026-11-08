/// Light / dark mode state for the whole app.
///
/// Dark is the default (it is the app's designed identity); the toggle
/// flips [mode], the root MaterialApp listens, and every screen redraws
/// from the brightness-aware palette. The choice is persisted on-device
/// through the `swat/theme` channel (SharedPreferences on Android), so
/// it survives restarts. Any platform without the channel (tests, web)
/// simply keeps the in-memory value.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThemeStore {
  static const MethodChannel _channel = MethodChannel('swat/theme');

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static Future<void> load() async {
    try {
      final stored = await _channel.invokeMethod<String>('getThemeMode');
      if (stored == 'light') mode.value = ThemeMode.light;
      if (stored == 'dark') mode.value = ThemeMode.dark;
    } on PlatformException {
      // Keep the default.
    } on MissingPluginException {
      // Keep the default.
    }
  }

  static Future<void> toggle() async {
    mode.value = mode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    try {
      await _channel.invokeMethod<void>('setThemeMode', {
        'mode': mode.value == ThemeMode.light ? 'light' : 'dark',
      });
    } on PlatformException {
      // In-memory flip already happened; persistence is best-effort.
    } on MissingPluginException {
      // Same.
    }
  }
}

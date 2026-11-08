import 'package:flutter/material.dart';

import '../services/theme_store.dart';

/// The app's semantic colors, resolved per brightness.
///
/// Every screen used to hardcode the dark palette (near-black surfaces,
/// white text). Those literals now route through here, so the light /
/// dark toggle flips the whole app — surfaces, bubbles, and the text
/// grays — while the drone colors and the T-Mobile magenta stay constant
/// in both modes (they are identity, not theme).
class AppPalette {
  const AppPalette(this.brightness);

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  Color get background =>
      isDark ? const Color(0xFF0B0B12) : const Color(0xFFF7F4FA);
  Color get panel => isDark ? const Color(0xFF12121C) : Colors.white;
  Color get sheet => isDark ? const Color(0xFF15151F) : Colors.white;
  Color get banner =>
      isDark ? const Color(0xFF15151F) : const Color(0xFFF0EAF4);
  Color get bubble => isDark ? const Color(0xFF1C1C26) : Colors.white;
  Color get bubbleSelected =>
      isDark ? const Color(0xFF26202E) : const Color(0xFFFBE9F4);
  Color get avatarBg =>
      isDark ? const Color(0xFF2A2A3A) : const Color(0xFFE6DFF0);
  Color get insetBox =>
      isDark ? const Color(0xFF0B0B12) : const Color(0xFFF1ECF5);
  Color get fieldFill =>
      isDark ? const Color(0xFF1C1C26) : const Color(0xFFF1ECF5);

  Color get primaryText => isDark ? Colors.white : const Color(0xFF1B1622);
  Color get secondaryText => isDark ? Colors.white70 : const Color(0xFF453D4D);
  Color get tertiaryText => isDark ? Colors.white54 : const Color(0xFF6E6577);
  Color get faintText => isDark ? Colors.white38 : const Color(0xFF9A92A5);

  Color get divider => isDark ? Colors.white10 : const Color(0x1F1B1622);

  /// Translucent neutral for hairline rings/borders that used to be
  /// white24 — visible on both backgrounds.
  Color get overlayBorder => isDark ? Colors.white24 : const Color(0x3D1B1622);
  Color get chipBg => isDark ? Colors.white10 : const Color(0x141B1622);
}

extension PaletteX on BuildContext {
  AppPalette get palette => AppPalette(Theme.of(this).brightness);
}

/// The sun / moon button that flips the app between light and dark.
/// Lives in the app bars; the choice persists on the device.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.mode,
      builder: (context, mode, _) {
        final dark = mode == ThemeMode.dark;
        return IconButton(
          tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
          icon: Icon(
            dark ? Icons.light_mode : Icons.dark_mode,
            color: context.palette.secondaryText,
          ),
          onPressed: ThemeStore.toggle,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

const swarmGreen = Color(0xFF30D158);
const _greenDark = Color(0xFF1F9D45);

ThemeData swarmTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: swarmGreen, brightness: b)
      .copyWith(
        primary: dark ? swarmGreen : _greenDark,
        onPrimary: dark ? Colors.black : Colors.white,
        surface: dark ? Colors.black : const Color(0xFFF5F5F7),
        onSurface: dark ? Colors.white : const Color(0xFF1D1D1F),
      );
  final base = ThemeData(
    brightness: b,
    colorScheme: scheme,
    useMaterial3: true,
  ).textTheme;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.copyWith(
      // Large text tracks tighter with tight leading (Apple optical sizing).
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 32,
        letterSpacing: -0.6,
        height: 1.1,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 17,
        height: 1.45,
        color: scheme.onSurface.withValues(alpha: .72),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// Grouped surface used for cards.
Color cardColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xFF1C1C1E)
    : Colors.white;

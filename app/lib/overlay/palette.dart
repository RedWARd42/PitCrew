import 'package:flutter/material.dart';

class DroneStyle {
  final String name, watches;
  final Color color;
  const DroneStyle(this.name, this.watches, this.color);
}

/// PLAN section 5.1 roster.
const droneStyles = <String, DroneStyle>{
  'angler': DroneStyle('Angler', 'Sender', Color(0xFFFB923C)),
  'link': DroneStyle('Link', 'URL', Color(0xFF38BDF8)),
  'pressure': DroneStyle('Pressure', 'Language', Color(0xFFF87171)),
  'impersonator': DroneStyle('Impersonator', 'Brand', Color(0xFFF472B6)),
  'warden': DroneStyle('Warden', 'Your reply', Color(0xFFFBBF24)),
  'drift': DroneStyle('Drift', 'Trajectory', Color(0xFFA3E635)),
  'carrier': DroneStyle('Carrier', 'Attachments', Color(0xFF4ADE80)),
  'scanner': DroneStyle('Scanner', 'Images', Color(0xFFC084FC)),
};

DroneStyle styleFor(String id) =>
    droneStyles[id] ?? DroneStyle(id.isEmpty ? 'Drone' : id[0].toUpperCase() + id.substring(1), '', const Color(0xFF9CA3AF));

/// Words + percent. Under 0.6 reads "Not sure".
String confidenceLabel(double c) {
  final pct = (c * 100).round();
  final word = c < 0.6 ? 'Not sure' : (c >= 0.8 ? 'Likely' : 'Probably');
  return '$word · $pct%';
}

String verdictWord(String v) => switch (v) {
      'scam' => 'Likely scam',
      'suspicious' => 'Suspicious',
      'safe' => 'Looks safe',
      _ => 'Not sure',
    };

const kRed = Color(0xFFFF453A);
const kAmber = Color(0xFFFF9F0A);
const kGreen = Color(0xFF30D158);
const kNeutral = Color(0xFF8E8E93);

Color verdictColor(String v) => switch (v) {
      'scam' => kRed,
      'suspicious' => kAmber,
      'safe' => kGreen,
      _ => kNeutral,
    };

/// Surfaces that read over both light and dark Google Messages.
class Pal {
  final Color surface, tonal, text, dim, hairline, scrim;
  const Pal._(this.surface, this.tonal, this.text, this.dim, this.hairline, this.scrim);
  static const light = Pal._(Color(0xFFFFFFFF), Color(0xFFF2F2F7), Color(0xFF1C1C1E), Color(0xFF6C6C70), Color(0x1F000000), Color(0x66000000));
  static const dark = Pal._(Color(0xFF1C1C1E), Color(0xFF2C2C2E), Color(0xFFF5F5F7), Color(0xFFA1A1A6), Color(0x2EFFFFFF), Color(0x99000000));
  static Pal of(Brightness b) => b == Brightness.dark ? dark : light;
}

TextStyle ts(double size, FontWeight w, Color c, {double? height, double spacing = 0, bool mono = false}) => TextStyle(
    fontSize: size, fontWeight: w, color: c, height: height, letterSpacing: spacing, decoration: TextDecoration.none, fontFamily: mono ? 'monospace' : null);

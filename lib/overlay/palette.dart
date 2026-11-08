import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_palette.dart';
import '../widgets/drone_widget.dart';

class DroneStyle {
  final String name, watches;
  final Color color;
  const DroneStyle(this.name, this.watches, this.color);

  IconData get icon => switch (name) {
    'Angler' => DroneId.angler.icon,
    'Link' => DroneId.link.icon,
    'Scanner' => DroneId.scanner.icon,
    'Pressure' => DroneId.pressure.icon,
    'Impersonator' => DroneId.impersonator.icon,
    'Swap' => DroneId.swap.icon,
    'Warden' => Icons.shield_outlined,
    'Drift' => Icons.trending_up,
    'Carrier' => Icons.attach_file,
    _ => Icons.shield_outlined,
  };
}

/// PLAN section 5.1 roster.
final droneStyles = <String, DroneStyle>{
  for (final drone in DroneId.values)
    drone.name: DroneStyle(
      drone.label,
      drone.specialty,
      Color(drone.colorValue),
    ),
  'warden': DroneStyle('Warden', 'Your reply', Color(0xFFFBBF24)),
  'drift': DroneStyle('Drift', 'Trajectory', Color(0xFFA3E635)),
  'carrier': DroneStyle('Carrier', 'Attachments', Color(0xFF4ADE80)),
};

DroneStyle styleFor(String id) =>
    droneStyles[id] ??
    DroneStyle(
      id.isEmpty ? 'Drone' : id[0].toUpperCase() + id.substring(1),
      '',
      const Color(0xFF9CA3AF),
    );

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
  const Pal._(
    this.surface,
    this.tonal,
    this.text,
    this.dim,
    this.hairline,
    this.scrim,
  );
  factory Pal._from(AppPalette p) => Pal._(
    p.sheet,
    p.banner,
    p.primaryText,
    p.secondaryText,
    p.divider,
    p.isDark ? const Color(0x99000000) : const Color(0x66000000),
  );
  static final light = Pal._from(const AppPalette(Brightness.light));
  static final dark = Pal._from(const AppPalette(Brightness.dark));
  static Pal of(Brightness b) => b == Brightness.dark ? dark : light;
}

TextStyle ts(
  double size,
  FontWeight w,
  Color c, {
  double? height,
  double spacing = 0,
  bool mono = false,
}) => TextStyle(
  fontSize: size,
  fontWeight: w,
  color: c,
  height: height,
  letterSpacing: spacing,
  decoration: TextDecoration.none,
  fontFamily: mono ? 'monospace' : null,
);

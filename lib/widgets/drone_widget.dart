import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_palette.dart';

/// Visual identity per drone: a specialty icon worn in the camera lens,
/// so the fleet is distinguishable by shape as well as color (color
/// alone fails color-blind users and tiny sizes).
extension DroneVisuals on DroneId {
  IconData get icon => switch (this) {
    DroneId.angler => Icons.phishing,
    DroneId.link => Icons.link,
    DroneId.scanner => Icons.qr_code_scanner,
    DroneId.pressure => Icons.bolt,
    DroneId.impersonator => Icons.person_search,
    DroneId.swap => Icons.swap_horiz,
  };
}

/// One specialist drone, drawn as a small top-down quadcopter: four
/// rotor pods on arms around a colored body, a camera lens in the middle
/// wearing the drone's specialty icon, and its name in a pill below.
///
/// The drone IS the interface — docked in the bay, flying over the
/// message while it scans, and tappable everywhere to open its findings.
/// States: rotors always turn (unless the system asks for reduced
/// motion), scanning adds a pulse ring, a radar sweep, a stronger glow
/// and a gentle hover bob; after a scan, a badge pill shows the risk
/// points this drone contributed (green check when it found nothing).
class DroneWidget extends StatefulWidget {
  const DroneWidget({
    super.key,
    required this.drone,
    this.size = 52,
    this.showLabel = true,
    this.scanning = false,
    this.badgePoints,
    this.onTap,
  });

  final DroneId drone;
  final double size;
  final bool showLabel;

  /// Rotors spin fast and a pulse ring shows while this drone is scanning.
  final bool scanning;

  /// When set (after analysis), a small badge shows the risk points this
  /// drone contributed. 0 renders as a green check.
  final int? badgePoints;

  final VoidCallback? onTap;

  @override
  State<DroneWidget> createState() => _DroneWidgetState();
}

class _DroneWidgetState extends State<DroneWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotor = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat();

  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Elderly-skill rule: honor reduced motion — still rotors, no bob.
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotor.stop();
    } else if (!_rotor.isAnimating) {
      _rotor.repeat();
    }
  }

  @override
  void dispose() {
    _rotor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.drone.colorValue);
    final s = widget.size;
    final stage = s + 2;
    final badge = widget.badgePoints;
    return Semantics(
      button: widget.onTap != null,
      label:
          '${widget.drone.label}, ${widget.drone.specialty}'
          '${badge != null ? (badge > 0 ? ', flagged plus $badge risk' : ', all clear') : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: s + 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: stage,
                  height: stage,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _rotor,
                        builder: (context, child) {
                          final bob = widget.scanning
                              ? math.sin(_rotor.value * math.pi * 2) * 1.6
                              : 0.0;
                          return Transform.translate(
                            offset: Offset(0, bob),
                            child: CustomPaint(
                              size: Size.square(stage),
                              painter: _DronePainter(
                                color: color,
                                progress: _rotor.value,
                                scanning: widget.scanning,
                              ),
                            ),
                          );
                        },
                      ),
                      // The specialty icon, worn in the camera lens.
                      Icon(
                        widget.drone.icon,
                        color: Colors.white,
                        size: math.max(11.0, s * 0.27),
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 3),
                        ],
                      ),
                      if (badge != null)
                        Positioned(
                          right: -6,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badge > 0
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF16A34A),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              badge > 0 ? '+$badge' : '✓',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 2),
                  // Name pill: a colored dot carries the identity, the
                  // text itself uses the palette's primary text color so
                  // it stays readable in both themes (raw drone colors
                  // like cyan fail contrast on white).
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: context.palette.isDark ? 0.16 : 0.12,
                        ),
                        border: Border.all(
                          color: color.withValues(alpha: 0.38),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.drone.label,
                            style: TextStyle(
                              color: context.palette.primaryText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the quadcopter: glow, drop shadow, four arms with spinning
/// rotor pods, a gradient body, and the dark camera lens at the center
/// (the specialty icon is overlaid as a widget by [DroneWidget]).
class _DronePainter extends CustomPainter {
  const _DronePainter({
    required this.color,
    required this.progress,
    required this.scanning,
  });

  final Color color;
  final double progress;
  final bool scanning;

  Color _shade(double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final u = size.shortestSide;

    // Halo glow — stronger while scanning.
    canvas.drawCircle(
      center,
      u * 0.36,
      Paint()
        ..color = color.withValues(alpha: scanning ? 0.30 : 0.15)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.12),
    );

    // Ground shadow, so the drone reads as hovering, not pasted on.
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, u * 0.33),
        width: u * 0.56,
        height: u * 0.15,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.05),
    );

    // Scanning radar sweep.
    if (scanning) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: u * 0.47),
        progress * math.pi * 2,
        1.15,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    final rotorCenters = [
      Offset(center.dx - u * 0.31, center.dy - u * 0.31),
      Offset(center.dx + u * 0.31, center.dy - u * 0.31),
      Offset(center.dx - u * 0.31, center.dy + u * 0.31),
      Offset(center.dx + u * 0.31, center.dy + u * 0.31),
    ];

    // Arms.
    final armPaint = Paint()
      ..color = _shade(-0.22)
      ..strokeWidth = u * 0.07
      ..strokeCap = StrokeCap.round;
    for (final rc in rotorCenters) {
      canvas.drawLine(center, rc, armPaint);
    }

    // Rotor pods: a translucent disc, a rim, and a spinning blur arc.
    for (var i = 0; i < rotorCenters.length; i++) {
      final rc = rotorCenters[i];
      final r = u * 0.155;
      canvas.drawCircle(rc, r, Paint()..color = color.withValues(alpha: 0.20));
      canvas.drawCircle(
        rc,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.1, u * 0.018)
          ..color = color.withValues(alpha: 0.75),
      );
      canvas.drawArc(
        Rect.fromCircle(center: rc, radius: r * 0.72),
        progress * math.pi * 2 + i * 1.7,
        4.2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.028
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.38),
      );
      canvas.drawCircle(
        rc,
        u * 0.026,
        Paint()..color = const Color(0xFF101018),
      );
    }

    // Body: a rounded quad with a light-to-dark gradient.
    final bodyRect = Rect.fromCenter(
      center: center,
      width: u * 0.54,
      height: u * 0.48,
    );
    final bodyRRect = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(u * 0.16),
    );
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_shade(0.16), color, _shade(-0.14)],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withValues(alpha: 0.28),
    );

    // Nose marker — which way is "forward" for this little aircraft.
    final noseRect = Rect.fromCenter(
      center: center + Offset(0, -u * 0.185),
      width: u * 0.16,
      height: u * 0.035,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(noseRect, Radius.circular(u * 0.02)),
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );

    // Camera lens (the icon widget sits on top of it).
    canvas.drawCircle(
      center,
      u * 0.185,
      Paint()..color = const Color(0xFF101018),
    );
    canvas.drawCircle(
      center,
      u * 0.185,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(_DronePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.scanning != scanning;
}

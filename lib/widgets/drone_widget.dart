import 'package:flutter/material.dart';

import '../models/message.dart';

/// One specialist drone: a colored orb with spinning rotors, a camera eye,
/// and its name. The drone IS the interface — docked in the bay, flying
/// over the message while it scans, and tappable everywhere to open its
/// walkthrough.
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

  @override
  void dispose() {
    _rotor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.drone.colorValue);
    final s = widget.size;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: s + 14,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: s,
              height: s,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (widget.scanning)
                    AnimatedBuilder(
                      animation: _rotor,
                      builder: (context, child) => Container(
                        width: s * (0.9 + 0.25 * _rotor.value),
                        height: s * (0.9 + 0.25 * _rotor.value),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(
                              alpha: 1 - _rotor.value * 0.8,
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  // Rotor bar
                  AnimatedBuilder(
                    animation: _rotor,
                    builder: (context, child) => Transform.rotate(
                      angle: _rotor.value * 6.28318 * 2,
                      child: Container(
                        width: s * 1.05,
                        height: 3,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  // Body
                  Container(
                    width: s * 0.72,
                    height: s * 0.72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(color: Colors.white24, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: widget.scanning ? 16 : 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: s * 0.26,
                        height: s * 0.26,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF101018),
                        ),
                        child: Center(
                          child: Container(
                            width: s * 0.11,
                            height: s * 0.11,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.badgePoints != null)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: widget.badgePoints! > 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.badgePoints! > 0
                              ? '+${widget.badgePoints}'
                              : '✓',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.showLabel)
              // The longest name ("Impersonator") is wider than the
              // drone's column on narrow phones — scale it down to fit
              // rather than letting it collide with its neighbours.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.drone.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

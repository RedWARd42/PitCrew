import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Hive mark: a centre hexagon ringed by six, in green.
class HiveLogo extends StatelessWidget {
  const HiveLogo({super.key, this.size = 96});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Signal Swarm hive logo',
    child: CustomPaint(size: Size.square(size), painter: _HivePainter()),
  );
}

class _HivePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 6.2;
    final c = s.center(Offset.zero);
    Path hex(Offset o, double rr) {
      final p = Path();
      for (var i = 0; i < 6; i++) {
        final a = math.pi / 6 + i * math.pi / 3;
        final pt = o + Offset(math.cos(a), math.sin(a)) * rr;
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      return p..close();
    }

    final fill = Paint()..color = swarmGreen;
    final line = Paint()
      ..color = swarmGreen.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(hex(c, r), fill);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawPath(
        hex(c + Offset(math.cos(a), math.sin(a)) * r * 1.75, r * .92),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

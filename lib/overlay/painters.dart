import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 56x56 drone: body centre at (28,26), four spinning rotors.
class DronePainter extends CustomPainter {
  final Color color;
  final double phase; // radians
  final double shadow; // 0..1 ground shadow (landed)
  final int arrow; // -1 up, 1 down, 0 none (docked at an edge)
  const DronePainter(this.color, this.phase, {this.shadow = 0, this.arrow = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 - 2);
    if (shadow > 0) {
      canvas.drawOval(Rect.fromCenter(center: Offset(c.dx, size.height - 3), width: 26, height: 6),
          Paint()..color = Colors.black.withValues(alpha: 0.22 * shadow)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    final arm = Paint()..color = const Color(0xFF3A3D45)..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final rc = c + Offset(i.isEven ? -17 : 17, i < 2 ? -13 : 11);
      canvas.drawLine(c, rc, arm);
      canvas.drawCircle(rc, 9, Paint()..color = color.withValues(alpha: 0.16));
      final a = phase * (i.isEven ? 1 : -1) + i;
      final blade = Paint()..color = color.withValues(alpha: 0.9)..strokeWidth = 1.6..strokeCap = StrokeCap.round;
      for (final k in [0.0, math.pi]) {
        canvas.drawLine(rc + Offset.fromDirection(a + k, 8), rc + Offset.fromDirection(a + k, 1.5), blade);
      }
      canvas.drawCircle(rc, 1.8, Paint()..color = const Color(0xFF14161A));
    }
    canvas.drawCircle(
        c,
        12.5,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3B3E47), Color(0xFF13151A)])
              .createShader(Rect.fromCircle(center: c, radius: 12.5)));
    canvas.drawCircle(c, 12.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = color);
    canvas.drawCircle(c, 5, Paint()..color = color.withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(c, 3.6, Paint()..color = color);
    if (arrow != 0) {
      final y = arrow < 0 ? 3.0 : size.height - 3.0;
      final p = Path()
        ..moveTo(c.dx - 5, y + arrow * 3.0)
        ..lineTo(c.dx, y - arrow * 1.5)
        ..lineTo(c.dx + 5, y + arrow * 3.0);
      canvas.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..color = color);
    }
  }

  @override
  bool shouldRepaint(DronePainter o) => o.phase != phase || o.color != color || o.shadow != shadow || o.arrow != arrow;
}

/// 56x56 Hive robot with a status ring. `t` seconds drives blink and sweep.
class HivePainter extends CustomPainter {
  final Color ring;
  final double t;
  final bool scanning;
  final double pulse; // 0..1, <0 none
  const HivePainter(this.ring, this.t, {this.scanning = false, this.pulse = -1});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (pulse >= 0) {
      canvas.drawCircle(c, 27 + pulse * 20, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = ring.withValues(alpha: 0.45 * (1 - pulse)));
    }
    canvas.drawCircle(c + const Offset(0, 2), 26, Paint()..color = Colors.black.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawCircle(c, 25, Paint()..color = const Color(0xFF16181D));
    final rr = Rect.fromCircle(center: c, radius: 25.5);
    final ringP = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round;
    if (scanning) {
      canvas.drawCircle(c, 25.5, ringP..color = ring.withValues(alpha: 0.25));
      canvas.drawArc(rr, t * 4.5, 1.9, false, ringP..color = ring);
    } else {
      canvas.drawCircle(c, 25.5, ringP..color = ring);
    }
    canvas.drawLine(c + const Offset(0, -11), c + const Offset(0, -15), Paint()..color = const Color(0xFF8A8F9A)..strokeWidth = 1.6);
    canvas.drawCircle(c + const Offset(0, -16), 2, Paint()..color = ring);
    final head = RRect.fromRectAndRadius(Rect.fromCenter(center: c + const Offset(0, 2), width: 34, height: 26), const Radius.circular(11));
    canvas.drawRRect(
        head,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF555A66), Color(0xFF2C2F36)])
              .createShader(head.outerRect));
    final visor = RRect.fromRectAndRadius(Rect.fromCenter(center: c + const Offset(0, 2), width: 26, height: 14), const Radius.circular(7));
    canvas.drawRRect(visor, Paint()..color = const Color(0xFF0B0C0F));
    final blink = (t % 4.0) < 0.12 ? 0.15 : 1.0;
    for (final dx in [-5.5, 5.5]) {
      final e = Rect.fromCenter(center: c + Offset(dx, 2), width: 5, height: 6 * blink);
      canvas.drawRRect(RRect.fromRectAndRadius(e.inflate(1.5), const Radius.circular(3)), Paint()..color = ring.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawRRect(RRect.fromRectAndRadius(e, const Radius.circular(2.5)), Paint()..color = ring);
    }
  }

  @override
  bool shouldRepaint(HivePainter o) => true;
}

class Outline {
  final Rect rect;
  final Color color;
  final double t;
  const Outline(this.rect, this.color, this.t);
}

/// Short pennant from a drone to the edge of what it is watching.
class Leader {
  final Offset from, to;
  final Color color;
  final double t;
  const Leader(this.from, this.to, this.color, this.t);
}

class OutlinesPainter extends CustomPainter {
  final List<Outline> items;
  final List<Leader> leaders;
  final Rect? clip; // highlights never draw outside this band (header..compose)
  const OutlinesPainter(this.items, [this.leaders = const [], this.clip]);
  @override
  void paint(Canvas canvas, Size size) {
    if (clip != null) canvas.clipRect(clip!);
    for (final l in leaders) {
      canvas.drawLine(l.from, l.to, Paint()..color = l.color.withValues(alpha: 0.7 * l.t)..strokeWidth = 1.5..strokeCap = StrokeCap.round);
      canvas.drawCircle(l.to, 2.5, Paint()..color = l.color.withValues(alpha: l.t));
    }
    for (final o in items) {
      final rr = RRect.fromRectAndRadius(o.rect.inflate(2), const Radius.circular(8));
      canvas.drawRRect(rr, Paint()..color = o.color.withValues(alpha: 0.06 * o.t));
      canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = o.color.withValues(alpha: 0.16 * o.t)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = o.color.withValues(alpha: 0.95 * o.t));
    }
  }

  @override
  bool shouldRepaint(OutlinesPainter o) => true;
}

class ScanBeamPainter extends CustomPainter {
  final Rect rect;
  final double t; // 0..1 loop
  final Color color;
  const ScanBeamPainter(this.rect, this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(14));
    canvas.save();
    canvas.clipRRect(rr);
    final y = rect.top - 40 + (rect.height + 40) * t;
    final band = Rect.fromLTWH(rect.left, y, rect.width, 40);
    canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.32)])
              .createShader(band));
    canvas.drawRect(Rect.fromLTWH(rect.left, y + 39, rect.width, 1.5), Paint()..color = color.withValues(alpha: 0.9));
    canvas.restore();
    canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = color.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(ScanBeamPainter o) => o.t != t || o.rect != rect;
}

class RiskMeterPainter extends CustomPainter {
  final int score;
  final Color color, track;
  const RiskMeterPainter(this.score, this.color, this.track);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    final w = size.width * (score.clamp(0, 100) / 100);
    if (w > 0) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, math.max(w, size.height), size.height), r), Paint()..color = color);
  }

  @override
  bool shouldRepaint(RiskMeterPainter o) => o.score != score || o.color != color;
}

class SparklinePainter extends CustomPainter {
  final List<double> v;
  final Color line, grid;
  const SparklinePainter(this.v, this.line, this.grid);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), Paint()..color = grid..strokeWidth = 1);
    if (v.length < 2) return;
    const pad = 8.0;
    Offset pt(int i) => Offset(pad + (size.width - 2 * pad) * i / (v.length - 1), pad + (size.height - 2 * pad) * (1 - v[i].clamp(0.0, 1.0)));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      final a = pt(i - 1), b = pt(i), mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pt(v.length - 1).dx, size.height)
      ..lineTo(pt(0).dx, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [line.withValues(alpha: 0.28), line.withValues(alpha: 0)])
              .createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..color = line);
    canvas.drawCircle(pt(v.length - 1), 4.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(SparklinePainter o) => o.v != v || o.line != line;
}

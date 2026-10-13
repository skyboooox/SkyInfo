import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'industrial.dart';

class ValueGauge extends StatelessWidget {
  final double? fraction;
  const ValueGauge({super.key, required this.fraction});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GaugePainter(fraction, Palette.of(context)));
}

class _GaugePainter extends CustomPainter {
  final double? fraction;
  final Palette palette;
  _GaugePainter(this.fraction, this.palette);
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2 - 10, size.height - 12);
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height - 4);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = palette.grid;
    canvas.drawArc(rect, math.pi, math.pi, false, track);
    if (fraction != null) {
      canvas.drawArc(
        rect,
        math.pi,
        math.pi * fraction!.clamp(0, 1),
        false,
        track..color = palette.acid,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.palette != palette;
}

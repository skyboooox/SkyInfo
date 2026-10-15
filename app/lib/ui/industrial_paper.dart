import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'industrial.dart' show Palette;

class IndustrialPaper extends StatelessWidget {
  final Widget child;
  const IndustrialPaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ColoredBox(
      color: p.paper,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _DotGrid(
                      p.grid.withValues(alpha: p == Palette.dark ? .3 : .45),
                    ),
                  ),
                ),
              ),
            ),
          ),
          RepaintBoundary(child: child),
        ],
      ),
    );
  }
}

class _DotGrid extends CustomPainter {
  final Color color;
  const _DotGrid(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      for (double x = 12; x < size.width; x += 24)
        for (double y = 12; y < size.height; y += 24) Offset(x, y),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DotGrid old) => old.color != color;
}

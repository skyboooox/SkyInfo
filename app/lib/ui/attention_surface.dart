import 'package:flutter/material.dart';
import 'motion_clock.dart';

class AttentionSurface extends StatefulWidget {
  final Widget child;
  final Color color;
  final bool animate;
  const AttentionSurface({
    super.key,
    required this.child,
    required this.color,
    this.animate = true,
  });
  @override
  State<AttentionSurface> createState() => _AttentionSurfaceState();
}

class _AttentionSurfaceState extends State<AttentionSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final clock = PaintClock(this);
  bool foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  void sync() => clock.setRunning(
    widget.animate &&
        foreground &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(AttentionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: CustomPaint(
      painter: _AttentionStripes(
        widget.color.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .10 : .06,
        ),
        clock,
      ),
      child: widget.child,
    ),
  );
}

class _AttentionStripes extends CustomPainter {
  final Color color;
  final PaintClock clock;
  _AttentionStripes(this.color, this.clock) : super(repaint: clock);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final offset = (clock.seconds / 1.4 % 1) * 40;
    for (double x = -size.height - 40; x < size.width + 40; x += 40) {
      final start = x + offset;
      canvas.drawPath(
        Path()
          ..moveTo(start, size.height)
          ..lineTo(start + size.height, 0)
          ..lineTo(start + size.height + 20, 0)
          ..lineTo(start + 20, size.height)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_AttentionStripes old) =>
      old.color != color || old.clock != clock;
}

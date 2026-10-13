import 'package:flutter/material.dart';
import 'industrial.dart';

class AttentionSurface extends StatefulWidget {
  final Widget child;
  final Color color;
  const AttentionSurface({super.key, required this.child, required this.color});
  @override
  State<AttentionSurface> createState() => _AttentionSurfaceState();
}

class _AttentionSurfaceState extends State<AttentionSurface>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!animation.isAnimating) animation.repeat();
    } else {
      animation.stop();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, child) => CustomPaint(
        painter: _AttentionStripes(
          widget.color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .10 : .06,
          ),
          animation.value,
        ),
        child: child,
      ),
      child: widget.child,
    ),
  );
}

class _AttentionStripes extends CustomPainter {
  final Color color;
  final double phase;
  _AttentionStripes(this.color, this.phase);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const period = 40.0;
    for (
      double x = -size.height - period;
      x < size.width + period;
      x += period
    ) {
      final offset = x + phase * period;
      final path = Path()
        ..moveTo(offset, size.height)
        ..lineTo(offset + size.height, 0)
        ..lineTo(offset + size.height + 20, 0)
        ..lineTo(offset + 20, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_AttentionStripes old) =>
      old.phase != phase || old.color != color;
}

class CommandFeedback extends StatelessWidget {
  final String status, label;
  const CommandFeedback({super.key, required this.status, required this.label});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final failed = ['error', 'rejected', 'expired', 'dropped'].contains(status);
    final attention = status == 'pending' || failed;
    final color = failed
        ? p.red
        : status == 'pending'
        ? p.warning
        : p.muted;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(
            failed
                ? Icons.error_outline
                : status == 'pending'
                ? Icons.sync
                : status == 'confirmed'
                ? Icons.check_circle_outline
                : Icons.north_east,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, style: TextStyle(fontSize: 16, color: color)),
          ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      child: attention
          ? AttentionSurface(color: color, child: content)
          : content,
    );
  }
}

class LifecycleMotion extends StatefulWidget {
  final Widget child;
  const LifecycleMotion({super.key, required this.child});
  @override
  State<LifecycleMotion> createState() => _LifecycleMotionState();
}

class _LifecycleMotionState extends State<LifecycleMotion>
    with WidgetsBindingObserver {
  bool visible =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => visible = state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: visible, child: widget.child);
}

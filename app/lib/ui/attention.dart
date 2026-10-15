import 'package:flutter/material.dart';
import 'industrial.dart';

import 'attention_surface.dart';
export 'attention_surface.dart';

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

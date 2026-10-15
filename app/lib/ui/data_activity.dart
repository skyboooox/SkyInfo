import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'industrial.dart';

class DataActivityDot extends StatefulWidget {
  final List<ValueListenable<Sample>> readings;
  final Listenable? historyApplied;
  const DataActivityDot({
    super.key,
    required this.readings,
    this.historyApplied,
  });
  @override
  State<DataActivityDot> createState() => _DataActivityDotState();
}

class _DataActivityDotState extends State<DataActivityDot>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: .5,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: .5,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
  ]).animate(animation);
  final listeners = <(ValueListenable<Sample>, VoidCallback)>[];
  bool foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool enabled = false;

  void pulse() {
    if (enabled && foreground && !animation.isAnimating) {
      animation.forward(from: 0);
    }
  }

  void bind() {
    for (final entry in listeners) {
      entry.$1.removeListener(entry.$2);
    }
    listeners.clear();
    for (final reading in widget.readings) {
      Object signature(Sample s) =>
          (s.value, s.raw, s.updatedAt, s.unit, s.source);
      var previous = signature(reading.value);
      void changed() {
        final s = reading.value, next = signature(reading.value);
        if (next == previous) return;
        previous = next;
        if (s.value != null &&
            ['available', 'unverified'].contains(s.quality)) {
          pulse();
        }
      }

      reading.addListener(changed);
      listeners.add((reading, changed));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bind();
    widget.historyApplied?.addListener(pulse);
  }

  @override
  void didUpdateWidget(DataActivityDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.readings, widget.readings)) bind();
    if (oldWidget.historyApplied != widget.historyApplied) {
      oldWidget.historyApplied?.removeListener(pulse);
      widget.historyApplied?.addListener(pulse);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!enabled) animation.reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) animation.reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final entry in listeners) {
      entry.$1.removeListener(entry.$2);
    }
    widget.historyApplied?.removeListener(pulse);
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: FadeTransition(
        opacity: opacity,
        child: SizedBox.square(
          dimension: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Palette.of(context).activity,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ),
  );
}

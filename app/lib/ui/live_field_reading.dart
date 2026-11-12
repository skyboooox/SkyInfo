import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import 'industrial.dart';

/// A visible connection row owns only its own temporary read demand.
class LiveFieldReading extends StatefulWidget {
  final AppController controller;
  final Metric metric;
  const LiveFieldReading({
    super.key,
    required this.controller,
    required this.metric,
  });

  @override
  State<LiveFieldReading> createState() => _LiveFieldReadingState();
}

class _LiveFieldReadingState extends State<LiveFieldReading> {
  late PreviewLease _lease;

  @override
  void initState() {
    super.initState();
    _lease = widget.controller.acquirePreview([widget.metric.id]);
  }

  @override
  void didUpdateWidget(covariant LiveFieldReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _lease.dispose();
      _lease = widget.controller.acquirePreview([widget.metric.id]);
    } else if (oldWidget.metric.id != widget.metric.id) {
      _lease.update([widget.metric.id]);
    }
  }

  @override
  void dispose() {
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Sample>(
    valueListenable: widget.controller.reading(widget.metric.id),
    builder: (context, sample, _) {
      final value = ['available', 'unverified'].contains(sample.quality)
          ? sample.formatted(1)
          : '—';
      final unit = widget.metric.displayUnitFor(sample);
      return Text(
        unit.isEmpty ? value : '$value $unit',
        softWrap: true,
        style: TextStyle(fontSize: 18, color: Palette.of(context).muted),
      );
    },
  );
}

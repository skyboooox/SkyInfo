import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../l10n/strings.dart';
import 'industrial.dart';

typedef HistorySeries = List<List<HistoryPoint>>;

class RetainedHistory extends StatefulWidget {
  final Future<HistorySeries>? future;
  final Widget Function(HistorySeries) builder;
  final VoidCallback? onApplied;
  const RetainedHistory({
    super.key,
    required this.future,
    required this.builder,
    this.onApplied,
  });
  @override
  State<RetainedHistory> createState() => _RetainedHistoryState();
}

class _RetainedHistoryState extends State<RetainedHistory> {
  HistorySeries? previous;
  Future<HistorySeries>? applied;
  @override
  Widget build(BuildContext context) => FutureBuilder<HistorySeries>(
    future: widget.future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData &&
          applied != widget.future) {
        final fresh = !listEquals(previous, snapshot.data);
        previous = snapshot.data;
        applied = widget.future;
        if (fresh && previous!.any((s) => s.isNotEmpty)) {
          final request = applied;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.future == request) widget.onApplied?.call();
          });
        }
      }
      final data = previous;
      final content = data == null
          ? const SizedBox.expand()
          : data.every((s) => s.isEmpty)
          ? Center(child: Text(Strings.text('text_482a16ecfa')))
          : widget.builder(data);
      if (!snapshot.hasError) return content;
      final error = Text(
        snapshot.error.toString().replaceFirst('Bad state: ', ''),
        style: TextStyle(color: Palette.of(context).red, fontSize: 14),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
      return data == null
          ? Center(child: error)
          : Column(
              children: [
                Expanded(child: content),
                error,
              ],
            );
    },
  );
}

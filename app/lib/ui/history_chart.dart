import '../l10n/strings.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import '../domain/models.dart';
import 'industrial.dart';

List<Color> historySeriesColors(Palette p) => [p.blue, p.rose, p.green, p.ink];

class HistoryChart extends StatefulWidget {
  final List<List<HistoryPoint>> series;
  final int minutes;
  final DateTime? windowEnd;
  final double? minimum, maximum;
  const HistoryChart({
    super.key,
    required this.series,
    required this.minutes,
    this.windowEnd,
    this.minimum,
    this.maximum,
  });
  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart>
    with WidgetsBindingObserver {
  double? selection;
  Timer? _selectionTimer;
  int _activePointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _restartSelectionTimer() {
    _selectionTimer?.cancel();
    if (selection == null || _activePointers > 0) return;
    _selectionTimer = Timer(const Duration(seconds: 2), _clearSelection);
  }

  void _select(Offset position, double width) {
    setState(() => selection = ((position.dx - 40) / (width - 48)).clamp(0, 1));
    _restartSelectionTimer();
  }

  void _clearSelection() {
    _selectionTimer?.cancel();
    _selectionTimer = null;
    if (mounted && selection != null) setState(() => selection = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _activePointers = 0;
      _clearSelection();
    }
  }

  @override
  void dispose() {
    _selectionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<List<HistoryPoint>>? _snapshot;
  DateTime? _snapshotEnd;
  _ChartProjection? _projection;

  _ChartProjection project(int buckets, DateTime start, DateTime end) {
    final previous = _projection;
    if (previous != null &&
        previous.buckets == buckets &&
        previous.start == start &&
        previous.end == end) {
      return previous;
    }
    return _projection = _ChartProjection(widget.series, buckets, start, end);
  }

  @override
  Widget build(BuildContext context) {
    // History results are immutable snapshots; only the small outer list is
    // compared because Future.wait may recreate it for the same cached results.
    if (!listEquals(_snapshot, widget.series)) {
      _snapshot = List.of(widget.series);
      _snapshotEnd = null;
      _projection = null;
    }
    final p = Palette.of(context),
        end =
            widget.windowEnd ??
            (_snapshotEnd ??= historySnapshotEnd(
              widget.series,
              DateTime.now(),
            ));
    final start = end.subtract(Duration(minutes: widget.minutes));
    return LayoutBuilder(
      builder: (context, box) {
        final projection = project(
          math.max(1, ((box.maxWidth - 48) / 3).floor()),
          start,
          end,
        );
        final groups = projection.groups;
        if (groups.every((g) => g.isEmpty)) {
          return Center(child: Text(Strings.text('text_482a16ecfa')));
        }
        String time(DateTime? at) {
          if (at == null) return '—';
          final local = at.toLocal();
          return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
        }

        final target = selection == null
            ? null
            : start.add(
                Duration(
                  milliseconds:
                      (end.difference(start).inMilliseconds * selection!)
                          .round(),
                ),
              );
        final selected = target == null
            ? <({HistoryBucket bucket, bool held})>[]
            : groups
                  .map((segments) => historySelectionAt(segments, target))
                  .whereType<({HistoryBucket bucket, bool held})>()
                  .toList();
        return Listener(
          onPointerDown: (_) {
            _activePointers++;
            _selectionTimer?.cancel();
          },
          onPointerUp: (_) {
            _activePointers = math.max(0, _activePointers - 1);
            _restartSelectionTimer();
          },
          onPointerCancel: (_) {
            _activePointers = math.max(0, _activePointers - 1);
            _restartSelectionTimer();
          },
          child: GestureDetector(
            onTapUp: (_) => _restartSelectionTimer(),
            onTapDown: (details) =>
                _select(details.localPosition, box.maxWidth),
            onHorizontalDragStart: (details) =>
                _select(details.localPosition, box.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _select(details.localPosition, box.maxWidth),
            onHorizontalDragEnd: (_) => _restartSelectionTimer(),
            onLongPress: _clearSelection,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size(box.maxWidth, box.maxHeight),
                      painter: _ChartPainter(
                        projection,
                        p,
                        widget.minimum,
                        widget.maximum,
                      ),
                    ),
                  ),
                ),
                if (selected.isNotEmpty)
                  Positioned(
                    left: 40,
                    right: 8,
                    top: 12,
                    child: Container(
                      color: p.paper,
                      padding: EdgeInsets.all(8),
                      constraints: BoxConstraints(
                        maxHeight: math.max(0, box.maxHeight - 24),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final item in selected)
                              Text(
                                item.held
                                    ? Strings.text('history_held_value', {
                                        'time': time(
                                          item.bucket.sampleCount == 0
                                              ? item.bucket.representativeAt
                                              : item.bucket.lastAt,
                                        ),
                                        'value':
                                            (item.bucket.lastValue ??
                                                    item.bucket.representative)
                                                .toStringAsFixed(2),
                                      })
                                    : Strings.text('history_bucket_summary', {
                                        'start': time(item.bucket.rangeStart),
                                        'end': time(item.bucket.rangeEnd),
                                        'mean': item.bucket.representative
                                            .toStringAsFixed(2),
                                        'count': item.bucket.sampleCount,
                                        'min': item.bucket.min.toStringAsFixed(
                                          2,
                                        ),
                                        'minTime': time(item.bucket.minimumAt),
                                        'max': item.bucket.max.toStringAsFixed(
                                          2,
                                        ),
                                        'maxTime': time(item.bucket.maximumAt),
                                      }),
                                style: TextStyle(fontSize: 14),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChartProjection {
  final int buckets;
  final DateTime start, end;
  final List<List<List<HistoryBucket>>> groups;
  // Geometry is independent of theme and is retained only for the current
  // viewport/axis. Resizing replaces it rather than growing a cache.
  _ChartGeometry? geometry;
  _ChartProjection(
    List<List<HistoryPoint>> series,
    this.buckets,
    this.start,
    this.end,
  ) : groups = [
        for (final points in series)
          aggregateHistory(points, buckets, start, end),
      ];
}

class _ChartGeometry {
  final Size size;
  final double? minimum, maximum;
  final Rect plot;
  final double low, high;
  final List<List<_ChartStroke>> series;
  _ChartGeometry(
    this.size,
    this.minimum,
    this.maximum,
    this.plot,
    this.low,
    this.high,
    this.series,
  );
}

class _ChartStroke {
  final List<(Path, bool)> ranges;
  final Path line;
  final Offset? dot;
  _ChartStroke(this.ranges, this.line, this.dot);
}

class _ChartPainter extends CustomPainter {
  final _ChartProjection projection;
  final Palette p;
  final double? minimum, maximum;
  _ChartPainter(this.projection, this.p, this.minimum, this.maximum);
  void label(Canvas c, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: 'ChillDIN', fontSize: 14, color: p.muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
    tp.dispose();
  }

  _ChartGeometry geometry(Size size) {
    final old = projection.geometry;
    if (old != null &&
        old.size == size &&
        old.minimum == minimum &&
        old.maximum == maximum) {
      return old;
    }
    final plot = Rect.fromLTWH(
      40,
      12,
      math.max(1, size.width - 48),
      math.max(1, size.height - 44),
    );
    var low = double.infinity, high = double.negativeInfinity;
    for (final series in projection.groups) {
      for (final segment in series) {
        for (final bucket in segment) {
          low = math.min(low, bucket.min);
          high = math.max(high, bucket.max);
        }
      }
    }
    if (high == low) {
      high += 1;
      low -= 1;
    }
    final margin = (high - low) * 0.08;
    high += margin;
    low -= margin;
    if (minimum != null && maximum != null && maximum! > minimum!) {
      low = minimum!;
      high = maximum!;
    }
    double x(DateTime t) =>
        plot.left +
        plot.width *
            t.difference(projection.start).inMilliseconds /
            projection.end.difference(projection.start).inMilliseconds;
    double y(double value) =>
        plot.bottom - (value - low) / (high - low) * plot.height;
    final series = <List<_ChartStroke>>[];
    for (var s = 0; s < projection.groups.length; s++) {
      final strokes = <_ChartStroke>[];
      for (var i = 0; i < projection.groups[s].length; i++) {
        final segment = projection.groups[s][i];
        final band = <(Path, bool)>[];
        for (final run in historyEnvelopeRuns(segment)) {
          if (run.length == 1) {
            final b = run.single;
            if (b.sampleCount < 2 || b.min == b.max) continue;
            final left = x(b.startAt!), right = x(b.lastAt!);
            final path = Path()
              ..moveTo(left, y(b.max))
              ..lineTo(right, y(b.max))
              ..lineTo(right, y(b.min))
              ..lineTo(left, y(b.min))
              ..close();
            band.add((path, left == right));
            continue;
          }
          final path = Path()..moveTo(x(run.first.at), y(run.first.max));
          for (final b in run.skip(1)) {
            path.lineTo(x(b.at), y(b.max));
          }
          for (final b in run.reversed) {
            path.lineTo(x(b.at), y(b.min));
          }
          path.close();
          band.add((path, false));
        }
        final vertices = historyLineVertices(segment);
        final line = Path()..moveTo(x(vertices.first.$1), y(vertices.first.$2));
        for (final vertex in vertices.skip(1)) {
          line.lineTo(x(vertex.$1), y(vertex.$2));
        }
        strokes.add(
          _ChartStroke(
            band,
            line,
            vertices.length == 1
                ? Offset(x(segment.first.at), y(segment.first.representative))
                : null,
          ),
        );
      }
      series.add(strokes);
    }
    return projection.geometry = _ChartGeometry(
      size,
      minimum,
      maximum,
      plot,
      low,
      high,
      series,
    );
  }

  @override
  void paint(Canvas c, Size size) {
    final data = geometry(size), plot = data.plot;
    final grid = Paint()
      ..color = p.grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4,
          x = plot.left + plot.width * i / 4;
      c.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      c.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      label(
        c,
        (data.low + (data.high - data.low) * i / 4).toStringAsFixed(1),
        Offset(0, y - 8),
      );
    }
    c.save();
    c.clipRect(plot);
    final colors = historySeriesColors(p);
    for (var s = 0; s < data.series.length; s++) {
      final color = colors[s % colors.length];
      final fill = Paint()
        ..color = color.withValues(alpha: p == Palette.dark ? 0.24 : 0.18);
      final stroke = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      for (final segment in data.series[s]) {
        for (final range in segment.ranges) {
          c.drawPath(
            range.$1,
            range.$2
                ? (Paint()
                    ..color = fill.color
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1)
                : fill,
          );
        }
        c.drawPath(segment.line, stroke);
        if (segment.dot != null) {
          c.drawCircle(segment.dot!, 2, Paint()..color = color);
        }
      }
    }
    c.restore();
    String time(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    label(c, time(projection.start), Offset(plot.left, plot.bottom + 8));
    label(
      c,
      time(projection.end),
      Offset(math.max(plot.left, plot.right - 40), plot.bottom + 8),
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.projection != projection ||
      old.p != p ||
      old.minimum != minimum ||
      old.maximum != maximum;
}

class StateTimeline extends StatefulWidget {
  final List<HistoryPoint> points;
  final int minutes;
  const StateTimeline({super.key, required this.points, required this.minutes});
  @override
  State<StateTimeline> createState() => _StateTimelineState();
}

class _StateTimelineState extends State<StateTimeline> {
  late List<HistoryPoint> ordered;
  late List<String> states;
  late DateTime end;
  void snapshot() {
    ordered = [...widget.points]..sort((a, b) => a.at.compareTo(b.at));
    states = widget.points
        .map((p) => p.state ?? Strings.text('text_beff4a1cd1'))
        .toSet()
        .toList();
    end = historySnapshotEnd([widget.points], DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    snapshot();
  }

  @override
  void didUpdateWidget(StateTimeline old) {
    super.didUpdateWidget(old);
    if (old.points != widget.points) snapshot();
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      Palette.of(context).ink,
      Palette.of(context).blue,
      Palette.of(context).acid,
      Palette.of(context).rose,
    ];
    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _TimelinePainter(
                ordered,
                widget.minutes,
                Palette.of(context),
                states,
                colors,
                end,
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (var i = 0; i < states.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    color: colors[i % colors.length],
                  ),
                  SizedBox(width: 6),
                  Text(states[i], style: TextStyle(fontSize: 16)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<HistoryPoint> points;
  final int minutes;
  final Palette palette;
  final List<String> states;
  final List<Color> colors;
  final DateTime end;
  _TimelinePainter(
    this.points,
    this.minutes,
    this.palette,
    this.states,
    this.colors,
    this.end,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final start = end.subtract(Duration(minutes: minutes));
    final ordered = points;
    final area = Rect.fromLTWH(0, size.height / 2 - 20, size.width, 40);
    canvas.drawRect(area, Paint()..color = palette.grid);
    for (var i = 0; i < ordered.length; i++) {
      final from = ordered[i].at.isBefore(start) ? start : ordered[i].at;
      final until = i + 1 < ordered.length ? ordered[i + 1].at : end;
      if (until.isBefore(start) || from.isAfter(end)) continue;
      final state = ordered[i].state ?? Strings.text('text_beff4a1cd1');
      final left =
          (from.difference(start).inMilliseconds /
                  end.difference(start).inMilliseconds *
                  size.width)
              .clamp(0.0, size.width);
      final right =
          (until.difference(start).inMilliseconds /
                  end.difference(start).inMilliseconds *
                  size.width)
              .clamp(0.0, size.width);
      if (right <= left) continue;
      final unavailable = [
        'unknown',
        'unavailable',
        Strings.text('text_beff4a1cd1'),
      ].contains(state);
      canvas.drawRect(
        Rect.fromLTRB(left, area.top, right, area.bottom),
        Paint()
          ..color = unavailable
              ? palette.grid
              : colors[states.indexOf(state) % colors.length],
      );
    }
    String time(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    for (final item in [
      (time(start), 0.0),
      (time(end), math.max(0.0, size.width - 44)),
    ]) {
      final text = TextPainter(
        text: TextSpan(
          text: item.$1,
          style: TextStyle(
            fontFamily: 'ChillDIN',
            fontSize: 14,
            color: palette.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(item.$2, area.bottom + 12));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.points != points ||
      old.palette != palette ||
      old.minutes != minutes ||
      old.end != end;
}

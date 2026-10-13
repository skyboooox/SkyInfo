import '../l10n/strings.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'industrial.dart';

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

class _HistoryChartState extends State<HistoryChart> {
  double? selection;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context),
        end =
            widget.windowEnd ??
            historySnapshotEnd(widget.series, DateTime.now());
    final start = end.subtract(Duration(minutes: widget.minutes));
    return LayoutBuilder(
      builder: (context, box) {
        final groups = widget.series
            .map(
              (s) => aggregateHistory(
                s,
                math.max(1, (box.maxWidth / 3).floor()),
                start,
                end,
              ),
            )
            .toList();
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
            ? <HistoryBucket>[]
            : groups
                  .map((segments) {
                    for (final segment in segments) {
                      final first = segment.first.startAt ?? segment.first.at;
                      final last =
                          segment.last.observedUntil ?? segment.last.at;
                      if (target.isBefore(first) || target.isAfter(last)) {
                        continue;
                      }
                      return segment
                          .where((b) => !(b.startAt ?? b.at).isAfter(target))
                          .lastOrNull;
                    }
                    return null;
                  })
                  .whereType<HistoryBucket>()
                  .toList();
        return GestureDetector(
          onTapDown: (details) => setState(
            () => selection =
                ((details.localPosition.dx - 40) / (box.maxWidth - 48)).clamp(
                  0,
                  1,
                ),
          ),
          onLongPress: () => setState(() => selection = null),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  size: Size(box.maxWidth, box.maxHeight),
                  painter: _ChartPainter(
                    groups,
                    start,
                    end,
                    p,
                    widget.minimum,
                    widget.maximum,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final b in selected)
                          Text(
                            Strings.text('text_a61b02882d', {
                              'value0': time(b.representativeAt ?? b.at),
                              'value1': b.representative.toStringAsFixed(2),
                              'value2': b.min.toStringAsFixed(2),
                              'value3': time(b.minimumAt),
                              'value4': b.max.toStringAsFixed(2),
                              'value5': time(b.maximumAt),
                            }),
                            style: TextStyle(fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<List<List<HistoryBucket>>> series;
  final DateTime start, end;
  final Palette p;
  final double? minimum, maximum;
  _ChartPainter(
    this.series,
    this.start,
    this.end,
    this.p,
    this.minimum,
    this.maximum,
  );
  void label(Canvas c, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: 'ChillDIN', fontSize: 14, color: p.muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
  }

  @override
  void paint(Canvas c, Size size) {
    final plot = Rect.fromLTWH(
      40,
      12,
      math.max(1, size.width - 48),
      math.max(1, size.height - 44),
    );
    final all = series.expand((s) => s).expand((s) => s).toList();
    if (all.isEmpty) return;
    var low = all.map((b) => b.min).reduce(math.min),
        high = all.map((b) => b.max).reduce(math.max);
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
        (low + (high - low) * i / 4).toStringAsFixed(1),
        Offset(0, y - 8),
      );
    }
    double x(DateTime t) =>
        plot.left +
        plot.width *
            t.difference(start).inMilliseconds /
            end.difference(start).inMilliseconds;
    double y(double value) =>
        plot.bottom - (value - low) / (high - low) * plot.height;
    c.save();
    c.clipRect(plot);
    final colors = [p.ink, p.blue, p.rose, p.green];
    for (var s = 0; s < series.length; s++) {
      final color = colors[s % colors.length];
      for (final segment in series[s]) {
        if (segment.isEmpty) continue;
        for (final b in segment) {
          if (b.min == b.max ||
              b.rangeStart == null ||
              b.rangeEnd == null ||
              !b.rangeEnd!.isAfter(b.rangeStart!)) {
            continue;
          }
          c.drawRect(
            Rect.fromLTRB(x(b.rangeStart!), y(b.max), x(b.rangeEnd!), y(b.min)),
            Paint()
              ..color = color.withValues(
                alpha: p == Palette.dark ? 0.16 : 0.12,
              ),
          );
        }
        final vertices = historyLineVertices(segment);
        final line = Path()..moveTo(x(vertices.first.$1), y(vertices.first.$2));
        for (final vertex in vertices.skip(1)) {
          line.lineTo(x(vertex.$1), y(vertex.$2));
        }
        c.drawPath(
          line,
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
        if (vertices.length == 1) {
          c.drawCircle(
            Offset(x(segment.first.at), y(segment.first.representative)),
            2,
            Paint()..color = color,
          );
        }
      }
    }
    c.restore();
    String time(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    label(c, time(start), Offset(plot.left, plot.bottom + 8));
    label(
      c,
      time(end),
      Offset(math.max(plot.left, plot.right - 40), plot.bottom + 8),
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

class StateTimeline extends StatelessWidget {
  final List<HistoryPoint> points;
  final int minutes;
  const StateTimeline({super.key, required this.points, required this.minutes});
  @override
  Widget build(BuildContext context) {
    final colors = [
      Palette.of(context).ink,
      Palette.of(context).blue,
      Palette.of(context).acid,
      Palette.of(context).rose,
    ];
    final states = points
        .map((p) => p.state ?? Strings.text('text_beff4a1cd1'))
        .toSet()
        .toList();
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _TimelinePainter(
              points,
              minutes,
              Palette.of(context),
              states,
              colors,
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
  _TimelinePainter(
    this.points,
    this.minutes,
    this.palette,
    this.states,
    this.colors,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final end = DateTime.now(),
        start = DateTime.now().subtract(Duration(minutes: minutes));
    final ordered = [...points]..sort((a, b) => a.at.compareTo(b.at));
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
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.points != points || old.palette != palette;
}

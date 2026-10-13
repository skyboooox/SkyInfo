import 'dart:math' as math;
import 'metrics.dart';

class HistoryPoint {
  final DateTime at;
  final double? value;
  final String segment;
  final String? state;
  final DateTime? observedUntil, snapshotAt, sourceAt;
  const HistoryPoint(
    this.at,
    this.value, {
    this.segment = '',
    this.state,
    this.observedUntil,
    this.snapshotAt,
    this.sourceAt,
  });
}

class HistoryBucket {
  final DateTime at;
  final double min, max, representative;
  final double? firstValue;
  final List<HistoryPoint> points;
  final DateTime? minimumAt,
      maximumAt,
      startAt,
      rangeStart,
      rangeEnd,
      observedUntil,
      representativeAt;
  const HistoryBucket(
    this.at,
    this.min,
    this.max,
    this.representative, {
    this.firstValue,
    this.points = const [],
    this.minimumAt,
    this.maximumAt,
    this.startAt,
    this.rangeStart,
    this.rangeEnd,
    this.observedUntil,
    this.representativeAt,
  });
}

DateTime historySnapshotEnd(
  List<List<HistoryPoint>> series,
  DateTime fallback,
) {
  final times = series
      .expand((s) => s)
      .map((p) => p.snapshotAt)
      .whereType<DateTime>();
  return times.isEmpty
      ? fallback
      : times.reduce((a, b) => a.isAfter(b) ? a : b);
}

List<List<HistoryBucket>> aggregateHistory(
  List<HistoryPoint> input,
  int buckets,
  DateTime start,
  DateTime end,
) {
  if (buckets < 1 || !end.isAfter(start)) return [];
  final ordered = input.where((p) => !p.at.isAfter(end)).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  final visible = ordered.where((p) => !p.at.isBefore(start)).toList();
  final preceding = ordered.where((p) => p.at.isBefore(start)).lastOrNull;
  bool valid(HistoryPoint p) => p.value != null && p.value!.isFinite;
  if (preceding != null &&
      valid(preceding) &&
      ((preceding.observedUntil?.isAfter(start) ?? false) ||
          (visible.isNotEmpty &&
              (visible.first.segment == preceding.segment ||
                  !valid(visible.first))))) {
    visible.insert(
      0,
      HistoryPoint(
        start,
        preceding.value,
        segment: preceding.segment,
        state: preceding.state,
        sourceAt: preceding.sourceAt ?? preceding.at,
        observedUntil: preceding.observedUntil,
        snapshotAt: preceding.snapshotAt,
      ),
    );
  }
  final result = <List<HistoryBucket>>[];
  var segment = <HistoryPoint>[];
  DateTime clampTime(DateTime t) => t.isBefore(start)
      ? start
      : t.isAfter(end)
      ? end
      : t;
  void flush([DateTime? unavailableAt]) {
    if (segment.isEmpty) return;
    final until = clampTime(
      segment.last.observedUntil ?? unavailableAt ?? segment.last.at,
    );
    final groups = <int, List<HistoryPoint>>{};
    for (final p in segment) {
      final key = math.min(
        buckets - 1,
        ((p.at.millisecondsSinceEpoch - start.millisecondsSinceEpoch) *
                buckets /
                end.difference(start).inMilliseconds)
            .floor(),
      );
      groups.putIfAbsent(key, () => []).add(p);
    }
    final current = <HistoryBucket>[];
    for (final entry in groups.entries) {
      final g = entry.value, values = g.map((p) => p.value!).toList();
      final low = values.reduce(math.min), high = values.reduce(math.max);
      final left = start.add(
        Duration(
          milliseconds:
              (end.difference(start).inMilliseconds * entry.key / buckets)
                  .ceil(),
        ),
      );
      final right = start.add(
        Duration(
          milliseconds:
              (end.difference(start).inMilliseconds * (entry.key + 1) / buckets)
                  .ceil(),
        ),
      );
      current.add(
        HistoryBucket(
          g.last.at,
          low,
          high,
          values.last,
          firstValue: values.first,
          points: List.unmodifiable(g),
          startAt: g.first.at,
          representativeAt: g.last.sourceAt ?? g.last.at,
          minimumAt:
              g[values.indexOf(low)].sourceAt ?? g[values.indexOf(low)].at,
          maximumAt:
              g[values.indexOf(high)].sourceAt ?? g[values.indexOf(high)].at,
          rangeStart: left.isBefore(segment.first.at) ? segment.first.at : left,
          rangeEnd: right.isAfter(until) ? until : right,
          observedUntil:
              entry.key == groups.keys.last && until.isAfter(g.last.at)
              ? until
              : null,
        ),
      );
    }
    result.add(current);
    segment = [];
  }

  String? lastSegment;
  for (final p in visible) {
    if (!valid(p)) {
      flush(p.at);
      lastSegment = null;
      continue;
    }
    if (lastSegment != null && lastSegment != p.segment) flush();
    segment.add(p);
    lastSegment = p.segment;
  }
  flush();
  return result;
}

List<(DateTime, double)> historyLineVertices(List<HistoryBucket> segment) {
  final points = segment
      .expand(
        (b) => b.points.isNotEmpty
            ? b.points
            : [
                HistoryPoint(
                  b.startAt ?? b.at,
                  b.firstValue ?? b.representative,
                ),
                if (b.startAt != null && b.startAt != b.at)
                  HistoryPoint(b.at, b.representative),
              ],
      )
      .toList();
  final intervals = <int>[];
  for (var i = 1; i < points.length; i++) {
    final delta = points[i].at.difference(points[i - 1].at).inMilliseconds;
    if (delta > 0) intervals.add(delta);
  }
  intervals.sort();
  final continuousInterval = intervals.isEmpty
      ? 5000
      : (intervals[intervals.length ~/ 2] * 3).clamp(5000, 30000);
  final vertices = <(DateTime, double)>[];
  void add(DateTime at, double value) {
    if (vertices.isEmpty || vertices.last != (at, value)) {
      vertices.add((at, value));
    }
  }

  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    if (i > 0 &&
        point.at
                .difference(points[i - 1].sourceAt ?? points[i - 1].at)
                .inMilliseconds >
            continuousInterval) {
      add(point.at, points[i - 1].value!);
    }
    add(point.at, point.value!);
  }
  if (segment.isNotEmpty && segment.last.observedUntil != null) {
    add(segment.last.observedUntil!, segment.last.representative);
  }
  return vertices;
}

bool comparableFields(List<String> fields, List<Metric> catalog) {
  final metrics = fields
      .map((id) => catalog.firstWhere((m) => m.id == id))
      .toList();
  if (metrics.isEmpty ||
      metrics.any((m) => ['enum', 'text'].contains(m.encoding))) {
    return false;
  }
  if (metrics.every((m) => m.unit.isNotEmpty) &&
      metrics.map((m) => (m.unit, m.encoding)).toSet().length == 1) {
    return true;
  }
  return fields.length == 2 &&
      fields.toSet().containsAll(const [
        '1014/5/1148190752',
        '1014/5/1148190736',
      ]);
}

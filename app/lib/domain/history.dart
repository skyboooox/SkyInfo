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
  /// Representative time and arithmetic mean of actual samples in this bucket.
  final DateTime at;
  final double min, max, representative;
  final double? firstValue, lastValue;
  final int sampleCount;
  final bool continuousFromPrevious, holdFromPrevious;
  final DateTime? minimumAt,
      maximumAt,
      startAt,
      lastAt,
      rangeStart,
      rangeEnd,
      observedUntil,
      representativeAt,
      validBefore;
  const HistoryBucket(
    this.at,
    this.min,
    this.max,
    this.representative, {
    this.firstValue,
    this.lastValue,
    this.sampleCount = 0,
    this.continuousFromPrevious = false,
    this.holdFromPrevious = false,
    this.minimumAt,
    this.maximumAt,
    this.startAt,
    this.lastAt,
    this.rangeStart,
    this.rangeEnd,
    this.observedUntil,
    this.representativeAt,
    this.validBefore,
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
  final ordered = input.where((p) => !p.at.isAfter(end)).toList();
  // Immutable SQLite snapshots are normally already chronological.
  for (var i = 1; i < ordered.length; i++) {
    if (ordered[i].at.isBefore(ordered[i - 1].at)) {
      ordered.sort((a, b) => a.at.compareTo(b.at));
      break;
    }
  }
  final span = end.difference(start).inMicroseconds;
  final visible = ordered.where((p) => !p.at.isBefore(start)).toList();
  final preceding = ordered.where((p) => p.at.isBefore(start)).lastOrNull;
  bool valid(HistoryPoint p) => p.value != null && p.value!.isFinite;
  HistoryPoint? boundary;
  if (preceding != null &&
      valid(preceding) &&
      ((preceding.observedUntil?.isAfter(start) ?? false) ||
          (visible.isNotEmpty &&
              (visible.first.segment == preceding.segment ||
                  !valid(visible.first))))) {
    boundary = preceding;
  }
  final result = <List<HistoryBucket>>[];
  var segment = <HistoryPoint>[];
  DateTime clampTime(DateTime t) => t.isBefore(start)
      ? start
      : t.isAfter(end)
      ? end
      : t;
  int bucketOf(DateTime at) => math.min(
    buckets - 1,
    (at.difference(start).inMicroseconds * buckets / span).floor(),
  );
  void flush([DateTime? boundaryAt, bool holdToBoundary = false]) {
    if (segment.isEmpty && boundary == null) return;
    final last = segment.lastOrNull ?? boundary!;
    var until = clampTime(
      last.observedUntil ?? (holdToBoundary ? boundaryAt : null) ?? last.at,
    );
    if (boundaryAt != null && until.isAfter(boundaryAt)) {
      until = clampTime(boundaryAt);
    }
    if (segment.isEmpty && !until.isAfter(start)) {
      boundary = null;
      return;
    }
    final intervals = <int>[];
    for (var i = 1; i < segment.length; i++) {
      final delta = segment[i].at.difference(segment[i - 1].at).inMicroseconds;
      if (delta > 0) intervals.add(delta);
    }
    intervals.sort();
    final continuousInterval = intervals.isEmpty
        ? 5000000
        : (((intervals[(intervals.length - 1) ~/ 2] +
                          intervals[intervals.length ~/ 2]) /
                      2) *
                  3)
              .round()
              .clamp(5000000, 30000000);
    final current = <HistoryBucket>[];
    final predecessor = boundary;
    if (predecessor != null) {
      current.add(
        HistoryBucket(
          start,
          predecessor.value!,
          predecessor.value!,
          predecessor.value!,
          firstValue: predecessor.value,
          lastValue: predecessor.value,
          startAt: start,
          lastAt: start,
          representativeAt: predecessor.sourceAt ?? predecessor.at,
          observedUntil: segment.isEmpty ? until : null,
          validBefore: segment.isEmpty ? boundaryAt : null,
        ),
      );
    }
    // A bucket contains only actual samples. Long gaps start a separate run,
    // even if both updates fall in the same wide time bucket.
    var from = 0;
    int? previousKey;
    while (from < segment.length) {
      final first = segment[from], key = bucketOf(first.at);
      var to = from + 1;
      while (to < segment.length &&
          bucketOf(segment[to].at) == key &&
          segment[to].at.difference(segment[to - 1].at).inMicroseconds <=
              continuousInterval) {
        to++;
      }
      var minimum = first, maximum = first;
      var mean = 0.0, timeSum = 0.0;
      for (var i = from; i < to; i++) {
        final point = segment[i];
        mean += (point.value! - mean) / (i - from + 1);
        timeSum += point.at.difference(first.at).inMicroseconds;
        if (point.value! < minimum.value!) minimum = point;
        if (point.value! > maximum.value!) maximum = point;
      }
      final last = segment[to - 1];
      final at = first.at.add(
        Duration(microseconds: (timeSum / (to - from)).round()),
      );
      final left = start.add(
        Duration(microseconds: (span * key / buckets).ceil()),
      );
      final right = start.add(
        Duration(microseconds: (span * (key + 1) / buckets).ceil()),
      );
      current.add(
        HistoryBucket(
          at,
          minimum.value!,
          maximum.value!,
          mean,
          firstValue: first.value,
          lastValue: last.value,
          sampleCount: to - from,
          validBefore: to == segment.length ? boundaryAt : null,
          startAt: first.at,
          lastAt: last.at,
          representativeAt: at,
          minimumAt: minimum.sourceAt ?? minimum.at,
          maximumAt: maximum.sourceAt ?? maximum.at,
          rangeStart: left.isBefore(first.at) ? first.at : left,
          rangeEnd:
              to == segment.length ||
                  segment[to].at.difference(last.at).inMicroseconds >
                      continuousInterval
              ? last.at
              : (right.isAfter(until) ? until : right),
          holdFromPrevious: from == 0
              ? predecessor != null
              : first.at.difference(segment[from - 1].at).inMicroseconds >
                    continuousInterval,
          continuousFromPrevious:
              previousKey != null &&
              key == previousKey + 1 &&
              first.at.difference(segment[from - 1].at).inMicroseconds <=
                  continuousInterval,
          observedUntil: to == segment.length && until.isAfter(last.at)
              ? until
              : null,
        ),
      );
      previousKey = key;
      from = to;
    }
    result.add(current);
    segment = [];
    boundary = null;
  }

  String? lastSegment = boundary?.segment;
  for (final p in visible) {
    if (!valid(p)) {
      flush(p.at, true);
      lastSegment = null;
      continue;
    }
    if (lastSegment != null && lastSegment != p.segment) flush(p.at);
    segment.add(p);
    lastSegment = p.segment;
  }
  flush();
  return result;
}

List<(DateTime, double)> historyLineVertices(List<HistoryBucket> segment) {
  final vertices = <(DateTime, double)>[];
  void add(DateTime at, double value) {
    if (vertices.isEmpty || vertices.last != (at, value)) {
      vertices.add((at, value));
    }
  }

  for (var i = 0; i < segment.length; i++) {
    final bucket = segment[i];
    if (i > 0 && bucket.holdFromPrevious) {
      final previous = segment[i - 1];
      final value = previous.lastValue ?? previous.representative;
      add(previous.lastAt ?? previous.at, value);
      add(bucket.startAt ?? bucket.at, value);
    }
    add(bucket.at, bucket.representative);
  }
  if (segment.isNotEmpty && segment.last.observedUntil != null) {
    final last = segment.last;
    final value = last.lastValue ?? last.representative;
    add(last.lastAt ?? last.at, value);
    add(last.observedUntil!, value);
  }
  return vertices;
}

/// Selection resolves summaries and known-value holds separately.
({HistoryBucket bucket, bool held})? historySelectionAt(
  List<List<HistoryBucket>> segments,
  DateTime target,
) {
  for (final segment in segments) {
    final first = segment.first.startAt ?? segment.first.at;
    final last =
        segment.last.observedUntil ?? segment.last.lastAt ?? segment.last.at;
    if (target.isBefore(first) ||
        target.isAfter(last) ||
        (segment.last.validBefore != null &&
            !target.isBefore(segment.last.validBefore!))) {
      continue;
    }
    for (var i = segment.length - 1; i >= 0; i--) {
      final bucket = segment[i];
      if (target.isBefore(bucket.startAt ?? bucket.at)) continue;
      final afterSamples = target.isAfter(bucket.lastAt ?? bucket.at);
      final holdsAfter =
          i == segment.length - 1 || segment[i + 1].holdFromPrevious;
      final withinRange =
          bucket.rangeEnd != null && !target.isAfter(bucket.rangeEnd!);
      return (
        bucket: bucket,
        held:
            bucket.sampleCount == 0 ||
            (afterSamples && (holdsAfter || !withinRange)),
      );
    }
  }
  return null;
}

/// Consecutive occupied buckets form one extrema envelope. Boundary holds and
/// empty buckets never create ranges or bridge the envelope.
List<List<HistoryBucket>> historyEnvelopeRuns(List<HistoryBucket> segment) {
  final runs = <List<HistoryBucket>>[];
  for (final bucket in segment) {
    if (bucket.sampleCount == 0) continue;
    if (!bucket.continuousFromPrevious || runs.isEmpty) runs.add([]);
    runs.last.add(bucket);
  }
  return runs;
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

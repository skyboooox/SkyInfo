import 'dart:async';
import 'package:flutter/scheduler.dart';
import '../domain/build_channel.dart';

/// Opt-in elapsed-time aggregates. No samples, configuration or logs are retained.
class RuntimePerformance {
  final bool enabled;
  final void Function(int, Map<String, int>) report;
  final void Function(TimingsCallback) addTimings, removeTimings;
  final int Function()? clockMicros;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, int> _counts = {};
  Timer? _timer;
  int? _session;
  int _started = 0;
  late final TimingsCallback _frames = _recordFrames;

  RuntimePerformance({
    this.enabled = BuildChannel.name == 'alpha',
    required this.report,
    this.clockMicros,
    void Function(TimingsCallback)? addTimings,
    void Function(TimingsCallback)? removeTimings,
  }) : addTimings =
           addTimings ??
           ((callback) =>
               SchedulerBinding.instance.addTimingsCallback(callback)),
       removeTimings =
           removeTimings ??
           ((callback) =>
               SchedulerBinding.instance.removeTimingsCallback(callback));

  bool get active => _session != null;
  int get _micros => clockMicros?.call() ?? _clock.elapsedMicroseconds;
  int? begin() => active ? _micros : null;
  void add(String key, [int amount = 1]) {
    if (active) _counts[key] = (_counts[key] ?? 0) + amount;
  }

  void applied(int? started, int entries) {
    if (started == null || !active) return;
    final micros = _micros - started;
    add('applyCalls');
    add('sampleEntries', entries);
    add('applyMicros', micros);
    if (micros > (_counts['applyMaxMicros'] ?? 0)) {
      _counts['applyMaxMicros'] = micros;
    }
  }

  void control(Map<dynamic, dynamic> value) {
    if (!enabled) return;
    final session = value['session'], duration = value['durationMillis'];
    if (session is! int || session < 1) return;
    if (value['action'] == 'stop') {
      if (session == _session) _finish();
    } else if (value['action'] == 'start' &&
        !active &&
        duration is int &&
        duration > 0 &&
        duration <= 180000) {
      _session = session;
      _counts.clear();
      _started = _micros;
      addTimings(_frames);
      _timer = Timer(Duration(milliseconds: duration), _finish);
    }
  }

  void _recordFrames(List<FrameTiming> frames) {
    if (!active) return;
    for (final frame in frames) {
      final build = frame.buildDuration.inMicroseconds;
      final raster = frame.rasterDuration.inMicroseconds;
      add('frames');
      add('buildMicros', build);
      add('rasterMicros', raster);
      if (build > (_counts['buildMaxMicros'] ?? 0)) {
        _counts['buildMaxMicros'] = build;
      }
      if (raster > (_counts['rasterMaxMicros'] ?? 0)) {
        _counts['rasterMaxMicros'] = raster;
      }
      String bucket(int micros) => micros <= 4000
          ? 'Le4ms'
          : micros <= 8000
          ? 'Le8ms'
          : micros <= 16000
          ? 'Le16ms'
          : micros <= 32000
          ? 'Le32ms'
          : 'Gt32ms';
      add('build${bucket(build)}');
      add('raster${bucket(raster)}');
    }
  }

  void _finish() {
    final session = _session;
    if (session == null) return;
    _timer?.cancel();
    _timer = null;
    removeTimings(_frames);
    _counts['elapsedMicros'] = _micros - _started;
    _session = null;
    report(session, Map<String, int>.of(_counts));
    _counts.clear();
  }

  void dispose() => _finish();
}

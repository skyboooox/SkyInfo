import 'dart:ui';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/runtime_performance.dart';
import 'package:skyinfo/domain/build_channel.dart';

void main() {
  test('default channel gate and disabled commands register no work', () {
    var registrations = 0, reports = 0;
    final defaults = RuntimePerformance(report: (_, _) {});
    expect(defaults.enabled, BuildChannel.name == 'alpha');
    final off = RuntimePerformance(
      enabled: false,
      report: (_, _) => reports++,
      addTimings: (_) => registrations++,
    );
    off.control({'session': 1, 'action': 'start', 'durationMillis': 1000});
    off.add('events');
    off.dispose();
    expect(off.active, false);
    expect(registrations, 0);
    expect(reports, 0);
  });

  testWidgets(
    'timeout, reentry and explicit stop report exactly once and clean callbacks',
    (tester) async {
      var now = 1000, registrations = 0, removals = 0;
      final reports = <(int, Map<String, int>)>[];
      final perf = RuntimePerformance(
        enabled: true,
        clockMicros: () => now,
        report: (id, data) => reports.add((id, data)),
        addTimings: (_) => registrations++,
        removeTimings: (_) => removals++,
      );
      perf.control({'session': 1, 'action': 'start', 'durationMillis': 1000});
      perf.control({'session': 2, 'action': 'start', 'durationMillis': 1000});
      perf.control({'session': 2, 'action': 'stop'});
      expect(perf.active, true);
      perf.add('events', 3);
      now = 1001000;
      await tester.pump(const Duration(seconds: 1));
      perf.control({'session': 1, 'action': 'stop'});
      perf.dispose();
      expect(reports.single.$1, 1);
      expect(reports.single.$2['elapsedMicros'], 1000000);
      expect(reports.single.$2['events'], 3);
      expect(registrations, 1);
      expect(removals, 1);
      expect(perf.active, false);
    },
  );

  testWidgets(
    'frame distributions and data work use measured aggregates only',
    (tester) async {
      var now = 10;
      TimingsCallback? callback;
      Map<String, int>? summary;
      final perf = RuntimePerformance(
        enabled: true,
        clockMicros: () => now,
        report: (_, data) => summary = data,
        addTimings: (value) => callback = value,
        removeTimings: (value) {
          expect(value, same(callback));
          callback = null;
        },
      );
      perf.control({'session': 3, 'action': 'start', 'durationMillis': 180000});
      final started = perf.begin();
      now = 210;
      perf.applied(started, 12);
      callback!([
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 6000,
          rasterStart: 6000,
          rasterFinish: 26000,
          rasterFinishWallTime: 26000,
        ),
      ]);
      perf.control({'session': 3, 'action': 'stop'});
      expect(summary!['frames'], 1);
      expect(summary!['buildLe8ms'], 1);
      expect(summary!['rasterLe32ms'], 1);
      expect(summary!['buildMicros'], 6000);
      expect(summary!['rasterMicros'], 20000);
      expect(summary!['sampleEntries'], 12);
      expect(summary!['applyMicros'], 200);
      expect(callback, null);
      expect(summary!.keys, isNot(contains('overBudgetFrames')));
    },
  );

  testWidgets(
    'actual sample notification counts preserve equality and freshness',
    (tester) async {
      Map<String, int>? summary;
      final perf = RuntimePerformance(
        enabled: true,
        report: (_, data) => summary = data,
        addTimings: (_) {},
        removeTimings: (_) {},
      );
      final controller = AppController(performance: perf);
      var notified = 0;
      controller.reading('a').addListener(() => notified++);
      perf.control({'session': 1, 'action': 'start', 'durationMillis': 1000});
      final sample = {
        'value': 1,
        'raw': 1,
        'quality': 'available',
        'updatedAt': 1000,
      };
      controller.applySamples({'a': sample});
      controller.applySamples({'a': Map<String, dynamic>.of(sample)});
      controller.applySamples({
        'a': {...sample, 'updatedAt': 2000},
      });
      controller.dispose();
      expect(notified, 2);
      expect(summary!['sampleNotifications'], notified);
      expect(summary!['applyCalls'], 3);
      expect(summary!['sampleEntries'], 3);
      expect(
        controller.reading('a').value.updatedAt!.millisecondsSinceEpoch,
        2000,
      );
    },
  );

  testWidgets('invalid durations and old stop cannot affect new windows', (
    tester,
  ) async {
    var reports = 0;
    final perf = RuntimePerformance(
      enabled: true,
      report: (_, _) => reports++,
      addTimings: (_) {},
      removeTimings: (_) {},
    );
    for (final duration in [0, 180001]) {
      perf.control({
        'session': 1,
        'action': 'start',
        'durationMillis': duration,
      });
    }
    expect(perf.active, false);
    perf.control({'session': 1, 'action': 'start', 'durationMillis': 1});
    await tester.pump(const Duration(milliseconds: 1));
    perf.control({'session': 2, 'action': 'start', 'durationMillis': 1000});
    perf.control({'session': 1, 'action': 'stop'});
    expect(perf.active, true);
    perf.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(reports, 2);
  });
}

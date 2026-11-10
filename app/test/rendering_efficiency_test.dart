import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/history_chart.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/metric_tile.dart';
import 'package:skyinfo/data/app_controller.dart';

class _CountedPoints extends ListBase<HistoryPoint> {
  final List<HistoryPoint> points;
  int reads = 0;
  _CountedPoints(this.points);
  @override
  int get length => points.length;
  @override
  set length(int value) => throw UnsupportedError('snapshot');
  @override
  HistoryPoint operator [](int index) {
    reads++;
    return points[index];
  }

  @override
  void operator []=(int index, HistoryPoint value) =>
      throw UnsupportedError('snapshot');
}

void main() {
  final end = DateTime(2026, 11, 10, 12),
      start = end.subtract(const Duration(hours: 2));
  List<HistoryPoint> points(int count) => List.generate(
    count,
    (i) => HistoryPoint(
      start.add(Duration(milliseconds: i * 250)),
      math.sin(i / 30) * 100,
      segment: 'recorded',
      snapshotAt: end,
      observedUntil: i == count - 1 ? end : null,
    ),
  );

  testWidgets(
    'stable long-history snapshots reuse projection and paint delegate',
    (tester) async {
      final inputs = List.generate(4, (_) => _CountedPoints(points(28801)));
      Widget host() => MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 360,
            child: HistoryChart(
              series: [...inputs],
              minutes: 120,
              windowEnd: end,
            ),
          ),
        ),
      );
      final coldWatch = Stopwatch()..start();
      await tester.pumpWidget(host());
      coldWatch.stop();
      CustomPainter painter() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(HistoryChart),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      var previous = painter(), invalidations = 0, pictureReplacements = 0;
      ui.Picture? picture() {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find
              .ancestor(
                of: find.byType(CustomPaint),
                matching: find.byType(RepaintBoundary),
              )
              .first,
        );
        return (boundary.debugLayer!.firstChild as PictureLayer).picture;
      }

      var recorded = picture();
      final before = inputs.fold(0, (v, s) => v + s.reads);
      final rebuildWatch = Stopwatch()..start();
      for (var i = 0; i < 12; i++) {
        await tester.pumpWidget(host());
        final next = painter();
        if (next.shouldRepaint(previous)) invalidations++;
        previous = next;
        final current = picture();
        if (!identical(current, recorded)) pictureReplacements++;
        recorded = current;
      }
      rebuildWatch.stop();
      final extraReads = inputs.fold(0, (v, s) => v + s.reads) - before;
      final paintWatch = Stopwatch()..start();
      for (var i = 0; i < 12; i++) {
        final recorder = ui.PictureRecorder();
        previous.paint(Canvas(recorder), const Size(700, 360));
        recorder.endRecording().dispose();
      }
      paintWatch.stop();
      // Timings measure offline Flutter test CPU work, not device frame times.
      // ignore: avoid_print
      print(
        'RENDER_BENCH series=4 samplesPerSeries=28801 rebuilds=12 '
        'initialPointReads=$before repeatPointReads=$extraReads '
        'paintInvalidations=$invalidations pictureReplacements=$pictureReplacements coldBuildUs=${coldWatch.elapsedMicroseconds} rebuildUs=${rebuildWatch.elapsedMicroseconds} '
        'forcedPaintUs=${paintWatch.elapsedMicroseconds}',
      );
      expect(extraReads, 0);
      expect(invalidations, 0);
      expect(pictureReplacements, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'long history aggregation and vertices preserve every recorded sample',
    () {
      final input = points(28801);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 12; i++) {
        final groups = aggregateHistory(input, 233, start, end);
        final vertices = historyLineVertices(groups.single);
        expect(vertices.length, input.length);
        expect(vertices[1000], (input[1000].at, input[1000].value));
      }
      watch.stop();
      // ignore: avoid_print
      print(
        'HISTORY_BENCH samples=28801 iterations=12 aggregateAndVerticesUs=${watch.elapsedMicroseconds}',
      );
    },
  );
  testWidgets('chart cache follows snapshots, window, width, axis and theme', (
    tester,
  ) async {
    var input = _CountedPoints(points(28801));
    var minutes = 120, width = 700.0, height = 360.0;
    DateTime? windowEnd;
    double? minimum, maximum;
    var brightness = Brightness.light;
    Widget host() => MaterialApp(
      theme: industrialTheme(brightness),
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: HistoryChart(
            series: [input],
            minutes: minutes,
            windowEnd: windowEnd,
            minimum: minimum,
            maximum: maximum,
          ),
        ),
      ),
    );
    CustomPainter painter() => tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(HistoryChart),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await tester.pumpWidget(host());
    var before = input.reads;
    var old = painter();
    await tester.pumpWidget(host());
    expect(input.reads, before);
    expect(painter().shouldRepaint(old), isFalse);
    // Selection changes its overlay while retaining the chart drawing layer.
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(find.textContaining('最低'), findsOneWidget);
    expect(input.reads, before);
    expect(painter().shouldRepaint(old), isFalse);
    brightness = Brightness.dark;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(input.reads, before);
    expect(painter().shouldRepaint(old), isTrue);
    old = painter();
    minimum = -200;
    maximum = 200;
    await tester.pumpWidget(host());
    expect(input.reads, before);
    expect(painter().shouldRepaint(old), isTrue);
    old = painter();
    height = 420;
    await tester.pumpWidget(host());
    expect(input.reads, before);
    // RenderCustomPaint repaints on size changes, independently of the delegate.
    expect(painter().shouldRepaint(old), isFalse);
    width = 600;
    await tester.pumpWidget(host());
    expect(input.reads, greaterThan(before));
    before = input.reads;
    old = painter();
    minutes = 30;
    await tester.pumpWidget(host());
    expect(input.reads, greaterThan(before));
    expect(painter().shouldRepaint(old), isTrue);
    before = input.reads;
    old = painter();
    windowEnd = end.add(const Duration(minutes: 1));
    await tester.pumpWidget(host());
    expect(input.reads, greaterThan(before));
    expect(painter().shouldRepaint(old), isTrue);
    old = painter();
    input = _CountedPoints(points(28802));
    await tester.pumpWidget(host());
    expect(input.reads, greaterThan(0));
    expect(painter().shouldRepaint(old), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'timeline reuses ordered snapshots and invalidates for the window',
    (tester) async {
      final input = _CountedPoints([
        HistoryPoint(
          end.subtract(const Duration(minutes: 10)),
          null,
          state: 'on',
          snapshotAt: end,
        ),
        HistoryPoint(
          end.subtract(const Duration(minutes: 5)),
          null,
          state: 'off',
          snapshotAt: end,
        ),
      ]);
      Widget host(int minutes) => MaterialApp(
        home: Scaffold(
          body: StateTimeline(points: input, minutes: minutes),
        ),
      );
      CustomPainter painter() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(StateTimeline),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      await tester.pumpWidget(host(30));
      final reads = input.reads, old = painter();
      await tester.pumpWidget(host(30));
      expect(input.reads, reads);
      expect(painter().shouldRepaint(old), isFalse);
      await tester.pumpWidget(host(5));
      expect(input.reads, reads);
      expect(painter().shouldRepaint(old), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('large metric lists construct visible rows on demand', (
    tester,
  ) async {
    final controller = _MetricController();
    final fields = List.generate(200, (i) => 'field-$i');
    final tile = TileSpec(
      id: 'list',
      title: 'Metrics',
      kind: WidgetKind.list,
      fields: fields,
      columns: 2,
      rows: 2,
    );
    Widget host() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: MetricTile(
            tile: tile,
            controller: controller,
            now: end,
            onEdit: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(host());
    final initial = controller.lookups;
    expect(initial, inInclusiveRange(1, 20));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(controller.lookups, greaterThan(initial));
    expect(controller.lookups, lessThan(40));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('history refresh pauses in background and releases on disposal', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controller = _MetricController();
    final tile = TileSpec(
      id: 'history',
      title: 'History',
      kind: WidgetKind.trend,
      fields: ['field-0'],
      columns: 2,
      rows: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MetricTile(
              tile: tile,
              controller: controller,
              now: end,
              onEdit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller.historyQueries, 1);
    controller.reading('field-0').value = const Sample(
      value: 1,
      quality: 'available',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(controller.historyQueries, 1);
    controller.reading('field-0').value = const Sample(
      value: 2,
      quality: 'available',
    );
    await tester.pump(const Duration(seconds: 10));
    expect(controller.historyQueries, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(controller.historyQueries, 2);
    controller.reading('field-0').value = const Sample(
      value: 3,
      quality: 'available',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(controller.historyQueries, 2);
    controller.dispose();
  });
}

class _MetricController extends AppController {
  int lookups = 0, historyQueries = 0;
  @override
  Metric metric(String id) {
    lookups++;
    return Metric(
      id: id,
      name: id,
      category: '',
      icon: '',
      unit: '',
      encoding: 'number',
      entityKey: '',
      displayAllowed: true,
    );
  }

  @override
  Future<List<HistoryPoint>> history(
    String field,
    int minutes, {
    bool refresh = false,
  }) async {
    historyQueries++;
    return const [];
  }
}

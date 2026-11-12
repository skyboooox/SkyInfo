import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/history_chart.dart';
import 'package:skyinfo/ui/industrial.dart';

void main() {
  final end = DateTime(2026, 10, 9, 19, 17);
  final start = end.subtract(const Duration(minutes: 30));
  DateTime at(int seconds) => start.add(Duration(seconds: seconds));
  final high = [
    HistoryPoint(at(840), 46, segment: 'high', snapshotAt: end),
    HistoryPoint(at(842), 45, segment: 'high', snapshotAt: end),
    HistoryPoint(at(1140), 44, segment: 'high', snapshotAt: end),
    HistoryPoint(
      at(1620),
      43,
      segment: 'high',
      snapshotAt: end,
      observedUntil: end,
    ),
  ];
  final low = [
    HistoryPoint(at(1140), 39, segment: 'low', snapshotAt: end),
    HistoryPoint(at(1142), 38, segment: 'low', snapshotAt: end),
    HistoryPoint(
      at(1680),
      38,
      segment: 'low',
      snapshotAt: end,
      observedUntil: end,
    ),
  ];
  test('密集样本使用均值，稀疏更新保持最近真实值', () {
    final groups = aggregateHistory(high, 100, start, end);
    expect(groups.length, 1);
    expect(historyLineVertices(groups.single), [
      (at(841), 45.5),
      (at(842), 45.0),
      (at(1140), 45.0),
      (at(1140), 44.0),
      (at(1620), 44.0),
      (at(1620), 43.0),
      (end, 43.0),
    ]);
    final range = groups.single.first;
    expect((range.min, range.max, range.sampleCount), (45, 46, 2));
    expect(range.maximumAt, at(840));
    expect(range.minimumAt, at(842));
    expect(historyEnvelopeRuns(groups.single).map((r) => r.length), [1, 1, 1]);
  });
  test('unordered history keeps chronological vertices and bucket extrema', () {
    for (final bins in [1, 100, 600]) {
      final ordered = aggregateHistory(high, bins, start, end).single;
      final reversed = aggregateHistory(
        high.reversed.toList(),
        bins,
        start,
        end,
      ).single;
      expect(historyLineVertices(reversed), historyLineVertices(ordered));
      expect(
        reversed.map((b) => (b.min, b.max, b.minimumAt, b.maximumAt)),
        ordered.map((b) => (b.min, b.max, b.minimumAt, b.maximumAt)),
      );
    }
  });
  for (final hz in [1, 4]) {
    test('30分钟每秒$hz个样本投影随绘图区宽度有界', () {
      final points = List.generate(
        1800 * hz + 1,
        (i) => HistoryPoint(
          start.add(Duration(milliseconds: i * 1000 ~/ hz)),
          100 + i / hz / 100,
          segment: 'dense',
        ),
      );
      final original = List.of(points);
      for (final bins in [100, 200, 600]) {
        final groups = aggregateHistory(points, bins, start, end);
        final vertices = historyLineVertices(groups.single);
        expect(vertices.length, lessThanOrEqualTo(bins));
        expect(
          groups.single.fold(0, (n, b) => n + b.sampleCount),
          points.length,
        );
        expect(historyEnvelopeRuns(groups.single).length, 1);
      }
      expect(points, original);
    });
  }
  test('同桶正负尖峰由真实均值和极值发生时间表达', () {
    final points = [
      HistoryPoint(at(10), 10, segment: 'a'),
      HistoryPoint(at(11), 50, segment: 'a'),
      HistoryPoint(at(12), -20, segment: 'a'),
      HistoryPoint(at(13), 12, segment: 'a'),
    ];
    final segment = aggregateHistory(points, 10, start, end).single;
    final bucket = segment.single;
    expect(historyEnvelopeRuns(segment).single.single.sampleCount, 4);
    expect(
      (bucket.min, bucket.max, bucket.representative, bucket.sampleCount),
      (-20, 50, 13, 4),
    );
    expect(bucket.at, at(10).add(const Duration(milliseconds: 1500)));
    expect(bucket.minimumAt, at(12));
    expect(bucket.maximumAt, at(11));
    expect(historyLineVertices([bucket]), [(bucket.at, 13.0)]);
  });
  test('24小时宽桶仍按原始样本间隔连续', () {
    final from = end.subtract(const Duration(hours: 24));
    final input = List.generate(
      86401,
      (i) => HistoryPoint(
        from.add(Duration(seconds: i)),
        math.sin(i / 50),
        segment: 'dense',
      ),
    );
    final buckets = aggregateHistory(input, 200, from, end).single;
    expect(historyLineVertices(buckets).length, 200);
    expect(historyEnvelopeRuns(buckets).single.length, 200);
    expect(
      buckets
          .skip(1)
          .every((b) => b.continuousFromPrevious && !b.holdFromPrevious),
      isTrue,
    );
  });
  test('空桶与失效、来源及单位分段不连接极值包络', () {
    final input = [
      HistoryPoint(at(0), 1, segment: 'source/unit-a'),
      HistoryPoint(at(1), 3, segment: 'source/unit-a'),
      HistoryPoint(at(5), 2, segment: 'source/unit-a'),
      HistoryPoint(at(6), 4, segment: 'source/unit-a'),
      HistoryPoint(at(7), double.nan, segment: 'source/unit-a'),
      HistoryPoint(at(8), 5, segment: 'source/unit-a'),
      HistoryPoint(at(9), 6, segment: 'source/unit-b'),
    ];
    final groups = aggregateHistory(input, 900, start, end);
    expect(groups.length, 3);
    expect(historyEnvelopeRuns(groups.first).map((r) => r.length), [1, 2]);
    expect(groups.first[1].holdFromPrevious, isFalse);
    expect(historyLineVertices(groups.first).length, 4);
  });
  test('同个宽桶内稀疏更新使用真实值保持，选点区分均值与保持', () {
    final groups = aggregateHistory(
      [
        HistoryPoint(at(10), 10),
        HistoryPoint(at(11), 20),
        HistoryPoint(at(100), 40, observedUntil: at(200)),
      ],
      1,
      start,
      end,
    );
    expect(groups.single.length, 2);
    expect(groups.single.first.rangeEnd, at(11));
    expect(groups.single.last.rangeEnd, at(100));
    expect(historySelectionAt(groups, at(10))!.held, isFalse);
    expect(historySelectionAt(groups, at(50))!.held, isTrue);
    expect(historySelectionAt(groups, at(150))!.held, isTrue);
    expect(historyLineVertices(groups.single), [
      (at(10).add(const Duration(milliseconds: 500)), 15.0),
      (at(11), 20.0),
      (at(100), 20.0),
      (at(100), 40.0),
      (at(200), 40.0),
    ]);
  });
  test('窗口前稳定值形成平台，但原样本时间保持不变', () {
    final original = start.subtract(const Duration(hours: 2));
    final groups = aggregateHistory(
      [HistoryPoint(original, 43, segment: 'a', observedUntil: end)],
      100,
      start,
      end,
    );
    expect(historyLineVertices(groups.single), [(start, 43.0), (end, 43.0)]);
    expect(groups.single.single.representativeAt, original);
    expect(groups.single.single.minimumAt, isNull);
    expect(groups.single.single.sampleCount, 0);
    expect(historySelectionAt(groups, at(200))!.held, isTrue);
    expect(
      aggregateHistory(
        [HistoryPoint(original, 43, segment: 'old-session')],
        100,
        start,
        end,
      ),
      isEmpty,
    );
  });
  test('前驱只保持边界，不进入窗口内均值和极值', () {
    final original = start.subtract(const Duration(seconds: 1));
    final groups = aggregateHistory(
      [
        HistoryPoint(original, 10000, segment: 'a'),
        HistoryPoint(at(1), 10, segment: 'a'),
        HistoryPoint(at(2), 20, segment: 'a'),
      ],
      1,
      start,
      end,
    );
    final real = groups.single.where((b) => b.sampleCount > 0).single;
    expect(
      (real.representative, real.min, real.max, real.sampleCount),
      (15, 10, 20, 2),
    );
    expect(real.minimumAt, at(1));
    expect(real.maximumAt, at(2));
    expect(historySelectionAt(groups, start)!.held, isTrue);
    expect(
      historySelectionAt(groups, start)!.bucket.representativeAt,
      original,
    );
  });
  test('窗口内变化接续窗口前的状态；失效和来源变化仍分段', () {
    final before = start.subtract(const Duration(minutes: 1));
    final groups = aggregateHistory(
      [
        HistoryPoint(before, 44, segment: 'a'),
        HistoryPoint(at(300), 43, segment: 'a'),
        HistoryPoint(at(600), null, segment: 'failed'),
        HistoryPoint(at(900), 42, segment: 'a'),
        HistoryPoint(at(1000), 41, segment: 'b', observedUntil: end),
      ],
      100,
      start,
      end,
    );
    expect(groups.length, 3);
    expect(historyLineVertices(groups.first), [
      (start, 44.0),
      (at(300), 44.0),
      (at(300), 43.0),
      (at(600), 43.0),
    ]);
    expect(historyLineVertices(groups[1]), [(at(900), 42.0)]);
    expect(historyLineVertices(groups.last), [(at(1000), 41.0), (end, 41.0)]);
  });
  test('失效时刻排除旧保持值，来源同刻切换采用新段', () {
    final failed = aggregateHistory(
      [
        HistoryPoint(at(10), 11, segment: 'a', observedUntil: end),
        HistoryPoint(at(100), null, segment: 'a'),
        HistoryPoint(at(200), 22, segment: 'a'),
      ],
      100,
      start,
      end,
    );
    expect(historySelectionAt(failed, at(99))!.held, isTrue);
    expect(historySelectionAt(failed, at(100)), isNull);
    expect(historySelectionAt(failed, at(150)), isNull);
    expect(historyLineVertices(failed.first).last, (at(100), 11.0));
    expect(
      aggregateHistory(
        [
          HistoryPoint(
            start.subtract(const Duration(seconds: 1)),
            11,
            segment: 'a',
            observedUntil: end,
          ),
          HistoryPoint(start, null, segment: 'a'),
        ],
        100,
        start,
        end,
      ),
      isEmpty,
    );
    final switched = aggregateHistory(
      [
        HistoryPoint(at(100), 11, segment: 'source/unit-a'),
        HistoryPoint(at(100), 22, segment: 'source/unit-b', observedUntil: end),
      ],
      100,
      start,
      end,
    );
    expect(switched.length, 2);
    expect(historySelectionAt(switched, at(100))!.bucket.representative, 22);
    final recovered = aggregateHistory(
      [
        HistoryPoint(at(10), 11, segment: 'a'),
        HistoryPoint(at(100), null, segment: 'a'),
        HistoryPoint(at(100), 22, segment: 'a', observedUntil: end),
      ],
      100,
      start,
      end,
    );
    expect(historySelectionAt(recovered, at(100))!.bucket.representative, 22);
  });
  test('缓存图表沿用查询快照时间，不随页面重绘漂移', () {
    expect(
      historySnapshotEnd([high, low], end.add(const Duration(minutes: 2))),
      end,
    );
  });
  test('充电回放各时间桶保留真实峰谷，只有已记录区间有包络', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/charging-voltage-20261009.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final points = (fixture['points'] as List)
        .map(
          (p) => HistoryPoint(
            DateTime.parse(p['at']),
            (p['value'] as num).toDouble(),
            segment: p['segment'],
          ),
        )
        .toList();
    final from = points.first.at.subtract(const Duration(minutes: 5)),
        to = points.last.at.add(const Duration(seconds: 1));
    for (final b in aggregateHistory(points, 180, from, to).single) {
      expect(
        b.rangeEnd!.difference(b.rangeStart!).inMilliseconds,
        lessThanOrEqualTo((to.difference(from).inMilliseconds / 180).ceil()),
      );
      expect(
        points.any((p) => p.at == b.minimumAt && p.value == b.min),
        isTrue,
      );
      expect(
        points.any((p) => p.at == b.maximumAt && p.value == b.max),
        isTrue,
      );
    }
  });
  testWidgets('窄卡片双序列选点保持可滚动且不溢出', (tester) async {
    final input = List.generate(1801, (i) => HistoryPoint(at(i), i.toDouble()));
    await tester.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              height: 130,
              child: HistoryChart(
                series: [input, input],
                minutes: 30,
                windowEnd: end,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 40));
    await tester.pump();
    expect(find.textContaining('均值'), findsNWidgets(2));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -100),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('同时间多样本的极值竖线保留', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 500,
              height: 240,
              child: HistoryChart(
                series: [
                  [HistoryPoint(at(900), -20), HistoryPoint(at(900), 50)],
                ],
                minutes: 30,
                windowEnd: end,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/light-history-same-time.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('均值趋势与尖峰包络的浅深主题', (tester) async {
    for (final font in ['ChillDIN', 'IBMPlexMono']) {
      final loader = FontLoader(font)
        ..addFont(
          rootBundle.load(
            font == 'ChillDIN'
                ? 'assets/fonts/ChillDINGothic_Std.otf'
                : 'assets/fonts/IBMPlexMono-Medium.ttf',
          ),
        );
      await tester.runAsync(loader.load);
    }
    tester.view.physicalSize = const Size(700, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final input = List.generate(7201, (i) {
      final value =
          13 +
          3 * math.sin(i / 580) +
          0.7 * math.sin(i / 9) +
          (i % 601 == 0 ? 7 : 0) -
          (i % 811 == 0 ? 6 : 0);
      return HistoryPoint(
        start.add(Duration(milliseconds: i * 250)),
        value,
        segment: 'anonymous',
        snapshotAt: end,
      );
    });
    for (final theme in [Brightness.light, Brightness.dark]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: industrialTheme(theme),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: theme == Brightness.dark
                    ? Palette.dark.paper
                    : Palette.light.paper,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: HistoryChart(
                    series: [input],
                    minutes: 30,
                    windowEnd: end,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        historySeriesColors(
          theme == Brightness.dark ? Palette.dark : Palette.light,
        ).toSet().length,
        4,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/${theme.name}-history-trend.png'),
      );
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('.dart_tool/test-reports/history');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/trend-${theme.name}-2x.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tapAt(const Offset(350, 150));
      await tester.pump();
      expect(find.textContaining('均值'), findsOneWidget);
      expect(find.textContaining('个样本'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('温度双曲线的浅深色绘制与缺口提示', (tester) async {
    for (final font in ['ChillDIN', 'IBMPlexMono']) {
      final loader = FontLoader(font)
        ..addFont(
          rootBundle.load(
            font == 'ChillDIN'
                ? 'assets/fonts/ChillDINGothic_Std.otf'
                : 'assets/fonts/IBMPlexMono-Medium.ttf',
          ),
        );
      await tester.runAsync(loader.load);
    }
    tester.view.physicalSize = const Size(700, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in [Brightness.light, Brightness.dark]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: industrialTheme(theme),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: theme == Brightness.dark
                    ? Palette.dark.paper
                    : Palette.light.paper,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: HistoryChart(
                    series: [high, low],
                    minutes: 30,
                    windowEnd: end,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/${theme.name}-history-sparse.png'),
      );
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('.dart_tool/test-reports/history');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/temperature-${theme.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.dark),
        home: Scaffold(
          body: HistoryChart(
            series: [
              [
                HistoryPoint(at(100), 44, segment: 'a'),
                HistoryPoint(at(200), null),
                HistoryPoint(at(1000), 43, segment: 'b'),
              ],
            ],
            minutes: 30,
            windowEnd: end,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(350, 150));
    await tester.pump();
    expect(find.textContaining('最低'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

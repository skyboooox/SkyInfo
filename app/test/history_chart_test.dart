import 'dart:convert';
import 'dart:io';
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
  test('复现截图：密集点连线、稀疏区间保持，不跨桶插值极值', () {
    final groups = aggregateHistory(high, 100, start, end);
    expect(groups.length, 1);
    final vertices = historyLineVertices(groups.single);
    expect(
      vertices,
      containsAllInOrder([
        (at(840), 46.0),
        (at(842), 45.0),
        (at(1140), 45.0),
        (at(1140), 44.0),
        (at(1620), 44.0),
        (at(1620), 43.0),
        (end, 43.0),
      ]),
    );
    final range = groups.single.first;
    expect(range.min, 45);
    expect(range.max, 46);
    expect(
      range.rangeEnd!.difference(range.rangeStart!).inSeconds,
      lessThanOrEqualTo(18),
    );
    expect(range.maximumAt, at(840));
    expect(range.minimumAt, at(842));
    expect(groups.single.skip(1).every((b) => b.min == b.max), isTrue);
  });
  for (final hz in [1, 4]) {
    test('30分钟每秒$hz个样本全部保留，不被像素桶降成十秒阶梯', () {
      final points = List.generate(
        1800 * hz + 1,
        (i) => HistoryPoint(
          start.add(Duration(milliseconds: i * 1000 ~/ hz)),
          100 + i / hz / 100,
          segment: 'dense',
        ),
      );
      for (final bins in [100, 200, 600]) {
        final groups = aggregateHistory(points, bins, start, end);
        final vertices = historyLineVertices(groups.single);
        expect(vertices.length, points.length);
        for (var i = 0; i < points.length; i++) {
          expect(vertices[i], (points[i].at, points[i].value));
        }
      }
    });
  }
  test('相同像素桶里的瞬间峰谷也出现在主线中', () {
    final points = [
      HistoryPoint(at(10), 10, segment: 'a'),
      HistoryPoint(at(11), 50, segment: 'a'),
      HistoryPoint(at(12), -20, segment: 'a'),
      HistoryPoint(at(13), 11, segment: 'a'),
    ];
    final buckets = aggregateHistory(points, 10, start, end).single;
    expect(buckets.length, 1);
    expect(buckets.single.min, -20);
    expect(buckets.single.max, 50);
    expect(
      historyLineVertices(buckets),
      points.map((p) => (p.at, p.value)).toList(),
    );
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
    expect(groups.single.single.minimumAt, original);
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

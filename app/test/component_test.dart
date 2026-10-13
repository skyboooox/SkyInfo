import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/metric_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/runtime'),
          (call) async => call.method == 'history'
              ? {
                  'points': [
                    {
                      'at': DateTime.now()
                          .subtract(const Duration(seconds: 10))
                          .toIso8601String(),
                      'value': 13.6,
                      'state': '13.6',
                      'segment': 'a',
                    },
                    {
                      'at': DateTime.now().toIso8601String(),
                      'value': 14.0,
                      'state': '14.0',
                      'segment': 'a',
                    },
                  ],
                }
              : {'config': {}, 'samples': {}, 'status': {}},
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/events'),
          (_) async => null,
        );
  });
  testWidgets('历史查询保留真实时间，变化合并刷新且相同读数不重复查询', (tester) async {
    final calls = <String>[];
    final snapshot = DateTime(2026, 10, 9, 19, 17);
    final original = snapshot.subtract(const Duration(hours: 2));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/runtime'),
          (call) async {
            calls.add(call.method);
            return call.method == 'history'
                ? {
                    'queriedAt': snapshot.millisecondsSinceEpoch,
                    'points': [
                      {
                        'at': original.toIso8601String(),
                        'value': 43.0,
                        'segment': 'a',
                        'observedUntil': snapshot.millisecondsSinceEpoch,
                      },
                    ],
                  }
                : {'config': {}, 'samples': {}, 'status': {}};
          },
        );
    final controller = AppController();
    await tester.runAsync(controller.initialize);
    const id = '1014/5/1148190752';
    final history = (await tester.runAsync(() => controller.history(id, 30)))!;
    expect(history.single.at, original);
    expect(history.single.snapshotAt, snapshot);
    expect(history.single.observedUntil, snapshot);
    calls.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 500,
            child: MetricTile(
              tile: TileSpec(
                id: 'trend',
                title: '温度',
                kind: WidgetKind.trend,
                fields: [id],
                columns: 2,
                rows: 2,
              ),
              controller: controller,
              now: snapshot,
              onEdit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: '初始查询复用缓存');
    controller.applySamples({
      id: {'value': 43, 'quality': 'available'},
    });
    controller.applySamples({
      id: {'value': 44, 'quality': 'available'},
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(calls, ['history'], reason: '多次变化只刷新一次本机历史');
    calls.clear();
    controller.applySamples({
      id: {
        'value': 44,
        'quality': 'available',
        'updatedAt': snapshot.millisecondsSinceEpoch,
      },
    });
    await tester.pump(const Duration(seconds: 6));
    expect(calls, isEmpty, reason: '仅更新时间改变不查询');
    controller.applySamples({
      id: {'value': 45, 'quality': 'available'},
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    expect(calls, isEmpty, reason: '离页取消延迟查询');
    controller.dispose();
  });
  testWidgets('组件只显示相对时间，普通读数无质量说明，可用性组件保留状态', (tester) async {
    final controller = AppController();
    await tester.runAsync(controller.initialize);
    final now = DateTime(2026, 10, 9, 22);
    const id = '1032/7/1128267816';
    controller.applySamples({
      id: {
        'value': 13.7,
        'quality': 'unverified',
        'updatedAt': now
            .subtract(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
        'changedAt': now
            .subtract(const Duration(minutes: 3))
            .millisecondsSinceEpoch,
      },
    });
    for (final kind in [
      WidgetKind.number,
      WidgetKind.list,
      WidgetKind.availability,
    ]) {
      for (final time in [TimeDisplay.updated, TimeDisplay.changed]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: industrialTheme(Brightness.light),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: MetricTile(
                  key: ValueKey('$kind-$time'),
                  controller: controller,
                  now: now,
                  onEdit: () {},
                  preview: true,
                  tile: TileSpec(
                    id: 'time',
                    title: '电压',
                    kind: kind,
                    fields: [id],
                    time: time,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(time == TimeDisplay.updated ? '2分钟前' : '3分钟前'),
          findsOneWidget,
        );
        expect(find.textContaining('变动'), findsNothing);
        expect(find.textContaining('更新'), findsNothing);
        expect(
          find.text('未验证'),
          kind == WidgetKind.availability ? findsOneWidget : findsNothing,
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('全部样式与固定跨度支持时间、图标和未知状态', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController();
    await tester.runAsync(controller.initialize);
    for (final kind in WidgetKind.values) {
      for (final size in kind.sizes) {
        for (final valid in [true, false]) {
          final ids = kind.multiple
              ? ['1014/5/1148190752', '1014/5/1148190736']
              : ['1032/7/1128267816'];
          controller.applySamples({
            for (final id in ids)
              id: {
                'value': valid ? 13.6 : null,
                'quality': valid ? 'available' : 'invalid',
                'updatedAt': DateTime.now().millisecondsSinceEpoch,
              },
          });
          final tile = TileSpec(
            id: '${kind.name}-${size.$1}-${size.$2}-$valid',
            title: '组件',
            kind: kind,
            fields: ids,
            columns: size.$1,
            rows: size.$2,
            time: TimeDisplay.updated,
            icon: 'battery',
            icons: {for (final id in ids) id: 'battery'},
            minimum: 10,
            maximum: 16,
            glanceColumns: 3,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: industrialTheme(Brightness.light),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 182 * size.$1 + 16 * (size.$1 - 1),
                    height: 182 * size.$2 + 16 * (size.$2 - 1),
                    child: MetricTile(
                      key: ValueKey(tile.id),
                      tile: tile,
                      controller: controller,
                      now: DateTime.now(),
                      onEdit: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${kind.name} $size valid=$valid',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

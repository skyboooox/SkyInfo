import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/dashboard_layout.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/network_adb_settings.dart';

class StartupBridge extends VehicleBridge {
  final updates = StreamController<Map<String, dynamic>>();
  final calls = <String>[];
  String state;
  StartupBridge(this.state);
  @override
  Stream<Map<String, dynamic>> get events => updates.stream;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    return {
      'config': {},
      'status': {'adb': state},
      'samples': {},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<AppController> show(
    WidgetTester t,
    StartupBridge b, {
    String theme = 'dark',
  }) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final font in ['ChillDIN', 'IBMPlexMono', 'MaterialIcons']) {
      final loader = FontLoader(font)
        ..addFont(
          rootBundle.load(
            font == 'ChillDIN'
                ? 'assets/fonts/ChillDINGothic_Std.otf'
                : font == 'MaterialIcons'
                ? 'fonts/MaterialIcons-Regular.otf'
                : 'assets/fonts/IBMPlexMono-Medium.ttf',
          ),
        );
      await t.runAsync(loader.load);
    }
    final c = (await t.runAsync(() async {
      final c = AppController(bridge: b);
      await c.initialize();
      c.reduceMotion = true;
      c.theme = theme;
      return c;
    }))!;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await b.updates.close();
    });
    await t.pumpWidget(SkyInfo(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  test(
    'fresh and missing preferences default to standard, saved enlarged remains',
    () {
      final c = AppController();
      expect(c.dashboardSize, DashboardSize.standard);
      expect(c.collect, isTrue);
      c.restore({'dashboardSize': 'enlarged', 'collect': false});
      expect(c.dashboardSize, DashboardSize.enlarged);
      expect(c.collect, isFalse);
      c.restore({'theme': 'dark'});
      expect(c.dashboardSize, DashboardSize.standard);
      expect(c.collect, isTrue);
      c.dispose();
    },
  );

  testWidgets(
    'waits for authorization result; later dismisses once without writes or repeated prompts',
    (t) async {
      final b = StartupBridge('connecting');
      await show(t, b);
      expect(find.text('需要网络ADB授权'), findsNothing);
      b.updates.add({
        'status': {'adb': 'authorization'},
      });
      await t.pumpAndSettle();
      expect(find.text('需要网络ADB授权'), findsOneWidget);
      await t.tap(find.text('稍后'));
      await t.pumpAndSettle();
      b.updates.add({
        'status': {'adb': 'authorization'},
      });
      await t.pumpAndSettle();
      expect(find.text('需要网络ADB授权'), findsNothing);
      expect(b.calls, ['load']);
    },
  );

  testWidgets('successful launch stays quiet even after a later disconnect', (
    t,
  ) async {
    final b = StartupBridge('connected');
    await show(t, b);
    b.updates.add({
      'status': {'adb': 'disconnected'},
    });
    await t.pumpAndSettle();
    expect(find.text('需要网络ADB授权'), findsNothing);
    expect(find.text('无法连接网络ADB'), findsNothing);
    expect(b.calls, ['load']);
  });

  testWidgets(
    'confirmation opens configured connection settings, without claiming authorization',
    (t) async {
      final b = StartupBridge('authorization');
      await show(t, b);
      await t.tap(find.text('授权连接'));
      await t.pumpAndSettle();
      expect(find.byType(NetworkAdbSettings), findsOneWidget);
      expect(b.calls, ['load']);
      expect(find.text('请在系统中接受SkyInfo的ADB授权'), findsOneWidget);
    },
  );

  testWidgets(
    'unreachable connection is not mislabeled as missing permission',
    (t) async {
      await show(t, StartupBridge('unreachable'));
      expect(find.text('无法连接网络ADB'), findsOneWidget);
      expect(find.text('需要网络ADB授权'), findsNothing);
      expect(find.text('连接设置'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  for (final theme in ['light', 'dark']) {
    testWidgets('$theme startup authorization golden', (t) async {
      await show(t, StartupBridge('authorization'), theme: theme);
      await expectLater(
        find.byType(SkyInfo),
        matchesGoldenFile('goldens/$theme-startup-authorization.png'),
      );
      expect(t.takeException(), isNull);
    });
  }
}

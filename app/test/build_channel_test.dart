import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/build_channel.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/release_notice.dart';

class ChannelBridge extends VehicleBridge {
  final calls = <String>[];
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    return method == 'load'
        ? {
            'config': {'channel': BuildChannel.isBeta ? 'stable' : 'beta'},
            'status': {'adb': 'connected'},
          }
        : {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  setUpAll(() async {
    for (final entry in {
      'ChillDIN': 'assets/fonts/ChillDINGothic_Std.otf',
      'IBMPlexMono': 'assets/fonts/IBMPlexMono-Medium.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value));
      await loader.load();
    }
  });
  final launches = <MethodCall>[];
  var launchSucceeds = true;
  setUp(() {
    launchSucceeds = true;
    launches.clear();
    PackageInfo.setMockInitialValues(
      appName: 'SkyInfo',
      packageName: 'app.skyinfo.vehicle',
      version: BuildChannel.isBeta ? '9.8.7-beta' : '9.8.7',
      buildNumber: '123',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            launches.add(call);
            return launchSucceeds;
          },
        );
  });

  Future<(AppController, ChannelBridge)> show(
    WidgetTester t, {
    String theme = 'light',
  }) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final bridge = ChannelBridge();
    final controller = (await t.runAsync(() async {
      final c = AppController(bridge: bridge);
      await c.initialize();
      return c;
    }))!;
    controller.theme = theme;
    controller.reduceMotion = true;
    addTearDown(controller.dispose);
    await t.pumpWidget(SkyInfo(controller: controller));
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('设置').last);
    await t.pumpAndSettle();
    return (controller, bridge);
  }

  testWidgets(
    'channel controls persistent notice and audit only, not user recovery tools',
    (t) async {
      final (c, bridge) = await show(t);
      for (final tab in ['常规', '采集', '悬浮窗', '连接', '高级']) {
        await t.tap(find.widgetWithText(SelectionRow, tab));
        await t.pumpAndSettle();
        expect(
          find.byType(ReleaseNotice),
          BuildChannel.isBeta ? findsOneWidget : findsNothing,
        );
        expect(t.takeException(), isNull);
      }
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.text('实体映射'),
      );
      await t.scrollUntilVisible(
        list,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await t.ensureVisible(list);
      await t.pumpAndSettle();
      expect(find.text('诊断信息'), findsOneWidget);
      expect(find.text('实体映射'), findsOneWidget);
      if (BuildChannel.isBeta) {
        await t.scrollUntilVisible(
          find.text('车辆适配检查'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await t.tap(find.text('车辆适配检查'));
        await t.pumpAndSettle();
        expect(bridge.calls, contains('auditFields'));
      } else {
        expect(find.text('测试工具'), findsNothing);
        expect(find.text('车辆适配检查'), findsNothing);
        expect(bridge.calls, isNot(contains('auditFields')));
      }
      c.restore({'channel': BuildChannel.isBeta ? 'stable' : 'beta'});
      await t.pump();
      expect(
        find.byType(ReleaseNotice),
        BuildChannel.isBeta ? findsOneWidget : findsNothing,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'about shows installed version and opens project externally; failure keeps settings',
    (t) async {
      final (c, bridge) = await show(t);
      expect(c.appVersion, BuildChannel.isBeta ? '9.8.7-beta' : '9.8.7');
      expect(c.config.containsKey('channel'), isFalse);
      final link = find.text(BuildChannel.projectUrl);
      await t.scrollUntilVisible(
        link,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await t.ensureVisible(link);
      await t.pumpAndSettle();
      expect(find.text(c.versionLabel), findsOneWidget);
      await t.tap(link);
      await t.pumpAndSettle();
      expect(launches.single.arguments['url'], BuildChannel.projectUrl);
      expect(launches.single.arguments['useWebView'], isFalse);
      expect(bridge.calls.where((method) => method != 'visibility'), ['load']);
      launchSucceeds = false;
      await t.tap(link);
      await t.pumpAndSettle();
      expect(find.text('无法打开链接，请检查是否已安装浏览器'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  if (BuildChannel.isBeta) {
    testWidgets('notice action opens project without runtime writes', (
      t,
    ) async {
      final (_, bridge) = await show(t);
      await t.tap(find.text('版本与更新'));
      await t.pumpAndSettle();
      expect(launches.single.arguments['url'], BuildChannel.projectUrl);
      expect(bridge.calls.where((method) => method != 'visibility'), ['load']);
      await t.pumpWidget(const SizedBox());
    });
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('${BuildChannel.name} $theme settings golden', (t) async {
      await show(t, theme: theme);
      await expectLater(
        find.byType(SkyInfo),
        matchesGoldenFile('goldens/${BuildChannel.name}-$theme-settings.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$theme narrow notice supports large text without clipping actions',
      (t) async {
        t.view.physicalSize = const Size(390, 900);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(
          MaterialApp(
            theme: industrialTheme(
              theme == 'light' ? Brightness.light : Brightness.dark,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ReleaseNotice(version: '9.8.7-beta', onOpen: () {}),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('正在使用测试版'), findsOneWidget);
        expect(
          t.getSize(find.widgetWithText(IndustrialButton, '版本与更新')).height,
          greaterThanOrEqualTo(48),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}

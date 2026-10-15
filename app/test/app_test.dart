import 'package:skyinfo/ui/industrial.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/domain/dashboard_layout.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';

class PositionBridge extends VehicleBridge {
  final updates = StreamController<Map<String, dynamic>>();
  Map<String, dynamic>? saved;
  @override
  Stream<Map<String, dynamic>> get events => updates.stream;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (method == 'save') saved = Map<String, dynamic>.from(args!['config']);
    return method == 'load'
        ? {
            'config': {'overlayX': 0.1, 'overlayY': 0.2},
          }
        : {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/runtime'),
          (call) async => call.method == 'load'
              ? {'config': {}, 'samples': {}, 'status': {}}
              : {},
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/events'),
          (call) async => null,
        );
  });
  Future<AppController> load() async {
    final c = AppController();
    await c.initialize();
    return c;
  }

  testWidgets('动力电池功率可选择且不自动添加组件或上报', (tester) async {
    final c = (await tester.runAsync(load))!;
    final power = c.metrics.singleWhere((m) => m.id == 'derived.battery_power');
    expect(power.name, '动力电池功率');
    expect(power.category, '动力电池');
    expect(power.unit, 'kW');
    expect(power.displayAllowed, isTrue);
    expect(c.metrics.singleWhere((m) => m.id == '1009/5/1145045000').unit, 'V');
    expect(c.metrics.singleWhere((m) => m.id == '1009/7/1145045016').unit, 'A');
    expect(c.metrics.singleWhere((m) => m.id == '1039/5/677380120').unit, 'A');
    expect(c.tiles, isEmpty);
    expect(c.overlays, isEmpty);
    expect(c.uploaded, isEmpty);
    c.dispose();
  });

  testWidgets('用户确认单位与原始编码展示并保留待充电验证项', (tester) async {
    final c = (await tester.runAsync(load))!;
    for (final entry in {
      '1005/5/1031798840': ('压缩机功耗', 'W'),
      '1005/5/1320169504': ('PTC功耗', 'W'),
      '1012/5/339738656': ('动力功率', 'kW'),
      '1000/5/1031798832': ('车内温度', '°C'),
      '1014/5/1145045032': ('电池健康度', '%'),
      '1038/5/303038502': ('AEB激活', ''),
      '1014/5/1147142192': ('单体最高电压', 'mV'),
      '1014/5/1147142160': ('单体最低电压', 'mV'),
      '1006/5/1186988096': ('发动机水泵转速', 'rpm'),
      '1039/5/1302331672': ('前电机温度 · DM40', '°C'),
      '1039/5/1178624024': ('前电机温度 · 464', '°C'),
      '1039/5/1302331756': ('后电机温度 · DM40', '°C'),
      '1039/5/1178624040': ('后电机温度 · 464', '°C'),
      '1039/5/1302331648': ('前IPM温度 · DM40', '°C'),
      '1039/5/1178624016': ('前IPM温度 · 464', '°C'),
      '1039/5/1302331748': ('后IPM温度 · DM40', '°C'),
      '1039/5/1178624032': ('后IPM温度 · 464', '°C'),
      '1000/5/1320181776': ('车内滤波温度', '°C'),
      '1039/5/919601208': ('DC/DC温度', '°C'),
      '1007/5/1246797848': ('左前轮胎温度', '°C'),
      '1007/5/1246797860': ('右前轮胎温度', '°C'),
      '1007/5/1246797872': ('左后轮胎温度', '°C'),
      '1007/5/1246797884': ('右后轮胎温度', '°C'),
    }.entries) {
      final m = c.metric(entry.key);
      expect(m.name, entry.value.$1);
      expect(m.unit, entry.value.$2);
    }
    expect(
      c.metrics.where((m) => m.name.contains('候选')).map((m) => m.id).toSet(),
      {'1009/7/666894360', '1009/7/1249050652'},
    );
    c.dispose();
  });
  testWidgets('拖动位置同步后设置保存与导出保留新位置', (tester) async {
    final bridge = PositionBridge();
    final c = AppController(bridge: bridge);
    await tester.runAsync(c.initialize);
    bridge.updates.add({
      'overlayPosition': {'x': 0.75, 'y': 0.8},
    });
    await tester.pump();
    await c.save();
    expect(bridge.saved!['overlayX'], 0.75);
    expect(jsonDecode(c.exportConfig())['overlayY'], 0.8);
    c.dispose();
    await tester.runAsync(bridge.updates.close);
  });

  testWidgets('菜单动效、外部关闭、返回键及实车密度无渲染异常', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(load))!;
    await tester.pumpWidget(SkyInfo(controller: c));
    await tester.tap(find.byIcon(Icons.menu));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
    expect(find.byType(Drawer), findsNothing);
    expect(tester.getSize(find.text('信息').last).height, lessThan(32));
    await tester.tapAt(const Offset(800, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('悬浮窗'), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('悬浮窗'), findsNothing);
    for (final name in ['悬浮窗', '连接', '设置', '信息']) {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.text(name).last);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('实车密度下编辑弹窗、键盘与弹出菜单使用相同设计尺度', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    await tester.pumpWidget(SkyInfo(controller: c));
    await tester.tap(find.byTooltip('编辑布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加组件').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('使用预设'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-低压电压')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.tap(find.text('添加到仪表盘').last);
    await tester.pumpAndSettle();
    expect(c.tiles, hasLength(1));
    if (find.byTooltip('编辑布局').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('编辑布局'));
    }
    await tester.pump();
    await tester.tap(find.byTooltip('编辑组件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('size-2-1')));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(c.tiles.single.rows, 1);
    c.tiles[0] = TileSpec(
      id: c.tiles.single.id,
      title: '双数值',
      kind: WidgetKind.pair,
      fields: c.metrics
          .where((m) => m.displayAllowed)
          .take(2)
          .map((m) => m.id)
          .toList(),
      columns: 1,
      rows: 2,
    );
    await c.save();
    await tester.pump();
    expect(find.byTooltip('调整尺寸'), findsNothing);
    await tester.tap(find.byTooltip('编辑组件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('size-4-2')));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(c.tiles.single.columns, 4);
    expect(c.tiles.single.rows, 2);
    await tester.tap(find.byTooltip('编辑组件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('size-2-1')));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(c.tiles.single.columns, 2);
    expect(c.tiles.single.rows, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('停止与恢复切换按钮，保留用户配置', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final actions = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/runtime'),
          (call) async {
            if (call.method == 'stop' || call.method == 'resume') {
              actions.add(call.method);
              return {
                'status': {'stopped': call.method == 'stop'},
              };
            }
            return call.method == 'load'
                ? {'config': {}, 'samples': {}, 'status': {}}
                : {};
          },
        );
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    c.overlayEnabled = true;
    c.uploaded = {'1032/7/1128267816'};
    final before = jsonDecode(jsonEncode(c.config));
    await tester.pumpWidget(SkyInfo(controller: c));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('采集').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(IndustrialButton, '停止运行'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(IndustrialButton, '恢复运行'), findsOneWidget);
    expect(c.config, before);
    await tester.tap(find.widgetWithText(IndustrialButton, '恢复运行'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(IndustrialButton, '停止运行'), findsOneWidget);
    expect(c.config, before);
    expect(actions, ['stop', 'resume']);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('首次配置为空，主页选择不会自动上报', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    expect(c.tiles, isEmpty);
    expect(c.overlays, isEmpty);
    expect(c.uploaded, isEmpty);
    await tester.pumpWidget(SkyInfo(controller: c));
    expect(find.text('尚未添加组件'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加组件').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用预设'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-低压电压')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加到仪表盘'));
    await tester.pumpAndSettle();
    expect(c.tiles, hasLength(1));
    expect(c.uploaded, isEmpty);
    expect(c.overlays, isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('布局编辑长按拖动吸附，铅笔编辑固定跨度并保存位置', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic> stored = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/runtime'),
          (call) async {
            if (call.method == 'save') {
              stored = Map<String, dynamic>.from(
                jsonDecode(jsonEncode((call.arguments as Map)['config'])),
              );
            }
            return call.method == 'load'
                ? {'config': stored, 'samples': {}, 'status': {}}
                : {};
          },
        );
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    c.dashboardSize = DashboardSize.enlarged;
    c.tiles.add(
      TileSpec(
        id: 'move',
        title: '拖动测试',
        kind: WidgetKind.pair,
        fields: c.metrics
            .where((m) => m.displayAllowed)
            .take(2)
            .map((m) => m.id)
            .toList(),
      ),
    );
    await tester.pumpWidget(SkyInfo(controller: c));
    await tester.tap(find.byTooltip('编辑布局'));
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('拖动测试')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(396, 198));
    await gesture.up();
    await tester.pump();
    expect(c.tiles.single.column, 2);
    expect(c.tiles.single.row, 1);
    expect(find.byTooltip('调整尺寸'), findsNothing);
    await tester.tap(find.byTooltip('编辑组件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('size-4-2')));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(c.tiles.single.columns, 4);
    expect(c.tiles.single.rows, 2);
    await tester.tap(find.byTooltip('编辑组件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('size-2-1')));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(c.tiles.single.columns, 2);
    expect(c.tiles.single.rows, 1);
    expect(c.tiles.single.column, 2);
    expect(c.tiles.single.row, 1);
    expect(
      TileSpec.fromJson(
        Map<String, dynamic>.from((stored['tiles'] as List).single),
      ).rows,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('四页导航、分类列表和主题切换可操作', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    await tester.pumpWidget(SkyInfo(controller: c));
    await tester.pump();
    expect(find.text('尚未添加组件'), findsOneWidget);
    for (final title in ['悬浮窗', '连接', '设置']) {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(c.theme, 'dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('组件编辑保存、选择数据和时间互斥', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    await tester.pumpWidget(SkyInfo(controller: c));
    await tester.tap(find.byTooltip('编辑布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加组件').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用预设'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-低压电压')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加到仪表盘').last);
    await tester.pumpAndSettle();
    expect(c.tiles.length, 1);
    expect(c.tiles.single.time, TimeDisplay.none);
    expect(c.uploaded, isEmpty);
    expect(find.text('13.6'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('1024×600布局与悬浮模块编辑无溢出', (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    await tester.pumpWidget(SkyInfo(controller: c));
    for (final title in ['悬浮窗', '连接', '设置']) {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('四页浅色和深色预览', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      await tester.runAsync(loader.load);
    }
    final c = (await tester.runAsync(load))!;
    c.reduceMotion = true;
    c.reduceMotion = true;
    c.tiles = [
      const TileSpec(
        id: 'a',
        title: '热管理',
        kind: WidgetKind.list,
        fields: ['1005/5/1031798840', '1005/5/1320169504', '1006/5/1186988096'],
      ),
      const TileSpec(
        id: 'b',
        title: '低压电压',
        kind: WidgetKind.number,
        fields: ['1032/7/1128267816'],
      ),
      const TileSpec(
        id: 'c',
        title: '电池温度',
        kind: WidgetKind.pair,
        fields: ['1014/5/1148190752', '1014/5/1148190736'],
      ),
      const TileSpec(
        id: 'd',
        title: '冷却水泵',
        kind: WidgetKind.number,
        fields: ['1006/5/1186988096'],
        columns: 1,
        rows: 1,
      ),
      const TileSpec(
        id: 'e',
        title: 'DC/DC温度',
        kind: WidgetKind.number,
        fields: ['1039/5/919601208'],
        columns: 1,
        rows: 1,
      ),
      const TileSpec(
        id: 'f',
        title: '低压电压历史',
        kind: WidgetKind.trend,
        fields: ['1032/7/1128267816'],
        columns: 4,
        rows: 2,
      ),
    ];
    for (final theme in ['light', 'dark']) {
      c.theme = theme;
      await tester.pumpWidget(SkyInfo(key: ValueKey(theme), controller: c));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$theme-navigation.png'),
      );
      await tester.tapAt(const Offset(1200, 450));
      await tester.pumpAndSettle();
      for (final title in ['信息', '悬浮窗', '连接', '设置']) {
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (title != '设置') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/$theme-$title.png'),
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}

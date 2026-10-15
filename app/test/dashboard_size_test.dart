import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/dashboard_layout.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/metric_tile.dart';

class SizeBridge extends VehicleBridge {
  final calls = <String>[];
  Map<String, dynamic> stored = {};
  bool fail = false;
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    if (method == 'save') {
      if (fail) throw PlatformException(code: 'save-failed');
      stored = jsonDecode(jsonEncode(args!['config']));
    }
    return {'config': stored, 'samples': {}, 'status': {}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  const field = '1032/7/1128267816';
  void viewport(WidgetTester t, [Size size = const Size(1600, 900)]) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<AppController> load(WidgetTester t, SizeBridge b) async =>
      (await t.runAsync(() async {
        final c = AppController(bridge: b);
        await c.initialize();
        c.reduceMotion = true;
        c.tiles = [
          TileSpec(
            id: 'tile',
            title: '低压电压',
            kind: WidgetKind.number,
            fields: [field],
          ),
        ];
        c.applySamples({
          field: {'value': 13.7, 'unit': 'V', 'quality': 'available'},
        });
        return c;
      }))!;
  Future<void> close(WidgetTester t, AppController c) async {
    await t.pumpWidget(const SizedBox());
    c.dispose();
  }

  test('标准新增两列一行、固定间距与正方格适应车机视口', () {
    for (final size in [
      const Size(1248, 496),
      const Size(1568, 796),
      const Size(1888, 984),
    ]) {
      final large = DashboardLayout.forViewport(
        size.width,
        size.height,
        size: DashboardSize.enlarged,
      );
      final standard = DashboardLayout.forViewport(
        size.width,
        size.height,
        size: DashboardSize.standard,
      );
      expect(standard.columns, large.columns + 2);
      expect(standard.visibleRows, large.visibleRows + 1);
      expect(large.scale, 1);
      expect(standard.scale, lessThan(1));
      expect(standard.width, lessThanOrEqualTo(size.width + 1e-8));
      expect(
        standard.span(standard.visibleRows),
        lessThanOrEqualTo(size.height + 1e-8),
      );
      expect(standard.gap, 9.6);
      expect(
        standard.height,
        closeTo(standard.span(standard.visibleRows), 1e-8),
      );
      expect(
        standard.verticalInset * 2 + standard.height,
        closeTo(size.height, 1e-8),
      );
      expect(standard.span(2) / large.span(2), closeTo(standard.scale, 1e-8));
      for (final cells in [1, 2, 4]) {
        expect(
          standard.span(cells),
          closeTo(cells * standard.cell + (cells - 1) * 9.6, 1e-8),
        );
      }
    }
  });

  testWidgets('设置两档可保存恢复与导出，失败回退，不改变组件或触发控制', (t) async {
    viewport(t);
    final b = SizeBridge(), c = await load(t, b);
    final before = jsonEncode(c.tiles.map((x) => x.toJson()).toList());
    expect(c.dashboardSize, DashboardSize.standard);
    c.dashboardSize = DashboardSize.enlarged;
    await t.pumpWidget(SkyInfo(controller: c));
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('设置').last);
    await t.pumpAndSettle();
    expect(find.text('主页显示大小'), findsOneWidget);
    await t.tap(find.text('标准'));
    await t.pumpAndSettle();
    expect(c.dashboardSize, DashboardSize.standard);
    expect(b.stored['dashboardSize'], 'standard');
    expect(jsonDecode(c.exportConfig())['dashboardSize'], 'standard');
    final restored = AppController();
    restored.restore(b.stored);
    expect(restored.dashboardSize, DashboardSize.standard);
    restored.dispose();
    b.fail = true;
    await t.tap(find.text('放大'));
    await t.pumpAndSettle();
    expect(c.dashboardSize, DashboardSize.standard);
    expect(jsonEncode(c.tiles.map((x) => x.toJson()).toList()), before);
    expect(b.calls.where((x) => x == 'control' || x == 'haControl'), isEmpty);
    await close(t, c);
  });

  testWidgets('主页卡片等比例变化而Header与组件配置保持，标准模式铅笔可命中', (t) async {
    viewport(t);
    final b = SizeBridge(), c = await load(t, b);
    c.dashboardSize = DashboardSize.enlarged;
    await t.pumpWidget(SkyInfo(controller: c));
    final slot = find.byKey(const ValueKey('dashboard-slot-tile'));
    final large = t.getSize(slot);
    final menu = t.getSize(find.byIcon(Icons.menu));
    final inner = t.getSize(find.byType(MetricTile));
    c.dashboardSize = DashboardSize.standard;
    await c.save();
    await t.pumpAndSettle();
    final standard = t.getSize(slot);
    expect(standard.width, lessThan(large.width));
    expect(
      standard.width / large.width,
      closeTo(standard.height / large.height, 1e-8),
    );
    expect(
      t.getSize(find.byType(MetricTile)).width,
      closeTo(inner.width, 1e-8),
    );
    expect(
      t.getSize(find.byType(MetricTile)).height,
      closeTo(inner.height, 1e-8),
    );
    expect(t.getSize(find.byIcon(Icons.menu)), menu);
    expect(c.tiles.single.columns, 2);
    expect(c.tiles.single.rows, 2);
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('编辑组件'));
    await t.pumpAndSettle();
    expect(find.text('编辑组件'), findsWidgets);
    expect(t.takeException(), isNull);
    await close(t, c);
  });

  testWidgets('标准模式长按拖动用实际缩放网格坐标保存位置', (t) async {
    viewport(t);
    final b = SizeBridge(), c = await load(t, b);
    c.dashboardSize = DashboardSize.standard;
    await t.pumpWidget(SkyInfo(controller: c));
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    final slot = find.byKey(const ValueKey('dashboard-slot-tile'));
    final origin = t.getTopLeft(slot);
    final layout = DashboardLayout.forViewport(
      1568,
      796,
      size: DashboardSize.standard,
    );
    final gesture = await t.startGesture(t.getCenter(slot));
    await t.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(
      origin +
          Offset(
            2 * (layout.cell + layout.gap) + 4,
            layout.cell + layout.gap + 4,
          ),
    );
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(c.tiles.single.column, 2);
    expect(c.tiles.single.row, 1);
    expect(b.stored['dashboardSize'], 'standard');
    expect(t.takeException(), isNull);
    await close(t, c);
  });

  testWidgets('标准窄屏与字体放大无溢出', (t) async {
    viewport(t, const Size(600, 720));
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await load(t, SizeBridge());
    c.dashboardSize = DashboardSize.standard;
    await t.pumpWidget(SkyInfo(controller: c));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await close(t, c);
  });

  testWidgets('车机240dpi和系统栏，两档尺寸按APP可用内容计算', (t) async {
    viewport(t, const Size(1920, 1080));
    t.view.devicePixelRatio = 1.5;
    const insets = FakeViewPadding(top: 84, bottom: 96);
    t.view.padding = insets;
    t.view.viewPadding = insets;
    addTearDown(t.view.resetPadding);
    addTearDown(t.view.resetViewPadding);
    final c = await load(t, SizeBridge());
    c.dashboardSize = DashboardSize.enlarged;
    await t.pumpWidget(SkyInfo(controller: c));
    await t.pumpAndSettle();
    final slot = find.byKey(const ValueKey('dashboard-slot-tile'));
    final large = t.getSize(slot);
    expect(large.width * 1.5, closeTo(608, 1e-5));
    expect(large.height * 1.5, closeTo(608, 1e-5));
    expect(t.getTopLeft(slot).dx * 1.5, closeTo(24, 1e-5));
    final layout = DashboardLayout.forViewport(
      1248,
      496,
      size: DashboardSize.standard,
    );
    expect(layout.columns, 8);
    expect(layout.visibleRows, 3);
    expect(layout.scale, closeTo(304.8 / (608 / 1.5), 1e-8));
    c.dashboardSize = DashboardSize.standard;
    await c.save();
    await t.pumpAndSettle();
    final small = t.getSize(slot);
    expect(small.width / large.width, closeTo(layout.scale, 1e-8));
    expect(small.height / large.height, closeTo(layout.scale, 1e-8));
    expect(small.width * 1.5, closeTo(457.2, 1e-5));
    expect(t.getTopLeft(slot).dx, closeTo(16, 1e-5));
    expect(t.getTopLeft(slot).dy, closeTo(161, 1e-5));
    expect(t.takeException(), isNull);
    await close(t, c);
  });

  testWidgets('车机APP窗口1920×900两档浅深视觉以实车比例为基准', (t) async {
    viewport(t, const Size(1920, 900));
    t.view.devicePixelRatio = 1.5;
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
    final c = await load(t, SizeBridge());
    c.tiles.addAll([
      TileSpec(
        id: 'mini',
        title: '电压',
        kind: WidgetKind.number,
        fields: [field],
        columns: 1,
        rows: 1,
      ),
      TileSpec(
        id: 'list',
        title: '供电读数',
        kind: WidgetKind.list,
        fields: [field],
        columns: 2,
        rows: 2,
      ),
    ]);
    for (final theme in ['light', 'dark']) {
      for (final size in DashboardSize.values) {
        c.theme = theme;
        c.dashboardSize = size;
        await t.pumpWidget(SkyInfo(controller: c));
        await t.pumpAndSettle();
        await expectLater(
          find.byType(SkyInfo),
          matchesGoldenFile('goldens/$theme-dashboard-device-${size.name}.png'),
        );
        expect(t.takeException(), isNull);
      }
    }
    await close(t, c);
  });

  testWidgets('两档主页浅深主题视觉', (t) async {
    viewport(t);
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
    final c = await load(t, SizeBridge());
    c.tiles.addAll([
      TileSpec(
        id: 'mini',
        title: '电压',
        kind: WidgetKind.number,
        fields: [field],
        columns: 1,
        rows: 1,
      ),
      TileSpec(
        id: 'list',
        title: '供电读数',
        kind: WidgetKind.list,
        fields: [field],
        columns: 2,
        rows: 4,
      ),
    ]);
    for (final theme in ['light', 'dark']) {
      for (final size in DashboardSize.values) {
        c.theme = theme;
        c.dashboardSize = size;
        await t.pumpWidget(SkyInfo(controller: c));
        await t.pumpAndSettle();
        await expectLater(
          find.byType(SkyInfo),
          matchesGoldenFile('goldens/$theme-dashboard-${size.name}.png'),
        );
        expect(t.takeException(), isNull);
      }
    }
    await close(t, c);
  });
}

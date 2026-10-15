import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/dashboard_layout.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/industrial.dart';

const field = '1032/7/1128267816';

class GridBridge extends VehicleBridge {
  final calls = <String>[];
  Map<String, dynamic> config = {};
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    if (method == 'save') config = jsonDecode(jsonEncode(args!['config']));
    return {'config': config, 'samples': {}, 'status': {}, 'points': []};
  }
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  TileSpec tile(
    String id, {
    int columns = 2,
    int rows = 2,
    WidgetKind kind = WidgetKind.number,
  }) => TileSpec(
    id: id,
    title: id,
    kind: kind,
    fields: [field],
    columns: columns,
    rows: rows,
  );
  Future<AppController> mount(
    WidgetTester t,
    GridBridge bridge,
    List<TileSpec> tiles,
  ) async {
    t.view.physicalSize = const Size(1920, 900);
    t.view.devicePixelRatio = 1.5;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = (await t.runAsync(() async {
      final c = AppController(bridge: bridge);
      await c.initialize();
      c.reduceMotion = true;
      c.tiles = tiles;
      c.applySamples({
        field: {'value': 13.7, 'unit': 'V', 'quality': 'available'},
      });
      return c;
    }))!;
    await t.pumpWidget(SkyInfo(controller: c));
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  Rect visualRect(WidgetTester t, Finder f) =>
      Rect.fromPoints(t.getTopLeft(f), t.getBottomRight(f));

  test('参考车机八列三行正方格、混合卡片优先完整摆放且保留手动位置', () {
    final layout = DashboardLayout.forViewport(
      1248,
      496,
      size: DashboardSize.standard,
    );
    expect(layout.columns, 8);
    expect(layout.visibleRows, 3);
    expect(layout.cell, closeTo(147.6, 1e-8));
    expect(layout.gap, closeTo(9.6, 1e-8));
    expect(layout.width, closeTo(1248, 1e-8));
    expect(layout.height, closeTo(462, 1e-8));
    expect(layout.verticalInset, closeTo(17, 1e-8));
    expect(layout.span(2), closeTo(304.8, 1e-8));
    final cards = [
      tile('v'),
      tile('i'),
      tile('chart', columns: 4),
      tile('device'),
      for (var i = 0; i < 4; i++) tile('short$i', rows: 1),
      tile('entities'),
    ];
    final slots = packTiles(cards, 8, compact: true, visibleRows: 3);
    expect(slots.map((s) => s.tile.id), cards.map((s) => s.id));
    expect(slots.where((s) => s.row + s.tile.rows <= 3).length, 7);
    expect(
      slots.where((s) => s.tile.rows == 1).every((s) => s.row == 2),
      isTrue,
    );
    expect(
      slots.where((s) => s.tile.rows == 2).every((s) => s.row != 2),
      isTrue,
    );
    final pinned = cards.last.positioned(4, 2);
    final fixed = packTiles(
      [...cards.take(8), pinned],
      8,
      compact: true,
      visibleRows: 3,
    ).last;
    expect((fixed.column, fixed.row), (4, 2));
    expect(packTiles(cards, 6).last.row, 4);
  });

  testWidgets('四个正常与四个矮组件完整可见，新增正常卡保持可滚动', (t) async {
    final c = await mount(t, GridBridge(), [
      for (var i = 0; i < 4; i++) tile('card$i'),
      for (var i = 4; i < 8; i++) tile('card$i', rows: 1),
    ]);
    for (var i = 0; i < 8; i++) {
      final rect = visualRect(t, find.byKey(ValueKey('dashboard-slot-card$i')));
      expect(rect.width, closeTo(304.8, 1e-5));
      expect(rect.height, closeTo(i < 4 ? 304.8 : 147.6, 1e-5));
      expect(rect.top, greaterThanOrEqualTo(104.999));
      expect(rect.bottom, lessThanOrEqualTo(567.001));
    }
    expect(
      t.getTopLeft(find.byKey(const ValueKey('dashboard-slot-card0'))).dx,
      closeTo(16, 1e-5),
    );
    c.tiles.add(tile('ninth'));
    await c.save();
    await t.pumpAndSettle();
    final ninth = find.byKey(const ValueKey('dashboard-slot-ninth'));
    expect(visualRect(t, ninth).top, greaterThan(567));
    await t.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -400),
    );
    await t.pumpAndSettle();
    expect(visualRect(t, ninth).bottom, lessThanOrEqualTo(567.001));
    expect(t.takeException(), isNull);
  });

  testWidgets('2×4保留正方格跨度，滚动能看到整张卡的底部', (t) async {
    await mount(t, GridBridge(), [tile('tall', rows: 4)]);
    final card = find.byKey(const ValueKey('dashboard-slot-tall'));
    final rect = visualRect(t, card);
    expect(rect.width, closeTo(304.8, 1e-5));
    expect(rect.height, closeTo(619.2, 1e-5));
    await t.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -220),
    );
    await t.pumpAndSettle();
    expect(visualRect(t, card).bottom, closeTo(567, 1e-4));
    expect(t.takeException(), isNull);
  });

  testWidgets('滚动后的拖放仍按网格原点保存，手动位置不被首屏排列覆盖', (t) async {
    final bridge = GridBridge();
    final c = await mount(t, bridge, [
      for (var i = 0; i < 8; i++) tile('card$i'),
    ]);
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    await t.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -240),
    );
    await t.pumpAndSettle();
    final slot = find.byKey(const ValueKey('dashboard-slot-card4'));
    final origin = t.getTopLeft(slot);
    final gesture = await t.startGesture(t.getCenter(slot));
    await t.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(origin + const Offset(2 * 157.2 + 4, 4));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect((c.tiles[4].column, c.tiles[4].row), (2, 3));
    final saved = (bridge.config['tiles'] as List).firstWhere(
      (t) => t['id'] == 'card4',
    );
    expect((saved['column'], saved['row']), (2, 3));
    expect(t.takeException(), isNull);
  });

  testWidgets('车机标准档使用实际坐标拖动到右下角并保存', (t) async {
    final bridge = GridBridge();
    final c = await mount(t, bridge, [tile('movable')]);
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    final slot = find.byKey(const ValueKey('dashboard-slot-movable'));
    final origin = t.getTopLeft(slot);
    final gesture = await t.startGesture(t.getCenter(slot));
    await t.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(origin + const Offset(6 * 157.2 + 4, 157.2 + 4));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect((c.tiles.single.column, c.tiles.single.row), (6, 1));
    expect(visualRect(t, slot).right, closeTo(1264, 1e-4));
    expect(bridge.config['dashboardSize'], 'standard');
    expect(t.takeException(), isNull);
  });

  testWidgets('标准实际缩放后刷新与开关双轴热区至少48dp，编辑迷你卡不溢出', (t) async {
    final bridge = GridBridge();
    final c = await mount(t, bridge, [
      tile('history', kind: WidgetKind.trend, columns: 4),
      TileSpec(
        id: 'switch',
        title: '空调电源',
        kind: WidgetKind.toggle,
        fields: ['control.ac_power'],
      ),
      tile('mini', columns: 1, rows: 1),
    ]);
    for (final finder in [
      find.ancestor(
        of: find.byIcon(Icons.refresh),
        matching: find.byType(IndustrialIconButton),
      ),
      find.byType(IndustrialSwitch),
    ]) {
      final rect = visualRect(t, finder);
      expect(rect.width, greaterThanOrEqualTo(47.999));
      expect(rect.height, greaterThanOrEqualTo(47.999));
    }
    final refresh = find.ancestor(
      of: find.byIcon(Icons.refresh),
      matching: find.byType(IndustrialIconButton),
    );
    final before = bridge.calls.where((x) => x == 'history').length;
    await t.tapAt(visualRect(t, refresh).topLeft + const Offset(2, 2));
    await t.pumpAndSettle();
    expect(bridge.calls.where((x) => x == 'history').length, before + 1);
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    final mini = find.byKey(const ValueKey('dashboard-slot-mini'));
    final pencil = find.descendant(of: mini, matching: find.byTooltip('编辑组件'));
    final rect = visualRect(t, pencil);
    expect(rect.width, closeTo(48, 1e-5));
    expect(rect.height, closeTo(48, 1e-5));
    await t.tap(pencil);
    await t.pumpAndSettle();
    expect(find.text('编辑组件'), findsWidgets);
    expect(
      bridge.calls.where((x) => x == 'control' || x == 'haControl'),
      isEmpty,
    );
    expect(c.tiles.last.columns, 1);
    expect(t.takeException(), isNull);
  });
}

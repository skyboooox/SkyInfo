import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/attention.dart';
import 'package:skyinfo/ui/history_preferences.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/tile_editor.dart';

class UiBridge extends VehicleBridge {
  final calls = <String>[];
  final saved = <Map<String, dynamic>>[];
  bool failSave = false;
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    if (method == 'save') {
      if (failSave) throw PlatformException(code: 'test-failure');
      saved.add(Map<String, dynamic>.from(args!['config']));
    }
    return method == 'load'
        ? {'config': {}, 'samples': {}, 'status': {}}
        : method == 'history'
        ? {'points': []}
        : {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  void viewport(
    WidgetTester t, {
    Size size = const Size(1600, 900),
    double dpr = 1,
    double fontScale = 1,
  }) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = dpr;
    t.platformDispatcher.textScaleFactorTestValue = fontScale;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<AppController> load(WidgetTester t, UiBridge bridge) async =>
      (await t.runAsync(() async {
        final c = AppController(bridge: bridge);
        await c.initialize();
        c.reduceMotion = true;
        return c;
      }))!;
  Future<void> dispose(WidgetTester t, AppController c) async {
    await t.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets('删除确认取消与Escape不写入，确认只删除当前组件，失败恢复布局', (t) async {
    viewport(t);
    final bridge = UiBridge();
    final c = await load(t, bridge);
    const id = '1032/7/1128267816';
    c.tiles = [
      TileSpec(id: 'a', title: '保留甲', kind: WidgetKind.number, fields: [id]),
      TileSpec(id: 'b', title: '删除乙', kind: WidgetKind.number, fields: [id]),
    ];
    await t.pumpWidget(SkyInfo(controller: c));
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('编辑组件').last);
    await t.pumpAndSettle();
    await t.tap(find.text('删除组件'));
    await t.pumpAndSettle();
    expect(find.text('删除组件？'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(c.tiles.map((x) => x.id), ['a', 'b']);
    expect(bridge.saved, isEmpty);
    await t.tap(find.text('删除组件'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消').last);
    await t.pumpAndSettle();
    expect(c.tiles, hasLength(2));
    bridge.failSave = true;
    await t.tap(find.text('删除组件'));
    await t.pumpAndSettle();
    await t.tap(find.text('删除').last);
    await t.pumpAndSettle();
    expect(c.tiles.map((x) => x.id), ['a', 'b']);
    expect(find.text('删除组件'), findsOneWidget);
    bridge.failSave = false;
    await t.tap(find.text('删除组件'));
    await t.pumpAndSettle();
    await t.tap(find.text('删除').last);
    await t.pumpAndSettle();
    expect(c.tiles.map((x) => x.id), ['a']);
    expect(bridge.saved.last['tiles'], hasLength(1));
    expect(
      bridge.calls.where((x) => ['command', 'haControl'].contains(x)),
      isEmpty,
    );
    expect(t.takeException(), isNull);
    await dispose(t, c);
  });

  testWidgets('悬浮模块只在编辑器确认后删除，取消保留模块', (t) async {
    viewport(t);
    final bridge = UiBridge();
    final c = await load(t, bridge);
    c.overlays = [
      const OverlaySpec(
        id: 'strip',
        field: '1032/7/1128267816',
        icon: '',
        unit: '',
        alignment: 'center',
      ),
    ];
    await t.pumpWidget(SkyInfo(controller: c));
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('悬浮窗').last);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsNothing);
    await t.tap(find.byTooltip('编辑悬浮模块'));
    await t.pumpAndSettle();
    await t.tap(find.text('删除'));
    await t.pumpAndSettle();
    expect(find.text('删除悬浮模块？'), findsOneWidget);
    await t.tap(find.text('取消').last);
    await t.pumpAndSettle();
    expect(c.overlays, hasLength(1));
    expect(bridge.saved, isEmpty);
    await t.tap(find.text('删除'));
    await t.pumpAndSettle();
    await t.tap(find.text('删除').last);
    await t.pumpAndSettle();
    expect(c.overlays, isEmpty);
    expect(bridge.saved.last['overlays'], isEmpty);
    await dispose(t, c);
  });

  testWidgets('历史偏好即刻保存，关闭与取消清空均保留记录，清空只发本地动作', (t) async {
    viewport(t);
    final bridge = UiBridge();
    final c = await load(t, bridge);
    await t.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLocalHistoryPreferences(context, c),
              child: const Text('history'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('history'));
    await t.pumpAndSettle();
    expect(find.text('保存'), findsNothing);
    expect(find.text('取消'), findsNothing);
    await t.tap(find.byType(IndustrialSwitch).first);
    await t.pumpAndSettle();
    expect(c.localHistory, isFalse);
    expect(bridge.saved.last['localHistory'], isFalse);
    await t.tap(find.text('清空'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消').last);
    await t.pumpAndSettle();
    expect(bridge.calls.where((x) => x == 'clearHistory'), isEmpty);
    await t.tap(find.text('清空'));
    await t.pumpAndSettle();
    await t.tap(find.text('清空').last);
    await t.pumpAndSettle();
    expect(bridge.calls.where((x) => x == 'clearHistory'), hasLength(1));
    await t.tap(find.text('关闭'));
    await t.pumpAndSettle();
    expect(c.localHistory, isFalse);
    expect(bridge.calls.where((x) => x.startsWith('ha')), isEmpty);
    await dispose(t, c);
  });

  testWidgets('创建返回保留搜索、选择与兼容样式；取消不保存', (t) async {
    viewport(t);
    final bridge = UiBridge();
    final c = await load(t, bridge);
    await t.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editTile(context, c),
              child: const Text('wizard'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('wizard'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '电池最高温度');
    await t.pumpAndSettle();
    await t.tap(find.byType(XCheck).first);
    await t.pumpAndSettle();
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('上一步'));
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '电池最高温度',
    );
    expect(t.widget<XCheck>(find.byType(XCheck).first).value, isTrue);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(c.tiles, isEmpty);
    expect(bridge.saved, isEmpty);
    expect(
      bridge.calls.where((x) => ['command', 'haControl'].contains(x)),
      isEmpty,
    );
    await dispose(t, c);
  });

  testWidgets('窄屏及字体放大四页重排，没有整页缩放或溢出', (t) async {
    viewport(t, size: const Size(390, 844), fontScale: 1.6);
    final bridge = UiBridge();
    final c = await load(t, bridge);
    await t.pumpWidget(SkyInfo(controller: c));
    expect(
      t.getSize(
        find.ancestor(
          of: find.byIcon(Icons.menu),
          matching: find.byType(IndustrialIconButton),
        ),
      ),
      const Size(56, 56),
    );
    for (final name in ['悬浮窗', '连接', '设置', '信息']) {
      await t.tap(find.byIcon(Icons.menu));
      await t.pumpAndSettle();
      await t.tap(find.text(name).last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: name);
    }
    await dispose(t, c);
  });

  testWidgets('逻辑密度不会缩小48热区，键盘与缩放字体下编辑器可退出', (t) async {
    viewport(t, size: const Size(1920, 1080), dpr: 1.5, fontScale: 1.4);
    final bridge = UiBridge();
    final c = await load(t, bridge);
    await t.pumpWidget(SkyInfo(controller: c));
    expect(t.getSize(find.byTooltip('编辑布局')), const Size(48, 48));
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    await t.tap(find.text('添加组件').first);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    t.view.viewInsets = const FakeViewPadding(bottom: 480);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    t.view.resetViewInsets();
    await dispose(t, c);
  });

  testWidgets('按钮、X和开关支持键盘，禁用开关保持选中值且不执行', (t) async {
    viewport(t);
    var presses = 0;
    bool changed = false;
    await t.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              IndustrialButton(
                '确认',
                autofocus: true,
                onPressed: () => presses++,
              ),
              XCheck(value: false, onChanged: (v) => changed = v),
              const IndustrialSwitch(value: true, onChanged: null),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(presses, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(changed, isTrue);
    final disabled = find.byType(IndustrialSwitch);
    expect(t.widget<IndustrialSwitch>(disabled).value, isTrue);
    expect(t.getSize(disabled), const Size(76, 48));
    expect(t.takeException(), isNull);
  });

  testWidgets('等待纹理只在前台运动，减少动画与后台停帧', (t) async {
    viewport(t);
    Widget scene(bool enabled, bool reduce) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(
          enabled: enabled,
          child: const Scaffold(
            body: AttentionSurface(
              color: Colors.amber,
              child: SizedBox(width: 300, height: 48),
            ),
          ),
        ),
      ),
    );
    await t.pumpWidget(scene(true, false));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpWidget(scene(false, false));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.binding.hasScheduledFrame, isFalse);
    await t.pumpWidget(scene(true, true));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.binding.hasScheduledFrame, isFalse);
    expect(t.takeException(), isNull);
  });
}

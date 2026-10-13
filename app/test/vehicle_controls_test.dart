import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/entity_content.dart';

class ControlBridge extends VehicleBridge {
  final calls = <(String, Map<String, dynamic>?)>[];
  Completer<Map<String, dynamic>>? pending;
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add((method, args));
    if (method == 'control') {
      return pending?.future ?? {'status': 'accepted_unconfirmed', 'actual': 1};
    }
    return {'config': {}, 'status': {}, 'samples': {}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = 'control.ac_cycle';
  Future<AppController> load(WidgetTester t, ControlBridge bridge) async {
    final c = AppController(bridge: bridge);
    await t.runAsync(c.initialize);
    c.reduceMotion = true;
    c.tiles.add(
      TileSpec(
        id: 'cycle',
        title: '循环模式',
        kind: WidgetKind.select,
        fields: [id],
      ),
    );
    return c;
  }

  void feedback(AppController c, int value) => c.applySamples({
    '1000/5/1077936148': {
      'value': value,
      'raw': value,
      'quality': 'available',
      'updatedAt': 1000,
    },
  });
  testWidgets('控制作为主动添加的实体，无独立菜单；选择不写入，状态来自订阅读回', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final b = ControlBridge();
    final c = await load(t, b);
    feedback(c, 0);
    await t.pumpWidget(SkyInfo(controller: c));
    await t.pumpAndSettle();
    expect(find.byTooltip('车辆控制'), findsNothing);
    await t.tap(find.byKey(const ValueKey('entity-details-$id')));
    await t.pumpAndSettle();
    await t.tap(find.text('内循环'));
    await t.pumpAndSettle();
    expect(b.calls.where((e) => e.$1 == 'control'), isEmpty);
    await t.tap(find.text('发送'));
    await t.pumpAndSettle();
    expect(b.calls.singleWhere((e) => e.$1 == 'control').$2, {
      'action': 'ac_cycle',
      'value': 1,
    });
    expect(c.reading(id).value.stateLabel, '外循环');
    feedback(c, 1);
    await t.pump();
    expect(c.reading(id).value.stateLabel, '内循环');
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('重复点击去重，未添加实体和未知参数不会下发，销毁后回执安全释放', (t) async {
    final b = ControlBridge()..pending = Completer();
    final c = await load(t, b);
    final first = c.command(id, 1);
    expect((await c.command(id, 1))['status'], 'busy');
    expect((await c.command('control.ac_power', 1))['status'], 'not_added');
    expect(b.calls.where((e) => e.$1 == 'control').length, 1);
    c.dispose();
    b.pending!.complete({'status': 'accepted_unconfirmed'});
    await first;
    final other = await load(t, ControlBridge());
    expect((await other.command(id, 999))['status'], 'invalid_value');
    other.dispose();
  });
  testWidgets('推测实体直接使用固定计划，未知参数不发送，异常反馈不伪装成关闭', (t) async {
    final b = ControlBridge();
    final c = await load(t, b);
    c.tiles.add(
      TileSpec(
        id: 'hud',
        title: 'HUD',
        kind: WidgetKind.entity,
        fields: ['control.hud_brightness'],
      ),
    );
    expect(
      (await c.command('control.hud_brightness', 1))['status'],
      'accepted_unconfirmed',
    );
    expect(b.calls.where((e) => e.$1 == 'control').length, 1);
    expect(
      (await c.command('control.hud_brightness', 999))['status'],
      'invalid_value',
    );
    expect(b.calls.where((e) => e.$1 == 'control').length, 1);
    expect(c.controlEntity('control.hud_brightness').inferred, isTrue);
    expect(c.config.containsKey('inferredControlsEnabled'), isFalse);
    feedback(c, 65535);
    expect(c.reading(id).value.value, isNull);
    feedback(c, 42);
    expect(c.reading(id).value.value, isNull);
    c.dispose();
  });
  testWidgets('设置不再提供推测开关，旧配置不会保留阻断，选择和预览不下发', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final b = ControlBridge(), c = await load(t, b);
    c.restore({...c.config, 'inferredControlsEnabled': false});
    expect(c.config.containsKey('inferredControlsEnabled'), isFalse);
    await t.pumpWidget(SkyInfo(controller: c));
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('设置').last);
    await t.pumpAndSettle();
    await t.tap(find.text('高级').first);
    await t.pumpAndSettle();
    expect(find.text('推测控制'), findsNothing);
    expect(find.text('请开启推测控制'), findsNothing);
    expect(b.calls.where((e) => e.$1 == 'control'), isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('实体预览没有可执行控件，嵌套预览共享并分别释放订阅', (t) async {
    final b = ControlBridge();
    final c = await load(t, b);
    feedback(c, 0);
    final a = c.acquirePreview([id]);
    final nested = c.acquirePreview(['control.ac_power']);
    await t.pump();
    expect(b.calls.last.$2!['fields'], containsAll([id, 'control.ac_power']));
    nested.dispose();
    await t.pump();
    expect(b.calls.last.$2!['fields'], [id]);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityContent(
            controller: c,
            tile: c.tiles.first,
            disabled: true,
            now: DateTime.now(),
          ),
        ),
      ),
    );
    expect(
      t
          .widget<IconButton>(find.byKey(const ValueKey('entity-details-$id')))
          .onPressed,
      isNull,
    );
    a.dispose();
    await t.pump();
    expect(b.calls.last.$2!['fields'], isEmpty);
    expect(b.calls.where((e) => e.$1 == 'control'), isEmpty);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
}

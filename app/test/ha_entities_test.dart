import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/component_compatibility.dart';
import 'package:skyinfo/ui/field_picker.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/tile_editor.dart';

const haSensor = 'ha|one|sensor.temperature';
const haSwitch = 'ha|one|switch.lamp';
Map<String, dynamic> field(String id, String name, String type, String unit) =>
    {
      'id': id,
      'name': name,
      'category': 'Home Assistant',
      'encoding': type,
      'unit': unit,
      'icon': '',
      'entityKey': id.split('|')[2],
      'displayAllowed': true,
    };
final directory = {
  'state': 'connected',
  'fields': {
    haSensor: field(haSensor, '房间温度', '数值', '°C'),
    haSwitch: field(haSwitch, '照明', '文本', ''),
  },
  'entities': [
    {
      'id': haSensor,
      'entityId': 'sensor.temperature',
      'name': '房间温度',
      'domain': 'sensor',
      'field': field(haSensor, '房间温度', '数值', '°C'),
      'functions': [],
    },
    {
      'id': haSwitch,
      'entityId': 'switch.lamp',
      'name': '照明',
      'domain': 'switch',
      'field': field(haSwitch, '照明', '文本', ''),
      'functions': [
        {
          'key': 'power',
          'kind': 'toggle',
          'label': 'ha_power',
          'expected': 'state',
        },
      ],
    },
  ],
};

class HaTestBridge extends VehicleBridge {
  final updates = StreamController<Map<String, dynamic>>();
  final calls = <(String, Map<String, dynamic>?)>[];
  Completer<Map<String, dynamic>>? command;
  @override
  Stream<Map<String, dynamic>> get events => updates.stream;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add((method, args));
    if (method == 'load') {
      return {
        'config': {'haConnectionId': 'one', 'haImportEnabled': true},
        'haDirectory': directory,
        'samples': {
          haSensor: {'value': 68.0, 'unit': '°C', 'quality': 'available'},
          haSwitch: {'value': 'off', 'unit': '', 'quality': 'available'},
        },
      };
    }
    if (method == 'haDirectory') return directory;
    if (method == 'haControl') return (command = Completer()).future;
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(AppController, HaTestBridge)> load() async {
    final b = HaTestBridge();
    final c = AppController(bridge: b);
    await c.initialize();
    c.reduceMotion = true;
    return (c, b);
  }

  void size(WidgetTester t) {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> harness(
    WidgetTester t,
    AppController c,
    void Function(BuildContext) action,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: DesignViewport(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => action(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('打开'));
    await t.pumpAndSettle();
  }

  testWidgets('HA未知动作仍可首次发送，未知开关与不可用动作仍阻断', (t) async {
    final (c, b) = (await t.runAsync(load))!;
    const id = 'ha|one|button.test';
    c.applyHaDirectory({
      'state': 'connected',
      'fields': {id: field(id, '测试动作', '文本', '')},
      'entities': [
        {
          'id': id,
          'entityId': 'button.test',
          'name': '测试动作',
          'domain': 'button',
          'field': field(id, '测试动作', '文本', ''),
          'functions': [
            {'key': 'press', 'kind': 'button', 'label': 'ha_press'},
          ],
        },
      ],
    });
    c.reading(id).value = Sample.fromJson({'quality': 'unknown'});
    c.tiles = [
      TileSpec(
        id: 'action',
        title: '动作',
        kind: WidgetKind.action,
        fields: [id],
      ),
    ];
    final sending = c.haCommand(id, 'press', null);
    expect(b.calls.where((call) => call.$1 == 'haControl'), hasLength(1));
    b.command!.complete({'status': 'accepted_unconfirmed'});
    expect((await sending)['status'], 'accepted_unconfirmed');
    c.reading(id).value = Sample.fromJson({'quality': 'unavailable'});
    expect((await c.haCommand(id, 'press', null))['status'], 'disconnected');
    c.reading(haSwitch).value = Sample.fromJson({'quality': 'unknown'});
    expect(c.canOperateHa(haSwitch), isFalse);
    expect(b.calls.where((call) => call.$1 == 'haControl'), hasLength(1));
    c.dispose();
    b.updates.close();
  });

  testWidgets('HA增量只替换目标描述，属性实时更新且字段与其他实体保持', (t) async {
    final (c, b) = (await t.runAsync(load))!;
    final sensor = c.haEntity(haSensor);
    final metric = c.metric(haSwitch);
    final functions = c.haEntity(haSwitch)!.functions;
    var notifications = 0;
    c.addListener(() => notifications++);
    final update = Map<String, dynamic>.from((directory['entities'] as List)[1])
      ..['attributes'] = {'brightness': 180, 'current_position': 40};
    b.updates.add({
      'haEntityUpdates': [update],
      'samples': {
        haSwitch: {'value': 'on', 'quality': 'available'},
      },
    });
    await t.pump();
    expect(c.haEntity(haSwitch)!.attributes['brightness'], 180);
    expect(c.haEntity(haSwitch)!.functions.first.key, functions.first.key);
    expect(c.haEntity(haSensor), same(sensor));
    expect(c.metric(haSwitch), same(metric));
    expect(c.reading(haSwitch).value.value, 'on');
    expect(notifications, 1);
    c.applyHaEntityUpdates([
      {...update, 'id': 'ha|other|switch.lamp'},
    ]);
    expect(notifications, 1);
    expect(b.calls.where((v) => v.$1 == 'haControl'), isEmpty);
    c.dispose();
    b.updates.close();
  });

  testWidgets('HA来源保持数值/单位，不进行温度减30或显示原值', (t) async {
    final (c, b) = (await t.runAsync(load))!;
    expect(c.reading(haSensor).value.value, 68.0);
    expect(c.metric(haSensor).encoding, 'number');
    expect(c.metric(haSwitch).displayUnit, '');
    expect(c.uploaded, isEmpty);
    expect(c.tiles, isEmpty);
    expect(compatibleKinds(c, [haSwitch]), isNot(contains(WidgetKind.number)));
    expect(compatibleKinds(c, [haSwitch]), contains(WidgetKind.toggle));
    expect(compatibleKinds(c, [haSwitch]), isNot(contains(WidgetKind.trend)));
    expect(
      compatibleKinds(c, [haSwitch, haSensor]),
      contains(WidgetKind.entities),
    );
    expect(
      compatibleKinds(c, [haSwitch, haSensor]),
      isNot(contains(WidgetKind.toggle)),
    );
    c.dispose();
    b.updates.close();
  });
  testWidgets('HA只有保存实体后可控制；并发、属性与离线拒绝且不乐观更新', (t) async {
    final (c, b) = (await t.runAsync(load))!;
    expect((await c.haCommand(haSwitch, 'power', true))['status'], 'not_added');
    c.tiles.add(
      const TileSpec(
        id: 'lamp',
        title: '灯',
        kind: WidgetKind.toggle,
        fields: [haSwitch],
      ),
    );
    final first = c.haCommand(haSwitch, 'power', true);
    await t.pump();
    expect((await c.haCommand(haSwitch, 'power', true))['status'], 'busy');
    expect(
      (await c.haCommand('$haSwitch|brightness', 'power', true))['status'],
      'not_added',
    );
    expect(c.reading(haSwitch).value.value, 'off');
    expect(b.calls.where((v) => v.$1 == 'haControl'), hasLength(1));
    c.applySamples({
      haSwitch: {'value': 'on', 'quality': 'available', 'unit': ''},
    });
    b.command!.complete({'status': 'confirmed'});
    await first;
    expect(c.reading(haSwitch).value.value, 'on');
    expect(c.pendingCommands, isEmpty);
    c.haImportState = 'disconnected';
    expect(
      (await c.haCommand(haSwitch, 'power', false))['status'],
      'disconnected',
    );
    expect(b.calls.where((v) => v.$1 == 'haControl'), hasLength(1));
    c.dispose();
    b.updates.close();
  });
  testWidgets('添加流程保留选择与返回草稿，实时预览不控制也不保存', (t) async {
    size(t);
    final (c, b) = (await t.runAsync(load))!;
    TileSpec? saved;
    await harness(t, c, (context) async => saved = await editTile(context, c));
    await t.tap(find.text('Home Assistant').first);
    await t.pumpAndSettle();
    await t.tap(find.text('房间温度').last);
    await t.pumpAndSettle();
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('上一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('Home Assistant').first);
    await t.pumpAndSettle();
    expect(t.widget<XCheck>(find.byType(XCheck).first).value, isTrue);
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    expect(find.text('68.0'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    await t.tap(find.text('添加到仪表盘'));
    await t.pumpAndSettle();
    expect(saved!.fields, [haSensor]);
    expect(saved!.kind, WidgetKind.number);
    expect(c.tiles, isEmpty);
    expect(
      b.calls.where((v) => v.$1 == 'haControl' || v.$1 == 'save'),
      isEmpty,
    );
    await t.pumpWidget(const SizedBox());
    c.dispose();
    b.updates.close();
    expect(t.takeException(), isNull);
  });
  testWidgets('选择器跨来源筛选保留已选次序，取消不会触发写入', (t) async {
    size(t);
    final (c, b) = (await t.runAsync(load))!;
    List<String>? selected;
    await harness(
      t,
      c,
      (context) async => selected = await chooseFields(
        context,
        c,
        [haSwitch, haSensor],
        multiple: true,
        entities: true,
      ),
    );
    await t.enterText(find.byType(TextField).first, '不会匹配');
    await t.pumpAndSettle();
    await t.tap(find.text('确认选择'));
    await t.pumpAndSettle();
    expect(selected, [haSwitch, haSensor]);
    expect(
      b.calls.where((v) => v.$1 == 'haControl' || v.$1 == 'save'),
      isEmpty,
    );
    await t.pumpWidget(const SizedBox());
    c.dispose();
    b.updates.close();
    expect(t.takeException(), isNull);
  });
  testWidgets('上报选择为独立草稿，撤销和确认保存不隐式开启发布', (t) async {
    size(t);
    final (c, b) = (await t.runAsync(load))!;
    await t.pumpWidget(SkyInfo(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('导航'));
    await t.pumpAndSettle();
    await t.tap(find.text('连接').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(XCheck).first);
    await t.pumpAndSettle();
    expect(c.uploaded, isEmpty);
    expect(b.calls.where((v) => v.$1 == 'save'), isEmpty);
    await t.tap(find.text('撤销修改'));
    await t.pumpAndSettle();
    expect(t.widget<XCheck>(find.byType(XCheck).first).value, isFalse);
    await t.tap(find.byType(XCheck).first);
    await t.pumpAndSettle();
    await t.tap(find.text('保存上报选择'));
    await t.pumpAndSettle();
    expect(c.uploaded, hasLength(1));
    expect(c.publishEnabled, isFalse);
    expect(b.calls.where((v) => v.$1 == 'save'), hasLength(1));
    await t.pumpWidget(const SizedBox());
    c.dispose();
    b.updates.close();
    expect(t.takeException(), isNull);
  });
  testWidgets('E典型数值、混合实体及大负功率浅深色视觉基线', (t) async {
    size(t);
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
    final (c, b) = (await t.runAsync(load))!;
    c.tiles = [
      const TileSpec(
        id: 'thermal',
        title: '热管理',
        kind: WidgetKind.list,
        fields: ['1005/5/1031798840', '1005/5/1320169504', '1006/5/1186988096'],
      ),
      const TileSpec(
        id: 'temperature',
        title: '电池温度',
        kind: WidgetKind.pair,
        fields: ['1014/5/1148190752', '1014/5/1148190736'],
      ),
      const TileSpec(
        id: 'current',
        title: '电池电流',
        kind: WidgetKind.number,
        fields: ['1039/5/677380120'],
      ),
      const TileSpec(
        id: 'power',
        title: '动力电池功率',
        kind: WidgetKind.number,
        fields: ['derived.battery_power'],
      ),
      const TileSpec(
        id: 'ha',
        title: '车辆与 HA',
        kind: WidgetKind.entities,
        fields: [haSensor, haSwitch],
      ),
      const TileSpec(
        id: 'voltage',
        title: '低压电压',
        kind: WidgetKind.number,
        fields: ['1032/7/1128267816'],
        columns: 1,
        rows: 1,
      ),
    ];
    // Fixture values exercise typography and unit layout; they are not a live vehicle sample.
    c.applySamples({
      '1005/5/1031798840': {'value': 1344, 'unit': 'W', 'quality': 'available'},
      '1005/5/1320169504': {'value': 0, 'unit': 'W', 'quality': 'available'},
      '1006/5/1186988096': {
        'value': 1440,
        'unit': 'rpm',
        'quality': 'available',
      },
      '1014/5/1148190752': {'value': 39, 'unit': '°C', 'quality': 'available'},
      '1014/5/1148190736': {'value': 37, 'unit': '°C', 'quality': 'available'},
      '1039/5/677380120': {'value': 0.6, 'unit': 'A', 'quality': 'available'},
      'derived.battery_power': {
        'value': -380.2,
        'unit': 'kW',
        'quality': 'available',
      },
      '1032/7/1128267816': {'value': 13.7, 'unit': 'V', 'quality': 'available'},
      haSwitch: {'value': 'on', 'unit': '', 'quality': 'available'},
    });
    for (final theme in ['light', 'dark']) {
      c.theme = theme;
      await t.pumpWidget(SkyInfo(key: ValueKey(theme), controller: c));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(SkyInfo),
        matchesGoldenFile('goldens/$theme-e-values.png'),
      );
    }
    expect(b.calls.where((v) => v.$1 == 'haControl'), isEmpty);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    b.updates.close();
  });
}

import 'package:skyinfo/ui/design_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/domain/build_channel.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/component_library.dart';
import 'package:skyinfo/ui/editors.dart';
import 'package:skyinfo/ui/icon_picker.dart';
import 'package:skyinfo/ui/unit_picker.dart';
import 'package:skyinfo/ui/history_dialog.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/overlay_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/runtime'),
          (call) async {
            calls.add(call);
            return call.method == 'load'
                ? {'config': {}, 'samples': {}, 'status': {}}
                : call.method == 'history'
                ? {'points': []}
                : {};
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/events'),
          (_) async => null,
        );
  });
  Future<AppController> load() async {
    final c = AppController();
    await c.initialize();
    c.reduceMotion = true;
    return c;
  }

  void size(
    WidgetTester t, [
    Size size = const Size(1600, 900),
    double dpr = 1,
  ]) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = dpr;
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
        debugShowCheckedModeBanner: false,
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

  testWidgets('标题输入可聚焦，键盘打开后预览和保存保留新标题', (t) async {
    size(t, const Size(1920, 1080));
    addTearDown(t.view.resetViewInsets);
    final c = (await t.runAsync(load))!;
    TileSpec? saved;
    await harness(t, c, (context) async {
      saved = await editTile(context, c, existing: componentPreset('低压电压'));
    });
    await t.tap(find.text('内容'));
    await t.pumpAndSettle();
    final input = find.byType(TextField);
    expect(input, findsOneWidget);
    await t.tap(input);
    await t.pump();
    expect(t.testTextInput.isVisible, isTrue);
    t.view.viewInsets = const FakeViewPadding(bottom: 360);
    await t.pumpAndSettle();
    t.testTextInput.enterText('QA20261011');
    await t.pump();
    expect(t.widget<TextField>(input).controller!.text, 'QA20261011');
    expect(find.text('QA20261011'), findsAtLeastNWidgets(2));
    expect(t.takeException(), isNull);
    t.testTextInput.hide();
    t.view.resetViewInsets();
    await t.pumpAndSettle();
    await t.tap(find.text('保存修改'));
    await t.pumpAndSettle();
    expect(saved?.title, 'QA20261011');
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('数据搜索在软键盘重排时保留焦点与输入连接', (t) async {
    size(t, const Size(900, 700));
    final c = (await t.runAsync(load))!;
    await harness(t, c, (context) => chooseFields(context, c, []));
    await t.tap(find.byType(TextField).first);
    await t.pump();
    final before = t.widget<EditableText>(find.byType(EditableText));
    expect(before.focusNode.hasFocus, isTrue);
    await t.enterText(find.byType(TextField).first, 'qa');
    t.view.viewInsets = const FakeViewPadding(bottom: 350);
    await t.pumpAndSettle();
    final after = t.widget<EditableText>(find.byType(EditableText));
    expect(after.focusNode, same(before.focusNode));
    expect(after.focusNode.hasFocus, isTrue);
    expect(after.controller.text, 'qa');
    expect(t.takeException(), isNull);
    t.view.resetViewInsets();
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('分类选中背景和点击墨水属于列表行，滚动不会覆盖标题', (t) async {
    size(t, const Size(1600, 720));
    final c = (await t.runAsync(load))!;
    await harness(
      t,
      c,
      (context) => chooseFields(context, c, [], multiple: true),
    );
    final row = find.widgetWithText(SelectionRow, '全部');
    final material = find
        .descendant(of: row, matching: find.byType(Material))
        .first;
    expect(t.widget<Material>(material).clipBehavior, Clip.hardEdge);
    final list = find.ancestor(of: row, matching: find.byType(ListView));
    final title = t.getRect(find.text('选择数据'));
    await t.drag(list, const Offset(0, -500));
    await t.pumpAndSettle();
    expect(t.getRect(find.text('选择数据')), title);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('组件库展示样式、预设和实体，预览读取历史且取消不保存', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    await t.pumpWidget(SkyInfo(controller: c));
    if (find.byTooltip('编辑布局').evaluate().isNotEmpty) {
      await t.tap(find.byTooltip('编辑布局'));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('添加组件').first);
    await t.pumpAndSettle();
    expect(find.text('使用预设'), findsOneWidget);
    expect(find.text('Home Assistant'), findsOneWidget);
    await t.tap(find.text('使用预设'));
    await t.pumpAndSettle();
    expect(componentPresets.length, 11);
    await t.tap(find.byKey(const ValueKey('library-低压电压')));
    await t.pumpAndSettle();
    expect(find.byType(LiveComponentPreview), findsOneWidget);
    await t.tap(find.text('上次变动时间'));
    await t.pumpAndSettle();
    await t.tap(find.text('上次更新时间'));
    await t.pumpAndSettle();
    await t.tap(find.text('添加到仪表盘'));
    await t.pumpAndSettle();
    expect(c.tiles.single.time, TimeDisplay.updated);
    expect(c.uploaded, isEmpty);
    expect(c.overlays, isEmpty);
    expect(c.tiles.single.icon, isNull);
    if (find.byTooltip('编辑布局').evaluate().isNotEmpty) {
      await t.tap(find.byTooltip('编辑布局'));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('添加组件').first);
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(c.tiles.length, 1);
    expect(c.uploaded, isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('图标可按字段搜索、按分类筛选和关闭', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    String? result;
    await harness(
      t,
      c,
      (context) async => result = await chooseIcon(context, c),
    );
    expect(find.byType(GridView), findsNothing);
    await t.enterText(find.byType(TextField), '发动机水泵');
    await t.pumpAndSettle();
    expect(find.byType(MetricIcon), findsWidgets);
    await t.tap(find.text('不使用图标'));
    await t.pumpAndSettle();
    expect(result, '');
    await t.tap(find.text('打开'));
    await t.pumpAndSettle();
    await t.tap(find.text('电气与仪表').first);
    await t.pumpAndSettle();
    await t.tap(find.text('竖向电池').last);
    await t.pumpAndSettle();
    expect(result, 'tabler-battery-vertical');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('组件只保留铅笔，编辑窗口删除并保存，取消不更改组件', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    c.tiles.add(componentPreset('低压电压'));
    await t.pumpWidget(SkyInfo(controller: c));
    expect(find.text('添加组件'), findsNothing);
    expect(find.byTooltip('编辑组件'), findsNothing);
    await t.tap(find.byTooltip('编辑布局'));
    await t.pumpAndSettle();
    expect(find.text('添加组件'), findsOneWidget);
    expect(find.byTooltip('编辑组件'), findsOneWidget);
    for (final tooltip in ['向前移动', '向后移动', '移除', '调整尺寸']) {
      expect(find.byTooltip(tooltip), findsNothing);
    }
    expect(find.text('删除组件'), findsNothing);
    await t.tap(find.byTooltip('编辑组件'));
    await t.pumpAndSettle();
    expect(find.text('删除组件'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(c.tiles, hasLength(1));
    expect(calls.where((c) => c.method == 'save'), isEmpty);
    await t.tap(find.byTooltip('编辑组件'));
    await t.pumpAndSettle();
    await t.tap(find.text('删除组件'));
    await t.pumpAndSettle();
    expect(c.tiles, hasLength(1));
    await t.tap(find.text('删除').last);
    await t.pumpAndSettle();
    expect(c.tiles, isEmpty);
    final saved = calls.where((c) => c.method == 'save').single;
    expect(saved.arguments['config']['tiles'], isEmpty);
    expect(find.text('删除组件'), findsNothing);
    await t.tap(find.byTooltip('退出编辑布局'));
    await t.pumpAndSettle();
    expect(find.text('添加组件'), findsNothing);
    expect(find.byTooltip('编辑组件'), findsNothing);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('选择字段即接入真实预览，后续读数改变且取消释放草稿需求', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    const high = '1014/5/1148190752';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.skyinfo.vehicle/runtime'),
          (call) async {
            calls.add(call);
            if (call.method == 'previewFields' &&
                (call.arguments['fields'] as List).contains(high)) {
              return {
                'samples': {
                  high: {
                    'value': 38.0,
                    'raw': 68,
                    'quality': 'available',
                    'changedAt': DateTime.now().millisecondsSinceEpoch,
                  },
                },
              };
            }
            return {};
          },
        );
    await harness(
      t,
      c,
      (context) => editTile(context, c, existing: componentPreset('低压电压')),
    );
    await t.tap(find.text('内容'));
    await t.pumpAndSettle();
    await t.tap(find.text('选择数据'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '电池最高温度');
    await t.pumpAndSettle();
    await t.tap(find.text('电池最高温度').last);
    await t.tap(find.text('确认选择'));
    await t.pumpAndSettle();
    expect(find.text('38.0'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    c.applySamples({
      high: {'value': 39.0, 'raw': 69, 'quality': 'available'},
    });
    await t.pump();
    expect(find.text('39.0'), findsOneWidget);
    expect(find.text('38.0'), findsNothing);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(
      (calls.where((c) => c.method == 'previewFields').last.arguments['fields']
          as List),
      isEmpty,
    );
    expect(calls.where((c) => c.method == 'save'), isEmpty);
    expect(c.tiles, isEmpty);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('数据选择保留单选/多选规则，单位与小数位使用独立选择器', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    List<String>? selected;
    await harness(
      t,
      c,
      (context) async => selected = await chooseFields(context, c, []),
    );
    await t.enterText(find.byType(TextField), '电池最高温度');
    await t.pumpAndSettle();
    await t.tap(find.text('电池最高温度').last);
    await t.pumpAndSettle();
    await t.tap(find.text('确认选择'));
    await t.pumpAndSettle();
    expect(selected, ['1014/5/1148190752']);
    UnitChoice? unit;
    await harness(
      t,
      c,
      (context) async =>
          unit = await chooseDisplayUnit(context, reduceMotion: true),
    );
    await t.tap(find.text('无单位'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '原始');
    await t.pumpAndSettle();
    await t.tap(find.text('确认选择'));
    await t.pumpAndSettle();
    expect(unit!.unit, '原始');
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('温度原值历史预设可保存，不同未知口径不能合并', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    expect(
      comparableFields(componentPreset('电池温度历史').fields, c.metrics),
      isTrue,
    );
    expect(
      comparableFields(['1014/5/1148190752', '1005/5/1031798840'], c.metrics),
      isFalse,
    );
    TileSpec? result;
    await harness(t, c, (context) async => result = await editTile(context, c));
    await t.tap(find.text('使用预设'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('library-电池温度历史')),
      400,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('library-电池温度历史')));
    await t.pumpAndSettle();
    await t.tap(find.text('添加到仪表盘'));
    await t.pumpAndSettle();
    expect(result!.kind, WidgetKind.comparison);
    expect(result!.units, isEmpty);
    expect(c.uploaded, isEmpty);
    expect(c.uploaded, isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('实车比例和键盘下配置及悬浮编辑没有溢出，取消不改变位置', (t) async {
    size(t, const Size(1920, 1080), 1.5);
    final c = (await t.runAsync(load))!;
    c.overlayX = 0.3;
    c.overlayY = 0.2;
    await harness(
      t,
      c,
      (context) => editOverlay(
        context,
        c,
        existing: const OverlaySpec(
          id: 'test',
          field: '1014/5/1148190752',
          icon: '',
          unit: '',
          alignment: 'center',
        ),
      ),
    );
    expect(find.byType(OverlayStripPreview), findsOneWidget);
    expect(find.text('模块对齐'), findsOneWidget);
    await t.tap(find.text('居中'));
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect((c.overlayX, c.overlayY), (0.3, 0.2));
    expect(c.overlays, isEmpty);
    await harness(
      t,
      c,
      (context) => editTile(context, c, existing: componentPreset('热管理')),
    );
    t.view.viewInsets = const FakeViewPadding(bottom: 360);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    t.view.resetViewInsets();
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('历史详情在HA未连接时使用本地窗口，不开启上传', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    await harness(
      t,
      c,
      (context) => showHistoryDetails(
        context,
        c,
        componentPreset('低压电压'),
        onEdit: () {},
      ),
    );
    expect(find.text('暂无历史'), findsOneWidget);
    await t.tap(find.text('15 分钟'));
    await t.pumpAndSettle();
    expect(
      calls.where((c) => c.method == 'history').last.arguments['minutes'],
      15,
    );
    expect(c.localHistory, isTrue);
    expect(c.uploaded, isEmpty);
    await t.scrollUntilVisible(
      find.text('历史设置'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await t.tap(find.text('历史设置'));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DesignDialog).last,
        matching: find.text('本地'),
      ),
      findsOneWidget,
    );
    expect(find.text('记录主页数据'), findsOneWidget);
    expect(find.text('连接设置'), findsNothing);
    await t.tap(find.text('关闭').last);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('新获授权HA地址可保存，空令牌不覆盖原凭据', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    c.haUrl = 'http://192.168.10.20:8123';
    await t.pumpWidget(SkyInfo(controller: c));
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('连接').last);
    await t.pumpAndSettle();
    await t.tap(find.text('连接设置'));
    await t.pumpAndSettle();
    final address = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Home Assistant URL',
    );
    await t.enterText(address, 'http://192.168.10.30:8123/');
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(find.text('更换 Home Assistant 服务器？'), findsOneWidget);
    await t.tap(find.text('更换服务器'));
    await t.pumpAndSettle();
    expect(find.text('使用未加密连接？'), findsOneWidget);
    await t.tap(find.text('继续保存'));
    await t.pumpAndSettle();
    expect(c.haUrl, 'http://192.168.10.30:8123/');
    final save = calls.where((c) => c.method == 'save').last;
    expect(save.arguments['config']['haUrl'], c.haUrl);
    expect((save.arguments['secrets'] as Map?)?['haToken'], isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('高级连接及服务表单取消保留原连接与凭据配置', (t) async {
    size(t);
    final c = (await t.runAsync(load))!;
    c.haUrl = 'http://192.168.10.20:8123';
    await t.pumpWidget(SkyInfo(controller: c));
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('设置').last);
    await t.pumpAndSettle();
    await t.tap(find.text('连接'));
    await t.pumpAndSettle();
    expect(find.text('自定义 MQTT 服务器'), findsNothing);
    await t.tap(find.text('高级'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ParameterRow, '自定义 MQTT 服务器'));
    await t.pumpAndSettle();
    expect(find.text('高级 · 自定义 MQTT'), findsOneWidget);
    expect(find.text('连接方式'), findsOneWidget);
    expect(find.text('TLS'), findsOneWidget);
    final secretFields = t
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.obscureText);
    expect(secretFields.single.controller!.text, isEmpty);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(c.connection, 'ha');
    expect(c.haUrl, 'http://192.168.10.20:8123');
    expect(calls.where((c) => c.method == 'save'), isEmpty);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('新增弹窗浅深色视觉基线', (t) async {
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
    final c = (await t.runAsync(load))!;
    for (final dark in [false, true]) {
      for (final name in [
        'library',
        'editor',
        'icons',
        'units',
        'overlay',
        'history',
        'server',
      ]) {
        if (name == 'server') {
          c.theme = dark ? 'dark' : 'light';
          await t.pumpWidget(SkyInfo(controller: c));
          await t.tap(find.byIcon(Icons.menu));
          await t.pumpAndSettle();
          await t.tap(find.text('设置').last);
          await t.pumpAndSettle();
          await t.tap(find.text('连接'));
          await t.pumpAndSettle();
          await t.tap(find.text('高级'));
          await t.pumpAndSettle();
          await t.tap(find.widgetWithText(ParameterRow, '自定义 MQTT 服务器'));
          await t.pumpAndSettle();
        } else {
          await t.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: industrialTheme(dark ? Brightness.dark : Brightness.light),
              home: DesignViewport(
                child: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () {
                        switch (name) {
                          case 'library':
                            choosePreset(context, c);
                          case 'editor':
                            editTile(
                              context,
                              c,
                              existing: componentPreset('热管理'),
                            );
                          case 'icons':
                            chooseIcon(context, c);
                          case 'units':
                            chooseDisplayUnit(context, reduceMotion: true);
                          case 'overlay':
                            editOverlay(
                              context,
                              c,
                              existing: const OverlaySpec(
                                id: 'preview',
                                field: '1032/7/1128267816',
                                icon: 'tabler-battery-automotive',
                                unit: 'V',
                              ),
                            );
                          case 'history':
                            showHistoryDetails(
                              context,
                              c,
                              componentPreset('低压电压'),
                              onEdit: () {},
                            );
                        }
                      },
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
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/${name == 'server' && BuildChannel.isTesting ? 'beta-' : ''}${dark ? 'dark' : 'light'}-$name.png',
          ),
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      }
    }
    c.dispose();
  });
}

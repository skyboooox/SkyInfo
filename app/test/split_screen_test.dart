import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/split_catalog.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/split_screen.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/navigation.dart';
import 'package:skyinfo/ui/split_screen.dart';
import 'package:skyinfo/ui/startup_page_picker.dart';

const mapApp = SplitTarget(packageName: 'app.maps', label: '高德地图');
const musicApp = SplitTarget(packageName: 'app.music', label: '音乐');
const combo = SplitCombo(
  id: 'commute',
  name: '通勤',
  ratio: '7/3',
  left: mapApp,
  right: musicApp,
);

class SplitBridge extends VehicleBridge {
  final calls = <(String, Map<String, dynamic>?)>[];
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic> saved;
  bool failSave = false, failQuery = false, supported = true, removed = false;
  Completer<Map<String, dynamic>>? launch;
  final List<Completer<Map<String, dynamic>>> delayedApps = [];
  final List<Completer<Map<String, dynamic>>> delayedActivities = [];
  Map<String, dynamic> result = {
    'status': 'requested',
    'requestedSides': ['left', 'right'],
  };
  SplitBridge({
    String startupPage = 'split',
    List<SplitCombo> combos = const [combo],
  }) : saved = {
         'startupPage': startupPage,
         'splitCombos': combos.map((e) => e.toJson()).toList(),
       };
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
        'config': saved,
        'status': {'adb': 'connected'},
        'samples': {},
      };
    }
    if (method == 'saveSplitPreferences') {
      if (failSave) throw PlatformException(code: 'disk_full');
      saved = {...saved, ...args!};
      return {'config': saved};
    }
    if (method == 'splitApps' && delayedApps.isNotEmpty) {
      return delayedApps.removeAt(0).future;
    }
    if (method == 'splitActivities' && delayedActivities.isNotEmpty) {
      return delayedActivities.removeAt(0).future;
    }
    if (method == 'splitApps') {
      return failQuery
          ? {'apps': [], 'reason': 'query_failed'}
          : {
              'supported': supported,
              'apps': [
                if (!removed)
                  {
                    'packageName': mapApp.packageName,
                    'label': mapApp.label,
                    'defaultActivity': 'Main',
                  },
                {
                  'packageName': musicApp.packageName,
                  'label': musicApp.label,
                  'defaultActivity': 'Main',
                },
              ],
            };
    }
    if (method == 'splitActivities') {
      return {
        'activities': [
          for (final entry in ['Main', 'Detail', 'Private'])
            {
              'packageName': args!['packageName'],
              'activityName': entry,
              'label': entry == 'Main'
                  ? '主界面'
                  : entry == 'Detail'
                  ? '音乐库'
                  : '内部入口',
              'isDefault': entry == 'Main',
              'available': entry != 'Private',
              'enabled': true,
              'exported': entry != 'Private',
              if (entry == 'Private') 'reason': 'not_exported',
            },
        ],
      };
    }
    if (method == 'launchSplit') return launch?.future ?? result;
    return {};
  }

  int count(String method) => calls.where((e) => e.$1 == method).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  Future<AppController> show(
    WidgetTester t,
    SplitBridge bridge, {
    Size size = const Size(1280, 600),
    double scale = 1,
    String theme = 'light',
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = (await t.runAsync(() async {
      final c = AppController(bridge: bridge);
      await c.initialize();
      c.reduceMotion = true;
      c.theme = theme;
      c.splitCompatibilityAcknowledged = true;
      return c;
    }))!;
    await t.pumpWidget(SkyInfo(controller: c));
    if (scale != 1) {
      final app = t.widget<MaterialApp>(find.byType(MaterialApp));
      await t.pumpWidget(
        ListenableBuilder(
          listenable: c,
          builder: (_, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: industrialTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: app.home,
          ),
        ),
      );
    }
    await t.pumpAndSettle();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await bridge.updates.close();
    });
    return c;
  }

  Future<void> fonts(WidgetTester t) async {
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
  }

  Future<void> selectApp(WidgetTester t, String side, String app) async {
    await t.tap(
      find.ancestor(
        of: find.text(side).first,
        matching: find.byType(SplitAppButton),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(SelectionRow, app));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(IndustrialButton, '选择'));
    await t.pumpAndSettle();
  }

  test(
    'drafts preserve independent selections, named identity and advanced reset boundaries',
    () {
      final original = SplitCombo(
        id: 'one',
        name: '同名',
        ratio: '3/7',
        left: mapApp.withActivity('Detail'),
        right: musicApp.withActivity('Main'),
        advanced: true,
      );
      final draft = SplitDraft.fromCombo(original),
          quick = SplitDraft(left: musicApp, right: mapApp);
      draft.select(true, musicApp);
      expect(draft.left!.activityName, isNull);
      expect(draft.right!.activityName, 'Main');
      expect(original.left.activityName, 'Detail');
      expect(quick.left!.packageName, 'app.music');
      draft.swap();
      expect(draft.left!.activityName, 'Main');
      draft.setAdvanced(false);
      expect(draft.left!.activityName, isNull);
      expect(draft.right!.activityName, isNull);
      expect(draft.snapshot('ignored').id, 'one');
      expect(
        SplitCombo.fromJson(original.toJson()).left.activityName,
        'Detail',
      );
      expect(
        SplitDraft(
          name: '同名',
          left: mapApp,
          right: musicApp,
        ).snapshot('two').id,
        'two',
      );
    },
  );
  test(
    'split preferences persist atomically, preserve export, and launch prevents repetition',
    () async {
      final b = SplitBridge();
      final controller = AppController(bridge: b);
      controller.restore(b.saved);
      b.failSave = true;
      expect(
        await controller.saveSplitPreferences(page: 'settings', combos: []),
        isFalse,
      );
      expect(controller.startupPage, 'split');
      expect(controller.splitCombos.single.id, 'commute');
      b.failSave = false;
      expect(await controller.saveSplitPreferences(page: 'settings'), isTrue);
      expect(jsonDecode(controller.exportConfig())['startupPage'], 'settings');
      expect(
        jsonDecode(controller.exportConfig())['splitCombos'][0]['id'],
        'commute',
      );
      b.launch = Completer();
      final first = controller.launchSplit(SplitDraft.fromCombo(combo));
      expect(
        (await controller.launchSplit(SplitDraft.fromCombo(combo)))['status'],
        'busy',
      );
      expect(b.count('launchSplit'), 1);
      b.launch!.complete({
        'status': 'partial',
        'requestedSides': ['left'],
        'side': 'right',
        'reason': 'permission_denied',
      });
      expect((await first)['status'], 'partial');
      expect(controller.splitLaunching, isFalse);
      controller.dispose();
      await b.updates.close();
    },
  );
  test(
    'catalog distinguishes unavailable packages and protected activities',
    () async {
      final b = SplitBridge();
      final live = SplitCatalog(b);
      await live.refresh([mapApp.withActivity('Main'), musicApp]);
      expect(live.invalid(mapApp), isNull);
      expect(live.invalid(mapApp.withActivity('Private')), 'not_exported');
      expect(
        live.invalid(mapApp.withActivity('Removed')),
        'activity_unavailable',
      );
      b.removed = true;
      await live.refresh([mapApp]);
      expect(live.invalid(mapApp), 'package_unavailable');
      live.dispose();
      await b.updates.close();
    },
  );
  test(
    'catalog ignores older refreshes and picker responses across catalog replacement',
    () async {
      final b = SplitBridge();
      final catalog = SplitCatalog(b);
      final oldApps = Completer<Map<String, dynamic>>(),
          newApps = Completer<Map<String, dynamic>>();
      b.delayedApps.addAll([oldApps, newApps]);
      final oldRefresh = catalog.refresh([mapApp.withActivity('Detail')]);
      final newRefresh = catalog.refresh([]);
      oldApps.complete({'apps': [], 'supported': false});
      await oldRefresh;
      expect(catalog.loading, isTrue);
      expect(b.count('splitActivities'), 0);
      newApps.complete({
        'apps': [
          {
            'packageName': 'app.maps',
            'label': '新版地图',
            'defaultActivity': 'Main',
          },
        ],
      });
      await newRefresh;
      expect(catalog.apps.single.label, '新版地图');
      final oldActivities = Completer<Map<String, dynamic>>();
      b.delayedActivities.add(oldActivities);
      final picker = catalog.loadActivities('app.maps');
      await catalog.refresh([]);
      oldActivities.complete({'activities': []});
      await picker;
      expect(catalog.activities, isEmpty);
      expect(catalog.invalid(mapApp), isNull);
      catalog.dispose();
      await b.updates.close();
    },
  );
  for (final page in startupPages) {
    testWidgets(
      'new Home adopts $page while foreground resume preserves current page',
      (t) async {
        final b = SplitBridge(startupPage: page);
        final c = await show(t, b);
        final expected = pageTitles[startupPageIndices[page]!];
        expect(
          b.calls.firstWhere((e) => e.$1 == 'visibility').$2!['information'],
          page == 'information',
        );
        expect(
          find.widgetWithText(NavigationHeading, expected),
          findsOneWidget,
        );
        c.startupPage = page == 'information' ? 'settings' : 'information';
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          t.binding.handleAppLifecycleStateChanged(state);
        }
        await t.pumpAndSettle();
        expect(
          find.widgetWithText(NavigationHeading, expected),
          findsOneWidget,
        );
        expect(b.count('launchSplit'), 0);
      },
    );
  }
  testWidgets(
    'quick selection, searching and cancellation never save or launch; explicit launch locks',
    (t) async {
      final b = SplitBridge(), c = await show(t, b);
      await selectApp(t, '左侧应用', '高德地图');
      await t.tap(
        find.ancestor(
          of: find.text('右侧应用').first,
          matching: find.byType(SplitAppButton),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '没有的应用');
      await t.pump();
      expect(find.text('没有匹配结果'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(c.splitQuickDraft.right, isNull);
      expect(b.count('saveSplitPreferences'), 0);
      expect(b.count('launchSplit'), 0);
      await selectApp(t, '右侧应用', '音乐');
      b.launch = Completer();
      await t.tap(find.widgetWithText(IndustrialButton, '启动分屏'));
      await t.pump();
      expect(b.count('launchSplit'), 1);
      expect(
        t
            .widget<IndustrialButton>(
              find.widgetWithText(IndustrialButton, '正在发送…'),
            )
            .onPressed,
        isNull,
      );
      b.launch!.complete({'status': 'requested'});
      await t.pumpAndSettle();
      expect(find.text('已发送启动请求，请检查实际左右布局。'), findsOneWidget);
      await t.tap(find.byIcon(Icons.menu));
      await t.pumpAndSettle();
      await t.tap(find.text('信息').last);
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.menu));
      await t.pumpAndSettle();
      await t.tap(find.text('自定义分屏').last);
      await t.pumpAndSettle();
      expect(c.splitQuickDraft.left!.packageName, 'app.maps');
      expect(b.count('launchSplit'), 1);
    },
  );
  testWidgets(
    'editor cancel preserves saved combo; failed save retains draft and retry updates identity',
    (t) async {
      final b = SplitBridge(), c = await show(t, b);
      await t.tap(find.byTooltip('编辑组合：通勤'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '周末');
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(IndustrialButton, '放弃更改'));
      await t.pumpAndSettle();
      expect(c.splitCombos.single.name, '通勤');
      expect(b.count('saveSplitPreferences'), 0);
      await t.tap(find.byTooltip('编辑组合：通勤'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '周末');
      b.failSave = true;
      await t.tap(find.text('保存组合'));
      await t.pumpAndSettle();
      expect(find.text('保存失败，已保留当前输入，请重试。'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        '周末',
      );
      expect(c.splitCombos.single.name, '通勤');
      b.failSave = false;
      await t.tap(find.text('保存组合'));
      await t.pumpAndSettle();
      expect(c.splitCombos.single.id, 'commute');
      expect(c.splitCombos.single.name, '周末');
      expect(b.count('launchSplit'), 0);
    },
  );
  testWidgets(
    'advanced Activity selection is read-only and closing advanced resets both sides',
    (t) async {
      final b = SplitBridge(), c = await show(t, b);
      await t.tap(find.byTooltip('编辑组合：通勤'));
      await t.pumpAndSettle();
      await t.tap(find.byType(IndustrialSwitch));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(IndustrialButton, '默认启动入口').first);
      await t.pumpAndSettle();
      expect(find.text('启动入口未向外部应用开放'), findsOneWidget);
      expect(
        t
            .widget<InkWell>(
              find
                  .ancestor(
                    of: find.text('内部入口'),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .onTap,
        isNull,
      );
      await t.tap(find.text('音乐库'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(IndustrialButton, '选择'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(IndustrialButton, 'Detail'), findsOneWidget);
      await t.tap(find.widgetWithText(IndustrialButton, '默认启动入口'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消').last);
      await t.pumpAndSettle();
      expect(find.widgetWithText(IndustrialButton, 'Detail'), findsOneWidget);
      await t.tap(find.widgetWithText(IndustrialButton, '默认启动入口'));
      await t.pumpAndSettle();
      await t.tap(find.text('音乐库'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(IndustrialButton, '选择'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(IndustrialButton, 'Detail'), findsNWidgets(2));
      await t.tap(find.byType(IndustrialSwitch));
      await t.pumpAndSettle();
      await t.tap(find.text('保存组合'));
      await t.pumpAndSettle();
      expect(c.splitCombos.single.advanced, isFalse);
      expect(c.splitCombos.single.left.activityName, isNull);
      expect(c.splitCombos.single.right.activityName, isNull);
      expect(b.count('launchSplit'), 0);
    },
  );
  testWidgets(
    'deleted application is retained with a repair action and disabled launch',
    (t) async {
      final b = SplitBridge()..removed = true;
      final c = await show(t, b);
      expect(find.textContaining('左侧：应用已卸载或当前用户不可见'), findsOneWidget);
      expect(
        t
            .widget<IndustrialButton>(
              find.widgetWithText(IndustrialButton, '启动'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.byTooltip('编辑组合：通勤'));
      await t.pumpAndSettle();
      expect(find.byType(SplitComboEditor), findsOneWidget);
      expect(c.splitCombos.single.name, '通勤');
      expect(b.count('launchSplit'), 0);
    },
  );
  testWidgets(
    'partial launch explains the requested side without claiming completion',
    (t) async {
      final b = SplitBridge()
        ..result = {
          'status': 'partial',
          'requestedSides': ['left'],
          'side': 'right',
          'reason': 'permission_denied',
        };
      await show(t, b);
      await t.tap(find.widgetWithText(IndustrialButton, '启动'));
      await t.pumpAndSettle();
      expect(
        find.text('左侧已发送启动请求，另一侧未发送：当前应用缺少调用权限。可重试或编辑组合。'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'right primary request is reported when the later left request fails',
    (t) async {
      final b = SplitBridge()
        ..result = {
          'status': 'partial',
          'requestedSides': ['right'],
          'side': 'left',
          'reason': 'launch_rejected',
        };
      await show(t, b);
      await t.tap(find.widgetWithText(IndustrialButton, '启动'));
      await t.pumpAndSettle();
      expect(
        find.text('右侧已发送启动请求，另一侧未发送：系统拒绝启动请求。可重试或编辑组合。'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'direction readback failure preserves the two sent requests in feedback',
    (t) async {
      final b = SplitBridge()
        ..result = {
          'status': 'requested',
          'requestedSides': ['left', 'right'],
          'layoutReason': 'direction_unconfirmed',
          'directionVerified': false,
          'layoutStatus': 'unverified',
        };
      await show(t, b);
      await t.tap(find.widgetWithText(IndustrialButton, '启动'));
      await t.pumpAndSettle();
      expect(
        find.text('两侧已发送启动请求，系统方向未确认：系统方向未按所选比例更新。请检查实际布局后重试，或使用系统分屏调整。'),
        findsOneWidget,
      );
      expect(find.textContaining('另一侧未发送'), findsNothing);
    },
  );
  testWidgets(
    'startup picker saves immediately and failed change preserves the saved selection',
    (t) async {
      final b = SplitBridge(), c = await show(t, b);
      final context = t.element(find.byType(SplitScreenPage));
      showStartupPagePicker(context, c);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(SelectionRow, '设置'));
      await t.pumpAndSettle();
      expect(c.startupPage, 'settings');
      b.failSave = true;
      await t.tap(find.widgetWithText(SelectionRow, '信息'));
      await t.pumpAndSettle();
      expect(c.startupPage, 'settings');
      expect(find.text('保存失败，已保留当前输入，请重试。'), findsOneWidget);
      await t.tap(find.text('关闭').last);
      await t.pumpAndSettle();
      expect(find.byType(SplitScreenPage), findsOneWidget);
    },
  );
  for (final size in [const Size(360, 780), const Size(1280, 600)]) {
    testWidgets('split pages accommodate $size at 2x text and keyboard', (
      t,
    ) async {
      await show(t, SplitBridge(), size: size, scale: 2);
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.byTooltip('编辑组合：通勤'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SplitScreenPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('编辑组合：通勤'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.byType(TextField),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SplitComboEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(TextField).first);
      t.view.viewInsets = const FakeViewPadding(bottom: 200);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      t.view.resetViewInsets();
    });
  }
  testWidgets(
    'application loading, empty inventory and query failure keep actions safe',
    (t) async {
      final b = SplitBridge();
      final apps = Completer<Map<String, dynamic>>();
      b.delayedApps.add(apps);
      // Complete before pumping the page so the isolated empty-inventory state is deterministic.
      apps.complete({'apps': [], 'supported': true});
      await show(t, b);
      await t.tap(
        find.ancestor(
          of: find.text('左侧应用').first,
          matching: find.byType(SplitAppButton),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('当前用户没有可见的可启动应用'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      b.failQuery = true;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(state);
      }
      await t.pumpAndSettle();
      expect(find.text('应用查询失败，请检查系统权限后重试。'), findsOneWidget);
      expect(b.count('launchSplit'), 0);
    },
  );
  testWidgets(
    'first explicit launch can cancel compatibility confirmation without sending a request',
    (t) async {
      final b = SplitBridge(), c = await show(t, b);
      c.splitCompatibilityAcknowledged = false;
      await t.tap(find.widgetWithText(IndustrialButton, '启动'));
      await t.pumpAndSettle();
      expect(find.text('分屏兼容提示'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(b.count('launchSplit'), 0);
      expect(c.splitCompatibilityAcknowledged, isFalse);
    },
  );
  testWidgets(
    'delete requires confirmation and only removes the selected stable ID',
    (t) async {
      final b = SplitBridge(
        combos: [
          combo,
          const SplitCombo(
            id: 'duplicate-name',
            name: '通勤',
            ratio: '3/7',
            left: musicApp,
            right: mapApp,
          ),
        ],
      );
      final c = await show(t, b);
      await t.tap(find.byTooltip('编辑组合：通勤').first);
      await t.pumpAndSettle();
      await t.tap(find.text('删除组合'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(IndustrialButton, '取消').last);
      await t.pumpAndSettle();
      expect(c.splitCombos, hasLength(2));
      await t.tap(find.text('删除组合'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(IndustrialButton, '删除'));
      await t.pumpAndSettle();
      expect(c.splitCombos.single.id, 'duplicate-name');
      expect(b.count('launchSplit'), 0);
    },
  );
  testWidgets('narrow editor visual reference', (t) async {
    await fonts(t);
    await show(t, SplitBridge(), size: const Size(360, 780), scale: 2);
    await t.scrollUntilVisible(
      find.byTooltip('编辑组合：通勤'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SplitScreenPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('编辑组合：通勤'));
    await t.pumpAndSettle();
    expect(find.text('30%'), findsNothing);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/light-split-editor-narrow.png'),
    );
  });
  for (final theme in ['light', 'dark']) {
    testWidgets('$theme split screen and editor visual reference', (t) async {
      await fonts(t);
      final b = SplitBridge(
        combos: [
          combo,
          const SplitCombo(
            id: 'info',
            name: '信息与音乐',
            ratio: '3/7',
            left: musicApp,
            right: mapApp,
          ),
        ],
      );
      final c = await show(t, b, theme: theme);
      c.splitQuickDraft.select(true, mapApp);
      c.splitQuickDraft.select(false, musicApp);
      await c.saveSplitPreferences(page: 'split');
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$theme-split-screen.png'),
      );
      showStartupPagePicker(t.element(find.byType(SplitScreenPage)), c);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$theme-startup-page.png'),
      );
      await t.tap(find.text('关闭').last);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('编辑组合：通勤'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$theme-split-editor.png'),
      );
    });
  }
}

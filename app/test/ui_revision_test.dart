import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/ha_control_status.dart';
import 'package:skyinfo/ui/history_chart.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/live_field_reading.dart';
import 'package:skyinfo/ui/shell/home.dart';

class PreviewBridge extends VehicleBridge {
  final demands = <Set<String>>[];
  final methods = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    methods.add(method);
    if (method == 'previewFields') {
      demands.add(Set<String>.from(args!['fields']));
    }
    return {};
  }
}

Metric metric(int index) => Metric.fromJson({
  'id': 'field-$index',
  'name': '数值$index',
  'category': '测试',
  'icon': '',
  'entityKey': 'field-$index',
  'displayAllowed': true,
  'unit': 'mV',
  'encoding': 'mV',
});

Future<void> loadFonts(WidgetTester t) async {
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

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.dart_tool/test-reports/ui-revision/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final variation in [
    (320.0, Brightness.light),
    (1280.0, Brightness.light),
    (320.0, Brightness.dark),
    (1280.0, Brightness.dark),
  ]) {
    final (width, theme) = variation;
    testWidgets(
      'connection preview uses real values and visible leases at $width ${theme.name}',
      (t) async {
        await loadFonts(t);
        final boundary = GlobalKey();
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final bridge = PreviewBridge();
        final c = AppController(bridge: bridge)
          ..startupPage = 'connection'
          ..reduceMotion = true
          ..metrics = List.generate(80, metric);
        c.reading('field-0');
        c.applySamples({
          'field-0': {'value': -1234567.8, 'quality': 'available'},
        });
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: industrialTheme(theme),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(1.3),
                ),
                child: Home(controller: c),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('-1234567.8 mV'), findsOneWidget);
        await capture(t, boundary, 'connection-${theme.name}-${width.toInt()}');
        expect(bridge.demands.last, contains('field-0'));
        expect(bridge.demands.last.length, lessThan(20));
        expect(bridge.demands.last, isNot(contains('field-79')));
        expect(find.byType(LiveFieldReading).evaluate().length, lessThan(20));
        c.applySamples({
          'field-0': {'value': 42.5, 'quality': 'available'},
        });
        await t.pump();
        expect(find.text('42.5 mV'), findsOneWidget);
        c.applySamples({
          'field-0': {'value': 0, 'quality': 'available'},
        });
        await t.pump();
        expect(find.text('0 mV'), findsOneWidget);
        c.applySamples({
          'field-0': {'quality': 'unavailable'},
        });
        await t.pump();
        expect(find.text('0 mV'), findsNothing);
        expect(find.text('— mV'), findsWidgets);
        final list = find
            .ancestor(
              of: find.byType(LiveFieldReading).first,
              matching: find.byType(ListView),
            )
            .first;
        await t.drag(list, const Offset(0, -700));
        await t.pumpAndSettle();
        expect(bridge.demands.last, isNot(contains('field-0')));
        expect(c.uploaded, isEmpty);
        expect(
          bridge.methods.where(
            (m) => ['save', 'command', 'control'].contains(m),
          ),
          isEmpty,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(bridge.demands.last, isEmpty);
        c.dispose();
      },
    );
  }

  testWidgets('HA status follows subscription state and preserves unknown', (
    t,
  ) async {
    final c = AppController(bridge: PreviewBridge())..haControlEnabled = true;
    Future<void> show(Map<String, dynamic> status) async {
      c.status = status;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HaControlStatus(key: UniqueKey(), controller: c),
          ),
        ),
      );
    }

    await show({'connection': '已连接'});
    expect(find.text('远控状态未知'), findsOneWidget);
    for (final entry in {
      'subscribing': '正在订阅远控',
      'retrying': '正在恢复远控',
      'blocked': '远控订阅被拒绝',
      'disconnected': '远控未连接',
      'ready': '远控已就绪',
      'disabled': '远控已关闭',
    }.entries) {
      await show({'haControlState': entry.key});
      expect(find.text(entry.value), findsOneWidget);
    }
    await show({'haControlState': 'blocked', 'haControlError': 'acl_denied'});
    expect(find.text('远控订阅被拒绝\n订阅错误：acl_denied'), findsOneWidget);
    c.haControlEnabled = false;
    await show({'haControlState': 'ready', 'haControlError': 'old_error'});
    expect(find.text('远控已关闭'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'chart selection expires two seconds after last touch and cleans up',
    (t) async {
      await loadFonts(t);
      final boundary = GlobalKey();
      final end = DateTime(2026, 11, 11, 10);
      final points = List.generate(
        6001,
        (i) => HistoryPoint(
          end.subtract(Duration(milliseconds: 60000 - i * 10)),
          i.toDouble(),
        ),
      );
      Future<void> chart() async {
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: industrialTheme(Brightness.light),
              home: Scaffold(
                body: Dialog(
                  alignment: Alignment.topLeft,
                  insetPadding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 600,
                    height: 300,
                    child: Column(
                      children: [
                        const Text('历史详情'),
                        Expanded(
                          child: HistoryChart(
                            series: [points],
                            minutes: 1,
                            windowEnd: end,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await chart();
      await t.tapAt(const Offset(300, 180));
      await t.pump();
      expect(find.textContaining(RegExp('均值|最近真实值')), findsOneWidget);
      await capture(t, boundary, 'chart-selected');
      await t.pump(const Duration(milliseconds: 1999));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsNothing);
      await capture(t, boundary, 'chart-hidden');
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('历史详情'), findsOneWidget);
      await t.tapAt(const Offset(300, 180));
      await t.pump(const Duration(milliseconds: 1500));
      await t.tapAt(const Offset(330, 180));
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsNothing);
      final gesture = await t.startGesture(const Offset(250, 180));
      await gesture.moveTo(const Offset(310, 180));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsOneWidget);
      await gesture.up();
      await t.pump(const Duration(milliseconds: 1999));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsNothing);
      final interrupted = await t.startGesture(const Offset(250, 180));
      await interrupted.moveTo(const Offset(310, 180));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(find.textContaining(RegExp('均值|最近真实值')), findsNothing);
      await interrupted.cancel();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.tapAt(const Offset(300, 180));
      await t.pump();
      expect(find.textContaining(RegExp('均值|最近真实值')), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.textContaining(RegExp('均值|最近真实值')), findsNothing);
      await t.tapAt(const Offset(300, 180));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/ui/network_adb_settings.dart';
import 'package:skyinfo/ui/industrial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.skyinfo.vehicle/runtime');
  final calls = <MethodCall>[];
  var failSave = false;
  setUp(() {
    calls.clear();
    failSave = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'save') {
            if (failSave) throw PlatformException(code: 'save_failed');
            return {'config': (call.arguments as Map)['config']};
          }
          if (call.method == 'pairAdb') return {'result': 'paired'};
          return {
            'status': {'adb': 'connecting'},
          };
        });
  });
  Future<void> show(
    WidgetTester tester,
    AppController controller, {
    Size size = const Size(1600, 900),
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = size;
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
    await tester.pumpWidget(
      MaterialApp(
        theme: industrialTheme(brightness),
        home: NetworkAdbSettings(
          controller: controller,
          onNavigate: (_) {},
          onTab: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'draft does not connect or save until confirmed, then persists and reconnects',
    (tester) async {
      final c = AppController();
      await show(tester, c);
      expect(calls, isEmpty);
      expect(find.text('Shizuku'), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), 'localhost');
      await tester.enterText(find.byType(TextField).at(1), '5566');
      expect(c.adbHost, '127.0.0.1');
      expect(calls, isEmpty);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(c.adbHost, 'localhost');
      expect(c.adbPort, 5566);
      expect(calls.map((call) => call.method), ['save']);
      // Enable is still a draft until the next save.
      final toggles = find
          .byType(Semantics)
          .evaluate()
          .where((e) => (e.widget as Semantics).properties.toggled != null)
          .toList();
      await tester.tap(find.byWidget(toggles.first.widget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      expect(c.adbEnabled, isTrue);
      expect(calls.last.method, 'reconnectAdb');
    },
  );
  testWidgets(
    'bad endpoint cannot save; persistence failure rolls back configuration',
    (tester) async {
      final c = AppController();
      await show(tester, c);
      await tester.enterText(find.byType(TextField).at(0), 'http://host');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('请输入有效地址和端口'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'localhost');
      failSave = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(c.adbHost, '127.0.0.1');
      expect(calls.map((call) => call.method), ['save']);
    },
  );
  testWidgets(
    'pairing uses a separate port and transient code without changing saved preferences',
    (tester) async {
      final c = AppController();
      await show(tester, c);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('无线配对').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), '37123');
      await tester.enterText(find.byType(TextField).at(3), '012345');
      await tester.ensureVisible(find.text('配对'));
      await tester.tap(find.text('配对'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'pairAdb');
      expect((calls.single.arguments as Map)['port'], 37123);
      expect(c.adbMode, 'tcp');
      expect(c.exportConfig(), isNot(contains('012345')));
      expect(
        (tester.widget<TextField>(
          find.byType(TextField).at(3),
        )).controller!.text,
        isEmpty,
      );
      expect(find.text('配对成功，请使用连接端口连接'), findsOneWidget);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('$brightness network ADB page golden', (tester) async {
      await show(tester, AppController(), brightness: brightness);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(NetworkAdbSettings),
        matchesGoldenFile('goldens/${brightness.name}-network-adb.png'),
      );
    });
  }
  testWidgets('narrow screen and enlarged text remain usable', (tester) async {
    final c = AppController();
    await show(tester, c, size: const Size(800, 600));
    await tester.ensureVisible(find.text('保存'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'save');
  });
}

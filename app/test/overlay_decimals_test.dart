import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/overlay_editor.dart';
import 'package:skyinfo/ui/overlay_preview.dart';

class DecimalBridge extends VehicleBridge {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    return ['save', 'importConfig'].contains(method)
        ? {'config': args!['config']}
        : {};
  }
}

Map<String, dynamic> module(String id, [int? digits]) => {
  'id': id,
  'field': 'voltage',
  'icon': '',
  'unit': 'V',
  'alignment': 'center',
  'digits': ?digits,
};
AppController controller() => AppController(bridge: DecimalBridge())
  ..metrics = [
    Metric.fromJson({
      'id': 'voltage',
      'name': '电压',
      'category': '测试',
      'icon': '',
      'entityKey': 'voltage',
      'displayAllowed': true,
      'unit': 'V',
      'encoding': 'V',
    }),
  ]
  ..reading('voltage')
  ..applySamples({
    'voltage': {'value': 13.67, 'quality': 'available'},
  });

Future<void> openEditor(
  WidgetTester t,
  AppController c,
  OverlaySpec? existing,
  void Function(OverlaySpec?) result, {
  GlobalKey? boundary,
  Brightness theme = Brightness.light,
}) async {
  await t.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: industrialTheme(theme),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result(await editOverlay(context, c, existing: existing)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

Future<void> checkbox(WidgetTester t) async {
  await t.scrollUntilVisible(
    find.text('显示小数'),
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await t.pumpAndSettle();
}

void main() {
  for (final theme in Brightness.values) {
    testWidgets(
      'new module starts with integer preview and saves zero digits ${theme.name}',
      (t) async {
        t.view.physicalSize = const Size(1280, 600);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
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
        final boundary = GlobalKey();
        final c = controller();
        OverlaySpec? saved;
        await openEditor(
          t,
          c,
          null,
          (value) => saved = value,
          boundary: boundary,
          theme: theme,
        );
        await t.tap(find.text('电压'));
        await t.pump();
        await t.tap(find.text('确认选择'));
        await t.pumpAndSettle();
        expect(find.text('14'), findsOneWidget);
        await checkbox(t);
        expect(t.widget<XCheck>(find.byType(XCheck)).value, isFalse);
        expect(
          t
              .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
              .onChanged,
          isNull,
        );
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.dart_tool/test-reports/ui-revision/new-overlay-${theme.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await t.tap(find.text('保存'));
        await t.pumpAndSettle();
        expect(saved!.digits, 0);
        expect(
          const OverlaySpec(
            id: 'new',
            field: 'voltage',
            icon: '',
            unit: 'V',
          ).digits,
          0,
        );
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.pump();
      },
    );
  }
  for (final oldDigits in [null, 0, 3]) {
    testWidgets('legacy precision $oldDigits stays compatible when saved', (
      t,
    ) async {
      t.view.physicalSize = const Size(1280, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = controller();
      final original = OverlaySpec.fromJson(module('a', oldDigits));
      OverlaySpec? saved;
      await openEditor(t, c, original, (value) => saved = value);
      await checkbox(t);
      expect(t.widget<XCheck>(find.byType(XCheck)).value, oldDigits != 0);
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(saved!.digits, oldDigits ?? 1);
      c.overlays = [saved!, OverlaySpec.fromJson(module('b', 4))];
      expect(await c.save(), isTrue);
      expect(c.overlays.map((m) => m.digits), [oldDigits ?? 1, 4]);
      final exported = c.exportConfig();
      expect(await c.importConfig(exported), isTrue);
      expect(c.overlays.map((m) => m.digits), [oldDigits ?? 1, 4]);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.pump();
    });
  }
  testWidgets(
    'checkbox previews integer rounding and retains draft precision on re-enable',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = controller();
      final original = OverlaySpec.fromJson(module('a', 3));
      OverlaySpec? saved;
      await openEditor(t, c, original, (value) => saved = value);
      expect(find.text('13.670'), findsOneWidget);
      await checkbox(t);
      await t.tap(find.byType(XCheck));
      await t.pumpAndSettle();
      expect(find.text('14'), findsOneWidget);
      expect(
        t
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .onChanged,
        isNull,
      );
      await t.tap(find.byType(XCheck));
      await t.pumpAndSettle();
      expect(find.text('13.670'), findsOneWidget);
      await t.tap(find.byType(XCheck));
      await t.pumpAndSettle();
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(saved!.digits, 0);
      expect(original.digits, 3);
      await openEditor(
        t,
        c,
        OverlaySpec.fromJson(saved!.toJson()),
        (value) => saved = value,
      );
      await checkbox(t);
      await t.tap(find.byType(XCheck));
      await t.pumpAndSettle();
      expect(find.text('13.7'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(saved, isNull);
      expect(
        (c.bridge as DecimalBridge).calls.where(
          (x) => ['save', 'importConfig'].contains(x),
        ),
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.pump();
    },
  );
  testWidgets(
    'module precision is independent and state text and units are preserved',
    (t) async {
      final c = controller()
        ..overlays = [
          OverlaySpec.fromJson(module('a', 0)),
          OverlaySpec.fromJson(module('b', 2)),
        ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayStripPreview(controller: c, modules: c.overlays),
          ),
        ),
      );
      expect(find.text('14'), findsOneWidget);
      expect(find.text('13.67'), findsOneWidget);
      expect(find.text('V'), findsNWidgets(2));
      c.applySamples({
        'voltage': {'value': 39, 'quality': 'available'},
      });
      await t.pump();
      expect(find.text('39'), findsOneWidget);
      expect(find.text('39.00'), findsOneWidget);
      c.applySamples({
        'voltage': {'value': -13.67, 'quality': 'available'},
      });
      await t.pump();
      expect(find.text('-14'), findsOneWidget);
      expect(find.text('-13.67'), findsOneWidget);
      c.applySamples({
        'voltage': {'value': '运行', 'quality': 'available'},
      });
      await t.pump();
      expect(find.text('运行'), findsNWidgets(2));
      expect(find.text('V'), findsNWidgets(2));
      c.applySamples({
        'voltage': {'value': 2, 'stateLabel': '开启', 'quality': 'available'},
      });
      await t.pump();
      expect(find.text('开启'), findsNWidgets(2));
      c.applySamples({
        'voltage': {'quality': 'unavailable'},
      });
      await t.pump();
      expect(find.text('—'), findsNWidgets(2));
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.pump();
    },
  );
  for (final theme in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('module checkbox layout ${theme.name} $width', (t) async {
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
        t.view.physicalSize = Size(width, width == 320 ? 800 : 600);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = controller();
        final key = GlobalKey();
        await openEditor(
          t,
          c,
          OverlaySpec.fromJson(module('a', 2)),
          (_) {},
          boundary: key,
          theme: theme,
        );
        await checkbox(t);
        expect(find.byType(XCheck), findsOneWidget);
        expect(find.byType(IndustrialSwitch), findsNothing);
        expect(t.takeException(), isNull);
        final name =
            '${theme.name}-overlay-decimals${width == 320 ? '-narrow' : ''}';
        await expectLater(
          find.byKey(key),
          matchesGoldenFile('goldens/$name.png'),
        );
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = File('.dart_tool/test-reports/overlay/$name.png');
          await out.parent.create(recursive: true);
          await out.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        if (width == 1280) {
          await t.tap(find.byType(XCheck));
          await t.pumpAndSettle();
          expect(find.text('14'), findsOneWidget);
          await t.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '.dart_tool/test-reports/overlay/$name-off.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.pump();
      });
    }
  }
}

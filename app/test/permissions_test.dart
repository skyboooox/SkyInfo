import 'package:skyinfo/ui/design_dialog.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/main.dart';
import 'package:skyinfo/domain/build_channel.dart';
import 'package:skyinfo/ui/industrial.dart';

class PermissionBridge extends VehicleBridge {
  final calls = <String>[];
  Map<String, dynamic> config = {
    'overlayEnabled': false,
    'autoSystemAdb': false,
  };
  Completer<Map<String, dynamic>>? permission;
  bool failSave = false;
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    if (method == 'setOverlayEnabled') {
      if (args!['enabled'] == true) return permission!.future;
      config['overlayEnabled'] = false;
    }
    if (method == 'save') {
      if (failSave) throw StateError('failed');
      config = Map<String, dynamic>.from(args!['config']);
    }
    return {
      'config': Map<String, dynamic>.from(config),
      'status': <String, dynamic>{},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  test(
    'auto restore defaults off and persists with the rest of the configuration',
    () async {
      final bridge = PermissionBridge();
      final c = AppController(bridge: bridge);
      expect(c.autoSystemAdb, isFalse);
      c.restore({'collect': true});
      expect(c.autoSystemAdb, isFalse);
      await c.setAutoSystemAdb(true);
      expect(bridge.config['autoSystemAdb'], isTrue);
      final restored = AppController()..restore(bridge.config);
      expect(restored.autoSystemAdb, isTrue);
      await c.setAutoSystemAdb(false);
      expect(bridge.config['autoSystemAdb'], isFalse);
      bridge.failSave = true;
      await c.setAutoSystemAdb(true);
      expect(c.autoSystemAdb, isFalse);
      expect(c.autoSystemAdbPending, isFalse);
      restored.dispose();
      c.dispose();
    },
  );
  test(
    'overlay remains off while requesting permission, cancellation keeps modules',
    () async {
      final bridge = PermissionBridge()..permission = Completer();
      bridge.config['overlays'] = [
        {
          'id': 'test-module',
          'field': '1032/7/1128267816',
          'icon': 'tabler-battery-automotive',
          'unit': 'V',
          'alignment': 'center',
        },
      ];
      final c = AppController(bridge: bridge);
      c.restore(bridge.config);
      final before = c.config['overlays'];
      final enabling = c.setOverlayEnabled(true);
      expect(c.overlayEnabled, isFalse);
      expect(c.overlayPermissionPending, isTrue);
      await c.setOverlayEnabled(true);
      expect(bridge.calls, ['setOverlayEnabled']);
      bridge.permission!.complete({'config': bridge.config});
      await enabling;
      expect(c.overlayEnabled, isFalse);
      expect(c.overlayPermissionPending, isFalse);
      expect(c.config['overlays'], before);
      expect(c.overlays.single.id, 'test-module');
      expect(c.error, isNull);
      c.dispose();
    },
  );
  test(
    'overlay enables only from native permission result and disabling does not request authorization',
    () async {
      final bridge = PermissionBridge()..permission = Completer();
      final c = AppController(bridge: bridge);
      final enabling = c.setOverlayEnabled(true);
      bridge.config['overlayEnabled'] = true;
      bridge.permission!.complete({
        'config': bridge.config,
        'status': {'overlayGranted': true},
      });
      await enabling;
      expect(c.overlayEnabled, isTrue);
      expect(c.status['overlayGranted'], isTrue);
      bridge.permission = null;
      await c.setOverlayEnabled(false);
      expect(c.overlayEnabled, isFalse);
      expect(bridge.calls, ['setOverlayEnabled', 'setOverlayEnabled']);
      c.dispose();
    },
  );
  test('authorization error clears pending state and permits retry', () async {
    final bridge = PermissionBridge()..permission = Completer();
    final c = AppController(bridge: bridge);
    final enabling = c.setOverlayEnabled(true);
    bridge.permission!.completeError(StateError('no activity'));
    await enabling;
    expect(c.overlayPermissionPending, isFalse);
    expect(c.overlayEnabled, isFalse);
    expect(c.error, isNotNull);
    c.dispose();
  });
  testWidgets(
    'explanation and switch are independent at vehicle density and in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 900);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final bridge = PermissionBridge();
      final c = AppController(bridge: bridge);
      await tester.runAsync(c.initialize);
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
      c.reduceMotion = true;
      for (final theme in ['light', 'dark']) {
        c.theme = theme;
        await tester.pumpWidget(SkyInfo(controller: c));
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('设置').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('高级').last);
        await tester.pumpAndSettle();
        final help = find.byTooltip('自动开启系统ADB说明');
        await tester.ensureVisible(help);
        expect(
          DefaultTextStyle.of(
            tester.element(find.text('自动开启系统ADB')),
          ).style.color,
          Palette.of(tester.element(help)).ink,
        );
        final callsBefore = bridge.calls.length;
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/${BuildChannel.isTesting ? 'beta' : 'stable'}-$theme-auto-adb-settings.png',
          ),
        );
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(bridge.calls.length, callsBefore);
        expect(c.autoSystemAdb, isFalse);
        expect(find.textContaining('Wi-Fi'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/${BuildChannel.isTesting ? 'beta' : 'stable'}-$theme-auto-adb-explanation.png',
          ),
        );
        final closeRect = tester.getRect(find.byIcon(Icons.close));
        final body = find
            .descendant(
              of: find.byType(DesignDialog),
              matching: find.byType(ListView),
            )
            .last;
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(of: body, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        expect(scroll.maxScrollExtent, 0);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        expect(scroll.maxScrollExtent, greaterThan(0));
        await tester.drag(body, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(scroll.pixels, greaterThan(0));
        expect(tester.getRect(find.byIcon(Icons.close)), closeRect);
        expect(c.autoSystemAdb, isFalse);
        expect(bridge.calls.length, callsBefore);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        final row = find.ancestor(
          of: find.text('自动开启系统ADB'),
          matching: find.byType(ParameterRow),
        );
        await tester.ensureVisible(row);
        await tester.tap(
          find.descendant(of: row, matching: find.byType(IndustrialSwitch)),
        );
        await tester.pumpAndSettle();
        expect(c.autoSystemAdb, isTrue);
        await c.setAutoSystemAdb(false);
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}

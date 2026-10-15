import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/overlay_settings.dart';

class PositionBridge extends VehicleBridge {
  final calls = <String>[];
  Completer<Map<String, dynamic>>? pending;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    if (fail) throw StateError('unavailable');
    if (pending != null) return pending!.future;
    return {
      'config': {'overlayX': null, 'overlayY': null},
      'status': {'overlayInteraction': 'locked'},
    };
  }
}

void main() {
  test(
    'reset changes only coordinates and uses a dedicated command even when hidden',
    () async {
      final bridge = PositionBridge();
      final c = AppController(bridge: bridge)
        ..restore({
          'overlayX': .3,
          'overlayY': .6,
          'collect': false,
          'overlayFont': 24,
          'overlayOpacity': .3,
        });
      final before = c.config;
      expect(await c.resetOverlayPosition(), isTrue);
      expect(c.config, {...before, 'overlayX': null, 'overlayY': null});
      expect(bridge.calls, ['resetOverlayPosition']);
      c.dispose();
    },
  );
  test(
    'position failure preserves configuration and repeated pending requests are ignored',
    () async {
      final bridge = PositionBridge()..pending = Completer();
      final c = AppController(bridge: bridge)
        ..overlayX = .4
        ..overlayY = .5;
      final before = c.config;
      final action = c.resetOverlayPosition();
      expect(c.overlayPositionPending, isTrue);
      expect(await c.resetOverlayPosition(), isFalse);
      expect(bridge.calls.length, 1);
      bridge.pending!.completeError(StateError('failed'));
      expect(await action, isFalse);
      expect(c.config, before);
      expect(c.error, isNotNull);
      expect(c.overlayPositionPending, isFalse);
      c.dispose();
    },
  );
  test(
    'adjust requires enabled modules and running collection, but reset does not',
    () async {
      final bridge = PositionBridge();
      final c = AppController(bridge: bridge);
      expect(await c.adjustOverlayPosition(), isFalse);
      c.overlayEnabled = true;
      expect(await c.adjustOverlayPosition(), isFalse);
      c.overlays = [
        OverlaySpec.fromJson({
          'id': 'o1',
          'field': 'voltage',
          'icon': '',
          'unit': 'V',
          'alignment': 'left',
        }),
      ];
      c.status = {'stopped': true};
      expect(await c.adjustOverlayPosition(), isFalse);
      c.status = {};
      expect(await c.adjustOverlayPosition(), isTrue);
      expect(bridge.calls, ['editOverlay']);
      c.dispose();
    },
  );
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1000.0]) {
      testWidgets(
        'overlay settings are compact with no position sliders $brightness $width',
        (t) async {
          t.view.physicalSize = Size(width, 800);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final c = AppController(bridge: PositionBridge());
          await t.pumpWidget(
            MaterialApp(
              theme: industrialTheme(brightness),
              home: Scaffold(
                body: ListView(children: [OverlaySettings(controller: c)]),
              ),
            ),
          );
          expect(find.byType(ParameterRow), findsNWidgets(4));
          expect(find.byType(Slider), findsOneWidget);
          expect(find.text('顶部偏移'), findsNothing);
          expect(find.text('左侧留空'), findsNothing);
          expect(find.text('右侧留空'), findsNothing);
          expect(find.text('开启悬浮条后可调整位置。'), findsOneWidget);
          expect(
            t
                .widget<IndustrialButton>(
                  find.widgetWithText(IndustrialButton, '调整位置'),
                )
                .onPressed,
            isNull,
          );
          expect(
            t
                .widget<IndustrialButton>(
                  find.widgetWithText(IndustrialButton, '恢复默认'),
                )
                .onPressed,
            isNotNull,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
}

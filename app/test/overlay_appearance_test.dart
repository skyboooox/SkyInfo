import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/ui/live_setting_slider.dart';
import 'package:skyinfo/ui/field_details.dart';
import 'package:skyinfo/ui/industrial.dart';

class StyleBridge extends VehicleBridge {
  final calls = <(String, Map<String, dynamic>)>[];
  Completer<Map<String, dynamic>>? slow;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add((method, Map.of(args ?? {})));
    if (method == 'previewOverlayStyle' && slow != null) return slow!.future;
    if (method == 'saveOverlayAppearance') {
      if (fail) throw StateError('save failed');
      return {
        'config': {
          'overlayFont': 18,
          'overlayOpacity': .7,
          ...args!['style'] as Map,
        },
      };
    }
    return {};
  }
}

void main() {
  test('expired GNSS data does not display its cached height as current', () {
    final sample = Sample.fromJson({
      'value': 14.7,
      'raw': 14.7,
      'quality': 'stale',
    });
    expect(sample.formatted(1), '—');
    expect(sample.qualityLabel, '已过期');
    expect(sample.raw, 14.7);
  });
  testWidgets('GNSS permission is explicit and real data removes the entry', (
    t,
  ) async {
    final c = AppController(bridge: StyleBridge())
      ..metrics = [
        Metric.fromJson({
          'id': 'location.gnss_altitude',
          'name': '海拔 · GNSS',
          'unit': 'm',
          'category': '车身与环境',
          'encoding': 'm',
          'icon': 'tabler-arrows-up-down',
          'entityKey': 'gnss_altitude',
          'displayAllowed': true,
        }),
      ];
    c.reading('location.gnss_altitude');
    c.applySamples({
      'location.gnss_altitude': {'quality': 'permission'},
    });
    await t.pumpWidget(
      MaterialApp(
        theme: industrialTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showFieldDetails(context, c, 'location.gnss_altitude'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('定位授权'), findsOneWidget);
    await t.ensureVisible(find.text('定位授权'));
    await t.tap(find.text('定位授权'));
    await t.pumpAndSettle();
    expect(
      (c.bridge as StyleBridge).calls
          .where((x) => x.$1 == 'requestLocation')
          .length,
      1,
    );
    c.applySamples({
      'location.gnss_altitude': {'quality': 'available', 'value': 14.7},
    });
    await t.pump();
    expect(find.text('定位授权'), findsNothing);
    expect(find.textContaining('14.7'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.pump();
  });
  testWidgets(
    'slow preview stays bounded and saves once on release without resetting other preferences',
    (t) async {
      final bridge = StyleBridge()..slow = Completer();
      final c = AppController(bridge: bridge)
        ..restore({
          'collect': false,
          'overlayX': 0.4,
          'overlayY': 0.6,
          'overlayOpacity': .2,
        });
      var notifications = 0;
      c.addListener(() => notifications++);
      for (var i = 0; i < 50; i++) {
        c.overlayAppearance.previewOpacity(.1 + i * .006);
      }
      await t.pump(const Duration(milliseconds: 34));
      expect(bridge.calls.length, 1);
      for (var i = 50; i < 100; i++) {
        c.overlayAppearance.previewOpacity(.1 + i * .006);
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(bridge.calls.length, 1);
      expect(notifications, 0);
      expect(c.overlayOpacity, .2);
      final first = bridge.slow!;
      bridge.slow = null;
      first.complete({});
      await t.pump(const Duration(milliseconds: 34));
      final saved = c.overlayAppearance.commitOpacity(.7);
      await t.pump(const Duration(milliseconds: 34));
      expect(await saved, isTrue);
      final writes = bridge.calls
          .where((x) => x.$1 == 'saveOverlayAppearance')
          .toList();
      expect(writes.length, 1);
      final config = c.config;
      expect(writes.single.$2['style'], {'overlayOpacity': .7});
      expect(config['overlayOpacity'], .7);
      expect(config['overlayY'], .6);
      expect(config['overlayX'], 0.4);
      expect(config['collect'], false);
      expect(
        bridge.calls
            .where((x) => x.$1 == 'previewOverlayStyle')
            .last
            .$2['style'],
        {'overlayOpacity': .694},
      );
      c.dispose();
      await t.pump();
    },
  );
  testWidgets(
    'failed commit restores the saved configuration and clears preview',
    (t) async {
      final bridge = StyleBridge()..fail = true;
      final c = AppController(bridge: bridge);
      final before = c.config;
      final saved = c.overlayAppearance.commitOpacity(.5);
      await t.pump();
      expect(await saved, isFalse);
      expect(c.config, before);
      expect(c.error, isNotNull);
      await t.pump(const Duration(milliseconds: 34));
      expect(bridge.calls.last.$1, 'previewOverlayStyle');
      expect(bridge.calls.last.$2, {'style': null});
      c.dispose();
      await t.pump();
    },
  );
  testWidgets('thumb tracks the finger before a slow save completes', (
    t,
  ) async {
    final saved = Completer<bool>();
    final values = <double>[];
    var commits = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: LiveSettingSlider(
              value: 0,
              min: 0,
              max: 120,
              onPreview: values.add,
              onCancel: () {},
              onCommit: (_) {
                commits++;
                return saved.future;
              },
            ),
          ),
        ),
      ),
    );
    final slider = find.byType(Slider);
    final start = t.getTopLeft(slider) + const Offset(30, 24);
    final gesture = await t.startGesture(start);
    await gesture.moveBy(const Offset(300, 0));
    await t.pump();
    expect(values.last, greaterThan(60));
    expect(t.widget<Slider>(slider).value, values.last);
    expect(commits, 0);
    await gesture.up();
    await t.pump();
    expect(commits, 1);
    expect(t.widget<Slider>(slider).value, values.last);
    saved.complete(true);
    await t.pump();
    await t.pumpWidget(const SizedBox());
  });
}

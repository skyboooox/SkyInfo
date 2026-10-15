import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';
import 'package:skyinfo/main.dart';

class ThemeBridge extends VehicleBridge {
  final updates = StreamController<Map<String, dynamic>>();
  final calls = <String>[];
  final String? brightness;
  ThemeBridge(this.brightness);
  @override
  Stream<Map<String, dynamic>> get events => updates.stream;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add(method);
    return method == 'load'
        ? {
            'config': {'theme': 'system', 'collect': false},
            'status': {
              'appearance': {
                'brightness': brightness,
                'source': 'byd_display_mode',
              },
            },
          }
        : {};
  }
}

void main() {
  testWidgets('自动优先车机主题，变化不写配置且保留当前页面与弹窗', (t) async {
    t.view.physicalSize = const Size(1920, 900);
    t.view.devicePixelRatio = 1.5;
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    final bridge = ThemeBridge('light');
    final c = AppController(bridge: bridge);
    await t.runAsync(c.initialize);
    c.reduceMotion = true;
    await t.pumpWidget(SkyInfo(controller: c));
    await t.pumpAndSettle();
    Brightness shown() =>
        Theme.of(t.element(find.byType(Scaffold).first)).brightness;
    expect(shown(), Brightness.light);
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('设置').last);
    await t.pumpAndSettle();
    expect(find.text('自动'), findsOneWidget);
    final before = c.config;
    final calls = bridge.calls.toList();
    showDialog<void>(
      context: t.element(find.byType(Scaffold).first),
      builder: (_) => const AlertDialog(content: Text('保留草稿')),
    );
    await t.pumpAndSettle();
    bridge.updates.add({
      'status': {
        'appearance': {'brightness': 'dark'},
      },
    });
    await t.pumpAndSettle();
    expect(shown(), Brightness.dark);
    expect(find.text('保留草稿'), findsOneWidget);
    expect(find.text('主页显示大小'), findsOneWidget);
    expect(c.config, before);
    expect(bridge.calls, calls);
    c.theme = 'light';
    bridge.updates.add({
      'status': {
        'appearance': {'brightness': 'dark', 'source': 'byd_night_mode'},
      },
    });
    await t.pumpAndSettle();
    expect(shown(), Brightness.light);
    c.theme = 'dark';
    bridge.updates.add({
      'status': {
        'appearance': {'brightness': 'light'},
      },
    });
    await t.pumpAndSettle();
    expect(shown(), Brightness.dark);
    c.theme = 'system';
    bridge.updates.add({
      'status': {
        'appearance': {'brightness': null, 'source': 'android'},
      },
    });
    await t.pumpAndSettle();
    expect(shown(), Brightness.dark);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pumpAndSettle();
    expect(shown(), Brightness.light);
    bridge.updates.add({
      'status': {
        'appearance': {'brightness': 'unrecognized'},
      },
    });
    await t.pumpAndSettle();
    expect(shown(), Brightness.light);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(bridge.updates.close);
  });
}

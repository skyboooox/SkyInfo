import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/data/vehicle_bridge.dart';

class EfficiencyBridge extends VehicleBridge {
  final updates = StreamController<Map<String, dynamic>>();
  final calls = <(String, Map<String, dynamic>?)>[];
  final historyReplies = <Completer<Map<String, dynamic>>>[];
  final previewReplies = <Completer<Map<String, dynamic>>>[];
  bool delayPreview = false;
  @override
  Stream<Map<String, dynamic>> get events => updates.stream;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) {
    calls.add((method, args));
    if (method == 'history') {
      final reply = Completer<Map<String, dynamic>>();
      historyReplies.add(reply);
      return reply.future;
    }
    if (method == 'previewFields' && delayPreview) {
      final reply = Completer<Map<String, dynamic>>();
      previewReplies.add(reply);
      return reply.future;
    }
    return Future.value(
      method == 'load'
          ? {
              'config': {},
              'status': {
                'adb': 'connected',
                'systemAdb': {'state': 'enabled'},
                'appearance': {'brightness': 'dark'},
              },
            }
          : {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'equivalent nested status is quiet and actual adb or brightness changes notify',
    () async {
      final b = EfficiencyBridge();
      final c = AppController(bridge: b);
      await c.initialize();
      var notifications = 0;
      c.addListener(() {
        notifications++;
      });
      b.updates.add({
        'status': {
          'appearance': {'brightness': 'dark'},
          'systemAdb': {'state': 'enabled'},
          'adb': 'connected',
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      b.updates.add({
        'status': {
          'adb': 'authorization',
          'systemAdb': {'state': 'enabled'},
          'appearance': {'brightness': 'dark'},
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      b.updates.add({
        'status': {
          'adb': 'authorization',
          'systemAdb': {'state': 'enabled'},
          'appearance': {'brightness': 'light'},
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);
      c.dispose();
      await b.updates.close();
    },
  );
  test(
    'history shares refresh requests in flight and retries after failure',
    () async {
      final b = EfficiencyBridge();
      final c = AppController(bridge: b);
      final first = c.history('v', 30, refresh: true);
      expect(identical(first, c.history('v', 30, refresh: true)), isTrue);
      expect(b.historyReplies, hasLength(1));
      final secondWindow = c.history('v', 120, refresh: true);
      expect(b.historyReplies, hasLength(2));
      b.historyReplies[0].complete({'points': []});
      b.historyReplies[1].complete({'points': []});
      await first;
      await secondWindow;
      await c.history('v', 30);
      expect(b.historyReplies, hasLength(2));
      final failed = c.history('v', 30, refresh: true);
      final failure = expectLater(failed, throwsStateError);
      b.historyReplies.last.completeError(StateError('fixture'));
      await failure;
      final retried = c.history('v', 30, refresh: true);
      expect(b.historyReplies, hasLength(4));
      b.historyReplies.last.complete({'points': []});
      await retried;
      c.dispose();
      unawaited(b.updates.close());
    },
  );
  test(
    'preview keeps one request and the latest union then releases after disposal',
    () async {
      final b = EfficiencyBridge()..delayPreview = true;
      final c = AppController(bridge: b);
      final lease = c.acquirePreview(['a']);
      lease.update(['a']);
      lease.update(['b']);
      lease.update(['c']);
      expect(b.previewReplies, hasLength(1));
      b.previewReplies[0].complete({});
      await Future<void>.delayed(Duration.zero);
      expect(b.previewReplies, hasLength(2));
      expect(b.calls.last.$2!['fields'], ['c']);
      c.dispose();
      b.previewReplies[1].complete({});
      await Future<void>.delayed(Duration.zero);
      expect(b.previewReplies, hasLength(3));
      expect(b.calls.last.$2!['fields'], isEmpty);
      b.previewReplies[2].complete({});
      await Future<void>.delayed(Duration.zero);
      lease.dispose();
      expect(b.previewReplies, hasLength(3));
      unawaited(b.updates.close());
    },
  );
  test(
    'failed preview retries the same explicit demand and failed disposal is bounded',
    () async {
      final b = EfficiencyBridge()..delayPreview = true;
      final c = AppController(bridge: b);
      final lease = c.acquirePreview(['a']);
      b.previewReplies[0].completeError(StateError('fixture'));
      await Future<void>.delayed(Duration.zero);
      expect(b.previewReplies, hasLength(1));
      lease.update(['a']);
      expect(b.previewReplies, hasLength(2));
      b.previewReplies[1].complete({});
      await Future<void>.delayed(Duration.zero);
      lease.update(['b']);
      c.dispose();
      b.previewReplies[2].completeError(StateError('fixture'));
      await Future<void>.delayed(Duration.zero);
      expect(b.calls.last.$2!['fields'], isEmpty);
      expect(b.previewReplies, hasLength(4));
      b.previewReplies[3].completeError(StateError('fixture'));
      await Future<void>.delayed(Duration.zero);
      expect(b.previewReplies, hasLength(4));
      unawaited(b.updates.close());
    },
  );
  test(
    'history snapshots share query time and reject in-place mutation',
    () async {
      final bridge = EfficiencyBridge();
      final c = AppController(bridge: bridge);
      final request = c.history('field', 120);
      expect(bridge.calls.last.$2!['includeSample'], false);
      bridge.historyReplies.single.complete({
        'queriedAt': 1794283200000,
        'points': [
          {'at': '2026-11-10T11:59:00Z', 'value': 1},
          {
            'at': '2026-11-10T12:00:00Z',
            'value': 2,
            'state': 'ready',
            'segment': 'current',
            'observedUntil': 1794283200000,
          },
        ],
      });
      final points = await request;
      expect(
        identical(points.first.snapshotAt, points.last.snapshotAt),
        isTrue,
      );
      expect(() => points.clear(), throwsUnsupportedError);
      expect(points.last.state, 'ready');
      expect(points.last.segment, 'current');
      expect(points.last.observedUntil, points.last.snapshotAt);
      c.dispose();
      unawaited(bridge.updates.close());
    },
  );
}

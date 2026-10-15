import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/domain/models.dart';
import 'package:skyinfo/ui/data_activity.dart';
import 'package:skyinfo/ui/retained_history.dart';
import 'package:skyinfo/ui/attention_surface.dart';
import 'package:skyinfo/ui/confirmation.dart';
import 'package:skyinfo/ui/industrial.dart';
import 'package:skyinfo/ui/motion_clock.dart';
import 'package:skyinfo/ui/motion.dart';

void main() {
  HistorySeries series(double v) => [
    [HistoryPoint(DateTime(2026), v)],
  ];
  Widget host(Widget child, {bool reduce = false}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: child!,
    ),
    home: Scaffold(body: SizedBox(width: 640, height: 400, child: child)),
  );
  Widget retained(
    Future<HistorySeries> future, {
    int scope = 0,
    VoidCallback? applied,
  }) => RetainedHistory(
    key: ValueKey(scope),
    future: future,
    onApplied: applied,
    builder: (data) => Text('${data.first.first.value}'),
  );
  testWidgets(
    'history keeps its last plot while refreshing and on failure, then replaces without a loading state',
    (t) async {
      var calls = 0;
      final first = Completer<HistorySeries>();
      await t.pumpWidget(host(retained(first.future, applied: () => calls++)));
      expect(find.text('读取历史…'), findsNothing);
      expect(find.text('暂无历史'), findsNothing);
      first.complete(series(12));
      await t.pump();
      await t.pump();
      expect(find.text('12.0'), findsOneWidget);
      expect(calls, 1);
      final second = Completer<HistorySeries>();
      await t.pumpWidget(host(retained(second.future, applied: () => calls++)));
      expect(find.text('12.0'), findsOneWidget);
      expect(calls, 1);
      second.completeError(StateError('offline'));
      await t.pumpAndSettle();
      expect(find.text('12.0'), findsOneWidget);
      expect(find.text('offline'), findsOneWidget);
      await t.pumpWidget(
        host(retained(Future.value(series(13)), applied: () => calls++)),
      );
      await t.pump();
      await t.pump();
      expect(find.text('13.0'), findsOneWidget);
      expect(find.text('12.0'), findsNothing);
      expect(calls, 2);
      await t.pumpWidget(host(retained(Future.value([[]]))));
      await t.pump();
      expect(find.text('暂无历史'), findsOneWidget);
      expect(find.text('13.0'), findsNothing);
    },
  );
  testWidgets(
    'history scope changes clear old fields/window, ignore late completions and never pulse for cache rebuilds',
    (t) async {
      var pulses = 0;
      final data = series(5), pending = Completer<HistorySeries>();
      await t.pumpWidget(
        host(retained(Future.value(data), applied: () => pulses++)),
      );
      await t.pump();
      await t.pump();
      await t.pumpWidget(
        host(retained(Future.value(data), applied: () => pulses++)),
      );
      await t.pump();
      await t.pump();
      expect(pulses, 1);
      await t.pumpWidget(host(retained(pending.future)));
      final next = Completer<HistorySeries>();
      await t.pumpWidget(host(retained(next.future, scope: 1)));
      expect(find.text('5.0'), findsNothing);
      expect(find.text('暂无历史'), findsNothing);
      pending.complete(series(99));
      await t.pump();
      expect(find.text('99.0'), findsNothing);
      next.complete(series(6));
      await t.pumpAndSettle();
      expect(find.text('6.0'), findsOneWidget);
    },
  );
  testWidgets(
    'sample timestamp alone pulses the subtle dot, coalesced within a 500ms cycle',
    (t) async {
      final at = DateTime(2026),
          a = ValueNotifier(const Sample()),
          b = ValueNotifier(const Sample());
      await t.pumpWidget(host(DataActivityDot(readings: [a, b])));
      final opacity = t
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(DataActivityDot),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity;
      final dot = t.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(DataActivityDot),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect((dot.decoration as BoxDecoration).color, Palette.light.activity);
      expect(opacity.value, .5);
      a.value = Sample(value: 10, quality: 'available', updatedAt: at);
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(opacity.value, closeTo(1, .01));
      b.value = Sample(value: 20, quality: 'available', updatedAt: at);
      await t.pump(const Duration(milliseconds: 250));
      expect(opacity.value, .5);
      await t.pump(const Duration(milliseconds: 1));
      a.value = Sample(
        value: 10,
        quality: 'available',
        updatedAt: at.add(const Duration(seconds: 1)),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(opacity.value, closeTo(1, .01));
      await t.pumpWidget(host(DataActivityDot(readings: [a, b]), reduce: true));
      expect(opacity.value, .5);
      a.value = Sample(
        value: 11,
        quality: 'available',
        updatedAt: at.add(const Duration(seconds: 2)),
      );
      await t.pump(const Duration(seconds: 1));
      expect(opacity.value, .5);
      await t.pumpWidget(const SizedBox());
      a.dispose();
      b.dispose();
    },
  );
  testWidgets(
    'stripes repaint at most 20Hz without rebuilding foreground, pause while hidden',
    (t) async {
      late PaintClock clock;
      var builds = 0, paints = 0;
      await t.pumpWidget(
        _ClockHarness(
          onClock: (c) {
            clock = c;
            clock.addListener(() => paints++);
          },
          child: Builder(
            builder: (_) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      );
      await t.pump();
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 17));
      }
      expect(paints, inInclusiveRange(10, 20));
      expect(builds, 1);
      clock.setRunning(false);
      final before = paints;
      await t.pump(const Duration(seconds: 2));
      expect(paints, before);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'confirmation stripes only affirmative action, reduced motion is static and cancel remains default',
    (t) async {
      bool? result;
      await t.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmRemoval(
                  context,
                  title: 'Remove?',
                  message: 'Remove this card',
                );
              },
              child: const Text('open'),
            ),
          ),
          reduce: true,
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(AttentionSurface), findsOneWidget);
      final buttons = t
          .widgetList<IndustrialButton>(find.byType(IndustrialButton))
          .toList();
      expect(buttons.where((b) => b.attention).single.label, '删除');
      expect(buttons.where((b) => b.autofocus).single.label, '取消');
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(result, false);
    },
  );
  testWidgets(
    'decorative motion stops in background and stays static with reduced motion',
    (t) async {
      Widget surface(bool reduce) => host(
        const AttentionSurface(
          color: Colors.black,
          child: SizedBox(width: 200, height: 48),
        ),
        reduce: reduce,
      );
      await t.pumpWidget(surface(false));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.hasScheduledFrame, isTrue);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.hasScheduledFrame, isTrue);
      await t.pumpWidget(surface(true));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'outgoing page cannot receive actions while a new page transitions',
    (t) async {
      var writes = 0;
      await t.pumpWidget(
        host(
          Motion(
            identity: 0,
            child: TextButton(
              onPressed: () => writes++,
              child: const Text('old'),
            ),
          ),
        ),
      );
      await t.pumpWidget(host(const Motion(identity: 1, child: SizedBox())));
      final old = find.text('old');
      expect(old, findsOneWidget);
      expect(
        find
            .ancestor(of: old, matching: find.byType(IgnorePointer))
            .evaluate()
            .where((e) => (e.widget as IgnorePointer).ignoring),
        isNotEmpty,
      );
      expect(writes, 0);
      await t.pump(const Duration(milliseconds: 300));
      expect(old, findsNothing);
    },
  );
}

class _ClockHarness extends StatefulWidget {
  final void Function(PaintClock) onClock;
  final Widget child;
  const _ClockHarness({required this.onClock, required this.child});
  @override
  State<_ClockHarness> createState() => _ClockHarnessState();
}

class _ClockHarnessState extends State<_ClockHarness>
    with SingleTickerProviderStateMixin {
  late final clock = PaintClock(this);
  @override
  void initState() {
    super.initState();
    widget.onClock(clock);
    clock.setRunning(true);
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

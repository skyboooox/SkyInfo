import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/domain/control_entity.dart';
import 'package:skyinfo/domain/models.dart';

Map<String, dynamic> sample() => {
  'value': 10,
  'raw': 10,
  'quality': 'available',
  'source': 'vehicle',
  'unit': '°C',
  'stateLabel': 'warm',
  'updatedAt': 1000,
  'changedAt': 1000,
};

void main() {
  test('repeated snapshots preserve objects and isolate other readings', () {
    final c = AppController();
    final a = c.reading('a'), b = c.reading('b');
    c.applySamples({'a': sample(), 'b': sample()});
    final previous = a.value;
    var aCalls = 0, bCalls = 0;
    a.addListener(() => aCalls++);
    b.addListener(() => bCalls++);
    for (var i = 0; i < 100; i++) {
      c.applySamples({'a': sample(), 'b': sample()});
    }
    expect(a.value, same(previous));
    expect(aCalls, 0);
    expect(bCalls, 0);
    c.applySamples({
      'a': sample(),
      'b': {...sample(), 'value': 11},
    });
    expect(aCalls, 0);
    expect(bCalls, 1);
    c.dispose();
  });

  for (final change in <String, dynamic>{
    'value': 11,
    'raw': 11,
    'quality': 'error',
    'source': 'other',
    'unit': 'K',
    'stateLabel': 'hot',
    'updatedAt': 2000,
    'changedAt': 2000,
  }.entries) {
    test('${change.key} changes remain observable', () {
      final c = AppController(), next = {...sample(), change.key: change.value};
      final reading = c.reading('a');
      c.applySamples({'a': sample()});
      final previous = reading.value;
      var calls = 0;
      reading.addListener(() => calls++);
      c.applySamples({'a': next});
      expect(calls, 1);
      expect(reading.value, isNot(same(previous)));
      expect(
        reading.value.updatedAt!.millisecondsSinceEpoch,
        change.key == 'updatedAt' ? 2000 : 1000,
      );
      c.applySamples({'a': Map<String, dynamic>.from(next)});
      expect(calls, 1);
      c.dispose();
    });
  }

  test('structured raw data and stale quality retain their meaning', () {
    final c = AppController(), reading = c.reading('a');
    Map<String, dynamic> structured(int n) => {
      ...sample(),
      'raw': {
        'values': [n, null],
      },
    };
    c.applySamples({'a': structured(1)});
    var calls = 0;
    reading.addListener(() => calls++);
    c.applySamples({'a': structured(1)});
    expect(calls, 0);
    c.applySamples({'a': structured(2)});
    expect(calls, 1);
    c.applySamples({
      'a': {...structured(2), 'quality': 'stale'},
    });
    expect(calls, 2);
    expect(reading.value.value, isNull);
    expect(reading.value.quality, 'stale');
    c.dispose();
  });

  for (final field in ['value', 'raw']) {
    test('$field numeric representation changes notify in both directions', () {
      final c = AppController(), reading = c.reading('a');
      final initial = {...sample(), 'stateLabel': null};
      c.applySamples({'a': initial});
      var calls = 0;
      reading.addListener(() => calls++);
      c.applySamples({
        'a': {...initial, field: 10.0},
      });
      expect(calls, 1);
      if (field == 'value') expect(reading.value.formatted(1), '10.0');
      c.applySamples({'a': initial});
      expect(calls, 2);
      if (field == 'value') expect(reading.value.formatted(1), '10');
      c.dispose();
    });

    test('$field signed zero changes notify in both directions', () {
      final c = AppController(), reading = c.reading('a');
      final initial = {...sample(), 'stateLabel': null, field: 0.0};
      c.applySamples({'a': initial});
      var calls = 0;
      reading.addListener(() => calls++);
      c.applySamples({
        'a': {...initial, field: -0.0},
      });
      expect(calls, 1);
      if (field == 'value') expect(reading.value.formatted(1), '-0.0');
      c.applySamples({
        'a': {...initial, field: -0.0},
      });
      expect(calls, 1);
      c.applySamples({'a': initial});
      expect(calls, 2);
      if (field == 'value') expect(reading.value.formatted(1), '0.0');
      c.dispose();
    });
  }

  test('nested sample data preserves numeric representation changes', () {
    final c = AppController(), reading = c.reading('a');
    for (final field in ['value', 'raw']) {
      Map<String, dynamic> data(num n) => {
        ...sample(),
        field: {
          'nested': [
            n,
            {'other': 1},
          ],
        },
      };
      c.applySamples({'a': data(10)});
      var calls = 0;
      void changed() => calls++;
      reading.addListener(changed);
      c.applySamples({'a': data(10)});
      expect(calls, 0);
      c.applySamples({'a': data(10.0)});
      expect(calls, 1);
      c.applySamples({'a': data(10)});
      expect(calls, 2);
      c.applySamples({'a': data(0.0)});
      expect(calls, 3);
      c.applySamples({'a': data(-0.0)});
      expect(calls, 4);
      c.applySamples({'a': data(0.0)});
      expect(calls, 5);
      reading.removeListener(changed);
    }
    c.dispose();
  });

  test(
    'derived control feedback preserves duplicates and fresh timestamps',
    () {
      final c = AppController();
      c.controlEntities = [
        const ControlEntity(
          action: 'fan',
          name: 'Fan',
          category: 'Cabin',
          icon: '',
          unit: '',
          readField: 'a',
          feedbackFields: ['a'],
          options: [EntityOption(1, 'On', 10)],
          states: {'10': 'On'},
          inferred: false,
          capability: EntityCapability.toggle,
        ),
      ];
      final reading = c.reading('a'), control = c.reading('control.fan');
      c.applySamples({'a': sample()});
      final old = control.value;
      var calls = 0;
      control.addListener(() => calls++);
      c.applySamples({'a': sample()});
      expect(control.value, same(old));
      expect(calls, 0);
      c.applySamples({
        'a': {...sample(), 'updatedAt': 2000},
      });
      expect(calls, 1);
      expect(control.value.updatedAt, reading.value.updatedAt);
      expect(control.value.stateLabel, 'On');
      c.applySamples({
        'a': {...sample(), 'quality': 'error'},
      });
      expect(calls, 2);
      expect(control.value.quality, 'invalid');
      expect(control.value.value, isNull);
      c.dispose();
    },
  );

  testWidgets(
    'duplicate snapshots skip rebuilds while freshness updates paint',
    (tester) async {
      final c = AppController(), reading = c.reading('a');
      c.applySamples({'a': sample()});
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<Sample>(
            valueListenable: reading,
            builder: (_, value, _) {
              builds++;
              return Text('${value.updatedAt!.millisecondsSinceEpoch}');
            },
          ),
        ),
      );
      c.applySamples({'a': sample()});
      await tester.pump();
      expect(builds, 1);
      c.applySamples({
        'a': {...sample(), 'updatedAt': 2000},
      });
      await tester.pump();
      expect(builds, 2);
      expect(find.text('2000'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}

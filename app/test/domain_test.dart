import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/domain/models.dart';

void main() {
  test('相对时间边界、未知和未来时间', () {
    final now = DateTime.utc(2026, 10, 8, 12);
    expect(relativeAge(null, now), '—');
    expect(relativeAge(now.add(const Duration(seconds: 1)), now), '—');
    expect(relativeAge(now.subtract(const Duration(seconds: 59)), now), '59秒前');
    expect(relativeAge(now.subtract(const Duration(seconds: 60)), now), '1分钟前');
    expect(relativeAge(now.subtract(const Duration(hours: 1)), now), '1小时前');
    expect(relativeAge(now.subtract(const Duration(days: 35)), now), '35天前');
  });
  test('混合尺寸网格不重叠，保留固定跨度', () {
    final tiles = [
      for (var i = 0; i < 12; i++)
        TileSpec(
          id: '$i',
          title: '测试',
          kind: WidgetKind.number,
          fields: const ['value'],
          columns: i % 3 == 0 ? 4 : 2,
          rows: i % 4 == 0 ? 4 : 2,
        ),
    ];
    final slots = packTiles(tiles, 8);
    final occupied = <String>{};
    for (final s in slots) {
      expect(s.column + s.tile.columns, lessThanOrEqualTo(8));
      for (var y = 0; y < s.tile.rows; y++) {
        for (var x = 0; x < s.tile.columns; x++) {
          expect(occupied.add('${s.column + x},${s.row + y}'), isTrue);
        }
      }
    }
  });
  test('降采样保留峰谷，并在无效值和来源变更处分段', () {
    final start = DateTime.utc(2026, 10, 8),
        end = start.add(const Duration(minutes: 1));
    final points = [
      HistoryPoint(start, 1, segment: 'a'),
      HistoryPoint(start.add(const Duration(seconds: 1)), 99, segment: 'a'),
      HistoryPoint(start.add(const Duration(seconds: 2)), 2, segment: 'a'),
      HistoryPoint(start.add(const Duration(seconds: 3)), null),
      HistoryPoint(start.add(const Duration(seconds: 4)), 4, segment: 'a'),
      HistoryPoint(start.add(const Duration(seconds: 5)), 5, segment: 'b'),
    ];
    final groups = aggregateHistory(points, 1, start, end);
    expect(groups.length, 3);
    expect(groups.first.single.min, 1);
    expect(groups.first.single.max, 99);
    expect(groups.first.single.representative, 2);
  });
  test('匿名电压回归序列不会被空桶拆成短线段', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/charging-voltage-20261009.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final points = (fixture['points'] as List)
        .map(
          (p) => HistoryPoint(
            DateTime.parse(p['at'] as String),
            (p['value'] as num).toDouble(),
            segment: p['segment'] as String,
          ),
        )
        .toList();
    final start = points.first.at.subtract(const Duration(minutes: 5)),
        end = points.last.at.add(const Duration(seconds: 1));
    final groups = aggregateHistory(points, 180, start, end);
    expect(groups.length, 1);
    expect(groups.single.first.at, points.first.at);
    expect(groups.single.last.at, points.last.at);
    expect(
      groups.single.map((b) => b.min).reduce((a, b) => a < b ? a : b),
      points.map((p) => p.value!).reduce((a, b) => a < b ? a : b),
    );
    expect(
      groups.single.map((b) => b.max).reduce((a, b) => a > b ? a : b),
      points.map((p) => p.value!).reduce((a, b) => a > b ? a : b),
    );
  });
  test('组件配置往返保持独立单位、图标和互斥时间', () {
    const tile = TileSpec(
      id: 'a',
      title: '电池',
      kind: WidgetKind.pair,
      fields: ['a', 'b'],
      columns: 1,
      rows: 2,
      time: TimeDisplay.changed,
      icons: {'a': 'temperature'},
      units: {'a': '原值', 'b': '自定义'},
    );
    final restored = TileSpec.fromJson(tile.toJson());
    expect(restored.time, TimeDisplay.changed);
    expect(restored.units, tile.units);
    expect(restored.icons, tile.icons);
    expect(restored.columns, 1);
    expect(restored.rows, 2);
  });
  test('位置保留、碰撞重排和窄屏回流', () {
    const a = TileSpec(
      id: 'a',
      title: 'A',
      kind: WidgetKind.number,
      fields: ['a'],
      column: 4,
      row: 2,
    );
    const b = TileSpec(
      id: 'b',
      title: 'B',
      kind: WidgetKind.number,
      fields: ['b'],
      column: 4,
      row: 2,
    );
    final wide = packTiles([a, b], 8);
    expect((wide.first.column, wide.first.row), (4, 2));
    expect((wide.last.column, wide.last.row), isNot((4, 2)));
    final narrow = packTiles([a, b], 4);
    expect(narrow.every((s) => s.column + s.tile.columns <= 4), isTrue);
    final resized = a.positioned(1, 3, columns: 1, rows: 2);
    expect(TileSpec.fromJson(resized.toJson()).column, 1);
  });
  test('稀疏订阅跨空桶连续且保留峰谷实际时间', () {
    final start = DateTime.utc(2026, 10, 8),
        end = start.add(const Duration(seconds: 100));
    final groups = aggregateHistory(
      [
        HistoryPoint(start, 9),
        HistoryPoint(start.add(const Duration(seconds: 1)), 2),
        HistoryPoint(start.add(const Duration(seconds: 2)), 7),
        HistoryPoint(start.add(const Duration(seconds: 90)), 5),
      ],
      10,
      start,
      end,
    );
    expect(groups.length, 1);
    expect(groups.single.length, 2);
    expect(groups.first.first.maximumAt, start);
    expect(groups.first.first.minimumAt, start.add(const Duration(seconds: 1)));
    expect(groups.first.first.at, start.add(const Duration(seconds: 2)));
  });
}

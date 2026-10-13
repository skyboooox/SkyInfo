import 'dart:math' as math;
import 'metrics.dart';

class GridSlot {
  final TileSpec tile;
  final int column, row;
  const GridSlot(this.tile, this.column, this.row);
}

List<GridSlot> packTiles(List<TileSpec> tiles, int columns) {
  final occupied = <String>{};
  final placed = <String, GridSlot>{};
  List<String> cells(TileSpec tile, int col, int row) => [
    for (var y = 0; y < tile.rows; y++)
      for (var x = 0; x < math.min(tile.columns, columns); x++)
        '${col + x},${row + y}',
  ];
  bool put(TileSpec tile, int col, int row) {
    if (col < 0 || row < 0 || col + math.min(tile.columns, columns) > columns) {
      return false;
    }
    final area = cells(tile, col, row);
    if (area.any(occupied.contains)) return false;
    occupied.addAll(area);
    placed[tile.id] = GridSlot(tile, col, row);
    return true;
  }

  for (final tile in tiles) {
    if (tile.column != null && tile.row != null) {
      put(tile, tile.column!, tile.row!);
    }
  }
  for (final tile in tiles) {
    if (placed.containsKey(tile.id)) continue;
    var found = false;
    for (var row = 0; !found; row++) {
      for (
        var col = 0;
        col <= columns - math.min(tile.columns, columns);
        col++
      ) {
        if (put(tile, col, row)) {
          found = true;
          break;
        }
      }
    }
  }
  return tiles.map((tile) => placed[tile.id]!).toList();
}

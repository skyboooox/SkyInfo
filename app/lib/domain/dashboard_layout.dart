import 'dart:math' as math;

enum DashboardSize { standard, enlarged }

class DashboardLayout {
  final int columns, visibleRows;
  final double cell, gap, scale, width, height, verticalInset;

  const DashboardLayout._({
    required this.columns,
    required this.visibleRows,
    required this.cell,
    required this.gap,
    required this.scale,
    required this.width,
    required this.height,
    required this.verticalInset,
  });

  factory DashboardLayout.forViewport(
    double width,
    double height, {
    required DashboardSize size,
  }) {
    const baseGap = 16.0;
    final columns = math.max(4, (width / 198).round());
    final cell = (width - baseGap * (columns - 1)) / columns;
    final rows = math.max(1, ((height + baseGap) / (cell + baseGap)).floor());
    if (size == DashboardSize.enlarged) {
      return DashboardLayout._(
        columns: columns,
        visibleRows: rows,
        cell: cell,
        gap: baseGap,
        scale: 1,
        width: width,
        height: height,
        verticalInset: 0,
      );
    }
    const gap = 9.6;
    final targetColumns = columns + 2, targetRows = rows + 1;
    final unit = math.min(
      (width - gap * (targetColumns - 1)) / targetColumns,
      (height - gap * (targetRows - 1)) / targetRows,
    );
    final canvasHeight = targetRows * unit + (targetRows - 1) * gap;
    return DashboardLayout._(
      columns: targetColumns,
      visibleRows: targetRows,
      cell: unit,
      gap: gap,
      scale: (2 * unit + gap) / (2 * cell + baseGap),
      width: targetColumns * unit + (targetColumns - 1) * gap,
      height: canvasHeight,
      verticalInset: math.max(0, (height - canvasHeight) / 2),
    );
  }

  double span(int cells) => cells * cell + (cells - 1) * gap;
}

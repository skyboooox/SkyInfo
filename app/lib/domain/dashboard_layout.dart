import 'dart:math' as math;

enum DashboardSize { standard, enlarged }

class DashboardLayout {
  final int columns, visibleRows;
  final double cell, gap, scale, width;

  const DashboardLayout._({
    required this.columns,
    required this.visibleRows,
    required this.cell,
    required this.gap,
    required this.scale,
    required this.width,
  });

  factory DashboardLayout.forViewport(
    double width,
    double height, {
    required DashboardSize size,
  }) {
    const gap = 16.0;
    final columns = math.max(4, (width / 198).round());
    final cell = (width - gap * (columns - 1)) / columns;
    final rows = math.max(1, ((height + gap) / (cell + gap)).floor());
    final standard = size == DashboardSize.standard;
    final targetColumns = columns + (standard ? 1 : 0);
    final targetRows = rows + (standard ? 1 : 0);
    final canvasWidth = targetColumns * (cell + gap) - gap;
    final canvasHeight = targetRows * (cell + gap) - gap;
    final scale = standard
        ? math.min(width / canvasWidth, height / canvasHeight)
        : 1.0;
    return DashboardLayout._(
      columns: targetColumns,
      visibleRows: targetRows,
      cell: cell * scale,
      gap: gap * scale,
      scale: scale,
      width: canvasWidth * scale,
    );
  }

  double span(int cells) => cells * cell + (cells - 1) * gap;
}

part of 'home.dart';

extension _Information on _HomeState {
  Widget information() {
    if (c.tiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Strings.text('text_ffc1aeb3ed'),
              style: TextStyle(color: Palette.of(context).muted),
            ),
            if (editing) ...[
              SizedBox(height: 24),
              button(
                Strings.text('add_component'),
                () => addTile(),
                primary: true,
                width: 160,
              ),
            ],
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth <= 0 || box.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        if (box.maxWidth < 760 && c.dashboardSize == DashboardSize.enlarged) {
          Widget item(int i) {
            final tile = c.tiles[i];
            final card = Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                height: math
                    .max(
                      tile.kind.history ? 320.0 : 182.0,
                      box.maxWidth * tile.rows / tile.columns,
                    )
                    .clamp(182.0, 720.0)
                    .toDouble(),
                child: MetricTile(
                  key: ValueKey(tile.id),
                  tile: tile,
                  controller: c,
                  now: now,
                  clock: DateTime.now,
                  editing: editing,
                  onEdit: () => addTile(tile),
                  onHistory: tile.kind.controls
                      ? null
                      : () => showHistoryDetails(
                          context,
                          c,
                          tile,
                          onEdit: () => addTile(tile),
                        ),
                ),
              ),
            );
            return KeyedSubtree(
              key: ValueKey('compact-${tile.id}'),
              child: editing
                  ? ReorderableDelayedDragStartListener(index: i, child: card)
                  : card,
            );
          }

          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: c.tiles.length,
            itemBuilder: (context, i) => item(i),
            onReorderItem: (a, b) async {
              if (!editing) return;
              final before = c.config;
              final tile = c.tiles.removeAt(a);
              c.tiles.insert(b, tile);
              for (var i = 0; i < c.tiles.length; i++) {
                c.tiles[i] = c.tiles[i].positioned(null, null);
              }
              if (!await save()) {
                c.restore(before);
                update(() {});
              }
            },
          );
        }
        final layout = DashboardLayout.forViewport(
          box.maxWidth,
          box.maxHeight,
          size: c.dashboardSize,
        );
        final columns = layout.columns;
        final cell = layout.cell;
        final gap = layout.gap;
        final slots = packTiles(c.tiles, columns);
        final rows = slots.map((s) => s.row + s.tile.rows).reduce(math.max);
        return SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                key: grid,
                width: layout.width,
                height: (rows + (editing ? 2 : 0)) * (cell + gap) - gap,
                child: Stack(
                  children: [
                    for (final slot in slots)
                      Positioned(
                        key: ValueKey('dashboard-slot-${slot.tile.id}'),
                        left: slot.column * (cell + gap),
                        top: slot.row * (cell + gap),
                        width: layout.span(slot.tile.columns),
                        height: layout.span(slot.tile.rows),
                        child: editableTile(
                          slot,
                          columns,
                          cell,
                          gap,
                          FittedBox(
                            fit: BoxFit.fill,
                            child: SizedBox(
                              width:
                                  layout.span(slot.tile.columns) / layout.scale,
                              height:
                                  layout.span(slot.tile.rows) / layout.scale,
                              child: TouchTargets(
                                visualScale: layout.scale,
                                child: MetricTile(
                                  key: ValueKey(slot.tile.id),
                                  tile: slot.tile,
                                  controller: c,
                                  now: now,
                                  clock: DateTime.now,
                                  editing: editing,
                                  onEdit: () => addTile(slot.tile),
                                  onHistory:
                                      !slot.tile.kind.controls &&
                                          slot.tile.fields.any(
                                            (id) => ![
                                              'text',
                                            ].contains(c.metric(id).encoding),
                                          )
                                      ? () => showHistoryDetails(
                                          context,
                                          c,
                                          slot.tile,
                                          onEdit: () => addTile(slot.tile),
                                          onConnection: connectionSettings,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget editableTile(
    GridSlot slot,
    int columns,
    double cell,
    double gap,
    Widget child,
  ) {
    if (!editing) return child;
    final tile = slot.tile;
    return Stack(
      children: [
        Positioned.fill(
          child: LongPressDraggable<TileSpec>(
            data: tile,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Material(
              color: Palette.of(context).acid,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(tile.title),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: child),
            onDragEnd: (details) {
              final box = grid.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(details.offset);
              final col = (local.dx / (cell + gap)).floor().clamp(
                0,
                columns - tile.columns,
              );
              final row = math.max(0, (local.dy / (cell + gap)).floor());
              final i = c.tiles.indexOf(tile);
              if (i < 0) return;
              final occupied = Rect.fromLTWH(
                col.toDouble(),
                row.toDouble(),
                tile.columns.toDouble(),
                tile.rows.toDouble(),
              );
              for (final existing in packTiles(c.tiles, columns)) {
                if (existing.tile.id != tile.id &&
                    occupied.overlaps(
                      Rect.fromLTWH(
                        existing.column.toDouble(),
                        existing.row.toDouble(),
                        existing.tile.columns.toDouble(),
                        existing.tile.rows.toDouble(),
                      ),
                    )) {
                  final j = c.tiles.indexOf(existing.tile);
                  c.tiles[j] = existing.tile.positioned(null, null);
                }
              }
              c.tiles[i] = tile.positioned(col, row);
              save();
            },
            child: child,
          ),
        ),
      ],
    );
  }
}

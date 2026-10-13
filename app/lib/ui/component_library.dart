import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../l10n/strings.dart';
import 'industrial.dart';
import 'layout.dart';
import 'design_dialog.dart';
import 'metric_tile.dart';
import 'preview_catalog.dart';
import 'component_compatibility.dart';
export 'preview_catalog.dart' show componentPresets, componentPreset;

Future<TileSpec?> choosePreset(BuildContext context, AppController c) =>
    showDesignDialog<TileSpec>(
      context: context,
      builder: (_) => DesignDialog(
        title: Strings.text('text_465a3062ea'),
        footer: Align(
          alignment: Alignment.centerRight,
          child: IndustrialButton(
            Strings.text('cancel'),
            kind: ButtonKind.quiet,
            width: 96,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        child: ListView(
          children: [
            for (final name in componentPresets)
              ParameterRow(
                name,
                key: ValueKey('library-$name'),
                trailing: const Icon(Icons.chevron_right, size: 24),
                onTap: () => Navigator.pop(context, componentPreset(name)),
              ),
          ],
        ),
      ),
    );

Future<WidgetKind?> chooseCompatibleComponent(
  BuildContext context,
  AppController c,
  TileSpec draft,
) => showDesignDialog<WidgetKind>(
  context: context,
  builder: (_) => _StyleDialog(c, draft),
);

class _StyleDialog extends StatefulWidget {
  final AppController c;
  final TileSpec draft;
  const _StyleDialog(this.c, this.draft);
  @override
  State<_StyleDialog> createState() => _StyleDialogState();
}

class _StyleDialogState extends State<_StyleDialog> {
  late WidgetKind selected = widget.draft.kind;
  @override
  Widget build(BuildContext context) => DesignDialog(
    title: Strings.text('choose_component'),
    footer: Row(
      children: [
        IndustrialButton(
          Strings.text('cancel'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
        const Spacer(),
        IndustrialButton(
          Strings.text('confirm_selection'),
          primary: true,
          width: 160,
          onPressed: () => Navigator.pop(context, selected),
        ),
      ],
    ),
    child: ComponentStyleSelector(
      controller: widget.c,
      draft: TileSpec.fromJson({
        ...widget.draft.toJson(),
        'kind': selected.name,
      }),
      onChanged: (kind) => setState(() => selected = kind),
    ),
  );
}

class ComponentStyleSelector extends StatelessWidget {
  final AppController controller;
  final TileSpec draft;
  final ValueChanged<WidgetKind> onChanged;
  const ComponentStyleSelector({
    super.key,
    required this.controller,
    required this.draft,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final compatible = compatibleKinds(controller, draft.fields);
    final p = Palette.of(context);
    final size = draft.kind.sizes.contains((draft.columns, draft.rows))
        ? (draft.columns, draft.rows)
        : (2, 2);
    final preview = TileSpec.fromJson({
      ...draft.toJson(),
      'columns': size.$1,
      'rows': size.$2,
    });
    return PreviewLayout(
      preview: Container(
        color: p.paper,
        padding: const EdgeInsets.all(24),
        child: LiveComponentPreview(controller: controller, tile: preview),
      ),
      parameters: ListView(
        children: [
          for (final kind in compatible)
            SelectionRow(
              kind.label,
              selected: kind == draft.kind,
              height: 80,
              onTap: () => onChanged(kind),
              trailing: const Icon(Icons.chevron_right, size: 24),
            ),
        ],
      ),
      previewWidth: 560,
      previewFirst: false,
    );
  }
}

class LiveComponentPreview extends StatefulWidget {
  final AppController controller;
  final TileSpec tile;
  const LiveComponentPreview({
    super.key,
    required this.controller,
    required this.tile,
  });
  @override
  State<LiveComponentPreview> createState() => _LiveComponentPreviewState();
}

class _LiveComponentPreviewState extends State<LiveComponentPreview> {
  late PreviewLease lease;
  @override
  void initState() {
    super.initState();
    lease = widget.controller.acquirePreview(widget.tile.fields);
  }

  @override
  void didUpdateWidget(LiveComponentPreview old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      lease.dispose();
      lease = widget.controller.acquirePreview(widget.tile.fields);
    } else {
      lease.update(widget.tile.fields);
    }
  }

  @override
  void dispose() {
    lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: widget.tile.columns * 198 - 16,
        height: widget.tile.rows * 198 - 16,
        child: MetricTile(
          tile: widget.tile,
          controller: widget.controller,
          now: DateTime.now(),
          preview: true,
          onEdit: () {},
        ),
      ),
    ),
  );
}

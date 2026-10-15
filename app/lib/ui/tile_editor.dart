import '../l10n/strings.dart';
import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import 'industrial.dart';
import 'design_dialog.dart';
import 'motion.dart';
import 'component_library.dart';
import 'icon_picker.dart';
import 'unit_picker.dart';
import 'history_dialog.dart';

import 'field_picker.dart';
import 'component_compatibility.dart';
import 'layout.dart';
import 'confirmation.dart';

part 'tile_configuration.dart';

Future<TileSpec?> editTile(
  BuildContext context,
  AppController c, {
  TileSpec? existing,
  Future<void> Function()? onDelete,
}) async {
  final seed =
      existing ??
      TileSpec(id: '', title: '', kind: WidgetKind.number, fields: []);
  return showDesignDialog<TileSpec>(
    context: context,
    builder: (_) => _TileEditor(c, existing, seed, onDelete),
  );
}

class _TileEditor extends StatefulWidget {
  final AppController c;
  final TileSpec? existing;
  final TileSpec seed;
  final Future<void> Function()? onDelete;
  const _TileEditor(this.c, this.existing, this.seed, this.onDelete);
  @override
  State<_TileEditor> createState() => _TileEditorState();
}

class _TileEditorState extends State<_TileEditor> {
  late final title = TextEditingController(text: widget.seed.title);
  late WidgetKind kind = widget.seed.kind;
  late List<String> fields = [...widget.seed.fields];
  late List<String> hiddenControls = [...widget.seed.hiddenControls];
  late (int, int) size = (widget.seed.columns, widget.seed.rows);
  late TimeDisplay time = widget.seed.time;
  late Map<String, String> icons = {...widget.seed.icons},
      units = {...widget.seed.units},
      labels = {...widget.seed.labels};
  late final minimum = TextEditingController(
    text: widget.seed.minimum?.toString() ?? '',
  );
  late final maximum = TextEditingController(
    text: widget.seed.maximum?.toString() ?? '',
  );
  late int digits = widget.seed.digits, minutes = widget.seed.historyMinutes;
  late String? componentIcon = widget.seed.icon;
  late double? fontSize = widget.seed.fontSize;
  late int glanceColumns = widget.seed.glanceColumns;
  late double rowHeight = widget.seed.rowHeight;
  late bool showTitle = widget.seed.showTitle,
      showUnits = widget.seed.showUnits,
      showIcon = widget.seed.showIcon && widget.seed.icon != null,
      showDataIcons = widget.seed.showDataIcons && widget.seed.icons.isNotEmpty;
  late final PreviewLease lease = widget.c.acquirePreview(fields);
  String? validation;
  late int step = widget.existing == null ? 0 : 2;
  int configurationTab = 1;
  bool deleting = false;
  final fieldFilters = FieldFilterState();
  @override
  void initState() {
    super.initState();
    lease;
  }

  @override
  void dispose() {
    lease.dispose();
    title.dispose();
    minimum.dispose();
    maximum.dispose();
    super.dispose();
  }

  void update(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    lease.update(fields);
  }

  Widget dropdown<T>(
    T value,
    List<T> list,
    String Function(T) label,
    ValueChanged<T> changed,
  ) => DropdownButton<T>(
    borderRadius: BorderRadius.zero,
    itemHeight: null,
    value: value,
    isExpanded: true,
    items: list
        .map((v) => DropdownMenuItem(value: v, child: Text(label(v))))
        .toList(),
    onChanged: (v) {
      if (v != null) changed(v);
    },
  );
  Future<void> chooseUnit(String id) async {
    final result = await chooseDisplayUnit(
      context,
      unit: units[id],
      reduceMotion: widget.c.reduceMotion,
    );
    if (result != null && mounted) {
      setState(() {
        if (result.unit == null) {
          units.remove(id);
        } else {
          units[id] = result.unit!;
        }
      });
    }
  }

  Future<void> chooseLabel(String id) async {
    final input = TextEditingController(
      text: labels[id] ?? widget.c.metric(id).name,
    );
    final label = await showDesignDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Strings.text('text_ac42511863')),
        content: TextField(controller: input),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Strings.text('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: Text(Strings.text('save')),
          ),
        ],
      ),
    );
    input.dispose();
    if (label != null && mounted) {
      setState(() {
        if (label.isEmpty) {
          labels.remove(id);
        } else {
          labels[id] = label;
        }
      });
    }
  }

  void submit() {
    if (fields.isEmpty || (kind == WidgetKind.pair && fields.length != 2)) {
      setState(
        () => validation = kind == WidgetKind.pair
            ? Strings.text('text_4fac808fa0')
            : Strings.text('text_2060790b08'),
      );
      return;
    }
    if ([
          WidgetKind.trend,
          WidgetKind.comparison,
          WidgetKind.range,
          WidgetKind.gauge,
        ].contains(kind) &&
        fields.any(
          (id) => ['enum', 'text'].contains(widget.c.metric(id).encoding),
        )) {
      setState(() => validation = Strings.text('text_c9eb168ddf'));
      return;
    }
    if (kind == WidgetKind.comparison &&
        !comparableFields(fields, widget.c.allMetrics)) {
      setState(() => validation = Strings.text('text_cf0ada21b6'));
      return;
    }
    if (!compatibleKinds(widget.c, fields).contains(kind)) {
      setState(() => validation = Strings.text('text_fa6982c219'));
      return;
    }
    final min = double.tryParse(minimum.text),
        max = double.tryParse(maximum.text);
    if ((kind == WidgetKind.range ||
            kind == WidgetKind.gauge ||
            minimum.text.trim().isNotEmpty ||
            maximum.text.trim().isNotEmpty) &&
        (min == null ||
            max == null ||
            !min.isFinite ||
            !max.isFinite ||
            max <= min)) {
      setState(() => validation = Strings.text('text_0e67ed1d4d'));
      return;
    }
    Navigator.pop(
      context,
      TileSpec(
        id:
            widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: title.text.trim().isEmpty
            ? widget.c.metric(fields.first).name
            : title.text.trim(),
        kind: kind,
        fields: fields,
        columns: size.$1,
        rows: size.$2,
        time: time,
        icons: {
          for (final id in fields)
            if (icons.containsKey(id)) id: icons[id]!,
        },
        units: {
          for (final id in fields)
            if (units.containsKey(id)) id: units[id]!,
        },
        digits: digits,
        minimum: min,
        maximum: max,
        historyMinutes: minutes,
        column: widget.seed.column,
        row: widget.seed.row,
        labels: {
          for (final id in fields)
            if (labels.containsKey(id)) id: labels[id]!,
        },
        icon: componentIcon,
        fontSize: fontSize,
        glanceColumns: glanceColumns,
        rowHeight: rowHeight,
        showTitle: showTitle,
        showUnits: showUnits,
        showIcon: showIcon,
        showDataIcons: showDataIcons,
        hiddenControls: hiddenControls.where(fields.contains).toList(),
      ),
    );
  }

  TileSpec get draft => TileSpec(
    id: widget.existing?.id ?? 'preview',
    title: title.text.trim().isEmpty
        ? fields.isEmpty
              ? kind.label
              : widget.c.metric(fields.first).name
        : title.text.trim(),
    kind: kind,
    fields: fields,
    columns: size.$1,
    rows: size.$2,
    time: time,
    icons: icons,
    units: units,
    labels: labels,
    icon: componentIcon,
    fontSize: fontSize,
    glanceColumns: glanceColumns,
    rowHeight: rowHeight,
    digits: digits,
    minimum: double.tryParse(minimum.text),
    maximum: double.tryParse(maximum.text),
    historyMinutes: minutes,
    showTitle: showTitle,
    showUnits: showUnits,
    showIcon: showIcon,
    showDataIcons: showDataIcons,
    hiddenControls: hiddenControls.where(fields.contains).toList(),
  );

  Future<void> selectFields() async {
    final r = await chooseFields(
      context,
      widget.c,
      fields,
      multiple: kind.multiple,
      filters: fieldFilters,
      entities: true,
    );
    if (r != null && mounted) {
      final previous = [...fields];
      update(() => fields = r);
      if (!compatibleKinds(widget.c, fields).contains(kind)) {
        final selected = await chooseCompatibleComponent(
          context,
          widget.c,
          draft,
        );
        if (!mounted) return;
        if (selected == null) {
          update(() => fields = previous);
        } else {
          setKind(selected);
        }
      }
    }
  }

  Widget preview() => Container(
    color: Palette.of(context).paper,
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          Strings.text('preview'),
          style: TextStyle(fontSize: 16, color: Palette.of(context).muted),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Motion(
            identity: (kind, size),
            child: LiveComponentPreview(controller: widget.c, tile: draft),
          ),
        ),
      ],
    ),
  );

  void setKind(WidgetKind value) => update(() {
    kind = value;
    if (!value.sizes.contains(size)) size = (2, 2);
  });
  void nextStep() => update(() {
    if (step == 0) {
      if (!compatibleKinds(widget.c, fields).contains(kind)) {
        kind = recommendedKind(widget.c, fields);
      }
      if (!kind.sizes.contains(size)) size = (2, 2);
    }
    step++;
  });
  Widget steps() => CreationSteps(
    active: step,
    labels: [
      Strings.text('select_data'),
      Strings.text('choose_component'),
      Strings.text('configure_component'),
    ],
  );
  @override
  Widget build(BuildContext context) => DesignDialog(
    title: widget.existing == null
        ? Strings.text(
            ['add_component', 'choose_component', 'configure_component'][step],
          )
        : Strings.text('edit_component'),
    footer: Row(
      children: [
        IndustrialButton(
          Strings.text('cancel'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
        if (widget.existing == null && step > 0) ...[
          const SizedBox(width: 16),
          IndustrialButton(
            Strings.text('back'),
            kind: ButtonKind.quiet,
            width: 96,
            onPressed: () => update(() => step--),
          ),
        ],
        Expanded(
          child: validation == null
              ? const SizedBox()
              : Text(
                  validation!,
                  style: TextStyle(color: Palette.of(context).red),
                ),
        ),
        if (widget.existing != null && widget.onDelete != null) ...[
          IndustrialButton(
            Strings.text('text_42527a1700'),
            kind: ButtonKind.danger,
            width: 160,
            onPressed: deleting
                ? null
                : () async {
                    setState(() => deleting = true);
                    final confirmed = await confirmRemoval(
                      context,
                      title: Strings.text('delete_component_title'),
                      message: Strings.text('delete_component_message', {
                        'name': widget.existing!.title,
                      }),
                    );
                    if (!mounted) return;
                    if (!confirmed) {
                      setState(() => deleting = false);
                      return;
                    }
                    try {
                      await widget.onDelete!();
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          deleting = false;
                          validation =
                              widget.c.error ?? Strings.text('save_failed');
                        });
                      }
                    }
                  },
          ),
          const SizedBox(width: 16),
        ],
        IndustrialButton(
          Strings.text(
            step < 2
                ? 'next'
                : widget.existing == null
                ? 'add_to_dashboard'
                : 'save_changes',
          ),
          primary: true,
          width: 192,
          onPressed: deleting || fields.isEmpty
              ? null
              : step < 2
              ? nextStep
              : submit,
        ),
      ],
    ),
    child: Column(
      children: [
        if (widget.existing == null) ...[steps(), const SizedBox(height: 12)],
        Expanded(
          child: Motion(
            identity: step,
            child: switch (step) {
              0 => FieldSelector(
                controller: widget.c,
                filters: fieldFilters,
                selected: fields,
                onChanged: (value) => update(() => fields = value),
                action: IndustrialButton(
                  Strings.text('use_preset'),
                  width: 160,
                  onPressed: () async {
                    final preset = await choosePreset(context, widget.c);
                    if (preset == null || !mounted) return;
                    update(() {
                      fields = [...preset.fields];
                      kind = preset.kind;
                      size = (preset.columns, preset.rows);
                      title.text = preset.title;
                      minutes = preset.historyMinutes;
                      minimum.text = preset.minimum?.toString() ?? '';
                      maximum.text = preset.maximum?.toString() ?? '';
                      step = 2;
                    });
                  },
                ),
              ),
              1 => ComponentStyleSelector(
                controller: widget.c,
                draft: draft,
                onChanged: setKind,
              ),
              _ => PreviewLayout(
                preview: preview(),
                parameters: configuration(),
              ),
            },
          ),
        ),
      ],
    ),
  );
}

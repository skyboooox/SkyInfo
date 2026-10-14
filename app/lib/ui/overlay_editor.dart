import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import 'industrial.dart';
import 'design_dialog.dart';
import 'icon_picker.dart';
import 'unit_picker.dart';
import 'field_picker.dart';
import 'overlay_preview.dart';
import 'confirmation.dart';

Future<OverlaySpec?> editOverlay(
  BuildContext context,
  AppController c, {
  OverlaySpec? existing,
  Future<void> Function()? onDelete,
}) async {
  final fields = existing == null
      ? await chooseFields(context, c, [], multiple: false)
      : [existing.field];
  if (fields == null || fields.isEmpty || !context.mounted) return null;
  return showDesignDialog<OverlaySpec>(
    context: context,
    builder: (_) => _OverlayEditor(c, existing, fields.first, onDelete),
  );
}

class _OverlayEditor extends StatefulWidget {
  final AppController c;
  final OverlaySpec? existing;
  final String field;
  final Future<void> Function()? onDelete;
  const _OverlayEditor(this.c, this.existing, this.field, this.onDelete);
  @override
  State<_OverlayEditor> createState() => _OverlayEditorState();
}

class _OverlayEditorState extends State<_OverlayEditor> {
  late String field = widget.field,
      icon = widget.existing?.icon ?? '',
      alignment = widget.existing?.alignment ?? 'center';
  late String? unit = widget.existing == null || widget.existing!.unitAuto
      ? null
      : widget.existing!.unit;
  late int digits = widget.existing?.digits ?? 1;
  bool deleting = false;
  String? error;
  late final lease = widget.c.acquirePreview([field]);
  @override
  void initState() {
    super.initState();
    lease;
  }

  @override
  void dispose() {
    lease.dispose();
    super.dispose();
  }

  OverlaySpec get draft => OverlaySpec(
    id: widget.existing?.id ?? 'preview',
    field: field,
    icon: icon,
    unit: unit ?? '',
    unitAuto: unit == null,
    alignment: alignment,
    digits: digits,
  );
  @override
  Widget build(BuildContext context) => DesignDialog(
    title: Strings.text(
      widget.existing == null ? 'text_962ebc86af' : 'text_41610ea654',
    ),
    footer: Row(
      children: [
        IndustrialButton(
          Strings.text('cancel'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 16),
        if (widget.onDelete != null)
          IndustrialButton(
            Strings.text('delete'),
            kind: ButtonKind.danger,
            width: 160,
            onPressed: deleting
                ? null
                : () async {
                    setState(() => deleting = true);
                    final confirmed = await confirmRemoval(
                      context,
                      title: Strings.text('delete_overlay_title'),
                      message: Strings.text('delete_overlay_message', {
                        'name': widget.c.metric(field).name,
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
                          error = widget.c.error ?? Strings.text('save_failed');
                        });
                      }
                    }
                  },
          ),
        Expanded(
          child: error == null
              ? const SizedBox.shrink()
              : Text(error!, style: TextStyle(color: Palette.of(context).red)),
        ),
        IndustrialButton(
          Strings.text('save'),
          primary: true,
          width: 160,
          onPressed: deleting
              ? null
              : () => Navigator.pop(
                  context,
                  OverlaySpec(
                    id:
                        widget.existing?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    field: field,
                    icon: icon,
                    unit: unit ?? '',
                    unitAuto: unit == null,
                    alignment: alignment,
                    digits: digits,
                  ),
                ),
        ),
      ],
    ),
    child: Column(
      children: [
        SizedBox(
          height: 96,
          child: Container(
            color: Palette.of(context).paper,
            child: OverlayStripPreview(
              controller: widget.c,
              modules: [
                ...widget.c.overlays.where((m) => m.id != widget.existing?.id),
                draft,
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              ParameterRow(
                Strings.text('data'),
                trailing: IndustrialButton(
                  widget.c.metric(field).name,
                  width: 280,
                  trailing: Icons.chevron_right,
                  onPressed: () async {
                    final value = await chooseFields(context, widget.c, [
                      field,
                    ]);
                    if (value != null && mounted) {
                      setState(() {
                        field = value.first;
                        unit = null;
                      });
                      lease.update(value);
                    }
                  },
                ),
              ),
              ParameterRow(
                Strings.text('text_87754d2484'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon.isNotEmpty) ...[
                      MetricIcon(icon),
                      const SizedBox(width: 16),
                    ],
                    IndustrialButton(
                      Strings.text('select_icon'),
                      width: 160,
                      trailing: Icons.chevron_right,
                      onPressed: () async {
                        final value = await chooseIcon(context, widget.c);
                        if (value != null && mounted) {
                          setState(() => icon = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              ParameterRow(
                Strings.text('text_8ec8c8c712'),
                trailing: IndustrialButton(
                  unit ?? widget.c.metric(field).displayUnit,
                  width: 160,
                  trailing: Icons.chevron_right,
                  onPressed: () async {
                    final value = await chooseDisplayUnit(context, unit: unit);
                    if (value != null && mounted) {
                      setState(() => unit = value.unit);
                    }
                  },
                ),
              ),
              ParameterRow(
                Strings.text('text_39df92f27c'),
                trailing: SizedBox(
                  width: 432,
                  child: ChoiceButtons<String>(
                    value: alignment,
                    values: const ['left', 'center', 'right'],
                    label: (value) => Strings.text(
                      {
                        'left': 'text_413f8db65f',
                        'center': 'text_5009324782',
                        'right': 'text_70fe40dec2',
                      }[value]!,
                    ),
                    onChanged: (value) => setState(() => alignment = value),
                  ),
                ),
              ),
              ParameterRow(
                Strings.text('text_75bf5c7a3e'),
                trailing: SizedBox(
                  width: 160,
                  child: DropdownButton<int>(
                    borderRadius: BorderRadius.zero,
                    itemHeight: null,
                    isExpanded: true,
                    value: digits,
                    items: [
                      for (final value in [0, 1, 2, 3, 4])
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: (value) => setState(() => digits = value!),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

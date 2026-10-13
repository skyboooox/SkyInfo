import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/ha_entity.dart';
import '../domain/models.dart';
import '../l10n/strings.dart';
import 'industrial.dart';
import 'attention.dart';
import 'design_dialog.dart';
import 'entity_content.dart' show commandLabel;

class HaEntityContent extends StatelessWidget {
  final AppController controller;
  final String id;
  final bool disabled, named, compact;
  final TileSpec tile;
  final DateTime now;
  const HaEntityContent({
    super.key,
    required this.controller,
    required this.id,
    required this.disabled,
    required this.tile,
    required this.now,
    this.named = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final entity = controller.haEntity(id);
    final p = Palette.of(context);
    final result = controller.commandResults.putIfAbsent(
      id,
      () => ValueNotifier(null),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        controller.reading(id),
        result,
      ]),
      builder: (context, _) {
        final sample = controller.reading(id).value;
        final blocked =
            disabled ||
            result.value == 'pending' ||
            controller.status['stopped'] == true ||
            controller.haImportState != 'connected' ||
            !controller.canOperateHa(id);
        final functions = id.split('|').length == 3
            ? entity?.functions ?? <HaFunction>[]
            : <HaFunction>[];
        final controlKind = {
          WidgetKind.toggle: 'toggle',
          WidgetKind.select: 'select',
          WidgetKind.action: 'button',
          WidgetKind.numberControl: 'number',
        }[tile.kind];
        final inlineFunction = functions
            .where((f) => controlKind == null || f.kind == controlKind)
            .firstOrNull;
        final unit = tile.showUnits
            ? controller.metric(id).displayUnitFor(sample, tile.units[id])
            : '';
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: named
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.grid)),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (named) ...[
                InkWell(
                  onTap: disabled
                      ? null
                      : () => showHaEntityDetails(context, controller, id),
                  child: Text(
                    tile.labels[id] ?? controller.metric(id).name,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: disabled
                          ? null
                          : () => showHaEntityDetails(context, controller, id),
                      child: Text(
                        '${sample.formatted(tile.digits)}${unit.isEmpty ? '' : ' $unit'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 24 : 36,
                          fontFamily: sample.value is num
                              ? 'IBMPlexMono'
                              : null,
                        ),
                      ),
                    ),
                  ),
                  if (inlineFunction != null &&
                      !tile.hiddenControls.contains(id) &&
                      tile.kind != WidgetKind.entity)
                    HaFunctionControl(
                      controller: controller,
                      id: id,
                      function: inlineFunction,
                      blocked: blocked,
                    ),
                  if (functions.length > 1 || tile.kind == WidgetKind.entity)
                    IndustrialIconButton(
                      icon: Icons.chevron_right,
                      tooltip: Strings.text('details'),
                      onPressed: disabled
                          ? null
                          : () => showHaEntityDetails(context, controller, id),
                    ),
                ],
              ),
              if (sample.quality != 'available')
                Text(
                  sample.qualityLabel,
                  style: TextStyle(fontSize: 16, color: p.muted),
                ),
              if (tile.time != TimeDisplay.none)
                Text(
                  relativeAge(
                    tile.time == TimeDisplay.updated
                        ? sample.updatedAt
                        : sample.changedAt,
                    now,
                  ),
                  style: TextStyle(fontSize: 16, color: p.muted),
                ),
              if (result.value != null)
                CommandFeedback(
                  status: result.value!,
                  label: commandLabel(result.value!),
                ),
            ],
          ),
        );
      },
    );
  }
}

class HaFunctionControl extends StatefulWidget {
  final AppController controller;
  final String id;
  final HaFunction function;
  final bool blocked, detail;
  const HaFunctionControl({
    super.key,
    required this.controller,
    required this.id,
    required this.function,
    required this.blocked,
    this.detail = false,
  });
  @override
  State<HaFunctionControl> createState() => _HaFunctionControlState();
}

class _HaFunctionControlState extends State<HaFunctionControl> {
  Object? target;
  Future<void> send(Object? value) async {
    final f = widget.function;
    var confirmed = false;
    if (f.confirmation) {
      confirmed =
          await showDesignDialog<bool>(
            context: context,
            builder: (context) => DesignDialog(
              title: Strings.text('ha_unlock_confirm'),
              width: 560,
              height: 260,
              footer: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IndustrialButton(
                    Strings.text('cancel'),
                    kind: ButtonKind.quiet,
                    width: 96,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                  IndustrialButton(
                    Strings.text(f.label),
                    kind: ButtonKind.danger,
                    width: 160,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
              child: const SizedBox(),
            ),
          ) ==
          true;
      if (!confirmed) return;
    }
    await widget.controller.haCommand(
      widget.id,
      f.key,
      value,
      confirmed: confirmed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.function;
    final sample = widget.controller.reading(widget.id).value;
    final current = f.expected == 'state'
        ? sample.value
        : widget.controller.haEntity(widget.id)?.attributes[f.expected];
    switch (f.kind) {
      case 'toggle':
        return IndustrialSwitch(
          value: sample.value == 'on',
          onChanged: widget.blocked ? null : send,
        );
      case 'select':
        return SizedBox(
          width: widget.detail ? 280 : 160,
          child: DropdownButtonFormField<String>(
            borderRadius: BorderRadius.zero,
            itemHeight: null,
            key: ValueKey((f.key, current, f.options.join('|'))),
            initialValue: f.options.contains(current)
                ? current as String
                : null,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            isExpanded: true,
            hint: Text(Strings.text('ha_select_option')),
            items: [
              for (final option in f.options)
                DropdownMenuItem(
                  value: option,
                  child: Text(
                    option,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: widget.blocked ? null : (value) => send(value),
          ),
        );
      case 'number':
        final actual = current is num
            ? current.toDouble()
            : double.tryParse('$current');
        final requested = (target as double?) ?? actual;
        final valid =
            requested != null &&
            requested >= f.minimum! &&
            requested <= f.maximum!;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final direction in [-1, 1]) ...[
              if (direction == 1 && widget.detail) ...[
                SizedBox(
                  width: 88,
                  child: Text(
                    valid
                        ? requested
                              .toStringAsFixed(2)
                              .replaceFirst(RegExp(r'\.?0+$'), '')
                        : '—',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'IBMPlexMono',
                      fontSize: 24,
                    ),
                  ),
                ),
              ],
              IndustrialIconButton(
                icon: direction < 0 ? Icons.remove : Icons.add,
                tooltip: direction < 0 ? '−' : '+',
                outlined: true,
                onPressed:
                    widget.blocked ||
                        !valid ||
                        requested + direction * f.step! < f.minimum! - 1e-8 ||
                        requested + direction * f.step! > f.maximum! + 1e-8
                    ? null
                    : () {
                        final next = double.parse(
                          (requested + direction * f.step!).toStringAsFixed(8),
                        );
                        if (widget.detail) {
                          setState(() => target = next);
                        } else {
                          send(next);
                        }
                      },
              ),
            ],
            if (widget.detail) ...[
              const SizedBox(width: 16),
              IndustrialButton(
                Strings.text('send'),
                width: 120,
                primary: true,
                onPressed: widget.blocked || !valid
                    ? null
                    : () => send(requested),
              ),
            ],
          ],
        );
      default:
        return IndustrialButton(
          Strings.text(f.label),
          width: 160,
          onPressed: widget.blocked ? null : () => send(null),
        );
    }
  }
}

Future<void> showHaEntityDetails(
  BuildContext context,
  AppController c,
  String id,
) =>
    showDesignDialog<void>(context: context, builder: (_) => _HaDetails(c, id));

class _HaDetails extends StatefulWidget {
  final AppController c;
  final String id;
  const _HaDetails(this.c, this.id);
  @override
  State<_HaDetails> createState() => _HaDetailsState();
}

class _HaDetailsState extends State<_HaDetails> {
  late final lease = widget.c.acquirePreview([widget.id]);
  @override
  void initState() {
    super.initState();
    lease;
    widget.c.refreshHaDirectory();
  }

  @override
  void dispose() {
    lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final id = widget.id;
    final result = c.commandResults.putIfAbsent(id, () => ValueNotifier(null));
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.reading(id), result]),
      builder: (context, _) {
        final entity = c.haEntity(id),
            sample = c.reading(id).value,
            p = Palette.of(context);
        final blocked =
            result.value == 'pending' ||
            c.status['stopped'] == true ||
            c.haImportState != 'connected' ||
            !c.canOperateHa(id) ||
            !c.tiles.any((t) => t.kind.controls && t.fields.contains(id));
        return DesignDialog(
          title: c.metric(id).name,
          width: 720,
          height: 720,
          footer: Align(
            alignment: Alignment.centerRight,
            child: IndustrialButton(
              Strings.text('close'),
              kind: ButtonKind.quiet,
              width: 96,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          child: ListView(
            children: [
              Text(
                '${sample.formatted(1)} ${c.metric(id).displayUnitFor(sample)}',
                style: const TextStyle(fontSize: 40),
              ),
              if (sample.quality != 'available')
                Text(sample.qualityLabel, style: TextStyle(color: p.muted)),
              if (result.value != null)
                CommandFeedback(
                  status: result.value!,
                  label: commandLabel(result.value!),
                ),
              const SizedBox(height: 24),
              if (entity != null && id.split('|').length == 3)
                for (final function in entity.functions)
                  ParameterRow(
                    Strings.text(function.label),
                    trailing: HaFunctionControl(
                      key: ValueKey(function.key),
                      controller: c,
                      id: id,
                      function: function,
                      blocked: blocked,
                      detail: true,
                    ),
                  ),
              ParameterRow(
                Strings.text('source'),
                trailing: const Text('Home Assistant'),
              ),
              ParameterRow(
                Strings.text('ha_entity_id'),
                trailing: Flexible(
                  child: Text(entity?.entityId ?? id.split('|').skip(2).first),
                ),
              ),
              if (entity?.device.isNotEmpty == true)
                ParameterRow(
                  Strings.text('ha_device'),
                  trailing: Flexible(child: Text(entity!.device)),
                ),
              if (entity?.area.isNotEmpty == true)
                ParameterRow(
                  Strings.text('ha_area'),
                  trailing: Text(entity!.area),
                ),
            ],
          ),
        );
      },
    );
  }
}

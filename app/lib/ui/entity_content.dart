import '../l10n/strings.dart';
import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../domain/control_entity.dart';
import 'design_dialog.dart';
import 'industrial.dart';
import 'attention.dart';
import 'ha_entity_content.dart';

class EntityContent extends StatelessWidget {
  final AppController controller;
  final TileSpec tile;
  final bool disabled;
  final DateTime now;
  const EntityContent({
    super.key,
    required this.controller,
    required this.tile,
    required this.disabled,
    required this.now,
  });
  @override
  Widget build(BuildContext context) {
    if (tile.fields.isEmpty) {
      return Center(child: Text(Strings.text('text_61992c0926')));
    }
    final multiple = tile.kind.multiple;
    final children = [
      for (final id in tile.fields)
        _EntityRow(
          controller: controller,
          id: id,
          tile: tile,
          disabled: disabled,
          now: now,
          compact: multiple || tile.rows == 1,
          named: multiple,
        ),
    ];
    if (tile.kind == WidgetKind.device) {
      return LayoutBuilder(
        builder: (context, box) => GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: box.maxWidth < 300
                ? 1
                : tile.glanceColumns.clamp(1, 2),
            mainAxisExtent: 200,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          children: children,
        ),
      );
    }
    return multiple
        ? ListView(children: children)
        : SingleChildScrollView(child: children.first);
  }
}

class _EntityRow extends StatelessWidget {
  final AppController controller;
  final String id;
  final TileSpec tile;
  final bool disabled, compact, named;
  final DateTime now;
  const _EntityRow({
    required this.controller,
    required this.id,
    required this.tile,
    required this.disabled,
    required this.now,
    required this.compact,
    required this.named,
  });
  @override
  Widget build(BuildContext context) {
    if (id.startsWith('ha|')) {
      return HaEntityContent(
        controller: controller,
        id: id,
        disabled: disabled,
        tile: tile,
        now: now,
        compact: compact,
        named: named,
      );
    }
    final p = Palette.of(context);
    final isControl = id.startsWith('control.');
    final entity = isControl ? controller.controlEntity(id) : null;
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.reading(id),
        if (isControl) controller.commandResults[id]!,
      ]),
      builder: (context, _) {
        final sample = controller.reading(id).value;
        final status = isControl ? controller.commandResults[id]!.value : null;
        final blocked =
            disabled ||
            status == 'pending' ||
            controller.status['stopped'] == true ||
            (entity != null &&
                !entity.inferred &&
                entity.capability != EntityCapability.button &&
                sample.value == null);
        final age = tile.time == TimeDisplay.none
            ? null
            : relativeAge(
                tile.time == TimeDisplay.updated
                    ? sample.updatedAt
                    : sample.changedAt,
                now,
              );
        final unit = tile.showUnits
            ? controller.metric(id).displayUnitFor(sample, tile.units[id])
            : '';
        final state = sample.formatted(tile.digits);
        return Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 12 : 8),
          decoration: named
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.grid)),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (named)
                Row(
                  children: [
                    if (tile.showDataIcons && tile.icons[id] != null) ...[
                      MetricIcon(tile.icons[id], size: 24),
                      SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        tile.labels[id] ?? controller.metric(id).name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ],
                ),
              if (named) SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$state${unit.isEmpty ? '' : ' $unit'}',
                      style: TextStyle(
                        fontFamily:
                            entity?.capability == EntityCapability.number ||
                                entity == null
                            ? 'IBMPlexMono'
                            : null,
                        fontSize: compact ? 24 : 36,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!tile.hiddenControls.contains(id) &&
                      entity?.capability == EntityCapability.toggle)
                    IndustrialSwitch(
                      value:
                          entity!.selectedValue(sample) ==
                          entity.options
                              .firstWhere((o) => o.label == Strings.text('on'))
                              .value,
                      onChanged: blocked
                          ? null
                          : (value) => controller.command(
                              id,
                              entity.options
                                  .firstWhere(
                                    (o) =>
                                        o.label ==
                                        (value
                                            ? Strings.text('on')
                                            : Strings.text('close')),
                                  )
                                  .value,
                            ),
                    ),
                  if (!tile.hiddenControls.contains(id) &&
                      entity?.capability == EntityCapability.number) ...[
                    for (final direction in [-1, 1])
                      IconButton(
                        tooltip: direction < 0 ? '−' : '+',
                        onPressed:
                            blocked ||
                                entity!.selectedValue(sample) == null ||
                                entity.options.indexWhere(
                                          (o) =>
                                              o.value ==
                                              entity.selectedValue(sample),
                                        ) +
                                        direction <
                                    0 ||
                                entity.options.indexWhere(
                                          (o) =>
                                              o.value ==
                                              entity.selectedValue(sample),
                                        ) +
                                        direction >=
                                    entity.options.length
                            ? null
                            : () => controller.command(
                                id,
                                entity
                                    .options[entity.options.indexWhere(
                                          (o) =>
                                              o.value ==
                                              entity.selectedValue(sample),
                                        ) +
                                        direction]
                                    .value,
                              ),
                        icon: Icon(direction < 0 ? Icons.remove : Icons.add),
                      ),
                  ] else if (!tile.hiddenControls.contains(id) &&
                      entity?.capability == EntityCapability.button &&
                      entity!.options.length == 1)
                    IndustrialButton(
                      entity.options.single.label,
                      width: 160,
                      height: 48,
                      primary: true,
                      reduceMotion: controller.reduceMotion,
                      onPressed: blocked
                          ? null
                          : () => controller.command(
                              id,
                              entity.options.single.value,
                            ),
                    )
                  else if (entity != null &&
                      entity.capability != EntityCapability.toggle)
                    IconButton(
                      key: ValueKey('entity-details-$id'),
                      tooltip: Strings.text('details'),
                      onPressed: disabled
                          ? null
                          : () => showEntityDetails(context, controller, id),
                      icon: Icon(Icons.chevron_right),
                    ),
                ],
              ),
              if (age != null)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    age,
                    style: TextStyle(fontSize: 16, color: p.muted),
                  ),
                ),
              if (entity?.inferred == true)
                Text(
                  Strings.text('unverified'),
                  style: TextStyle(fontSize: 16, color: p.muted),
                ),
              if (status != null)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: CommandFeedback(
                    status: status,
                    label: commandLabel(status),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String commandLabel(String status) => switch (status) {
  'pending' => Strings.text('text_c1b894480d'),
  'confirmed' => Strings.text('text_d9fea67ad2'),
  'accepted_unconfirmed' => Strings.text('text_afb62932a7'),
  'unsupported_environment' => Strings.text('text_994271b71d'),
  'unsupported_state' => Strings.text('text_46381e6aef'),
  'stopped' => Strings.text('text_036894a305'),
  'bridge_unavailable' => Strings.text('text_0b5941f778'),
  'stop_unconfirmed' => Strings.text('text_42ef8b15a8'),
  'partial_unconfirmed' ||
  'timeout_unconfirmed' => Strings.text('text_0642fa2988'),
  'disconnected' => Strings.text('ha_disconnected'),
  'permission' => Strings.text('ha_permission'),
  'unavailable' => Strings.text('ha_unavailable'),
  'invalid_value' => Strings.text('ha_invalid_value'),
  'confirmation_required' => Strings.text('ha_unlock_confirm'),
  'busy' => Strings.text('text_c1b894480d'),
  'not_added' => Strings.text('text_92ccb79dd6'),
  _ => Strings.text('text_9746cfc7d2'),
};

Future<void> showEntityDetails(
  BuildContext context,
  AppController controller,
  String id,
) => showDesignDialog<void>(
  context: context,
  builder: (_) => _EntityDetails(controller, id),
);

class _EntityDetails extends StatefulWidget {
  final AppController c;
  final String id;
  const _EntityDetails(this.c, this.id);
  @override
  State<_EntityDetails> createState() => _EntityDetailsState();
}

class _EntityDetailsState extends State<_EntityDetails> {
  int? selected;
  late final lease = widget.c.acquirePreview([widget.id]);
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

  @override
  Widget build(BuildContext context) {
    final entity = widget.c.controlEntity(widget.id);
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.c,
        widget.c.reading(widget.id),
        widget.c.commandResults[widget.id]!,
      ]),
      builder: (context, _) {
        final sample = widget.c.reading(widget.id).value;
        final busy = widget.c.commandResults[widget.id]!.value == 'pending';
        final blocked =
            busy ||
            widget.c.status['stopped'] == true ||
            !widget.c.tiles.any(
              (t) => t.kind.controls && t.fields.contains(widget.id),
            ) ||
            (!entity.inferred &&
                entity.capability != EntityCapability.button &&
                sample.value == null);
        return DesignDialog(
          title: entity.name,
          width: 720,
          height: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(sample.formatted(1), style: TextStyle(fontSize: 40)),
              if (entity.inferred) Text(Strings.text('unverified')),
              SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    for (final option in entity.options)
                      ParameterRow(
                        option.label,
                        trailing: XCheck(
                          value: selected == option.value,
                          onChanged: blocked
                              ? null
                              : (v) => setState(
                                  () => selected = v ? option.value : null,
                                ),
                        ),
                        onTap: blocked
                            ? null
                            : () => setState(() => selected = option.value),
                      ),
                  ],
                ),
              ),
              if (widget.c.commandResults[widget.id]!.value != null)
                CommandFeedback(
                  status: widget.c.commandResults[widget.id]!.value!,
                  label: commandLabel(
                    widget.c.commandResults[widget.id]!.value!,
                  ),
                ),
              SizedBox(height: 16),
              IndustrialButton(
                Strings.text('send'),
                primary: true,
                reduceMotion: widget.c.reduceMotion,
                onPressed: blocked || selected == null
                    ? null
                    : () => widget.c.command(widget.id, selected!),
              ),
            ],
          ),
        );
      },
    );
  }
}

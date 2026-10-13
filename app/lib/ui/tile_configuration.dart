part of 'tile_editor.dart';

extension _TileConfiguration on _TileEditorState {
  bool get hasControls => kind.controls && fields.any(widget.c.isControl);
  Widget configuration() => Column(
    children: [
      LayoutBuilder(
        builder: (context, box) {
          String label(int tab) => Strings.text(
            [
              'content',
              'appearance',
              hasControls ? 'entity_features' : 'data_settings',
            ][tab],
          );
          if (box.maxWidth < 700 ||
              MediaQuery.textScalerOf(context).scale(20) > 30) {
            return DropdownButtonFormField<int>(
              borderRadius: BorderRadius.zero,
              itemHeight: null,
              key: ValueKey(configurationTab),
              initialValue: configurationTab,
              isExpanded: true,
              items: [
                for (final tab in [0, 1, 2])
                  DropdownMenuItem(value: tab, child: Text(label(tab))),
              ],
              onChanged: (tab) {
                if (tab != null) update(() => configurationTab = tab);
              },
            );
          }
          return Row(
            children: [
              for (final tab in [0, 1, 2])
                IndustrialButton(
                  label(tab),
                  width: 144,
                  kind: configurationTab == tab
                      ? ButtonKind.selected
                      : ButtonKind.quiet,
                  onPressed: () => update(() => configurationTab = tab),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      Expanded(
        child: ListView(
          children: switch (configurationTab) {
            0 => [
              ParameterRow(
                Strings.text('data'),
                trailing: IndustrialButton(
                  Strings.text('select_data'),
                  width: 160,
                  trailing: Icons.chevron_right,
                  onPressed: selectFields,
                ),
              ),
              ParameterRow(
                Strings.text('component'),
                trailing: IndustrialButton(
                  kind.label,
                  width: 200,
                  trailing: Icons.chevron_right,
                  onPressed: () async {
                    final selected = await chooseCompatibleComponent(
                      context,
                      widget.c,
                      draft,
                    );
                    if (selected != null && mounted) setKind(selected);
                  },
                ),
              ),
              ParameterInput(
                controller: title,
                label: Strings.text('text_748d7dc7e3'),
                maxLength: 64,
                onChanged: (_) => update(() {}),
              ),
              if (fields.length > 1) ...[
                const SizedBox(height: 16),
                Text(
                  Strings.text('field_order'),
                  style: TextStyle(
                    fontSize: 18,
                    color: Palette.of(context).muted,
                  ),
                ),
                for (final id in fields)
                  ParameterRow(
                    labels[id] ?? widget.c.metric(id).name,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IndustrialIconButton(
                          icon: Icons.arrow_upward,
                          tooltip: Strings.text('text_e4490b3a2c'),
                          onPressed: fields.indexOf(id) == 0
                              ? null
                              : () => update(() {
                                  final i = fields.indexOf(id);
                                  fields.removeAt(i);
                                  fields.insert(i - 1, id);
                                }),
                        ),
                        IndustrialIconButton(
                          icon: Icons.edit_outlined,
                          tooltip: Strings.text('text_09109fb3b9'),
                          onPressed: () => chooseLabel(id),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
            1 => [
              ParameterRow(
                Strings.text('size'),
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final shape in kind.sizes)
                      IndustrialButton(
                        '${shape.$1} × ${shape.$2}',
                        key: ValueKey('size-${shape.$1}-${shape.$2}'),
                        content: GridShape(shape.$1, shape.$2),
                        width: 56,
                        kind: shape == size
                            ? ButtonKind.selected
                            : ButtonKind.quiet,
                        onPressed: () => update(() => size = shape),
                      ),
                  ],
                ),
              ),
              ParameterRow(
                Strings.text('text_87754d2484'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (componentIcon != null) ...[
                      MetricIcon(componentIcon, size: 24),
                      const SizedBox(width: 16),
                    ],
                    IndustrialButton(
                      Strings.text('select_icon'),
                      width: 160,
                      trailing: Icons.chevron_right,
                      onPressed: () async {
                        final icon = await chooseIcon(context, widget.c);
                        if (icon != null && mounted) {
                          update(() {
                            componentIcon = icon.isEmpty ? null : icon;
                            showIcon = icon.isNotEmpty;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              ParameterRow(
                Strings.text('time'),
                trailing: SizedBox(
                  width: 620,
                  child: ChoiceButtons<TimeDisplay>(
                    value: time,
                    values: TimeDisplay.values,
                    label: (value) => Strings.text(
                      [
                        'text_5c23be05d4',
                        'text_f8ca224e88',
                        'text_d62b45e808',
                      ][value.index],
                    ),
                    onChanged: (value) => update(() => time = value),
                  ),
                ),
              ),
              ParameterRow(
                Strings.text('display_options'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    option(
                      Strings.text('text_748d7dc7e3'),
                      showTitle,
                      (v) => update(() => showTitle = v),
                    ),
                    const SizedBox(width: 16),
                    option(
                      Strings.text('text_8ec8c8c712'),
                      showUnits,
                      (v) => update(() => showUnits = v),
                    ),
                  ],
                ),
              ),
            ],
            _ => [
              if (hasControls) ...[
                for (final id in fields.where((id) => !widget.c.isControl(id)))
                  ParameterRow(
                    labels[id] ?? widget.c.metric(id).name,
                    trailing: IndustrialButton(
                      units[id] ?? widget.c.metric(id).displayUnit,
                      width: 160,
                      trailing: Icons.chevron_right,
                      onPressed: () => chooseUnit(id),
                    ),
                  ),
                for (final id in fields.where(widget.c.isControl))
                  ParameterRow(
                    widget.c.metric(id).name,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          id.startsWith('ha|')
                              ? widget.c
                                        .haEntity(id)
                                        ?.functions
                                        .map((f) => Strings.text(f.label))
                                        .join(' / ') ??
                                    Strings.text('readonly')
                              : widget.c.controlEntity(id).capability.name,
                          style: TextStyle(
                            fontSize: 18,
                            color: Palette.of(context).muted,
                          ),
                        ),
                        const SizedBox(width: 24),
                        XCheck(
                          value: !hiddenControls.contains(id),
                          onChanged: (value) => update(() {
                            if (value) {
                              hiddenControls.remove(id);
                            } else {
                              hiddenControls.add(id);
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                for (final id in fields)
                  ParameterRow(
                    labels[id] ?? widget.c.metric(id).name,
                    trailing: IndustrialButton(
                      units[id] ?? widget.c.metric(id).displayUnit,
                      width: 160,
                      trailing: Icons.chevron_right,
                      onPressed: () => chooseUnit(id),
                    ),
                  ),
                ParameterRow(
                  Strings.text('text_75bf5c7a3e'),
                  trailing: SizedBox(
                    width: 200,
                    child: dropdown(
                      digits,
                      [0, 1, 2, 3, 4],
                      (value) => '$value',
                      (value) => update(() => digits = value),
                    ),
                  ),
                ),
                if (kind.history)
                  ParameterRow(
                    Strings.text('history_window'),
                    trailing: IndustrialButton(
                      Strings.text('text_db8d00ea5b', {'value0': minutes}),
                      width: 200,
                      trailing: Icons.chevron_right,
                      onPressed: () async {
                        final value = await chooseHistoryWindow(
                          context,
                          widget.c,
                          minutes,
                        );
                        if (value != null && mounted) {
                          update(() => minutes = value);
                        }
                      },
                    ),
                  ),
                if ([
                  WidgetKind.range,
                  WidgetKind.gauge,
                  WidgetKind.trend,
                  WidgetKind.comparison,
                ].contains(kind))
                  Row(
                    children: [
                      Expanded(
                        child: ParameterInput(
                          controller: minimum,
                          label: Strings.text('text_b311283033'),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => update(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ParameterInput(
                          controller: maximum,
                          label: Strings.text('text_820be8bca9'),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => update(() {}),
                        ),
                      ),
                    ],
                  ),
                if (kind.multiple)
                  for (final id in fields)
                    ParameterRow(
                      labels[id] ?? widget.c.metric(id).name,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icons[id] != null) ...[
                            MetricIcon(icons[id]),
                            const SizedBox(width: 16),
                          ],
                          IndustrialButton(
                            Strings.text('select_icon'),
                            width: 160,
                            onPressed: () async {
                              final icon = await chooseIcon(context, widget.c);
                              if (icon != null && mounted) {
                                update(() {
                                  if (icon.isEmpty) {
                                    icons.remove(id);
                                  } else {
                                    icons[id] = icon;
                                    showDataIcons = true;
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
              ],
              if (kind == WidgetKind.glance)
                ParameterRow(
                  Strings.text('text_067f80c392'),
                  trailing: SizedBox(
                    width: 160,
                    child: dropdown(
                      glanceColumns,
                      [2, 3],
                      (value) => '$value',
                      (value) => update(() => glanceColumns = value),
                    ),
                  ),
                ),
              if (kind == WidgetKind.list || kind == WidgetKind.availability)
                ParameterRow(
                  Strings.text('text_b534c8636c'),
                  trailing: SizedBox(
                    width: 160,
                    child: dropdown(
                      rowHeight,
                      [64.0, 84.0, 104.0],
                      (value) => '${value.toInt()}',
                      (value) => update(() => rowHeight = value),
                    ),
                  ),
                ),
            ],
          },
        ),
      ),
    ],
  );
  Widget option(String label, bool value, ValueChanged<bool> changed) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      XCheck(value: value, onChanged: changed),
      Text(label, style: const TextStyle(fontSize: 18)),
    ],
  );
}

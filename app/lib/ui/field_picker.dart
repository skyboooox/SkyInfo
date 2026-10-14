import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../l10n/strings.dart';
import 'industrial.dart';
import 'design_dialog.dart';
import 'field_details.dart';
import 'layout.dart';

part 'field_row.dart';
part 'field_toolbar.dart';

Future<List<String>?> chooseFields(
  BuildContext context,
  AppController c,
  List<String> current, {
  bool multiple = false,
  bool entities = false,
  FieldFilterState? filters,
}) => showDesignDialog<List<String>>(
  context: context,
  builder: (_) => _FieldsDialog(c, current, multiple, entities, filters),
);

class _FieldsDialog extends StatefulWidget {
  final AppController c;
  final List<String> initial;
  final bool multiple, entities;
  final FieldFilterState? filters;
  const _FieldsDialog(
    this.c,
    this.initial,
    this.multiple,
    this.entities,
    this.filters,
  );
  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late List<String> selected = [...widget.initial];
  @override
  Widget build(BuildContext context) => DesignDialog(
    title: Strings.text('select_data'),
    footer: Row(
      children: [
        IndustrialButton(
          Strings.text('cancel'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            Strings.text('selected_count', {'count': selected.length}),
          ),
        ),
        IndustrialButton(
          Strings.text('confirm_selection'),
          primary: true,
          width: 160,
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.pop(context, selected),
        ),
      ],
    ),
    child: FieldSelector(
      controller: widget.c,
      filters: widget.filters,
      selected: selected,
      multiple: widget.multiple,
      entities: widget.entities,
      onChanged: (value) => setState(() => selected = value),
    ),
  );
}

Future<void> browseEntities(BuildContext context, AppController c) =>
    showDesignDialog<void>(
      context: context,
      builder: (context) => DesignDialog(
        title: Strings.text('browse_entities'),
        footer: Align(
          alignment: Alignment.centerRight,
          child: IndustrialButton(
            Strings.text('close'),
            kind: ButtonKind.quiet,
            width: 96,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        child: FieldSelector(
          controller: c,
          selected: const [],
          initialSource: 'ha',
          readOnly: true,
          onChanged: (_) {},
        ),
      ),
    );

class FieldFilterState {
  String search = '', category = '', haFilter = 'type', source;
  bool selectedOnly = false;
  FieldFilterState({this.source = 'all'});
}

class FieldSelector extends StatefulWidget {
  final AppController controller;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool multiple, entities, readOnly;
  final String initialSource;
  final FieldFilterState? filters;
  final Widget? action;
  const FieldSelector({
    super.key,
    required this.controller,
    required this.selected,
    required this.onChanged,
    this.multiple = true,
    this.entities = true,
    this.action,
    this.readOnly = false,
    this.initialSource = 'all',
    this.filters,
  });
  @override
  State<FieldSelector> createState() => _FieldSelectorState();
}

class _FieldSelectorState extends State<FieldSelector> {
  late final filters =
      widget.filters ?? FieldFilterState(source: widget.initialSource);
  late final searchInput = TextEditingController(text: filters.search);
  final searchFieldKey = GlobalKey();
  String get search => filters.search;
  set search(String value) => filters.search = value;
  String get category => filters.category;
  set category(String value) => filters.category = value;
  String get haFilter => filters.haFilter;
  set haFilter(String value) => filters.haFilter = value;
  String get source => filters.source;
  set source(String value) => filters.source = value;
  bool get selectedOnly => filters.selectedOnly;
  set selectedOnly(bool value) => filters.selectedOnly = value;
  void changeFilters(VoidCallback action) {
    if (mounted) setState(action);
  }

  @override
  void dispose() {
    searchInput.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.refreshHaDirectory();
  }

  void select(String id) {
    final next = [...widget.selected];
    if (next.contains(id)) {
      next.remove(id);
    } else {
      if (!widget.multiple) next.clear();
      next.add(id);
    }
    widget.onChanged(next);
  }

  String group(Metric m) {
    if (!m.id.startsWith('ha|')) return m.category;
    final entity = widget.controller.haEntity(m.id);
    return switch (haFilter) {
      'area' =>
        entity?.area.isNotEmpty == true
            ? entity!.area
            : Strings.text('ha_unassigned'),
      'device' =>
        entity?.device.isNotEmpty == true
            ? entity!.device
            : Strings.text('ha_unassigned'),
      _ => entity?.domain ?? Strings.text('unknown'),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, p = Palette.of(context);
      final catalog = [
        ...c.metrics.where((m) => m.displayAllowed),
        if (widget.entities) ...c.controlEntities.map((e) => e.metric),
        ...c.haFields.values.where(
          (m) => m.id.split('|').length == 3 || widget.selected.contains(m.id),
        ),
      ];
      final sourced = catalog
          .where(
            (m) =>
                source == 'all' || (source == 'ha') == m.id.startsWith('ha|'),
          )
          .toList();
      final categories = {...sourced.map(group)}.toList();
      final selected = widget.selected;
      final list = sourced
          .where(
            (m) =>
                (!selectedOnly || selected.contains(m.id)) &&
                (search.isNotEmpty ||
                    category.isEmpty ||
                    group(m) == category) &&
                (m.name.toLowerCase().contains(search.toLowerCase()) ||
                    m.id.toLowerCase().contains(search.toLowerCase()) ||
                    c.haEntity(m.id)?.matches(search) == true),
          )
          .toList();
      return LayoutBuilder(
        builder: (context, box) {
          final compact =
              box.maxWidth < 1120 ||
              MediaQuery.textScalerOf(context).scale(20) > 30;
          return Column(
            children: [
              if (compact)
                (box.maxHeight < 320
                    ? denseToolbar(c, selected)
                    : compactToolbar(c, selected))
              else
                Row(
                  children: [
                    for (final item in ['all', 'vehicle', 'ha']) ...[
                      IndustrialButton(
                        item == 'ha'
                            ? 'Home Assistant'
                            : Strings.text(
                                item == 'all'
                                    ? 'all_sources'
                                    : 'vehicle_source',
                              ),
                        width: item == 'ha' ? 192 : 120,
                        kind: source == item
                            ? ButtonKind.selected
                            : ButtonKind.secondary,
                        onPressed: () => setState(() {
                          source = item;
                          category = '';
                        }),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: TextField(
                          key: searchFieldKey,
                          controller: searchInput,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, size: 24),
                            hintText: Strings.text('search_entities'),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (value) => setState(() => search = value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (!widget.readOnly)
                      IndustrialButton(
                        Strings.text('selected_count', {
                          'count': selected.length,
                        }),
                        width: 120,
                        kind: selectedOnly
                            ? ButtonKind.selected
                            : ButtonKind.secondary,
                        onPressed: () =>
                            setState(() => selectedOnly = !selectedOnly),
                      ),
                    if (widget.action != null) ...[
                      const SizedBox(width: 8),
                      widget.action!,
                    ],
                  ],
                ),
              if (source == 'ha' && !compact) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final filter in ['type', 'area', 'device']) ...[
                      IndustrialButton(
                        Strings.text('ha_$filter'),
                        width: 120,
                        kind: haFilter == filter
                            ? ButtonKind.selected
                            : ButtonKind.quiet,
                        onPressed: () => setState(() {
                          haFilter = filter;
                          category = '';
                        }),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    Text(
                      Strings.text('ha_status_${c.haImportState}'),
                      style: TextStyle(color: p.muted, fontSize: 16),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: CategoryPane<String>(
                  values: ['', ...categories],
                  selected: category,
                  label: (value) =>
                      value.isEmpty ? Strings.text('all_sources') : value,
                  count: (value) => value.isEmpty
                      ? sourced.length
                      : sourced.where((m) => group(m) == value).length,
                  onChanged: (value) => setState(() => category = value),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border.all(color: p.grid),
                    ),
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              Strings.text('no_results'),
                              style: TextStyle(color: p.muted),
                            ),
                          )
                        : ListView.builder(
                            key: PageStorageKey((
                              source,
                              category,
                              selectedOnly,
                              search,
                            )),
                            scrollCacheExtent: ScrollCacheExtent.pixels(0),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final m = list[index];
                              return _FieldRow(
                                key: ValueKey(m.id),
                                controller: c,
                                metric: m,
                                selected: selected.contains(m.id),
                                readOnly: widget.readOnly,
                                onSelect: () => widget.readOnly
                                    ? showFieldDetails(context, c, m.id)
                                    : select(m.id),
                                onDetails: () async {
                                  final binding = await showFieldDetails(
                                    context,
                                    c,
                                    m.id,
                                    chooseAttribute: !widget.readOnly,
                                  );
                                  if (binding != null && mounted) {
                                    final next = [...widget.selected];
                                    if (!widget.multiple) next.clear();
                                    if (!next.contains(binding)) {
                                      next.add(binding);
                                    }
                                    widget.onChanged(next);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ),
              ),
              if (selectedOnly && selected.length > 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(20) <= 20
                      ? 64
                      : MediaQuery.textScalerOf(context).scale(20) * 2.6 + 24,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    itemCount: selected.length,
                    onReorderItem: (a, b) {
                      final next = [...selected];
                      final item = next.removeAt(a);
                      next.insert(b, item);
                      widget.onChanged(next);
                    },
                    itemBuilder: (context, index) =>
                        ReorderableDragStartListener(
                          key: ValueKey(selected[index]),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IndustrialButton(
                              c.metric(selected[index]).name,
                              width: 200,
                              trailing: Icons.drag_indicator,
                              onPressed: () => select(selected[index]),
                            ),
                          ),
                        ),
                  ),
                ),
              ],
            ],
          );
        },
      );
    },
  );
}

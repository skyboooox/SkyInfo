part of 'field_picker.dart';

extension _FieldToolbar on _FieldSelectorState {
  Widget denseToolbar(AppController c, List<String> selected) => Row(
    children: [
      Expanded(
        child: TextField(
          key: searchFieldKey,
          controller: searchInput,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 24),
            hintText: Strings.text('search_entities'),
          ),
          onChanged: (value) => changeFilters(() => search = value),
        ),
      ),
      const SizedBox(width: 8),
      PopupMenuButton<String>(
        tooltip: Strings.text('selection_tools'),
        icon: const Icon(Icons.more_horiz, size: 24),
        onSelected: (value) {
          if (value == 'preset') {
            (widget.action as IndustrialButton).onPressed?.call();
            return;
          }
          changeFilters(() {
            if (value == 'selected') {
              selectedOnly = !selectedOnly;
            } else if (value.startsWith('group:')) {
              haFilter = value.substring(6);
              category = '';
            } else {
              source = value;
              category = '';
            }
          });
        },
        itemBuilder: (context) => [
          for (final item in ['all', 'vehicle', 'ha'])
            PopupMenuItem(
              value: item,
              child: Text(
                item == 'ha'
                    ? 'Home Assistant'
                    : Strings.text(
                        item == 'all' ? 'all_sources' : 'vehicle_source',
                      ),
              ),
            ),
          if (!widget.readOnly)
            PopupMenuItem(
              value: 'selected',
              child: Text(
                Strings.text('selected_count', {'count': selected.length}),
              ),
            ),
          if (widget.action is IndustrialButton)
            PopupMenuItem(
              value: 'preset',
              child: Text((widget.action as IndustrialButton).label),
            ),
          if (source == 'ha')
            for (final filter in ['type', 'area', 'device'])
              PopupMenuItem(
                value: 'group:$filter',
                child: Text(Strings.text('ha_$filter')),
              ),
        ],
      ),
    ],
  );

  Widget compactToolbar(AppController c, List<String> selected) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              borderRadius: BorderRadius.zero,
              itemHeight: null,
              key: ValueKey(source),
              initialValue: source,
              isExpanded: true,
              decoration: InputDecoration(labelText: Strings.text('source')),
              items: [
                for (final item in ['all', 'vehicle', 'ha'])
                  DropdownMenuItem(
                    value: item,
                    child: Text(
                      item == 'ha'
                          ? 'HA'
                          : Strings.text(
                              item == 'all' ? 'all_sources' : 'vehicle_source',
                            ),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  changeFilters(() {
                    source = value;
                    category = '';
                  });
                }
              },
            ),
          ),
          if (!widget.readOnly) ...[
            const SizedBox(width: 8),
            IndustrialIconButton(
              icon: Icons.filter_list,
              tooltip: Strings.text('selected_count', {
                'count': selected.length,
              }),
              selected: selectedOnly,
              outlined: true,
              onPressed: () =>
                  changeFilters(() => selectedOnly = !selectedOnly),
            ),
          ],
          if (widget.action is IndustrialButton) ...[
            const SizedBox(width: 8),
            IndustrialIconButton(
              icon: Icons.dashboard_customize_outlined,
              tooltip: (widget.action as IndustrialButton).label,
              outlined: true,
              onPressed: (widget.action as IndustrialButton).onPressed,
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: searchFieldKey,
        controller: searchInput,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 24),
          hintText: Strings.text('search_entities'),
        ),
        onChanged: (value) => changeFilters(() => search = value),
      ),
      if (source == 'ha') ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                borderRadius: BorderRadius.zero,
                itemHeight: null,
                key: ValueKey(haFilter),
                initialValue: haFilter,
                isExpanded: true,
                items: [
                  for (final filter in ['type', 'area', 'device'])
                    DropdownMenuItem(
                      value: filter,
                      child: Text(Strings.text('ha_$filter')),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    changeFilters(() {
                      haFilter = value;
                      category = '';
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                Strings.text('ha_status_${c.haImportState}'),
                maxLines: 2,
                style: TextStyle(
                  fontSize: 16,
                  color: Palette.of(context).muted,
                ),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}

part of 'home.dart';

extension _Connection on _HomeState {
  Widget connectionPage() {
    uploadDraft ??= {...c.uploaded};
    final selected = uploadDraft!;
    final dirty =
        selected.length != c.uploaded.length ||
        !selected.containsAll(c.uploaded);
    final p = Palette.of(context);
    final categories = {...c.metrics.map((m) => m.category)}.toList();
    final filtered = c.metrics
        .where(
          (m) =>
              (search.isNotEmpty ||
                  category == Strings.text('text_83ada17910') ||
                  category == m.category) &&
              (!selectedOnly || selected.contains(m.id)) &&
              (m.name.toLowerCase().contains(search.toLowerCase()) ||
                  m.id.toLowerCase().contains(search.toLowerCase())),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, box) {
        final compact =
            box.maxWidth < 1000 ||
            MediaQuery.textScalerOf(context).scale(20) > 30;
        return Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.grid),
              ),
              child: ResponsiveToolbar(
                children: [
                  if (!compact)
                    Text(
                      Strings.text('ha_entities'),
                      style: const TextStyle(fontSize: 24),
                    ),
                  const SizedBox(width: 24),
                  if (!compact)
                    Text(
                      Strings.text('dashboard_overlay'),
                      style: TextStyle(fontSize: 16, color: p.muted),
                    ),
                  const Spacer(),
                  Text(
                    Strings.text('ha_status_${c.haImportState}'),
                    style: TextStyle(fontSize: 18, color: p.muted),
                  ),
                  const SizedBox(width: 24),
                  IndustrialButton(
                    Strings.text('browse_entities'),
                    width: 160,
                    trailing: Icons.chevron_right,
                    onPressed: () => browseEntities(context, c),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 24),
                        hintText: Strings.text('text_2856cf5d5c'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) => update(() => search = value),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                if (compact)
                  IndustrialIconButton(
                    icon: Icons.filter_list,
                    tooltip: Strings.text('only_selected'),
                    selected: selectedOnly,
                    outlined: true,
                    onPressed: () => update(() => selectedOnly = !selectedOnly),
                  )
                else
                  IndustrialButton(
                    Strings.text('only_selected'),
                    width: 160,
                    kind: selectedOnly
                        ? ButtonKind.selected
                        : ButtonKind.secondary,
                    onPressed: () => update(() => selectedOnly = !selectedOnly),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: CategoryPane<String>(
                values: [Strings.text('text_83ada17910'), ...categories],
                selected: category,
                label: (value) => value,
                count: (value) => value == Strings.text('text_83ada17910')
                    ? c.metrics.length
                    : c.metrics.where((m) => m.category == value).length,
                onChanged: (value) => update(() => category = value),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border.all(color: p.grid),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 64,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                Strings.text('text_fdb4bf21fa'),
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            Text(
                              Strings.text('follow_vehicle_updates'),
                              style: TextStyle(fontSize: 18, color: p.muted),
                            ),
                            const SizedBox(width: 24),
                            Text(
                              '${filtered.length}',
                              style: TextStyle(fontSize: 16, color: p.muted),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final m = filtered[index];
                            return Container(
                              height: 80,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: p.grid),
                                ),
                              ),
                              child: Row(
                                children: [
                                  XCheck(
                                    value: selected.contains(m.id),
                                    onChanged: (value) => update(
                                      () => value
                                          ? selected.add(m.id)
                                          : selected.remove(m.id),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => update(
                                        () => selected.contains(m.id)
                                            ? selected.remove(m.id)
                                            : selected.add(m.id),
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          m.name,
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: compact ? 64 : 200,
                                    child: Text(
                                      m.displayUnit,
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: p.muted,
                                      ),
                                    ),
                                  ),
                                  IndustrialIconButton(
                                    icon: Icons.chevron_right,
                                    tooltip: Strings.text('details'),
                                    onPressed: () =>
                                        showFieldDetails(context, c, m.id),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ResponsiveToolbar(
              children: [
                Expanded(
                  child: Text(
                    Strings.text('selected_count', {'count': selected.length}),
                    style: TextStyle(fontSize: 16, color: p.muted),
                  ),
                ),
                IndustrialButton(
                  Strings.text('discard_changes'),
                  width: 160,
                  onPressed: dirty
                      ? () => update(() => uploadDraft = {...c.uploaded})
                      : null,
                ),
                const SizedBox(width: 16),
                IndustrialButton(
                  Strings.text('save_upload_selection'),
                  primary: true,
                  width: 192,
                  onPressed: dirty
                      ? () async {
                          final before = {...c.uploaded};
                          c.uploaded = {...selected};
                          if (!await c.save()) {
                            c.uploaded = before;
                          }
                          if (mounted) update(() {});
                        }
                      : null,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

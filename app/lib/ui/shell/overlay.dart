part of 'home.dart';

extension _Overlay on _HomeState {
  Widget overlayPreview() =>
      OverlayStripPreview(controller: c, modules: c.overlays);

  Widget overlayPage() => Column(
    children: [
      SizedBox(
        height: 112,
        child: Panel(
          title: Strings.text('text_de61aa8e1c'),
          child: overlayPreview(),
        ),
      ),
      SizedBox(height: 16),
      Expanded(
        child: Panel(
          title: Strings.text('text_c1bebd4ab3'),
          action: TextButton(
            onPressed: () {
              update(() {
                page = 3;
                settingsTab = 2;
              });
            },
            child: Text(Strings.text('text_d056ee5616')),
          ),
          child: c.overlays.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Strings.text('text_05a1b9eab5'),
                        style: TextStyle(color: Palette.of(context).muted),
                      ),
                      SizedBox(height: 24),
                      button(
                        Strings.text('text_962ebc86af'),
                        () => addOverlay(),
                        primary: true,
                        width: 160,
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: c.overlays.length,
                  onReorderItem: (a, b) {
                    final m = c.overlays.removeAt(a);
                    c.overlays.insert(b, m);
                    save();
                  },
                  itemBuilder: (context, i) {
                    final m = c.overlays[i];
                    return ParameterRow(
                      key: ValueKey(m.id),
                      c.metric(m.field).name,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m.icon.isNotEmpty) ...[
                            MetricIcon(m.icon),
                            const SizedBox(width: 12),
                          ],
                          Flexible(
                            child: ValueListenableBuilder<Sample>(
                              valueListenable: c.reading(m.field),
                              builder: (context, sample, _) {
                                final unit = c
                                    .metric(m.field)
                                    .displayUnitFor(
                                      sample,
                                      m.unitAuto ? null : m.unit,
                                    );
                                return Text(
                                  '${sample.formatted(m.digits)}${unit.isEmpty ? '' : ' $unit'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'IBMPlexMono',
                                    fontSize: 20,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          IndustrialIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: Strings.text('edit_overlay'),
                            onPressed: () => addOverlay(m),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    ],
  );
}

part of 'split_screen.dart';

Future<SplitApp?> pickSplitApp(
  BuildContext context,
  SplitCatalog catalog,
  SplitTarget? selected,
) => showDesignDialog<SplitApp>(
  context: context,
  builder: (_) => _SplitAppPicker(catalog: catalog, selected: selected),
);

class _SplitAppPicker extends StatefulWidget {
  final SplitCatalog catalog;
  final SplitTarget? selected;
  const _SplitAppPicker({required this.catalog, this.selected});
  @override
  State<_SplitAppPicker> createState() => _SplitAppPickerState();
}

class _SplitAppPickerState extends State<_SplitAppPicker> {
  String search = '';
  SplitApp? selected;
  SplitCatalog get catalog => widget.catalog;
  @override
  void initState() {
    super.initState();
    selected = catalog.app(widget.selected);
    catalog.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    catalog.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = catalog.apps
        .where((e) => e.label.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return DesignDialog(
      title: splitText('select_app'),
      width: 880,
      footer: Row(
        children: [
          const Spacer(),
          IndustrialButton(
            Strings.text('cancel'),
            width: 96,
            kind: ButtonKind.quiet,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          IndustrialButton(
            splitText('select'),
            width: 160,
            primary: true,
            onPressed:
                selected == null || catalog.loading || catalog.error != null
                ? null
                : () => Navigator.pop(context, selected),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              labelText: splitText('search_app'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => search = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: catalog.loading
                ? Center(
                    child: Semantics(
                      label: splitText('loading'),
                      child: const CircularProgressIndicator(),
                    ),
                  )
                : catalog.error != null
                ? SingleChildScrollView(
                    child: SplitNotice(
                      message: splitText('query_failed'),
                      onRetry: () => catalog.refresh([widget.selected]),
                    ),
                  )
                : matches.isEmpty
                ? Center(
                    child: Text(
                      splitText(
                        catalog.apps.isEmpty ? 'no_apps' : 'no_results',
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: Palette.of(context).grid),
                    itemBuilder: (context, index) {
                      final app = matches[index];
                      return SelectionRow(
                        app.label,
                        selected: selected?.packageName == app.packageName,
                        height: 64,
                        onTap: () => setState(() => selected = app),
                        trailing: app.iconBytes == null
                            ? null
                            : Image.memory(
                                app.iconBytes!,
                                width: 32,
                                height: 32,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.apps),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Future<SplitActivity?> pickSplitActivity(
  BuildContext context,
  SplitCatalog catalog,
  SplitTarget target,
) => showDesignDialog<SplitActivity>(
  context: context,
  builder: (_) => _SplitActivityPicker(catalog: catalog, target: target),
);

class _SplitActivityPicker extends StatefulWidget {
  final SplitCatalog catalog;
  final SplitTarget target;
  const _SplitActivityPicker({required this.catalog, required this.target});
  @override
  State<_SplitActivityPicker> createState() => _SplitActivityPickerState();
}

class _SplitActivityPickerState extends State<_SplitActivityPicker> {
  List<SplitActivity> activities = [];
  SplitActivity? selected;
  bool loading = true, failed = false;
  String search = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final list = await widget.catalog.loadActivities(
        widget.target.packageName,
      );
      if (!mounted) return;
      setState(() {
        activities = list;
        loading = false;
        for (final entry in list) {
          if ((widget.target.activityName != null &&
                  splitActivityName(
                        widget.target.packageName,
                        entry.activityName,
                      ) ==
                      splitActivityName(
                        widget.target.packageName,
                        widget.target.activityName!,
                      )) ||
              (widget.target.activityName == null && entry.isDefault)) {
            selected = entry;
          }
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = activities
        .where(
          (e) => '${e.label} ${e.activityName}'.toLowerCase().contains(
            search.toLowerCase(),
          ),
        )
        .toList();
    return DesignDialog(
      title: splitText('select_activity'),
      width: 960,
      footer: Row(
        children: [
          const Spacer(),
          IndustrialButton(
            Strings.text('cancel'),
            width: 96,
            kind: ButtonKind.quiet,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          IndustrialButton(
            splitText('select'),
            width: 160,
            primary: true,
            onPressed: selected?.available != true || loading || failed
                ? null
                : () => Navigator.pop(context, selected),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              labelText: splitText('search_activity'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => search = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : failed
                ? SingleChildScrollView(
                    child: SplitNotice(
                      message: splitText('query_failed'),
                      onRetry: load,
                    ),
                  )
                : matches.isEmpty
                ? Center(
                    child: Text(
                      splitText(
                        activities.isEmpty ? 'no_activities' : 'no_results',
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final entry = matches[index], p = Palette.of(context);
                      return Semantics(
                        selected: selected?.activityName == entry.activityName,
                        enabled: entry.available,
                        child: Material(
                          color: selected?.activityName == entry.activityName
                              ? p.field
                              : Colors.transparent,
                          child: InkWell(
                            onTap: entry.available
                                ? () => setState(() => selected = entry)
                                : null,
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 80),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    width: 2,
                                    color:
                                        selected?.activityName ==
                                            entry.activityName
                                        ? p.acid
                                        : Colors.transparent,
                                  ),
                                  bottom: BorderSide(color: p.grid),
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${entry.label}${entry.isDefault ? ' · ${splitText('default_entry')}' : ''}',
                                    style: TextStyle(
                                      color: entry.available ? p.ink : p.muted,
                                    ),
                                  ),
                                  Text(
                                    '${entry.packageName}/${entry.activityName}',
                                    style: TextStyle(
                                      fontFamily: 'IBMPlexMono',
                                      fontSize: 14,
                                      color: p.muted,
                                    ),
                                  ),
                                  if (!entry.available)
                                    Text(
                                      splitReason(entry.reason),
                                      style: TextStyle(
                                        color: p.red,
                                        fontSize: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

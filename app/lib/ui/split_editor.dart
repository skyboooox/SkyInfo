part of 'split_screen.dart';

class SplitComboEditor extends StatefulWidget {
  final AppController controller;
  final SplitCatalog catalog;
  final SplitCombo? existing;
  const SplitComboEditor({
    super.key,
    required this.controller,
    required this.catalog,
    this.existing,
  });
  @override
  State<SplitComboEditor> createState() => _SplitComboEditorState();
}

class _SplitComboEditorState extends State<SplitComboEditor> {
  late final draft = widget.existing == null
      ? SplitDraft()
      : SplitDraft.fromCombo(widget.existing!);
  late final name = TextEditingController(text: draft.name);
  late final initial = signature;
  bool pending = false, allowPop = false;
  String? error;
  SplitCatalog get catalog => widget.catalog;
  String get signature => [
    draft.name,
    draft.ratio,
    draft.advanced,
    draft.left?.toJson(),
    draft.right?.toJson(),
  ].join('|');
  bool get dirty => signature != initial;
  @override
  void initState() {
    super.initState();
    initial;
    catalog.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    catalog.removeListener(changed);
    name.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (pending) return;
    if (dirty &&
        !await confirmAction(
          context,
          title: splitText('discard_title'),
          message: splitText('discard_message'),
          action: splitText('discard'),
          dismiss: splitText('continue_edit'),
        )) {
      return;
    }
    if (mounted) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    }
  }

  Future<void> pick(bool left) async {
    final app = await pickSplitApp(
      context,
      catalog,
      left ? draft.left : draft.right,
    );
    if (app != null && mounted) {
      setState(() {
        draft.select(left, app.target);
        error = null;
      });
      try {
        await catalog.loadActivities(app.packageName);
      } catch (_) {
        /* The selected side exposes the query error and retry. */
      }
      changed();
    }
  }

  Future<void> activity(bool left) async {
    final target = left ? draft.left : draft.right;
    if (target == null || pending) return;
    final entry = await pickSplitActivity(context, catalog, target);
    if (entry != null && mounted) {
      setState(() {
        if (left) {
          draft.left = target.withActivity(entry.activityName);
        } else {
          draft.right = target.withActivity(entry.activityName);
        }
        error = null;
      });
    }
  }

  Future<void> save() async {
    if (pending || !draft.complete) return;
    setState(() {
      pending = true;
      error = null;
    });
    await catalog.refresh([draft.left, draft.right]);
    if (!mounted) return;
    final leftError = catalog.invalid(draft.left),
        rightError = catalog.invalid(draft.right);
    if (leftError != null || rightError != null) {
      setState(() {
        pending = false;
        error =
            '${splitText(leftError != null ? 'left' : 'right')}：${splitReason(leftError ?? rightError)}';
      });
      return;
    }
    final combo = draft.snapshot(
      'split-${DateTime.now().microsecondsSinceEpoch}',
    );
    final combos = [...widget.controller.splitCombos];
    final index = combos.indexWhere((e) => e.id == combo.id);
    if (index >= 0) {
      combos[index] = combo;
    } else {
      combos.add(combo);
    }
    final saved = await widget.controller.saveSplitPreferences(combos: combos);
    if (!mounted) return;
    if (saved) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    } else {
      setState(() {
        pending = false;
        error = splitText('save_failed');
      });
    }
  }

  Future<void> delete() async {
    if (pending || widget.existing == null) return;
    if (!await confirmRemoval(
      context,
      title: splitText('delete_title'),
      message: Strings.text('split_delete_message', {
        'name': widget.existing!.name,
      }),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      pending = true;
      error = null;
    });
    final saved = await widget.controller.saveSplitPreferences(
      combos: widget.controller.splitCombos
          .where((e) => e.id != widget.existing!.id)
          .toList(),
    );
    if (!mounted) return;
    if (saved) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    } else {
      setState(() {
        pending = false;
        error = splitText('save_failed');
      });
    }
  }

  Widget appRow(bool left) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SplitAppButton(
        catalog: catalog,
        target: left ? draft.left : draft.right,
        label: splitText(left ? 'left_app' : 'right_app'),
        onTap: pending ? null : () => pick(left),
      ),
      if (!catalog.loading &&
          (left ? draft.left : draft.right) != null &&
          catalog.invalid(left ? draft.left : draft.right) != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${splitText(left ? 'left' : 'right')}：${splitReason(catalog.invalid(left ? draft.left : draft.right))}',
            style: TextStyle(color: Palette.of(context).red, fontSize: 16),
          ),
        ),
    ],
  );
  Widget activityRow(bool left) {
    final target = left ? draft.left : draft.right;
    return ParameterRow(
      splitText(left ? 'left_entry' : 'right_entry'),
      trailing: SizedBox(
        width: 360,
        child: IndustrialButton(
          target?.activityName ?? splitText('default_entry'),
          onPressed: target == null || pending ? null : () => activity(left),
        ),
      ),
    );
  }

  Widget preview(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        splitText('preview'),
        style: TextStyle(color: Palette.of(context).muted, fontSize: 18),
      ),
      const SizedBox(height: 16),
      if (wide)
        Expanded(
          child: SplitArea(
            catalog: catalog,
            draft: draft,
            onSelect: pending ? null : pick,
          ),
        )
      else
        SizedBox(
          height: 240,
          child: SplitArea(
            catalog: catalog,
            draft: draft,
            onSelect: pending ? null : pick,
          ),
        ),
      const SizedBox(height: 24),
      SplitRatioButtons(
        ratio: draft.ratio,
        onChanged: pending
            ? null
            : (value) => setState(() => draft.ratio = value),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              splitText('ratio_hint'),
              style: TextStyle(color: Palette.of(context).muted, fontSize: 16),
            ),
          ),
          IndustrialButton(
            splitText('swap'),
            width: 176,
            kind: ButtonKind.quiet,
            onPressed: pending ? null : () => setState(draft.swap),
          ),
        ],
      ),
    ],
  );
  Widget parameters() => Container(
    color: Palette.of(context).surface,
    padding: const EdgeInsets.all(16),
    child: ListView(
      children: [
        TextField(
          controller: name,
          enabled: !pending,
          maxLength: 128,
          decoration: InputDecoration(
            labelText: splitText('name'),
            hintText: splitText('name_hint'),
            counterText: '',
          ),
          onChanged: (value) => setState(() => draft.name = value),
        ),
        const SizedBox(height: 16),
        appRow(true),
        const SizedBox(height: 8),
        appRow(false),
        const SizedBox(height: 16),
        ParameterRow(
          Strings.text('advanced'),
          trailing: IndustrialSwitch(
            value: draft.advanced,
            onChanged: pending
                ? (_) {}
                : (value) => setState(() => draft.setAdvanced(value)),
          ),
          labelAction: Flexible(
            child: Text(
              splitText('specify_activity'),
              style: TextStyle(color: Palette.of(context).muted, fontSize: 16),
            ),
          ),
        ),
        if (draft.advanced) ...[
          activityRow(true),
          activityRow(false),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              splitText('default_hint'),
              style: TextStyle(color: Palette.of(context).muted, fontSize: 16),
            ),
          ),
        if (catalog.error != null)
          SplitNotice(
            message: splitText('query_failed'),
            onRetry: () => catalog.refresh([draft.left, draft.right]),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndustrialPaper(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IndustrialIconButton(
                      icon: Icons.chevron_left,
                      tooltip: splitText('back'),
                      size: 56,
                      outlined: true,
                      onPressed: pending ? null : close,
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 2,
                      height: 28,
                      child: ColoredBox(color: Palette.of(context).acid),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        splitText(widget.existing == null ? 'create' : 'edit'),
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final wide =
                          box.maxWidth >= 1120 &&
                          box.maxHeight >= 300 &&
                          MediaQuery.textScalerOf(context).scale(18) <= 27;
                      return wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: (box.maxWidth - 24) * .4575,
                                  child: preview(true),
                                ),
                                const SizedBox(width: 24),
                                Expanded(child: parameters()),
                              ],
                            )
                          : ListView(
                              children: [
                                preview(false),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: draft.advanced ? 700 : 520,
                                  child: parameters(),
                                ),
                              ],
                            );
                    },
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(color: Palette.of(context).red),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Divider(height: 1, color: Palette.of(context).grid),
                const SizedBox(height: 16),
                ResponsiveToolbar(
                  children: [
                    if (widget.existing != null)
                      IndustrialButton(
                        splitText('delete'),
                        width: 160,
                        kind: ButtonKind.quiet,
                        onPressed: pending ? null : delete,
                      ),
                    const Spacer(),
                    IndustrialButton(
                      Strings.text('cancel'),
                      width: 96,
                      kind: ButtonKind.quiet,
                      onPressed: pending ? null : close,
                    ),
                    const SizedBox(width: 16),
                    IndustrialButton(
                      splitText(pending ? 'saving' : 'save'),
                      width: 176,
                      primary: true,
                      onPressed: pending || !draft.complete || catalog.loading
                          ? null
                          : save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

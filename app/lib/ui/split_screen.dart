import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../data/split_catalog.dart';
import '../domain/split_screen.dart';
import '../l10n/strings.dart';
import 'confirmation.dart';
import 'design_dialog.dart';
import 'industrial.dart';
import 'layout.dart';

part 'split_editor.dart';
part 'split_picker.dart';

String splitText(String key) => Strings.text('split_$key');
String splitReason(String? reason) {
  final key = 'split_reason_${reason ?? 'activity_unavailable'}';
  final value = Strings.text(key);
  return value == key ? Strings.text('split_reason_launch_failed') : value;
}

String splitLabel(SplitCatalog catalog, SplitTarget? target) =>
    catalog.app(target)?.label ?? target?.label ?? splitText('select_app');

class SplitScreenPage extends StatefulWidget {
  final AppController controller;
  const SplitScreenPage({super.key, required this.controller});
  @override
  State<SplitScreenPage> createState() => SplitScreenPageState();
}

class SplitScreenPageState extends State<SplitScreenPage>
    with WidgetsBindingObserver {
  late final catalog = SplitCatalog(widget.controller.bridge);
  AppController get c => widget.controller;
  SplitDraft get quick => c.splitQuickDraft;
  String? feedback;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    catalog.addListener(changed);
    c.addListener(changed);
    refresh();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> refresh() => catalog.refresh([
    quick.left,
    quick.right,
    ...c.splitCombos.expand((e) => [e.left, e.right]),
  ]);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !catalog.loading) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(changed);
    catalog.removeListener(changed);
    catalog.dispose();
    super.dispose();
  }

  Future<void> pick(bool left) async {
    final selected = await pickSplitApp(
      context,
      catalog,
      left ? quick.left : quick.right,
    );
    if (selected != null && mounted) {
      setState(() {
        quick.select(left, selected.target);
        feedback = null;
      });
      try {
        await catalog.loadActivities(selected.packageName);
      } catch (_) {
        /* Render the query state beside the selected application. */
      }
      changed();
    }
  }

  Future<void> launch(SplitDraft draft) async {
    if (c.splitLaunching) return;
    // Lock before the asynchronous inventory refresh as well as the native request.
    if (launchChecking) return;
    setState(() {
      launchChecking = true;
      feedback = null;
    });
    if (!c.splitCompatibilityAcknowledged) {
      final accepted = await confirmAction(
        context,
        title: splitText('compatibility_title'),
        message: splitText('compatibility_message'),
        action: splitText('launch_split'),
      );
      if (!mounted) return;
      if (!accepted) {
        setState(() => launchChecking = false);
        return;
      }
      c.splitCompatibilityAcknowledged = true;
    }
    await catalog.refresh([
      draft.left,
      draft.right,
      ...c.splitCombos.expand((e) => [e.left, e.right]),
    ]);
    if (!mounted) return;
    final invalidLeft = catalog.invalid(draft.left),
        invalidRight = catalog.invalid(draft.right);
    if (invalidLeft != null || invalidRight != null) {
      setState(() {
        launchChecking = false;
        feedback =
            '${splitText(invalidLeft != null ? 'left' : 'right')}：${splitReason(invalidLeft ?? invalidRight)}';
      });
      return;
    }
    final result = await c.launchSplit(draft);
    if (!mounted) return;
    final status = result['status'];
    final side = result['side'] == 'right'
        ? splitText('right')
        : splitText('left');
    setState(() {
      launchChecking = false;
      feedback = status == 'requested'
          ? result['layoutReason'] == null
                ? splitText('requested')
                : Strings.text('split_direction_pending', {
                    'reason': splitReason(result['layoutReason'] as String?),
                  })
          : status == 'partial'
          ? Strings.text('split_partial', {
              'side':
                  (result['requestedSides'] as List? ?? []).contains('right')
                  ? splitText('right')
                  : splitText('left'),
              'reason': splitReason(result['reason'] as String?),
            })
          : status == 'busy'
          ? splitText('busy')
          : status == 'unsupported'
          ? splitReason('unsupported_device')
          : '$side：${splitReason(result['reason'] as String?)}';
    });
  }

  bool launchChecking = false;
  bool get busy => c.splitLaunching || launchChecking;
  Future<void> edit([SplitCombo? combo]) async {
    if (combo == null && c.splitCombos.length >= 64) {
      setState(() => feedback = splitText('limit'));
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            SplitComboEditor(controller: c, catalog: catalog, existing: combo),
      ),
    );
    if (mounted) {
      setState(() => feedback = null);
      refresh();
    }
  }

  Widget appButton(bool left) => SplitAppButton(
    catalog: catalog,
    target: left ? quick.left : quick.right,
    label: splitText(left ? 'left_app' : 'right_app'),
    onTap: busy ? null : () => pick(left),
  );
  Widget quickPanel() => LayoutBuilder(
    builder: (context, box) {
      final wide =
          box.maxWidth >= 1216 &&
          MediaQuery.textScalerOf(context).scale(18) <= 22;
      final apps = [appButton(true), appButton(false)];
      final choices = SplitRatioButtons(
        ratio: quick.ratio,
        onChanged: busy ? null : (ratio) => setState(() => quick.ratio = ratio),
      );
      final start = IndustrialButton(
        splitText(busy ? 'starting' : 'launch_split'),
        width: 176,
        primary: true,
        onPressed:
            busy ||
                catalog.loading ||
                catalog.error != null ||
                !catalog.supported ||
                !quick.complete ||
                catalog.invalid(quick.left) != null ||
                catalog.invalid(quick.right) != null
            ? null
            : () => launch(quick),
      );
      return Container(
        color: Palette.of(context).surface,
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(splitText('quick'), style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 312, child: apps[0]),
                  const SizedBox(width: 12),
                  SizedBox(width: 312, child: apps[1]),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: choices),
                  const Spacer(),
                  start,
                ],
              )
            else ...[
              for (final app in apps)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: app),
              choices,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: start),
            ],
          ],
        ),
      );
    },
  );
  Widget comboRow(SplitCombo combo) => LayoutBuilder(
    builder: (context, box) {
      final leftError = catalog.loading ? null : catalog.invalid(combo.left),
          rightError = catalog.loading ? null : catalog.invalid(combo.right);
      final invalid = leftError != null || rightError != null;
      final name = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(combo.name, style: const TextStyle(fontSize: 24)),
          if (invalid)
            Text(
              '${splitText(leftError != null ? 'left' : 'right')}：${splitReason(leftError ?? rightError)} · ${splitText('edit_repair')}',
              style: TextStyle(color: Palette.of(context).red, fontSize: 16),
            ),
        ],
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IndustrialButton(
            splitText('launch'),
            width: 160,
            onPressed: invalid || busy || catalog.loading || !catalog.supported
                ? null
                : () => launch(SplitDraft.fromCombo(combo)),
          ),
          const SizedBox(width: 16),
          IndustrialIconButton(
            icon: Icons.edit_outlined,
            tooltip: Strings.text('split_edit_named', {'name': combo.name}),
            onPressed: busy ? null : () => edit(combo),
          ),
        ],
      );
      final preview = SplitArea(
        catalog: catalog,
        draft: SplitDraft.fromCombo(combo),
        compact: true,
      );
      return Container(
        key: ValueKey('split-combo-${combo.id}'),
        color: Palette.of(context).surface,
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child:
            box.maxWidth >= 800 &&
                MediaQuery.textScalerOf(context).scale(18) <= 27
            ? Row(
                children: [
                  SizedBox(width: 264, height: 64, child: preview),
                  const SizedBox(width: 24),
                  Expanded(child: name),
                  const SizedBox(width: 16),
                  actions,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 72, child: preview),
                  const SizedBox(height: 12),
                  name,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              ),
      );
    },
  );
  List<Widget> get notices => [
    if (catalog.loading) const LinearProgressIndicator(),
    if (!catalog.loading && catalog.error == null)
      for (final left in [true, false])
        if ((left ? quick.left : quick.right) != null &&
            catalog.invalid(left ? quick.left : quick.right) != null)
          SplitNotice(
            message:
                '${splitText(left ? 'left' : 'right')}：${splitReason(catalog.invalid(left ? quick.left : quick.right))}',
          ),
    if (catalog.error != null)
      SplitNotice(message: splitText('query_failed'), onRetry: refresh),
    if (!catalog.supported && catalog.error == null)
      SplitNotice(message: splitReason('unsupported_device')),
    if (feedback != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Semantics(
          liveRegion: true,
          child: Text(feedback!, key: const ValueKey('split-feedback')),
        ),
      ),
  ];
  Widget savedHeading() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 40),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              splitText('saved'),
              style: TextStyle(fontSize: 18, color: Palette.of(context).muted),
            ),
          ),
          Text(
            Strings.text('split_count', {'count': c.splitCombos.length}),
            style: TextStyle(color: Palette.of(context).muted),
          ),
        ],
      ),
    ),
  );
  List<Widget> get rows => [
    if (c.splitCombos.isEmpty)
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(splitText('empty')),
      ),
    for (final combo in c.splitCombos)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: comboRow(combo),
      ),
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final fixed =
          box.maxWidth >= 1216 &&
          box.maxHeight >= 360 &&
          MediaQuery.textScalerOf(context).scale(18) <= 22;
      return fixed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                quickPanel(),
                ...notices,
                savedHeading(),
                Expanded(child: ListView(children: rows)),
              ],
            )
          : ListView(
              children: [quickPanel(), ...notices, savedHeading(), ...rows],
            );
    },
  );
}

class SplitNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const SplitNotice({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(message, style: TextStyle(color: Palette.of(context).red)),
        if (onRetry != null)
          IndustrialButton(splitText('retry'), width: 120, onPressed: onRetry),
      ],
    ),
  );
}

class SplitAppButton extends StatelessWidget {
  final SplitCatalog catalog;
  final SplitTarget? target;
  final String label;
  final VoidCallback? onTap;
  const SplitAppButton({
    super.key,
    required this.catalog,
    required this.target,
    required this.label,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context), app = catalog.app(target);
    return Semantics(
      label: '$label ${splitLabel(catalog, target)}',
      button: true,
      child: Material(
        color: p.field,
        shape: Border.all(color: p.edge),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  if (app?.iconBytes != null) ...[
                    Image.memory(
                      app!.iconBytes!,
                      width: 32,
                      height: 32,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.apps, size: 32),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            color: p.muted,
                          ),
                        ),
                        Text(
                          splitLabel(catalog, target),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    splitText('change'),
                    style: TextStyle(fontSize: 16, color: p.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SplitRatioButtons extends StatelessWidget {
  final String ratio;
  final ValueChanged<String>? onChanged;
  const SplitRatioButtons({super.key, required this.ratio, this.onChanged});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final value in ['7/3', '3/7']) ...[
        if (value == '3/7') const SizedBox(width: 8),
        Expanded(
          child: IndustrialButton(
            splitText(value == '7/3' ? 'large_left' : 'large_right'),
            kind: ratio == value ? ButtonKind.selected : ButtonKind.secondary,
            onPressed: onChanged == null ? null : () => onChanged!(value),
          ),
        ),
      ],
    ],
  );
}

class SplitArea extends StatelessWidget {
  final SplitCatalog catalog;
  final SplitDraft draft;
  final bool compact;
  final ValueChanged<bool>? onSelect;
  const SplitArea({
    super.key,
    required this.catalog,
    required this.draft,
    this.compact = false,
    this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context), largeLeft = draft.ratio == '7/3';
    return LayoutBuilder(
      builder: (context, box) {
        final showPercent =
            !compact &&
            box.maxWidth * .3 - 32 >=
                MediaQuery.textScalerOf(context).scale(20) * 3;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border.all(color: p.edge)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final left in [true, false])
                Expanded(
                  flex: left == largeLeft ? 7 : 3,
                  child: Material(
                    color: left ? p.field : p.grid,
                    child: Semantics(
                      label:
                          '${splitText(left ? 'left_app' : 'right_app')} ${splitLabel(catalog, left ? draft.left : draft.right)}',
                      button: onSelect != null,
                      child: InkWell(
                        onTap: onSelect == null ? null : () => onSelect!(left),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 8 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: compact
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.spaceBetween,
                            children: [
                              if (!compact)
                                Text(
                                  splitText(left ? 'left' : 'right'),
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 16,
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  splitLabel(
                                    catalog,
                                    left ? draft.left : draft.right,
                                  ),
                                  maxLines: compact ? 2 : 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: compact ? 16 : 24),
                                ),
                              ),
                              if (showPercent)
                                Text(
                                  left == largeLeft ? '70%' : '30%',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: p.muted,
                                    fontFamily: 'IBMPlexMono',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

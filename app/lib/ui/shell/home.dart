import '../../l10n/strings.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../data/app_controller.dart';
import '../../domain/models.dart';
import '../../domain/dashboard_layout.dart';
import '../../domain/connection_options.dart';
import '../../domain/build_channel.dart';
import '../project_link.dart';
import '../touch_targets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../industrial.dart';
import '../editors.dart';
import '../history_dialog.dart';
import '../history_preferences.dart';
import '../design_dialog.dart';
import '../metric_tile.dart';
import '../motion.dart';
import '../navigation.dart';
import '../field_details.dart';
import '../overlay_preview.dart';
import '../overlay_settings.dart';
import '../layout.dart';
import '../confirmation.dart';
import '../connection_confirmation.dart';
import '../network_adb_settings.dart';
import '../auto_adb_explanation.dart';
import '../release_notice.dart';
import '../laboratory.dart';

part 'information.dart';
part 'overlay.dart';
part 'connection.dart';
part 'settings.dart';
part 'config_transfer.dart';
part 'entity_mapping.dart';
part 'history_settings.dart';
part 'startup_authorization.dart';
part 'connection_settings.dart';

class Home extends StatefulWidget {
  final AppController controller;
  const Home({super.key, required this.controller});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  AppController get c => widget.controller;
  bool menuOpen = false;
  final grid = GlobalKey();
  final menuKey = GlobalKey();
  int page = 0, settingsTab = 0;
  bool editing = false, selectedOnly = false;
  Set<String>? uploadDraft;
  String category = Strings.text('text_83ada17910'), search = '';
  DateTime now = DateTime.now();
  Timer? ageTimer;
  final Set<ValueNotifier<Sample>> ageSources = {};
  bool visible = true;
  bool startupAuthorizationChecked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(scheduleAge);
    c.addListener(checkStartupAuthorization);
    scheduleAge();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => checkStartupAuthorization(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(scheduleAge);
    c.removeListener(checkStartupAuthorization);
    ageTimer?.cancel();
    for (final source in ageSources) {
      source.removeListener(scheduleAge);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    ageTimer?.cancel();
    c.bridge.call('visibility', {'visible': visible, 'information': page == 0});
    if (visible) {
      setState(() => now = DateTime.now());
      scheduleAge();
      checkStartupAuthorization();
    }
  }

  void scheduleAge() {
    ageTimer?.cancel();
    final sources = visible && page == 0
        ? c.tiles
              .where((t) => t.time != TimeDisplay.none)
              .expand((t) => t.fields)
              .map(c.reading)
              .toSet()
        : <ValueNotifier<Sample>>{};
    for (final source in ageSources.difference(sources)) {
      source.removeListener(scheduleAge);
    }
    for (final source in sources.difference(ageSources)) {
      source.addListener(scheduleAge);
    }
    ageSources
      ..clear()
      ..addAll(sources);
    if (!visible || page != 0) return;
    final timed = c.tiles.where((t) => t.time != TimeDisplay.none).toList();
    final historyVisible = c.tiles.any((t) => t.kind.history);
    if (timed.isEmpty && !historyVisible) return;
    var wait = historyVisible ? Duration(minutes: 1) : Duration(days: 1);
    final current = DateTime.now();
    for (final t in timed) {
      for (final id in t.fields) {
        final sample = c.reading(id).value;
        final at = t.time == TimeDisplay.updated
            ? sample.updatedAt
            : sample.changedAt;
        if (at == null || at.isAfter(current)) continue;
        final age = current.difference(at).inMilliseconds;
        final period = age < 60000
            ? 1000
            : age < 3600000
            ? 60000
            : age < 86400000
            ? 3600000
            : 86400000;
        final next = Duration(milliseconds: period - age % period + 10);
        if (next < wait) wait = next;
      }
    }
    ageTimer = Timer(wait, () {
      if (mounted) {
        setState(() => now = DateTime.now());
        scheduleAge();
      }
    });
  }

  Future<bool> save() async {
    final saved = await c.save();
    if (mounted && c.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(c.error!)));
    }
    return saved;
  }

  Future<void> addTile([TileSpec? old]) async {
    final tile = await editTile(
      context,
      c,
      existing: old,
      onDelete: old == null
          ? null
          : () async {
              final before = c.config;
              c.tiles.removeWhere((tile) => tile.id == old.id);
              if (!await save()) {
                c.restore(before);
                throw StateError('save failed');
              }
            },
    );
    if (tile == null) return;
    final before = c.config;
    if (old == null) {
      c.tiles.add(tile);
    } else {
      final index = c.tiles.indexWhere((t) => t.id == old.id);
      if (index < 0) return;
      c.tiles[index] = tile;
    }
    if (!await save()) {
      c.restore(before);
      if (mounted) setState(() {});
    }
  }

  Future<void> addOverlay([OverlaySpec? old]) async {
    final module = await editOverlay(
      context,
      c,
      existing: old,
      onDelete: old == null
          ? null
          : () async {
              final before = c.config;
              c.overlays.removeWhere((m) => m.id == old.id);
              if (!await save()) {
                c.restore(before);
                throw StateError('save failed');
              }
            },
    );
    if (module == null) return;
    final before = c.config;
    if (old == null) {
      c.overlays.add(module);
    } else {
      final index = c.overlays.indexWhere((m) => m.id == old.id);
      if (index < 0) return;
      c.overlays[index] = module;
    }
    if (!await save()) {
      c.restore(before);
      if (mounted) setState(() {});
    }
  }

  Future<void> openNavigation() async {
    if (menuOpen) return;
    setState(() => menuOpen = true);
    final target = await showNavigationMenu(context, page, menuKey);
    if (!mounted) return;
    setState(() => menuOpen = false);
    if (target != null) navigate(target);
  }

  void update(VoidCallback change) {
    if (mounted) setState(change);
  }

  Widget button(
    String title,
    VoidCallback action, {
    bool primary = false,
    double width = 180,
    double height = 48,
  }) => IndustrialButton(
    title,
    width: width,
    height: height,
    primary: primary,
    reduceMotion: c.reduceMotion,
    onPressed: action,
  );
  Widget statusBadge(String label) {
    final p = Palette.of(context);
    final good = [
      Strings.text('text_65fe35c45e'),
      Strings.text('text_c6f7c57883'),
    ].contains(label);
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: good ? p.green : p.muted),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }

  void navigate(int target) {
    setState(() {
      page = target;
      menuOpen = false;
    });
    if (target != 0) c.releaseHistoryViews();
    scheduleAge();
    c.bridge.call('visibility', {
      'visible': visible,
      'information': target == 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: PopScope(
        canPop: !editing,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && editing) setState(() => editing = false);
        },
        child: TickerMode(
          enabled: visible,
          child: IndustrialPaper(
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          NavigationHeading(
                            title: pageTitles[page],
                            menuOpen: menuOpen,
                            menuKey: menuKey,
                            onMenu: openNavigation,
                            actions: [
                              if (page == 0) ...[
                                if (editing)
                                  button(
                                    Strings.text('add_component'),
                                    () => addTile(),
                                    primary: true,
                                    width: 160,
                                  ),
                                IndustrialIconButton(
                                  icon: Icons.edit_outlined,
                                  outlined: true,
                                  selected: editing,
                                  tooltip: editing
                                      ? Strings.text('text_9a104e6602')
                                      : Strings.text('text_f7d900fb39'),
                                  onPressed: () =>
                                      setState(() => editing = !editing),
                                ),
                              ],
                              if (page == 1)
                                button(
                                  Strings.text('text_962ebc86af'),
                                  () => addOverlay(),
                                  primary: true,
                                  width: 160,
                                ),
                              if (page == 2) ...[
                                if (MediaQuery.sizeOf(context).width > 1000)
                                  Text(
                                    c.connection == 'ha'
                                        ? 'Home Assistant'
                                        : 'MQTT',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                statusBadge(
                                  c.status['connection'] ??
                                      Strings.text('text_f2f3e9803c'),
                                ),
                                button(
                                  Strings.text('text_03b78d7463'),
                                  connectionSettings,
                                  width: 180,
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: 16),
                          if (page == 3 && BuildChannel.isTesting) ...[
                            ReleaseNotice(
                              version: c.appVersion,
                              onOpen: openProject,
                            ),
                            const SizedBox(height: 16),
                          ],
                          Expanded(
                            child: Motion(
                              identity: page,
                              child: switch (page) {
                                0 => information(),
                                1 => overlayPage(),
                                2 => connectionPage(),
                                _ => settings(),
                              },
                            ),
                          ),
                          if (c.error != null)
                            Text(
                              c.error!,
                              style: TextStyle(color: p.red, fontSize: 16),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget toggle(String name, bool v, ValueChanged<bool> changed) =>
      ParameterRow(
        name,
        trailing: IndustrialSwitch(
          value: v,
          onChanged: (v) {
            changed(v);
            save();
          },
        ),
      );
  bool connectionAdvanced = false;
}

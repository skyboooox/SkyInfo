part of 'home.dart';

extension _Settings on _HomeState {
  String get adbState => c.status['adb'] ?? 'disabled';
  Widget settings() => CategoryPane<int>(
    values: settingsTabs,
    selected: settingsTab,
    label: (tab) => settingsTitles[tab],
    onChanged: (tab) => update(() => settingsTab = tab),
    child: Container(
      color: Palette.of(context).surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        children: switch (settingsTab) {
          0 => [
            settingHeading('appearance'),
            ParameterRow(
              Strings.text('theme'),
              trailing: SizedBox(
                width: 432,
                child: ChoiceButtons<String>(
                  value: c.theme,
                  values: const ['system', 'light', 'dark'],
                  label: (value) => Strings.text(
                    {
                      'system': 'text_f4bbd91f79',
                      'light': 'text_80ec9e2b1b',
                      'dark': 'text_30b2c979ac',
                    }[value]!,
                  ),
                  onChanged: (value) {
                    c.theme = value;
                    save();
                  },
                ),
              ),
            ),
            toggle(
              Strings.text('text_6fb0efeed7'),
              c.reduceMotion,
              (v) => c.reduceMotion = v,
            ),
            ParameterRow(
              Strings.text('dashboard_size'),
              trailing: SizedBox(
                width: 320,
                child: ChoiceButtons<DashboardSize>(
                  value: c.dashboardSize,
                  values: DashboardSize.values,
                  label: (size) => Strings.text('dashboard_size_${size.name}'),
                  onChanged: (size) async {
                    final before = c.dashboardSize;
                    c.dashboardSize = size;
                    if (!await save() && mounted) {
                      update(() => c.dashboardSize = before);
                    }
                  },
                ),
              ),
            ),
            settingHeading('runtime'),
            toggle(
              Strings.text('text_4b0ba84503'),
              c.autoStart,
              (v) => c.autoStart = v,
            ),
            settingHeading('configuration'),
            settingAction('text_280779a502', importSettings),
            settingAction('text_3d05c8ad5e', exportSettings),
            settingHeading('about'),
            ParameterRow(
              Strings.text('app_version'),
              trailing: Text(
                c.versionLabel,
                style: const TextStyle(fontFamily: 'IBMPlexMono', fontSize: 20),
              ),
            ),
            projectLink(),
          ],
          1 => [
            settingHeading('acquisition'),
            toggle(
              Strings.text('text_518c133e30'),
              c.collect,
              (v) => c.collect = v,
            ),
            toggle(
              Strings.text('text_b3a73c91a8'),
              c.fallbackPolling,
              (v) => c.fallbackPolling = v,
            ),
            ParameterRow(
              Strings.text('text_ab3b7651bf'),
              trailing: Flexible(
                child: Text(
                  c.status['path'] ?? Strings.text('text_f2f3e9803c'),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            ParameterRow(
              Strings.text('text_5319af762d'),
              trailing: Text(
                c.status['subscription'] ?? Strings.text('unverified'),
              ),
            ),
            settingAction('text_4d4b8f80e8', () => c.action('refresh')),
            ParameterRow(
              Strings.text('runtime_state'),
              trailing: IndustrialButton(
                c.status['stopped'] == true
                    ? Strings.text('text_67be57f398')
                    : Strings.text('text_42bf555da5'),
                width: 160,
                onPressed: () =>
                    c.action(c.status['stopped'] == true ? 'resume' : 'stop'),
              ),
            ),
            settingHeading('local_history'),
            settingAction('text_219e5cc5ca', localHistorySettings),
          ],
          2 => [settingHeading('page_overlay'), OverlaySettings(controller: c)],
          3 => [
            settingHeading('ha_entities'),
            toggle(
              Strings.text('ha_import_enabled'),
              c.haImportEnabled,
              (v) => c.haImportEnabled = v,
            ),
            ParameterRow(
              Strings.text('ha_import_state'),
              trailing: Text(Strings.text('ha_status_${c.haImportState}')),
            ),
            settingAction(
              'text_03b78d7463',
              () => connectionSettings(initialMode: 'ha'),
            ),
            settingAction('ha_reconnect', () => c.action('refreshHa')),
            settingHeading('vehicle_reporting'),
            toggle(
              Strings.text('text_fdb4bf21fa'),
              c.publishEnabled,
              (v) => c.publishEnabled = v,
            ),
            if (c.connection == 'ha')
              toggle(
                Strings.text('text_5033b61a3f'),
                c.haControlEnabled,
                (v) => c.haControlEnabled = v,
              ),
            if (c.connection == 'mqtt')
              toggle(
                Strings.text('text_846f8d4fb3'),
                c.mqttControlEnabled,
                (v) => c.mqttControlEnabled = v,
              ),
            settingAction('text_40548fd30f', () => c.action('checkConnection')),
            settingAction('text_b9da27a9e2', () async {
              final clear = await confirmRemoval(
                context,
                title: Strings.text('clear_credentials_title'),
                message: Strings.text('clear_credentials_message'),
                action: Strings.text('text_84fcd70d42'),
              );
              if (clear) {
                await c.action('clearCredentials');
              }
            }),
          ],
          4 => [
            settingHeading('advanced'),
            settingAction(
              'text_9f0ca615e8',
              () => connectionSettings(initialMode: 'mqtt'),
            ),
            settingHeading('permissions'),
            ParameterRow(
              Strings.text('adb_name'),
              trailing: Text(Strings.text('adb_status_$adbState')),
            ),
            ParameterRow(
              Strings.text('auto_system_adb'),
              labelAction: IndustrialIconButton(
                icon: Icons.error_outline,
                tooltip: Strings.text('auto_system_adb_explanation'),
                onPressed: () => showAutoAdbExplanation(context, c),
              ),
              trailing: IndustrialSwitch(
                value: c.autoSystemAdb,
                onChanged: c.autoSystemAdbPending ? null : c.setAutoSystemAdb,
              ),
            ),
            ParameterRow(
              Strings.text('text_413484c00f'),
              trailing: Text(
                c.status['overlay'] ?? Strings.text('text_ed9ec8188c'),
              ),
            ),
            settingAction(
              'adb_settings',
              () => showDesignDialog<void>(
                context: context,
                builder: (_) => NetworkAdbSettings(
                  controller: c,
                  onNavigate: (p) {
                    Navigator.pop(context);
                    update(() {
                      page = p;
                      menuOpen = false;
                    });
                  },
                  onTab: (t) {
                    Navigator.pop(context);
                    update(() {
                      page = 3;
                      settingsTab = t;
                    });
                  },
                ),
              ),
            ),
            settingAction('text_076b77e2ac', () => c.action('requestOverlay')),
            settingAction('text_a304ba2797', () => c.action('openStartup')),
            settingHeading('diagnostics'),
            settingAction('text_0b673e8796', showDiagnostics),
            settingAction('text_f403f4466e', entitySettings),
          ],
          5 when BuildChannel.isTesting => [Laboratory(controller: c)],
          _ => [],
        },
      ),
    ),
  );
  Future<void> openProject() => openProjectLink(context);

  Widget projectLink() => LayoutBuilder(
    builder: (context, box) => ParameterRow(
      Strings.text('project_github'),
      trailing: SizedBox(
        width: box.maxWidth < 600
            ? (box.maxWidth - 16).clamp(0, 700).toDouble()
            : (box.maxWidth * .7).clamp(0, 700).toDouble(),
        child: Row(
          children: [
            Expanded(
              child: Text(
                BuildChannel.projectUrl,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Palette.of(context).blue,
                  fontSize: 20,
                  fontFamily: 'IBMPlexMono',
                ),
              ),
            ),
            const SizedBox(width: 16),
            SvgPicture.asset(
              'assets/ui/external-link.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                Palette.of(context).blue,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
      onTap: openProject,
    ),
  );
  Widget settingHeading(String key) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      Strings.text(key),
      style: TextStyle(fontSize: 20, color: Palette.of(context).muted),
    ),
  );
  Widget settingAction(String key, VoidCallback action) => ParameterRow(
    Strings.text(key),
    trailing: IndustrialButton(
      Strings.text(switch (key) {
        'text_280779a502' => 'action_import',
        'text_3d05c8ad5e' => 'action_export',
        'text_0b673e8796' => 'action_view',
        'text_219e5cc5ca' ||
        'text_03b78d7463' ||
        'text_9f0ca615e8' ||
        'adb_settings' ||
        'text_f403f4466e' => 'action_configure',
        'text_076b77e2ac' => 'action_authorize',
        'text_a304ba2797' => 'action_startup_settings',
        'text_b9da27a9e2' => 'action_clear',
        _ => key,
      }),
      width: 160,
      trailing: Icons.chevron_right,
      onPressed: action,
    ),
    onTap: action,
  );
}

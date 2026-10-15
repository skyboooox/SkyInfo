import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../l10n/strings.dart';
import 'design_dialog.dart';
import 'industrial.dart';

Future<void> showAutoAdbExplanation(
  BuildContext context,
  AppController controller,
) => showDesignDialog<void>(
  context: context,
  builder: (context) => DesignDialog(
    title: Strings.text('auto_system_adb'),
    width: 640,
    height: 440,
    footer: Align(
      alignment: Alignment.centerRight,
      child: IndustrialButton(
        Strings.text('close'),
        width: 160,
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final result = controller.status['systemAdb'] as Map? ?? {};
        final settings = result['settings'] as Map? ?? {};
        return ListView(
          children: [
            Text(
              Strings.text('auto_system_adb_message'),
              style: TextStyle(color: Palette.of(context).muted),
            ),
            if (controller.autoSystemAdb) ...[
              const SizedBox(height: 16),
              for (final entry in {
                'system_adb_switch': settings['adb_enabled'],
                'system_wifi_adb_switch': settings['adb_wifi_enabled'],
                'system_adb_permission': result['appPermission'] == true
                    ? 'granted'
                    : result['appPermission'] == false
                    ? 'permission_required'
                    : 'pending',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${Strings.text(entry.key)}：${_stateLabel(entry.value)}',
                  ),
                ),
            ],
          ],
        );
      },
    ),
  ),
);

String _stateLabel(Object? state) => Strings.text(switch (state) {
  'enabled' => 'system_adb_state_enabled',
  'granted' => 'system_adb_state_granted',
  'permission_required' => 'system_adb_state_permission_required',
  'error' => 'system_adb_state_error',
  _ => 'system_adb_state_pending',
});

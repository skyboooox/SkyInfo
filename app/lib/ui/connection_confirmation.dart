import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/connection_options.dart';
import '../l10n/strings.dart';
import 'confirmation.dart';

Future<Set<String>?> confirmConnectionConfiguration(
  BuildContext context,
  AppController controller,
  Map<String, dynamic> next,
) async {
  final mode = next['connection'] as String? ?? 'ha';
  final url = next['haUrl'] as String? ?? '';
  if (mode == 'ha' &&
      controller.haUrl.isNotEmpty &&
      haEndpointIdentity(controller.haUrl) != haEndpointIdentity(url)) {
    if (!await confirmAction(
      context,
      title: Strings.text('connection_server_change_title'),
      message: Strings.text('connection_server_change_message'),
      action: Strings.text('connection_server_change_action'),
    )) {
      return null;
    }
    if (!context.mounted) return null;
  }
  final key = insecureConnectionKey(
    mode: mode,
    haUrl: url,
    transport: next['mqttTransport'] as String? ?? 'tls',
    mqttHost: next['mqttHost'] as String? ?? '',
    mqttPort: next['mqttPort'] as int? ?? 8883,
  );
  final acknowledgements = {...controller.insecureAcknowledgements};
  if (key != null && !acknowledgements.contains(key)) {
    if (!await confirmAction(
      context,
      title: Strings.text('connection_insecure_title'),
      message: Strings.text('connection_insecure_message'),
      action: Strings.text('connection_continue_save'),
    )) {
      return null;
    }
    acknowledgements.add(key);
  }
  return acknowledgements;
}

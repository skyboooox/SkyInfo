import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../l10n/strings.dart';
import 'industrial.dart';

class HaControlStatus extends StatelessWidget {
  final AppController controller;
  const HaControlStatus({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final reported = controller.status['haControlState'];
      final state = !controller.haControlEnabled
          ? 'disabled'
          : const {
              'disabled',
              'disconnected',
              'subscribing',
              'retrying',
              'blocked',
              'ready',
            }.contains(reported)
          ? reported as String
          : 'unknown';
      final error = controller.status['haControlError'];
      final showError =
          controller.haControlEnabled &&
          error is String &&
          error.isNotEmpty &&
          state != 'ready';
      return Text(
        '${Strings.text('ha_control_state_$state')}${showError ? '\n${Strings.text('ha_control_error_detail', {'error': error})}' : ''}',
        style: TextStyle(fontSize: 16, color: Palette.of(context).muted),
      );
    },
  );
}

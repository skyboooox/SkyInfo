import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../l10n/strings.dart';
import 'industrial.dart';
import 'live_setting_slider.dart';

class OverlaySettings extends StatelessWidget {
  final AppController controller;
  const OverlaySettings({super.key, required this.controller});

  Future<void> _run(BuildContext context, Future<bool> operation) async {
    final ok = await operation;
    if (!ok && context.mounted && controller.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.error!)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final busy = c.overlayPositionPending || c.overlayPermissionPending;
      final unavailable = c.overlayPositionUnavailable;
      return LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ParameterRow(
              Strings.text('text_b399f97c5f'),
              trailing: IndustrialSwitch(
                value: c.overlayEnabled,
                onChanged: busy ? null : c.setOverlayEnabled,
              ),
            ),
            ParameterRow(
              Strings.text('text_88c34452cc'),
              trailing: SizedBox(
                width: (box.maxWidth - 16).clamp(0, 332).toDouble(),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    IndustrialButton(
                      Strings.text('overlay_adjust_position'),
                      width: 160,
                      onPressed: busy || unavailable != null
                          ? null
                          : () => _run(context, c.adjustOverlayPosition()),
                    ),
                    IndustrialButton(
                      Strings.text('overlay_restore_position'),
                      width: 160,
                      onPressed: busy
                          ? null
                          : () => _run(context, c.resetOverlayPosition()),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Text(
                unavailable != null
                    ? Strings.text(unavailable)
                    : [
                        if (c.status['overlayInteraction'] is String)
                          c.status['overlayInteraction'],
                        Strings.text('overlay_position_hint'),
                      ].join(' · '),
                style: TextStyle(
                  fontSize: 16,
                  color: Palette.of(context).muted,
                ),
              ),
            ),
            ParameterRow(
              Strings.text('text_576ccdb1f1'),
              trailing: SizedBox(
                width: 200,
                child: DropdownButton<double>(
                  borderRadius: BorderRadius.zero,
                  itemHeight: null,
                  isExpanded: true,
                  value: c.overlayFont,
                  items: [
                    for (final value in [14.0, 16.0, 18.0, 20.0, 24.0])
                      DropdownMenuItem(
                        value: value,
                        child: Text('${value.toInt()}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _run(context, c.overlayAppearance.commitFont(value));
                    }
                  },
                ),
              ),
            ),
            ParameterRow(
              Strings.text('text_d626470d5a'),
              trailing: SizedBox(
                width: (box.maxWidth - 16).clamp(0, 360).toDouble(),
                child: LiveSettingSlider(
                  value: c.overlayOpacity,
                  min: .1,
                  max: .8,
                  onPreview: c.overlayAppearance.previewOpacity,
                  onCancel: c.overlayAppearance.cancel,
                  onCommit: (value) async {
                    final ok = await c.overlayAppearance.commitOpacity(value);
                    if (!ok && context.mounted && c.error != null) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(c.error!)));
                    }
                    return ok;
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

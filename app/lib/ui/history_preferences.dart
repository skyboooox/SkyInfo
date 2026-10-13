import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../l10n/strings.dart';
import 'confirmation.dart';
import 'design_dialog.dart';
import 'industrial.dart';

Future<void> showLocalHistoryPreferences(
  BuildContext context,
  AppController controller,
) => showDesignDialog<void>(
  context: context,
  builder: (_) => _HistoryPreferences(controller),
);

class _HistoryPreferences extends StatefulWidget {
  final AppController c;
  const _HistoryPreferences(this.c);
  @override
  State<_HistoryPreferences> createState() => _HistoryPreferencesState();
}

class _HistoryPreferencesState extends State<_HistoryPreferences> {
  bool busy = false;
  String? error;
  Future<void> persist(VoidCallback change) async {
    if (busy) return;
    final before = widget.c.config;
    setState(() {
      busy = true;
      error = null;
      change();
    });
    final success = await widget.c.save();
    if (!success) widget.c.restore(before);
    if (mounted) {
      setState(() {
        busy = false;
        error = success ? null : widget.c.error;
      });
    }
  }

  Future<void> clear() async {
    if (busy) return;
    setState(() => busy = true);
    final confirmed = await confirmRemoval(
      context,
      title: Strings.text('clear_history_title'),
      message: Strings.text('clear_history_message'),
      action: Strings.text('text_84fcd70d42'),
    );
    if (confirmed) await widget.c.action('clearHistory');
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return DesignDialog(
      title: Strings.text('text_35f6f2fbdb'),
      footer: Align(
        alignment: Alignment.centerRight,
        child: IndustrialButton(
          Strings.text('close'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      child: ListView(
        children: [
          ParameterRow(
            Strings.text('text_56c7f934b5'),
            trailing: Text(Strings.text('text_8b4c1c5f0c')),
          ),
          ParameterRow(
            Strings.text('text_2bf163bcf2'),
            trailing: IndustrialSwitch(
              value: c.localHistory,
              onChanged: busy
                  ? null
                  : (value) => persist(() => c.localHistory = value),
            ),
          ),
          ParameterRow(
            Strings.text('retention'),
            trailing: SizedBox(
              width: 192,
              child: DropdownButtonFormField<int>(
                borderRadius: BorderRadius.zero,
                itemHeight: null,
                key: ValueKey(c.localHistoryMinutes),
                initialValue: c.localHistoryMinutes,
                isExpanded: true,
                items: [
                  for (final n in ({
                    15,
                    30,
                    60,
                    120,
                    360,
                    1440,
                    c.localHistoryMinutes,
                  }.toList()..sort()))
                    DropdownMenuItem(
                      value: n,
                      child: Text(
                        Strings.text('text_db8d00ea5b', {'value0': n}),
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) {
                          persist(() => c.localHistoryMinutes = value);
                        }
                      },
              ),
            ),
          ),
          ParameterRow(
            Strings.text('text_cdc52e7e86'),
            trailing: IndustrialSwitch(
              value: c.retainHistory,
              onChanged: busy
                  ? null
                  : (value) => persist(() => c.retainHistory = value),
            ),
          ),
          ParameterRow(
            Strings.text('history_capacity'),
            trailing: const Text('200 MB'),
          ),
          ParameterRow(
            Strings.text('text_747731928b'),
            trailing: IndustrialButton(
              Strings.text('text_84fcd70d42'),
              kind: ButtonKind.danger,
              width: 160,
              onPressed: busy ? null : clear,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: TextStyle(color: Palette.of(context).red),
              ),
            ),
        ],
      ),
    );
  }
}

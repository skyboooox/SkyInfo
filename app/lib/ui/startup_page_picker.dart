import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/split_screen.dart';
import '../l10n/strings.dart';
import 'design_dialog.dart';
import 'industrial.dart';
import 'navigation.dart';

Future<void> showStartupPagePicker(
  BuildContext context,
  AppController controller,
) => showDesignDialog<void>(
  context: context,
  builder: (_) => _StartupPagePicker(controller),
);

class _StartupPagePicker extends StatefulWidget {
  final AppController controller;
  const _StartupPagePicker(this.controller);
  @override
  State<_StartupPagePicker> createState() => _StartupPagePickerState();
}

class _StartupPagePickerState extends State<_StartupPagePicker> {
  bool pending = false;
  String? error;
  Future<void> select(String value) async {
    if (pending || value == widget.controller.startupPage) return;
    setState(() {
      pending = true;
      error = null;
    });
    final saved = await widget.controller.saveSplitPreferences(page: value);
    if (mounted) {
      setState(() {
        pending = false;
        if (!saved) error = Strings.text('split_save_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !pending,
    child: DesignDialog(
      title: Strings.text('startup_page'),
      width: 720,
      onClose: pending ? () {} : () => Navigator.pop(context),
      footer: Align(
        alignment: Alignment.centerRight,
        child: IndustrialButton(
          Strings.text('close'),
          width: 160,
          onPressed: pending ? null : () => Navigator.pop(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            Strings.text('startup_page_hint'),
            style: TextStyle(color: Palette.of(context).muted, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final page in startupPages)
                  SelectionRow(
                    pageTitles[startupPageIndices[page]!],
                    selected: widget.controller.startupPage == page,
                    height: 64,
                    onTap: () => select(page),
                  ),
              ],
            ),
          ),
          if (pending) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: TextStyle(color: Palette.of(context).red)),
        ],
      ),
    ),
  );
}

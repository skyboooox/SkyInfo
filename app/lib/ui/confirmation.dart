import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'design_dialog.dart';
import 'industrial.dart';

Future<bool> confirmRemoval(
  BuildContext context, {
  required String title,
  required String message,
  String? action,
}) => confirmAction(
  context,
  title: title,
  message: message,
  action: action ?? Strings.text('delete'),
  kind: ButtonKind.danger,
);

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  ButtonKind kind = ButtonKind.primary,
  String? dismiss,
}) async =>
    await showDesignDialog<bool>(
      context: context,
      builder: (context) => DesignDialog(
        width: 640,
        height: 296,
        title: title,
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Spacer(),
            IndustrialButton(
              dismiss ?? Strings.text('cancel'),
              kind: ButtonKind.quiet,
              width: 96,
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
            ),
            const SizedBox(width: 16),
            IndustrialButton(
              action,
              kind: kind,
              width: 160,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            message,
            style: TextStyle(color: Palette.of(context).muted),
          ),
        ),
      ),
    ) ==
    true;

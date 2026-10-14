import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/build_channel.dart';
import '../l10n/strings.dart';

Future<void> openProjectLink(BuildContext context) async {
  try {
    if (await launchUrl(
      Uri.parse(BuildChannel.projectUrl),
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(Strings.text('project_open_failed'))),
    );
  }
}

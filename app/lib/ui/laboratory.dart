import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/build_channel.dart';
import '../domain/models.dart';
import '../l10n/strings.dart';
import 'industrial.dart';

class Laboratory extends StatefulWidget {
  final AppController controller;
  const Laboratory({super.key, required this.controller});
  @override
  State<Laboratory> createState() => _LaboratoryState();
}

class _LaboratoryState extends State<Laboratory> {
  bool pending = false;
  String? feedback;
  Map<String, dynamic>? qualities;
  Future<void> check() async {
    if (pending || !BuildChannel.isTesting) return;
    setState(() {
      pending = true;
      feedback = null;
      qualities = null;
    });
    try {
      final result = await widget.controller.bridge.call('auditFields');
      if (!mounted) return;
      final audit = result['adaptation_audit'];
      if (audit is! Map || audit['qualities'] is! Map) {
        throw StateError('Missing audit result');
      }
      setState(() {
        qualities = Map<String, dynamic>.from(audit['qualities'] as Map);
        feedback = Strings.text('check_completed');
      });
    } catch (_) {
      if (mounted) setState(() => feedback = Strings.text('check_failed'));
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => !BuildChannel.isTesting
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                Strings.text('laboratory_description'),
                style: TextStyle(
                  color: Palette.of(context).muted,
                  fontSize: 16,
                ),
              ),
            ),
            ParameterRow(
              Strings.text('text_9fd69b1f22'),
              trailing: IndustrialButton(
                Strings.text(pending ? 'checking' : 'start_check'),
                width: 160,
                onPressed: pending ? null : check,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                Strings.text('adaptation_check_description'),
                style: TextStyle(
                  fontSize: 16,
                  color: Palette.of(context).muted,
                ),
              ),
            ),
            if (feedback != null) Text(feedback!),
            if (qualities != null)
              for (final entry in qualities!.entries)
                ParameterRow(
                  entry.key == 'not_attempted'
                      ? Strings.text('quality_not_attempted')
                      : Sample(quality: entry.key).qualityLabel,
                  trailing: Text('${entry.value}'),
                ),
          ],
        );
}

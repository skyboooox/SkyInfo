import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_controller.dart';
import '../l10n/strings.dart';
import 'industrial.dart';
import 'design_dialog.dart';

class NetworkAdbSettings extends StatefulWidget {
  final AppController controller;
  final ValueChanged<int> onNavigate, onTab;
  const NetworkAdbSettings({
    super.key,
    required this.controller,
    required this.onNavigate,
    required this.onTab,
  });
  @override
  State<NetworkAdbSettings> createState() => _NetworkAdbSettingsState();
}

class _NetworkAdbSettingsState extends State<NetworkAdbSettings> {
  late final host = TextEditingController(text: widget.controller.adbHost);
  late final port = TextEditingController(text: '${widget.controller.adbPort}');
  final pairingPort = TextEditingController(), code = TextEditingController();
  late bool enabled = widget.controller.adbEnabled;
  late String mode = widget.controller.adbMode;
  bool busy = false, feedbackError = false;
  String? feedback;
  @override
  void dispose() {
    host.dispose();
    port.dispose();
    pairingPort.dispose();
    code.dispose();
    super.dispose();
  }

  bool validHost(String host) =>
      host.isNotEmpty &&
      host.length <= 253 &&
      !RegExp(r'''[\s/@'";\\]''').hasMatch(host);
  int? validPort(String value) {
    final port = int.tryParse(value);
    return port != null && port >= 1 && port <= 65535 ? port : null;
  }

  Future<void> pair() async {
    final pairing = validPort(pairingPort.text);
    if (!validHost(host.text.trim()) ||
        pairing == null ||
        !RegExp(r'^[0-9]{6}$').hasMatch(code.text)) {
      setState(() {
        feedbackError = true;
        feedback = Strings.text('adb_pair_invalid');
      });
      return;
    }
    setState(() {
      busy = true;
      feedback = null;
    });
    var success = false;
    try {
      final result = await widget.controller.bridge.call('pairAdb', {
        'host': host.text.trim(),
        'port': pairing,
        'code': code.text,
      });
      success = result['result'] == 'paired';
    } catch (_) {
      success = false;
    }
    code.clear();
    if (mounted) {
      setState(() {
        busy = false;
        feedbackError = !success;
        feedback = Strings.text(
          success ? 'adb_pair_success' : 'adb_pair_failed',
        );
      });
    }
  }

  Future<void> save() async {
    final connectionPort = validPort(port.text);
    if (!validHost(host.text.trim()) || connectionPort == null) {
      setState(() {
        feedbackError = true;
        feedback = Strings.text('adb_invalid');
      });
      return;
    }
    final c = widget.controller, previous = widget.controller.config;
    setState(() {
      busy = true;
      feedback = null;
    });
    c.adbHost = host.text.trim();
    c.adbPort = connectionPort;
    c.adbMode = mode;
    c.adbEnabled = enabled;
    if (await c.save()) {
      if (enabled) await c.action('reconnectAdb');
      if (mounted) setState(() => busy = false);
    } else {
      c.restore(previous);
      if (mounted) {
        setState(() {
          busy = false;
          feedbackError = true;
          feedback = c.error;
        });
      }
    }
  }

  Widget input(
    String label,
    TextEditingController controller, {
    bool digits = false,
    String? hint,
    bool secret = false,
  }) => ParameterRow(
    Strings.text(label),
    trailing: SizedBox(
      width: 700,
      child: TextField(
        controller: controller,
        enabled: !busy,
        autocorrect: false,
        enableSuggestions: false,
        obscureText: secret,
        keyboardType: digits ? TextInputType.number : TextInputType.url,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        inputFormatters: digits
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(secret ? 6 : 5),
              ]
            : null,
        decoration: InputDecoration(hintText: hint),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => SettingsEditor(
      controller: widget.controller,
      title: Strings.text('adb_title'),
      selectedTab: 4,
      onNavigate: widget.onNavigate,
      onTab: widget.onTab,
      footer: Row(
        children: [
          Expanded(
            child: feedback == null
                ? const SizedBox()
                : Text(
                    feedback!,
                    style: TextStyle(
                      color: feedbackError
                          ? Palette.of(context).red
                          : Palette.of(context).muted,
                    ),
                  ),
          ),
          IndustrialButton(
            Strings.text('cancel'),
            kind: ButtonKind.quiet,
            width: 96,
            onPressed: busy ? null : () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          IndustrialButton(
            Strings.text(enabled ? 'adb_connect' : 'save'),
            primary: true,
            width: 192,
            onPressed: busy ? null : save,
          ),
        ],
      ),
      child: Container(
        color: Palette.of(context).surface,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                Strings.text('adb_group'),
                style: TextStyle(color: Palette.of(context).muted),
              ),
            ),
            ParameterRow(
              Strings.text('adb_enable'),
              trailing: IndustrialSwitch(
                value: enabled,
                onChanged: busy
                    ? null
                    : (value) => setState(() => enabled = value),
              ),
            ),
            input('adb_host', host),
            input('adb_port', port, digits: true),
            ParameterRow(
              Strings.text('adb_mode'),
              trailing: SizedBox(
                width: 700,
                child: DropdownButton<String>(
                  value: mode,
                  isExpanded: true,
                  borderRadius: BorderRadius.zero,
                  items: [
                    for (final value in ['tcp', 'pair'])
                      DropdownMenuItem(
                        value: value,
                        child: Text(Strings.text('adb_mode_$value')),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          mode = value!;
                          feedback = null;
                        }),
                ),
              ),
            ),
            if (mode == 'pair') ...[
              input('adb_pair_port', pairingPort, digits: true),
              input(
                'adb_pair_code',
                code,
                digits: true,
                hint: Strings.text('adb_pair_placeholder'),
                secret: true,
              ),
              ParameterRow(
                Strings.text('adb_mode_pair'),
                trailing: IndustrialButton(
                  Strings.text('adb_pair'),
                  width: 160,
                  onPressed: busy ? null : pair,
                ),
              ),
            ],
            ParameterRow(
              Strings.text('ha_import_state'),
              trailing: Text(
                Strings.text(
                  'adb_status_${widget.controller.status['adb'] ?? 'disabled'}',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

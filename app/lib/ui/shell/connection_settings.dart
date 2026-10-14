part of 'home.dart';

extension _ConnectionSettings on _HomeState {
  Future<void> connectionSettings({String? initialMode}) async {
    final url = TextEditingController(text: c.haUrl),
        token = TextEditingController(),
        prefix = TextEditingController(text: c.prefix),
        host = TextEditingController(text: c.mqttHost),
        port = TextEditingController(text: '${c.mqttPort}'),
        user = TextEditingController(text: c.mqttUser),
        password = TextEditingController(),
        topic = TextEditingController(text: c.mqttTopic),
        birthTopic = TextEditingController(text: c.haBirthTopic),
        birthPayload = TextEditingController(text: c.haBirthPayload);
    final originalConfig = c.config;
    String mode = initialMode ?? c.connection;
    bool advanced = mode == 'mqtt';
    String protocol = c.mqttProtocol;
    String transport = c.mqttTransport;
    bool saving = false;
    bool fullState = c.mqttState;
    String? validation;
    final result = await showDesignDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SettingsEditor(
          controller: c,
          onNavigate: (p) {
            Navigator.pop(context);
            update(() {
              page = p;
              menuOpen = false;
            });
          },
          onTab: (t) {
            Navigator.pop(context);
            update(() {
              page = 3;
              settingsTab = t;
            });
          },
          title: mode == 'mqtt'
              ? Strings.text('text_605a11ec62')
              : Strings.text('text_c5bf073aba'),
          footer: Row(
            children: [
              Expanded(
                child: validation == null
                    ? SizedBox()
                    : Text(
                        validation!,
                        style: TextStyle(color: Palette.of(context).red),
                      ),
              ),
              SizedBox(
                width: 96,
                child: IndustrialButton(
                  Strings.text('cancel'),
                  kind: ButtonKind.quiet,
                  onPressed: saving ? null : () => Navigator.pop(context),
                ),
              ),
              SizedBox(width: 16),
              SizedBox(
                width: 192,
                child: IndustrialButton(
                  Strings.text('save'),
                  primary: true,
                  reduceMotion: c.reduceMotion,
                  onPressed: saving
                      ? null
                      : () async {
                          final endpoint = validHaEndpoint(url.text);
                          if (mode == 'ha' && endpoint == null) {
                            setState(
                              () =>
                                  validation = Strings.text('text_1c3c9dc393'),
                            );
                            return;
                          }
                          final mqttPort = int.tryParse(port.text);
                          if (mode == 'mqtt' &&
                              (host.text.trim().isEmpty ||
                                  host.text.contains('/') ||
                                  host.text.contains('@') ||
                                  mqttPort == null ||
                                  mqttPort < 1 ||
                                  mqttPort > 65535 ||
                                  topic.text.trim().isEmpty ||
                                  topic.text.contains('#') ||
                                  topic.text.contains('+'))) {
                            setState(
                              () =>
                                  validation = Strings.text('text_ecae147fe8'),
                            );
                            return;
                          }
                          if (!RegExp(
                            r'^[a-z0-9_]{1,48}$',
                          ).hasMatch(prefix.text.trim())) {
                            setState(
                              () =>
                                  validation = Strings.text('text_874cc4c277'),
                            );
                            return;
                          }
                          if (birthTopic.text.length > 256 ||
                              birthTopic.text.contains('#') ||
                              birthTopic.text.contains('+') ||
                              birthPayload.text.length > 256 ||
                              (birthTopic.text.isNotEmpty &&
                                  birthPayload.text.isEmpty)) {
                            setState(
                              () => validation = Strings.text(
                                'connection_invalid_birth',
                              ),
                            );
                            return;
                          }
                          setState(() => saving = true);
                          try {
                            final acknowledgements =
                                await confirmConnectionConfiguration(
                                  context,
                                  c,
                                  {
                                    'connection': mode,
                                    'haUrl': url.text.trim(),
                                    'mqttTransport': transport,
                                    'mqttHost': host.text.trim(),
                                    'mqttPort': mqttPort ?? 8883,
                                  },
                                );
                            if (acknowledgements == null || !context.mounted) {
                              return;
                            }
                            c.mqttProtocol = protocol;
                            c.mqttTransport = transport;
                            c.mqttState = fullState;
                            c.connection = mode;
                            c.haUrl = url.text.trim();
                            c.haBirthTopic = birthTopic.text.trim();
                            c.haBirthPayload = birthPayload.text;
                            c.prefix = prefix.text.trim();
                            c.mqttHost = host.text.trim();
                            c.mqttPort =
                                mqttPort ?? (transport == 'tls' ? 8883 : 1883);
                            c.mqttUser = user.text;
                            c.mqttTopic = topic.text.trim();
                            c.insecureAcknowledgements = acknowledgements;
                            Navigator.pop(context, true);
                          } finally {
                            if (context.mounted) setState(() => saving = false);
                          }
                        },
                ),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Panel(
                  title: Strings.text('text_30d94cb3b9'),
                  child: ListView(
                    padding: EdgeInsets.all(24),
                    children: [
                      if (mode == 'ha') ...[
                        ParameterInput(
                          controller: url,
                          label: 'Home Assistant URL',
                          hint: 'https://ha.example.com',
                          keyboardType: TextInputType.url,
                        ),
                        SizedBox(height: 16),
                        ParameterInput(
                          controller: token,
                          label: Strings.text('text_73bf8411b8'),
                          obscureText: true,
                          hint: Strings.text('text_af5da40b99'),
                        ),
                        SizedBox(height: 16),
                        ParameterInput(
                          controller: prefix,
                          label: Strings.text('text_7c83f3d8a1'),
                          maxLength: 48,
                        ),
                      ] else ...[
                        ParameterInput(
                          controller: host,
                          label: Strings.text('text_2eb291f695'),
                        ),
                        SizedBox(height: 16),
                        ParameterInput(
                          controller: port,
                          label: Strings.text('text_6cbb7335b5'),
                          keyboardType: TextInputType.number,
                        ),
                        ParameterRow(
                          Strings.text('connection_transport'),
                          trailing: DropdownButton<String>(
                            borderRadius: BorderRadius.zero,
                            value: transport,
                            items: [
                              DropdownMenuItem(
                                value: 'tls',
                                child: Text('TLS'),
                              ),
                              DropdownMenuItem(
                                value: 'tcp',
                                child: Text(
                                  Strings.text('connection_plain_tcp'),
                                ),
                              ),
                            ],
                            onChanged: saving
                                ? null
                                : (value) => setState(() {
                                    if (value == null) return;
                                    final previousDefault = transport == 'tls'
                                        ? 8883
                                        : 1883;
                                    transport = value;
                                    if (int.tryParse(port.text) ==
                                        previousDefault) {
                                      port.text = transport == 'tls'
                                          ? '8883'
                                          : '1883';
                                    }
                                  }),
                          ),
                        ),
                        ParameterInput(
                          controller: user,
                          label: Strings.text('text_a1aaf352cb'),
                        ),
                        SizedBox(height: 16),
                        ParameterInput(
                          controller: password,
                          label: Strings.text('text_c839a8ff17'),
                          obscureText: true,
                          hint: Strings.text('text_97a5744037'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(width: 24),
              Expanded(
                child: Panel(
                  title: mode == 'ha'
                      ? 'Home Assistant'
                      : Strings.text('text_94f172d02f'),
                  child: ListView(
                    padding: EdgeInsets.all(24),
                    children: [
                      if (mode == 'ha') ...[
                        ParameterRow(
                          Strings.text('text_56c7f934b5'),
                          trailing: Text('Home Assistant'),
                        ),
                        ParameterRow(
                          Strings.text('text_aca879b8f8'),
                          trailing: Text(Strings.text('text_dbea859a62')),
                        ),
                        ParameterRow(
                          Strings.text('page_connection'),
                          trailing: Text(
                            c.status['connection']?.toString() ??
                                Strings.text('text_ed9ec8188c'),
                          ),
                        ),
                        ParameterRow(
                          Strings.text('text_c009d0ab82'),
                          trailing: IndustrialSwitch(
                            value: advanced,
                            onChanged: (v) => setState(() => advanced = v),
                          ),
                        ),
                        if (advanced) ...[
                          ParameterInput(
                            controller: birthTopic,
                            label: Strings.text('connection_birth_topic'),
                            hint: 'homeassistant/status',
                          ),
                          SizedBox(height: 16),
                          ParameterInput(
                            controller: birthPayload,
                            label: Strings.text('connection_birth_payload'),
                            hint: 'online',
                          ),
                          SizedBox(height: 16),
                          IndustrialButton(
                            Strings.text('text_9f0ca615e8'),
                            onPressed: () => setState(() => mode = 'mqtt'),
                          ),
                        ],
                      ] else ...[
                        ParameterInput(
                          controller: topic,
                          label: Strings.text('text_702ddbc6f7'),
                        ),
                        ParameterRow(
                          Strings.text('text_071017752f'),
                          trailing: Text(Strings.text('text_a0c1a96b67')),
                        ),
                        ParameterRow(
                          Strings.text('text_1ae901d844'),
                          trailing: Text(Strings.text('on')),
                        ),
                        ParameterRow(
                          Strings.text('text_311609fd41'),
                          trailing: IndustrialSwitch(
                            value: fullState,
                            onChanged: (v) => setState(() => fullState = v),
                          ),
                        ),
                        ParameterRow(
                          Strings.text('text_9aa0af6f30'),
                          trailing: DropdownButton<String>(
                            borderRadius: BorderRadius.zero,
                            itemHeight: null,
                            value: protocol,
                            items: [
                              for (final v in ['5', '3.1.1'])
                                DropdownMenuItem(value: v, child: Text(v)),
                            ],
                            onChanged: (v) => setState(() => protocol = v!),
                          ),
                        ),
                        SizedBox(height: 16),
                        IndustrialButton(
                          'Home Assistant',
                          onPressed: () => setState(() => mode = 'ha'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true) {
      if (!await c.save(haToken: token.text, mqttPassword: password.text)) {
        c.restore(originalConfig);
      }
    }
    for (final input in [
      url,
      token,
      prefix,
      host,
      port,
      user,
      password,
      topic,
      birthTopic,
      birthPayload,
    ]) {
      input.dispose();
    }
  }
}

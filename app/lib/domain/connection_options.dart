Uri? validHaEndpoint(String input) {
  try {
    final uri = Uri.parse(input.trim());
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

String haEndpointIdentity(String input) {
  if (input.trim().isEmpty) return '';
  final uri = validHaEndpoint(input);
  if (uri == null) return input.trim();
  return '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}${uri.path.replaceFirst(RegExp(r'/+$'), '')}';
}

String? insecureConnectionKey({
  required String mode,
  required String haUrl,
  required String transport,
  required String mqttHost,
  required int mqttPort,
}) {
  if (mode == 'ha') {
    return validHaEndpoint(haUrl)?.scheme == 'http'
        ? 'ha|${haEndpointIdentity(haUrl)}'
        : null;
  }
  return transport == 'tcp'
      ? 'mqtt|tcp|${mqttHost.trim().toLowerCase()}|$mqttPort'
      : null;
}

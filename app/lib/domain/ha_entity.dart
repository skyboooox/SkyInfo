import 'metrics.dart';

class HaFunction {
  final String key, kind, label, expected;
  final List<String> options;
  final double? minimum, maximum, step;
  final bool confirmation;
  const HaFunction({
    required this.key,
    required this.kind,
    required this.label,
    this.expected = '',
    this.options = const [],
    this.minimum,
    this.maximum,
    this.step,
    this.confirmation = false,
  });
  factory HaFunction.fromJson(Map<String, dynamic> j) => HaFunction(
    key: j['key'],
    kind: j['kind'],
    label: j['label'],
    expected: j['expected'] ?? '',
    options: List<String>.from(j['options'] ?? []),
    minimum: (j['min'] as num?)?.toDouble(),
    maximum: (j['max'] as num?)?.toDouble(),
    step: (j['step'] as num?)?.toDouble(),
    confirmation: j['confirmation'] == true,
  );
}

class HaEntity {
  final String id, entityId, name, domain, deviceId, device, area;
  final Map<String, dynamic> attributes;
  final List<HaFunction> functions;
  final Metric metric;
  const HaEntity({
    required this.id,
    required this.entityId,
    required this.name,
    required this.domain,
    required this.deviceId,
    required this.device,
    required this.area,
    required this.attributes,
    required this.functions,
    required this.metric,
  });
  factory HaEntity.fromJson(Map<String, dynamic> j) => HaEntity(
    id: j['id'],
    entityId: j['entityId'],
    name: j['name'],
    domain: j['domain'],
    deviceId: j['deviceId'] ?? '',
    device: j['device'] ?? '',
    area: j['area'] ?? '',
    attributes: Map<String, dynamic>.from(j['attributes'] ?? {}),
    functions: (j['functions'] as List? ?? [])
        .map((f) => HaFunction.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
    metric: Metric.fromJson(Map<String, dynamic>.from(j['field'])),
  );
  String attributeId(String key) => '$id|$key';
  bool matches(String text) => [
    name,
    entityId,
    device,
    area,
  ].any((value) => value.toLowerCase().contains(text.toLowerCase()));
}

import '../l10n/strings.dart';
import 'models.dart';

enum EntityCapability { toggle, select, button, number }

class EntityOption {
  final int value;
  final String label;
  final int? expected;
  const EntityOption(this.value, this.label, this.expected);
  factory EntityOption.fromJson(Map<String, dynamic> j) => EntityOption(
    j['value'],
    j['labelKey'] == null ? j['label'] : Strings.text(j['labelKey']),
    j['expected'],
  );
}

class ControlEntity {
  final String action, name, category, icon, unit;
  final String? readField;
  final List<String> feedbackFields;
  final List<EntityOption> options;
  final Map<String, String> states;
  final bool inferred;
  final EntityCapability capability;
  const ControlEntity({
    required this.action,
    required this.name,
    required this.category,
    required this.icon,
    required this.unit,
    required this.readField,
    required this.feedbackFields,
    required this.options,
    required this.states,
    required this.inferred,
    required this.capability,
  });
  String get id => 'control.$action';
  factory ControlEntity.fromJson(Map<String, dynamic> j) => ControlEntity(
    action: j['id'],
    name: j['nameKey'] == null ? j['name'] : Strings.text(j['nameKey']),
    category: j['categoryKey'] == null
        ? j['category']
        : Strings.text(j['categoryKey']),
    icon: j['icon'] ?? 'tabler-car',
    unit: j['unit'] ?? '',
    readField: j['readField'],
    feedbackFields: List<String>.from(j['feedbackFields'] ?? []),
    options: (j['options'] as List)
        .map((o) => EntityOption.fromJson(Map<String, dynamic>.from(o)))
        .toList(),
    states: {
      for (final entry in Map<String, String>.from(j['states'] ?? {}).entries)
        entry.key: Strings.display(entry.value),
    },
    inferred: j['validation'] == 'inferred',
    capability: EntityCapability.values.byName(j['capability'] ?? 'button'),
  );
  Metric get metric => Metric(
    id: id,
    name: name,
    category: category,
    icon: icon,
    unit: unit,
    encoding: capability == EntityCapability.number ? 'number' : 'enum',
    entityKey: action,
    displayAllowed: true,
  );
  int? selectedValue(Sample sample) {
    if (sample.value == null) return null;
    for (final option in options) {
      if (option.expected == sample.raw) return option.value;
    }
    return null;
  }
}

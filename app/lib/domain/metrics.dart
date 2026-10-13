import '../l10n/strings.dart';

class Metric {
  final String id,
      name,
      category,
      icon,
      unit,
      encoding,
      entityKey,
      subscription;
  final bool displayAllowed, pairedUnit;
  const Metric({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.unit,
    required this.encoding,
    required this.entityKey,
    required this.displayAllowed,
    this.subscription = 'unverified',
    this.pairedUnit = false,
  });
  factory Metric.fromJson(Map<String, dynamic> j) => Metric(
    id: j['id'],
    name: j['nameKey'] == null ? j['name'] : Strings.text(j['nameKey']),
    category: j['categoryKey'] == null
        ? j['category']
        : Strings.text(j['categoryKey']),
    icon: j['icon'],
    unit: j['unit'],
    encoding: switch (j['encoding']) {
      '枚举' => 'enum',
      '文本' => 'text',
      _ => 'number',
    },
    entityKey: j['entityKey'],
    displayAllowed: j['displayAllowed'],
    subscription: j['subscription'] ?? 'unverified',
    pairedUnit: j['unitField'] != null,
  );
  String get displayUnit => unit.isNotEmpty
      ? unit
      : id.startsWith('ha|') || encoding == 'enum' || encoding == 'text'
      ? ''
      : Strings.text('raw_value');
  String displayUnitFor(Sample sample, [String? custom]) =>
      custom ??
      (sample.unit != null
          ? sample.unit!.isEmpty
                ? (id.startsWith('ha|') ||
                          encoding == 'enum' ||
                          encoding == 'text'
                      ? ''
                      : Strings.text('raw_value'))
                : sample.unit!
          : displayUnit);
}

enum WidgetKind {
  number('text_5215236493'),
  state('text_62e951a692'),
  text('text_bb7f204fc7'),
  pair('text_17d11a33d3'),
  list('text_e2c9f5a5b9'),
  glance('text_74f719a86c'),
  range('text_3a013ae52e'),
  gauge('text_aad5dfe3ba'),
  trend('text_376df657e6'),
  availability('text_fbc7de5a2e'),
  comparison('text_423a8111fb'),
  timeline('text_3c6baab8c0'),
  entity('text_4e4ca3dcc5'),
  toggle('text_d7716c4a8f'),
  select('text_221ee0cc94'),
  action('text_7c1965b15b'),
  numberControl('text_a09a525174'),
  entities('text_1bb96ba223'),
  device('text_8ad8e7c7b9');

  final String labelKey;
  String get label => Strings.text(labelKey);
  const WidgetKind(this.labelKey);
  bool get history => this == trend || this == comparison || this == timeline;
  bool get controls => index >= entity.index;
  bool get multiple => [
    pair,
    list,
    glance,
    availability,
    comparison,
    entities,
    device,
  ].contains(this);
  List<(int, int)> get sizes => switch (this) {
    number || state || text => [(1, 1), (1, 2), (2, 1), (2, 2)],
    pair => [(1, 2), (2, 1), (2, 2), (4, 2)],
    list ||
    glance ||
    availability ||
    entities ||
    device => [(2, 2), (2, 4), (4, 2)],
    entity || toggle || select || action || numberControl => [(2, 1), (2, 2)],
    range || timeline => [(2, 1), (2, 2), (4, 2)],
    _ => [(2, 2), (4, 2)],
  };
}

enum TimeDisplay { none, updated, changed }

String relativeAge(DateTime? at, DateTime now) {
  if (at == null || at.isAfter(now)) return '—';
  final seconds = now.difference(at).inSeconds;
  if (seconds < 60) return Strings.text('text_677fe3d598', {'value0': seconds});
  if (seconds < 3600) {
    return Strings.text('text_c5c33c482b', {'value0': seconds ~/ 60});
  }
  if (seconds < 86400) {
    return Strings.text('text_b2c5c8b72e', {'value0': seconds ~/ 3600});
  }
  return Strings.text('text_42a3b98192', {'value0': seconds ~/ 86400});
}

class Sample {
  final Object? value, raw;
  final String quality, source;
  final String? unit;
  final String? stateLabel;
  final DateTime? updatedAt, changedAt;
  const Sample({
    this.value,
    this.raw,
    this.quality = 'unverified',
    this.source = '',
    this.unit,
    this.stateLabel,
    this.updatedAt,
    this.changedAt,
  });
  factory Sample.fromJson(Map<String, dynamic> j) => Sample(
    value: j['value'],
    raw: j['raw'],
    quality: j['quality'] ?? 'unverified',
    source: j['source'] ?? '',
    unit: j['unit'],
    stateLabel: j['stateLabel'] == null
        ? null
        : Strings.display(j['stateLabel']),
    updatedAt: _date(j['updatedAt']),
    changedAt: _date(j['changedAt']),
  );
  static DateTime? _date(dynamic v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
  String get qualityLabel => switch (quality) {
    'available' => Strings.text('available'),
    'invalid' => Strings.text('invalid'),
    'error' => Strings.text('text_d9f607a200'),
    'timeout' => Strings.text('text_ff06c243d7'),
    'permission' => Strings.text('text_c664b782cd'),
    'disconnected' => Strings.text('text_f2f3e9803c'),
    'removed' => Strings.text('ha_removed'),
    'missing_attribute' => Strings.text('ha_missing_attribute'),
    'unavailable' => Strings.text('ha_unavailable'),
    'unsupported' => Strings.text('text_facf9394cc'),
    _ => Strings.text('text_6815896741'),
  };
  String formatted(int digits) => value == null
      ? '—'
      : stateLabel != null
      ? stateLabel!
      : value is double
      ? (value as double).toStringAsFixed(digits)
      : value.toString();
}

class TileSpec {
  final String id, title;
  final WidgetKind kind;
  final List<String> fields, hiddenControls;
  final int columns, rows, digits;
  final TimeDisplay time;
  final Map<String, String> icons, units;
  final double? minimum, maximum;
  final int historyMinutes;
  final int? column, row;
  final Map<String, String> labels;
  final String? icon;
  final double? fontSize;
  final int glanceColumns;
  final double rowHeight;
  final bool showTitle, showUnits, showIcon, showDataIcons;
  const TileSpec({
    required this.id,
    required this.title,
    required this.kind,
    required this.fields,
    this.columns = 2,
    this.rows = 2,
    this.digits = 1,
    this.time = TimeDisplay.none,
    this.icons = const {},
    this.units = const {},
    this.minimum,
    this.maximum,
    this.historyMinutes = 30,
    this.column,
    this.row,
    this.labels = const {},
    this.icon,
    this.fontSize,
    this.glanceColumns = 2,
    this.rowHeight = 84,
    this.showTitle = true,
    this.showUnits = true,
    this.showIcon = true,
    this.showDataIcons = true,
    this.hiddenControls = const [],
  });
  factory TileSpec.fromJson(Map<String, dynamic> j) => TileSpec(
    id: j['id'],
    title: j['title'],
    kind: WidgetKind.values.byName(j['kind']),
    fields: List<String>.from(j['fields']),
    columns: j['columns'] ?? 2,
    rows: j['rows'] ?? 2,
    digits: j['digits'] ?? 1,
    time: TimeDisplay.values.byName(j['time'] ?? 'none'),
    icons: Map<String, String>.from(j['icons'] ?? {}),
    units: Map<String, String>.from(j['units'] ?? {}),
    minimum: (j['minimum'] as num?)?.toDouble(),
    maximum: (j['maximum'] as num?)?.toDouble(),
    historyMinutes: j['historyMinutes'] ?? 30,
    column: j['column'],
    row: j['row'],
    labels: Map<String, String>.from(j['labels'] ?? {}),
    icon: j['icon'],
    fontSize: (j['fontSize'] as num?)?.toDouble(),
    glanceColumns: j['glanceColumns'] ?? 2,
    rowHeight: (j['rowHeight'] as num? ?? 84).toDouble(),
    showTitle: j['showTitle'] ?? true,
    showUnits: j['showUnits'] ?? true,
    showIcon: j['showIcon'] ?? true,
    showDataIcons: j['showDataIcons'] ?? true,
    hiddenControls: List<String>.from(j['hiddenControls'] ?? []),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'fields': fields,
    'columns': columns,
    'rows': rows,
    'digits': digits,
    'time': time.name,
    'icons': icons,
    'units': units,
    'minimum': minimum,
    'maximum': maximum,
    'historyMinutes': historyMinutes,
    'column': column,
    'row': row,
    'labels': labels,
    'icon': icon,
    'fontSize': fontSize,
    'glanceColumns': glanceColumns,
    'rowHeight': rowHeight,
    'showTitle': showTitle,
    'showUnits': showUnits,
    'showIcon': showIcon,
    'showDataIcons': showDataIcons,
    'hiddenControls': hiddenControls,
  };
}

extension TileChanges on TileSpec {
  TileSpec positioned(int? column, int? row, {int? columns, int? rows}) =>
      TileSpec(
        id: id,
        title: title,
        kind: kind,
        fields: fields,
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
        digits: digits,
        time: time,
        icons: icons,
        units: units,
        minimum: minimum,
        maximum: maximum,
        historyMinutes: historyMinutes,
        labels: labels,
        icon: icon,
        fontSize: fontSize,
        glanceColumns: glanceColumns,
        rowHeight: rowHeight,
        showTitle: showTitle,
        showUnits: showUnits,
        showIcon: showIcon,
        showDataIcons: showDataIcons,
        hiddenControls: hiddenControls,
        column: column,
        row: row,
      );
}

class OverlaySpec {
  final String id, field, icon, unit, alignment;
  final int digits;
  final bool unitAuto;
  const OverlaySpec({
    required this.id,
    required this.field,
    required this.icon,
    required this.unit,
    this.unitAuto = false,
    this.alignment = 'left',
    this.digits = 1,
  });
  factory OverlaySpec.fromJson(Map<String, dynamic> j) => OverlaySpec(
    id: j['id'],
    field: j['field'],
    icon: j['icon'],
    unit: j['unit'],
    alignment: j['alignment'],
    unitAuto: j['unitAuto'] ?? false,
    digits: j['digits'] ?? 1,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'field': field,
    'icon': icon,
    'unit': unit,
    'alignment': alignment,
    'unitAuto': unitAuto,
    'digits': digits,
  };
}

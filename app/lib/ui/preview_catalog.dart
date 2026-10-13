import '../l10n/strings.dart';
import '../domain/models.dart';

const voltageField = '1032/7/1128267816';
const gbCurrentField = '1039/5/677380120';
const batteryPowerField = 'derived.battery_power';
const temperatureFields = ['1014/5/1148190752', '1014/5/1148190736'];
const thermalFields = [
  '1005/5/1031798840',
  '1005/5/1320169504',
  '1006/5/1186988096',
];
const motorTemperatureFields = [
  '1039/5/1302331672',
  '1039/5/1302331756',
  '1039/5/1302331648',
  '1039/5/1302331748',
];
final componentPresets = [
  Strings.text('text_f645d5db37'),
  Strings.text('text_5c4792f489'),
  Strings.text('text_fc29d712b1'),
  Strings.text('text_adf04dee75'),
  Strings.text('text_c9ad76452e'),
  Strings.text('text_6b9132add5'),
  Strings.text('text_9182f9929f'),
  Strings.text('text_83225e05c7'),
  Strings.text('text_c9fe857183'),
  Strings.text('text_7478303d38'),
  Strings.text('text_4b1fea91c8'),
];

TileSpec componentPreset(String name) {
  final (kind, fields) = switch (name) {
    final label when label == Strings.text('text_5c4792f489') => (
      WidgetKind.number,
      [thermalFields.first],
    ),
    final label when label == Strings.text('text_fc29d712b1') => (
      WidgetKind.list,
      thermalFields,
    ),
    final label when label == Strings.text('text_adf04dee75') => (
      WidgetKind.pair,
      temperatureFields,
    ),
    final label when label == Strings.text('text_c9ad76452e') => (
      WidgetKind.pair,
      ['1014/5/1147142192', '1014/5/1147142160'],
    ),
    final label when label == Strings.text('text_6b9132add5') => (
      WidgetKind.glance,
      motorTemperatureFields,
    ),
    final label when label == Strings.text('text_9182f9929f') => (
      WidgetKind.text,
      ['system.firmware_version'],
    ),
    final label when label == Strings.text('text_83225e05c7') => (
      WidgetKind.availability,
      [voltageField, ...thermalFields.take(2)],
    ),
    final label when label == Strings.text('text_c9fe857183') => (
      WidgetKind.comparison,
      temperatureFields,
    ),
    final label when label == Strings.text('text_7478303d38') => (
      WidgetKind.number,
      [gbCurrentField],
    ),
    final label when label == Strings.text('text_4b1fea91c8') => (
      WidgetKind.number,
      [batteryPowerField],
    ),
    _ => (WidgetKind.number, [voltageField]),
  };
  return TileSpec(
    id: '',
    title: name,
    kind: kind,
    fields: fields,
    columns: kind.history ? 4 : 2,
  );
}

TileSpec stylePreview(WidgetKind kind) {
  final fields = switch (kind) {
    WidgetKind.number => [gbCurrentField],
    WidgetKind.pair || WidgetKind.comparison => temperatureFields,
    WidgetKind.list || WidgetKind.availability => thermalFields,
    WidgetKind.glance => motorTemperatureFields,
    WidgetKind.text => ['system.firmware_version'],
    WidgetKind.state || WidgetKind.timeline => ['1009/5/876609586'],
    WidgetKind.trend => [batteryPowerField],
    WidgetKind.entity || WidgetKind.toggle => ['control.ac_front_defrost'],
    WidgetKind.select => ['control.ac_cycle'],
    WidgetKind.action => ['control.air_purify'],
    WidgetKind.numberControl => ['control.ac_temperature'],
    WidgetKind.entities => [
      voltageField,
      'control.ac_cycle',
      thermalFields.first,
    ],
    WidgetKind.device => ['control.ac_cycle', 'control.ac_front_defrost'],
    _ => [voltageField],
  };
  return TileSpec(
    id: 'preview-${kind.name}',
    title: kind.label,
    kind: kind,
    fields: fields,
    columns: kind.history ? 4 : 2,
    minimum: kind == WidgetKind.range || kind == WidgetKind.gauge ? 10 : null,
    maximum: kind == WidgetKind.range || kind == WidgetKind.gauge ? 16 : null,
    showIcon: false,
    showDataIcons: false,
  );
}

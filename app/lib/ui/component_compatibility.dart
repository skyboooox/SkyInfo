import '../data/app_controller.dart';
import '../domain/models.dart';

List<WidgetKind> compatibleKinds(AppController c, List<String> fields) {
  if (fields.isEmpty) return [];
  final numeric = fields.every((id) => c.metric(id).encoding == 'number');
  final controls = fields.any(c.isControl);
  final deviceKeys = fields
      .map(
        (id) => id.startsWith('ha|')
            ? c.haEntity(id)?.deviceId ?? ''
            : 'vehicle:${c.metric(id).category}',
      )
      .toSet();
  return WidgetKind.values.where((kind) {
    if (!kind.multiple && fields.length != 1 ||
        kind == WidgetKind.pair && fields.length != 2) {
      return false;
    }
    if (fields.any((id) => id.startsWith('control.')) && !kind.controls) {
      return false;
    }
    if ([
          WidgetKind.number,
          WidgetKind.pair,
          WidgetKind.range,
          WidgetKind.gauge,
          WidgetKind.trend,
          WidgetKind.comparison,
        ].contains(kind) &&
        !numeric) {
      return false;
    }
    if (kind == WidgetKind.comparison &&
        !comparableFields(fields, c.allMetrics)) {
      return false;
    }
    if (kind == WidgetKind.device &&
        (deviceKeys.length != 1 || deviceKeys.contains(''))) {
      return false;
    }
    if ([
      WidgetKind.toggle,
      WidgetKind.select,
      WidgetKind.action,
      WidgetKind.numberControl,
    ].contains(kind)) {
      final id = fields.single;
      final capability = {
        WidgetKind.toggle: 'toggle',
        WidgetKind.select: 'select',
        WidgetKind.action: 'button',
        WidgetKind.numberControl: 'number',
      }[kind];
      if (id.startsWith('control.')) {
        return c.controlEntity(id).capability.name == capability;
      }
      return id.split('|').length == 3 &&
          (c.haEntity(id)?.functions.any((f) => f.kind == capability) ?? false);
    }
    if (kind.controls &&
        !controls &&
        ![WidgetKind.entities, WidgetKind.device].contains(kind)) {
      return false;
    }
    return true;
  }).toList();
}

WidgetKind recommendedKind(AppController c, List<String> fields) =>
    fields.length > 1
    ? WidgetKind.entities
    : c.isControl(fields.first)
    ? WidgetKind.entity
    : c.metric(fields.first).encoding == 'number'
    ? WidgetKind.number
    : WidgetKind.state;

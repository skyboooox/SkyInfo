import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../l10n/strings.dart';
import 'design_dialog.dart';
import 'industrial.dart';

Future<String?> showFieldDetails(
  BuildContext context,
  AppController controller,
  String id, {
  bool chooseAttribute = false,
}) => showDesignDialog<String>(
  context: context,
  builder: (_) => _FieldDetails(controller, id, chooseAttribute),
);

class _FieldDetails extends StatefulWidget {
  final AppController controller;
  final String id;
  final bool chooseAttribute;
  const _FieldDetails(this.controller, this.id, this.chooseAttribute);
  @override
  State<_FieldDetails> createState() => _FieldDetailsState();
}

class _FieldDetailsState extends State<_FieldDetails> {
  bool authorizing = false;
  late final lease = widget.controller.acquirePreview([widget.id]);
  @override
  void initState() {
    super.initState();
    lease;
  }

  @override
  void dispose() {
    lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        id = widget.id,
        metric = c.metric(id),
        entity = c.haEntity(id);
    return DesignDialog(
      title: metric.name,
      width: 720,
      height: 720,
      footer: Align(
        alignment: Alignment.centerRight,
        child: IndustrialButton(
          Strings.text('close'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      child: ValueListenableBuilder<Sample>(
        valueListenable: c.reading(id),
        builder: (context, sample, _) => ListView(
          children: [
            Text(
              '${sample.formatted(2)} ${metric.displayUnitFor(sample)}',
              style: const TextStyle(fontSize: 40),
            ),
            ParameterRow(
              Strings.text('source'),
              trailing: Text(
                id.startsWith('ha|')
                    ? 'Home Assistant'
                    : id == 'location.gnss_altitude'
                    ? Strings.text('gnss_source')
                    : Strings.text('vehicle_source'),
              ),
            ),
            ParameterRow(
              Strings.text('ha_entity_id'),
              trailing: Flexible(
                child: SelectableText(
                  entity?.entityId ?? id,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            ParameterRow(
              Strings.text('quality'),
              trailing: Text(sample.qualityLabel),
            ),
            if (id == 'location.gnss_altitude')
              ParameterRow(
                Strings.text('altitude_reference'),
                trailing: Text(Strings.text('wgs84_ellipsoid')),
              ),
            if (id == 'location.gnss_altitude' &&
                sample.quality == 'permission')
              ParameterRow(
                Strings.text('location_authorization_hint'),
                trailing: IndustrialButton(
                  Strings.text('location_authorization'),
                  kind: ButtonKind.secondary,
                  width: 160,
                  onPressed: authorizing
                      ? null
                      : () async {
                          setState(() => authorizing = true);
                          try {
                            await c.action('requestLocation');
                          } finally {
                            if (mounted) setState(() => authorizing = false);
                          }
                        },
                ),
              ),
            if (entity != null) ...[
              if (entity.device.isNotEmpty)
                ParameterRow(
                  Strings.text('ha_device'),
                  trailing: Text(entity.device),
                ),
              if (entity.area.isNotEmpty)
                ParameterRow(
                  Strings.text('ha_area'),
                  trailing: Text(entity.area),
                ),
              ParameterRow(
                Strings.text('ha_functions'),
                trailing: Text(
                  entity.functions.isEmpty
                      ? Strings.text('readonly')
                      : entity.functions
                            .map((f) => Strings.text(f.label))
                            .join(' / '),
                ),
              ),
              if (widget.chooseAttribute && id.split('|').length == 3) ...[
                ParameterRow(
                  Strings.text('ha_state'),
                  trailing: const Icon(Icons.chevron_right, size: 24),
                  onTap: () => Navigator.pop(context, id),
                ),
                for (final field in c.haFields.values.where(
                  (f) => f.id.startsWith('$id|'),
                ))
                  ParameterRow(
                    field.id.split('|').last,
                    trailing: Flexible(
                      child: Text(
                        '${entity.attributes[field.id.split('|').last]} ${field.displayUnit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, field.id),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

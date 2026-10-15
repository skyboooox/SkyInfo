import '../l10n/strings.dart';
import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import 'design_dialog.dart';
import 'industrial.dart';
import 'metric_tile.dart';
import 'history_chart.dart';
import 'layout.dart';
import 'data_activity.dart';
import 'retained_history.dart';

Future<int?> chooseHistoryWindow(
  BuildContext context,
  AppController c,
  int initial, {
  VoidCallback? onConnection,
  ValueChanged<int>? onChanged,
}) async {
  var current = initial;
  await showDesignDialog<void>(
    context: context,
    builder: (_) => _HistorySettings(c, initial, onConnection, (value) {
      current = value;
      onChanged?.call(value);
    }),
  );
  return current;
}

class _HistorySettings extends StatefulWidget {
  final AppController c;
  final int initial;
  final VoidCallback? onConnection;
  final ValueChanged<int> onChanged;
  const _HistorySettings(
    this.c,
    this.initial,
    this.onConnection,
    this.onChanged,
  );
  @override
  State<_HistorySettings> createState() => _HistorySettingsState();
}

class _HistorySettingsState extends State<_HistorySettings> {
  late int minutes = widget.initial;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return DesignDialog(
      title: Strings.text('text_ae96d42107'),
      footer: Align(
        alignment: Alignment.centerRight,
        child: IndustrialButton(
          Strings.text('close'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      child: ListView(
        children: [
          ParameterRow(
            Strings.text('text_56c7f934b5'),
            trailing: Text(Strings.text('text_8b4c1c5f0c')),
          ),
          ParameterRow(
            Strings.text('text_8d995281bf'),
            trailing: SizedBox(
              width: 192,
              child: DropdownButtonFormField<int>(
                borderRadius: BorderRadius.zero,
                itemHeight: null,
                initialValue: minutes,
                isExpanded: true,
                items: [
                  for (final n in ({5, 15, 30, 120, minutes}.toList()..sort()))
                    DropdownMenuItem(
                      value: n,
                      child: Text(
                        Strings.text('text_db8d00ea5b', {'value0': n}),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => minutes = value);
                    widget.onChanged(value);
                  }
                },
              ),
            ),
          ),
          ParameterRow(
            Strings.text('retention'),
            trailing: Text(
              Strings.text('text_b16f805a29', {
                'value0': c.localHistoryMinutes,
              }),
            ),
          ),
          ParameterRow(
            Strings.text('text_aca879b8f8'),
            trailing: Text(
              c.localHistory
                  ? Strings.text('text_2bf163bcf2')
                  : Strings.text('text_dbea859a62'),
            ),
          ),
          ParameterRow(
            Strings.text('text_cdc52e7e86'),
            trailing: Text(
              Strings.text(
                c.retainHistory ? 'text_d046ac70de' : 'text_7d431991f3',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showHistoryDetails(
  BuildContext context,
  AppController c,
  TileSpec tile, {
  required VoidCallback onEdit,
  VoidCallback? onConnection,
}) => showDesignDialog<void>(
  context: context,
  builder: (_) => _HistoryDetails(c, tile, onEdit, onConnection),
);

class _HistoryDetails extends StatefulWidget {
  final AppController c;
  final TileSpec tile;
  final VoidCallback onEdit;
  final VoidCallback? onConnection;
  const _HistoryDetails(this.c, this.tile, this.onEdit, this.onConnection);
  @override
  State<_HistoryDetails> createState() => _HistoryDetailsState();
}

class _HistoryDetailsState extends State<_HistoryDetails> {
  final historyApplied = ValueNotifier<int>(0);
  @override
  void dispose() {
    historyApplied.dispose();
    super.dispose();
  }

  late int minutes = widget.tile.historyMinutes;
  late Future<List<List<HistoryPoint>>> history = query();
  Future<List<List<HistoryPoint>>> query({bool refresh = false}) => Future.wait(
    widget.tile.fields.map(
      (id) => widget.c.history(id, minutes, refresh: refresh),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = widget.c, tile = widget.tile, p = Palette.of(context);
    return DesignDialog(
      title: tile.title,
      leading: DataActivityDot(
        readings: [for (final id in tile.fields) c.reading(id)],
        historyApplied: historyApplied,
      ),
      footer: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 192,
          child: IndustrialButton(
            Strings.text('close'),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      child: AdaptivePanels(
        first: Panel(
          title: Strings.text('text_fe1b82573b'),
          child: ListView(
            padding: EdgeInsets.all(24),
            children: [
              SizedBox(
                height: tile.kind.multiple ? 220 : 182,
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 380,
                    child: MetricTile(
                      tile: TileSpec(
                        id: 'current',
                        title: tile.title,
                        kind: tile.kind.multiple
                            ? WidgetKind.list
                            : tile.kind == WidgetKind.timeline
                            ? WidgetKind.state
                            : WidgetKind.number,
                        fields: tile.fields,
                        units: tile.units,
                        digits: tile.digits,
                        icons: tile.icons,
                        icon: tile.icon,
                        labels: tile.labels,
                        time: tile.time,
                        rows: tile.kind.multiple ? 2 : 1,
                        fontSize: 56,
                      ),
                      controller: c,
                      now: DateTime.now(),
                      preview: true,
                      onEdit: () {},
                    ),
                  ),
                ),
              ),
              ParameterRow(
                Strings.text('text_98dbf1f9d5'),
                trailing: Text(
                  Strings.text('text_db8d00ea5b', {'value0': minutes}),
                ),
              ),
              ParameterRow(
                Strings.text('text_8ec8c8c712'),
                trailing: Text(
                  tile.fields
                      .map(
                        (id) => c
                            .metric(id)
                            .displayUnitFor(
                              c.reading(id).value,
                              tile.units[id],
                            ),
                      )
                      .toSet()
                      .join(' / '),
                ),
              ),
              ParameterRow(
                Strings.text('text_56c7f934b5'),
                trailing: Text(Strings.text('text_8b4c1c5f0c')),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: 192,
                child: IndustrialButton(
                  Strings.text('text_530b5e0c70'),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onEdit();
                  },
                ),
              ),
              SizedBox(height: 12),
              SizedBox(
                width: 192,
                child: IndustrialButton(
                  Strings.text('text_ae96d42107'),
                  onPressed: () async {
                    final n = await chooseHistoryWindow(
                      context,
                      c,
                      minutes,
                      onConnection: widget.onConnection,
                      onChanged: (value) {
                        if (mounted) {
                          setState(() {
                            minutes = value;
                            history = query();
                          });
                        }
                      },
                    );
                    if (n != null && n != minutes && mounted) {
                      setState(() {
                        minutes = n;
                        history = query();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        second: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(border: Border.all(color: p.grid)),
          child: Column(
            children: [
              ChoiceButtons<int>(
                value: minutes,
                values: const [5, 15, 30, 120],
                label: (v) => v == 120
                    ? Strings.text('text_2b2c1f3643')
                    : Strings.text('text_b16f805a29', {'value0': v}),
                onChanged: (v) => setState(() {
                  minutes = v;
                  history = query();
                }),
              ),
              SizedBox(height: 24),
              Expanded(
                child: RetainedHistory(
                  key: ValueKey((c, tile.fields.join('\u0000'), minutes)),
                  future: history,
                  onApplied: () => historyApplied.value++,
                  builder: (data) {
                    return tile.kind == WidgetKind.timeline
                        ? StateTimeline(points: data.first, minutes: minutes)
                        : HistoryChart(
                            series: data,
                            minutes: minutes,
                            minimum: tile.minimum,
                            maximum: tile.maximum,
                          );
                  },
                ),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tile.fields
                          .map((id) => tile.labels[id] ?? c.metric(id).name)
                          .join(' · '),
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    tooltip: Strings.text('text_a99001a7bf'),
                    onPressed: () =>
                        setState(() => history = query(refresh: true)),
                    icon: Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        firstFlex: 512,
        secondFlex: 856,
      ),
    );
  }
}

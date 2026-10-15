import '../l10n/strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import 'industrial.dart';
import 'entity_content.dart';
import 'history_chart.dart';
import 'value_gauge.dart';
import 'touch_targets.dart';
import 'data_activity.dart';
import 'retained_history.dart';

class MetricTile extends StatefulWidget {
  final TileSpec tile;
  final AppController controller;
  final DateTime now;
  final bool editing, preview, externalEditAction;
  final VoidCallback? onHistory;
  final DateTime Function()? clock;
  final VoidCallback onEdit;
  const MetricTile({
    super.key,
    required this.tile,
    required this.controller,
    required this.now,
    required this.onEdit,
    this.editing = false,
    this.preview = false,
    this.externalEditAction = false,
    this.onHistory,
    this.clock,
  });
  @override
  State<MetricTile> createState() => _MetricTileState();
}

class _MetricTileState extends State<MetricTile> {
  final historyApplied = ValueNotifier<int>(0);
  DateTime get displayNow => widget.clock?.call() ?? widget.now;
  Future<List<List<HistoryPoint>>>? _history;
  Timer? _historyRefresh;
  final _historyListeners = <(ValueNotifier<Sample>, VoidCallback)>[];
  void _bindHistory() {
    for (final listener in _historyListeners) {
      listener.$1.removeListener(listener.$2);
    }
    _historyListeners.clear();
    _historyRefresh?.cancel();
    _historyRefresh = null;
    if (!widget.tile.kind.history) return;
    for (final id in widget.tile.fields) {
      final reading = widget.controller.reading(id);
      Object signature(Sample s) =>
          (s.value, s.quality, s.unit, s.source, s.stateLabel);
      var previous = signature(reading.value);
      void changed() {
        final next = signature(reading.value);
        if (next == previous) return;
        previous = next;
        _historyRefresh ??= Timer(Duration(seconds: 5), () {
          _historyRefresh = null;
          if (mounted) setState(() => _query(refresh: true));
        });
      }

      reading.addListener(changed);
      _historyListeners.add((reading, changed));
    }
  }

  @override
  void dispose() {
    _historyRefresh?.cancel();
    for (final listener in _historyListeners) {
      listener.$1.removeListener(listener.$2);
    }
    historyApplied.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bindHistory();
    _query();
  }

  @override
  void didUpdateWidget(MetricTile old) {
    super.didUpdateWidget(old);
    if (old.tile != widget.tile || old.controller != widget.controller) {
      _bindHistory();
      _query();
    } else if (widget.tile.kind.history &&
        widget.now.difference(old.now).inSeconds >= 0 &&
        widget.now.millisecondsSinceEpoch ~/ 60000 !=
            old.now.millisecondsSinceEpoch ~/ 60000) {
      _query();
    }
  }

  void _query({bool refresh = false}) {
    if (widget.tile.kind.history) {
      _history = Future.wait(
        widget.tile.fields.map(
          (f) => widget.controller.history(
            f,
            widget.tile.historyMinutes,
            refresh: refresh,
          ),
        ),
      );
    }
  }

  Widget reading(String id, {bool mini = false, bool named = false}) {
    final m = widget.controller.metric(id),
        p = Palette.of(context),
        tile = widget.tile;
    return ValueListenableBuilder<Sample>(
      valueListenable: widget.controller.reading(id),
      builder: (context, s, _) {
        final icon = tile.showDataIcons ? tile.icons[id] : null;
        final time = tile.time == TimeDisplay.none
            ? null
            : relativeAge(
                tile.time == TimeDisplay.updated ? s.updatedAt : s.changedAt,
                displayNow,
              );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (named)
              Row(
                children: [
                  if (icon != null) ...[
                    MetricIcon(icon, size: mini ? 20 : 28),
                    SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      tile.labels[id] ?? m.name,
                      maxLines: 2,
                      style: TextStyle(color: p.muted, fontSize: 18),
                    ),
                  ),
                ],
              ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      s.formatted(tile.digits),
                      style: TextStyle(
                        fontFamily: s.formatted(tile.digits) == '—'
                            ? 'ChillDIN'
                            : 'IBMPlexMono',
                        fontWeight: FontWeight.w500,
                        fontSize:
                            tile.fontSize ??
                            (mini
                                ? 32
                                : tile.kind == WidgetKind.number &&
                                      tile.rows > 1
                                ? 84
                                : 56),
                        height: s.formatted(tile.digits) == '—' ? null : 1.1,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      tile.showUnits ? m.displayUnitFor(s, tile.units[id]) : '',
                      style: TextStyle(fontSize: 16, color: p.muted),
                    ),
                  ],
                ),
              ),
            ),
            if (time != null)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  time,
                  style: TextStyle(fontSize: 16, color: p.muted),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget listEntry(String id) {
    final m = widget.controller.metric(id),
        p = Palette.of(context),
        t = widget.tile;
    return ValueListenableBuilder<Sample>(
      valueListenable: widget.controller.reading(id),
      builder: (context, s, _) => Container(
        constraints: BoxConstraints(minHeight: t.rowHeight),
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.grid)),
        ),
        child: Row(
          children: [
            if (t.showDataIcons && t.icons[id] != null) ...[
              MetricIcon(t.icons[id], size: 32),
              SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.labels[id] ?? m.name,
                    style: TextStyle(fontSize: 20, color: p.muted),
                  ),
                  if (t.time != TimeDisplay.none)
                    Text(
                      relativeAge(
                        t.time == TimeDisplay.updated
                            ? s.updatedAt
                            : s.changedAt,
                        displayNow,
                      ),
                      style: TextStyle(fontSize: 16, color: p.muted),
                    ),
                ],
              ),
            ),
            if (t.kind == WidgetKind.availability) ...[
              Icon(
                Icons.circle,
                size: 10,
                color: s.quality == 'available' ? p.green : p.muted,
              ),
              SizedBox(width: 8),
              Text(s.qualityLabel, style: TextStyle(fontSize: 18)),
            ] else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        s.formatted(t.digits),
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          fontWeight: FontWeight.w500,
                          fontSize: 32,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        t.showUnits ? m.displayUnitFor(s, t.units[id]) : '',
                        style: TextStyle(fontSize: 16, color: p.muted),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget history() {
    return Column(
      children: [
        if (widget.tile.rows > 1)
          SizedBox(
            height: 48,
            child: Row(
              children: [
                for (final id in widget.tile.fields)
                  Expanded(
                    child: ValueListenableBuilder<Sample>(
                      valueListenable: widget.controller.reading(id),
                      builder: (context, sample, _) => Text(
                        '${widget.tile.labels[id] ?? widget.controller.metric(id).name}  ${sample.formatted(widget.tile.digits)} ${widget.tile.showUnits ? widget.controller.metric(id).displayUnitFor(sample, widget.tile.units[id]) : ''}${widget.tile.time == TimeDisplay.none ? '' : ' · ${relativeAge(widget.tile.time == TimeDisplay.updated ? sample.updatedAt : sample.changedAt, displayNow)}'}',
                        style: TextStyle(fontSize: 16),
                        maxLines: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RetainedHistory(
            key: ValueKey((
              widget.controller,
              widget.tile.fields.join('\u0000'),
              widget.tile.historyMinutes,
            )),
            future: _history,
            onApplied: () => historyApplied.value++,
            builder: (data) {
              if (widget.tile.kind == WidgetKind.timeline) {
                return StateTimeline(
                  points: data.first,
                  minutes: widget.tile.historyMinutes,
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: HistoryChart(
                      series: data,
                      minutes: widget.tile.historyMinutes,
                      minimum: widget.tile.minimum,
                      maximum: widget.tile.maximum,
                    ),
                  ),
                  if (widget.tile.kind == WidgetKind.comparison)
                    Wrap(
                      spacing: 12,
                      children: [
                        for (var i = 0; i < widget.tile.fields.length; i++)
                          Text(
                            widget.tile.labels[widget.tile.fields[i]] ??
                                widget.controller
                                    .metric(widget.tile.fields[i])
                                    .name,
                            style: TextStyle(
                              fontSize: 14,
                              color: [
                                Palette.of(context).ink,
                                Palette.of(context).green,
                                Palette.of(context).blue,
                                Palette.of(context).acid,
                              ][i % 4],
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<Sample>(
                valueListenable: widget.controller.reading(
                  widget.tile.fields.first,
                ),
                builder: (context, sample, _) => Text(
                  Strings.text('text_ba1415d782', {
                    'value0': widget.tile.historyMinutes,
                    'value1':
                        widget.tile.rows == 1 &&
                            widget.tile.time != TimeDisplay.none
                        ? ' · ${relativeAge(widget.tile.time == TimeDisplay.updated ? sample.updatedAt : sample.changedAt, displayNow)}'
                        : '',
                  }),
                  style: TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IndustrialIconButton(
              tooltip: Strings.text('text_a99001a7bf'),
              onPressed: () => setState(() => _query(refresh: true)),
              icon: Icons.refresh,
            ),
          ],
        ),
      ],
    );
  }

  Widget body() {
    final t = widget.tile;
    if (t.fields.isEmpty) {
      return Center(child: Text(Strings.text('text_69b330657d')));
    }
    if (t.kind.controls) {
      return EntityContent(
        controller: widget.controller,
        tile: t,
        disabled: widget.editing || widget.preview,
        now: displayNow,
      );
    }
    return switch (t.kind) {
      WidgetKind.list || WidgetKind.availability => ListView(
        children: t.fields.map(listEntry).toList(),
      ),
      WidgetKind.pair =>
        t.columns == 1
            ? Column(
                children: [
                  for (final id in t.fields)
                    Expanded(child: reading(id, mini: true, named: true)),
                ],
              )
            : Row(
                children: [
                  for (final id in t.fields)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: reading(id, mini: t.rows == 1, named: true),
                      ),
                    ),
                ],
              ),
      WidgetKind.glance => GridView(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: t.glanceColumns,
          mainAxisExtent: t.time != TimeDisplay.none ? 164 : 140,
        ),
        children: [
          for (final id in t.fields)
            Container(
              padding: EdgeInsets.all(8),
              margin: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Palette.of(context).surface,
                border: Border.all(color: Palette.of(context).grid),
              ),
              child: reading(id, mini: true, named: true),
            ),
        ],
      ),
      WidgetKind.trend ||
      WidgetKind.comparison ||
      WidgetKind.timeline => history(),
      WidgetKind.gauge => Column(
        children: [
          if (t.minimum != null && t.maximum != null)
            SizedBox(
              height: 100,
              child: ValueListenableBuilder<Sample>(
                valueListenable: widget.controller.reading(t.fields.first),
                builder: (context, s, _) => ValueGauge(
                  fraction:
                      s.value is num && t.minimum != null && t.maximum != null
                      ? ((s.value as num).toDouble() - t.minimum!) /
                            (t.maximum! - t.minimum!)
                      : null,
                ),
              ),
            ),
          Expanded(child: reading(t.fields.first, mini: true)),
          if (t.minimum != null && t.maximum != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${t.minimum}', style: TextStyle(fontSize: 14)),
                Text('${t.maximum}', style: TextStyle(fontSize: 14)),
              ],
            ),
        ],
      ),
      WidgetKind.range => Column(
        children: [
          Expanded(child: reading(t.fields.first, mini: t.rows == 1)),
          if (t.minimum != null && t.maximum != null)
            ValueListenableBuilder<Sample>(
              valueListenable: widget.controller.reading(t.fields.first),
              builder: (context, s, _) => Column(
                children: [
                  LinearProgressIndicator(
                    minHeight: t.kind == WidgetKind.gauge ? 18 : 8,
                    value: s.value is num
                        ? (((s.value as num).toDouble() - t.minimum!) /
                                  (t.maximum! - t.minimum!))
                              .clamp(0, 1)
                        : 0,
                    color: Palette.of(context).acid,
                    backgroundColor: Palette.of(context).grid,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${t.minimum}', style: TextStyle(fontSize: 14)),
                      Text('${t.maximum}', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ],
              ),
            )
          else
            Text(
              Strings.text('text_3b1c665461'),
              style: TextStyle(fontSize: 16),
            ),
        ],
      ),
      _ => reading(t.fields.first, mini: t.columns == 1 || t.rows == 1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tile;
    final panel = Panel(
      title: t.title,
      dashboard: true,
      showTitle: t.showTitle,
      titleIndicator: DataActivityDot(
        readings: [for (final id in t.fields) widget.controller.reading(id)],
        historyApplied: historyApplied,
      ),
      leading: t.showIcon && t.icon != null
          ? MetricIcon(t.icon, size: t.columns == 1 || t.rows == 1 ? 20 : 28)
          : t.showDataIcons &&
                !t.kind.multiple &&
                t.fields.isNotEmpty &&
                t.icons[t.fields.first] != null
          ? MetricIcon(
              t.icons[t.fields.first],
              size: t.columns == 1 || t.rows == 1 ? 20 : 28,
            )
          : null,
      compact: t.columns == 1 || t.rows == 1,
      action: widget.preview
          ? null
          : widget.editing
          ? widget.externalEditAction
                ? SizedBox(width: TouchTargets.minimum(context))
                : IndustrialIconButton(
                    onPressed: widget.onEdit,
                    icon: Icons.edit_outlined,
                    tooltip: Strings.text('text_17fe884603'),
                  )
          : null,
      child: Padding(
        padding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: widget.editing || widget.preview ? null : widget.onHistory,
          child: body(),
        ),
      ),
    );
    return widget.preview ? panel : BoundaryCorners(child: panel);
  }
}

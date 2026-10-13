part of 'field_picker.dart';

class _FieldRow extends StatefulWidget {
  final AppController controller;
  final Metric metric;
  final bool selected, readOnly;
  final VoidCallback onSelect, onDetails;
  const _FieldRow({
    super.key,
    required this.controller,
    required this.metric,
    required this.selected,
    this.readOnly = false,
    required this.onSelect,
    required this.onDetails,
  });
  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  late final lease = widget.controller.acquirePreview([widget.metric.id]);
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
    final p = Palette.of(context), m = widget.metric;
    return Container(
      height: MediaQuery.textScalerOf(context).scale(20) <= 20
          ? 80
          : MediaQuery.textScalerOf(context).scale(20) * 2.6 + 24,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.grid)),
      ),
      child: Row(
        children: [
          if (!widget.readOnly)
            XCheck(value: widget.selected, onChanged: (_) => widget.onSelect()),
          if (widget.readOnly) const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: widget.onSelect,
              child: SizedBox.expand(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 760 ? 96 : 260,
            child: ValueListenableBuilder<Sample>(
              valueListenable: widget.controller.reading(m.id),
              builder: (context, s, _) => Text(
                ['available', 'unverified'].contains(s.quality)
                    ? '${s.formatted(1)} ${m.displayUnitFor(s)}'
                    : s.qualityLabel,
                style: TextStyle(color: p.muted, fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IndustrialIconButton(
            icon: Icons.chevron_right,
            tooltip: Strings.text('details'),
            onPressed: widget.onDetails,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

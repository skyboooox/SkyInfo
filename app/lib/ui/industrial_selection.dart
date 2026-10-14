part of 'industrial.dart';

class SelectionRow extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final double height;
  const SelectionRow(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.height = 56,
  });
  @override
  State<SelectionRow> createState() => _SelectionRowState();
}

class _SelectionRowState extends State<SelectionRow> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      selected: widget.selected,
      child: Material(
        color: widget.selected ? p.field : Colors.transparent,
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => focused = value),
          focusColor: Colors.transparent,
          hoverColor: p.ink.withValues(alpha: .04),
          child: CustomPaint(
            foregroundPainter: _SelectionMarker(
              widget.selected ? p.acid : null,
              focused ? p.blue : null,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.height),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    ?widget.trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionMarker extends CustomPainter {
  final Color? selected, focused;
  _SelectionMarker(this.selected, this.focused);
  @override
  void paint(Canvas canvas, Size size) {
    if (selected != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, (size.height - 32) / 2, 2, 32),
        Paint()..color = selected!,
      );
    }
    if (focused != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = focused!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionMarker old) =>
      old.selected != selected || old.focused != focused;
}

class XCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const XCheck({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      checked: value,
      enabled: onChanged != null,
      child: _ControlTarget(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: TouchTargets.minimum(context),
          height: TouchTargets.minimum(context),
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? p.acid : Colors.transparent,
                border: Border.all(color: p.edge),
              ),
              child: value
                  ? const Center(
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xff161616),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class IndustrialSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const IndustrialSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: _ControlTarget(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 76,
          height: TouchTargets.minimum(context),
          child: Center(
            child: Container(
              width: 64,
              height: 36,
              decoration: BoxDecoration(
                color: value ? p.acid : p.field,
                border: Border.all(color: p.edge),
              ),
              child: AnimatedAlign(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Container(
                    width: 24,
                    height: 24,
                    color: value ? const Color(0xff161616) : p.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlTarget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _ControlTarget({required this.child, required this.onTap});
  @override
  State<_ControlTarget> createState() => _ControlTargetState();
}

class _ControlTargetState extends State<_ControlTarget> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Opacity(
      opacity: widget.onTap == null ? .45 : 1,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => focused = value),
          focusColor: Colors.transparent,
          hoverColor: p.ink.withValues(alpha: .04),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: focused ? Border.all(color: p.blue, width: 2) : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

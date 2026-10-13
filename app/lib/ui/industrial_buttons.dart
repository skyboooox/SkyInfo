part of 'industrial.dart';

enum ButtonKind { secondary, primary, quiet, selected, danger }

class IndustrialButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary, reduceMotion, autofocus;
  final ButtonKind kind;
  final double height;
  final double? width;
  final IconData? trailing;
  final Widget? content;
  const IndustrialButton(
    this.label, {
    super.key,
    this.onPressed,
    this.primary = false,
    this.reduceMotion = false,
    this.autofocus = false,
    this.width,
    this.height = 48,
    this.kind = ButtonKind.secondary,
    this.trailing,
    this.content,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context), role = primary ? ButtonKind.primary : kind;
    final foreground = role == ButtonKind.primary
        ? const Color(0xff161616)
        : role == ButtonKind.danger
        ? p.red
        : p.ink;
    final background = role == ButtonKind.primary
        ? p.acid
        : role == ButtonKind.quiet
        ? Colors.transparent
        : p.field;
    return Semantics(
      label: content == null ? null : label,
      selected: role == ButtonKind.selected,
      child: Opacity(
        opacity: onPressed == null ? .45 : 1,
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: role == ButtonKind.selected
                    ? Border(bottom: BorderSide(color: p.acid, width: 2))
                    : null,
              ),
              child: TextButton(
                autofocus: autofocus,
                onPressed: onPressed,
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(foreground),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return Color.alphaBlend(
                        p.paper.withValues(alpha: .2),
                        background,
                      );
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return Color.alphaBlend(
                        p.ink.withValues(alpha: .04),
                        background == Colors.transparent ? p.paper : background,
                      );
                    }
                    return background;
                  }),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  minimumSize: WidgetStatePropertyAll(Size(0, height)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                  side: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.focused)
                        ? BorderSide(color: p.blue, width: 2)
                        : role == ButtonKind.quiet ||
                              role == ButtonKind.primary ||
                              role == ButtonKind.selected
                        ? BorderSide.none
                        : BorderSide(
                            color: role == ButtonKind.danger ? p.red : p.edge,
                          ),
                  ),
                  animationDuration:
                      reduceMotion || MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                ),
                child:
                    content ??
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 12),
                          Icon(trailing, size: 24),
                        ],
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

class IndustrialIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected, outlined;
  final double size;
  const IndustrialIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.outlined = false,
    this.size = 48,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selected
              ? Border(bottom: BorderSide(color: p.acid, width: 2))
              : null,
        ),
        child: IconButton(
          tooltip: tooltip,
          isSelected: selected,
          onPressed: onPressed,
          icon: Icon(icon, size: 24),
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ? p.muted : p.ink,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? p.field
                  : outlined
                  ? p.field
                  : Colors.transparent,
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            fixedSize: WidgetStatePropertyAll(Size(size, size)),
            shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(color: p.blue, width: 2)
                  : outlined
                  ? BorderSide(color: p.edge)
                  : BorderSide.none,
            ),
            animationDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 120),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'industrial.dart';

class CategoryPane<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final int Function(T)? count;
  final ValueChanged<T> onChanged;
  final Widget child;
  const CategoryPane({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    required this.child,
    this.count,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final current = values.contains(selected) ? selected : values.first;
      if (box.maxWidth < 760 ||
          MediaQuery.textScalerOf(context).scale(20) > 30) {
        return Column(
          children: [
            DropdownButtonFormField<T>(
              borderRadius: BorderRadius.zero,
              itemHeight: null,
              key: ValueKey((current, values.join('|'))),
              initialValue: current,
              isExpanded: true,
              decoration: InputDecoration(labelText: Strings.text('category')),
              items: [
                for (final value in values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      label(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
            const SizedBox(height: 16),
            Expanded(child: ClipRect(child: child)),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 224,
            child: ClipRect(
              child: ListView(
                children: [
                  for (final value in values)
                    SelectionRow(
                      label(value),
                      selected: selected == value,
                      onTap: () => onChanged(value),
                      trailing: count == null
                          ? null
                          : Text(
                              '${count!(value)}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Palette.of(context).muted,
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(child: ClipRect(child: child)),
        ],
      );
    },
  );
}

class PreviewLayout extends StatelessWidget {
  final Widget preview, parameters;
  final double previewWidth;
  final bool previewFirst;
  const PreviewLayout({
    super.key,
    required this.preview,
    required this.parameters,
    this.previewWidth = 480,
    this.previewFirst = true,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxHeight < 280) {
        return parameters;
      }
      if (box.maxWidth >= 1200 &&
          MediaQuery.textScalerOf(context).scale(20) <= 30) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: previewFirst
              ? [
                  SizedBox(width: previewWidth, child: preview),
                  const SizedBox(width: 24),
                  Expanded(child: parameters),
                ]
              : [
                  Expanded(child: parameters),
                  const SizedBox(width: 24),
                  SizedBox(width: previewWidth, child: preview),
                ],
        );
      }
      return Column(
        children: [
          SizedBox(
            height: (box.maxHeight * .36).clamp(100.0, 240.0).toDouble(),
            child: preview,
          ),
          const SizedBox(height: 16),
          Expanded(child: parameters),
        ],
      );
    },
  );
}

double preferredToolbarWidth(BuildContext context, Widget child) {
  if (child is IndustrialButton) return child.width ?? 160;
  if (child is IndustrialIconButton) return child.size;
  if (child is Expanded) return preferredToolbarWidth(context, child.child);
  if (child is Spacer) return 0;
  if (child is SizedBox) {
    return child.width ??
        (child.child == null
            ? 0
            : preferredToolbarWidth(context, child.child!));
  }
  if (child is Padding) {
    return child.padding.resolve(Directionality.of(context)).horizontal +
        preferredToolbarWidth(context, child.child ?? const SizedBox.shrink());
  }
  if (child is Row) {
    return child.children.fold<double>(
      0,
      (sum, item) => sum + preferredToolbarWidth(context, item),
    );
  }
  if (child is Text) {
    final painter = TextPainter(
      text: TextSpan(
        text: child.data,
        style: DefaultTextStyle.of(context).style.merge(child.style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
  return 56;
}

class ResponsiveToolbar extends StatelessWidget {
  final List<Widget> children;
  const ResponsiveToolbar({super.key, required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        box.maxWidth >=
                children.fold<double>(
                      0,
                      (sum, item) => sum + preferredToolbarWidth(context, item),
                    ) +
                    (children.length - 1) * 12 &&
            MediaQuery.textScalerOf(context).scale(20) <= 30
        ? Row(children: children)
        : Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: children
                .where(
                  (child) =>
                      child is! Spacer &&
                      !(child is SizedBox &&
                          child.child == null &&
                          child.height == null),
                )
                .map(
                  (child) =>
                      child is IndustrialButton &&
                          (child.primary || child.kind == ButtonKind.primary)
                      ? SizedBox(width: box.maxWidth, child: child)
                      : child is Expanded &&
                            child.child is SizedBox &&
                            (child.child as SizedBox).child == null
                      ? const SizedBox.shrink()
                      : child is Expanded
                      ? SizedBox(width: box.maxWidth, child: child.child)
                      : child is Spacer
                      ? const SizedBox.shrink()
                      : child,
                )
                .toList(),
          ),
  );
}

class AdaptivePanels extends StatelessWidget {
  final Widget first, second;
  final int firstFlex, secondFlex;
  const AdaptivePanels({
    super.key,
    required this.first,
    required this.second,
    this.firstFlex = 1,
    this.secondFlex = 1,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth >= 1000 &&
          MediaQuery.textScalerOf(context).scale(20) <= 30) {
        return Row(
          children: [
            Expanded(flex: firstFlex, child: first),
            const SizedBox(width: 24),
            Expanded(flex: secondFlex, child: second),
          ],
        );
      }
      return ListView(
        children: [
          SizedBox(height: 420, child: first),
          const SizedBox(height: 16),
          SizedBox(height: 420, child: second),
        ],
      );
    },
  );
}

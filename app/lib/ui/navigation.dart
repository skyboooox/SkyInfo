import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'industrial.dart';
import 'layout.dart';
import 'design_dialog.dart';

List<String> get pageTitles => [
  Strings.text('page_information'),
  Strings.text('page_overlay'),
  Strings.text('page_connection'),
  Strings.text('settings'),
];
List<String> get settingsTitles => [
  Strings.text('text_f1484fa78b'),
  Strings.text('text_c3f8933d77'),
  Strings.text('page_overlay'),
  Strings.text('page_connection'),
  Strings.text('advanced'),
];

class NavigationHeading extends StatelessWidget {
  final String title;
  final bool menuOpen;
  final VoidCallback onMenu;
  final List<Widget> actions;
  final GlobalKey? menuKey;
  const NavigationHeading({
    super.key,
    required this.title,
    required this.onMenu,
    this.menuOpen = false,
    this.actions = const [],
    this.menuKey,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final required =
          90 +
          MediaQuery.textScalerOf(context).scale(28) * title.length +
          actions.fold<double>(
            0,
            (sum, item) => sum + preferredToolbarWidth(context, item),
          ) +
          16 * actions.length;
      final stacked = box.maxWidth < required;

      final heading = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            IndustrialIconButton(
              key: menuKey,
              icon: menuOpen ? Icons.close : Icons.menu,
              tooltip: Strings.text(menuOpen ? 'close' : 'text_c7ed249504'),
              onPressed: onMenu,
              outlined: true,
              size: 56,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 2,
              height: 28,
              child: ColoredBox(color: Palette.of(context).acid),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            if (!stacked)
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                actions[i],
              ],
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          heading,
          if (stacked && actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            ResponsiveToolbar(children: actions),
          ],
        ],
      );
    },
  );
}

Future<int?> showNavigationMenu(
  BuildContext context,
  int selected,
  GlobalKey anchor,
) {
  final render = anchor.currentContext?.findRenderObject() as RenderBox?;
  final offset = render?.localToGlobal(Offset.zero) ?? const Offset(16, 16);
  return showDesignDialog<int>(
    context: context,
    useSafeArea: false,
    barrierColor: Colors.black.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? .36 : .16,
    ),
    builder: (context) => LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Positioned(
            left: offset.dx,
            top: offset.dy,
            width: 56,
            height: 56,
            child: IndustrialIconButton(
              icon: Icons.close,
              tooltip: Strings.text('close'),
              outlined: true,
              size: 56,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: offset.dx,
            top: offset.dy + 72,
            width: math.min(288, box.maxWidth - offset.dx - 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(
                  56,
                  box.maxHeight -
                      offset.dy -
                      88 -
                      MediaQuery.viewPaddingOf(context).bottom,
                ),
              ),
              child: NavigationMenu(
                selected: selected,
                onSelected: (value) => Navigator.pop(context, value),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class NavigationMenu extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const NavigationMenu({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Palette.of(context).surface,
    shape: Border.all(color: Palette.of(context).edge),
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 4; i++)
          SelectionRow(
            pageTitles[i],
            selected: i == selected,
            onTap: () => onSelected(i),
          ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/strings.dart';
import 'layout.dart';
import 'attention_surface.dart';
export 'industrial_paper.dart';
import 'touch_targets.dart';

part 'industrial_controls.dart';
part 'industrial_buttons.dart';
part 'industrial_selection.dart';

class DesignViewport extends StatelessWidget {
  final Widget child;
  const DesignViewport({super.key, required this.child});
  @override
  Widget build(BuildContext context) => FocusTraversalGroup(child: child);
}

class Palette {
  final Color paper,
      ink,
      surface,
      field,
      muted,
      acid,
      red,
      grid,
      edge,
      blue,
      green,
      rose,
      warning;
  const Palette({
    required this.paper,
    required this.ink,
    required this.surface,
    required this.field,
    required this.muted,
    required this.grid,
    required this.edge,
    required this.blue,
    required this.green,
    required this.rose,
    required this.warning,
    required this.red,
    this.acid = const Color(0xffFFD429),
  });
  static const light = Palette(
    paper: Color(0xffEFEFEF),
    ink: Color(0xff202020),
    surface: Color(0xffFAFAFA),
    field: Color(0xffFFFFFF),
    muted: Color(0xff626262),
    grid: Color(0xffD4D4D4),
    edge: Color(0xff888888),
    blue: Color(0xff2E6485),
    green: Color(0xff237A53),
    rose: Color(0xffAD2E68),
    warning: Color(0xff865312),
    red: Color(0xffB7403B),
  );
  static const dark = Palette(
    paper: Color(0xff111111),
    ink: Color(0xffEFEFEF),
    surface: Color(0xff1C1C1C),
    field: Color(0xff252525),
    muted: Color(0xffB0B0B0),
    grid: Color(0xff393939),
    edge: Color(0xff747474),
    blue: Color(0xff89B8D8),
    green: Color(0xff72C59A),
    rose: Color(0xffE47FAA),
    warning: Color(0xffD6A968),
    red: Color(0xffF18D83),
  );
  Color get activity =>
      this == dark ? const Color(0xff88A392) : const Color(0xff6B8776);
  static Palette of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

ThemeData industrialTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  return ThemeData(
    brightness: b,
    fontFamily: 'ChillDIN',
    scaffoldBackgroundColor: p.paper,
    canvasColor: p.field,
    sliderTheme: SliderThemeData(
      activeTrackColor: p.acid,
      inactiveTrackColor: p.grid,
      thumbColor: p.ink,
      overlayColor: p.acid.withValues(alpha: .08),
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.acid,
      brightness: b,
      surface: p.field,
      primary: p.acid,
      onPrimary: const Color(0xff161616),
      onSurface: p.ink,
      outline: p.edge,
      error: p.red,
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 18, color: p.ink),
      bodyMedium: TextStyle(
        fontSize: 18,
        color: p.ink,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        fontSize: 16,
        color: p.muted,
        fontWeight: FontWeight.w400,
      ),
    ),
    dividerColor: p.grid,
    splashFactory: NoSplash.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.field,
      contentPadding: EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: p.edge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: p.blue, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: p.edge),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.paper,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.edge)),
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'ChillDIN',
        fontSize: 32,
        color: p.ink,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'ChillDIN',
        fontSize: 18,
        color: p.ink,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.field,
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.edge)),
      textStyle: TextStyle(fontFamily: 'ChillDIN', fontSize: 18, color: p.ink),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: Size(48, 48),
        textStyle: TextStyle(fontFamily: 'ChillDIN', fontSize: 20),
        shape: RoundedRectangleBorder(),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(fontSize: 18, color: p.ink),
    ),
  );
}

class MetricIcon extends StatelessWidget {
  final String? id;
  final double size;
  const MetricIcon(this.id, {super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => id == null || id!.isEmpty
      ? SizedBox.shrink()
      : SvgPicture.asset(
          'assets/icons/$id.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(
            Palette.of(context).ink,
            BlendMode.srcIn,
          ),
        );
}

class Panel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action, leading, titleIndicator;
  final bool compact, showTitle, dashboard;
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.leading,
    this.titleIndicator,
    this.compact = false,
    this.showTitle = true,
    this.dashboard = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.grid),
      ),
      padding: dashboard ? EdgeInsets.all(compact ? 16 : 24) : EdgeInsets.zero,
      child: Column(
        children: [
          if (showTitle || action != null || leading != null)
            Container(
              constraints: BoxConstraints(
                minHeight: dashboard
                    ? 44
                    : compact
                    ? 40
                    : 52,
              ),
              padding: dashboard
                  ? EdgeInsets.zero
                  : EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(bottom: BorderSide(color: p.grid)),
              ),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, SizedBox(width: 10)],
                  if (showTitle && titleIndicator != null) ...[
                    titleIndicator!,
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      showTitle ? title : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: compact ? 20 : 24),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
          if (dashboard) const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class ParameterRow extends StatelessWidget {
  final String label;
  final Widget trailing;
  final Widget? leading;
  final Widget? labelAction;
  final VoidCallback? onTap;
  const ParameterRow(
    this.label, {
    super.key,
    required this.trailing,
    this.leading,
    this.labelAction,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        focusColor: p.blue.withValues(alpha: .10),
        hoverColor: p.ink.withValues(alpha: .04),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.grid)),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final name = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Flexible(child: Text(label)),
                  if (labelAction != null) ...[
                    const SizedBox(width: 8),
                    labelAction!,
                  ],
                ],
              );
              if (box.maxWidth <
                      preferredToolbarWidth(context, Text(label)) +
                          preferredToolbarWidth(context, trailing) +
                          (labelAction == null ? 0 : 56) +
                          32 ||
                  MediaQuery.textScalerOf(context).scale(20) > 30) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    name,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: trailing),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 16),
                  trailing,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

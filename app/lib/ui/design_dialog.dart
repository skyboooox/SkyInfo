import '../l10n/strings.dart';
import 'package:flutter/material.dart';
import 'industrial.dart';
import 'navigation.dart';
import 'layout.dart';
import '../data/app_controller.dart';
import '../domain/build_channel.dart';
import 'release_notice.dart';
import 'project_link.dart';

Future<T?> showDesignDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useSafeArea = true,
  bool barrierDismissible = true,
  Color? barrierColor,
}) => Navigator.of(context, rootNavigator: true).push<T>(
  _DesignDialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(
      from: context,
      to: Navigator.of(context, rootNavigator: true).context,
    ),
    useSafeArea: useSafeArea,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    animationStyle: AnimationStyle(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      reverseDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
    ),
  ),
);

class _DesignDialogRoute<T> extends DialogRoute<T> {
  _DesignDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.useSafeArea,
    super.barrierDismissible,
    super.barrierColor,
    super.animationStyle,
  });
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return IgnorePointer(
      ignoring: animation.status == AnimationStatus.reverse,
      child: FadeTransition(
        opacity: eased,
        child: ScaleTransition(
          scale: Tween(begin: .985, end: 1.0).animate(eased),
          child: child,
        ),
      ),
    );
  }
}

class DesignDialog extends StatelessWidget {
  final String title;
  final double width, height;
  final Widget child;
  final Widget? footer, leading;
  final VoidCallback? onClose;
  const DesignDialog({
    super.key,
    required this.title,
    required this.child,
    this.width = 1232,
    this.height = 568,
    this.footer,
    this.leading,
    this.onClose,
  });
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Palette.of(context).surface,
    insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Palette.of(context).grid),
                ),
              ),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 24),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IndustrialIconButton(
                    tooltip: Strings.text('close'),
                    onPressed: onClose ?? () => Navigator.pop(context),
                    icon: Icons.close,
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Expanded(child: child),
            if (footer != null) ...[
              const SizedBox(height: 16),
              if (footer is Row)
                ResponsiveToolbar(children: (footer as Row).children)
              else
                footer!,
            ],
          ],
        ),
      ),
    ),
  );
}

class ChoiceButtons<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool Function(T)? enabled;
  const ChoiceButtons({
    super.key,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.enabled,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width =
          (values
                          .map((v) => label(v).length)
                          .fold<int>(0, (a, b) => a > b ? a : b) *
                      MediaQuery.textScalerOf(context).scale(20) +
                  32)
              .clamp(112.0, box.maxWidth)
              .toDouble();
      Widget button(T value) => IndustrialButton(
        label(value),
        kind: this.value == value ? ButtonKind.selected : ButtonKind.secondary,
        onPressed: enabled?.call(value) == false
            ? null
            : () => onChanged(value),
      );
      if (box.maxWidth >= values.length * width + (values.length - 1) * 12) {
        return Row(
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: button(values[i])),
            ],
          ],
        );
      }
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final value in values)
            SizedBox(width: width, child: button(value)),
        ],
      );
    },
  );
}

class ParameterInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int? maxLength;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  const ParameterInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLength,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 64),
    child: TextField(
      controller: controller,
      maxLength: maxLength,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      style: TextStyle(fontSize: 18, color: Palette.of(context).ink),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        contentPadding: const EdgeInsets.all(16),
      ),
    ),
  );
}

class SettingsEditor extends StatefulWidget {
  final String title;
  final AppController controller;
  final Widget child, footer;
  final ValueChanged<int> onNavigate, onTab;
  final int selectedTab;
  const SettingsEditor({
    super.key,
    required this.title,
    required this.child,
    required this.footer,
    required this.controller,
    required this.onNavigate,
    required this.onTab,
    this.selectedTab = 3,
  });
  @override
  State<SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends State<SettingsEditor> {
  bool menuOpen = false;
  final menuKey = GlobalKey();
  Future<void> openNavigation() async {
    if (menuOpen) return;
    setState(() => menuOpen = true);
    final target = await showNavigationMenu(context, 3, menuKey);
    if (!mounted) return;
    setState(() => menuOpen = false);
    if (target != null) widget.onNavigate(target);
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.of(context).paper,
    child: IndustrialPaper(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              NavigationHeading(
                title: widget.title,
                menuOpen: menuOpen,
                menuKey: menuKey,
                onMenu: openNavigation,
              ),
              const SizedBox(height: 16),
              if (BuildChannel.isTesting) ...[
                ReleaseNotice(
                  version: widget.controller.appVersion,
                  onOpen: () => openProjectLink(context),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: CategoryPane<int>(
                  values: settingsTabs,
                  selected: widget.selectedTab,
                  label: (i) => settingsTitles[i],
                  onChanged: widget.onTab,
                  child: Column(
                    children: [
                      Expanded(child: widget.child),
                      const SizedBox(height: 16),
                      if (widget.footer is Row)
                        ResponsiveToolbar(
                          children: (widget.footer as Row).children,
                        )
                      else
                        widget.footer,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

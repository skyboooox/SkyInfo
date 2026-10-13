import '../l10n/strings.dart';
import 'package:flutter/material.dart';
import 'industrial.dart';
import 'navigation.dart';
import 'layout.dart';

Future<T?> showDesignDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useSafeArea = true,
  bool barrierDismissible = true,
  Color? barrierColor,
}) => showDialog<T>(
  context: context,
  builder: builder,
  useSafeArea: useSafeArea,
  barrierDismissible: barrierDismissible,
  barrierColor: barrierColor,
  animationStyle: AnimationStyle(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    reverseDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  ),
);

class DesignDialog extends StatelessWidget {
  final String title;
  final double width, height;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onClose;
  const DesignDialog({
    super.key,
    required this.title,
    required this.child,
    this.width = 1440,
    this.height = 820,
    this.footer,
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
        padding: EdgeInsets.all(24),
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
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 32),
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
    constraints: const BoxConstraints(minHeight: 80),
    child: TextField(
      controller: controller,
      maxLength: maxLength,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      style: TextStyle(fontSize: 20, color: Palette.of(context).ink),
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
  final Widget child, footer;
  final ValueChanged<int> onNavigate, onTab;
  final int selectedTab;
  const SettingsEditor({
    super.key,
    required this.title,
    required this.child,
    required this.footer,
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
            Expanded(
              child: CategoryPane<int>(
                values: const [0, 1, 2, 3, 4],
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
  );
}

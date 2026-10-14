import 'package:flutter/material.dart';

class TouchTargets extends InheritedWidget {
  final double visualScale;
  const TouchTargets({
    super.key,
    required this.visualScale,
    required super.child,
  });

  static double minimum(BuildContext context) {
    final scale =
        context
            .dependOnInheritedWidgetOfExactType<TouchTargets>()
            ?.visualScale ??
        1;
    return 48 / scale.clamp(.01, 1);
  }

  @override
  bool updateShouldNotify(TouchTargets oldWidget) =>
      oldWidget.visualScale != visualScale;
}

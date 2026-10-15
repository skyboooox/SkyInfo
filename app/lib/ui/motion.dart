import 'package:flutter/material.dart';

class Motion extends StatelessWidget {
  final Widget child;
  final Object identity;
  final bool slide;
  const Motion({
    super.key,
    required this.child,
    required this.identity,
    this.slide = true,
  });
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: 240),
    reverseDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: 120),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeOutCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.center,
      children: [
        for (final old in previous)
          ExcludeSemantics(child: IgnorePointer(child: old)),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => LayoutBuilder(
      builder: (context, box) => FadeTransition(
        opacity: animation,
        child: slide
            ? SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(0, box.maxHeight > 0 ? 6 / box.maxHeight : 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              )
            : child,
      ),
    ),
    child: RepaintBoundary(key: ValueKey(identity), child: child),
  );
}

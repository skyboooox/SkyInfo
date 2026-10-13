import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import 'industrial.dart';

class OverlayStripPreview extends StatelessWidget {
  final AppController controller;
  final List<OverlaySpec> modules;
  const OverlayStripPreview({
    super.key,
    required this.controller,
    required this.modules,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context), c = controller;
    if (modules.isEmpty) return const SizedBox.shrink();
    final groups = [
      'left',
      'center',
      'right',
    ].where((a) => modules.any((m) => m.alignment == a)).toList();
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          color: p.field.withValues(alpha: c.overlayOpacity),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: 24),
                for (final module in modules.where(
                  (m) => m.alignment == groups[i],
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ValueListenableBuilder<Sample>(
                      valueListenable: c.reading(module.field),
                      builder: (context, s, _) {
                        final unit = c
                            .metric(module.field)
                            .displayUnitFor(
                              s,
                              module.unitAuto ? null : module.unit,
                            );
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            if (module.icon.isNotEmpty) ...[
                              MetricIcon(module.icon, size: c.overlayFont + 2),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              ['available', 'unverified'].contains(s.quality)
                                  ? s.formatted(module.digits)
                                  : '—',
                              style: TextStyle(
                                fontFamily: s.value is num
                                    ? 'IBMPlexMono'
                                    : null,
                                fontSize: c.overlayFont,
                                color: p.ink,
                              ),
                            ),
                            if (unit.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                unit,
                                style: TextStyle(
                                  fontSize: c.overlayFont * .75,
                                  color: p.ink,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

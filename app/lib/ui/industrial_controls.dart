part of 'industrial.dart';

class GridShape extends StatelessWidget {
  final int columns, rows;
  const GridShape(this.columns, this.rows, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 32,
    child: Center(
      child: SizedBox(
        width: columns * 8 - 2,
        height: rows * 8 - 2,
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (var i = 0; i < columns * rows; i++)
              SizedBox(
                width: 6,
                height: 6,
                child: ColoredBox(color: Palette.of(context).ink),
              ),
          ],
        ),
      ),
    ),
  );
}

class BoundaryCorners extends StatelessWidget {
  final Widget child;
  const BoundaryCorners({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: child),
      for (final alignment in [
        Alignment.topLeft,
        Alignment.topRight,
        Alignment.bottomLeft,
        Alignment.bottomRight,
      ])
        Positioned(
          left: alignment.x < 0 ? 0 : null,
          right: alignment.x > 0 ? 0 : null,
          top: alignment.y < 0 ? 0 : null,
          bottom: alignment.y > 0 ? 0 : null,
          child: IgnorePointer(
            child: SizedBox(
              width: 20,
              height: 20,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: alignment.x < 0
                        ? BorderSide(color: Palette.of(context).blue, width: 2)
                        : BorderSide.none,
                    right: alignment.x > 0
                        ? BorderSide(color: Palette.of(context).blue, width: 2)
                        : BorderSide.none,
                    top: alignment.y < 0
                        ? BorderSide(color: Palette.of(context).blue, width: 2)
                        : BorderSide.none,
                    bottom: alignment.y > 0
                        ? BorderSide(color: Palette.of(context).blue, width: 2)
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class CreationSteps extends StatelessWidget {
  final int active;
  final List<String> labels;
  const CreationSteps({super.key, required this.active, required this.labels});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 760 ||
            MediaQuery.textScalerOf(context).scale(18) > 27) {
          return Semantics(
            label: Strings.text('creation_step', {
              'current': active + 1,
              'total': labels.length,
            }),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.acid, width: 2)),
              ),
              child: Row(
                children: [
                  Text(
                    '${active + 1} / ${labels.length}',
                    style: const TextStyle(
                      fontFamily: 'IBMPlexMono',
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      labels[active],
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Icon(Icons.chevron_right, size: 16),
                ),
              Container(
                constraints: const BoxConstraints(minHeight: 40, minWidth: 164),
                decoration: BoxDecoration(
                  border: i == active
                      ? Border(bottom: BorderSide(color: p.acid, width: 2))
                      : null,
                ),
                child: Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontFamily: 'IBMPlexMono',
                        fontSize: 18,
                        color: i == active ? p.ink : p.muted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 18,
                        color: i == active ? p.ink : p.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/strings.dart';
import 'industrial.dart';

class ReleaseNotice extends StatelessWidget {
  final String version;
  final VoidCallback onOpen;
  const ReleaseNotice({super.key, required this.version, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final message = Row(
      children: [
        SvgPicture.asset(
          'assets/ui/warning.svg',
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(p.ink, BlendMode.srcIn),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            Strings.text('beta_notice'),
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ],
    );
    final actions = [
      Text(
        version,
        style: TextStyle(
          fontFamily: 'IBMPlexMono',
          fontSize: 20,
          color: p.muted,
        ),
      ),
      IndustrialButton(
        Strings.text('version_updates'),
        content: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/ui/globe.svg',
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(p.ink, BlendMode.srcIn),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  Strings.text('version_updates'),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
        ),
        width: 160,
        onPressed: onOpen,
      ),
    ];
    return Container(
      key: const ValueKey('beta-notice'),
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(left: BorderSide(color: p.acid, width: 4)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 640 ||
              MediaQuery.textScalerOf(context).scale(20) > 30) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                message,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: message),
              const SizedBox(width: 16),
              actions[0],
              const SizedBox(width: 16),
              actions[1],
            ],
          );
        },
      ),
    );
  }
}

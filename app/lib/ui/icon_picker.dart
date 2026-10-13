import '../l10n/strings.dart';
import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import 'design_dialog.dart';
import 'industrial.dart';
import 'layout.dart';

Future<String?> chooseIcon(
  BuildContext context,
  AppController c, {
  bool allowNone = true,
}) => showDesignDialog<String>(
  context: context,
  builder: (_) => _IconPicker(c, allowNone),
);

class _IconPicker extends StatefulWidget {
  final AppController c;
  final bool allowNone;
  const _IconPicker(this.c, this.allowNone);
  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  String category = Strings.text('text_f6f4ab8243'), search = '';
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context), catalog = widget.c.iconCatalog;
    final cats = <String>[
      Strings.text('text_f6f4ab8243'),
      ...catalog.map((i) => i['category']!).toSet(),
    ];
    final icons =
        catalog
            .where(
              (i) =>
                  (category == Strings.text('text_f6f4ab8243') ||
                      i['category'] == category) &&
                  (i['name']!.contains(search) ||
                      i['id']!.toLowerCase().contains(search.toLowerCase()) ||
                      widget.c.metrics.any(
                        (m) => m.icon == i['id'] && m.name.contains(search),
                      )),
            )
            .toList()
          ..sort((a, b) {
            final order = cats
                .indexOf(a['category']!)
                .compareTo(cats.indexOf(b['category']!));
            return order == 0
                ? catalog.indexOf(a).compareTo(catalog.indexOf(b))
                : order;
          });
    return DesignDialog(
      title: Strings.text('text_ef6e0d1008'),
      width: 1440,
      height: 820,
      footer: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 96,
          child: IndustrialButton(
            Strings.text('cancel'),
            kind: ButtonKind.quiet,
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: Strings.text('text_b62f025730'),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: CategoryPane<String>(
              values: cats,
              selected: category,
              label: (value) => value,
              count: (value) => value == Strings.text('text_f6f4ab8243')
                  ? catalog.length
                  : catalog.where((i) => i['category'] == value).length,
              onChanged: (value) => setState(() => category = value),
              child: ListView(
                children: [
                  if (widget.allowNone)
                    ParameterRow(
                      Strings.text('text_6d0bd504b9'),
                      trailing: const Icon(Icons.chevron_right, size: 24),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  for (var i = 0; i < icons.length; i++) ...[
                    if (i == 0 ||
                        icons[i - 1]['category'] != icons[i]['category'])
                      Container(
                        height: 40,
                        color: p.surface,
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          icons[i]['category']!,
                          style: TextStyle(fontSize: 18, color: p.muted),
                        ),
                      ),
                    ParameterRow(
                      icons[i]['name']!,
                      leading: MetricIcon(icons[i]['id'], size: 24),
                      trailing: const Icon(Icons.chevron_right, size: 24),
                      onTap: () => Navigator.pop(context, icons[i]['id']),
                    ),
                  ],
                  if (icons.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(Strings.text('text_b78bec3cd7')),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

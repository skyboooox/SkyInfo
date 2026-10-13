import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import 'design_dialog.dart';
import 'industrial.dart';

class UnitChoice {
  final String? unit;
  const UnitChoice(this.unit);
}

Future<UnitChoice?> chooseDisplayUnit(
  BuildContext context, {
  String? unit,
  bool reduceMotion = false,
}) => showDesignDialog<UnitChoice>(
  context: context,
  builder: (_) => _UnitPicker(unit),
);

class _UnitPicker extends StatefulWidget {
  final String? unit;
  const _UnitPicker(this.unit);
  @override
  State<_UnitPicker> createState() => _UnitPickerState();
}

class _UnitPickerState extends State<_UnitPicker> {
  late String? unit = widget.unit;
  late final input = TextEditingController(text: widget.unit ?? '');
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesignDialog(
    title: Strings.text('text_3edaec3a28'),
    width: 880,
    height: 520,
    footer: Row(
      children: [
        IndustrialButton(
          Strings.text('cancel'),
          kind: ButtonKind.quiet,
          width: 96,
          onPressed: () => Navigator.pop(context),
        ),
        const Spacer(),
        IndustrialButton(
          Strings.text('confirm_selection'),
          primary: true,
          width: 160,
          onPressed: () => Navigator.pop(context, UnitChoice(unit)),
        ),
      ],
    ),
    child: ListView(
      children: [
        ChoiceButtons<String?>(
          value: unit,
          values: const [null, ''],
          label: (value) => Strings.text(
            value == null ? 'text_4afad87755' : 'text_8f40560d5a',
          ),
          onChanged: (value) => setState(() {
            unit = value;
            input.text = value ?? '';
          }),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in [
              'V',
              'A',
              'W',
              'kW',
              '°C',
              'mV',
              '%',
              'rpm',
              'kWh',
            ])
              IndustrialButton(
                value,
                width: 112,
                kind: unit == value
                    ? ButtonKind.selected
                    : ButtonKind.secondary,
                onPressed: () => setState(() {
                  unit = value;
                  input.text = value;
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        ParameterInput(
          controller: input,
          maxLength: 16,
          label: Strings.text('text_b8c9bab3b0'),
          onChanged: (value) => setState(() => unit = value),
        ),
      ],
    ),
  );
}

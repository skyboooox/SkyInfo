part of 'home.dart';

extension _EntityMapping on _HomeState {
  Future<void> entitySettings() async {
    final mappings = {...c.entityMappings};
    final selected = c.metrics
        .where(
          (m) =>
              c.uploaded.contains(m.id) ||
              c.tiles.any((t) => t.fields.contains(m.id)),
        )
        .toList();
    final inputs = {
      for (final m in selected)
        m.id: TextEditingController(text: mappings[m.id] ?? ''),
    };
    String? validation;
    final ok = await showDesignDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(Strings.text('text_f403f4466e')),
          content: SizedBox(
            width: 720,
            height: 460,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      for (final m in selected)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: TextField(
                            controller: inputs[m.id],
                            decoration: InputDecoration(
                              labelText: m.name,
                              hintText:
                                  'sensor.skyinfo_${c.prefix}_${m.entityKey}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (validation != null)
                  Text(
                    validation!,
                    style: TextStyle(color: Palette.of(context).red),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Strings.text('cancel')),
            ),
            TextButton(
              onPressed: () {
                for (final entry in inputs.entries) {
                  final value = entry.value.text.trim();
                  if (value.isNotEmpty &&
                      !RegExp(r'^sensor\.[a-z0-9_]+$').hasMatch(value)) {
                    update(() => validation = Strings.text('text_f19d5ec1de'));
                    return;
                  }
                  if (value.isEmpty) {
                    mappings.remove(entry.key);
                  } else {
                    mappings[entry.key] = value;
                  }
                }
                Navigator.pop(context, true);
              },
              child: Text(Strings.text('save')),
            ),
          ],
        ),
      ),
    );
    for (final input in inputs.values) {
      input.dispose();
    }
    if (ok == true) {
      c.entityMappings = mappings;
      await save();
    }
  }
}

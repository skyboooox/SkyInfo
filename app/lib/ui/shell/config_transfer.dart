part of 'home.dart';

extension _ConfigTransfer on _HomeState {
  Future<void> showDiagnostics() async {
    try {
      final result = await c.bridge.call('diagnostics');
      if (!mounted) return;
      await showDesignDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(Strings.text('text_0b673e8796')),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: SelectableText(
                result.toString(),
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Strings.text('close')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.text('text_e429415481'))),
        );
      }
    }
  }

  Future<void> exportSettings() async {
    final json = c.exportConfig();
    await showDesignDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Strings.text('text_3d05c8ad5e')),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: TextStyle(fontFamily: 'IBMPlexMono', fontSize: 14),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Strings.text('close')),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(context);
            },
            child: Text(Strings.text('text_4edd1d0087')),
          ),
        ],
      ),
    );
  }

  Future<void> importSettings() async {
    final input = TextEditingController();
    final text = await showDesignDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Strings.text('text_280779a502')),
        content: SizedBox(
          width: 720,
          child: TextField(controller: input, minLines: 8, maxLines: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Strings.text('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: Text(Strings.text('text_60e2bcad85')),
          ),
        ],
      ),
    );
    input.dispose();
    if (text != null && mounted) {
      Map<String, dynamic> next;
      try {
        next = Map<String, dynamic>.from(jsonDecode(text));
      } catch (_) {
        await c.importConfig(text);
        return;
      }
      try {
        if (!mounted) return;
        final acknowledgements = await confirmConnectionConfiguration(
          context,
          c,
          next,
        );
        if (acknowledgements == null || !mounted) return;
        next['insecureAcknowledgements'] = acknowledgements.toList();
        await c.importConfig(jsonEncode(next));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Strings.text('text_24dffa6f22'))),
          );
        }
      }
    }
  }
}

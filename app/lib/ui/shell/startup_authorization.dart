part of 'home.dart';

extension _StartupAuthorization on _HomeState {
  void checkStartupAuthorization() {
    if (!mounted || startupAuthorizationChecked || !visible) return;
    final state = c.status['adb'];
    if (state == 'connected') {
      startupAuthorizationChecked = true;
      return;
    }
    if (![
      'authorization',
      'pair_required',
      'disabled',
      'timeout',
      'unreachable',
      'error',
      'other_device',
      'disconnected',
    ].contains(state)) {
      return;
    }
    startupAuthorizationChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (c.status['adb'] == 'connected') return;
      final authorization = [
        'authorization',
        'pair_required',
        'disabled',
      ].contains(c.status['adb']);
      final open = await confirmAction(
        context,
        title: Strings.text(
          authorization ? 'adb_authorization_title' : 'adb_connection_title',
        ),
        message: Strings.text(
          authorization
              ? 'adb_authorization_message'
              : 'adb_connection_message',
        ),
        action: Strings.text(
          authorization ? 'adb_authorize' : 'adb_connection_action',
        ),
        dismiss: Strings.text('adb_later'),
      );
      if (!mounted || !open) return;
      await showDesignDialog<void>(
        context: context,
        builder: (_) => NetworkAdbSettings(
          controller: c,
          onNavigate: (p) {
            Navigator.pop(context);
            navigate(p);
          },
          onTab: (t) {
            Navigator.pop(context);
            update(() {
              page = 3;
              settingsTab = t;
            });
          },
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}

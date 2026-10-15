part of 'app_controller.dart';

extension PermissionPreferences on AppController {
  Future<void> setOverlayEnabled(bool enabled) async {
    if (_disposed || overlayPermissionPending) return;
    overlayPermissionPending = true;
    error = null;
    _notify();
    try {
      final result = await bridge.call('setOverlayEnabled', {
        'enabled': enabled,
      });
      if (_disposed) return;
      final next = Map<String, dynamic>.from(result['config'] ?? {});
      if (next['overlayEnabled'] is! bool) throw StateError('overlay_result');
      restore(next);
      if (result['status'] is Map) {
        status = Map<String, dynamic>.from(result['status']);
      }
    } catch (_) {
      if (!_disposed) error = Strings.text('overlay_authorization_error');
    } finally {
      overlayPermissionPending = false;
      _notify();
    }
  }

  Future<void> setAutoSystemAdb(bool enabled) async {
    if (_disposed || autoSystemAdbPending) return;
    autoSystemAdbPending = true;
    final before = autoSystemAdb;
    autoSystemAdb = enabled;
    _notify();
    try {
      if (!await save()) autoSystemAdb = before;
    } finally {
      autoSystemAdbPending = false;
      _notify();
    }
  }
}

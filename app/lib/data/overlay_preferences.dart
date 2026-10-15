part of 'app_controller.dart';

extension OverlayPreferences on AppController {
  String? get overlayPositionUnavailable => !overlayEnabled
      ? 'overlay_position_disabled'
      : overlays.isEmpty
      ? 'overlay_position_empty'
      : status['stopped'] == true
      ? 'overlay_position_stopped'
      : null;

  Future<bool> adjustOverlayPosition() async {
    if (overlayPositionUnavailable != null) return false;
    return _changeOverlayPosition('editOverlay');
  }

  Future<bool> resetOverlayPosition() =>
      _changeOverlayPosition('resetOverlayPosition');

  Future<bool> _changeOverlayPosition(String method) async {
    if (_disposed || overlayPositionPending || overlayPermissionPending) {
      return false;
    }
    overlayPositionPending = true;
    error = null;
    _notify();
    try {
      final result = await bridge.call(method);
      if (_disposed) return false;
      if (result['config'] is! Map) {
        throw StateError('overlay_position_result');
      }
      final next = result['config'] as Map;
      overlayX = (next['overlayX'] as num?)?.toDouble();
      overlayY = (next['overlayY'] as num?)?.toDouble();
      if (result['status'] is Map) {
        status = Map<String, dynamic>.from(result['status']);
      }
      return true;
    } catch (_) {
      if (!_disposed) {
        error = Strings.text(
          method == 'editOverlay'
              ? 'overlay_position_error'
              : 'overlay_restore_error',
        );
      }
      return false;
    } finally {
      overlayPositionPending = false;
      _notify();
    }
  }
}

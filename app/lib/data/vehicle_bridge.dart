import '../l10n/strings.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class VehicleBridge {
  static const _methods = MethodChannel('app.skyinfo.vehicle/runtime');
  static const _events = EventChannel('app.skyinfo.vehicle/events');
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final result = await _methods.invokeMapMethod<String, dynamic>(
        method,
        args,
      );
      return result ?? {};
    } on MissingPluginException {
      return method == 'load'
          ? {
              'config': <String, dynamic>{},
              'status': {'vehicle': Strings.text('text_c5bf1313e8')},
            }
          : {};
    }
  }

  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));
}

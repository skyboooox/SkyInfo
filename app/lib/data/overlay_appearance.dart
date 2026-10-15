part of 'app_controller.dart';

class OverlayAppearance {
  final AppController controller;
  OverlayAppearance(this.controller);
  Timer? _timer;
  Map<String, dynamic>? _pending;
  Future<void>? _sending;
  Future<void> _commits = Future.value();
  bool _closed = false, _used = false;

  void previewOpacity(double value) {
    _used = true;
    _pending = {
      'style': {'overlayOpacity': value.clamp(.1, .8)},
    };
    _schedule();
  }

  void cancel() {
    _pending = {'style': null};
    _schedule();
  }

  void _schedule() {
    if (_closed || _sending != null || _timer != null) return;
    _timer = Timer(const Duration(milliseconds: 33), () {
      _timer = null;
      unawaited(_send());
    });
  }

  Future<void> _send() async {
    if (_closed || _pending == null) return;
    final body = _pending!;
    _pending = null;
    final operation = controller.bridge.call('previewOverlayStyle', body);
    final completed = operation.then<void>((_) {}, onError: (Object _) {});
    _sending = completed;
    await completed;
    _sending = null;
    if (_pending != null) _schedule();
  }

  Future<void> _flush() async {
    _timer?.cancel();
    _timer = null;
    await _sending;
    _timer?.cancel();
    _timer = null;
    if (_pending != null) await _send();
  }

  Future<bool> commitOpacity(double value) =>
      _commit({'overlayOpacity': value.clamp(.1, .8)});

  Future<bool> commitFont(double value) => _commit({'overlayFont': value});

  Future<bool> _commit(Map<String, double> patch) {
    final result = Completer<bool>();
    _commits = _commits.then((_) async {
      if (_closed) {
        result.complete(false);
        return;
      }
      try {
        await _flush();
        final response = await controller.bridge.call('saveOverlayAppearance', {
          'style': patch,
        });
        if (_closed || controller._disposed) {
          result.complete(false);
          return;
        }
        final saved = response['config'] as Map;
        controller.overlayFont = (saved['overlayFont'] as num).toDouble();
        controller.overlayOpacity = (saved['overlayOpacity'] as num).toDouble();
        controller.error = null;
        controller._notify();
        result.complete(true);
      } catch (_) {
        if (!_closed) {
          controller.error = Strings.text('text_40525a7328');
          cancel();
          controller._notify();
        }
        result.complete(false);
      }
    });
    return result.future;
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
    _pending = null;
    if (_used) {
      unawaited(
        controller.bridge
            .call('previewOverlayStyle', {'style': null})
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Repaints decorative layers at most 20 times per second without rebuilding UI.
class PaintClock extends ChangeNotifier {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double seconds = 0, _base = 0;
  PaintClock(TickerProvider provider) {
    _ticker = provider.createTicker((elapsed) {
      if (elapsed - _last < const Duration(milliseconds: 50)) return;
      _last = elapsed;
      seconds = _base + elapsed.inMicroseconds / 1000000;
      notifyListeners();
    });
  }
  bool get isRunning => _ticker.isActive;
  void setRunning(bool value) {
    if (value == _ticker.isActive) return;
    if (value) {
      _last = Duration.zero;
      _base = seconds;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

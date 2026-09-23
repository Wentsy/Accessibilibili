import 'dart:async';

/// Coalesces a burst of stream errors into one cancellable reconnect.
class LiveReconnectScheduler {
  LiveReconnectScheduler({this.delay = const Duration(seconds: 3)});

  final Duration delay;
  Timer? _timer;
  int _generation = 0;
  bool _running = false;

  bool get isRunning => _running;
  bool get isPending => _timer != null;

  void schedule(Future<void> Function(bool Function() isCurrent) reconnect) {
    if (_timer != null || _running) return;
    final generation = _generation;
    _timer = Timer(delay, () async {
      _timer = null;
      if (generation != _generation) return;
      _running = true;
      try {
        await reconnect(() => generation == _generation);
      } catch (_) {
        // A later stream error may schedule another attempt. Never leave an
        // unhandled timer error or start an unconditional retry loop.
      } finally {
        _running = false;
      }
    });
  }

  void cancel() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
  }
}

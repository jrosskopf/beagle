import 'dart:async';

/// Trailing-edge debouncer with optional max-wait.
///
/// `tap()` schedules `action` to fire `delay` after the most recent tap. If
/// taps keep arriving, the action is delayed up to [maxWait] before firing,
/// so a continuous stream of events still drains.
///
/// Internally this uses two timers: a `delay` timer that resets on every
/// tap, and a `maxWait` deadline timer that is set once on the first tap
/// of a burst and never reset until the action fires.
class Debouncer {
  Debouncer({required this.delay, this.maxWait});

  final Duration delay;
  final Duration? maxWait;

  Timer? _delayTimer;
  Timer? _maxTimer;
  void Function()? _pendingAction;

  void tap(void Function() action) {
    _pendingAction = action;
    _delayTimer?.cancel();
    _delayTimer = Timer(delay, _fire);
    if (_maxTimer == null && maxWait != null) {
      _maxTimer = Timer(maxWait!, _fire);
    }
  }

  void _fire() {
    _delayTimer?.cancel();
    _maxTimer?.cancel();
    _delayTimer = null;
    _maxTimer = null;
    final a = _pendingAction;
    _pendingAction = null;
    if (a != null) a();
  }

  void cancel() {
    _delayTimer?.cancel();
    _maxTimer?.cancel();
    _delayTimer = null;
    _maxTimer = null;
    _pendingAction = null;
  }
}

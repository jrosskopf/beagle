import 'dart:async';

/// Trailing-edge debouncer with optional max-wait.
///
/// `tap()` schedules `action` to fire `delay` after the most recent tap. If
/// taps keep arriving, the call is delayed up to [maxWait] before firing,
/// so a continuous stream of events still drains.
class Debouncer {
  Debouncer({required this.delay, this.maxWait});

  final Duration delay;
  final Duration? maxWait;

  Timer? _timer;
  DateTime? _firstTapAt;

  void tap(void Function() action) {
    _firstTapAt ??= DateTime.now();
    _timer?.cancel();
    final remainingMaxWait = maxWait == null
        ? null
        : maxWait! - DateTime.now().difference(_firstTapAt!);
    final wait = remainingMaxWait != null && remainingMaxWait < delay
        ? remainingMaxWait
        : delay;
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _firstTapAt = null;
      action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _firstTapAt = null;
  }
}

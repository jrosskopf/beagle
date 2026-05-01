import 'dart:async';

/// Periodic reconciliation timer per sync pair.
///
/// Watcher events are hints; this scheduler is the source of eventual
/// consistency. It also catches missed events on Linux when inotify drops
/// notifications immediately after a directory is created.
class ReconciliationScheduler {
  ReconciliationScheduler({
    required this.intervalSeconds,
    required this.onTick,
  });

  final int intervalSeconds;
  final FutureOr<void> Function() onTick;

  Timer? _timer;

  void start() {
    stop();
    _timer = Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
      await onTick();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

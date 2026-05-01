import 'dart:async';

/// Per-pair serialized queue with at-most-one queued follow-up.
///
/// The semantics requested by drive-beagle: while a sync is running, additional
/// triggers must NOT spawn parallel runs and must NOT pile up unboundedly.
/// Instead, exactly one follow-up slot is reserved; subsequent triggers
/// collapse into that slot.
class SyncQueue {
  SyncQueue({required this.runner});

  /// The function actually invoked for a sync. Should return when the run
  /// completes (success or failure). Errors are surfaced on the returned
  /// future of [enqueue].
  final Future<void> Function(SyncTrigger trigger) runner;

  bool _running = false;
  SyncTrigger? _pendingFollowUp;
  Completer<void>? _runningCompleter;
  Completer<void>? _pendingCompleter;

  /// Enqueue a trigger. Returns a future that completes when *this* trigger's
  /// effective sync run finishes (the actual run, or the coalesced follow-up
  /// it merged into).
  Future<void> enqueue(SyncTrigger trigger) {
    if (!_running) {
      _running = true;
      _runningCompleter = Completer<void>();
      final c = _runningCompleter!;
      unawaited(_loop(trigger, c));
      return c.future;
    }
    // Already running; coalesce into single follow-up slot.
    _pendingFollowUp = _coalesce(_pendingFollowUp, trigger);
    _pendingCompleter ??= Completer<void>();
    return _pendingCompleter!.future;
  }

  Future<void> _loop(SyncTrigger first, Completer<void> firstCompleter) async {
    try {
      await runner(first);
      firstCompleter.complete();
    } catch (e, st) {
      firstCompleter.completeError(e, st);
    }
    while (_pendingFollowUp != null) {
      final next = _pendingFollowUp!;
      _pendingFollowUp = null;
      final c = _pendingCompleter!;
      _pendingCompleter = null;
      try {
        await runner(next);
        c.complete();
      } catch (e, st) {
        c.completeError(e, st);
      }
    }
    _running = false;
  }

  static SyncTrigger _coalesce(SyncTrigger? prior, SyncTrigger next) {
    if (prior == null) return next;
    // Manual / bootstrap requests always win — they carry more user intent.
    if (next.reason == SyncTriggerReason.manual ||
        next.reason == SyncTriggerReason.bootstrap) return next;
    if (prior.reason == SyncTriggerReason.manual ||
        prior.reason == SyncTriggerReason.bootstrap) return prior;
    return prior; // both passive; first one wins
  }

  bool get isRunning => _running;
  bool get hasPending => _pendingFollowUp != null;
}

enum SyncTriggerReason { watcher, reconcile, manual, bootstrap }

class SyncTrigger {
  const SyncTrigger({
    required this.reason,
    required this.requestedAt,
    this.note,
  });
  final SyncTriggerReason reason;
  final DateTime requestedAt;
  final String? note;

  String get wire => switch (reason) {
        SyncTriggerReason.watcher => 'watcher',
        SyncTriggerReason.reconcile => 'reconcile',
        SyncTriggerReason.manual => 'manual',
        SyncTriggerReason.bootstrap => 'bootstrap',
      };
}

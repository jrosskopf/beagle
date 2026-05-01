import '../models.dart';

/// Finite state machine for a single sync pair.
///
/// Transitions:
///   idle      → watching        (start)
///   watching  → pending         (event/reconcile/manual)
///   pending   → syncing         (queue dispatched)
///   syncing   → idle | warning  (run finished, depending on result)
///   any       → paused          (pause)
///   paused    → idle            (resume)
///   any       → error           (unrecoverable failure)
///   error     → idle            (recover)
class PairStateMachine {
  PairStateMachine([this._state = PairLifecycleState.idle]);

  PairLifecycleState _state;
  PairLifecycleState get state => _state;

  bool transition(PairLifecycleEvent ev) {
    final next = _next(_state, ev);
    if (next == null) return false;
    _state = next;
    return true;
  }

  static PairLifecycleState? _next(
      PairLifecycleState s, PairLifecycleEvent ev) {
    switch (ev) {
      case PairLifecycleEvent.start:
        if (s == PairLifecycleState.idle ||
            s == PairLifecycleState.error ||
            s == PairLifecycleState.warning) {
          return PairLifecycleState.watching;
        }
        return null;
      case PairLifecycleEvent.changeDetected:
        if (s == PairLifecycleState.watching ||
            s == PairLifecycleState.idle ||
            s == PairLifecycleState.warning) {
          return PairLifecycleState.pending;
        }
        if (s == PairLifecycleState.syncing) {
          // Already syncing — caller should record a queued follow-up
          // outside the FSM. Stay in syncing.
          return PairLifecycleState.syncing;
        }
        return null;
      case PairLifecycleEvent.dispatch:
        if (s == PairLifecycleState.pending) return PairLifecycleState.syncing;
        return null;
      case PairLifecycleEvent.runSucceeded:
        if (s == PairLifecycleState.syncing) return PairLifecycleState.idle;
        return null;
      case PairLifecycleEvent.runFailedRecoverable:
        if (s == PairLifecycleState.syncing) return PairLifecycleState.warning;
        return null;
      case PairLifecycleEvent.runFailedFatal:
        if (s == PairLifecycleState.syncing) return PairLifecycleState.error;
        return null;
      case PairLifecycleEvent.pause:
        if (s != PairLifecycleState.paused) return PairLifecycleState.paused;
        return null;
      case PairLifecycleEvent.resume:
        if (s == PairLifecycleState.paused) return PairLifecycleState.idle;
        return null;
      case PairLifecycleEvent.recover:
        if (s == PairLifecycleState.error) return PairLifecycleState.idle;
        return null;
    }
  }
}

enum PairLifecycleEvent {
  start,
  changeDetected,
  dispatch,
  runSucceeded,
  runFailedRecoverable,
  runFailedFatal,
  pause,
  resume,
  recover,
}

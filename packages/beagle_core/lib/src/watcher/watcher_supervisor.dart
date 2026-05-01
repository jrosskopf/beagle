import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../logging/logger.dart';
import '../models.dart';
import '../process/process_runner.dart';
import 'fswatch_backend.dart';
import 'inotifywait_backend.dart';
import 'watcher_backend.dart';

/// Picks the right backend for the host OS.
WatcherBackend defaultBackendForHost(ProcessRunner runner) {
  if (Platform.isMacOS) return FswatchBackend(runner: runner);
  return InotifywaitBackend(runner: runner);
}

/// Supervises a watcher backend for one sync pair: restarts on crash with
/// exponential backoff, surfaces a stable broadcast stream of events, and
/// emits health updates so the UI can show a "warning" badge after repeated
/// failures.
class WatcherSupervisor {
  WatcherSupervisor({
    required this.pair,
    required this.backendFactory,
    this.maxBackoff = const Duration(seconds: 30),
    this.warningRestartCount = 5,
  });

  final SyncPair pair;
  final WatcherBackend Function() backendFactory;
  final Duration maxBackoff;
  final int warningRestartCount;

  final _events = StreamController<WatcherEvent>.broadcast();
  final _health = StreamController<WatcherHealth>.broadcast();

  WatcherBackend? _current;
  bool _stopping = false;
  int _restarts = 0;

  Stream<WatcherEvent> get events => _events.stream;
  Stream<WatcherHealth> get health => _health.stream;

  Future<void> start() async {
    _stopping = false;
    unawaited(_runLoop());
  }

  Future<void> stop() async {
    _stopping = true;
    await _current?.stop();
    _current = null;
    if (!_events.isClosed) await _events.close();
    if (!_health.isClosed) await _health.close();
  }

  Future<void> _runLoop() async {
    while (!_stopping) {
      final backend = backendFactory();
      _current = backend;
      _health.add(WatcherHealth.running(pair.id, backend.name));
      try {
        await for (final ev in backend.start(pair)) {
          if (_stopping) break;
          _events.add(ev);
        }
      } catch (e, st) {
        StructuredLogger.instance.error(
          'watcher crashed',
          component: 'supervisor',
          pairId: pair.id,
          data: {'error': e.toString(), 'stack': st.toString()},
        );
      }
      if (_stopping) break;
      _restarts++;
      final delay = _backoff(_restarts);
      _health.add(WatcherHealth.restarting(pair.id, backend.name, _restarts, delay));
      if (_restarts >= warningRestartCount) {
        _health.add(WatcherHealth.warning(pair.id, backend.name, _restarts));
      }
      await Future<void>.delayed(delay);
    }
  }

  Duration _backoff(int restartCount) {
    final ms = math.min(maxBackoff.inMilliseconds,
        1000 * math.pow(2, restartCount - 1).toInt());
    return Duration(milliseconds: ms);
  }
}

class WatcherHealth {
  WatcherHealth._(this.pairId, this.backend, this.state, this.restarts, this.nextRetry);
  final String pairId;
  final String backend;
  final WatcherHealthState state;
  final int restarts;
  final Duration? nextRetry;

  factory WatcherHealth.running(String pairId, String backend) =>
      WatcherHealth._(pairId, backend, WatcherHealthState.running, 0, null);
  factory WatcherHealth.restarting(
          String pairId, String backend, int restarts, Duration nextRetry) =>
      WatcherHealth._(pairId, backend, WatcherHealthState.restarting, restarts,
          nextRetry);
  factory WatcherHealth.warning(String pairId, String backend, int restarts) =>
      WatcherHealth._(
          pairId, backend, WatcherHealthState.warning, restarts, null);

  Map<String, Object?> toJson() => {
        'pair_id': pairId,
        'backend': backend,
        'state': state.name,
        'restarts': restarts,
        if (nextRetry != null) 'next_retry_ms': nextRetry!.inMilliseconds,
      };
}

enum WatcherHealthState { running, restarting, warning }

/// Linux-specific helper: read `/proc/sys/fs/inotify/max_user_watches`.
/// Returns null if not Linux or unreadable.
Future<int?> readInotifyMaxUserWatches() async {
  if (!Platform.isLinux) return null;
  try {
    final f = File('/proc/sys/fs/inotify/max_user_watches');
    if (!await f.exists()) return null;
    final s = (await f.readAsString()).trim();
    return int.tryParse(s);
  } catch (_) {
    return null;
  }
}

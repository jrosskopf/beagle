import 'dart:async';

import '../models.dart';

/// Abstract watcher backend: emits normalized [WatcherEvent]s for one sync pair.
///
/// Implementations must be:
///   - re-startable (each call to [start] returns a fresh stream).
///   - safe to terminate via [stop] mid-stream.
///   - tolerant of unparsable lines (drop + log, never throw).
abstract class WatcherBackend {
  String get name;

  /// Begin watching [pair.localPath]. The returned stream completes when the
  /// underlying process exits (clean or otherwise).
  Stream<WatcherEvent> start(SyncPair pair);

  /// Send SIGTERM to the watcher process and release resources.
  Future<void> stop();

  /// Diagnostic label suitable for logs: "inotifywait pid=1234".
  String describe();
}

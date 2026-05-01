import '../models.dart';

/// Re-exported for backend implementations.
typedef NormalizedWatcherEvent = WatcherEvent;

/// Normalized watcher kind decoder shared by inotify and fswatch backends.
WatcherKind classifyEventNames(Iterable<String> names) {
  final set = names.map((s) => s.toUpperCase()).toSet();
  if (set.contains('MOVED_FROM') || set.contains('MOVED_TO') || set.contains('RENAMED') || set.contains('MOVED')) {
    return WatcherKind.moved;
  }
  if (set.contains('DELETE') || set.contains('REMOVED') || set.contains('DELETESELF')) {
    return WatcherKind.deleted;
  }
  if (set.contains('CREATE') || set.contains('CREATED')) {
    return WatcherKind.created;
  }
  return WatcherKind.modified;
}

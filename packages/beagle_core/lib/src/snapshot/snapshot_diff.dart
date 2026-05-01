import '../models.dart';

/// Classifies differences between two snapshots into authoritative change
/// candidates. Move detection is heuristic — same size+modtime on a deleted
/// path and a created path within the same diff is treated as a rename.
class SnapshotDiff {
  SnapshotDiff({
    required this.created,
    required this.modified,
    required this.deleted,
    required this.moved,
  });

  final List<SnapshotEntry> created;
  final List<SnapshotEntry> modified;
  final List<SnapshotEntry> deleted;
  final List<MovedEntry> moved;

  bool get isEmpty =>
      created.isEmpty && modified.isEmpty && deleted.isEmpty && moved.isEmpty;
  int get totalCount => created.length + modified.length + deleted.length + moved.length;
}

class MovedEntry {
  MovedEntry({required this.from, required this.to});
  final SnapshotEntry from;
  final SnapshotEntry to;
}

class SnapshotDiffer {
  /// Diff `before` → `after`. Both snapshots must cover the same logical side
  /// (caller's responsibility).
  SnapshotDiff diff(Snapshot before, Snapshot after) {
    final beforeMap = {for (final e in before.entries) e.path: e};
    final afterMap = {for (final e in after.entries) e.path: e};

    final createdRaw = <SnapshotEntry>[];
    final modifiedRaw = <SnapshotEntry>[];
    final deletedRaw = <SnapshotEntry>[];

    for (final e in afterMap.values) {
      final prior = beforeMap[e.path];
      if (prior == null) {
        createdRaw.add(e);
      } else if (_changed(prior, e)) {
        modifiedRaw.add(e);
      }
    }
    for (final e in beforeMap.values) {
      if (!afterMap.containsKey(e.path)) deletedRaw.add(e);
    }

    // Heuristic move detection: pair (deleted, created) with identical size
    // and equal-or-similar modtime. Same hash if both available, else fall
    // back to size+modtime.
    final moved = <MovedEntry>[];
    final createdLeft = <SnapshotEntry>[];
    for (final c in createdRaw) {
      final i = deletedRaw.indexWhere((d) => _likelyMove(d, c));
      if (i >= 0) {
        moved.add(MovedEntry(from: deletedRaw[i], to: c));
        deletedRaw.removeAt(i);
      } else {
        createdLeft.add(c);
      }
    }

    return SnapshotDiff(
      created: createdLeft,
      modified: modifiedRaw,
      deleted: deletedRaw,
      moved: moved,
    );
  }

  static bool _changed(SnapshotEntry a, SnapshotEntry b) {
    if (a.hash != null && b.hash != null) return a.hash != b.hash;
    return a.size != b.size ||
        a.modtime.millisecondsSinceEpoch != b.modtime.millisecondsSinceEpoch;
  }

  static bool _likelyMove(SnapshotEntry deleted, SnapshotEntry created) {
    if (deleted.hash != null && created.hash != null) {
      return deleted.hash == created.hash;
    }
    if (deleted.size != created.size) return false;
    final dt = (deleted.modtime
            .difference(created.modtime)
            .inSeconds)
        .abs();
    return dt < 5;
  }
}

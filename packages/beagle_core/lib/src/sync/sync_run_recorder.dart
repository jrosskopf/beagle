import '../journal/journal.dart';
import '../models.dart';
import '../snapshot/snapshot_diff.dart';

/// Translates a [SnapshotDiff] (and optional bisync output parse) into
/// authoritative [ChangeEntry] rows for a [SyncRun].
class SyncRunRecorder {
  /// Build the journal entries representing the authoritative outcome of one
  /// sync run. Caller is responsible for actually appending them to the
  /// [Journal] on disk.
  List<ChangeEntry> record({
    required SyncRun run,
    required ChangeSide attribution,
    required SnapshotDiff localDiff,
    required SnapshotDiff remoteDiff,
  }) {
    final out = <ChangeEntry>[];

    void addAll(SnapshotDiff d, ChangeSide side) {
      for (final e in d.created) {
        out.add(_entry(run, side, ChangeKind.created, e.path,
            size: e.size, modtime: e.modtime, hash: e.hash));
      }
      for (final e in d.modified) {
        out.add(_entry(run, side, ChangeKind.modified, e.path,
            size: e.size, modtime: e.modtime, hash: e.hash));
      }
      for (final e in d.deleted) {
        out.add(_entry(run, side, ChangeKind.deleted, e.path,
            size: e.size, modtime: e.modtime));
      }
      for (final m in d.moved) {
        out.add(_entry(run, side, ChangeKind.moved, m.to.path,
            previousPath: m.from.path,
            size: m.to.size,
            modtime: m.to.modtime));
      }
    }

    addAll(localDiff, ChangeSide.local);
    addAll(remoteDiff, ChangeSide.remote);
    // If both diffs report the same path, attribute it to the originating side
    // when caller provided one. We don't dedupe here; the journal carries one
    // entry per (side, path) which is fine — agents can collapse if needed.
    return out;
  }

  ChangeEntry _entry(
    SyncRun run,
    ChangeSide side,
    ChangeKind kind,
    String path, {
    String? previousPath,
    int? size,
    DateTime? modtime,
    String? hash,
  }) {
    return ChangeEntry(
      journalId: 0, // assigned by Journal.append
      pairId: run.pairId,
      syncRunId: run.id,
      ts: DateTime.now().toUtc(),
      source: ChangeSource.sync,
      side: side,
      kind: kind,
      path: path,
      previousPath: previousPath,
      fingerprint: (size != null || modtime != null || hash != null)
          ? Fingerprint(
              strategy: hash != null ? 'hash' : 'size_modtime',
              size: size,
              modtime: modtime,
              hash: hash,
            )
          : null,
      syncStatus: SyncStatus.applied,
      agentVisibility: true,
    );
  }
}

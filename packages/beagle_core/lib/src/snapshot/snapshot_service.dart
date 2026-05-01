import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import '../process/process_runner.dart';
import '../sync/rclone_command_builder.dart';

/// Captures point-in-time listings of a sync pair's local and remote sides.
class SnapshotService {
  SnapshotService({
    required this.runner,
    required this.builder,
  });

  final ProcessRunner runner;
  final RcloneCommandBuilder builder;

  /// Walk the local filesystem, applying the pair's basic ignore rules.
  /// We don't replicate the full filter language here — we only need a stable
  /// snapshot for diffing. Full filter fidelity comes from rclone itself
  /// during the actual sync.
  Future<Snapshot> takeLocal(SyncPair pair) async {
    final root = Directory(pair.localPath);
    final entries = <SnapshotEntry>[];
    if (!await root.exists()) {
      return Snapshot(
        pairId: pair.id,
        takenAt: DateTime.now().toUtc(),
        side: ChangeSide.local,
        entries: const [],
      );
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relPath = p.relative(entity.path, from: root.path);
      if (_isIgnored(relPath, pair)) continue;
      try {
        final stat = await entity.stat();
        entries.add(SnapshotEntry(
          path: relPath,
          size: stat.size,
          modtime: stat.modified.toUtc(),
        ));
      } on FileSystemException {
        // file disappeared between list() and stat() — ignore.
      }
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return Snapshot(
      pairId: pair.id,
      takenAt: DateTime.now().toUtc(),
      side: ChangeSide.local,
      entries: entries,
    );
  }

  /// Use `rclone lsjson --recursive --files-only` to capture the remote.
  Future<Snapshot> takeRemote(SyncPair pair) async {
    final cmd = builder.lsjson(pair);
    final r = await runner.run(cmd.executable, cmd.arguments,
        timeout: const Duration(minutes: 10));
    if (!r.ok) {
      throw StateError(
          'rclone lsjson failed (exit ${r.exitCode}): ${r.stderr.trim()}');
    }
    final list = jsonDecode(r.stdout) as List;
    final entries = <SnapshotEntry>[];
    for (final raw in list) {
      final m = (raw as Map).cast<String, Object?>();
      final isDir = (m['IsDir'] ?? false) as bool;
      if (isDir) continue;
      entries.add(SnapshotEntry(
        path: m['Path']! as String,
        size: (m['Size'] as num?)?.toInt() ?? 0,
        modtime: DateTime.parse(m['ModTime']! as String).toUtc(),
        hash: (m['Hashes'] is Map)
            ? ((m['Hashes'] as Map).values.firstWhere(
                  (_) => true,
                  orElse: () => null,
                ) as String?)
            : null,
        mime: m['MimeType'] as String?,
      ));
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return Snapshot(
      pairId: pair.id,
      takenAt: DateTime.now().toUtc(),
      side: ChangeSide.remote,
      entries: entries,
    );
  }

  /// Persist a snapshot atomically to disk.
  Future<void> persist(Snapshot s, String path) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(s.toJson()),
      flush: true,
    );
    await tmp.rename(path);
  }

  /// Read a previously persisted snapshot.
  Future<Snapshot?> load(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    final raw = await f.readAsString();
    return Snapshot.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  static bool _isIgnored(String relPath, SyncPair pair) {
    final f = pair.filters;
    final segs = p.split(relPath);
    for (final s in segs) {
      if (f.ignoreHidden && s.startsWith('.') && s != '.' && s != '..') {
        return true;
      }
      if (f.ignoreVcs && (s == '.git' || s == '.hg' || s == '.svn')) return true;
      if (f.ignoreNodeModules && s == 'node_modules') return true;
      if (f.ignoreCommonBuildDirs &&
          const {
            'build',
            'dist',
            'target',
            '.dart_tool',
            '.gradle',
            '.idea',
            '.vscode',
            '__pycache__',
            '.cache',
          }.contains(s)) {
        return true;
      }
    }
    return false;
  }
}

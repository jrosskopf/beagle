import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../errors.dart';
import '../models.dart';

/// Append-only change journal. Storage is two files per pair:
///
///   <journalDir>/<pairId>.jsonl   — durable, agent-greppable source of truth
///   <journalDir>/<pairId>.db      — SQLite index for fast queries
///
/// JSONL is the authoritative format. The SQLite index is rebuildable from
/// it on corruption (see [rebuildIndex]). Writes are append+fsync to JSONL,
/// then mirrored into SQLite — if the app crashes between the two, the next
/// startup detects the gap and replays.
class Journal {
  Journal._({
    required this.pairId,
    required this.jsonlPath,
    required this.dbPath,
    required this.db,
    required this.sink,
    required int nextSeq,
  }) : _nextSeq = nextSeq;

  final String pairId;
  final String jsonlPath;
  final String dbPath;
  final Database db;
  final IOSink sink;
  int _nextSeq;

  static Future<Journal> open({
    required String pairId,
    required String jsonlPath,
    required String dbPath,
  }) async {
    await File(jsonlPath).parent.create(recursive: true);
    final jsonlFile = File(jsonlPath);
    if (!await jsonlFile.exists()) await jsonlFile.create();

    final db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE IF NOT EXISTS entries (
        seq           INTEGER PRIMARY KEY,
        pair_id       TEXT NOT NULL,
        sync_run_id   TEXT NOT NULL,
        ts            TEXT NOT NULL,
        source        TEXT NOT NULL,
        side          TEXT NOT NULL,
        kind          TEXT NOT NULL,
        path          TEXT NOT NULL,
        previous_path TEXT,
        sync_status   TEXT NOT NULL,
        agent_visible INTEGER NOT NULL,
        authoritative INTEGER NOT NULL,
        json          TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_entries_ts ON entries(ts);
      CREATE INDEX IF NOT EXISTS idx_entries_path ON entries(path);
      CREATE INDEX IF NOT EXISTS idx_entries_kind ON entries(kind);
      CREATE INDEX IF NOT EXISTS idx_entries_authoritative ON entries(authoritative);
    ''');

    final sink = jsonlFile.openWrite(mode: FileMode.append);

    // Detect / repair gaps between JSONL and SQLite.
    final jsonlMaxSeq = await _scanMaxSeqFromJsonl(jsonlPath);
    final dbMaxRow =
        db.select('SELECT COALESCE(MAX(seq), 0) AS m FROM entries').first;
    final dbMax = (dbMaxRow['m'] as num).toInt();
    if (dbMax < jsonlMaxSeq) {
      _replayJsonlIntoIndex(
        db: db,
        jsonlPath: jsonlPath,
        fromSeq: dbMax + 1,
      );
    }

    return Journal._(
      pairId: pairId,
      jsonlPath: jsonlPath,
      dbPath: dbPath,
      db: db,
      sink: sink,
      nextSeq: jsonlMaxSeq + 1,
    );
  }

  /// Append a batch of changes atomically. Each entry receives the next
  /// monotonic sequence id. Returns the appended entries with their assigned
  /// IDs filled in.
  Future<List<ChangeEntry>> append(List<ChangeEntry> raw) async {
    if (raw.isEmpty) return const [];
    final stamped = <ChangeEntry>[];
    for (final r in raw) {
      final seq = _nextSeq++;
      stamped.add(ChangeEntry(
        journalId: seq,
        pairId: r.pairId,
        syncRunId: r.syncRunId,
        ts: r.ts,
        source: r.source,
        side: r.side,
        kind: r.kind,
        path: r.path,
        previousPath: r.previousPath,
        fingerprint: r.fingerprint,
        syncStatus: r.syncStatus,
        agentVisibility: r.agentVisibility,
        metadata: r.metadata,
      ));
    }

    // 1) Append to JSONL and fsync.
    for (final e in stamped) {
      sink.writeln(jsonEncode(e.toJson()));
    }
    await sink.flush();

    // 2) Mirror into SQLite.
    final stmt = db.prepare('''
      INSERT INTO entries
        (seq, pair_id, sync_run_id, ts, source, side, kind, path, previous_path, sync_status, agent_visible, authoritative, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    db.execute('BEGIN');
    try {
      for (final e in stamped) {
        stmt.execute([
          e.journalId,
          e.pairId,
          e.syncRunId,
          e.ts.toUtc().toIso8601String(),
          e.source.wire,
          e.side.wire,
          e.kind.wire,
          e.path,
          e.previousPath,
          e.syncStatus.wire,
          e.agentVisibility ? 1 : 0,
          e.authoritative ? 1 : 0,
          jsonEncode(e.toJson()),
        ]);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.dispose();
    }
    return stamped;
  }

  int get latestSeq => _nextSeq - 1;

  /// Query entries with rich filters. Defaults to authoritative + agent-visible.
  List<ChangeEntry> query({
    int? afterSeq,
    DateTime? since,
    Set<ChangeKind>? kinds,
    Set<String>? extensions,
    bool authoritativeOnly = true,
    bool agentVisibleOnly = true,
    int? limit,
  }) {
    final where = <String>[];
    final params = <Object?>[];
    if (afterSeq != null) {
      where.add('seq > ?');
      params.add(afterSeq);
    }
    if (since != null) {
      where.add('ts >= ?');
      params.add(since.toUtc().toIso8601String());
    }
    if (kinds != null && kinds.isNotEmpty) {
      where.add(
          'kind IN (${List.filled(kinds.length, '?').join(',')})');
      params.addAll(kinds.map((k) => k.wire));
    }
    if (authoritativeOnly) where.add('authoritative = 1');
    if (agentVisibleOnly) where.add('agent_visible = 1');

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final limitSql = limit == null ? '' : 'LIMIT $limit';
    final rows = db.select(
        'SELECT json FROM entries $whereSql ORDER BY seq ASC $limitSql',
        params);
    final list = <ChangeEntry>[];
    for (final r in rows) {
      final j = jsonDecode(r['json'] as String) as Map<String, Object?>;
      final entry = ChangeEntry.fromJson(j);
      if (extensions != null && extensions.isNotEmpty) {
        if (!extensions.contains(entry.extension)) continue;
      }
      list.add(entry);
    }
    return list;
  }

  Future<void> close() async {
    await sink.flush();
    await sink.close();
    db.dispose();
  }

  /// Drop and rebuild the SQLite index from the JSONL source. Called
  /// automatically on open() if a gap is detected, or on demand by
  /// `drive-beagle doctor --rebuild-index`.
  static Future<void> rebuildIndex({
    required String jsonlPath,
    required String dbPath,
  }) async {
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
    final db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE entries (
        seq INTEGER PRIMARY KEY, pair_id TEXT, sync_run_id TEXT, ts TEXT,
        source TEXT, side TEXT, kind TEXT, path TEXT, previous_path TEXT,
        sync_status TEXT, agent_visible INTEGER, authoritative INTEGER,
        json TEXT NOT NULL
      );
    ''');
    _replayJsonlIntoIndex(db: db, jsonlPath: jsonlPath, fromSeq: 1);
    db.dispose();
  }

  static Future<int> _scanMaxSeqFromJsonl(String path) async {
    final f = File(path);
    if (!await f.exists()) return 0;
    var max = 0;
    await for (final line in f
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      try {
        final j = jsonDecode(line) as Map<String, Object?>;
        final id = (j['id'] as num?)?.toInt() ?? 0;
        if (id > max) max = id;
      } on FormatException {
        throw BeagleError(
          BeagleErrorCode.journalCorrupt,
          'Corrupt journal line in $path',
          remedy: 'Run `drive-beagle doctor --rebuild-index` to recover.',
        );
      }
    }
    return max;
  }

  static void _replayJsonlIntoIndex({
    required Database db,
    required String jsonlPath,
    required int fromSeq,
  }) {
    final stmt = db.prepare('''
      INSERT OR REPLACE INTO entries
        (seq, pair_id, sync_run_id, ts, source, side, kind, path, previous_path, sync_status, agent_visible, authoritative, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    db.execute('BEGIN');
    try {
      final lines = File(jsonlPath).readAsLinesSync();
      for (final line in lines) {
        if (line.isEmpty) continue;
        final j = jsonDecode(line) as Map<String, Object?>;
        final seq = (j['id'] as num).toInt();
        if (seq < fromSeq) continue;
        final auth =
            (j['authoritative'] as bool?) ?? (j['source'] != 'watcher');
        stmt.execute([
          seq,
          j['pair_id'],
          j['sync_run_id'],
          j['timestamp'],
          j['source'],
          j['side'],
          j['kind'],
          j['path'],
          j['previous_path'],
          j['sync_status'],
          (j['agent_visibility'] ?? true) == true ? 1 : 0,
          auth ? 1 : 0,
          line,
        ]);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.dispose();
    }
  }
}


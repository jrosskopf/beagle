import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('beagle-journal-');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('append + query round-trips', () async {
    final journal = await Journal.open(
      pairId: 'p1',
      jsonlPath: p.join(tmp.path, 'p1.jsonl'),
      dbPath: p.join(tmp.path, 'p1.db'),
    );

    final now = DateTime.now().toUtc();
    final stamped = await journal.append([
      ChangeEntry(
        journalId: 0,
        pairId: 'p1',
        syncRunId: 'r1',
        ts: now,
        source: ChangeSource.sync,
        side: ChangeSide.local,
        kind: ChangeKind.modified,
        path: 'foo.md',
        syncStatus: SyncStatus.applied,
        agentVisibility: true,
      ),
      ChangeEntry(
        journalId: 0,
        pairId: 'p1',
        syncRunId: 'r1',
        ts: now,
        source: ChangeSource.watcher,
        side: ChangeSide.local,
        kind: ChangeKind.created,
        path: 'bar.md',
        syncStatus: SyncStatus.detected,
        agentVisibility: true,
      ),
    ]);
    expect(stamped[0].journalId, 1);
    expect(stamped[1].journalId, 2);
    expect(journal.latestSeq, 2);

    // Default query: authoritative-only.
    final auth = journal.query();
    expect(auth, hasLength(1));
    expect(auth.single.path, 'foo.md');

    // With tentative.
    final all = journal.query(authoritativeOnly: false);
    expect(all, hasLength(2));

    await journal.close();
  });

  test('rebuildIndex restores SQLite from JSONL', () async {
    final jsonl = p.join(tmp.path, 'p1.jsonl');
    final db = p.join(tmp.path, 'p1.db');

    final j1 = await Journal.open(pairId: 'p1', jsonlPath: jsonl, dbPath: db);
    await j1.append([
      ChangeEntry(
        journalId: 0,
        pairId: 'p1',
        syncRunId: 'r1',
        ts: DateTime.now().toUtc(),
        source: ChangeSource.sync,
        side: ChangeSide.remote,
        kind: ChangeKind.created,
        path: 'a.md',
        syncStatus: SyncStatus.applied,
        agentVisibility: true,
      ),
    ]);
    await j1.close();

    // Wipe SQLite, rebuild.
    await File(db).delete();
    await Journal.rebuildIndex(jsonlPath: jsonl, dbPath: db);

    final j2 = await Journal.open(pairId: 'p1', jsonlPath: jsonl, dbPath: db);
    expect(j2.query(), hasLength(1));
    expect(j2.latestSeq, 1);
    await j2.close();
  });

  test('extension filter matches dot-prefixed extensions', () async {
    final j = await Journal.open(
      pairId: 'p1',
      jsonlPath: p.join(tmp.path, 'p1.jsonl'),
      dbPath: p.join(tmp.path, 'p1.db'),
    );
    final ts = DateTime.now().toUtc();
    await j.append([
      _entry('a.md'),
      _entry('b.json'),
      _entry('c.txt'),
    ].map((e) => e.copyTs(ts)).toList());
    final mdOnly = j.query(extensions: {'.md'});
    expect(mdOnly.map((e) => e.path).toList(), ['a.md']);
    await j.close();
  });
}

ChangeEntry _entry(String path) => ChangeEntry(
      journalId: 0,
      pairId: 'p1',
      syncRunId: 'r1',
      ts: DateTime.now().toUtc(),
      source: ChangeSource.sync,
      side: ChangeSide.local,
      kind: ChangeKind.modified,
      path: path,
      syncStatus: SyncStatus.applied,
      agentVisibility: true,
    );

extension on ChangeEntry {
  ChangeEntry copyTs(DateTime ts) => ChangeEntry(
        journalId: journalId,
        pairId: pairId,
        syncRunId: syncRunId,
        ts: ts,
        source: source,
        side: side,
        kind: kind,
        path: path,
        previousPath: previousPath,
        fingerprint: fingerprint,
        syncStatus: syncStatus,
        agentVisibility: agentVisibility,
        metadata: metadata,
      );
}

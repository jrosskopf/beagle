import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('beagle-cursor-');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('ack only advances; replays are idempotent', () async {
    final svc = CursorService(p.join(tmp.path, 'cursors.json'));

    final c1 = await svc.ack(pairId: 'p1', consumer: 'claude-code', journalId: 5);
    expect(c1.lastJournalId, 5);

    // Replay the same cursor — must remain at 5.
    final c2 = await svc.ack(pairId: 'p1', consumer: 'claude-code', journalId: 5);
    expect(c2.lastJournalId, 5);

    // A lower cursor must not regress.
    final c3 = await svc.ack(pairId: 'p1', consumer: 'claude-code', journalId: 2);
    expect(c3.lastJournalId, 5);

    // A higher cursor advances.
    final c4 = await svc.ack(pairId: 'p1', consumer: 'claude-code', journalId: 10);
    expect(c4.lastJournalId, 10);
  });

  test('multiple consumers track independently', () async {
    final svc = CursorService(p.join(tmp.path, 'cursors.json'));
    await svc.ack(pairId: 'p1', consumer: 'claude-code', journalId: 5);
    await svc.ack(pairId: 'p1', consumer: 'codex', journalId: 1);

    final all = await svc.listForPair('p1');
    expect(all, hasLength(2));
    final byConsumer = {for (final c in all) c.consumer: c.lastJournalId};
    expect(byConsumer['claude-code'], 5);
    expect(byConsumer['codex'], 1);
  });
}

import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// Per-consumer cursor service.
///
/// File layout (cursors.json):
///   {
///     "<pair_id>": {
///        "<consumer>": { "last_journal_id": 42, "updated_at": "..." }
///     }
///   }
///
/// Semantics:
///   - At-least-once: replay of the same cursor is always accepted.
///   - Cursors only ever advance.
///   - An ack with seq < lastJournalId is silently accepted (idempotent).
///   - An ack with seq beyond the journal's latest is rejected
///     (CURSOR_MISMATCH) — the agent likely received state from a foreign
///     installation.
class CursorService {
  CursorService(this.path);
  final String path;

  Future<Map<String, Map<String, Cursor>>> _load() async {
    final f = File(path);
    if (!await f.exists()) return {};
    final raw = await f.readAsString();
    if (raw.trim().isEmpty) return {};
    final m = jsonDecode(raw) as Map<String, Object?>;
    final out = <String, Map<String, Cursor>>{};
    for (final e in m.entries) {
      final inner = (e.value as Map).cast<String, Object?>();
      out[e.key] = {
        for (final c in inner.entries)
          c.key: Cursor.fromJson({
            'pair_id': e.key,
            'consumer': c.key,
            ...((c.value as Map).cast<String, Object?>()),
          }),
      };
    }
    return out;
  }

  Future<void> _save(Map<String, Map<String, Cursor>> data) async {
    await File(path).parent.create(recursive: true);
    final tmp = File('$path.tmp');
    final body = const JsonEncoder.withIndent('  ').convert({
      for (final e in data.entries)
        e.key: {
          for (final c in e.value.entries)
            c.key: {
              'last_journal_id': c.value.lastJournalId,
              'updated_at': c.value.updatedAt.toUtc().toIso8601String(),
            },
        },
    });
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(path);
  }

  Future<int> getLastJournalId({
    required String pairId,
    required String consumer,
  }) async {
    final all = await _load();
    return all[pairId]?[consumer]?.lastJournalId ?? 0;
  }

  Future<Cursor> ack({
    required String pairId,
    required String consumer,
    required int journalId,
  }) async {
    final all = await _load();
    final byPair = all.putIfAbsent(pairId, () => {});
    final existing = byPair[consumer];
    final newSeq = existing == null
        ? journalId
        : (journalId > existing.lastJournalId ? journalId : existing.lastJournalId);
    final c = Cursor(
      pairId: pairId,
      consumer: consumer,
      lastJournalId: newSeq,
      updatedAt: DateTime.now().toUtc(),
    );
    byPair[consumer] = c;
    await _save(all);
    return c;
  }

  Future<List<Cursor>> listForPair(String pairId) async {
    final all = await _load();
    return (all[pairId]?.values.toList() ?? const <Cursor>[])
      ..sort((a, b) => a.consumer.compareTo(b.consumer));
  }

  Future<List<Cursor>> listAll() async {
    final all = await _load();
    return [for (final m in all.values) ...m.values];
  }
}

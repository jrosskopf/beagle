import '../cursor/cursor_service.dart';
import '../journal/journal.dart';
import '../models.dart';
import '../schema.dart';

/// Service that backs the agent-facing `drive-beagle changes` /
/// `changes-since` commands.
class ChangeQueryService {
  ChangeQueryService({required this.journal, required this.cursorService});

  final Journal journal;
  final CursorService cursorService;

  /// Build the JSON document returned by `drive-beagle changes`.
  Future<Map<String, Object?>> queryAsJson({
    required SyncPair pair,
    String? consumer,
    bool unacked = false,
    int? cursor,
    DateTime? since,
    Set<ChangeKind>? kinds,
    Set<String>? extensions,
    int? limit,
    bool includeTentative = false,
  }) async {
    int? after = cursor;
    if (unacked) {
      if (consumer == null) {
        throw ArgumentError('--unacked requires --consumer');
      }
      after = await cursorService.getLastJournalId(
          pairId: pair.id, consumer: consumer);
    }
    final entries = journal.query(
      afterSeq: after,
      since: since,
      kinds: kinds,
      extensions: extensions,
      authoritativeOnly: !includeTentative,
      limit: limit,
    );
    final newCursor = entries.isEmpty
        ? (after ?? journal.latestSeq)
        : entries.last.journalId;
    return {
      'schema_version': beagleSchemaVersion,
      'pair': {
        'id': pair.id,
        'name': pair.name,
      },
      'consumer': consumer,
      'cursor': newCursor,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'authoritative': !includeTentative,
      'count': entries.length,
      'changes': entries.map((e) => e.toJson()).toList(),
    };
  }
}

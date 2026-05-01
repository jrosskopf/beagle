import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// Persisted run-time state per pair: last-sync metadata, pending follow-up
/// flag, accumulated counters. Stored as a single JSON document so it survives
/// app restarts.
class PairState {
  PairState({
    required this.pairId,
    this.lastSyncRun,
    this.lastSuccessfulRun,
    this.lifecycle = PairLifecycleState.idle,
    this.lastWatcherEventAt,
    this.unackedAuthoritativeCount = 0,
  });

  final String pairId;
  SyncRun? lastSyncRun;
  SyncRun? lastSuccessfulRun;
  PairLifecycleState lifecycle;
  DateTime? lastWatcherEventAt;
  int unackedAuthoritativeCount;

  Map<String, Object?> toJson() => {
        'pair_id': pairId,
        'last_sync_run': lastSyncRun?.toJson(),
        'last_successful_run': lastSuccessfulRun?.toJson(),
        'lifecycle': lifecycle.name,
        'last_watcher_event_at': lastWatcherEventAt?.toUtc().toIso8601String(),
        'unacked_authoritative_count': unackedAuthoritativeCount,
      };

  factory PairState.fromJson(Map<String, Object?> j) => PairState(
        pairId: j['pair_id']! as String,
        lastSyncRun: j['last_sync_run'] == null
            ? null
            : SyncRun.fromJson(_asMap(j['last_sync_run'])),
        lastSuccessfulRun: j['last_successful_run'] == null
            ? null
            : SyncRun.fromJson(_asMap(j['last_successful_run'])),
        lifecycle: PairLifecycleState.values.firstWhere(
          (s) => s.name == j['lifecycle'],
          orElse: () => PairLifecycleState.idle,
        ),
        lastWatcherEventAt: j['last_watcher_event_at'] == null
            ? null
            : DateTime.parse(j['last_watcher_event_at']! as String),
        unackedAuthoritativeCount:
            (j['unacked_authoritative_count'] as num?)?.toInt() ?? 0,
      );
}

class StateStore {
  StateStore(this.filePath);
  final String filePath;

  Future<Map<String, PairState>> load() async {
    final f = File(filePath);
    if (!await f.exists()) return {};
    final raw = await f.readAsString();
    if (raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) =>
        MapEntry(k, PairState.fromJson(_asMap(v))));
  }

  Future<void> save(Map<String, PairState> states) async {
    final tmp = File('$filePath.tmp');
    final body = const JsonEncoder.withIndent('  ').convert({
      for (final e in states.entries) e.key: e.value.toJson(),
    });
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(filePath);
  }
}

Map<String, Object?> _asMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  throw ArgumentError('Expected map, got $v');
}

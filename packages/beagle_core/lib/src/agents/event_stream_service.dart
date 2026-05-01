import 'dart:async';

import '../models.dart';
import '../schema.dart';

/// Bridges live engine streams to the JSONL output that
/// `drive-beagle watch-events` emits.
class EventStreamService {
  EventStreamService({required this.events});
  final Stream<WatcherEvent> events;

  /// Yield NDJSON-ready maps; CLI encodes them.
  Stream<Map<String, Object?>> jsonl({String? pairId}) {
    return events
        .where((e) => pairId == null || e.pairId == pairId)
        .map((e) => {
              'schema_version': beagleSchemaVersion,
              'authoritative': false,
              ...e.toJson(),
            });
  }
}

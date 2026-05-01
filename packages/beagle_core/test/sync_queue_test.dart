import 'dart:async';

import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  group('SyncQueue', () {
    test('serializes and coalesces follow-ups', () async {
      final running = <SyncTrigger>[];
      final completer = Completer<void>();

      final q = SyncQueue(runner: (trigger) async {
        running.add(trigger);
        if (running.length == 1) {
          // Hold the first run open until we've enqueued more.
          await completer.future;
        }
      });

      final t1 = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final futureA = q.enqueue(SyncTrigger(reason: SyncTriggerReason.watcher, requestedAt: t1));
      // Now in flight; enqueue 5 more.
      final futures = <Future<void>>[
        for (var i = 0; i < 5; i++)
          q.enqueue(SyncTrigger(
              reason: SyncTriggerReason.watcher, requestedAt: t1.add(Duration(seconds: i)))),
      ];
      // Let the first run finish.
      completer.complete();
      await futureA;
      await Future.wait(futures);
      // The 5 follow-ups must collapse into exactly 1 additional run.
      expect(running.length, 2);
    });

    test('manual trigger wins coalesce over watcher', () async {
      final running = <SyncTrigger>[];
      final hold = Completer<void>();
      final q = SyncQueue(runner: (trigger) async {
        running.add(trigger);
        if (running.length == 1) await hold.future;
      });

      final now = DateTime.utc(2026, 1, 1);
      final f1 = q.enqueue(SyncTrigger(reason: SyncTriggerReason.watcher, requestedAt: now));
      final f2 = q.enqueue(SyncTrigger(reason: SyncTriggerReason.watcher, requestedAt: now));
      final f3 = q.enqueue(SyncTrigger(reason: SyncTriggerReason.manual, requestedAt: now));
      hold.complete();
      await Future.wait([f1, f2, f3]);
      expect(running.length, 2);
      expect(running.last.reason, SyncTriggerReason.manual);
    });
  });
}

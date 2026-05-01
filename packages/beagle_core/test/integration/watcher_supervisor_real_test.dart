@Tags(['integration'])
@TestOn('linux')
library;

import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late SyncPair pair;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('beagle-sup-');
    pair = SyncPair(
      id: 'p1',
      name: 'p1',
      localPath: tmp.path,
      remoteName: 'localtest',
      remotePath: '',
      mode: SyncMode.dryRun,
    );
    StructuredLogger.memory();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('emits running health and forwards events from the real watcher',
      () async {
    final sup = WatcherSupervisor(
      pair: pair,
      backendFactory: () =>
          InotifywaitBackend(runner: const RealProcessRunner()),
    );
    final events = <WatcherEvent>[];
    final healths = <WatcherHealth>[];
    final evSub = sup.events.listen(events.add);
    final hSub = sup.health.listen(healths.add);
    addTearDown(() async {
      await evSub.cancel();
      await hSub.cancel();
      await sup.stop();
    });

    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(healths.any((h) => h.state == WatcherHealthState.running), isTrue);

    await File(p.join(tmp.path, 'first.md')).writeAsString('a');
    final start = DateTime.now();
    while (events.isEmpty &&
        DateTime.now().difference(start).inSeconds < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(events, isNotEmpty);
  });

  test('restarts the watcher when its process exits unexpectedly', () async {
    // We need to drive the watcher process to exit. Easiest way: monkey-
    // patch by spawning a backend whose process we kill out-of-band.
    final sup = WatcherSupervisor(
      pair: pair,
      backendFactory: () =>
          InotifywaitBackend(runner: const RealProcessRunner()),
      maxBackoff: const Duration(milliseconds: 200),
    );
    final healths = <WatcherHealth>[];
    final hSub = sup.health.listen(healths.add);
    addTearDown(() async {
      await hSub.cancel();
      await sup.stop();
    });
    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Find the live inotifywait pid for this tmp dir and kill it.
    final pgrep = await Process.run('pgrep', ['-af', 'inotifywait']);
    final lines = (pgrep.stdout as String).split('\n').where(
        (l) => l.contains(tmp.path));
    expect(lines, isNotEmpty);
    final pid = int.parse(lines.first.split(' ').first);
    Process.killPid(pid, ProcessSignal.sigterm);

    // Wait for a restart-cycle health update.
    final start = DateTime.now();
    while (!healths.any((h) => h.state == WatcherHealthState.restarting) &&
        DateTime.now().difference(start).inSeconds < 4) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(healths.any((h) => h.state == WatcherHealthState.restarting),
        isTrue,
        reason: 'no `restarting` health update observed; '
            'states: ${healths.map((h) => h.state).toList()}');
  });
}

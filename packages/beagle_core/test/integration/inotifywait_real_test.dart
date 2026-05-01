@Tags(['integration'])
@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late SyncPair pair;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('beagle-inotify-');
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

  group('InotifywaitBackend (real binary)', () {
    test('observes a created file in the watched directory', () async {
      final backend = InotifywaitBackend(runner: const RealProcessRunner());
      final events = <WatcherEvent>[];
      final sub = backend.start(pair).listen(events.add);

      // Give inotifywait a moment to attach to the directory.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await File(p.join(tmp.path, 'hello.md')).writeAsString('hi');

      // Wait up to 2s for an event.
      final start = DateTime.now();
      while (events.isEmpty &&
          DateTime.now().difference(start).inSeconds < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      await sub.cancel();
      await backend.stop();

      expect(events, isNotEmpty);
      // We expect at least one event for hello.md.
      final paths = events.map((e) => e.path).toList();
      expect(paths.any((p) => p.endsWith('hello.md')), isTrue,
          reason: 'no event for hello.md; got: $paths');
    });

    test('handles filenames with spaces and unicode', () async {
      final backend = InotifywaitBackend(runner: const RealProcessRunner());
      final events = <WatcherEvent>[];
      final sub = backend.start(pair).listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await File(p.join(tmp.path, 'with space.md')).writeAsString('a');
      await File(p.join(tmp.path, 'éç.txt')).writeAsString('b');

      final start = DateTime.now();
      while (events.length < 2 &&
          DateTime.now().difference(start).inSeconds < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      await sub.cancel();
      await backend.stop();

      final paths = events.map((e) => e.path).toList();
      expect(paths.any((p) => p.endsWith('with space.md')), isTrue,
          reason: 'spaces broken; got: $paths');
      expect(paths.any((p) => p.endsWith('éç.txt')), isTrue,
          reason: 'unicode broken; got: $paths');
    });

    test('respects ignore_hidden filter (no .dotfile event)', () async {
      final hiddenIgnoringPair = pair.copyWith(
        filters: const Filters(
          ignoreHidden: true,
          ignoreVcs: true,
          ignoreNodeModules: true,
          ignoreCommonBuildDirs: true,
        ),
      );

      final backend = InotifywaitBackend(runner: const RealProcessRunner());
      final events = <WatcherEvent>[];
      final sub = backend.start(hiddenIgnoringPair).listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await File(p.join(tmp.path, '.hidden')).writeAsString('h');
      await File(p.join(tmp.path, 'visible.md')).writeAsString('v');

      final start = DateTime.now();
      while (!events.any((e) => e.path.endsWith('visible.md')) &&
          DateTime.now().difference(start).inSeconds < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      await sub.cancel();
      await backend.stop();

      final paths = events.map((e) => e.path).toList();
      expect(paths.any((p) => p.endsWith('visible.md')), isTrue);
      expect(paths.any((p) => p.endsWith('.hidden')), isFalse,
          reason: '.hidden should be filtered; got: $paths');
    });
  });
}

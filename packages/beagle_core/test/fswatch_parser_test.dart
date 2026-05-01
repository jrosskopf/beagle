import 'package:beagle_core/beagle_core.dart';
import 'package:beagle_core/src/watcher/fswatch_backend.dart';
import 'package:test/test.dart';

const _pair = SyncPair(
  id: 'p1',
  name: 'p1',
  localPath: '/tmp/p1',
  remoteName: 'gdrive',
  remotePath: 'p1',
  mode: SyncMode.bidirectional,
);

void main() {
  group('FswatchBackend.parseRecord', () {
    test('plain modify', () {
      final ev = FswatchBackend.parseRecord(
        '/tmp/p1/foo.md Updated,IsFile',
        _pair,
      );
      expect(ev, isNotNull);
      expect(ev!.path, '/tmp/p1/foo.md');
      expect(ev.kind, WatcherKind.modified);
      expect(ev.backend, 'fswatch');
    });

    test('created flag', () {
      final ev = FswatchBackend.parseRecord(
        '/tmp/p1/new.md Created,IsFile',
        _pair,
      );
      expect(ev!.kind, WatcherKind.created);
    });

    test('removed flag', () {
      final ev = FswatchBackend.parseRecord(
        '/tmp/p1/gone.md Removed,IsFile',
        _pair,
      );
      expect(ev!.kind, WatcherKind.deleted);
    });

    test('renamed flag', () {
      final ev = FswatchBackend.parseRecord(
        '/tmp/p1/x.md Renamed,IsFile',
        _pair,
      );
      expect(ev!.kind, WatcherKind.moved);
    });

    test('path with spaces preserved', () {
      final ev = FswatchBackend.parseRecord(
        '/tmp/p1/with space.md Updated,IsFile',
        _pair,
      );
      expect(ev!.path, '/tmp/p1/with space.md');
    });
  });
}

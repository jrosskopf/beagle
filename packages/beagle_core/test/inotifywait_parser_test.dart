import 'package:beagle_core/beagle_core.dart';
import 'package:beagle_core/src/watcher/inotifywait_backend.dart';
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
  group('InotifywaitBackend.parseLine', () {
    test('plain line', () {
      final ev = InotifywaitBackend.parseLine('/tmp/p1/,MODIFY,foo.md', _pair);
      expect(ev, isNotNull);
      expect(ev!.kind, WatcherKind.modified);
      expect(ev.path, endsWith('/tmp/p1/foo.md'));
      expect(ev.backend, 'inotifywait');
    });

    test('multi-event list', () {
      final ev =
          InotifywaitBackend.parseLine('/tmp/p1/,CREATE,ISDIR,sub', _pair);
      expect(ev, isNotNull);
      expect(ev!.kind, WatcherKind.created);
    });

    test('quoted filename with comma', () {
      final ev = InotifywaitBackend.parseLine(
        '"/tmp/p1/sub, dir/",MODIFY,"weird, name.md"',
        _pair,
      );
      expect(ev, isNotNull);
      expect(ev!.path, '/tmp/p1/sub, dir/weird, name.md');
    });

    test('quoted filename with embedded quotes (RFC4180 doubled)', () {
      final ev = InotifywaitBackend.parseLine(
        '/tmp/p1/,MODIFY,"a""b"".md"',
        _pair,
      );
      expect(ev, isNotNull);
      expect(ev!.path, '/tmp/p1/a"b".md');
    });

    test('move events classified as moved', () {
      final ev = InotifywaitBackend.parseLine(
        '/tmp/p1/,MOVED_FROM,old.md',
        _pair,
      );
      expect(ev!.kind, WatcherKind.moved);
    });

    test('delete events classified', () {
      final ev = InotifywaitBackend.parseLine(
        '/tmp/p1/,DELETE,gone.md',
        _pair,
      );
      expect(ev!.kind, WatcherKind.deleted);
    });

    test('empty line returns null', () {
      expect(InotifywaitBackend.parseLine('', _pair), isNull);
    });

    test('garbage line tolerated', () {
      // A single field is malformed; parser must not throw.
      expect(InotifywaitBackend.parseLine('totally-not-csv', _pair), isNull);
    });
  });
}

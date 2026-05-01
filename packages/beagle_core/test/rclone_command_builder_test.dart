import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

const _pair = SyncPair(
  id: 'p1',
  name: 'memory',
  localPath: '/home/u/memory',
  remoteName: 'gdrive',
  remotePath: 'memory',
  mode: SyncMode.bidirectional,
  bootstrapped: true,
);

void main() {
  group('RcloneCommandBuilder', () {
    const b = RcloneCommandBuilder();

    test('mirrorFromRemote produces expected vector', () {
      final c = b.mirrorFromRemote(_pair, filterFromPath: '/tmp/f.txt');
      expect(c.executable, 'rclone');
      expect(c.arguments, containsAllInOrder(['sync', 'gdrive:memory', '/home/u/memory']));
      expect(c.arguments, contains('--fix-case'));
      expect(c.arguments, contains('--no-slow-hash'));
      expect(c.arguments, contains('--drive-skip-gdocs'));
      expect(c.arguments, contains('--use-json-log'));
      expect(c.arguments, contains('--filter-from'));
      expect(c.arguments, contains('/tmp/f.txt'));
    });

    test('pushToRemote orders args local→remote', () {
      final c = b.pushToRemote(_pair);
      final i = c.arguments.indexOf('sync');
      expect(c.arguments[i + 1], '/home/u/memory');
      expect(c.arguments[i + 2], 'gdrive:memory');
    });

    test('bisync resync emits --resync', () {
      final c = b.bisyncResync(_pair, workdir: '/state/p1');
      expect(c.arguments, contains('--resync'));
      expect(c.arguments, contains('--workdir'));
      expect(c.arguments, contains('/state/p1'));
    });

    test('bisync default does not emit --resync', () {
      final c = b.bisync(_pair, workdir: '/state/p1');
      expect(c.arguments, isNot(contains('--resync')));
      expect(c.arguments, contains('--resilient'));
    });

    test('dry-run flag is passed through', () {
      final c = b.bisync(_pair, dryRun: true);
      expect(c.arguments, contains('--dry-run'));
    });

    test('conflict policies map to rclone flags', () {
      final newer = b.bisync(
        _pair.copyWith(conflictPolicy: ConflictPolicy.newerWins),
      );
      expect(newer.arguments, contains('--conflict-resolve=newer'));
      final remote = b.bisync(
        _pair.copyWith(conflictPolicy: ConflictPolicy.remoteWins),
      );
      expect(remote.arguments, contains('--conflict-resolve=path2'));
      final local = b.bisync(
        _pair.copyWith(conflictPolicy: ConflictPolicy.localWins),
      );
      expect(local.arguments, contains('--conflict-resolve=path1'));
      final both = b.bisync(
        _pair.copyWith(conflictPolicy: ConflictPolicy.keepBothSuffix),
      );
      expect(both.arguments, contains('--conflict-resolve=none'));
      expect(both.arguments, contains('--conflict-suffix=.local,.remote'));
    });
  });
}

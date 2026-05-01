import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  group('SnapshotDiffer', () {
    final t = DateTime.utc(2026, 1, 1, 0, 0, 0);
    SnapshotEntry e(String path, {int size = 100, DateTime? modtime, String? hash}) =>
        SnapshotEntry(path: path, size: size, modtime: modtime ?? t, hash: hash);

    test('classifies created/modified/deleted', () {
      final before = Snapshot(
        pairId: 'p1', takenAt: t, side: ChangeSide.local,
        entries: [e('keep.md'), e('mod.md', size: 100), e('gone.md')],
      );
      final after = Snapshot(
        pairId: 'p1', takenAt: t, side: ChangeSide.local,
        entries: [e('keep.md'), e('mod.md', size: 200), e('new.md')],
      );
      final d = SnapshotDiffer().diff(before, after);
      expect(d.created.map((e) => e.path).toList(), ['new.md']);
      expect(d.deleted.map((e) => e.path).toList(), ['gone.md']);
      expect(d.modified.map((e) => e.path).toList(), ['mod.md']);
      expect(d.moved, isEmpty);
    });

    test('detects moves by hash equality', () {
      final before = Snapshot(
        pairId: 'p1', takenAt: t, side: ChangeSide.local,
        entries: [e('old/path.md', size: 100, hash: 'abc')],
      );
      final after = Snapshot(
        pairId: 'p1', takenAt: t, side: ChangeSide.local,
        entries: [e('new/path.md', size: 100, hash: 'abc')],
      );
      final d = SnapshotDiffer().diff(before, after);
      expect(d.moved, hasLength(1));
      expect(d.moved.single.from.path, 'old/path.md');
      expect(d.moved.single.to.path, 'new/path.md');
      expect(d.created, isEmpty);
      expect(d.deleted, isEmpty);
    });

    test('falls back to size+modtime when no hash', () {
      final before = Snapshot(
        pairId: 'p1', takenAt: t, side: ChangeSide.local,
        entries: [e('old.md', size: 50, modtime: t)],
      );
      final after = Snapshot(
        pairId: 'p1', takenAt: t, side: ChangeSide.local,
        entries: [e('new.md', size: 50, modtime: t.add(const Duration(seconds: 1)))],
      );
      final d = SnapshotDiffer().diff(before, after);
      expect(d.moved, hasLength(1));
    });
  });
}

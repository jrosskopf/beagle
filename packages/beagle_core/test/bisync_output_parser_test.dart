import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  test('BisyncOutputParser handles representative bisync output', () {
    const stdout = '''
Synching Path1 "/local" with Path2 "gdrive:remote"
  - Path1    File was deleted: foo/old.md
  - Path2    File was created: foo/fresh.md
  - Path1    File is newer: foo/edit.md
  - Path1    File was renamed from 'foo/a.md' to 'foo/b.md'
Bisync successful
''';
    final changes = BisyncOutputParser().parse(stdout);
    expect(changes, hasLength(4));
    expect(
        changes.map((c) => '${c.kind.wire}/${c.side.wire}/${c.path}').toList(),
        contains('deleted/local/foo/old.md'));
    final move = changes.firstWhere((c) => c.kind == ChangeKind.moved);
    expect(move.previousPath, 'foo/a.md');
    expect(move.path, 'foo/b.md');
  });
}

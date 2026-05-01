import '../models.dart';

/// Parsed line from rclone bisync's stdout/stderr that describes an applied
/// change. We keep the parser tolerant — bisync's text output is not a stable
/// API and varies between versions, so we extract what we can and fall back
/// to snapshot diff for authoritative numbers.
class BisyncChange {
  BisyncChange({
    required this.kind,
    required this.side,
    required this.path,
    this.previousPath,
  });
  final ChangeKind kind;
  final ChangeSide side;
  final String path;
  final String? previousPath;
}

class BisyncOutputParser {
  /// Best-effort line parser. Recognized line shapes (rclone v1.65–1.69):
  ///   - "  - Path1    File was deleted: foo/bar.md"
  ///   - "  - Path2    File was created: foo/bar.md"
  ///   - "  - Path1    File is newer: foo/bar.md"
  ///   - "  - Path1    File was renamed from 'a' to 'b'"
  /// Anything we don't recognize is ignored — the snapshot diff catches it.
  List<BisyncChange> parse(String stdout) {
    final out = <BisyncChange>[];
    for (final raw in stdout.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = _re.firstMatch(line);
      if (m == null) continue;
      final sideStr = m.group(1)!;
      final verb = m.group(2)!;
      final tail = m.group(3)!;
      final side = sideStr == 'Path1' ? ChangeSide.local : ChangeSide.remote;
      final kind = switch (verb) {
        'was deleted' => ChangeKind.deleted,
        'was created' => ChangeKind.created,
        'is newer' || 'is older' => ChangeKind.modified,
        'was renamed from' => ChangeKind.moved,
        _ => null,
      };
      if (kind == null) continue;
      if (kind == ChangeKind.moved) {
        final mv = _renameRe.firstMatch(tail);
        if (mv != null) {
          out.add(BisyncChange(
            kind: kind,
            side: side,
            path: mv.group(2)!,
            previousPath: mv.group(1)!,
          ));
        }
      } else {
        out.add(BisyncChange(kind: kind, side: side, path: tail));
      }
    }
    return out;
  }

  static final RegExp _re = RegExp(
    r'(Path1|Path2)\s+File\s+(was deleted|was created|is newer|is older|was renamed from)[:\s]+(.*)$',
  );
  static final RegExp _renameRe =
      RegExp(r"'([^']+)'\s+to\s+'([^']+)'");
}

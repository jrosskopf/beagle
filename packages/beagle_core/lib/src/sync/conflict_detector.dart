import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

/// Surface conflict files written by rclone bisync's `keep both` policy.
/// We don't actually resolve conflicts in MVP — we just count them so the UI
/// can show a badge, and we surface them in the journal as `kind: conflict`.
class ConflictDetector {
  /// Scan [pair.localPath] for files matching rclone's conflict suffix
  /// pattern (`.local`, `.remote`, or `.conflict`). Returns relative paths.
  Future<List<String>> scan(SyncPair pair) async {
    final root = Directory(pair.localPath);
    if (!await root.exists()) return const [];
    final out = <String>[];
    await for (final ent in root.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final name = p.basename(ent.path);
      if (_re.hasMatch(name)) {
        out.add(p.relative(ent.path, from: root.path));
      }
    }
    out.sort();
    return out;
  }

  // Match suffixes like `.local`, `.local.1`, `.remote`, `.conflict.1`, etc.
  static final RegExp _re = RegExp(r'\.(local|remote|conflict)(\.\d+)?$');
}

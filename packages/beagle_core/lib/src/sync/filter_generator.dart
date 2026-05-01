import 'dart:io';

import '../models.dart';

/// Generates an rclone `--filter-from` file from a [Filters] spec.
///
/// rclone filter syntax:
///   `+ pattern`  include
///   `- pattern`  exclude
/// Rules are evaluated top-down; the first match wins. We layer rules so
/// excludes come first (hidden / VCS / build dirs / user globs), then includes
/// for whitelisted extensions, then a final `- *` if the user pinned an
/// allowlist.
class FilterFile {
  const FilterFile(this.lines);
  final List<String> lines;

  String render() => '${lines.join('\n')}\n';
}

class FilterGenerator {
  /// Build a deterministic filter file. Determinism matters — agents and tests
  /// rely on byte-stable output.
  FilterFile generate(Filters f) {
    final lines = <String>[];

    void exclude(String pattern) => lines.add('- $pattern');
    void include(String pattern) => lines.add('+ $pattern');

    if (f.ignoreHidden) {
      exclude('.*');
      exclude('.*/**');
    }
    if (f.ignoreVcs) {
      exclude('.git/**');
      exclude('.hg/**');
      exclude('.svn/**');
    }
    if (f.ignoreNodeModules) {
      exclude('node_modules/**');
    }
    if (f.ignoreCommonBuildDirs) {
      for (final d in const [
        'build',
        'dist',
        'target',
        '.dart_tool',
        '.gradle',
        '.idea',
        '.vscode',
        '__pycache__',
        '.cache',
      ]) {
        exclude('$d/**');
      }
    }

    // Editor swap / temp files.
    for (final p in const [
      '*~',
      '*.swp',
      '*.swo',
      '*.tmp',
      '.DS_Store',
      'Thumbs.db',
      '*.crdownload',
      '*.part',
    ]) {
      exclude(p);
    }

    for (final g in f.excludeGlobs) {
      exclude(g);
    }

    for (final r in f.customRules) {
      // Allow users to write raw rclone-style rules; require '+' or '-' prefix.
      final t = r.trimRight();
      if (t.isEmpty) continue;
      if (t.startsWith('+ ') || t.startsWith('- ')) {
        lines.add(t);
      } else {
        // Treat as exclude by default for safety.
        exclude(t);
      }
    }

    // Extension allowlist: include matching, exclude everything else.
    if (f.includeExtensions.isNotEmpty) {
      for (final ext in f.includeExtensions) {
        final clean = ext.startsWith('.') ? ext.substring(1) : ext;
        include('*.$clean');
      }
      // Always allow descending into directories so rules below take effect.
      include('**/');
      exclude('*');
    }

    return FilterFile(lines);
  }

  /// Write a filter file atomically. Returns the path written.
  Future<String> writeAtomic(String path, FilterFile file) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(file.render(), flush: true);
    await tmp.rename(path);
    return path;
  }
}

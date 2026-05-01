import 'package:path/path.dart' as p;

/// Normalizes a watcher-emitted path to be relative to a sync pair's local root.
///
/// Returns null if [absolutePath] is not actually inside [root].
String? relativeToRoot(String root, String absolutePath) {
  final n = p.normalize(absolutePath);
  final r = p.normalize(root);
  if (!p.isWithin(r, n) && p.equals(r, n)) return '';
  if (!p.isWithin(r, n)) return null;
  return p.relative(n, from: r);
}

/// Returns the dot-prefixed extension or '' if none.
String extOf(String path) {
  final i = path.lastIndexOf('.');
  if (i <= 0 || i == path.length - 1) return '';
  return path.substring(i);
}

/// Quotes a string for inclusion in a shell command — used purely for the
/// "Copy rclone command" UI feature; never executed via a shell.
String shellQuote(String s) {
  if (s.isEmpty) return "''";
  if (RegExp(r'^[A-Za-z0-9_./@%+\-:=]+$').hasMatch(s)) return s;
  return "'${s.replaceAll("'", "'\\''")}'";
}

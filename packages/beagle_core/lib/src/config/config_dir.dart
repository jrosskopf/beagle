import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves drive-beagle's per-platform config + state directory.
///
/// Linux:  $XDG_CONFIG_HOME/drive-beagle (default ~/.config/drive-beagle)
/// macOS:  ~/Library/Application Support/drive-beagle
class ConfigDir {
  ConfigDir(this.root);

  final Directory root;

  static ConfigDir resolve({String? overrideRoot}) {
    if (overrideRoot != null) return ConfigDir(Directory(overrideRoot));
    final home = _homeDir();
    final base = Platform.isMacOS
        ? p.join(home, 'Library', 'Application Support', 'drive-beagle')
        : p.join(
            Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config'),
            'drive-beagle',
          );
    return ConfigDir(Directory(base));
  }

  Future<void> ensure() async {
    if (!await root.exists()) await root.create(recursive: true);
    for (final sub in const ['logs', 'journal', 'snapshots', 'state']) {
      final d = Directory(p.join(root.path, sub));
      if (!await d.exists()) await d.create(recursive: true);
    }
  }

  String get configFilePath => p.join(root.path, 'config.yaml');
  String get stateFilePath => p.join(root.path, 'state', 'state.json');
  String get cursorFilePath => p.join(root.path, 'cursors.json');
  String get lockFilePath => p.join(root.path, 'drive-beagle.lock');
  String get logsDir => p.join(root.path, 'logs');
  String get journalDir => p.join(root.path, 'journal');
  String get snapshotsDir => p.join(root.path, 'snapshots');

  /// Default IPC socket path; on Linux prefer $XDG_RUNTIME_DIR.
  String defaultIpcSocketPath() {
    if (Platform.isMacOS) {
      return p.join(root.path, 'control.sock');
    }
    final xdg = Platform.environment['XDG_RUNTIME_DIR'];
    if (xdg != null && xdg.isNotEmpty) {
      return p.join(xdg, 'drive-beagle.sock');
    }
    return p.join(root.path, 'control.sock');
  }

  String journalJsonlPath(String pairId) =>
      p.join(journalDir, '$pairId.jsonl');
  String journalDbPath(String pairId) => p.join(journalDir, '$pairId.db');
  String snapshotPath(String pairId, String side, String tag) =>
      p.join(snapshotsDir, '$pairId.$side.$tag.json');
  String filtersFilePath(String pairId) =>
      p.join(root.path, 'state', 'filters.$pairId.txt');
  String bisyncWorkdir(String pairId) =>
      p.join(root.path, 'state', 'bisync.$pairId');
}

String _homeDir() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME environment variable is not set');
  }
  return home;
}

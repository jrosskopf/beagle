import '../models.dart';

/// Pure command-builder for rclone invocations.
///
/// Returns argument vectors suitable for `Process.start` — never builds a
/// shell string. The builder is opinionated for drive-beagle's use case
/// (markdown/code mirrors, many small files) but each preset can be tweaked
/// via the [RcloneFlagPreset] argument.
class RcloneFlagPreset {
  const RcloneFlagPreset({
    this.skipGdocs = true,
    this.fixCase = true,
    this.resilient = true,
    this.recover = true,
    this.noSlowHash = true,
    this.compare = 'size,modtime',
    this.transfers = 4,
    this.checkers = 8,
    this.retries = 3,
    this.lowLevelRetries = 5,
    this.statsOneLine = true,
    this.useJsonLog = true,
    this.backupSuffix = '.beagle.bak',
  });

  final bool skipGdocs;
  final bool fixCase;
  final bool resilient;
  final bool recover;
  final bool noSlowHash;
  final String compare;
  final int transfers;
  final int checkers;
  final int retries;
  final int lowLevelRetries;
  final bool statsOneLine;
  final bool useJsonLog;
  final String backupSuffix;

  static const developerDefault = RcloneFlagPreset();
}

class RcloneCommand {
  const RcloneCommand(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;
  List<String> get argv => [executable, ...arguments];
}

class RcloneCommandBuilder {
  const RcloneCommandBuilder({
    this.executable = 'rclone',
    this.preset = RcloneFlagPreset.developerDefault,
  });

  final String executable;
  final RcloneFlagPreset preset;

  List<String> _commonFlags({String? filterFromPath}) {
    final args = <String>[
      if (preset.useJsonLog) '--use-json-log',
      if (preset.statsOneLine) '--stats-one-line',
      '--stats=10s',
      '--transfers=${preset.transfers}',
      '--checkers=${preset.checkers}',
      '--retries=${preset.retries}',
      '--low-level-retries=${preset.lowLevelRetries}',
      if (filterFromPath != null) ...['--filter-from', filterFromPath],
    ];
    return args;
  }

  List<String> _driveFlags() => [
        if (preset.skipGdocs) '--drive-skip-gdocs',
      ];

  RcloneCommand version() => RcloneCommand(executable, const ['version']);

  RcloneCommand listRemotes() =>
      RcloneCommand(executable, const ['listremotes']);

  RcloneCommand about(String remoteName) =>
      RcloneCommand(executable, ['about', '$remoteName:']);

  /// `rclone lsjson --recursive --files-only <remote>:<path>` — used for
  /// remote snapshots. Caller may add `--no-modtime` etc. via preset flags.
  RcloneCommand lsjson(SyncPair pair, {bool dirs = false}) {
    return RcloneCommand(executable, [
      'lsjson',
      '--recursive',
      if (!dirs) '--files-only',
      ..._driveFlags(),
      pair.rcloneRemoteSpec,
    ]);
  }

  RcloneCommand lsjsonLocal(String localPath, {bool dirs = false}) {
    return RcloneCommand(executable, [
      'lsjson',
      '--recursive',
      if (!dirs) '--files-only',
      localPath,
    ]);
  }

  RcloneCommand lsf(SyncPair pair) {
    return RcloneCommand(executable, [
      'lsf',
      '--recursive',
      '--files-only',
      '--csv',
      '--format=pst',
      ..._driveFlags(),
      pair.rcloneRemoteSpec,
    ]);
  }

  /// One-way mirror from remote to local.
  RcloneCommand mirrorFromRemote(
    SyncPair pair, {
    String? filterFromPath,
    bool dryRun = false,
  }) {
    return RcloneCommand(executable, [
      'sync',
      pair.rcloneRemoteSpec,
      pair.localPath,
      if (preset.fixCase) '--fix-case',
      if (preset.compare.isNotEmpty) ...['--compare', preset.compare],
      if (preset.noSlowHash) '--no-slow-hash',
      '--create-empty-src-dirs',
      if (dryRun) '--dry-run',
      ..._driveFlags(),
      ..._commonFlags(filterFromPath: filterFromPath),
    ]);
  }

  /// One-way upload from local to remote.
  RcloneCommand pushToRemote(
    SyncPair pair, {
    String? filterFromPath,
    bool dryRun = false,
  }) {
    return RcloneCommand(executable, [
      'sync',
      pair.localPath,
      pair.rcloneRemoteSpec,
      if (preset.fixCase) '--fix-case',
      if (preset.compare.isNotEmpty) ...['--compare', preset.compare],
      if (preset.noSlowHash) '--no-slow-hash',
      '--create-empty-src-dirs',
      if (dryRun) '--dry-run',
      ..._driveFlags(),
      ..._commonFlags(filterFromPath: filterFromPath),
    ]);
  }

  /// Initial bisync resync — only runs explicitly via UI/CLI.
  RcloneCommand bisyncResync(
    SyncPair pair, {
    String? filterFromPath,
    String? workdir,
    bool dryRun = false,
  }) {
    return RcloneCommand(executable, [
      'bisync',
      pair.localPath,
      pair.rcloneRemoteSpec,
      '--resync',
      if (workdir != null) ...['--workdir', workdir],
      if (preset.resilient) '--resilient',
      if (preset.recover) '--recover',
      if (preset.fixCase) '--fix-case',
      '--create-empty-src-dirs',
      if (dryRun) '--dry-run',
      ..._driveFlags(),
      ..._commonFlags(filterFromPath: filterFromPath),
    ]);
  }

  RcloneCommand bisync(
    SyncPair pair, {
    String? filterFromPath,
    String? workdir,
    bool dryRun = false,
  }) {
    final conflict = _conflictArgs(pair.conflictPolicy);
    return RcloneCommand(executable, [
      'bisync',
      pair.localPath,
      pair.rcloneRemoteSpec,
      if (workdir != null) ...['--workdir', workdir],
      if (preset.resilient) '--resilient',
      if (preset.recover) '--recover',
      if (preset.fixCase) '--fix-case',
      '--create-empty-src-dirs',
      ...conflict,
      if (dryRun) '--dry-run',
      ..._driveFlags(),
      ..._commonFlags(filterFromPath: filterFromPath),
    ]);
  }

  /// Translate our policy enum into rclone bisync flags.
  ///   newer    -> --conflict-resolve=newer
  ///   remote   -> --conflict-resolve=path2
  ///   local    -> --conflict-resolve=path1
  ///   keepBoth -> --conflict-suffix=.local,.remote --conflict-resolve=none
  List<String> _conflictArgs(ConflictPolicy p) {
    switch (p) {
      case ConflictPolicy.newerWins:
        return ['--conflict-resolve=newer'];
      case ConflictPolicy.remoteWins:
        return ['--conflict-resolve=path2'];
      case ConflictPolicy.localWins:
        return ['--conflict-resolve=path1'];
      case ConflictPolicy.keepBothSuffix:
        return [
          '--conflict-resolve=none',
          '--conflict-suffix=.local,.remote',
          '--conflict-loser=num',
          '--backup-dir1=${defaultBackupDir()}',
        ];
    }
  }

  /// Default per-pair backup dir name used when `keepBothSuffix` is in effect.
  /// The engine resolves this against the pair's local root.
  String defaultBackupDir() => '.beagle-backups';
}

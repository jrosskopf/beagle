import 'package:meta/meta.dart';

/// Sync direction / engine choice for a pair.
enum SyncMode {
  mirrorFromRemote('mirror_from_remote'),
  toRemote('to_remote'),
  bidirectional('bidirectional'),
  dryRun('dry_run');

  const SyncMode(this.wire);
  final String wire;

  static SyncMode fromWire(String s) =>
      SyncMode.values.firstWhere((m) => m.wire == s,
          orElse: () => throw ArgumentError('Unknown SyncMode: $s'));
}

enum ConflictPolicy {
  newerWins('newer_wins'),
  remoteWins('remote_wins'),
  localWins('local_wins'),
  keepBothSuffix('keep_both_suffix');

  const ConflictPolicy(this.wire);
  final String wire;

  static ConflictPolicy fromWire(String s) =>
      ConflictPolicy.values.firstWhere((p) => p.wire == s,
          orElse: () => throw ArgumentError('Unknown ConflictPolicy: $s'));
}

enum ChangeKind {
  created('created'),
  modified('modified'),
  deleted('deleted'),
  moved('moved'),
  conflict('conflict'),
  metadata('metadata');

  const ChangeKind(this.wire);
  final String wire;

  static ChangeKind fromWire(String s) =>
      ChangeKind.values.firstWhere((k) => k.wire == s,
          orElse: () => throw ArgumentError('Unknown ChangeKind: $s'));
}

enum ChangeSide {
  local('local'),
  remote('remote'),
  both('both'),
  unknown('unknown');

  const ChangeSide(this.wire);
  final String wire;

  static ChangeSide fromWire(String s) =>
      ChangeSide.values.firstWhere((s2) => s2.wire == s,
          orElse: () => throw ArgumentError('Unknown ChangeSide: $s'));
}

enum ChangeSource {
  watcher('watcher'),
  sync('sync'),
  reconcile('reconcile'),
  manual('manual'),
  bootstrap('bootstrap');

  const ChangeSource(this.wire);
  final String wire;

  static ChangeSource fromWire(String s) =>
      ChangeSource.values.firstWhere((s2) => s2.wire == s,
          orElse: () => throw ArgumentError('Unknown ChangeSource: $s'));
}

enum SyncStatus {
  detected('detected'),
  planned('planned'),
  applied('applied'),
  failed('failed'),
  skipped('skipped');

  const SyncStatus(this.wire);
  final String wire;

  static SyncStatus fromWire(String s) =>
      SyncStatus.values.firstWhere((s2) => s2.wire == s,
          orElse: () => throw ArgumentError('Unknown SyncStatus: $s'));
}

enum WatcherKind {
  created('created'),
  modified('modified'),
  deleted('deleted'),
  moved('moved');

  const WatcherKind(this.wire);
  final String wire;
}

enum PairLifecycleState {
  idle,
  watching,
  pending,
  syncing,
  paused,
  warning,
  error,
}

enum SyncRunState {
  queued,
  started,
  snapshottingPre,
  syncing,
  snapshottingPost,
  journaling,
  succeeded,
  failed,
  partial;

  String get wire => switch (this) {
        SyncRunState.queued => 'queued',
        SyncRunState.started => 'started',
        SyncRunState.snapshottingPre => 'snapshotting_pre',
        SyncRunState.syncing => 'syncing',
        SyncRunState.snapshottingPost => 'snapshotting_post',
        SyncRunState.journaling => 'journaling',
        SyncRunState.succeeded => 'succeeded',
        SyncRunState.failed => 'failed',
        SyncRunState.partial => 'partial',
      };
}

@immutable
class Filters {
  const Filters({
    this.includeExtensions = const [],
    this.excludeGlobs = const [],
    this.ignoreHidden = true,
    this.ignoreVcs = true,
    this.ignoreNodeModules = true,
    this.ignoreCommonBuildDirs = true,
    this.customRules = const [],
  });

  final List<String> includeExtensions;
  final List<String> excludeGlobs;
  final bool ignoreHidden;
  final bool ignoreVcs;
  final bool ignoreNodeModules;
  final bool ignoreCommonBuildDirs;
  final List<String> customRules;

  Map<String, Object?> toJson() => {
        'include_extensions': includeExtensions,
        'exclude_globs': excludeGlobs,
        'ignore_hidden': ignoreHidden,
        'ignore_vcs': ignoreVcs,
        'ignore_node_modules': ignoreNodeModules,
        'ignore_common_build_dirs': ignoreCommonBuildDirs,
        'custom_rules': customRules,
      };

  factory Filters.fromJson(Map<String, Object?> j) => Filters(
        includeExtensions: _listOfString(j['include_extensions']),
        excludeGlobs: _listOfString(j['exclude_globs']),
        ignoreHidden: (j['ignore_hidden'] ?? true) as bool,
        ignoreVcs: (j['ignore_vcs'] ?? true) as bool,
        ignoreNodeModules: (j['ignore_node_modules'] ?? true) as bool,
        ignoreCommonBuildDirs: (j['ignore_common_build_dirs'] ?? true) as bool,
        customRules: _listOfString(j['custom_rules']),
      );

  static const developerDefault = Filters(
    includeExtensions: ['md', 'txt', 'json', 'yaml', 'yml'],
    excludeGlobs: [],
    ignoreHidden: true,
    ignoreVcs: true,
    ignoreNodeModules: true,
    ignoreCommonBuildDirs: true,
  );
}

@immutable
class SizePolicy {
  const SizePolicy({this.maxBytes});
  final int? maxBytes;
  Map<String, Object?> toJson() => {'max_bytes': maxBytes};
  factory SizePolicy.fromJson(Map<String, Object?> j) =>
      SizePolicy(maxBytes: (j['max_bytes'] as num?)?.toInt());
}

@immutable
class SyncPair {
  const SyncPair({
    required this.id,
    required this.name,
    required this.localPath,
    required this.remoteName,
    required this.remotePath,
    required this.mode,
    this.filters = Filters.developerDefault,
    this.sizePolicy = const SizePolicy(),
    this.conflictPolicy = ConflictPolicy.keepBothSuffix,
    this.debounceMs = 4000,
    this.reconcileEverySeconds = 600,
    this.enabled = true,
    this.bootstrapped = false,
  });

  final String id;
  final String name;
  final String localPath;
  final String remoteName;
  final String remotePath;
  final SyncMode mode;
  final Filters filters;
  final SizePolicy sizePolicy;
  final ConflictPolicy conflictPolicy;
  final int debounceMs;
  final int reconcileEverySeconds;
  final bool enabled;
  final bool bootstrapped;

  String get rcloneRemoteSpec =>
      remotePath.isEmpty ? '$remoteName:' : '$remoteName:$remotePath';

  SyncPair copyWith({
    String? name,
    SyncMode? mode,
    Filters? filters,
    SizePolicy? sizePolicy,
    ConflictPolicy? conflictPolicy,
    int? debounceMs,
    int? reconcileEverySeconds,
    bool? enabled,
    bool? bootstrapped,
  }) =>
      SyncPair(
        id: id,
        name: name ?? this.name,
        localPath: localPath,
        remoteName: remoteName,
        remotePath: remotePath,
        mode: mode ?? this.mode,
        filters: filters ?? this.filters,
        sizePolicy: sizePolicy ?? this.sizePolicy,
        conflictPolicy: conflictPolicy ?? this.conflictPolicy,
        debounceMs: debounceMs ?? this.debounceMs,
        reconcileEverySeconds:
            reconcileEverySeconds ?? this.reconcileEverySeconds,
        enabled: enabled ?? this.enabled,
        bootstrapped: bootstrapped ?? this.bootstrapped,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'local_path': localPath,
        'remote_name': remoteName,
        'remote_path': remotePath,
        'mode': mode.wire,
        'filters': filters.toJson(),
        'size_policy': sizePolicy.toJson(),
        'conflict_policy': conflictPolicy.wire,
        'debounce_ms': debounceMs,
        'reconcile_every_seconds': reconcileEverySeconds,
        'enabled': enabled,
        'bootstrapped': bootstrapped,
      };

  factory SyncPair.fromJson(Map<String, Object?> j) => SyncPair(
        id: j['id']! as String,
        name: j['name']! as String,
        localPath: j['local_path']! as String,
        remoteName: j['remote_name']! as String,
        remotePath: (j['remote_path'] ?? '') as String,
        mode: SyncMode.fromWire(j['mode']! as String),
        filters: j['filters'] == null
            ? Filters.developerDefault
            : Filters.fromJson(_asMap(j['filters'])),
        sizePolicy: j['size_policy'] == null
            ? const SizePolicy()
            : SizePolicy.fromJson(_asMap(j['size_policy'])),
        conflictPolicy: j['conflict_policy'] == null
            ? ConflictPolicy.keepBothSuffix
            : ConflictPolicy.fromWire(j['conflict_policy']! as String),
        debounceMs: (j['debounce_ms'] as num?)?.toInt() ?? 4000,
        reconcileEverySeconds:
            (j['reconcile_every_seconds'] as num?)?.toInt() ?? 600,
        enabled: (j['enabled'] ?? true) as bool,
        bootstrapped: (j['bootstrapped'] ?? false) as bool,
      );
}

@immutable
class AppConfig {
  const AppConfig({
    this.configVersion = 1,
    this.globalConcurrency = 1,
    this.logLevel = 'info',
    this.ipcSocketPath,
    this.pairs = const [],
  });

  final int configVersion;
  final int globalConcurrency;
  final String logLevel;
  final String? ipcSocketPath;
  final List<SyncPair> pairs;

  AppConfig copyWith({
    int? globalConcurrency,
    String? logLevel,
    String? ipcSocketPath,
    List<SyncPair>? pairs,
  }) =>
      AppConfig(
        configVersion: configVersion,
        globalConcurrency: globalConcurrency ?? this.globalConcurrency,
        logLevel: logLevel ?? this.logLevel,
        ipcSocketPath: ipcSocketPath ?? this.ipcSocketPath,
        pairs: pairs ?? this.pairs,
      );

  Map<String, Object?> toJson() => {
        'config_version': configVersion,
        'global_concurrency': globalConcurrency,
        'log_level': logLevel,
        if (ipcSocketPath != null) 'ipc_socket_path': ipcSocketPath,
        'pairs': pairs.map((p) => p.toJson()).toList(),
      };

  factory AppConfig.fromJson(Map<String, Object?> j) => AppConfig(
        configVersion: (j['config_version'] as num?)?.toInt() ?? 1,
        globalConcurrency: (j['global_concurrency'] as num?)?.toInt() ?? 1,
        logLevel: (j['log_level'] ?? 'info') as String,
        ipcSocketPath: j['ipc_socket_path'] as String?,
        pairs: ((j['pairs'] as List?) ?? const [])
            .map((e) => SyncPair.fromJson(_asMap(e)))
            .toList(),
      );
}

@immutable
class WatcherEvent {
  const WatcherEvent({
    required this.pairId,
    required this.backend,
    required this.path,
    required this.kind,
    required this.tsUtc,
    this.raw,
  });

  final String pairId;
  final String backend; // 'inotifywait' | 'fswatch'
  final String path;
  final WatcherKind kind;
  final DateTime tsUtc;
  final String? raw;

  Map<String, Object?> toJson() => {
        'pair_id': pairId,
        'backend': backend,
        'path': path,
        'kind': kind.wire,
        'ts_utc': tsUtc.toUtc().toIso8601String(),
        if (raw != null) 'raw': raw,
      };
}

@immutable
class Fingerprint {
  const Fingerprint({
    required this.strategy,
    this.size,
    this.modtime,
    this.hash,
  });

  /// 'size_modtime' or 'sha1' / 'md5' / 'quickxor'.
  final String strategy;
  final int? size;
  final DateTime? modtime;
  final String? hash;

  Map<String, Object?> toJson() => {
        'strategy': strategy,
        if (size != null) 'size': size,
        if (modtime != null) 'modtime': modtime!.toUtc().toIso8601String(),
        if (hash != null) 'hash': hash,
      };

  factory Fingerprint.fromJson(Map<String, Object?> j) => Fingerprint(
        strategy: j['strategy']! as String,
        size: (j['size'] as num?)?.toInt(),
        modtime: j['modtime'] == null
            ? null
            : DateTime.parse(j['modtime']! as String),
        hash: j['hash'] as String?,
      );
}

@immutable
class ChangeEntry {
  const ChangeEntry({
    required this.journalId,
    required this.pairId,
    required this.syncRunId,
    required this.ts,
    required this.source,
    required this.side,
    required this.kind,
    required this.path,
    this.previousPath,
    this.fingerprint,
    required this.syncStatus,
    required this.agentVisibility,
    this.metadata = const {},
  });

  /// Monotonic per-pair sequence id; doubles as the cursor token.
  final int journalId;
  final String pairId;
  final String syncRunId;
  final DateTime ts;
  final ChangeSource source;
  final ChangeSide side;
  final ChangeKind kind;
  final String path;
  final String? previousPath;
  final Fingerprint? fingerprint;
  final SyncStatus syncStatus;
  final bool agentVisibility;
  final Map<String, Object?> metadata;

  bool get authoritative => source != ChangeSource.watcher;

  String get extension {
    final i = path.lastIndexOf('.');
    if (i <= 0 || i == path.length - 1) return '';
    return path.substring(i);
  }

  Map<String, Object?> toJson() => {
        'id': journalId,
        'pair_id': pairId,
        'sync_run_id': syncRunId,
        'timestamp': ts.toUtc().toIso8601String(),
        'source': source.wire,
        'side': side.wire,
        'kind': kind.wire,
        'path': path,
        'previous_path': previousPath,
        'extension': extension,
        if (fingerprint != null) 'fingerprint': fingerprint!.toJson(),
        'sync_status': syncStatus.wire,
        'agent_visibility': agentVisibility,
        'authoritative': authoritative,
        'metadata': metadata,
      };

  factory ChangeEntry.fromJson(Map<String, Object?> j) => ChangeEntry(
        journalId: (j['id']! as num).toInt(),
        pairId: j['pair_id']! as String,
        syncRunId: j['sync_run_id']! as String,
        ts: DateTime.parse(j['timestamp']! as String),
        source: ChangeSource.fromWire(j['source']! as String),
        side: ChangeSide.fromWire(j['side']! as String),
        kind: ChangeKind.fromWire(j['kind']! as String),
        path: j['path']! as String,
        previousPath: j['previous_path'] as String?,
        fingerprint: j['fingerprint'] == null
            ? null
            : Fingerprint.fromJson(_asMap(j['fingerprint'])),
        syncStatus: SyncStatus.fromWire(j['sync_status']! as String),
        agentVisibility: (j['agent_visibility'] ?? true) as bool,
        metadata: j['metadata'] == null
            ? const {}
            : _asMap(j['metadata']),
      );
}

@immutable
class SyncRunCounts {
  const SyncRunCounts({
    this.created = 0,
    this.modified = 0,
    this.deleted = 0,
    this.moved = 0,
    this.conflicts = 0,
  });

  final int created;
  final int modified;
  final int deleted;
  final int moved;
  final int conflicts;

  int get total => created + modified + deleted + moved + conflicts;

  Map<String, Object?> toJson() => {
        'created': created,
        'modified': modified,
        'deleted': deleted,
        'moved': moved,
        'conflicts': conflicts,
        'total': total,
      };

  factory SyncRunCounts.fromJson(Map<String, Object?> j) => SyncRunCounts(
        created: (j['created'] as num?)?.toInt() ?? 0,
        modified: (j['modified'] as num?)?.toInt() ?? 0,
        deleted: (j['deleted'] as num?)?.toInt() ?? 0,
        moved: (j['moved'] as num?)?.toInt() ?? 0,
        conflicts: (j['conflicts'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class SyncRun {
  const SyncRun({
    required this.id,
    required this.pairId,
    required this.startedAt,
    this.endedAt,
    required this.mode,
    required this.trigger,
    this.exitCode,
    this.durationMs,
    this.counts = const SyncRunCounts(),
    this.commandSummary = '',
    this.state = SyncRunState.queued,
    this.errorMessage,
  });

  final String id;
  final String pairId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SyncMode mode;

  /// 'watcher' | 'reconcile' | 'manual' | 'bootstrap'
  final String trigger;

  final int? exitCode;
  final int? durationMs;
  final SyncRunCounts counts;
  final String commandSummary;
  final SyncRunState state;
  final String? errorMessage;

  bool get succeeded => state == SyncRunState.succeeded;

  SyncRun copyWith({
    DateTime? endedAt,
    int? exitCode,
    int? durationMs,
    SyncRunCounts? counts,
    String? commandSummary,
    SyncRunState? state,
    String? errorMessage,
  }) =>
      SyncRun(
        id: id,
        pairId: pairId,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        mode: mode,
        trigger: trigger,
        exitCode: exitCode ?? this.exitCode,
        durationMs: durationMs ?? this.durationMs,
        counts: counts ?? this.counts,
        commandSummary: commandSummary ?? this.commandSummary,
        state: state ?? this.state,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'pair_id': pairId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'mode': mode.wire,
        'trigger': trigger,
        'exit_code': exitCode,
        'duration_ms': durationMs,
        'counts': counts.toJson(),
        'command_summary': commandSummary,
        'state': state.wire,
        if (errorMessage != null) 'error_message': errorMessage,
      };

  factory SyncRun.fromJson(Map<String, Object?> j) => SyncRun(
        id: j['id']! as String,
        pairId: j['pair_id']! as String,
        startedAt: DateTime.parse(j['started_at']! as String),
        endedAt: j['ended_at'] == null
            ? null
            : DateTime.parse(j['ended_at']! as String),
        mode: SyncMode.fromWire(j['mode']! as String),
        trigger: j['trigger']! as String,
        exitCode: (j['exit_code'] as num?)?.toInt(),
        durationMs: (j['duration_ms'] as num?)?.toInt(),
        counts: j['counts'] == null
            ? const SyncRunCounts()
            : SyncRunCounts.fromJson(_asMap(j['counts'])),
        commandSummary: (j['command_summary'] ?? '') as String,
        state: SyncRunState.values.firstWhere(
          (s) => s.wire == j['state'],
          orElse: () => SyncRunState.queued,
        ),
        errorMessage: j['error_message'] as String?,
      );
}

@immutable
class SnapshotEntry {
  const SnapshotEntry({
    required this.path,
    required this.size,
    required this.modtime,
    this.hash,
    this.isDir = false,
    this.mime,
  });

  final String path;
  final int size;
  final DateTime modtime;
  final String? hash;
  final bool isDir;
  final String? mime;

  Map<String, Object?> toJson() => {
        'path': path,
        'size': size,
        'modtime': modtime.toUtc().toIso8601String(),
        if (hash != null) 'hash': hash,
        'is_dir': isDir,
        if (mime != null) 'mime': mime,
      };

  factory SnapshotEntry.fromJson(Map<String, Object?> j) => SnapshotEntry(
        path: j['path']! as String,
        size: (j['size'] as num).toInt(),
        modtime: DateTime.parse(j['modtime']! as String),
        hash: j['hash'] as String?,
        isDir: (j['is_dir'] ?? false) as bool,
        mime: j['mime'] as String?,
      );
}

@immutable
class Snapshot {
  const Snapshot({
    required this.pairId,
    required this.takenAt,
    required this.side,
    required this.entries,
  });

  final String pairId;
  final DateTime takenAt;
  final ChangeSide side; // local | remote
  final List<SnapshotEntry> entries;

  Map<String, Object?> toJson() => {
        'pair_id': pairId,
        'taken_at': takenAt.toUtc().toIso8601String(),
        'side': side.wire,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory Snapshot.fromJson(Map<String, Object?> j) => Snapshot(
        pairId: j['pair_id']! as String,
        takenAt: DateTime.parse(j['taken_at']! as String),
        side: ChangeSide.fromWire(j['side']! as String),
        entries: ((j['entries'] as List?) ?? const [])
            .map((e) => SnapshotEntry.fromJson(_asMap(e)))
            .toList(),
      );
}

@immutable
class Cursor {
  const Cursor({
    required this.pairId,
    required this.consumer,
    required this.lastJournalId,
    required this.updatedAt,
  });

  final String pairId;
  final String consumer;
  final int lastJournalId;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
        'pair_id': pairId,
        'consumer': consumer,
        'last_journal_id': lastJournalId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Cursor.fromJson(Map<String, Object?> j) => Cursor(
        pairId: j['pair_id']! as String,
        consumer: j['consumer']! as String,
        lastJournalId: (j['last_journal_id'] as num).toInt(),
        updatedAt: DateTime.parse(j['updated_at']! as String),
      );
}

// ---- helpers ---------------------------------------------------------------

List<String> _listOfString(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList(growable: false) : const [];

Map<String, Object?> _asMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  throw ArgumentError('Expected map, got $v');
}

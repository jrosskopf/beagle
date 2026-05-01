import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../config/config_dir.dart';
import '../errors.dart';
import '../journal/journal.dart';
import '../logging/logger.dart';
import '../models.dart';
import '../process/process_runner.dart';
import '../snapshot/snapshot_diff.dart';
import '../snapshot/snapshot_service.dart';
import 'bisync_output_parser.dart';
import 'filter_generator.dart';
import 'rclone_command_builder.dart';
import 'sync_queue.dart';
import 'sync_run_recorder.dart';

/// Orchestrates a single sync run for one pair: pre-snapshot, rclone, post-
/// snapshot, journal. Caller is responsible for serialization (use
/// [SyncQueue]) and FSM updates.
class SyncEngine {
  SyncEngine({
    required this.runner,
    required this.builder,
    required this.dir,
    required this.snapshotService,
    required this.journal,
    required this.recorder,
    FilterGenerator? filterGenerator,
  }) : filterGenerator = filterGenerator ?? FilterGenerator();

  final ProcessRunner runner;
  final RcloneCommandBuilder builder;
  final ConfigDir dir;
  final SnapshotService snapshotService;
  final Journal journal;
  final SyncRunRecorder recorder;
  final FilterGenerator filterGenerator;

  static const _uuid = Uuid();

  /// Run one sync pass for [pair].
  ///
  /// Returns the completed [SyncRun]. The pre/post snapshots are persisted
  /// under the configured snapshots dir and the journal is appended to.
  Future<SyncRun> runOnce({
    required SyncPair pair,
    required SyncTrigger trigger,
    bool forceDryRun = false,
  }) async {
    final runId = _uuid.v4();
    final started = DateTime.now().toUtc();
    var run = SyncRun(
      id: runId,
      pairId: pair.id,
      startedAt: started,
      mode: pair.mode,
      trigger: trigger.wire,
      state: SyncRunState.started,
    );

    StructuredLogger.instance.info(
      'sync run started',
      component: 'sync_engine',
      pairId: pair.id,
      data: {
        'run_id': runId,
        'mode': pair.mode.wire,
        'trigger': trigger.wire,
      },
    );

    if (pair.mode == SyncMode.bidirectional && !pair.bootstrapped &&
        trigger.reason != SyncTriggerReason.bootstrap) {
      throw BeagleError(
        BeagleErrorCode.bisyncNeedsResync,
        'Pair "${pair.name}" needs an initial bisync resync. '
        'Run "drive-beagle sync-now --pair ${pair.id} --bootstrap" '
        'or click "Bootstrap bisync" in the UI.',
      );
    }

    final filterPath = await _writeFilters(pair);
    final dryRun = forceDryRun || pair.mode == SyncMode.dryRun;

    // 1) Pre-snapshot.
    run = run.copyWith(state: SyncRunState.snapshottingPre);
    final preLocal = await snapshotService.takeLocal(pair);
    Snapshot preRemote;
    try {
      preRemote = await snapshotService.takeRemote(pair);
    } on Object catch (e) {
      throw BeagleError(
        BeagleErrorCode.remoteUnreachable,
        'Failed to enumerate remote: $e',
        remedy: 'Check `rclone listremotes` and network connectivity.',
        cause: e,
      );
    }
    await snapshotService.persist(
        preLocal, dir.snapshotPath(pair.id, 'local', 'pre.$runId'));
    await snapshotService.persist(
        preRemote, dir.snapshotPath(pair.id, 'remote', 'pre.$runId'));

    // 2) Run rclone.
    run = run.copyWith(state: SyncRunState.syncing);
    final cmd = _buildCommand(pair, filterPath, dryRun: dryRun, trigger: trigger);
    final r = await runner.run(
      cmd.executable,
      cmd.arguments,
      timeout: const Duration(minutes: 30),
    );
    StructuredLogger.instance.info(
      'rclone exited',
      component: 'sync_engine',
      pairId: pair.id,
      data: {
        'run_id': runId,
        'exit_code': r.exitCode,
        'duration_ms': r.durationMs,
        'cmd': r.commandLine,
      },
    );

    if (r.timedOut) {
      throw BeagleError(BeagleErrorCode.timeout,
          'rclone timed out after 30 minutes');
    }

    // 3) Post-snapshot (skipped on dry-run because nothing changed).
    SnapshotDiff localDiff;
    SnapshotDiff remoteDiff;
    if (dryRun) {
      localDiff = SnapshotDiff(created: [], modified: [], deleted: [], moved: []);
      remoteDiff = SnapshotDiff(created: [], modified: [], deleted: [], moved: []);
    } else {
      run = run.copyWith(state: SyncRunState.snapshottingPost);
      final postLocal = await snapshotService.takeLocal(pair);
      final postRemote = await snapshotService.takeRemote(pair);
      await snapshotService.persist(
          postLocal, dir.snapshotPath(pair.id, 'local', 'post.$runId'));
      await snapshotService.persist(
          postRemote, dir.snapshotPath(pair.id, 'remote', 'post.$runId'));
      final differ = SnapshotDiffer();
      localDiff = differ.diff(preLocal, postLocal);
      remoteDiff = differ.diff(preRemote, postRemote);
    }

    // 4) Journal.
    run = run.copyWith(state: SyncRunState.journaling);
    final entries = recorder.record(
      run: run,
      attribution: ChangeSide.unknown,
      localDiff: localDiff,
      remoteDiff: remoteDiff,
    );
    await journal.append(entries);

    // 5) Optionally enrich from bisync output.
    if (pair.mode == SyncMode.bidirectional && !dryRun) {
      final parsed = BisyncOutputParser().parse(r.stdout + '\n' + r.stderr);
      // We've already journaled the snapshot diff; the parse is supplementary
      // metadata, surfaced via the run's commandSummary for debugging.
      run = run.copyWith(
        commandSummary:
            '${r.commandLine}\n# bisync recognized ${parsed.length} structured changes',
      );
    } else {
      run = run.copyWith(commandSummary: r.commandLine);
    }

    final ended = DateTime.now().toUtc();
    final ok = r.exitCode == 0;
    final state = ok
        ? SyncRunState.succeeded
        : (entries.isNotEmpty ? SyncRunState.partial : SyncRunState.failed);
    run = run.copyWith(
      endedAt: ended,
      durationMs: ended.difference(started).inMilliseconds,
      exitCode: r.exitCode,
      counts: _countsOf(localDiff, remoteDiff),
      state: state,
      errorMessage: ok ? null : _firstStderrLine(r.stderr),
    );
    if (!ok) {
      throw BeagleError(
        BeagleErrorCode.rcloneFailed,
        'rclone exited with code ${r.exitCode}',
        remedy: 'See logs and run with --dry-run to inspect.',
      );
    }
    return run;
  }

  // ---- helpers ------------------------------------------------------------

  Future<String> _writeFilters(SyncPair pair) async {
    await Directory(dir.snapshotsDir).create(recursive: true);
    final ff = filterGenerator.generate(pair.filters);
    return filterGenerator.writeAtomic(dir.filtersFilePath(pair.id), ff);
  }

  RcloneCommand _buildCommand(
    SyncPair pair,
    String filterPath, {
    required bool dryRun,
    required SyncTrigger trigger,
  }) {
    switch (pair.mode) {
      case SyncMode.mirrorFromRemote:
        return builder.mirrorFromRemote(pair,
            filterFromPath: filterPath, dryRun: dryRun);
      case SyncMode.toRemote:
        return builder.pushToRemote(pair,
            filterFromPath: filterPath, dryRun: dryRun);
      case SyncMode.bidirectional:
        if (trigger.reason == SyncTriggerReason.bootstrap || !pair.bootstrapped) {
          return builder.bisyncResync(pair,
              filterFromPath: filterPath,
              workdir: dir.bisyncWorkdir(pair.id),
              dryRun: dryRun);
        }
        return builder.bisync(pair,
            filterFromPath: filterPath,
            workdir: dir.bisyncWorkdir(pair.id),
            dryRun: dryRun);
      case SyncMode.dryRun:
        // Use mirrorFromRemote with --dry-run as the safest read-only probe.
        return builder.mirrorFromRemote(pair,
            filterFromPath: filterPath, dryRun: true);
    }
  }

  static SyncRunCounts _countsOf(SnapshotDiff l, SnapshotDiff r) {
    return SyncRunCounts(
      created: l.created.length + r.created.length,
      modified: l.modified.length + r.modified.length,
      deleted: l.deleted.length + r.deleted.length,
      moved: l.moved.length + r.moved.length,
    );
  }

  static String? _firstStderrLine(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return t.split('\n').first;
  }
}

import 'dart:async';

import 'package:beagle_core/beagle_core.dart';

/// Aggregate snapshot of engine state suitable for UI rendering.
class EngineState {
  EngineState({
    required this.pairs,
    required this.lifecycleByPair,
    required this.lastSyncByPair,
    required this.lastEventByPair,
    required this.unackedByPair,
    required this.globalPaused,
    required this.appStartedAt,
  });

  final List<SyncPair> pairs;
  final Map<String, PairLifecycleState> lifecycleByPair;
  final Map<String, SyncRun?> lastSyncByPair;
  final Map<String, WatcherEvent?> lastEventByPair;
  final Map<String, int> unackedByPair;
  final bool globalPaused;
  final DateTime appStartedAt;
}

/// The engine ties everything together. One instance per running app.
class Engine {
  Engine._({
    required this.dir,
    required this.config,
    required this.controlServer,
  });

  final ConfigDir dir;
  AppConfig config;
  final ControlServer controlServer;

  final _coordinators = <String, _PairCoordinator>{};
  final _stateController = StreamController<EngineState>.broadcast();
  final _watcherEvents = StreamController<WatcherEvent>.broadcast();
  bool _globalPaused = false;
  final DateTime _startedAt = DateTime.now().toUtc();

  Stream<EngineState> get stateStream => _stateController.stream;
  Stream<WatcherEvent> get watcherEvents => _watcherEvents.stream;

  /// Public hook for the UI: trigger an immediate sync run for a pair.
  Future<void> triggerSync(String pairId,
      {required SyncTriggerReason reason, bool forceDryRun = false}) async {
    final c = _coordinators[pairId];
    if (c == null) return;
    await c.triggerNow(reason, forceDryRun: forceDryRun);
  }

  /// Public hook for the UI: pause / resume a single pair.
  void pausePair(String pairId) => _coordinators[pairId]?.pause();
  void resumePair(String pairId) => _coordinators[pairId]?.resume();

  static Future<Engine> start({
    required ConfigDir dir,
    required AppConfig config,
  }) async {
    final socketPath = config.ipcSocketPath ?? dir.defaultIpcSocketPath();
    late Engine engine;
    final server = ControlServer(
      socketPath: socketPath,
      dispatcher: (method, params, _) => engine._dispatch(method, params),
    );
    engine = Engine._(dir: dir, config: config, controlServer: server);
    await server.listen();

    for (final pair in config.pairs.where((p) => p.enabled)) {
      await engine._spawnCoordinator(pair);
    }
    engine._emitState();
    return engine;
  }

  Future<void> stop() async {
    for (final c in _coordinators.values) {
      await c.stop();
    }
    await controlServer.close();
    await _stateController.close();
    await _watcherEvents.close();
  }

  Future<void> _spawnCoordinator(SyncPair pair) async {
    final c = _PairCoordinator(
      pair: pair,
      dir: dir,
      onWatcherEvent: (e) {
        _watcherEvents.add(e);
        controlServer.broadcast('watch_events.update', e.toJson());
        _emitState();
      },
      onJournal: (entries) {
        for (final entry in entries) {
          controlServer.broadcast('journal.update', entry.toJson());
        }
      },
      onLifecycleChange: () => _emitState(),
    );
    await c.start();
    _coordinators[pair.id] = c;
  }

  // ---- IPC dispatcher -----------------------------------------------------

  Future<Object?> _dispatch(String method, Map<String, Object?> params) async {
    switch (method) {
      case 'ping':
        return 'pong';
      case 'status':
        return _statusJson();
      case 'list_pairs':
        return [for (final p in config.pairs) p.toJson()];
      case 'pause':
        if (params['pair'] is String) {
          _coordinators[_resolvePairId(params['pair']! as String)]?.pause();
        } else {
          _globalPaused = true;
          for (final c in _coordinators.values) {
            c.pause();
          }
        }
        _emitState();
        return {'ok': true};
      case 'resume':
        if (params['pair'] is String) {
          _coordinators[_resolvePairId(params['pair']! as String)]?.resume();
        } else {
          _globalPaused = false;
          for (final c in _coordinators.values) {
            c.resume();
          }
        }
        _emitState();
        return {'ok': true};
      case 'sync_now':
        final id = _resolvePairId(params['pair']! as String);
        final c = _coordinators[id];
        if (c == null) {
          throw BeagleError(BeagleErrorCode.pairNotFound, 'pair $id not running');
        }
        final isBootstrap = (params['bootstrap'] ?? false) as bool;
        unawaited(c.triggerNow(
            isBootstrap ? SyncTriggerReason.bootstrap : SyncTriggerReason.manual));
        return {'queued': true};
      case 'dry_run':
        final id = _resolvePairId(params['pair']! as String);
        final c = _coordinators[id];
        if (c == null) {
          throw BeagleError(BeagleErrorCode.pairNotFound, 'pair $id not running');
        }
        unawaited(c.triggerNow(SyncTriggerReason.manual, forceDryRun: true));
        return {'queued': true};
      case 'tail_logs':
        StructuredLogger.instance.tail.listen((entry) {
          controlServer.broadcast('log.update', entry);
        });
        return {'ok': true};
      case 'subscribe_watch_events':
        return {'ok': true}; // events are already broadcast.
      case 'subscribe_journal':
        return {'ok': true};
      case 'last_sync':
        final id = _resolvePairId(params['pair']! as String);
        final c = _coordinators[id];
        return {
          'attempt': c?.state.lastSyncRun?.toJson(),
          'success': c?.state.lastSuccessfulRun?.toJson(),
        };
      default:
        throw BeagleError(
          BeagleErrorCode.invalidConfig,
          'Unknown method: $method',
        );
    }
  }

  String _resolvePairId(String idOrName) {
    for (final p in config.pairs) {
      if (p.id == idOrName || p.name == idOrName) return p.id;
    }
    throw BeagleError(BeagleErrorCode.pairNotFound, 'No pair "$idOrName"');
  }

  Map<String, Object?> _statusJson() {
    return {
      'schema_version': beagleSchemaVersion,
      'started_at': _startedAt.toIso8601String(),
      'global_paused': _globalPaused,
      'pairs': [
        for (final p in config.pairs)
          {
            'id': p.id,
            'name': p.name,
            'lifecycle': _coordinators[p.id]?.fsm.state.name ?? 'idle',
            'last_event_at': _coordinators[p.id]
                ?.state
                .lastWatcherEventAt
                ?.toIso8601String(),
          },
      ],
    };
  }

  void _emitState() {
    if (_stateController.isClosed) return;
    _stateController.add(EngineState(
      pairs: config.pairs,
      lifecycleByPair: {
        for (final e in _coordinators.entries) e.key: e.value.fsm.state,
      },
      lastSyncByPair: {
        for (final e in _coordinators.entries) e.key: e.value.state.lastSyncRun,
      },
      lastEventByPair: {
        for (final e in _coordinators.entries) e.key: e.value.lastEvent,
      },
      unackedByPair: {
        for (final e in _coordinators.entries)
          e.key: e.value.state.unackedAuthoritativeCount,
      },
      globalPaused: _globalPaused,
      appStartedAt: _startedAt,
    ));
  }
}

/// One coordinator per sync pair: owns the watcher supervisor, scheduler,
/// queue, FSM, and persistent state for that pair.
class _PairCoordinator {
  _PairCoordinator({
    required this.pair,
    required this.dir,
    required this.onWatcherEvent,
    required this.onJournal,
    required this.onLifecycleChange,
  })  : runner = const RealProcessRunner(),
        builder = const RcloneCommandBuilder(),
        fsm = PairStateMachine(),
        state = PairState(pairId: pair.id);

  final SyncPair pair;
  final ConfigDir dir;
  final ProcessRunner runner;
  final RcloneCommandBuilder builder;
  final PairStateMachine fsm;
  final PairState state;

  final void Function(WatcherEvent) onWatcherEvent;
  final void Function(List<ChangeEntry>) onJournal;
  final void Function() onLifecycleChange;

  late WatcherSupervisor supervisor;
  late ReconciliationScheduler scheduler;
  late SyncQueue queue;
  late SyncEngine engine;
  late Journal journal;
  late SnapshotService snapshotService;

  Debouncer? _debounce;
  WatcherEvent? lastEvent;
  bool _paused = false;

  Future<void> start() async {
    journal = await Journal.open(
      pairId: pair.id,
      jsonlPath: dir.journalJsonlPath(pair.id),
      dbPath: dir.journalDbPath(pair.id),
    );
    snapshotService = SnapshotService(runner: runner, builder: builder);
    engine = SyncEngine(
      runner: runner,
      builder: builder,
      dir: dir,
      snapshotService: snapshotService,
      journal: journal,
      recorder: SyncRunRecorder(),
    );

    queue = SyncQueue(runner: _runOne);

    supervisor = WatcherSupervisor(
      pair: pair,
      backendFactory: () => defaultBackendForHost(runner),
    );
    await supervisor.start();
    supervisor.events.listen(_handleWatcherEvent);

    scheduler = ReconciliationScheduler(
      intervalSeconds: pair.reconcileEverySeconds,
      onTick: () async {
        if (_paused) return;
        await queue.enqueue(SyncTrigger(
          reason: SyncTriggerReason.reconcile,
          requestedAt: DateTime.now().toUtc(),
        ));
      },
    )..start();

    fsm.transition(PairLifecycleEvent.start);
    state.lifecycle = fsm.state;
    onLifecycleChange();
  }

  Future<void> stop() async {
    scheduler.stop();
    _debounce?.cancel();
    await supervisor.stop();
    await journal.close();
  }

  void pause() {
    _paused = true;
    fsm.transition(PairLifecycleEvent.pause);
    state.lifecycle = fsm.state;
    onLifecycleChange();
  }

  void resume() {
    _paused = false;
    fsm.transition(PairLifecycleEvent.resume);
    fsm.transition(PairLifecycleEvent.start);
    state.lifecycle = fsm.state;
    onLifecycleChange();
  }

  Future<void> triggerNow(SyncTriggerReason reason,
      {bool forceDryRun = false}) async {
    await queue.enqueue(SyncTrigger(
      reason: reason,
      requestedAt: DateTime.now().toUtc(),
      note: forceDryRun ? 'force_dry_run' : null,
    ));
  }

  void _handleWatcherEvent(WatcherEvent ev) {
    lastEvent = ev;
    state.lastWatcherEventAt = ev.tsUtc;
    onWatcherEvent(ev);
    if (_paused) return;

    _debounce ??= Debouncer(
      delay: Duration(milliseconds: pair.debounceMs),
      maxWait: Duration(milliseconds: pair.debounceMs * 5),
    );
    _debounce!.tap(() async {
      fsm.transition(PairLifecycleEvent.changeDetected);
      state.lifecycle = fsm.state;
      onLifecycleChange();
      await queue.enqueue(SyncTrigger(
        reason: SyncTriggerReason.watcher,
        requestedAt: DateTime.now().toUtc(),
      ));
    });
  }

  Future<void> _runOne(SyncTrigger trigger) async {
    fsm.transition(PairLifecycleEvent.dispatch);
    state.lifecycle = fsm.state;
    onLifecycleChange();

    try {
      final run = await engine.runOnce(
        pair: pair,
        trigger: trigger,
        forceDryRun: trigger.note == 'force_dry_run',
      );
      state.lastSyncRun = run;
      if (run.succeeded) {
        state.lastSuccessfulRun = run;
        fsm.transition(PairLifecycleEvent.runSucceeded);
      } else {
        fsm.transition(PairLifecycleEvent.runFailedRecoverable);
      }
    } on BeagleError catch (e) {
      StructuredLogger.instance.error(
        'sync run failed: ${e.message}',
        component: 'coordinator',
        pairId: pair.id,
        data: {'code': e.code.wire},
      );
      // Hard failures (auth, missing rclone) are fatal; everything else
      // recoverable.
      final fatal = e.code == BeagleErrorCode.rcloneMissing ||
          e.code == BeagleErrorCode.rcloneVersionTooOld ||
          e.code == BeagleErrorCode.bisyncNeedsResync;
      fsm.transition(fatal
          ? PairLifecycleEvent.runFailedFatal
          : PairLifecycleEvent.runFailedRecoverable);
    } finally {
      state.lifecycle = fsm.state;
      onLifecycleChange();
      // Persist state.
      final store = StateStore(dir.stateFilePath);
      final all = await store.load();
      all[pair.id] = state;
      await store.save(all);
    }
  }
}

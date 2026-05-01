import 'dart:async';

import 'package:beagle_core/beagle_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine.dart';

/// Riverpod handle on the running engine.
final engineHostProvider = Provider<EngineHost>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

final engineStateProvider = StreamProvider<EngineState>(
  (ref) => ref.watch(engineHostProvider).stateStream,
);

final watcherEventsProvider = StreamProvider<WatcherEvent>(
  (ref) => ref.watch(engineHostProvider).watcherEvents,
);

final logTailProvider = StreamProvider<Map<String, Object?>>(
  (ref) => ref.watch(engineHostProvider).logTail,
);

/// Hosts the [Engine] in the same Dart isolate as the Flutter UI.
///
/// We deliberately do NOT spawn a separate Dart isolate because the user-
/// requested architecture is "all-in-one Flutter app". The engine's heavy
/// work (rclone subprocesses, sqlite writes, watcher streaming) is naturally
/// async/IO-bound, so it co-exists comfortably with the UI on the main isolate.
class EngineHost {
  EngineHost._(this.engine);
  final Engine engine;

  Stream<EngineState> get stateStream => engine.stateStream;
  Stream<WatcherEvent> get watcherEvents => engine.watcherEvents;
  Stream<Map<String, Object?>> get logTail => StructuredLogger.instance.tail;

  static Future<EngineHost> boot() async {
    final dir = ConfigDir.resolve();
    await dir.ensure();
    await StructuredLogger.init(logsDir: dir.logsDir);
    final cfg = await ConfigLoader(dir).load();
    final engine = await Engine.start(dir: dir, config: cfg);
    return EngineHost._(engine);
  }

  Future<void> shutdown() => engine.stop();
}

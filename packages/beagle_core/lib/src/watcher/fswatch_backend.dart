import 'dart:async';
import 'dart:convert';

import '../logging/logger.dart';
import '../models.dart';
import '../process/process_runner.dart';
import 'watcher_backend.dart';
import 'watcher_event.dart';

/// fswatch-backed watcher (macOS).
///
/// Invocation:
///   fswatch -0 -r -x --event-flag-separator=, --latency 0.5 \
///     [-e <regex>] <root>
///
/// `-0` emits NUL-delimited records, `-x` includes the event flag list (after
/// the path, separated by a space — we reconfigure with
/// `--event-flag-separator=,` for stable parsing).
class FswatchBackend implements WatcherBackend {
  FswatchBackend({
    required this.runner,
    this.executable = 'fswatch',
    this.latencySeconds = 0.5,
  });

  final ProcessRunner runner;
  final String executable;
  final double latencySeconds;

  StreamedProcess? _proc;

  @override
  String get name => 'fswatch';

  @override
  Stream<WatcherEvent> start(SyncPair pair) async* {
    final excludes = _excludeRegexes(pair);
    final args = <String>[
      '-0',
      '-r',
      '-x',
      '--event-flag-separator=,',
      '--latency=$latencySeconds',
      for (final e in excludes) ...['-e', e],
      pair.localPath,
    ];

    final proc = await runner.stream(executable, args);
    _proc = proc;
    StructuredLogger.instance.info(
      'fswatch started',
      component: 'watcher',
      pairId: pair.id,
      data: {'cmd': proc.commandLine, 'pid': proc.process.pid},
    );

    proc.stderrLines.listen((line) {
      if (line.isEmpty) return;
      StructuredLogger.instance.warn(
        'fswatch stderr: $line',
        component: 'watcher',
        pairId: pair.id,
      );
    });

    final controller = StreamController<WatcherEvent>();
    // fswatch prints NUL-terminated records — we cannot use the line splitter
    // shipped by ProcessRunner. Re-tap the underlying process bytes.
    final raw = _nulSplit(proc.process.stdout);
    final sub = raw.listen((record) {
      final ev = parseRecord(record, pair);
      if (ev != null) controller.add(ev);
    }, onError: controller.addError);

    unawaited(proc.exitCode.then((code) async {
      await sub.cancel();
      await controller.close();
      StructuredLogger.instance.info(
        'fswatch exited',
        component: 'watcher',
        pairId: pair.id,
        data: {'exit_code': code},
      );
    }));

    yield* controller.stream;
  }

  @override
  Future<void> stop() async {
    final p = _proc;
    if (p != null) p.kill();
    _proc = null;
  }

  @override
  String describe() => 'fswatch pid=${_proc?.process.pid ?? "-"}';

  // --- pure helpers --------------------------------------------------------

  /// Parse one fswatch `-0 -x --event-flag-separator=,` record.
  /// Format: `<path> <flag1>,<flag2>,...`. Path may contain spaces.
  static WatcherEvent? parseRecord(String record, SyncPair pair) {
    if (record.isEmpty) return null;
    // Split off the trailing flag list. The separator is a single space, but
    // fswatch only ever appends one space + the comma-joined flags, so the
    // last space in the record marks the boundary.
    final lastSpace = record.lastIndexOf(' ');
    if (lastSpace < 0) return null;
    final path = record.substring(0, lastSpace);
    final flagList = record.substring(lastSpace + 1).split(',');
    final kind = classifyEventNames(flagList);
    return WatcherEvent(
      pairId: pair.id,
      backend: 'fswatch',
      path: path,
      kind: kind,
      tsUtc: DateTime.now().toUtc(),
      raw: record,
    );
  }

  static Stream<String> _nulSplit(Stream<List<int>> input) async* {
    final buf = <int>[];
    await for (final chunk in input) {
      for (final b in chunk) {
        if (b == 0) {
          yield utf8.decode(buf, allowMalformed: true);
          buf.clear();
        } else {
          buf.add(b);
        }
      }
    }
    if (buf.isNotEmpty) yield utf8.decode(buf, allowMalformed: true);
  }

  static List<String> _excludeRegexes(SyncPair pair) {
    final out = <String>[];
    if (pair.filters.ignoreHidden) out.add(r'(^|/)\..+');
    if (pair.filters.ignoreVcs) out.add(r'(^|/)\.git(/|$)');
    if (pair.filters.ignoreNodeModules) out.add(r'(^|/)node_modules(/|$)');
    if (pair.filters.ignoreCommonBuildDirs) {
      out.add(r'(^|/)(build|dist|target|\.dart_tool|\.gradle|\.idea|\.vscode|__pycache__|\.cache)(/|$)');
    }
    return out;
  }
}

import 'dart:async';

import 'package:path/path.dart' as p;

import '../logging/logger.dart';
import '../models.dart';
import '../process/process_runner.dart';
import 'watcher_backend.dart';
import 'watcher_event.dart';

/// inotifywait-backed watcher (Linux).
///
/// Invocation:
///   inotifywait -m -r -q --csv \
///     --format '%w,%e,%f' \
///     -e modify,create,delete,move,attrib,move_self,delete_self \
///     [--exclude <regex>] \
///     <root>
///
/// The CSV format is RFC-4180-ish: fields are separated by commas; any field
/// containing commas, quotes, or whitespace is wrapped in double-quotes and
/// embedded quotes are doubled. We parse it manually so filenames containing
/// commas don't break us.
class InotifywaitBackend implements WatcherBackend {
  InotifywaitBackend({
    required this.runner,
    this.executable = 'inotifywait',
  });

  final ProcessRunner runner;
  final String executable;

  StreamedProcess? _proc;

  @override
  String get name => 'inotifywait';

  @override
  Stream<WatcherEvent> start(SyncPair pair) async* {
    final exclude = _excludeRegex(pair);
    // NOTE: inotifywait 3.22+ rejects `--format` together with `--csv`; the
    // CSV output already uses the fixed format `<watched_path>,<events>,<file>`,
    // which is what `parseLine` expects.
    final args = <String>[
      '-m',
      '-r',
      '-q',
      '--csv',
      '-e',
      'modify,create,delete,move,attrib,move_self,delete_self',
      if (exclude != null) ...['--exclude', exclude],
      pair.localPath,
    ];

    final proc = await runner.stream(executable, args);
    _proc = proc;
    StructuredLogger.instance.info(
      'inotifywait started',
      component: 'watcher',
      pairId: pair.id,
      data: {'cmd': proc.commandLine, 'pid': proc.process.pid},
    );

    proc.stderrLines.listen((line) {
      if (line.isEmpty) return;
      StructuredLogger.instance.warn(
        'inotifywait stderr: $line',
        component: 'watcher',
        pairId: pair.id,
      );
    });

    final controller = StreamController<WatcherEvent>();
    final sub = proc.stdoutLines.listen((line) {
      final ev = parseLine(line, pair);
      if (ev != null) controller.add(ev);
    }, onError: controller.addError);

    unawaited(proc.exitCode.then((code) async {
      await sub.cancel();
      await controller.close();
      StructuredLogger.instance.info(
        'inotifywait exited',
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
  String describe() => 'inotifywait pid=${_proc?.process.pid ?? "-"}';

  // --- pure helpers (visible for tests) -----------------------------------

  /// Parse a single CSV-formatted inotifywait line.
  /// Format: `watched_path,event_list,filename`
  /// Returns null on parse failure.
  static WatcherEvent? parseLine(String line, SyncPair pair) {
    if (line.isEmpty) return null;
    final fields = _parseCsvLine(line);
    if (fields.length < 2 || fields.length > 3) return null;
    final watchedPath = fields[0];
    final events = fields[1].split(',');
    final filename = fields.length == 3 ? fields[2] : '';

    final fullPath =
        filename.isEmpty ? watchedPath : p.join(watchedPath, filename);
    final kind = classifyEventNames(events);

    return WatcherEvent(
      pairId: pair.id,
      backend: 'inotifywait',
      path: fullPath,
      kind: kind,
      tsUtc: DateTime.now().toUtc(),
      raw: line,
    );
  }

  static List<String> _parseCsvLine(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else {
        if (c == ',') {
          out.add(buf.toString());
          buf.clear();
        } else if (c == '"' && buf.isEmpty) {
          inQuotes = true;
        } else {
          buf.write(c);
        }
      }
    }
    out.add(buf.toString());
    return out;
  }

  static String? _excludeRegex(SyncPair pair) {
    final parts = <String>[];
    if (pair.filters.ignoreHidden) parts.add(r'(^|/)\..+');
    if (pair.filters.ignoreVcs) parts.add(r'(^|/)\.git(/|$)');
    if (pair.filters.ignoreNodeModules) parts.add(r'(^|/)node_modules(/|$)');
    if (pair.filters.ignoreCommonBuildDirs) {
      parts.add(r'(^|/)(build|dist|target|\.dart_tool|\.gradle|\.idea|\.vscode|__pycache__|\.cache)(/|$)');
    }
    if (parts.isEmpty) return null;
    return '(${parts.join('|')})';
  }
}

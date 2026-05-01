import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum LogLevel { trace, debug, info, warn, error }

LogLevel _parseLevel(String s) => switch (s.toLowerCase()) {
      'trace' => LogLevel.trace,
      'debug' => LogLevel.debug,
      'info' => LogLevel.info,
      'warn' || 'warning' => LogLevel.warn,
      'error' => LogLevel.error,
      _ => LogLevel.info,
    };

/// Structured JSONL logger.
///
/// One line per event so log tails are agent-greppable. Writes to a daily
/// rotating file under <configDir>/logs/ and to a broadcast stream consumed
/// by the UI / `drive-beagle logs --follow`.
class StructuredLogger {
  StructuredLogger._(this._sink, this._minLevel, this._tailController);

  static StructuredLogger? _instance;
  static StructuredLogger get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('StructuredLogger not initialized; call init() first.');
    }
    return i;
  }

  final IOSink? _sink;
  final LogLevel _minLevel;
  final StreamController<Map<String, Object?>> _tailController;

  Stream<Map<String, Object?>> get tail => _tailController.stream;

  static Future<StructuredLogger> init({
    required String logsDir,
    String level = 'info',
  }) async {
    await Directory(logsDir).create(recursive: true);
    final today =
        DateTime.now().toUtc().toIso8601String().substring(0, 10); // YYYY-MM-DD
    final file = File(p.join(logsDir, 'drive-beagle.$today.jsonl'));
    final sink = file.openWrite(mode: FileMode.append);
    final logger = StructuredLogger._(
      sink,
      _parseLevel(level),
      StreamController<Map<String, Object?>>.broadcast(),
    );
    _instance = logger;
    return logger;
  }

  /// Construct an in-memory-only logger (no file). Used by tests + CLI when
  /// running headless read-only commands.
  static StructuredLogger memory({String level = 'info'}) {
    final logger = StructuredLogger._(
      null,
      _parseLevel(level),
      StreamController<Map<String, Object?>>.broadcast(),
    );
    _instance = logger;
    return logger;
  }

  void log(
    LogLevel level,
    String message, {
    String? component,
    String? pairId,
    Map<String, Object?> data = const {},
  }) {
    if (level.index < _minLevel.index) return;
    final entry = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'msg': message,
      if (component != null) 'component': component,
      if (pairId != null) 'pair_id': pairId,
      ...data,
    };
    final line = jsonEncode(entry);
    _sink?.writeln(line);
    if (!_tailController.isClosed) _tailController.add(entry);
  }

  void trace(String m, {String? component, String? pairId, Map<String, Object?> data = const {}}) =>
      log(LogLevel.trace, m, component: component, pairId: pairId, data: data);
  void debug(String m, {String? component, String? pairId, Map<String, Object?> data = const {}}) =>
      log(LogLevel.debug, m, component: component, pairId: pairId, data: data);
  void info(String m, {String? component, String? pairId, Map<String, Object?> data = const {}}) =>
      log(LogLevel.info, m, component: component, pairId: pairId, data: data);
  void warn(String m, {String? component, String? pairId, Map<String, Object?> data = const {}}) =>
      log(LogLevel.warn, m, component: component, pairId: pairId, data: data);
  void error(String m, {String? component, String? pairId, Map<String, Object?> data = const {}}) =>
      log(LogLevel.error, m, component: component, pairId: pairId, data: data);

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    await _tailController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors.dart';

/// Client for the drive-beagle control socket. Used by the CLI when the app
/// is running. Read-only commands transparently fall back to direct on-disk
/// reads when [connect] fails — that fallback lives in the CLI dispatcher,
/// not here.
class ControlClient {
  ControlClient._(this._socket, this._lines);

  final Socket _socket;
  final Stream<String> _lines;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _notifications = StreamController<Map<String, Object?>>.broadcast();

  Stream<Map<String, Object?>> get notifications => _notifications.stream;

  static Future<ControlClient> connect(String socketPath,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final addr = InternetAddress(socketPath, type: InternetAddressType.unix);
    final Socket socket;
    try {
      socket = await Socket.connect(addr, 0).timeout(timeout);
    } on Object catch (e) {
      throw BeagleError(
        BeagleErrorCode.notRunning,
        'drive-beagle is not running (socket: $socketPath)',
        cause: e,
      );
    }
    final lines = socket
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    final c = ControlClient._(socket, lines);
    c._lines.listen(c._onLine);
    return c;
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    final m = (jsonDecode(line) as Map).cast<String, Object?>();
    final id = m['id'];
    if (id is int && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(m);
    } else {
      _notifications.add(m);
    }
  }

  Future<Object?> call(String method, [Map<String, Object?> params = const {}]) async {
    final id = _nextId++;
    final c = Completer<Map<String, Object?>>();
    _pending[id] = c;
    _socket.writeln(jsonEncode({'id': id, 'method': method, 'params': params}));
    final reply = await c.future.timeout(const Duration(seconds: 30));
    if (reply.containsKey('error')) {
      final err = (reply['error'] as Map).cast<String, Object?>();
      throw BeagleError(
        _parseCode(err['code']),
        (err['message'] ?? 'unknown error') as String,
        remedy: err['remedy'] as String?,
      );
    }
    return reply['result'];
  }

  Future<void> close() async {
    await _socket.close();
    await _notifications.close();
  }
}

BeagleErrorCode _parseCode(Object? raw) {
  if (raw is! String) return BeagleErrorCode.internalError;
  for (final c in BeagleErrorCode.values) {
    if (c.wire == raw) return c;
  }
  return BeagleErrorCode.internalError;
}

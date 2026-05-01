import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors.dart';
import '../logging/logger.dart';

/// Newline-delimited JSON-RPC 2.0 server over a Unix domain socket.
class ControlServer {
  ControlServer({
    required this.socketPath,
    required this.dispatcher,
  });

  final String socketPath;
  final Future<Object?> Function(String method, Map<String, Object?> params,
      ControlConnection connection) dispatcher;

  ServerSocket? _server;
  final _connections = <ControlConnection>{};

  Future<void> listen() async {
    final f = File(socketPath);
    if (await f.exists()) await f.delete();
    final addr = InternetAddress(socketPath, type: InternetAddressType.unix);
    _server = await ServerSocket.bind(addr, 0);
    StructuredLogger.instance.info(
      'control socket listening',
      component: 'ipc',
      data: {'path': socketPath},
    );
    _server!.listen((socket) {
      final conn = ControlConnection._(socket, dispatcher);
      _connections.add(conn);
      conn.onClose(() => _connections.remove(conn));
    });
  }

  Future<void> close() async {
    await _server?.close();
    for (final c in _connections.toList()) {
      await c.close();
    }
    final f = File(socketPath);
    if (await f.exists()) {
      try {
        await f.delete();
      } on FileSystemException {/* ignore */}
    }
  }

  /// Push a notification to all currently-connected clients (used for
  /// streaming watch events / journal updates).
  void broadcast(String method, Map<String, Object?> params) {
    for (final c in _connections) {
      c._write({'method': method, 'params': params});
    }
  }
}

class ControlConnection {
  ControlConnection._(this._socket, this._dispatcher) {
    _socket
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: _handleClose, onError: (Object _) => _handleClose());
  }

  final Socket _socket;
  final Future<Object?> Function(String, Map<String, Object?>, ControlConnection)
      _dispatcher;
  final List<void Function()> _closeHandlers = [];

  void onClose(void Function() handler) => _closeHandlers.add(handler);

  Future<void> close() async {
    await _socket.close();
  }

  Future<void> _handleLine(String line) async {
    if (line.trim().isEmpty) return;
    Map<String, Object?> req;
    try {
      req = (jsonDecode(line) as Map).cast<String, Object?>();
    } on Object {
      _write({
        'error': {'code': 'INVALID_REQUEST', 'message': 'Malformed JSON'},
      });
      return;
    }
    final id = req['id'];
    final method = req['method'] as String?;
    final params = (req['params'] as Map?)?.cast<String, Object?>() ?? const {};
    if (method == null) {
      _write({
        if (id != null) 'id': id,
        'error': {'code': 'INVALID_REQUEST', 'message': 'method required'},
      });
      return;
    }
    try {
      final result = await _dispatcher(method, params, this);
      _write({if (id != null) 'id': id, 'result': result});
    } on BeagleError catch (e) {
      _write({
        if (id != null) 'id': id,
        'error': e.toJson(),
      });
    } catch (e, st) {
      StructuredLogger.instance.error(
        'rpc dispatch error',
        component: 'ipc',
        data: {'method': method, 'error': e.toString(), 'stack': st.toString()},
      );
      _write({
        if (id != null) 'id': id,
        'error': {'code': 'INTERNAL_ERROR', 'message': e.toString()},
      });
    }
  }

  void _write(Map<String, Object?> obj) {
    try {
      _socket.writeln(jsonEncode(obj));
    } on StateError {
      // socket already closed; drop.
    }
  }

  void _handleClose() {
    for (final h in _closeHandlers) {
      h();
    }
  }
}

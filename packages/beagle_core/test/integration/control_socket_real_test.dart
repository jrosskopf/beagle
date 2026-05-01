@Tags(['integration'])
library;

import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String socketPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('beagle-ipc-');
    socketPath = p.join(tmp.path, 'control.sock');
    StructuredLogger.memory();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('ControlServer + ControlClient over a real Unix domain socket', () {
    test('ping → pong round-trip', () async {
      final server = ControlServer(
        socketPath: socketPath,
        dispatcher: (method, params, _) async {
          if (method == 'ping') return 'pong';
          throw BeagleError(BeagleErrorCode.invalidConfig, 'unknown');
        },
      );
      await server.listen();
      addTearDown(server.close);

      final client = await ControlClient.connect(socketPath);
      addTearDown(client.close);

      final r = await client.call('ping');
      expect(r, 'pong');
    });

    test('errors round-trip with code + message', () async {
      final server = ControlServer(
        socketPath: socketPath,
        dispatcher: (method, params, _) async {
          throw BeagleError(
            BeagleErrorCode.pairNotFound,
            'No pair "x"',
            remedy: 'List pairs',
          );
        },
      );
      await server.listen();
      addTearDown(server.close);

      final client = await ControlClient.connect(socketPath);
      addTearDown(client.close);

      Object? caught;
      try {
        await client.call('whatever');
      } on BeagleError catch (e) {
        caught = e;
      }
      expect(caught, isA<BeagleError>());
      expect((caught as BeagleError).code, BeagleErrorCode.pairNotFound);
      expect(caught.message, contains('No pair'));
      expect(caught.remedy, 'List pairs');
    });

    test('connect fails fast with NOT_RUNNING when no server is listening',
        () async {
      Object? caught;
      try {
        await ControlClient.connect(socketPath,
            timeout: const Duration(milliseconds: 500));
      } on BeagleError catch (e) {
        caught = e;
      }
      expect(caught, isA<BeagleError>());
      expect((caught as BeagleError).code, BeagleErrorCode.notRunning);
    });

    test('broadcast pushes notifications to connected clients', () async {
      final server = ControlServer(
        socketPath: socketPath,
        dispatcher: (method, params, _) async => null,
      );
      await server.listen();
      addTearDown(server.close);

      final client = await ControlClient.connect(socketPath);
      addTearDown(client.close);

      // Subscribe before broadcasting.
      final received = <Map<String, Object?>>[];
      final sub = client.notifications.listen(received.add);
      addTearDown(sub.cancel);

      // Give the connection a moment to register on the server side.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      server.broadcast('watch_events.update', {'pair_id': 'p1'});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(received, isNotEmpty);
      expect(received.first['method'], 'watch_events.update');
      expect((received.first['params'] as Map)['pair_id'], 'p1');
    });

    test('reuses path: server can rebind after previous instance exits',
        () async {
      // First server, then close.
      final s1 = ControlServer(
        socketPath: socketPath,
        dispatcher: (m, p, _) async => 'one',
      );
      await s1.listen();
      final c1 = await ControlClient.connect(socketPath);
      expect(await c1.call('x'), 'one');
      await c1.close();
      await s1.close();

      // Second server reuses the same path.
      final s2 = ControlServer(
        socketPath: socketPath,
        dispatcher: (m, p, _) async => 'two',
      );
      await s2.listen();
      addTearDown(s2.close);
      final c2 = await ControlClient.connect(socketPath);
      addTearDown(c2.close);
      expect(await c2.call('x'), 'two');
    });
  });
}

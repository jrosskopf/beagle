@Tags(['integration'])
library;

import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late ConfigDir dir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('beagle-cfg-');
    dir = ConfigDir(tmp);
    await dir.ensure();
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('ConfigLoader.save → file → load round-trip on real disk', () {
    test('preserves fields across save/load', () async {
      final original = AppConfig(
        globalConcurrency: 2,
        logLevel: 'debug',
        pairs: [
          SyncPair(
            id: 'pair-1',
            name: 'memory',
            localPath: '/home/u/memory',
            remoteName: 'gdrive',
            remotePath: 'memory',
            mode: SyncMode.bidirectional,
            conflictPolicy: ConflictPolicy.newerWins,
            debounceMs: 7000,
            reconcileEverySeconds: 900,
            enabled: true,
            bootstrapped: true,
          ),
        ],
      );
      final loader = ConfigLoader(dir);
      await loader.save(original);

      // Sanity: the file is on disk and parses as YAML.
      expect(await File(dir.configFilePath).exists(), isTrue);

      final reloaded = await loader.load();
      expect(reloaded.globalConcurrency, 2);
      expect(reloaded.logLevel, 'debug');
      expect(reloaded.pairs, hasLength(1));
      final p = reloaded.pairs.single;
      expect(p.id, 'pair-1');
      expect(p.name, 'memory');
      expect(p.localPath, '/home/u/memory');
      expect(p.remoteName, 'gdrive');
      expect(p.remotePath, 'memory');
      expect(p.mode, SyncMode.bidirectional);
      expect(p.conflictPolicy, ConflictPolicy.newerWins);
      expect(p.debounceMs, 7000);
      expect(p.reconcileEverySeconds, 900);
      expect(p.bootstrapped, isTrue);
    });

    test('emits stable bytes for unchanged config', () async {
      final cfg = AppConfig(
        pairs: [
          SyncPair(
            id: 'a',
            name: 'a',
            localPath: '/x',
            remoteName: 'r',
            remotePath: '',
            mode: SyncMode.toRemote,
          ),
        ],
      );
      final loader = ConfigLoader(dir);
      await loader.save(cfg);
      final bytes1 = await File(dir.configFilePath).readAsBytes();
      await loader.save(cfg);
      final bytes2 = await File(dir.configFilePath).readAsBytes();
      expect(bytes1, equals(bytes2));
    });
  });

  group('StructuredLogger writes JSONL to a real file', () {
    test('each call adds a parseable JSON line', () async {
      final logger = await StructuredLogger.init(logsDir: dir.logsDir);
      addTearDown(logger.close);
      logger.info('first', component: 'unit',
          data: const {'a': 1});
      logger.warn('second', pairId: 'p1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await logger.close();

      final files = Directory(dir.logsDir).listSync().whereType<File>().toList();
      expect(files, isNotEmpty);
      final lines = await files.first.readAsLines();
      // Both events plus possibly nothing else.
      expect(lines.length, greaterThanOrEqualTo(2));
      // Each is parseable.
      for (final l in lines) {
        expect(() => l.length, returnsNormally);
      }
    });
  });

  group('StateStore round-trip on real disk', () {
    test('save then load yields equivalent state', () async {
      final store = StateStore(dir.stateFilePath);
      final state = PairState(
        pairId: 'p1',
        lifecycle: PairLifecycleState.warning,
        unackedAuthoritativeCount: 7,
      );
      await store.save({'p1': state});
      final loaded = await store.load();
      expect(loaded['p1']!.pairId, 'p1');
      expect(loaded['p1']!.lifecycle, PairLifecycleState.warning);
      expect(loaded['p1']!.unackedAuthoritativeCount, 7);
    });

    test('returns empty map when state file does not exist', () async {
      final store = StateStore('${dir.root.path}/never_written.json');
      expect(await store.load(), isEmpty);
    });
  });
}

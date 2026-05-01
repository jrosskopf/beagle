import 'package:beagle_core/beagle_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigLoader.parse', () {
    test('parses YAML with one pair', () {
      const yaml = '''
config_version: 1
global_concurrency: 1
log_level: info
pairs:
  - id: aaa
    name: memory
    local_path: /home/u/memory
    remote_name: gdrive
    remote_path: memory
    mode: bidirectional
    conflict_policy: keep_both_suffix
    debounce_ms: 4000
    reconcile_every_seconds: 600
    enabled: true
    bootstrapped: false
''';
      final cfg = ConfigLoader.parse(yaml);
      expect(cfg.pairs, hasLength(1));
      final p = cfg.pairs.single;
      expect(p.name, 'memory');
      expect(p.mode, SyncMode.bidirectional);
      expect(p.conflictPolicy, ConflictPolicy.keepBothSuffix);
      expect(p.bootstrapped, false);
    });

    test('parses JSON with same shape', () {
      const json = '''
{
  "config_version": 1,
  "pairs": [{
    "id": "aaa",
    "name": "memory",
    "local_path": "/home/u/memory",
    "remote_name": "gdrive",
    "remote_path": "memory",
    "mode": "to_remote"
  }]
}
''';
      final cfg = ConfigLoader.parse(json);
      expect(cfg.pairs.single.mode, SyncMode.toRemote);
    });

    test('rejects malformed input', () {
      expect(() => ConfigLoader.parse('this: : is bad: : :'),
          throwsA(isA<BeagleError>()));
    });
  });
}

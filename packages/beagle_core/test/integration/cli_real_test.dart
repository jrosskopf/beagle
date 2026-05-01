@Tags(['integration'])
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io' hide ProcessResult;
import 'dart:io' as io show ProcessResult;

import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end tests for the compiled `drive-beagle` CLI binary.
/// We invoke the real Dart-AOT binary, not its Dart entrypoint, to also catch
/// AOT-only regressions (e.g. `\$\$` interpolation, missing tree-shaken APIs).
void main() {
  final cliPath = Platform.environment['DRIVE_BEAGLE_BIN'] ?? '/tmp/drive-beagle';

  setUpAll(() {
    expect(File(cliPath).existsSync(), isTrue,
        reason:
            'CLI binary missing at $cliPath. Build with: '
            'dart compile exe packages/beagle_cli/bin/drive_beagle.dart -o $cliPath');
  });

  late Directory cfg;
  setUp(() async {
    cfg = await Directory.systemTemp.createTemp('beagle-cli-');
  });
  tearDown(() async {
    if (await cfg.exists()) await cfg.delete(recursive: true);
  });

  Future<io.ProcessResult> run(List<String> args) =>
      Process.run(cliPath, ['--config-dir', cfg.path, ...args]);

  Map<String, Object?> jsonOf(io.ProcessResult r) {
    expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}\nstdout: ${r.stdout}');
    return jsonDecode(r.stdout as String) as Map<String, Object?>;
  }

  group('drive-beagle CLI (real binary, no mocks)', () {
    test('--help returns 0 and lists agent commands', () async {
      final r = await Process.run(cliPath, const ['--help']);
      expect(r.exitCode, 0);
      final out = r.stdout as String;
      for (final cmd in const [
        'changes', 'changes-since', 'last-sync',
        'snapshot', 'diff', 'watch-events', 'ack',
        'doctor', 'add', 'remove', 'pause', 'resume',
      ]) {
        expect(out, contains(cmd));
      }
    });

    test('add → status → remove round-trips through real config file',
        () async {
      final addJson = jsonOf(await run([
        'add',
        '--name', 'memory',
        '--local-path', '${cfg.path}/local',
        '--remote', 'localtest',
        '--remote-path', '${cfg.path}/remote',
        '--mode', 'mirror_from_remote',
      ]));
      expect(addJson['schema_version'], '1.0');
      final pair = (addJson['added'] as Map).cast<String, Object?>();
      expect(pair['name'], 'memory');
      final id = pair['id']! as String;

      // Status reflects the new pair.
      final statusJson = jsonOf(await run(['status']));
      final pairs = (statusJson['pairs'] as List).cast<Map>();
      expect(pairs.map((p) => p['id']).toList(), contains(id));

      // Remove
      jsonOf(await run(['remove', '--pair', id]));
      final after = jsonOf(await run(['status']));
      expect((after['pairs'] as List), isEmpty);
    });

    test('export-config / import-config round-trip', () async {
      // Add a pair.
      jsonOf(await run([
        'add',
        '--name', 'r1',
        '--local-path', '/x',
        '--remote', 'r',
        '--mode', 'to_remote',
      ]));
      final exported = jsonOf(await run(['export-config']));
      final body = jsonEncode(exported['config']);

      // Wipe config and re-import via stdin.
      await File(p.join(cfg.path, 'config.yaml')).delete();
      final p2 = await Process.start(
        cliPath,
        ['--config-dir', cfg.path, 'import-config'],
      );
      p2.stdin.write(body);
      await p2.stdin.close();
      final exit = await p2.exitCode;
      expect(exit, 0);

      final reExported = jsonOf(await run(['export-config']));
      expect((reExported['config'] as Map)['pairs'],
          (exported['config'] as Map)['pairs']);
    });

    test('changes/ack round-trip through real journal + cursors files',
        () async {
      // Add a pair so the CLI knows its id.
      final addJson = jsonOf(await run([
        'add',
        '--name', 'memory',
        '--local-path', '/tmp/dontmatter',
        '--remote', 'localtest',
        '--remote-path', '/tmp/remote',
        '--mode', 'mirror_from_remote',
      ]));
      final pairId = ((addJson['added'] as Map)['id']) as String;

      // Seed the journal directly via the in-process beagle_core API so
      // the CLI invocation later actually has data to query / ack.
      final jsonlPath = p.join(cfg.path, 'journal', '$pairId.jsonl');
      final dbPath = p.join(cfg.path, 'journal', '$pairId.db');
      await Directory(p.dirname(jsonlPath)).create(recursive: true);
      final journal = await Journal.open(
        pairId: pairId,
        jsonlPath: jsonlPath,
        dbPath: dbPath,
      );
      await journal.append([
        ChangeEntry(
          journalId: 0,
          pairId: pairId,
          syncRunId: 'r1',
          ts: DateTime.now().toUtc(),
          source: ChangeSource.sync,
          side: ChangeSide.remote,
          kind: ChangeKind.modified,
          path: 'note.md',
          syncStatus: SyncStatus.applied,
          agentVisibility: true,
        ),
        ChangeEntry(
          journalId: 0,
          pairId: pairId,
          syncRunId: 'r1',
          ts: DateTime.now().toUtc(),
          source: ChangeSource.sync,
          side: ChangeSide.remote,
          kind: ChangeKind.created,
          path: 'data.json',
          syncStatus: SyncStatus.applied,
          agentVisibility: true,
        ),
      ]);
      await journal.close();

      // Initial unacked query via the CLI.
      final c1 = jsonOf(await run([
        'changes',
        '--pair', 'memory',
        '--consumer', 'claude-code',
        '--unacked',
      ]));
      expect(c1['count'], 2);
      expect(c1['authoritative'], isTrue);
      final cursor = c1['cursor'] as int;
      final paths = ((c1['changes'] as List)
              .cast<Map>())
          .map((e) => e['path'])
          .toList();
      expect(paths, containsAll(['note.md', 'data.json']));

      // Ack and re-query.
      final ackJson = jsonOf(await run([
        'ack',
        '--pair', 'memory',
        '--consumer', 'claude-code',
        '--cursor', cursor.toString(),
      ]));
      expect(((ackJson['cursor'] as Map)['last_journal_id'] as int), cursor);

      final c2 = jsonOf(await run([
        'changes',
        '--pair', 'memory',
        '--consumer', 'claude-code',
        '--unacked',
      ]));
      expect(c2['count'], 0);

      // changes-since with explicit --since = epoch returns the same items.
      final c3 = jsonOf(await run([
        'changes-since',
        '--pair', 'memory',
        '--since', '2000-01-01T00:00:00Z',
      ]));
      expect((c3['changes'] as List), hasLength(2));

      // .md filter narrows down.
      final c4 = jsonOf(await run([
        'changes',
        '--pair', 'memory',
        '--extensions', 'md',
      ]));
      expect((c4['changes'] as List), hasLength(1));
      expect(((c4['changes'] as List).first as Map)['path'], 'note.md');
    });

    test('ack beyond latest journal id is rejected with CURSOR_MISMATCH',
        () async {
      jsonOf(await run([
        'add',
        '--name', 'p',
        '--local-path', '/x',
        '--remote', 'r',
        '--mode', 'to_remote',
      ]));

      final r = await run([
        'ack',
        '--pair', 'p',
        '--consumer', 'whoever',
        '--cursor', '999',
      ]);
      expect(r.exitCode, isNot(0));
      final err = (r.stderr as String).trim();
      expect(err, contains('CURSOR_MISMATCH'));
    });

    test('pause without running app returns NOT_RUNNING (exit 3)', () async {
      jsonOf(await run([
        'add',
        '--name', 'p',
        '--local-path', '/x',
        '--remote', 'r',
        '--mode', 'to_remote',
      ]));
      final r = await run(['pause', '--pair', 'p']);
      expect(r.exitCode, 3);
      expect(r.stderr.toString(), contains('NOT_RUNNING'));
    });

    test('changes against unknown pair returns PAIR_NOT_FOUND', () async {
      final r = await run([
        'changes',
        '--pair', 'nope',
      ]);
      expect(r.exitCode, isNot(0));
      expect(r.stderr.toString(), contains('PAIR_NOT_FOUND'));
    });
  });
}

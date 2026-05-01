@Tags(['integration'])
library;

import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// rclone v1.60.x in Ubuntu's apt repo predates --fix-case (1.62) and is
/// quirky around bisync. We override the preset for these tests so they
/// work on whatever real rclone is on $PATH.
const _preset = RcloneFlagPreset(
  fixCase: false,
  resilient: false,
  recover: false,
  noSlowHash: false,
  useJsonLog: false,
  statsOneLine: false,
  skipGdocs: false,
  compare: '',
);

const _builder = RcloneCommandBuilder(preset: _preset);

void main() {
  late Directory localRoot;
  late Directory remoteRoot;
  late Directory beagleRoot;
  late SyncPair pair;
  late ConfigDir dir;

  setUp(() async {
    localRoot = await Directory.systemTemp.createTemp('beagle-local-');
    remoteRoot = await Directory.systemTemp.createTemp('beagle-remote-');
    beagleRoot = await Directory.systemTemp.createTemp('beagle-cfg-');
    dir = ConfigDir(beagleRoot);
    await dir.ensure();
    StructuredLogger.memory();

    // Use rclone's `local:` backend rooted at remoteRoot. SyncPair.remoteName
    // is `localtest` and remotePath is the absolute path of remoteRoot.
    pair = SyncPair(
      id: 'p1',
      name: 'memory',
      localPath: localRoot.path,
      remoteName: 'localtest',
      remotePath: remoteRoot.path,
      mode: SyncMode.mirrorFromRemote,
      bootstrapped: true,
    );
  });

  tearDown(() async {
    for (final d in [localRoot, remoteRoot, beagleRoot]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  group('Doctor (real rclone)', () {
    test('rclone present + bisync supported checks pass', () async {
      final doc = Doctor(runner: const RealProcessRunner(), dir: dir);
      final report = await doc.run();
      final byId = {for (final c in report.checks) c.id: c};
      expect(byId['rclone_present']!.passed, isTrue,
          reason: byId['rclone_present']!.detail);
      expect(byId['rclone_bisync_supported']!.passed, isTrue);
      expect(byId['watcher_present']!.passed, isTrue);
      expect(byId['config_dir_writable']!.passed, isTrue);
    });

    test('local: remote is reachable', () async {
      final doc = Doctor(runner: const RealProcessRunner(), dir: dir);
      final report = await doc.run(pairs: [pair]);
      final reach =
          report.checks.firstWhere((c) => c.id == 'pair_remote_reachable:p1');
      expect(reach.passed, isTrue, reason: reach.detail);
    });

    test('non-existent remote produces a failing check', () async {
      final bad = pair.copyWith(); // we'll just force a bogus remote name
      final report = await Doctor(runner: const RealProcessRunner(), dir: dir)
          .run(pairs: [
        SyncPair(
          id: 'bad',
          name: 'bad',
          localPath: localRoot.path,
          remoteName: 'definitely_does_not_exist',
          remotePath: '',
          mode: SyncMode.dryRun,
        ),
        bad,
      ]);
      final reach = report.checks
          .firstWhere((c) => c.id == 'pair_remote_reachable:bad');
      expect(reach.passed, isFalse);
    });
  });

  group('SnapshotService.takeRemote (real rclone lsjson)', () {
    test('lists files placed in the remote root', () async {
      await File(p.join(remoteRoot.path, 'a.md')).writeAsString('aaa');
      await Directory(p.join(remoteRoot.path, 'sub')).create();
      await File(p.join(remoteRoot.path, 'sub', 'b.json'))
          .writeAsString('{}');

      final svc = SnapshotService(
        runner: const RealProcessRunner(),
        builder: _builder,
      );
      final snap = await svc.takeRemote(pair);
      final paths = snap.entries.map((e) => e.path).toList();
      expect(paths, containsAll(['a.md', 'sub/b.json']));
      expect(snap.entries.firstWhere((e) => e.path == 'a.md').size, 3);
    });
  });

  group('SnapshotService.takeLocal (real filesystem walk)', () {
    test('skips ignored dirs and files', () async {
      await File(p.join(localRoot.path, 'kept.md')).writeAsString('k');
      await File(p.join(localRoot.path, '.hidden')).writeAsString('x');
      await Directory(p.join(localRoot.path, '.git')).create();
      await File(p.join(localRoot.path, '.git', 'HEAD')).writeAsString('h');
      await Directory(p.join(localRoot.path, 'node_modules')).create();
      await File(p.join(localRoot.path, 'node_modules', 'pkg.json'))
          .writeAsString('{}');

      final svc = SnapshotService(
        runner: const RealProcessRunner(),
        builder: _builder,
      );
      final snap = await svc.takeLocal(pair);
      final paths = snap.entries.map((e) => e.path).toList();
      expect(paths, contains('kept.md'));
      expect(paths.any((p) => p.startsWith('.git')), isFalse);
      expect(paths.any((p) => p.startsWith('node_modules')), isFalse);
      expect(paths, isNot(contains('.hidden')));
    });
  });

  group('SyncEngine.runOnce mirrorFromRemote (real rclone sync)', () {
    test('mirrors remote → local and journals authoritative changes',
        () async {
      // Seed remote.
      await File(p.join(remoteRoot.path, 'note.md')).writeAsString('hello');
      await File(p.join(remoteRoot.path, 'data.json'))
          .writeAsString('{"x":1}');

      final journal = await Journal.open(
        pairId: pair.id,
        jsonlPath: dir.journalJsonlPath(pair.id),
        dbPath: dir.journalDbPath(pair.id),
      );
      addTearDown(journal.close);

      final engine = SyncEngine(
        runner: const RealProcessRunner(),
        builder: _builder,
        dir: dir,
        snapshotService: SnapshotService(
          runner: const RealProcessRunner(),
          builder: _builder,
        ),
        journal: journal,
        recorder: SyncRunRecorder(),
      );

      final run = await engine.runOnce(
        pair: pair,
        trigger: SyncTrigger(
          reason: SyncTriggerReason.manual,
          requestedAt: DateTime.now().toUtc(),
        ),
      );

      // Local now has the files.
      expect(File(p.join(localRoot.path, 'note.md')).existsSync(), isTrue);
      expect(File(p.join(localRoot.path, 'data.json')).existsSync(), isTrue);

      // Sync run state.
      expect(run.state, SyncRunState.succeeded);
      expect(run.exitCode, 0);

      // Journal has authoritative entries for each file.
      final entries = journal.query();
      final byPath = {for (final e in entries) e.path: e};
      expect(byPath.containsKey('note.md'), isTrue);
      expect(byPath.containsKey('data.json'), isTrue);
      expect(byPath['note.md']!.source, ChangeSource.sync);
      expect(byPath['note.md']!.authoritative, isTrue);
    });

    test('dry-run leaves local empty and journals nothing applied', () async {
      await File(p.join(remoteRoot.path, 'should-not-arrive.md'))
          .writeAsString('x');

      final dryPair = pair.copyWith(mode: SyncMode.dryRun);
      final journal = await Journal.open(
        pairId: dryPair.id,
        jsonlPath: dir.journalJsonlPath(dryPair.id),
        dbPath: dir.journalDbPath(dryPair.id),
      );
      addTearDown(journal.close);
      final engine = SyncEngine(
        runner: const RealProcessRunner(),
        builder: _builder,
        dir: dir,
        snapshotService: SnapshotService(
          runner: const RealProcessRunner(),
          builder: _builder,
        ),
        journal: journal,
        recorder: SyncRunRecorder(),
      );
      final run = await engine.runOnce(
        pair: dryPair,
        trigger: SyncTrigger(
          reason: SyncTriggerReason.manual,
          requestedAt: DateTime.now().toUtc(),
        ),
      );
      expect(run.state, SyncRunState.succeeded);
      expect(File(p.join(localRoot.path, 'should-not-arrive.md')).existsSync(),
          isFalse);
      expect(journal.query(), isEmpty);
    });
  });

  group('FilterGenerator output (consumed by real rclone lsf)', () {
    test('rclone honors the generated filter file', () async {
      // Build a fixture: keep.md, drop.log, .hidden, .git/HEAD
      await File(p.join(remoteRoot.path, 'keep.md')).writeAsString('k');
      await File(p.join(remoteRoot.path, 'drop.log')).writeAsString('d');
      await File(p.join(remoteRoot.path, '.hidden')).writeAsString('h');
      await Directory(p.join(remoteRoot.path, '.git')).create();
      await File(p.join(remoteRoot.path, '.git', 'HEAD')).writeAsString('x');

      final fg = FilterGenerator();
      final ff = fg.generate(const Filters(
        includeExtensions: ['md'],
        ignoreHidden: true,
        ignoreVcs: true,
        ignoreNodeModules: true,
        ignoreCommonBuildDirs: true,
      ));
      final filterPath = p.join(beagleRoot.path, 'filter.txt');
      await fg.writeAtomic(filterPath, ff);

      final r = await const RealProcessRunner().run(
        'rclone',
        [
          'lsf',
          '--recursive',
          '--files-only',
          '--filter-from',
          filterPath,
          'localtest:${remoteRoot.path}',
        ],
      );
      expect(r.exitCode, 0, reason: r.stderr);
      final lines = r.stdout
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines, contains('keep.md'));
      expect(lines, isNot(contains('drop.log')));
      expect(lines, isNot(contains('.hidden')));
      expect(lines.any((l) => l.startsWith('.git')), isFalse);
    });
  });
}

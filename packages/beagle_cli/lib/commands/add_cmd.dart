import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';
import 'package:uuid/uuid.dart';

import '../cli_runner.dart';

class AddCmd extends Command<int> {
  @override
  String get name => 'add';
  @override
  String get description => 'Add a new sync pair.';

  AddCmd() {
    argParser
      ..addOption('name', mandatory: true)
      ..addOption('local-path', mandatory: true)
      ..addOption('remote', mandatory: true, help: 'rclone remote name (without colon)')
      ..addOption('remote-path', defaultsTo: '')
      ..addOption('mode',
          allowed: SyncMode.values.map((m) => m.wire).toList(),
          defaultsTo: SyncMode.dryRun.wire,
          help: 'Default safe choice is dry_run; switch to bidirectional after bootstrap.')
      ..addOption('debounce-ms', defaultsTo: '4000')
      ..addOption('reconcile-seconds', defaultsTo: '600')
      ..addOption('conflict-policy',
          defaultsTo: ConflictPolicy.keepBothSuffix.wire,
          allowed: ConflictPolicy.values.map((c) => c.wire).toList());
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final loader = ConfigLoader(ctx.dir);
    final cfg = await loader.load();
    final pair = SyncPair(
      id: const Uuid().v4(),
      name: argResults!['name'] as String,
      localPath: argResults!['local-path'] as String,
      remoteName: argResults!['remote'] as String,
      remotePath: argResults!['remote-path'] as String,
      mode: SyncMode.fromWire(argResults!['mode'] as String),
      debounceMs: int.parse(argResults!['debounce-ms'] as String),
      reconcileEverySeconds: int.parse(argResults!['reconcile-seconds'] as String),
      conflictPolicy: ConflictPolicy.fromWire(argResults!['conflict-policy'] as String),
    );
    final updated = cfg.copyWith(pairs: [...cfg.pairs, pair]);
    await loader.save(updated);
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'added': pair.toJson(),
    });
    return exitOk;
  }
}

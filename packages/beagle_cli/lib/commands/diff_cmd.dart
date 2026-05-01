import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class DiffCmd extends Command<int> {
  @override
  String get name => 'diff';
  @override
  String get description => 'Diff two snapshots or snapshot vs current state.';

  DiffCmd() {
    argParser
      ..addOption('pair', mandatory: true)
      ..addOption('from',
          allowed: const ['snapshot', 'last-sync'], defaultsTo: 'last-sync')
      ..addOption('to', allowed: const ['snapshot', 'now'], defaultsTo: 'now')
      ..addOption('against',
          allowed: const ['local', 'remote'], defaultsTo: 'local');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();
    final pair = findPair(cfg, argResults!['pair'] as String);
    final side = argResults!['against'] as String;
    final svc = SnapshotService(
      runner: const RealProcessRunner(),
      builder: const RcloneCommandBuilder(),
    );

    final fromTag = argResults!['from'] == 'last-sync' ? 'pre.last' : 'latest';
    final fromSnap =
        await svc.load(ctx.dir.snapshotPath(pair.id, side, fromTag));
    if (fromSnap == null) {
      throw BeagleError(
        BeagleErrorCode.invalidConfig,
        'No baseline snapshot found at ${ctx.dir.snapshotPath(pair.id, side, fromTag)}',
        remedy: 'Run `drive-beagle snapshot --pair ${pair.id} --fresh` first.',
      );
    }
    final Snapshot toSnap;
    if (argResults!['to'] == 'now') {
      toSnap = side == 'local'
          ? await svc.takeLocal(pair)
          : await svc.takeRemote(pair);
    } else {
      final t = await svc.load(ctx.dir.snapshotPath(pair.id, side, 'latest'));
      if (t == null) {
        throw BeagleError(
          BeagleErrorCode.invalidConfig,
          'No "to" snapshot persisted.',
        );
      }
      toSnap = t;
    }
    final diff = SnapshotDiffer().diff(fromSnap, toSnap);
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'pair': {'id': pair.id, 'name': pair.name},
      'side': side,
      'created': diff.created.map((e) => e.toJson()).toList(),
      'modified': diff.modified.map((e) => e.toJson()).toList(),
      'deleted': diff.deleted.map((e) => e.toJson()).toList(),
      'moved': diff.moved
          .map((m) => {'from': m.from.toJson(), 'to': m.to.toJson()})
          .toList(),
    });
    return exitOk;
  }
}

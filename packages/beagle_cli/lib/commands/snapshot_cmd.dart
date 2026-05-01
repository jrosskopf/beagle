import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class SnapshotCmd extends Command<int> {
  @override
  String get name => 'snapshot';
  @override
  String get description => 'Capture or print the current indexed view of a sync pair.';

  SnapshotCmd() {
    argParser
      ..addOption('pair', mandatory: true)
      ..addOption('side',
          allowed: const ['local', 'remote'],
          defaultsTo: 'local',
          help: 'Which side to capture or load.')
      ..addFlag('fresh', defaultsTo: false, help: 'Force a fresh capture.');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();
    final pair = findPair(cfg, argResults!['pair'] as String);
    final side = argResults!['side'] as String;
    final fresh = argResults!['fresh'] as bool;

    final svc = SnapshotService(
      runner: const RealProcessRunner(),
      builder: const RcloneCommandBuilder(),
    );

    Snapshot snap;
    if (fresh) {
      snap = side == 'local'
          ? await svc.takeLocal(pair)
          : await svc.takeRemote(pair);
    } else {
      // Use the most recent persisted snapshot if available, else fresh.
      final loaded = await svc.load(
          ctx.dir.snapshotPath(pair.id, side, 'latest'));
      snap = loaded ??
          (side == 'local'
              ? await svc.takeLocal(pair)
              : await svc.takeRemote(pair));
    }
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'snapshot': snap.toJson(),
    });
    return exitOk;
  }
}

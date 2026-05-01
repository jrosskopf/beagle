import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class LastSyncCmd extends Command<int> {
  @override
  String get name => 'last-sync';
  @override
  String get description => 'Metadata about the last sync run for a pair.';

  LastSyncCmd() {
    argParser.addOption('pair', mandatory: true);
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();
    final pair = findPair(cfg, argResults!['pair'] as String);
    final states = await StateStore(ctx.dir.stateFilePath).load();
    final s = states[pair.id];
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'pair': {'id': pair.id, 'name': pair.name},
      'last_attempt': s?.lastSyncRun?.toJson(),
      'last_success': s?.lastSuccessfulRun?.toJson(),
    });
    return exitOk;
  }
}

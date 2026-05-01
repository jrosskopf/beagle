import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class SyncNowCmd extends Command<int> {
  @override
  String get name => 'sync-now';
  @override
  String get description => 'Trigger an immediate sync run for one pair.';

  SyncNowCmd() {
    argParser
      ..addOption('pair', mandatory: true)
      ..addFlag('bootstrap', defaultsTo: false, help: 'Run bisync --resync (one-time bootstrap).');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cli = await ctx.tryConnect();
    if (cli == null) {
      throw BeagleError(BeagleErrorCode.notRunning, 'drive-beagle is not running.');
    }
    final result = await cli.call('sync_now', {
      'pair': argResults!['pair'],
      'bootstrap': argResults!['bootstrap'],
    });
    await cli.close();
    ctx.emitJson({'schema_version': beagleSchemaVersion, 'result': result});
    return exitOk;
  }
}

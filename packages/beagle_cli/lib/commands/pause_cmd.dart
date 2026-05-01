import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class PauseCmd extends Command<int> {
  @override
  String get name => 'pause';
  @override
  String get description => 'Pause sync globally or for one pair.';

  PauseCmd() {
    argParser.addOption('pair', help: 'Pair id or name; omit to pause globally.');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cli = await ctx.tryConnect();
    if (cli == null) {
      throw BeagleError(
        BeagleErrorCode.notRunning,
        'drive-beagle is not running.',
        remedy: 'Start the app first.',
      );
    }
    final result = await cli.call('pause', {
      if (argResults!['pair'] != null) 'pair': argResults!['pair'],
    });
    await cli.close();
    ctx.emitJson({'schema_version': beagleSchemaVersion, 'result': result});
    return exitOk;
  }
}

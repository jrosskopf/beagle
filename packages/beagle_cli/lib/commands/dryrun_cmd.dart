import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class DryRunCmd extends Command<int> {
  @override
  String get name => 'dry-run';
  @override
  String get description => 'Run a dry-run sync (no remote changes).';

  DryRunCmd() {
    argParser.addOption('pair', mandatory: true);
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cli = await ctx.tryConnect();
    if (cli == null) {
      throw BeagleError(BeagleErrorCode.notRunning, 'drive-beagle is not running.');
    }
    final result = await cli.call('dry_run', {'pair': argResults!['pair']});
    await cli.close();
    ctx.emitJson({'schema_version': beagleSchemaVersion, 'result': result});
    return exitOk;
  }
}

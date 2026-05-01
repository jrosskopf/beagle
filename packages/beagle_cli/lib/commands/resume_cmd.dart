import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class ResumeCmd extends Command<int> {
  @override
  String get name => 'resume';
  @override
  String get description => 'Resume sync globally or for one pair.';

  ResumeCmd() {
    argParser.addOption('pair');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cli = await ctx.tryConnect();
    if (cli == null) {
      throw BeagleError(BeagleErrorCode.notRunning, 'drive-beagle is not running.');
    }
    final result = await cli.call('resume', {
      if (argResults!['pair'] != null) 'pair': argResults!['pair'],
    });
    await cli.close();
    ctx.emitJson({'schema_version': beagleSchemaVersion, 'result': result});
    return exitOk;
  }
}

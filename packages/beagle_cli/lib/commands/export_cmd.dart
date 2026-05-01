import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class ExportCmd extends Command<int> {
  @override
  String get name => 'export-config';
  @override
  String get description => 'Print current config as JSON to stdout.';

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'config': cfg.toJson(),
    });
    return exitOk;
  }
}

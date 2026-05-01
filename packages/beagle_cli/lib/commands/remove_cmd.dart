import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class RemoveCmd extends Command<int> {
  @override
  String get name => 'remove';
  @override
  String get description => 'Remove a sync pair from config (does not delete files).';

  RemoveCmd() {
    argParser.addOption('pair', mandatory: true);
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final loader = ConfigLoader(ctx.dir);
    final cfg = await loader.load();
    final target = findPair(cfg, argResults!['pair'] as String);
    final updated = cfg.copyWith(
      pairs: cfg.pairs.where((p) => p.id != target.id).toList(),
    );
    await loader.save(updated);
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'removed': target.id,
    });
    return exitOk;
  }
}

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class ImportCmd extends Command<int> {
  @override
  String get name => 'import-config';
  @override
  String get description =>
      'Replace current config with JSON read from --file or stdin.';

  ImportCmd() {
    argParser.addOption('file', help: 'Path to JSON file; default stdin.');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final file = argResults!['file'] as String?;
    final raw = file == null
        ? await stdin.transform(const SystemEncoding().decoder).join()
        : await File(file).readAsString();
    final cfg = ConfigLoader.parse(raw);
    await ConfigLoader(ctx.dir).save(cfg);
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'imported_pairs': cfg.pairs.length,
    });
    return exitOk;
  }
}

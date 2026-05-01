import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class DoctorCmd extends Command<int> {
  @override
  String get name => 'doctor';
  @override
  String get description =>
      'Validate dependencies, watch limits, and remote reachability.';

  DoctorCmd() {
    argParser.addFlag('rebuild-index',
        defaultsTo: false,
        help: 'Drop and rebuild the SQLite journal index from JSONL.');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();

    if (argResults!['rebuild-index'] as bool) {
      for (final pair in cfg.pairs) {
        await Journal.rebuildIndex(
          jsonlPath: ctx.dir.journalJsonlPath(pair.id),
          dbPath: ctx.dir.journalDbPath(pair.id),
        );
        stderr.writeln('rebuilt index for ${pair.id}');
      }
    }

    final doctor = Doctor(runner: const RealProcessRunner(), dir: ctx.dir);
    final report = await doctor.run(pairs: cfg.pairs);
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      ...report.toJson(),
    });
    return report.allPassed ? exitOk : exitWatcherFailure;
  }
}

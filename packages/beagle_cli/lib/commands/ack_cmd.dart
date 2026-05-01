import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class AckCmd extends Command<int> {
  @override
  String get name => 'ack';
  @override
  String get description => 'Advance a consumer cursor to a journal id.';

  AckCmd() {
    argParser
      ..addOption('pair', mandatory: true)
      ..addOption('consumer', mandatory: true)
      ..addOption('cursor', mandatory: true,
          help: 'Numeric journal id returned by `drive-beagle changes`.');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();
    final pair = findPair(cfg, argResults!['pair'] as String);

    // Sanity check: the cursor must not exceed the journal's latest id.
    final journal = await Journal.open(
      pairId: pair.id,
      jsonlPath: ctx.dir.journalJsonlPath(pair.id),
      dbPath: ctx.dir.journalDbPath(pair.id),
    );
    final latest = journal.latestSeq;
    await journal.close();

    final requested = int.parse(argResults!['cursor'] as String);
    if (requested > latest) {
      throw BeagleError(
        BeagleErrorCode.cursorMismatch,
        'Requested cursor $requested exceeds latest journal id $latest',
        remedy: 'Re-run `drive-beagle changes` to discover the current cursor.',
      );
    }

    final svc = CursorService(ctx.dir.cursorFilePath);
    final cursor = await svc.ack(
      pairId: pair.id,
      consumer: argResults!['consumer'] as String,
      journalId: requested,
    );
    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'cursor': cursor.toJson(),
    });
    return exitOk;
  }
}

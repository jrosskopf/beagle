import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

/// Backs both `changes` and `changes-since`. The latter requires `--since`.
class ChangesCmd extends Command<int> {
  ChangesCmd({required this.timeBased}) {
    argParser
      ..addOption('pair', mandatory: true)
      ..addOption('consumer', help: 'Cursor consumer name (e.g. claude-code).')
      ..addFlag('unacked', defaultsTo: false)
      ..addOption('cursor',
          help: 'Numeric journal id; equivalent to --since for sequence-based queries.')
      ..addOption('since',
          mandatory: timeBased, help: 'ISO-8601 UTC timestamp.')
      ..addMultiOption('kinds', defaultsTo: const [])
      ..addMultiOption('extensions', defaultsTo: const [])
      ..addOption('limit', defaultsTo: '500')
      ..addFlag('include-tentative',
          defaultsTo: false,
          help: 'Include un-confirmed watcher events. Off by default.');
  }

  final bool timeBased;

  @override
  String get name => timeBased ? 'changes-since' : 'changes';
  @override
  String get description => timeBased
      ? 'Authoritative changes since a specific timestamp (alias of changes --since).'
      : 'Authoritative changes for one sync pair (post-sync truth).';

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();
    final pair = findPair(cfg, argResults!['pair'] as String);

    final journal = await Journal.open(
      pairId: pair.id,
      jsonlPath: ctx.dir.journalJsonlPath(pair.id),
      dbPath: ctx.dir.journalDbPath(pair.id),
    );
    final cursorService = CursorService(ctx.dir.cursorFilePath);
    final svc =
        ChangeQueryService(journal: journal, cursorService: cursorService);

    final kinds = (argResults!['kinds'] as List<String>)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(ChangeKind.fromWire)
        .toSet();
    final exts = (argResults!['extensions'] as List<String>)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s.startsWith('.') ? s : '.$s')
        .toSet();

    final cursorRaw = argResults!['cursor'] as String?;
    final sinceRaw = argResults!['since'] as String?;

    final result = await svc.queryAsJson(
      pair: pair,
      consumer: argResults!['consumer'] as String?,
      unacked: argResults!['unacked'] as bool,
      cursor: cursorRaw == null ? null : int.parse(cursorRaw),
      since: sinceRaw == null ? null : DateTime.parse(sinceRaw),
      kinds: kinds.isEmpty ? null : kinds,
      extensions: exts.isEmpty ? null : exts,
      limit: int.parse(argResults!['limit'] as String),
      includeTentative: argResults!['include-tentative'] as bool,
    );
    await journal.close();

    if (ctx.format == 'jsonl') {
      for (final c in (result['changes'] as List)) {
        ctx.emitJson({
          'schema_version': beagleSchemaVersion,
          'change': c,
        });
      }
    } else {
      ctx.emitJson(result);
    }
    return exitOk;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';
import 'package:path/path.dart' as p;

import '../cli_runner.dart';

class LogsCmd extends Command<int> {
  @override
  String get name => 'logs';
  @override
  String get description => 'Tail structured logs (JSONL).';

  LogsCmd() {
    argParser
      ..addOption('pair', help: 'Filter by pair id.')
      ..addFlag('follow', abbr: 'f', defaultsTo: false);
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final follow = argResults!['follow'] as bool;
    final pairFilter = argResults!['pair'] as String?;

    if (follow) {
      final cli = await ctx.tryConnect();
      if (cli != null) {
        await cli.call('tail_logs', {});
        await for (final n in cli.notifications) {
          if (n['method'] != 'log.update') continue;
          final params = (n['params'] as Map).cast<String, Object?>();
          if (pairFilter != null && params['pair_id'] != pairFilter) continue;
          stdout.writeln(jsonEncode(params));
        }
        return exitOk;
      }
      stderr.writeln('app not running; cannot --follow live logs');
      return exitNotRunning;
    }

    // Static read: stream the most recent log file.
    final dir = Directory(ctx.dir.logsDir);
    if (!await dir.exists()) return exitOk;
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('drive-beagle.'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) return exitOk;
    await for (final line in files.last
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (pairFilter != null) {
        try {
          final j = jsonDecode(line) as Map<String, Object?>;
          if (j['pair_id'] != pairFilter) continue;
        } catch (_) {
          continue;
        }
      }
      stdout.writeln(line);
    }
    return exitOk;
  }
}

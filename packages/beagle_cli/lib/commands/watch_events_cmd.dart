import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class WatchEventsCmd extends Command<int> {
  @override
  String get name => 'watch-events';
  @override
  String get description => 'Stream tentative watcher events as JSONL (requires running app).';

  WatchEventsCmd() {
    argParser.addOption('pair', help: 'Filter by pair id; omit for all pairs.');
  }

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cli = await ctx.tryConnect();
    if (cli == null) {
      throw BeagleError(
        BeagleErrorCode.notRunning,
        'drive-beagle is not running.',
        remedy: 'Start the app to stream live watcher events.',
      );
    }
    await cli.call('subscribe_watch_events', {
      if (argResults!['pair'] != null) 'pair': argResults!['pair'],
    });
    await for (final n in cli.notifications) {
      if (n['method'] != 'watch_events.update') continue;
      final params = (n['params'] as Map).cast<String, Object?>();
      stdout.writeln(jsonEncode({
        'schema_version': beagleSchemaVersion,
        'authoritative': false,
        ...params,
      }));
    }
    return exitOk;
  }
}

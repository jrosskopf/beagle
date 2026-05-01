import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import 'commands/ack_cmd.dart';
import 'commands/add_cmd.dart';
import 'commands/changes_cmd.dart';
import 'commands/diff_cmd.dart';
import 'commands/doctor_cmd.dart';
import 'commands/dryrun_cmd.dart';
import 'commands/export_cmd.dart';
import 'commands/import_cmd.dart';
import 'commands/last_sync_cmd.dart';
import 'commands/logs_cmd.dart';
import 'commands/pause_cmd.dart';
import 'commands/remove_cmd.dart';
import 'commands/resume_cmd.dart';
import 'commands/snapshot_cmd.dart';
import 'commands/status_cmd.dart';
import 'commands/sync_now_cmd.dart';
import 'commands/watch_events_cmd.dart';

/// Exit codes are stable: agents may switch on them.
const exitOk = 0;
const exitUserError = 2;
const exitNotRunning = 3;
const exitRcloneFailure = 4;
const exitWatcherFailure = 5;
const exitJournalCursorError = 6;

Future<int> runCli(List<String> argv) async {
  final runner = CommandRunner<int>('drive-beagle',
      'drive-beagle — desktop sync utility for Google-Drive-backed folders.')
    ..argParser.addOption('config-dir', help: 'Override config dir path.')
    ..argParser.addOption('format',
        defaultsTo: 'json',
        allowed: ['json', 'jsonl', 'table'],
        help: 'Output format.')
    ..argParser.addFlag('quiet', abbr: 'q', defaultsTo: false)
    ..argParser.addFlag('no-color', defaultsTo: false);

  // User commands
  runner.addCommand(DoctorCmd());
  runner.addCommand(StatusCmd());
  runner.addCommand(AddCmd());
  runner.addCommand(RemoveCmd());
  runner.addCommand(PauseCmd());
  runner.addCommand(ResumeCmd());
  runner.addCommand(SyncNowCmd());
  runner.addCommand(DryRunCmd());
  runner.addCommand(LogsCmd());
  runner.addCommand(ExportCmd());
  runner.addCommand(ImportCmd());
  // Agent commands
  runner.addCommand(ChangesCmd(timeBased: false));
  runner.addCommand(ChangesCmd(timeBased: true));
  runner.addCommand(LastSyncCmd());
  runner.addCommand(SnapshotCmd());
  runner.addCommand(DiffCmd());
  runner.addCommand(WatchEventsCmd());
  runner.addCommand(AckCmd());

  try {
    final code = await runner.run(argv);
    return code ?? exitOk;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    return exitUserError;
  } on BeagleError catch (e) {
    stderr.writeln(jsonEncode(e.toJson()));
    return _codeToExit(e.code);
  } on Object catch (e, st) {
    stderr.writeln(jsonEncode({
      'code': 'INTERNAL_ERROR',
      'message': e.toString(),
      'stack': st.toString(),
    }));
    return 1;
  }
}

int _codeToExit(BeagleErrorCode c) => switch (c) {
      BeagleErrorCode.notRunning => exitNotRunning,
      BeagleErrorCode.rcloneFailed ||
      BeagleErrorCode.rcloneMissing ||
      BeagleErrorCode.rcloneVersionTooOld =>
        exitRcloneFailure,
      BeagleErrorCode.watcherMissing ||
      BeagleErrorCode.watchLimitLow =>
        exitWatcherFailure,
      BeagleErrorCode.journalCorrupt ||
      BeagleErrorCode.cursorMismatch =>
        exitJournalCursorError,
      _ => exitUserError,
    };

/// Shared CLI runtime context.
class CliContext {
  CliContext(this.dir, this.format);
  final ConfigDir dir;
  final String format;

  static Future<CliContext> fromGlobals(ArgResults topResults) async {
    final overrideDir = topResults['config-dir'] as String?;
    final dir = ConfigDir.resolve(overrideRoot: overrideDir);
    await dir.ensure();
    StructuredLogger.memory();
    return CliContext(dir, topResults['format'] as String);
  }

  /// Try to connect to the running app; return null if not running.
  Future<ControlClient?> tryConnect() async {
    final cfg = await ConfigLoader(dir).load();
    final socket = cfg.ipcSocketPath ?? dir.defaultIpcSocketPath();
    try {
      return await ControlClient.connect(socket);
    } on BeagleError {
      return null;
    }
  }

  void emitJson(Object obj) {
    if (format == 'jsonl') {
      stdout.writeln(jsonEncode(obj));
    } else {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(obj));
    }
  }
}

/// Find the pair matching `--pair <id-or-name>` in the loaded config.
SyncPair findPair(AppConfig cfg, String idOrName) {
  for (final p in cfg.pairs) {
    if (p.id == idOrName || p.name == idOrName) return p;
  }
  throw BeagleError(
    BeagleErrorCode.pairNotFound,
    'No sync pair matching "$idOrName"',
    remedy: 'List configured pairs with `drive-beagle status`.',
  );
}

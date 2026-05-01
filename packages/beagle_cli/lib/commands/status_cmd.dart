import 'package:args/command_runner.dart';
import 'package:beagle_core/beagle_core.dart';

import '../cli_runner.dart';

class StatusCmd extends Command<int> {
  @override
  String get name => 'status';
  @override
  String get description => 'Show sync pair status (live if app running, otherwise on-disk).';

  @override
  Future<int> run() async {
    final ctx = await CliContext.fromGlobals(globalResults!);
    final cfg = await ConfigLoader(ctx.dir).load();
    final cli = await ctx.tryConnect();
    Map<String, Object?> live = const {};
    if (cli != null) {
      live = (await cli.call('status')) as Map<String, Object?>;
      await cli.close();
    }
    final stateStore = StateStore(ctx.dir.stateFilePath);
    final states = await stateStore.load();

    final pairsJson = [
      for (final p in cfg.pairs)
        {
          'id': p.id,
          'name': p.name,
          'mode': p.mode.wire,
          'enabled': p.enabled,
          'bootstrapped': p.bootstrapped,
          'local_path': p.localPath,
          'remote': p.rcloneRemoteSpec,
          'lifecycle': states[p.id]?.lifecycle.name ?? 'idle',
          'last_sync_run': states[p.id]?.lastSyncRun?.toJson(),
          'last_successful_run': states[p.id]?.lastSuccessfulRun?.toJson(),
          'unacked_authoritative_count':
              states[p.id]?.unackedAuthoritativeCount ?? 0,
        },
    ];

    ctx.emitJson({
      'schema_version': beagleSchemaVersion,
      'app_running': cli != null,
      'live': live,
      'pairs': pairsJson,
    });
    return exitOk;
  }
}

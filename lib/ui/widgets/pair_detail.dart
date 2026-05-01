import 'dart:io';

import 'package:beagle_core/beagle_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../engine.dart';
import '../../engine_host.dart';

class PairDetail extends ConsumerWidget {
  const PairDetail({
    super.key,
    required this.pair,
    required this.state,
    this.dense = false,
  });

  final SyncPair pair;
  final EngineState state;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (pair.id == 'placeholder') {
      return const Center(
        child: Text('Add a pair via the CLI to get started.'),
      );
    }
    final lifecycle =
        state.lifecycleByPair[pair.id] ?? PairLifecycleState.idle;
    final lastRun = state.lastSyncByPair[pair.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(pair.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              _StateBadge(lifecycle),
              const SizedBox(width: 16),
              FilledButton.tonalIcon(
                onPressed: () => ref
                    .read(engineHostProvider)
                    .engine
                    .triggerSync(pair.id, reason: SyncTriggerReason.manual),
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(engineHostProvider)
                    .engine
                    .triggerSync(pair.id,
                        reason: SyncTriggerReason.manual,
                        forceDryRun: true),
                icon: const Icon(Icons.preview),
                label: const Text('Dry run'),
              ),
              if (pair.mode == SyncMode.bidirectional && !pair.bootstrapped)
                FilledButton.icon(
                  onPressed: () => _confirmBootstrap(context, ref),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Bootstrap bisync'),
                ),
              OutlinedButton.icon(
                onPressed: () => _openLocal(),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open folder'),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyRcloneCommand(context),
                icon: const Icon(Icons.terminal),
                label: const Text('Copy rclone cmd'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _kv('Mode', pair.mode.wire),
              _kv('Local', pair.localPath),
              _kv('Remote', pair.rcloneRemoteSpec),
              _kv('Conflict policy', pair.conflictPolicy.wire),
              _kv('Debounce', '${pair.debounceMs} ms'),
              _kv('Reconcile every', '${pair.reconcileEverySeconds} s'),
              const SizedBox(height: 16),
              Text('Last sync run', style: Theme.of(context).textTheme.titleMedium),
              if (lastRun == null)
                const Text('No runs yet')
              else
                ...[
                  _kv('Started', lastRun.startedAt.toLocal().toString()),
                  if (lastRun.endedAt != null)
                    _kv('Ended', lastRun.endedAt!.toLocal().toString()),
                  _kv('State', lastRun.state.wire),
                  _kv('Trigger', lastRun.trigger),
                  _kv('Files', lastRun.counts.total.toString()),
                  if (lastRun.errorMessage != null)
                    _kv('Error', lastRun.errorMessage!),
                ],
            ],
          ),
        ),
      ],
    );
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 140,
                child: Text(k,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  Future<void> _openLocal() async {
    final dir = Directory(pair.localPath);
    if (!await dir.exists()) return;
    await launchUrl(Uri.file(dir.path));
  }

  Future<void> _copyRcloneCommand(BuildContext context) async {
    final builder = const RcloneCommandBuilder();
    final cmd = pair.mode == SyncMode.bidirectional
        ? builder.bisync(pair)
        : pair.mode == SyncMode.toRemote
            ? builder.pushToRemote(pair)
            : builder.mirrorFromRemote(pair, dryRun: pair.mode == SyncMode.dryRun);
    final line = ([cmd.executable, ...cmd.arguments]).join(' ');
    await Clipboard.setData(ClipboardData(text: line));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('rclone command copied to clipboard')),
      );
    }
  }

  Future<void> _confirmBootstrap(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bootstrap bisync?'),
        content: const Text(
          'This will run `rclone bisync --resync` to establish the initial '
          'baseline between local and remote. It is required exactly once '
          'per pair before bidirectional sync can run.\n\n'
          'Make sure both sides contain the files you expect first — '
          'rclone may copy missing files in either direction during resync.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Run bootstrap')),
        ],
      ),
    );
    if (ok ?? false) {
      ref
          .read(engineHostProvider)
          .engine
          .triggerSync(pair.id, reason: SyncTriggerReason.bootstrap);
    }
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge(this.s);
  final PairLifecycleState s;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(s.name, style: const TextStyle(fontSize: 12)),
    );
  }
}

import 'package:beagle_core/beagle_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PairCard extends StatelessWidget {
  const PairCard({
    super.key,
    required this.pair,
    required this.lifecycle,
    required this.lastRun,
    required this.unacked,
    required this.selected,
    required this.onTap,
  });

  final SyncPair pair;
  final PairLifecycleState lifecycle;
  final SyncRun? lastRun;
  final int unacked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(lifecycle, Theme.of(context).colorScheme);
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pair.name,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${pair.mode.wire} • ${_lastRunLabel(lastRun)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (unacked > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unacked',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _colorFor(PairLifecycleState s, ColorScheme cs) =>
      switch (s) {
        PairLifecycleState.idle ||
        PairLifecycleState.watching =>
          Colors.green,
        PairLifecycleState.pending ||
        PairLifecycleState.syncing =>
          cs.primary,
        PairLifecycleState.paused => Colors.grey,
        PairLifecycleState.warning => Colors.orange,
        PairLifecycleState.error => cs.error,
      };

  static String _lastRunLabel(SyncRun? r) {
    if (r == null) return 'never synced';
    final fmt = DateFormat.Hm();
    return 'last ${fmt.format(r.startedAt.toLocal())}';
  }
}

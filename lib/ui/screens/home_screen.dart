import 'package:beagle_core/beagle_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine_host.dart';
import '../widgets/pair_card.dart';
import '../widgets/pair_detail.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.compact});
  final bool compact;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedPairId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(engineStateProvider).valueOrNull;
    if (state == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selected = state.pairs.firstWhere(
      (p) => p.id == _selectedPairId,
      orElse: () => state.pairs.isEmpty
          ? _placeholderPair()
          : state.pairs.first,
    );

    if (widget.compact) {
      return _CompactLayout(state: state, onSelect: _select, selected: selected);
    }
    return _WideLayout(state: state, onSelect: _select, selected: selected);
  }

  void _select(String id) => setState(() => _selectedPairId = id);
}

SyncPair _placeholderPair() => const SyncPair(
      id: 'placeholder',
      name: 'No pairs configured',
      localPath: '',
      remoteName: '',
      remotePath: '',
      mode: SyncMode.dryRun,
      enabled: false,
    );

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.state,
    required this.onSelect,
    required this.selected,
  });
  final EngineState state;
  final void Function(String) onSelect;
  final SyncPair selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('drive-beagle'),
        actions: [
          IconButton(
            tooltip: state.globalPaused ? 'Resume all' : 'Pause all',
            icon: Icon(state.globalPaused ? Icons.play_arrow : Icons.pause),
            onPressed: () {/* TODO global pause */},
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: _PairList(state: state, onSelect: onSelect, selectedId: selected.id),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: PairDetail(pair: selected, state: state)),
        ],
      ),
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.state,
    required this.onSelect,
    required this.selected,
  });
  final EngineState state;
  final void Function(String) onSelect;
  final SyncPair selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ListTile(
              dense: true,
              leading: Icon(Icons.cloud_sync,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('drive-beagle'),
              subtitle: Text(state.globalPaused ? 'paused' : 'running',
                  style: const TextStyle(fontSize: 11)),
            ),
            const Divider(height: 1),
            Expanded(
              child: state.pairs.isEmpty
                  ? const Center(child: Text('Add a sync pair from the CLI.'))
                  : ListView(
                      children: [
                        for (final p in state.pairs)
                          PairCard(
                            pair: p,
                            lifecycle:
                                state.lifecycleByPair[p.id] ?? PairLifecycleState.idle,
                            lastRun: state.lastSyncByPair[p.id],
                            unacked: state.unackedByPair[p.id] ?? 0,
                            selected: p.id == selected.id,
                            onTap: () => onSelect(p.id),
                          ),
                      ],
                    ),
            ),
            if (state.pairs.isNotEmpty)
              SizedBox(
                height: 220,
                child: PairDetail(pair: selected, state: state, dense: true),
              ),
          ],
        ),
      ),
    );
  }
}

class _PairList extends StatelessWidget {
  const _PairList({
    required this.state,
    required this.onSelect,
    required this.selectedId,
  });
  final EngineState state;
  final void Function(String) onSelect;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    if (state.pairs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No sync pairs yet. Add one with:\n\n'
            'drive-beagle add --name memory '
            '--local-path ~/memory --remote gdrive --remote-path memory',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: state.pairs.length,
      itemBuilder: (ctx, i) {
        final p = state.pairs[i];
        return PairCard(
          pair: p,
          lifecycle: state.lifecycleByPair[p.id] ?? PairLifecycleState.idle,
          lastRun: state.lastSyncByPair[p.id],
          unacked: state.unackedByPair[p.id] ?? 0,
          selected: p.id == selectedId,
          onTap: () => onSelect(p.id),
        );
      },
    );
  }
}

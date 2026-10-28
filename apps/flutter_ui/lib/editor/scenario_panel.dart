import 'package:flutter/material.dart';

import 'project_controller.dart';

class ScenarioPanel extends StatefulWidget {
  const ScenarioPanel({super.key, required this.controller});
  final ProjectController controller;
  @override
  State<ScenarioPanel> createState() => _ScenarioPanelState();
}

class _ScenarioPanelState extends State<ScenarioPanel> {
  String? corridor;
  int section = 0;
  int formEpoch = 0;
  String? error;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, s = widget.controller.scenario;
    final corridors = c.payload?['geometry']?['corridors'] as List? ?? [];
    final baseline = c.allocation;
    final after = s.stale ? null : s.payload?['allocation'];
    final enabled = c.result != null && !c.stale && !c.busy && !s.busy;
    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('TEMPORARY SCENARIO'),
                FilterChip(
                  label: const Text('Block floor tiles'),
                  selected: s.blocking,
                  onSelected: enabled
                      ? (value) {
                          s.blocking = value;
                          c.note(
                            value
                                ? 'Click floor tiles on the map to toggle temporary blocks. Entrance stays open.'
                                : 'Scenario tile tool off.',
                          );
                        }
                      : null,
                ),
                FilledButton(
                  onPressed: enabled ? s.apply : null,
                  child: Text(s.busy ? 'Applying scenario…' : 'Apply scenario'),
                ),
                TextButton(
                  onPressed: s.busy
                      ? null
                      : () {
                          s.reset();
                          setState(() => formEpoch++);
                        },
                  child: const Text('Restore baseline'),
                ),
                if (s.busy)
                  TextButton(
                    onPressed: c.engine.cancel,
                    child: const Text('Cancel scenario'),
                  ),
                Text(
                  s.stale
                      ? 'SCENARIO ASSIGNMENTS STALE'
                      : s.result != null
                      ? 'EXACT · full rerun'
                      : 'Baseline',
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 175,
                  child: DropdownButtonFormField<String>(
                    initialValue: corridor,
                    decoration: const InputDecoration(
                      labelText: 'Corridor section',
                    ),
                    items: corridors
                        .map(
                          (r) => DropdownMenuItem(
                            value: r['id'] as String,
                            child: Text(r['id'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: enabled
                        ? (value) => setState(() {
                            corridor = value;
                            section = 0;
                          })
                        : null,
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    key: ValueKey(corridor),
                    initialValue: '0',
                    decoration: const InputDecoration(labelText: 'Path index'),
                    onChanged: (value) => section = int.tryParse(value) ?? -1,
                  ),
                ),
                OutlinedButton(
                  onPressed: enabled && corridor != null
                      ? () {
                          final matches = corridors.where(
                            (r) => r['id'] == corridor,
                          );
                          if (matches.isEmpty) {
                            return;
                          }
                          final path = matches.first['path'] as List;
                          if (section < 0 || section >= path.length) {
                            setState(
                              () => error =
                                  'Path index must be 0–${path.length - 1}.',
                            );
                            return;
                          }
                          final point = path[section];
                          final width = c.settings['corridor_width'] as int;
                          final floor =
                              c.payload!['geometry']['layers']['floor'] as List;
                          final entrance =
                              c.payload!['geometry']['entrance_marker'];
                          for (
                            var y = point['y'] as int;
                            y < (point['y'] as int) + width;
                            y++
                          ) {
                            for (
                              var x = point['x'] as int;
                              x < (point['x'] as int) + width;
                              x++
                            ) {
                              if (y >= 0 &&
                                  y < floor.length &&
                                  x >= 0 &&
                                  x < (floor[y] as String).length &&
                                  floor[y][x] == '1' &&
                                  (x != entrance['x'] || y != entrance['y'])) {
                                s.blocked.add('$x,$y');
                              }
                            }
                          }
                          s.edit();
                          setState(() => error = null);
                        }
                      : null,
                  child: const Text('Block width section'),
                ),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    key: ValueKey('budget-$formEpoch'),
                    initialValue:
                        '${s.budget ?? c.settings['threat_budget'] ?? ''}',
                    decoration: const InputDecoration(
                      labelText: 'Scenario budget',
                    ),
                    onFieldSubmitted: (value) {
                      final n = BigInt.tryParse(value);
                      if (n == null ||
                          n.isNegative ||
                          n > BigInt.parse('9223372036854775807')) {
                        setState(
                          () => error = 'Enter a nonnegative int64 budget.',
                        );
                        return;
                      }
                      s.budget = n;
                      s.edit();
                    },
                  ),
                ),
                if (c.selectedRoom != null) ...[
                  FilterChip(
                    label: Text('Disable ${c.selectedRoom}'),
                    selected: s.disabled.contains(c.selectedRoom),
                    onSelected: enabled
                        ? (value) {
                            if (value) {
                              s.disabled.add(c.selectedRoom!);
                            } else {
                              s.disabled.remove(c.selectedRoom);
                            }
                            s.edit();
                          }
                        : null,
                  ),
                  SizedBox(
                    width: 145,
                    child: TextFormField(
                      key: ValueKey('capacity-${c.selectedRoom}-$formEpoch'),
                      initialValue:
                          '${s.capacities[c.selectedRoom] ?? (s.payload?['geometry']?['rooms'] as List? ?? []).where((r) => r['id'] == c.selectedRoom).map((r) => r['capacity']).firstOrNull ?? 0}',
                      decoration: const InputDecoration(
                        labelText: 'Scenario capacity',
                      ),
                      onFieldSubmitted: (value) {
                        final n = int.tryParse(value);
                        if (n == null || n < 0 || n > 262144) {
                          setState(() => error = 'Capacity must be 0–262144.');
                          return;
                        }
                        s.capacities[c.selectedRoom!] = n;
                        s.edit();
                      },
                    ),
                  ),
                ],
              ],
            ),
            Text(error ?? s.message, style: const TextStyle(fontSize: 11)),
            Text(
              'Blocks: ${s.blocked.length} · Room disable affects encounters only. Select a room for capacity/disable controls.',
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              'Baseline → scenario: reachable room hubs ${c.rooms.length} → ${s.stale ? 'pending' : s.metadata['reachable_rooms'] ?? c.rooms.length}; packs ${baseline?['assignments']?.length ?? 0} → ${after?['assignments']?.length ?? 'pending'}; score ${baseline?['total_score'] ?? 0} → ${after?['total_score'] ?? 'pending'}; threat ${baseline?['total_threat'] ?? 0} → ${after?['total_threat'] ?? 'pending'}.',
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              'Baseline allocation ${_total(c.analysisMetrics['allocation']?['timings_us'])} µs · Scenario connectivity ${s.metadata['timings_us']?['connectivity'] ?? '—'} µs / total ${s.metadata['timings_us']?['total'] ?? '—'} µs (wall clock).',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

String _total(dynamic timings) => timings is Map
    ? timings.values
          .whereType<num>()
          .fold<num>(0, (a, b) => a + b)
          .toStringAsFixed(1)
    : '—';

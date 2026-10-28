import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analysis_controller.dart';
import 'exact_json.dart';
import 'files.dart';
import 'project_controller.dart';

class AnalyzePanel extends StatefulWidget {
  const AnalyzePanel({super.key, required this.controller});
  final ProjectController controller;
  @override
  State<AnalyzePanel> createState() => _AnalyzePanelState();
}

class _AnalyzePanelState extends State<AnalyzePanel> {
  String tab = 'Trace';
  BenchmarkAxis axis = BenchmarkAxis.packs;
  final values = TextEditingController(text: '12,13,14'),
      repeats = TextEditingController(text: '3'),
      seed = TextEditingController(text: '42');
  String? error;
  ProjectController get c => widget.controller;
  @override
  void dispose() {
    values.dispose();
    repeats.dispose();
    seed.dispose();
    super.dispose();
  }

  Widget small(String text) => Text(text, style: const TextStyle(fontSize: 11));
  void inspect(String text) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raw analysis data'),
        content: SizedBox(
          width: 720,
          height: 450,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            child: const Text('Copy JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> export() async {
    final files = ProjectFiles();
    try {
      await files.save(c.benchmarks.rawJson, 'dungeon-benchmark.json', true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      files.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = c.playback;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DropdownButton<String>(
                value: tab,
                items: [
                  for (final t in [
                    'Trace',
                    'BSP tree',
                    'DP inspector',
                    'Metrics',
                    'Benchmarks',
                  ])
                    DropdownMenuItem(
                      value: t,
                      child: Text(t, style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (v) => setState(() => tab = v!),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: small(
                  '${c.analysisOutcome}${c.stale ? ' · previous input' : ''}',
                ),
              ),
            ],
          ),
          SizedBox(
            height: 190,
            child: SingleChildScrollView(
              child: switch (tab) {
                'Trace' => trace(),
                'BSP tree' => tree(),
                'DP inspector' => dp(),
                'Metrics' => metrics(),
                _ => benchmarks(),
              },
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final key in [
                'mask',
                'partition bounds',
                'room IDs',
                'capacities',
                'doors',
                'connectivity',
                'assignments',
              ])
                FilterChip(
                  label: Text(key, style: const TextStyle(fontSize: 10)),
                  selected: c.overlays.contains(key),
                  onSelected: (_) => c.toggleOverlay(key),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          small(
            'Run ${p.runId} · editor revision ${p.revision} · ${p.events.length} events${p.truncated ? ' · TRUNCATED: ${p.dropped} omitted' : ''}. Full workloads use summaries. Replay stores one bounded immutable trace; seeking uses its exact event index, no engine rerun.',
          ),
        ],
      ),
    );
  }

  Widget trace() {
    final p = c.playback, event = c.playback.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: p.playing ? 'Pause trace' : 'Play trace',
              onPressed: p.events.isEmpty || c.stale
                  ? null
                  : () => p.playing ? p.pause() : p.play(),
              icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: 'Step trace',
              onPressed: p.events.isEmpty ? null : p.step,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: 'Restart trace',
              onPressed: p.restart,
              icon: const Icon(Icons.replay),
            ),
            small('${p.cursor}/${p.events.length}'),
            const SizedBox(width: 10),
            DropdownButton<double>(
              value: p.speed,
              items: [
                for (final s in [.5, 1.0, 4.0, 16.0, 60.0])
                  DropdownMenuItem(value: s, child: small('$s events/s')),
              ],
              onChanged: (v) => p.setSpeed(v!),
            ),
            TextButton(
              onPressed: () => inspect(encodeExact(p.events)),
              child: const Text('Inspect trace JSON'),
            ),
          ],
        ),
        Slider(
          value: p.cursor.toDouble(),
          max: p.events.isEmpty ? 1 : p.events.length.toDouble(),
          onChanged: p.events.isEmpty ? null : (v) => p.seek(v.round()),
        ),
        small(
          event == null
              ? 'Step to inspect actual split, preserved fixed room, placement, connection and reconstruction events.'
              : encodeExact(event),
        ),
        if (event?['event']?['kind'] == 'fixed_reserved')
          small(
            'Preserved source feature: this fixed room was reserved before BSP search; it is not a generated leaf.',
          ),
        if (c.allocation != null)
          small(
            'Score ${c.allocation!['total_score']} · threat ${c.allocation!['total_threat']} · ${(c.allocation!['assignments'] as List).length} reconstructed pack assignments.',
          ),
      ],
    );
  }

  Widget tree() {
    final nodes = c.payload?['layout']?['partitions'] as List? ?? [];
    final byId = {for (final n in nodes) n['id']: n};
    int depth(dynamic node) {
      var d = 0;
      var parent = node['parent'];
      while (parent != -1 && d < 64) {
        d++;
        parent = byId[parent]?['parent'] ?? -1;
      }
      return d;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        small(
          'Final accepted BSP tree. Select a region to highlight its bounds on the map; map clicks select their containing leaf.',
        ),
        if (nodes.length > 256)
          small(
            "Showing first 256 of ${nodes.length} tree nodes. Select other regions directly on the map.",
          ),
        for (final n in nodes.take(256))
          Padding(
            padding: EdgeInsets.only(left: depth(n) * 12.0),
            child: TextButton(
              onPressed: () => c.selectPartition(n['id'] as int),
              child: Text(
                '${c.selectedPartition == n['id'] ? '▶ ' : ''}Region ${n['id']} · ${n['axis']} ${n['cut']} · ${n['room_id'] == '' ? '${n['requested_rooms']} requested' : n['room_id']}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        small(
          'Preserved fixed features (separate from generated leaves): ${c.rooms.where((r) => c.roomFixed(r['id'] as String)).map((r) => r['id']).join(', ')}',
        ),
      ],
    );
  }

  Widget dp() {
    final events = c.playback.events
        .take(c.playback.cursor)
        .where((e) => e['stage'] == 'allocation')
        .toList();
    final order =
        c.result?.document['stages']?['allocation']?['pack_bit_order'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        small(
          'Bit order: ${order ?? 'not available'}. Candidate events are only actual examined submasks: mask = used inventory, subset = candidate for this room, predecessor = mask XOR subset. The solver short-circuits at its first feasible predecessor.',
        ),
        small(
          'Detailed candidates require ≤6 active packs and ≤8 rooms; otherwise room summaries and actual reconstruction decisions are shown. Truncation can omit transitions.',
        ),
        for (final e in events.skip(
          (events.length - 30).clamp(0, events.length),
        ))
          SelectableText(
            '${e['sequence']} · ${e['event']['kind']} · room ${e['event']['room_id']} · mask ${e['event']['mask']} · subset ${e['event']['subset']} · predecessor ${(e['event']['mask'] as int? ?? 0) ^ (e['event']['subset'] as int? ?? 0)}',
            style: const TextStyle(fontSize: 11),
          ),
      ],
    );
  }

  Widget metrics() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      small(
        'Stage timings are steady-clock wall measurements including validation, tracing and cooperative worker yields. Trace emission is a nested measurement, not an additive phase. JSON dump serialization and bridge wall duration have separate labels. Rendering and playback are excluded from native stage timers. Storage is logical vector capacity, not process RSS.',
      ),
      SelectableText(
        encodeExact(c.analysisMetrics),
        style: const TextStyle(fontSize: 11),
      ),
      TextButton(
        onPressed: () => inspect(encodeExact(c.analysisMetrics)),
        child: const Text('Inspect metrics JSON'),
      ),
    ],
  );
  Widget field(String label, TextEditingController controller, double width) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label),
          style: const TextStyle(fontSize: 11),
        ),
      );
  Widget benchmarks() {
    final b = c.benchmarks, summary = c.benchmarks.summary;
    BenchmarkConfig? proposed;
    String preview;
    try {
      proposed = BenchmarkConfig(
        axis: axis,
        values: values.text.split(',').map((v) => int.parse(v.trim())).toList(),
        repeats: int.parse(repeats.text),
        seed: int.parse(seed.text),
      );
      proposed.validate();
      preview =
          'Workload preview: ${proposed.values.length} points x ${proposed.repeats} repeats = ${proposed.jobs} sequential jobs; seed ${proposed.seed}. Maximum 40 jobs; 60 raw records retained.';
    } catch (e) {
      proposed = null;
      preview =
          'Invalid workload: $e No jobs will start; maximum 8 points x 5 repeats = 40 jobs.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        small(
          'Controlled rectangle fixture v1: one axis varies; other axes stay at 150×150, 16 rooms, 12 packs. Rooms 4–8 tiles, no fixed features, tracing disabled. Each repeat uses the same seed. Area points must be perfect squares (64–512 tile sides). Default 1000-attempt/100-million-work/30-second budgets apply. Isolated worker; no editor result replacement. At most 40 jobs/batch and 60 raw records retained.',
        ),
        small(preview),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<BenchmarkAxis>(
              value: axis,
              items: [
                for (final a in BenchmarkAxis.values)
                  DropdownMenuItem(value: a, child: small(a.name)),
              ],
              onChanged: b.running
                  ? null
                  : (v) => setState(() {
                      axis = v!;
                      values.text = switch (axis) {
                        BenchmarkAxis.area => '10000,22500,40000',
                        BenchmarkAxis.rooms => '10,16,20',
                        BenchmarkAxis.packs => '12,13,14',
                      };
                    }),
            ),
            field('Axis points', values, 170),
            field('Repeats', repeats, 70),
            field('Seed', seed, 80),
            FilledButton(
              onPressed: b.running || c.canonical.isEmpty || proposed == null
                  ? null
                  : () {
                      try {
                        final config = BenchmarkConfig(
                          axis: axis,
                          values: values.text
                              .split(',')
                              .map((v) => int.parse(v.trim()))
                              .toList(),
                          repeats: int.parse(repeats.text),
                          seed: int.parse(seed.text),
                        );
                        config.validate();
                        setState(() => error = null);
                        unawaited(b.run(c.canonical, config));
                      } catch (e) {
                        setState(() => error = '$e');
                      }
                    },
              child: const Text('Run benchmark'),
            ),
            TextButton(
              onPressed: b.running ? () => unawaited(b.cancel()) : null,
              child: const Text('Cancel benchmark'),
            ),
          ],
        ),
        if (error != null) small(error!),
        small('${b.status} · ${b.completed}/${b.total}'),
        if (b.running)
          LinearProgressIndicator(
            value: b.total == 0 ? null : b.completed / b.total,
          ),
        if (summary.isNotEmpty)
          SizedBox(
            height: 100,
            child: CustomPaint(
              size: const Size(double.infinity, 100),
              painter: _BenchmarkChart(
                summary,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        for (final s in summary)
          small(
            '${s['label']}: median ${(s['median_ms'] as double).toStringAsFixed(2)} ms · range ${(s['min_ms'] as double).toStringAsFixed(2)}–${(s['max_ms'] as double).toStringAsFixed(2)} ms · n=${s['n']} successes (native stages total; latest batch only)',
          ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => inspect(b.rawJson),
              child: const Text('Inspect benchmark raw JSON'),
            ),
            TextButton(
              onPressed: b.records.isEmpty ? null : () => unawaited(export()),
              child: const Text('Export benchmark JSON'),
            ),
          ],
        ),
      ],
    );
  }
}

class _BenchmarkChart extends CustomPainter {
  _BenchmarkChart(this.points, this.color);
  final List<Map<String, dynamic>> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final max = points.fold<double>(
      1,
      (v, p) => v > (p['max_ms'] as double) ? v : p['max_ms'] as double,
    );
    final width = size.width / points.length;
    for (var i = 0; i < points.length; i++) {
      final p = points[i], x = width * (i + .5);
      double y(String k) =>
          size.height - 8 - (p[k] as double) / max * (size.height - 16);
      canvas.drawRect(
        Rect.fromLTRB(
          x - width * .25,
          y('median_ms'),
          x + width * .25,
          size.height - 8,
        ),
        Paint()..color = color.withValues(alpha: .5),
      );
      canvas.drawLine(
        Offset(x, y('min_ms')),
        Offset(x, y('max_ms')),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_BenchmarkChart old) => true;
}

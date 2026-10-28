import 'dart:async';
import 'dart:convert';

import 'package:dungeon_architect/editor/analysis_controller.dart';
import 'package:dungeon_architect/editor/analysis_panel.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'project_controller_test.dart' show FakeEngine, source;

Map<String, dynamic> event(int sequence) => {
  'schema_version': 1,
  'run_id': 11,
  'input_revision': 'fnv1a32-123',
  'sequence': sequence,
  'stage': 'generation',
  'affected_ids': ['room-1'],
  'event': {
    'kind': 'place',
    'bounds': {'x': sequence, 'y': 1, 'width': 4, 'height': 4},
  },
};

class TelemetryEngine extends FakeEngine {
  Completer<Map<String, dynamic>>? pendingTrace;
  bool traceRequested = false;
  @override
  Future<Map<String, dynamic>> trace({int cursor = 0, int count = 128}) async {
    traceRequested = true;
    return pendingTrace == null
        ? {
            'run_id': 11,
            'events': [event(0)],
            'next_cursor': 1,
            'total': 1,
          }
        : pendingTrace!.future;
  }
}

class BenchmarkEngine extends Engine {
  final inputs = <Map<String, dynamic>>[];
  final capacities = <int>[];
  final results = <EngineResult>[];
  final times = <double>[1000, 9000, 3000, 5000];
  Completer<EngineResult>? pending;
  bool opened = false, inFlight = false;
  int cancelledCalls = 0, closeCalls = 0;
  @override
  Future<void> open() async {
    opened = true;
  }

  @override
  Future<EngineResult> run(
    String raw, {
    EngineOperation operation = EngineOperation.run,
    int maxEvents = 256,
    bool detailedTrace = false,
  }) async {
    expect(opened, true);
    expect(inFlight, false, reason: 'No concurrent jobs in one worker');
    inFlight = true;
    inputs.add(jsonDecode(raw) as Map<String, dynamic>);
    capacities.add(maxEvents);
    try {
      return pending != null
          ? await pending!.future
          : results.isEmpty
          ? const EngineResult('', {'outcome': 'success', 'optimal': true})
          : results.removeAt(0);
    } finally {
      inFlight = false;
    }
  }

  @override
  Future<Map<String, dynamic>> metrics() async => {
    'generation': {
      'timings_us': {'search': times[(inputs.length - 1) % times.length]},
    },
    'routing': {
      'timings_us': {'routing': 1000},
    },
    'allocation': {
      'timings_us': {'dp': 2000},
    },
    'instrumentation': {
      'engine_version': 'test-1',
      'build_mode': 'test',
      'environment': 'fake-worker',
    },
  };
  @override
  Future<void> cancel() async {
    cancelledCalls++;
    if (pending != null && !pending!.isCompleted) {
      pending!.complete(
        const EngineResult('', {'outcome': 'cancelled', 'optimal': false}),
      );
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

void main() {
  test(
    'new benchmark batch does not pool medians across different seeds',
    () async {
      final c = BenchmarkController(engineFactory: BenchmarkEngine.new);
      addTearDown(c.dispose);
      await c.run(
        source,
        const BenchmarkConfig(
          axis: BenchmarkAxis.packs,
          values: [12],
          repeats: 2,
          seed: 1,
        ),
      );
      await c.run(
        source,
        const BenchmarkConfig(
          axis: BenchmarkAxis.packs,
          values: [12],
          repeats: 2,
          seed: 2,
        ),
      );
      expect(c.records.length, 4);
      expect(c.summary.single['n'], 2);
      expect(c.records.map((r) => r['seed']), [1, 1, 2, 2]);
    },
  );
  testWidgets(
    'Analyze exposes optional overlays, linked BSP and real trace inspection',
    (tester) async {
      final c = ProjectController(
        engine: TelemetryEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      c.result!.document['result']['layout']['partitions'] = [
        {
          'id': 0,
          'parent': -1,
          'axis': 'leaf',
          'cut': 0,
          'room_id': 'room-1',
          'requested_rooms': 1,
          'bounds': {'x': 1, 'y': 1, 'width': 4, 'height': 4},
        },
      ];
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: Listenable.merge([c, c.playback, c.benchmarks]),
              builder: (_, child) => AnalyzePanel(controller: c),
            ),
          ),
        ),
      );
      expect(find.byType(FilterChip), findsNWidgets(7));
      await tester.tap(find.widgetWithText(FilterChip, 'doors'));
      await tester.pump();
      expect(c.overlays, contains('doors'));
      await tester.tap(find.byTooltip('Step trace'));
      await tester.pump();
      expect(c.playback.cursor, 1);
      await tester.tap(find.text('Inspect trace JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('fnv1a32-123'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trace').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('BSP tree').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Region 0').first);
      await tester.pump();
      expect(c.selectedPartition, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'playback controls bound time, restart and never mutate solver events',
    (tester) async {
      final trace = TracePlayback();
      addTearDown(trace.dispose);
      final original = List.generate(5, event);
      final before = jsonEncode(original);
      trace.load(original, revision: 8, runId: 11);
      trace.step();
      expect(trace.cursor, 1);
      expect(trace.current!['sequence'], 0);
      trace.play();
      await tester.pump(const Duration(milliseconds: 500));
      trace.pause();
      final paused = trace.cursor;
      await tester.pump(const Duration(seconds: 2));
      expect(trace.cursor, paused);
      trace.setSpeed(60);
      trace.play();
      await tester.pump(const Duration(seconds: 1));
      expect(trace.cursor, 5);
      expect(trace.playing, false);
      trace.restart();
      expect(trace.cursor, 0);
      expect(trace.current, isNull);
      trace.seek(-1);
      expect(trace.cursor, 0);
      trace.seek(999);
      expect(trace.cursor, 5);
      expect(jsonEncode(original), before);
    },
  );
  test('playback owns a deeply immutable bounded event snapshot', () {
    final trace = TracePlayback();
    addTearDown(trace.dispose);
    final original = List.generate(4100, event);
    trace.load(original, revision: 2, runId: 11, dropped: 3);
    expect(trace.events.length, 4096);
    expect(trace.truncated, true);
    expect(trace.dropped, 7);
    original[0]['event']['bounds']['x'] = 999;
    expect(trace.events.first['event']['bounds']['x'], 0);
    expect(
      () => trace.events.first['event']['bounds']['x'] = 77,
      throwsUnsupportedError,
    );
    expect(
      () => (trace.events.first['affected_ids'] as List).add('injected'),
      throwsUnsupportedError,
    );
    trace.step();
    trace.play();
    trace.load([event(0)], revision: 3, runId: 12);
    expect(trace.playing, false);
    expect(trace.cursor, 0);
    expect(trace.runId, 12);
  });
  test(
    'controlled benchmark independently varies area, room count and pack count',
    () {
      final original = jsonDecode(source);
      for (final axis in BenchmarkAxis.values) {
        final values = switch (axis) {
          BenchmarkAxis.area => [4096, 22500],
          BenchmarkAxis.rooms => [10, 20],
          BenchmarkAxis.packs => [12, 14],
        };
        final config = BenchmarkConfig(axis: axis, values: values, seed: 123);
        for (final value in values) {
          final project = jsonDecode(benchmarkProject(source, config, value));
          final s = project['source']['settings'];
          expect(s['seed'], 123);
          expect(s['room_count'], axis == BenchmarkAxis.rooms ? value : 16);
          expect(
            project['source']['packs'].length,
            axis == BenchmarkAxis.packs ? value : 12,
          );
          expect(
            s['columns'] * s['rows'],
            axis == BenchmarkAxis.area ? value : 22500,
          );
          expect(project['source']['rooms'], isEmpty);
          expect(project['source']['allowed_mask'].length, s['rows']);
        }
      }
      expect(jsonDecode(source), original);
    },
  );
  test(
    'invalid benchmark workloads are rejected before creating a worker',
    () async {
      var workers = 0;
      final c = BenchmarkController(
        engineFactory: () {
          workers++;
          return BenchmarkEngine();
        },
      );
      addTearDown(c.dispose);
      for (final config in [
        const BenchmarkConfig(axis: BenchmarkAxis.packs, values: [15]),
        const BenchmarkConfig(axis: BenchmarkAxis.rooms, values: [1]),
        const BenchmarkConfig(axis: BenchmarkAxis.area, values: [262145]),
        const BenchmarkConfig(axis: BenchmarkAxis.area, values: [4097]),
        const BenchmarkConfig(
          axis: BenchmarkAxis.packs,
          values: [12],
          repeats: 1,
        ),
        const BenchmarkConfig(
          axis: BenchmarkAxis.packs,
          values: [12],
          seed: -1,
        ),
      ]) {
        await expectLater(c.run(source, config), throwsFormatException);
      }
      expect(workers, 0);
      expect(c.running, false);
    },
  );
  test('benchmarks run sequential fixed seeds with honest success-only median and spread', () async {
    final engine = BenchmarkEngine()
      ..results.addAll([
        const EngineResult('', {'outcome': 'success', 'optimal': true}),
        const EngineResult('', {
          'outcome': 'search_exhausted',
          'optimal': false,
        }),
        const EngineResult('', {'outcome': 'success', 'optimal': true}),
        const EngineResult('', {'outcome': 'success', 'optimal': true}),
      ]);
    final c = BenchmarkController(engineFactory: () => engine);
    addTearDown(c.dispose);
    await c.run(
      source,
      const BenchmarkConfig(
        axis: BenchmarkAxis.packs,
        values: [12],
        repeats: 4,
        seed: 42,
      ),
    );
    expect(c.completed, 4);
    expect(c.total, 4);
    expect(c.running, false);
    expect(engine.closeCalls, 1);
    expect(
      engine.inputs.length,
      4,
      reason: 'Failed fixed seed is recorded once; no hidden retries',
    );
    expect(
      engine.inputs.map((p) => p['source']['settings']['seed']),
      everyElement(42),
    );
    expect(engine.capacities, everyElement(0));
    expect(c.summary.single['n'], 3);
    expect(c.summary.single['median_ms'], 6);
    expect(c.summary.single['min_ms'], 4);
    expect(c.summary.single['max_ms'], 8);
    final exported = jsonDecode(c.rawJson);
    expect(exported['schema_version'], 1);
    expect(exported['records'].length, 4);
    expect(exported['records'][1]['outcome'], 'search_exhausted');
    expect(exported['records'][0]['parameters']['seed'], 42);
    expect(
      exported['records'][0]['metrics']['instrumentation']['build_mode'],
      'test',
    );
  });
  test(
    'benchmark cancellation stops later points and preserves completed records',
    () async {
      final engine = BenchmarkEngine()..pending = Completer<EngineResult>();
      final c = BenchmarkController(engineFactory: () => engine);
      addTearDown(c.dispose);
      final running = c.run(
        source,
        const BenchmarkConfig(axis: BenchmarkAxis.packs, values: [12, 13, 14]),
      );
      while (engine.inputs.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await c.run(
        source,
        const BenchmarkConfig(axis: BenchmarkAxis.rooms, values: [10]),
      );
      await c.cancel();
      await running;
      expect(engine.inputs.length, 1);
      expect(engine.cancelledCalls, 1);
      expect(engine.closeCalls, 1);
      expect(c.cancelled, true);
      expect(c.running, false);
      expect(c.completed, lessThan(c.total));
      expect(c.records.single['outcome'], 'cancelled');
      expect(c.summary, isEmpty);
    },
  );
  test(
    'benchmark history and exported raw records stay bounded at60',
    () async {
      final c = BenchmarkController(engineFactory: BenchmarkEngine.new);
      addTearDown(c.dispose);
      for (var batch = 0; batch < 3; batch++) {
        await c.run(
          source,
          BenchmarkConfig(
            axis: BenchmarkAxis.packs,
            values: const [0, 1, 2, 3, 4, 5, 6, 7],
            repeats: 3,
            seed: batch,
          ),
        );
      }
      expect(c.records.length, 60);
      expect(jsonDecode(c.rawJson)['records'].length, 60);
      expect(c.records.first['seed'], 0);
      expect(c.records.first['value'], 4);
      expect(c.records.last['seed'], 2);
      expect(c.records.last['value'], 7);
    },
  );
  test(
    'late trace response after input edit cannot replace accepted analysis',
    () async {
      final engine = TelemetryEngine();
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      final oldEvents = c.playback.events, oldRun = c.playback.runId;
      engine.pendingTrace = Completer();
      engine.traceRequested = false;
      final run = c.run();
      while (!engine.traceRequested) {
        await Future<void>.delayed(Duration.zero);
      }
      c.editSetting(
        'seed',
        '99',
        min: BigInt.zero,
        max: BigInt.from(4294967295),
      );
      engine.pendingTrace!.complete({
        'run_id': 22,
        'events': [event(1)],
        'next_cursor': 1,
        'total': 1,
      });
      await run;
      expect(c.playback.events, same(oldEvents));
      expect(c.playback.runId, oldRun);
    },
  );
  testWidgets(
    'view switch and stale edits pause playback without changing output',
    (tester) async {
      final c = ProjectController(
        engine: TelemetryEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      final accepted = c.result, canonical = c.canonical;
      c.switchView(EditorView.analyze);
      c.playback.play();
      c.switchView(EditorView.design);
      expect(c.playback.playing, false);
      c.switchView(EditorView.analyze);
      c.playback.play();
      c.editSetting(
        'seed',
        '99',
        min: BigInt.zero,
        max: BigInt.from(4294967295),
      );
      expect(c.playback.playing, false);
      expect(c.result, same(accepted));
      expect(canonical, source);
      await tester.pump();
    },
  );
}

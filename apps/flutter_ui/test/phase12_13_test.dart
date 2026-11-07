import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:dungeon_architect/editor/analysis_controller.dart';
import 'package:dungeon_architect/editor/preview.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/editor/trace_explanations.dart';
import 'package:dungeon_architect/engine/engine.dart';
import 'package:dungeon_architect/main.dart';
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
  test('DP reconstruction reports the recorded post-assignment remainder', () {
    final record = {
      'stage': 'allocation',
      'event': {
        'kind': 'reconstruct',
        'room_id': 'room-2',
        'mask': 1,
        'subset': 2,
      },
    };
    final result = {
      'stages': {
        'allocation': {
          'pack_bit_order': ['archer', 'guard'],
        },
      },
    };
    final decision = describeTrace(record, result)!;
    expect(decision.$1, 'Assignment reconstructed');
    expect(decision.$2, contains('guard'));
    expect(decision.$2, contains('room-2'));
    expect(
      decision.$2,
      contains('Inventory before 3 · assigned subset 2 · remaining 1.'),
    );
  });

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
    'Analyze shows only the trace ribbon above a pannable and zoomable map',
    (tester) async {
      final c = ProjectController(
        engine: TelemetryEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      c.result!.document['result']['layout']['rooms'][0].addAll({
        'name': 'Study',
        'role': 'normal',
        'lock_position': false,
      });
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(DungeonArchitectApp(controller: c));
      await tester.tap(find.text('Analyze'));
      await tester.pump();
      expect(find.text('All algorithms'), findsOneWidget);
      for (final removed in [
        'Advanced details',
        'Final BSP tree',
        'Exact DP details',
        'Apply scenario',
        'Explorer',
        'Inspector',
      ]) {
        expect(find.text(removed), findsNothing);
      }
      await tester.tap(find.byTooltip('Next'));
      await tester.pump();
      expect(c.playback.cursor, 1);
      expect(find.textContaining('Room generation (BSP) ·'), findsOneWidget);
      final canvas = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is CanvasPainter,
      );
      expect(tester.getSize(canvas).width, 1600);
      expect(tester.getSize(canvas).height, greaterThan(690));
      final painter =
          tester.widget<CustomPaint>(canvas).painter as CanvasPainter;
      final origin = painter.camera.origin;
      final scale = painter.camera.scale;
      await tester.drag(
        canvas,
        const Offset(75, 31),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(painter.camera.origin, origin + const Offset(75, 31));
      expect(c.playback.cursor, 1);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(painter.camera.scale, greaterThan(scale));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'playback controls bound time, restart and never mutate solver events',
    (tester) async {
      final start = tester.binding.clock.now();
      final trace = TracePlayback(
        elapsed: () => tester.binding.clock.now().difference(start),
      );
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
  testWidgets('trace pacing follows elapsed time, including batched speeds', (
    tester,
  ) async {
    final start = tester.binding.clock.now();
    final trace = TracePlayback(
      elapsed: () => tester.binding.clock.now().difference(start),
    );
    addTearDown(trace.dispose);
    trace.load(List.generate(120, event), revision: 3, runId: 11);
    expect(trace.speed, 1);
    trace.play();
    await tester.pump(const Duration(milliseconds: 999));
    expect(trace.cursor, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(trace.cursor, 1);
    trace.setSpeed(2);
    await tester.pump(const Duration(milliseconds: 499));
    expect(trace.cursor, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(trace.cursor, 2);

    for (final speed in [5.0, 10.0, 50.0, 100.0, 2.5]) {
      trace.restart();
      trace.setSpeed(speed);
      trace.play();
      // Allow timer quantization at the 800 ms boundary. At 100× the next
      // visual batch is still scheduled for 816 ms.
      await tester.pump(const Duration(milliseconds: 805));
      expect(trace.cursor, (speed * .8).round(), reason: '$speed×');
      expect(trace.currentOriginalIndex, trace.cursor - 1);
    }
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => trace.setSpeed(invalid), throwsArgumentError);
      expect(trace.speed, 2.5);
    }
    trace.setSpeed(100);
    trace.seek(60);
    expect(trace.playing, false);
    await tester.pump(const Duration(seconds: 1));
    expect(trace.cursor, 60);
    trace.back();
    expect(trace.current!['sequence'], 58);
    trace.play();
    await tester.pump(const Duration(seconds: 1));
    expect(trace.cursor, 120);
    expect(trace.playing, false);
  });

  testWidgets('selection replays the same original events in recorded order', (
    tester,
  ) async {
    final trace = TracePlayback();
    addTearDown(trace.dispose);
    trace.load(
      [
        event(9),
        event(12),
        {...event(20), 'stage': 'routing'},
        {...event(35), 'stage': 'routing'},
        {...event(42), 'stage': 'allocation'},
      ],
      revision: 3,
      runId: 11,
      truncated: true,
      dropped: 50,
    );
    final original = trace.events;
    expect(trace.selection, TraceSelection.all);
    expect(trace.selectedIndices, [0, 1, 2, 3, 4]);
    trace.play();
    trace.setSelection(TraceSelection.routing);
    expect(trace.playing, false);
    expect(trace.cursor, 0);
    expect(trace.selectedIndices, [2, 3]);
    trace.step();
    expect(trace.currentOriginalIndex, 2);
    expect(trace.current, same(original[2]));
    trace.seek(999);
    expect(trace.currentOriginalIndex, 3);
    trace.back();
    expect(trace.current!['sequence'], 20);
    trace.setSelection(TraceSelection.allocation);
    trace.step();
    expect(trace.currentOriginalIndex, 4);
    expect(trace.current!['sequence'], 42);
    trace.setSelection(TraceSelection.generation);
    expect(trace.selectedIndices, [0, 1]);
    trace.setSelection(TraceSelection.all);
    expect(trace.events, same(original));
    expect(trace.truncated, true);
    expect(trace.dropped, 50);

    trace.setSelection(TraceSelection.generation);
    trace.load(
      [
        {...event(0), 'stage': 'allocation'},
      ],
      revision: 4,
      runId: 12,
    );
    expect(trace.events.length, 1);
    expect(trace.selectedEvents, isEmpty);
    trace.play();
    expect(trace.playing, false);
  });

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
          BenchmarkAxis.packs => [0, 12, 14],
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
          expect(project['source'].containsKey('template_catalogue'), false);
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

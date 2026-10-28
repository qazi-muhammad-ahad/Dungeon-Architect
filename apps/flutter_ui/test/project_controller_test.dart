import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/editor/exact_json.dart';
import 'package:dungeon_architect/engine/engine.dart';

final source = jsonEncode({
  'schema_version': 1,
  'engine_version': '0.9.0',
  'source': {
    'name': 'Test',
    'settings': {
      'columns': 24,
      'rows': 16,
      'room_count': 2,
      'seed': 42,
      'threat_budget': 3,
    },
    'allowed_mask': List.filled(16, '1' * 24),
    'rooms': [],
    'packs': [],
  },
});
EngineResult success(String raw) => EngineResult(
  raw,
  jsonDecode(
    jsonEncode({
      'outcome': 'success',
      'result': {
        'layout': {
          'rooms': [
            {
              'id': 'room-1',
              'bounds': {'x': 1, 'y': 1, 'width': 4, 'height': 4},
            },
          ],
        },
        'allocation': {
          'total_score': 14,
          'total_threat': 3,
          'actors': [],
          'assignments': [],
        },
      },
    }),
  ) as Map<String, dynamic>,
);

class FakeEngine extends Engine {
  Completer<EngineResult>? pending;
  final List<EngineResult> replies = [];
  final List<int> triedSeeds = [];
  @override
  Future<void> open() async {}
  @override
  Future<Map<String, dynamic>> metrics() async => {};
  @override
  Future<Map<String, dynamic>> trace({int cursor = 0, int count = 128}) async =>
      {'events': [], 'next_cursor': 0, 'total': 0};
  @override
  Future<EngineResult> run(
    String raw, {
    EngineOperation operation = EngineOperation.run,
    int maxEvents = 256,
    bool detailedTrace = false,
  }) async {
    if (operation == EngineOperation.normalize ||
        operation == EngineOperation.newProject) {
      if (raw == 'bad') {
        return const EngineResult('', {
          'outcome': 'invalid_input',
          'diagnostics': [
            {'message': 'Invalid project.', 'recovery': 'Fix file.'},
          ],
        });
      }
      return EngineResult('', {'outcome': 'success', 'project_json': raw});
    }
    triedSeeds.add(jsonDecode(raw)['source']['settings']['seed'] as int);
    return replies.isNotEmpty
        ? replies.removeAt(0)
        : pending == null
        ? success(raw)
        : pending!.future;
  }

  @override
  Future<void> cancel() async {
    pending?.complete(
      const EngineResult('', {'outcome': 'cancelled', 'diagnostics': []}),
    );
    pending = null;
  }

  @override
  EngineProgress get progress => const EngineProgress(1, 4, 0);
}

Future<void> settle(ProjectController c) async {
  for (var i = 0; i < 30 && c.validating; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'automatic search deadline cancels without replacing a valid result',
    () async {
      final engine = FakeEngine();
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      final draft = jsonDecode(source);
      draft['source']['settings']['max_time_ms'] = 10;
      await c.load(jsonEncode(draft));
      await c.run();
      final old = c.result;
      final before = c.canonical;
      engine.pending = Completer();
      await c.run();
      expect(c.result, same(old));
      expect(c.canonical, before);
      expect(c.message, contains('Search time limit reached'));
      expect(c.canRun, true);
    },
  );
  test(
    'automatic search publishes first success and persists its seed',
    () async {
      final engine = FakeEngine()
        ..replies.addAll([
          const EngineResult('', {'outcome': 'search_exhausted'}),
          const EngineResult('', {'outcome': 'search_exhausted'}),
          success('winner'),
        ]);
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      expect(engine.triedSeeds, [42, 43, 44]);
      expect(c.result!.rawJson, 'winner');
      expect(c.settings['seed'], 44);
      expect(decodeExact(c.canonical)['source']['settings']['seed'], 44);
      expect(c.stale, false);
      expect(c.dirty, true);
      expect(c.canSave, true);
    },
  );
  test(
    'invalid input stops immediately and retains previous result/source',
    () async {
      final engine = FakeEngine();
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      final old = c.result;
      engine.replies.add(const EngineResult('', {'outcome': 'invalid_input'}));
      await c.run();
      expect(engine.triedSeeds, [42, 42]);
      expect(c.result, same(old));
      expect(c.canonical, source);
      expect(c.state, RunState.invalid);
    },
  );
  test(
    'seed wraps at uint32 boundary and search respects cancellation',
    () async {
      final engine = FakeEngine()
        ..replies.add(const EngineResult('', {'outcome': 'search_exhausted'}));
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      final draft = jsonDecode(source);
      draft['source']['settings']['seed'] = 4294967295;
      await c.load(jsonEncode(draft));
      await c.run();
      expect(engine.triedSeeds, [4294967295, 0]);
      engine.replies.add(
        const EngineResult('', {'outcome': 'search_exhausted'}),
      );
      final old = c.result;
      final task = c.run();
      await c.cancel();
      await task;
      expect(c.result, same(old));
      expect(c.busy, false);
      expect(engine.triedSeeds, [4294967295, 0, 0]);
    },
  );
  test(
    'document replacement locks edits until native validation finishes',
    () async {
      final c = ProjectController(
        engine: FakeEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      final replacement = c.load(source);
      expect(c.loading, true);
      c.rename('Would be silently lost');
      c.editSetting('seed', '9', min: BigInt.zero, max: BigInt.from(100));
      expect(c.source['name'], 'Test');
      expect(c.settings['seed'], 42);
      expect(await replacement, true);
      expect(c.loading, false);
      expect(c.canSave, true);
    },
  );
  test('lossless source transport retains int64 and escaped strings', () {
    const raw =
        r'{"n":9223372036854775807,"text":"__da_integer__123 and \"42\"","small":42}';
    final decoded = decodeExact(raw);
    expect(decoded['n'], BigInt.parse('9223372036854775807'));
    expect(encodeExact(decoded), raw);
    expect(decodeExact(encodeExact(decoded))['small'], 42);
  });
  test(
    'transactional load, save state and view/selection preservation',
    () async {
      final c = ProjectController(
        engine: FakeEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(await c.load(source), true);
      expect(c.dirty, false);
      await c.run();
      c.select('room-1');
      final old = c.result;
      for (final view in EditorView.values) {
        c.switchView(view);
        expect(c.selectedRoom, 'room-1');
        expect(c.result, same(old));
      }
      expect(await c.load('bad'), false);
      expect(c.canonical, source);
      expect(c.result, same(old));
      expect(c.dirty, false);
      c.editSetting(
        'seed',
        '7',
        min: BigInt.zero,
        max: BigInt.from(4294967295),
      );
      await settle(c);
      expect(c.stale, true);
      expect(c.dirty, true);
      expect(c.canSave, true);
      c.markSaved(c.canonical, 'saved.json');
      expect(c.dirty, false);
      expect(c.filename, 'saved.json');
    },
  );
  test(
    'edits reject obsolete in-flight results and preserve previous result',
    () async {
      final engine = FakeEngine();
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      final old = c.result;
      engine.pending = Completer();
      final task = c.run();
      expect(c.busy, true);
      c.editSetting(
        'seed',
        '9',
        min: BigInt.zero,
        max: BigInt.from(4294967295),
      );
      await settle(c);
      engine.pending!.complete(success('obsolete'));
      await task;
      expect(c.result, same(old));
      expect(c.stale, true);
      expect(c.state, RunState.stale);
      expect(c.canRun, true);
    },
  );
  test(
    'cancel, invalid fields, recovery and clearing an old validation',
    () async {
      final engine = FakeEngine();
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      final old = c.result;
      engine.pending = Completer();
      final task = c.run();
      await c.cancel();
      await task;
      expect(c.result, same(old));
      expect(c.busy, false);
      c.editSetting('seed', '5', min: BigInt.zero, max: BigInt.from(100));
      c.editSetting('seed', '-', min: BigInt.zero, max: BigInt.from(100));
      await Future<void>.delayed(Duration.zero);
      expect(c.validating, false);
      expect(c.canSave, false);
      expect(c.state, RunState.invalid);
      c.editSetting('seed', '6', min: BigInt.zero, max: BigInt.from(100));
      await settle(c);
      expect(c.canSave, true);
      final saved = c.canonical;
      c.editSetting('seed', '7', min: BigInt.zero, max: BigInt.from(100));
      await settle(c);
      c.markSaved(saved, 'older.json');
      expect(c.dirty, true);
    },
  );
}

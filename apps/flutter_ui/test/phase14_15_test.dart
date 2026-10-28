import 'dart:async';
import 'dart:convert';

import 'package:dungeon_architect/editor/play_controller.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/editor/scenario_controller.dart';
import 'package:dungeon_architect/editor/scenario_panel.dart';
import 'package:dungeon_architect/engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> dungeon({int exitX = 20}) => {
  'geometry': {
    'id': 'native-geometry-11',
    'entrance_marker': {'x': 1, 'y': 1},
    'exit_marker': {'x': exitX, 'y': 1},
    'layers': {
      'floor': ['0' * 24, '0${'1' * 22}0', '0' * 24],
    },
    'rooms': [
      {'id': 'entry', 'capacity': 0, 'reachable': true},
      {'id': 'exit', 'capacity': 4, 'reachable': true},
    ],
  },
  'allocation': {
    'total_score': 14,
    'total_threat': 3,
    'actors': [
      {
        'pack_id': 'guard',
        'room_id': 'exit',
        'tile': {'x': 4, 'y': 1},
      },
    ],
  },
  'source_project': {
    'source': {
      'settings': {'threat_budget': 3},
      'packs': [
        {'id': 'guard', 'name': 'Guard', 'threat': 2, 'score': 9},
      ],
    },
  },
};

EngineResult report(Map<String, dynamic> payload, {bool disconnected = false}) {
  final doc = <String, dynamic>{
    'outcome': 'success',
    'optimal': true,
    'result': payload,
    'scenario': {
      'snapshot_job': 12,
      'baseline_job': 11,
      'exit_reachable': !disconnected,
      'reachable_rooms': disconnected ? 1 : 2,
      'disconnected_rooms': disconnected ? ['exit'] : [],
      'solver': 'full_exact_rerun',
    },
  };
  return EngineResult(jsonEncode(doc), doc);
}

class ScenarioEngine extends Engine {
  final requests = <Map<String, dynamic>>[];
  Completer<EngineResult>? pending;
  EngineResult? reply;

  @override
  Future<EngineResult> run(
    String raw, {
    EngineOperation operation = EngineOperation.run,
    int maxEvents = 256,
    bool detailedTrace = false,
  }) async {
    expect(operation, EngineOperation.scenario);
    requests.add(jsonDecode(raw) as Map<String, dynamic>);
    return pending != null ? pending!.future : reply ?? report(dungeon());
  }
}

void main() {
  testWidgets(
    'scenario numeric fields retain typing state, submit exact values on Enter and restore baseline',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = ScenarioEngine();
      final c = ProjectController(engine: engine, validator: ScenarioEngine());
      addTearDown(c.dispose);
      c.document = {
        'source': {
          'settings': {'threat_budget': 3, 'corridor_width': 2},
        },
      };
      c.result = report(dungeon());
      c.resultRevision = c.revision;
      c.selectedRoom = 'exit';
      c.scenario.bind(c.result, c.revision, 11);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (context, child) => Align(
                alignment: Alignment.topCenter,
                child: ScenarioPanel(controller: c),
              ),
            ),
          ),
        ),
      );
      Finder field(String label) => find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
        matching: find.byType(TextFormField),
      );
      Finder editor(String label) => find.descendant(
        of: field(label),
        matching: find.byType(EditableText),
      );
      EditableText editable(String label) =>
          tester.widget<EditableText>(editor(label));
      expect(editable('Scenario budget').controller.text, '3');
      expect(editable('Scenario capacity').controller.text, '4');
      final budgetState = tester.state(field('Scenario budget'));
      await tester.enterText(field('Scenario budget'), '9');
      await tester.pump();
      expect(tester.state(field('Scenario budget')), same(budgetState));
      expect(editable('Scenario budget').focusNode.hasFocus, true);
      expect(editable('Scenario budget').controller.text, '9');
      expect(
        c.scenario.budget,
        isNull,
        reason: 'Enter commits temporary controls',
      );
      tester.testTextInput.enterText('9007199254740993');
      await tester.pump();
      expect(tester.state(field('Scenario budget')), same(budgetState));
      expect(editable('Scenario budget').focusNode.hasFocus, true);
      expect(editable('Scenario budget').controller.text, '9007199254740993');
      expect(c.scenario.budget, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.scenario.budget, BigInt.parse('9007199254740993'));
      expect(tester.state(field('Scenario budget')), same(budgetState));
      expect(editable('Scenario budget').controller.text, '9007199254740993');
      expect(c.scenario.stale, true);
      await tester.enterText(field('Scenario budget'), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        c.scenario.budget,
        BigInt.parse('9007199254740993'),
        reason: 'An invalid empty submission preserves the last control value',
      );
      expect(find.text('Enter a nonnegative int64 budget.'), findsOneWidget);
      expect(c.settings['threat_budget'], 3);
      expect(tester.state(field('Scenario budget')), same(budgetState));
      await tester.enterText(field('Scenario capacity'), '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.scenario.capacities['exit'], 2);
      await tester.enterText(field('Scenario capacity'), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.scenario.capacities['exit'], 2);
      expect(find.text('Capacity must be 0–262144.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Restore baseline'));
      await tester.pump();
      expect(editable('Scenario budget').controller.text, '3');
      expect(editable('Scenario capacity').controller.text, '4');
      expect(c.scenario.changed, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'worker latency retains frame time without concurrent native moves',
    () async {
      final first = Completer<Map<String, dynamic>>();
      var calls = 0, inFlight = 0, maxInFlight = 0;
      final c = PlayController(({
        required snapshotJob,
        required x,
        required y,
        required dx,
        required dy,
      }) async {
        calls++;
        inFlight++;
        if (inFlight > maxInFlight) {
          maxInFlight = inFlight;
        }
        try {
          return calls == 1 ? await first.future : {'x': x + dx, 'y': y + dy};
        } finally {
          inFlight--;
        }
      });
      addTearDown(c.dispose);
      c.start(dungeon(), 11, 0);
      c.key('right', true);
      final pending = c.advance(const Duration(milliseconds: 125));
      for (var i = 0; i < 7; i++) {
        await c.advance(const Duration(milliseconds: 125));
      }
      expect(calls, 1);
      first.complete({'x': 2, 'y': 1});
      await pending;
      expect(maxInFlight, 1);
      expect(calls, 8);
      expect(c.x, 9);
    },
  );

  test(
    'elapsed time partitions preserve fixed cardinal movement rate',
    () async {
      Future<int> travel(List<Duration> frames) async {
        final calls = <List<int>>[];
        final c = PlayController(({
          required snapshotJob,
          required x,
          required y,
          required dx,
          required dy,
        }) async {
          expect(snapshotJob, 11);
          expect(dx.abs() + dy.abs(), 1);
          calls.add([x, y, dx, dy]);
          return {'x': x + dx, 'y': y + dy};
        });
        addTearDown(c.dispose);
        c.start(dungeon(), 11, 7);
        c.key('right', true);
        for (final frame in frames) {
          await c.advance(frame);
        }
        expect(calls.length, 8);
        expect(c.y, 1);
        expect(c.revision, 7);
        return c.x;
      }

      expect(
        await travel(List.filled(16, const Duration(microseconds: 62500))),
        9,
      );
      expect(
        await travel(List.filled(4, const Duration(milliseconds: 250))),
        9,
      );
    },
  );

  test('long frames submit bounded single steps and cannot jump a wall', () async {
    final calls = <List<int>>[];
    final c = PlayController(({
      required snapshotJob,
      required x,
      required y,
      required dx,
      required dy,
    }) async {
      calls.add([x, y, dx, dy]);
      // This fake models an authoritative wall at x=6; native tests separately
      // exercise every edge of real generated floor, doors and blocked routes.
      return {'x': x + dx < 6 ? x + dx : x, 'y': y};
    });
    addTearDown(c.dispose);
    c.start(dungeon(), 11, 0);
    c.key('right', true);
    await c.advance(const Duration(seconds: 50));
    expect(c.x, 5);
    expect(calls.length, 8);
    expect(calls.every((call) => call[2] == 1 && call[3] == 0), true);
    c.key('right', false);
    await c.advance(const Duration(seconds: 10));
    expect(calls.length, 8);
  });

  test('overlapping frames serialize and stale response cannot move restarted session', () async {
    final pending = Completer<Map<String, dynamic>>();
    var calls = 0;
    final c = PlayController(({
      required snapshotJob,
      required x,
      required y,
      required dx,
      required dy,
    }) {
      calls++;
      return pending.future;
    });
    addTearDown(c.dispose);
    c.start(dungeon(), 11, 0);
    c.key('right', true);
    final frame = c.advance(const Duration(seconds: 1));
    await c.advance(const Duration(seconds: 1));
    expect(calls, 1);
    c.restart();
    pending.complete({'x': 9, 'y': 1});
    await frame;
    expect(c.x, 1);
    expect(c.y, 1);
    expect(c.held, isEmpty);
    expect(c.moving, false);
  });

  test(
    'pause clears held keys and fractional time, resume requires fresh key',
    () async {
      var calls = 0;
      final c = PlayController(({
        required snapshotJob,
        required x,
        required y,
        required dx,
        required dy,
      }) async {
        calls++;
        return {'x': x + dx, 'y': y + dy};
      });
      addTearDown(c.dispose);
      c.start(dungeon(), 11, 0);
      c.key('right', true);
      await c.advance(const Duration(milliseconds: 100));
      c.pause();
      expect(c.held, isEmpty);
      c.resume();
      await c.advance(const Duration(seconds: 2));
      expect(calls, 0);
      c.key('right', true);
      await c.advance(const Duration(milliseconds: 25));
      expect(calls, 0);
      await c.advance(const Duration(milliseconds: 100));
      expect(calls, 1);
      c.invalidate();
      expect(c.active, false);
      expect(c.paused, true);
      expect(c.held, isEmpty);
    },
  );

  test(
    'immutable session, nonblocking actor inspection, exit and restart',
    () async {
      final c = PlayController(
        ({
          required snapshotJob,
          required x,
          required y,
          required dx,
          required dy,
        }) async => {'x': x + dx, 'y': y + dy},
      );
      addTearDown(c.dispose);
      final original = dungeon(exitX: 5);
      c.start(original, 11, 3);
      original['geometry']['exit_marker']['x'] = 19;
      original['allocation']['actors'].clear();
      c.key('right', true);
      await c.advance(const Duration(milliseconds: 125));
      expect(c.nearbyActor()?['pack_id'], 'guard');
      await c.advance(const Duration(milliseconds: 375));
      expect(c.x, 5, reason: 'Actor at x=4 must not block movement');
      expect(c.completed, true);
      expect(c.paused, true);
      expect(c.held, isEmpty);
      expect(c.message, contains('Exit reached'));
      c.restart();
      expect(c.x, 1);
      expect(c.completed, false);
      expect(c.paused, false);
    },
  );

  test(
    'movement engine error invalidates instead of retaining a mixed session',
    () async {
      final c = PlayController(
        ({
          required snapshotJob,
          required x,
          required y,
          required dx,
          required dy,
        }) async =>
            throw const EngineException('stale_result', 'Snapshot changed'),
      );
      addTearDown(c.dispose);
      c.start(dungeon(), 11, 0);
      c.key('right', true);
      await c.advance(const Duration(milliseconds: 125));
      expect(c.active, false);
      expect(c.message, contains('Snapshot changed'));
    },
  );

  test('scenario edit is immediately stale; apply uses temporary exact controls and reset restores baseline', () async {
    final engine = ScenarioEngine();
    final c = ScenarioController(() => engine);
    addTearDown(c.dispose);
    final baseline = report(dungeon());
    final before = jsonEncode(baseline.document);
    c.bind(baseline, 7, 11);
    c.toggleTile(8, 1);
    c.disabled.add('exit');
    c.capacities['exit'] = 0;
    c.budget = BigInt.from(9007199254740993);
    c.edit();
    expect(c.stale, true);
    expect(c.exitReachable, false);
    await c.apply();
    expect(engine.requests.single, {
      'baseline_job': 11,
      'blocked_tiles': [
        [8, 1],
      ],
      'disabled_rooms': ['exit'],
      'capacities': {'exit': 0},
      'budget': 9007199254740993,
    });
    expect(c.stale, false);
    expect(c.snapshotJob, 12);
    expect(jsonEncode(baseline.document), before);
    c.reset();
    expect(c.changed, false);
    expect(c.stale, false);
    expect(c.result, isNull);
    expect(c.snapshotJob, 11);
    expect(c.payload, same(baseline.document['result']));
    expect(jsonEncode(baseline.document), before);
  });

  test('scenario rejects obsolete async success after edit, reset and new baseline', () async {
    for (final change in ['edit', 'reset', 'bind']) {
      final engine = ScenarioEngine()..pending = Completer();
      final c = ScenarioController(() => engine);
      c.bind(report(dungeon()), 0, 11);
      c.toggleTile(8, 1);
      final applying = c.apply();
      expect(c.busy, true);
      if (change == 'edit') {
        c.toggleTile(9, 1);
      } else if (change == 'reset') {
        c.reset();
      } else {
        c.bind(report(dungeon()), 1, 15);
      }
      engine.pending!.complete(report(dungeon(), disconnected: true));
      await applying;
      expect(c.result, isNull, reason: '$change must discard old completion');
      expect(c.busy, false);
      expect(c.snapshotJob, change == 'bind' ? 15 : 11);
      expect(c.stale, change == 'edit');
      c.dispose();
    }
  });

  test('failed scenario retains previous valid scenario and disconnected exit explanation', () async {
    final engine = ScenarioEngine()
      ..reply = report(dungeon(), disconnected: true);
    final c = ScenarioController(() => engine);
    addTearDown(c.dispose);
    c.bind(report(dungeon()), 0, 11);
    c.toggleTile(8, 1);
    await c.apply();
    final previous = c.result;
    expect(c.exitReachable, false);
    expect(c.message, contains('Exit disconnected'));
    engine.reply = const EngineResult('', {
      'outcome': 'cancelled',
      'diagnostics': [],
    });
    c.toggleTile(9, 1);
    await c.apply();
    expect(c.result, same(previous));
    expect(c.stale, true);
    expect(c.message, 'cancelled');
  });
}

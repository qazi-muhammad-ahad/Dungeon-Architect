import 'package:dungeon_architect/editor/exact_json.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/editor/record_editors.dart';
import 'package:dungeon_architect/engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase11_test.dart' show ScriptedEngine, accepted, pack;
import 'project_controller_test.dart' show source;

void main() {
  testWidgets('Room capacity uses the current valid spawn positions', (
    tester,
  ) async {
    final validator = ScriptedEngine(), engine = ScriptedEngine();
    final c = ProjectController(engine: engine, validator: validator);
    addTearDown(c.dispose);
    await c.initialize();
    final room = <String, dynamic>{
      'id': 'room-1',
      'name': 'Hall',
      'bounds': {'x': 2, 'y': 2, 'width': 4, 'height': 4},
      'role': 'normal',
      'tags': <String>[],
      'lock_position': true,
      'lock_size': true,
      'capacity_override': null,
    };
    final project = decodeExact(source) as Map<String, dynamic>;
    project['source']['rooms'] = [room];
    await c.load(encodeExact(project));
    engine.nextRun = EngineResult('', {
      'outcome': 'success',
      'result': {
        'layout': {
          'rooms': [room],
        },
        'geometry': {
          'rooms': [
            {
              'id': 'room-1',
              'capacity': 2,
              'spawn_positions': [
                {
                  'id': 'spawn-1',
                  'tile': {'x': 3, 'y': 3},
                },
                {
                  'id': 'spawn-2',
                  'tile': {'x': 4, 'y': 4},
                },
              ],
            },
          ],
        },
      },
    });
    await c.run();
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => editRoom(context, c, room),
              child: const Text('Open room editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open room editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final capacity = find.widgetWithText(
      TextFormField,
      'Capacity (slots; blank = all valid positions)',
    );
    await tester.enterText(capacity, '3');
    await tester.tap(find.text('Save room'));
    await tester.pump();
    expect(
      find.text('Maximum 2 slots in the current valid positions.'),
      findsOneWidget,
    );
    expect(
      validator.requests.where((r) => r.operation == EngineOperation.edit),
      isEmpty,
    );
    expect(c.source['rooms'][0]['capacity_override'], isNull);
    await tester.enterText(capacity, '2');
    final expected = {...room, 'capacity_override': 2};
    final saved = decodeExact(c.canonical) as Map<String, dynamic>;
    saved['source']['rooms'] = [expected];
    validator.edits.add(accepted(saved));
    await tester.tap(find.text('Save room'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final request = validator.requests.singleWhere(
      (r) => r.operation == EngineOperation.edit,
    );
    expect(decodeExact(request.raw)['command']['room'], expected);
    expect(c.source['rooms'][0]['capacity_override'], 2);
    expect(c.geometryCurrent, true);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'New pack validates actual numeric form state before native commit',
    (tester) async {
      final validator = ScriptedEngine();
      final c = ProjectController(
        engine: ScriptedEngine(),
        validator: validator,
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => editPack(context, c),
                child: const Text('Open pack editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open pack editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      Finder field(String label) => find.widgetWithText(TextFormField, label);
      await tester.enterText(field('Pack name'), 'Patrol');
      await tester.enterText(field('Slots (spawn positions)'), '0');
      await tester.tap(find.text('Save pack'));
      await tester.pump();
      expect(
        find.text('Enter a positive whole number within int64.'),
        findsOneWidget,
      );
      expect(
        validator.requests.where((r) => r.operation == EngineOperation.edit),
        isEmpty,
      );
      await tester.enterText(field('Slots (spawn positions)'), '1');
      await tester.enterText(field('Designer score (points)'), '100');
      final expected = {
        ...pack('pack-1'),
        'name': 'Patrol',
        'threat': 0,
        'score': 100,
        'min_room_width': 1,
        'min_room_height': 1,
        'allowed_roles': <String>[],
        'required_tags': <String>[],
      };
      final project = decodeExact(source) as Map<String, dynamic>;
      project['source']['packs'] = [expected];
      validator.edits.add(accepted(project));
      await tester.tap(find.text('Save pack'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final request = validator.requests.singleWhere(
        (r) => r.operation == EngineOperation.edit,
      );
      expect(decodeExact(request.raw)['command']['pack'], expected);
      expect(c.catalogue.single['score'], 100);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

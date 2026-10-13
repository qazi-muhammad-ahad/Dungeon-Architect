import 'dart:convert';

import 'package:dungeon_architect/main.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'project_controller_test.dart' show FakeEngine, source;

void main() {
  testWidgets(
    'editor resizes and switches views without losing selection or source',
    (tester) async {
      final c = ProjectController(
        engine: FakeEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      c.select('room-1');
      // Supply complete renderable fixture layers, without algorithm behavior in UI.
      c.result!.document['result']['source_project'] = jsonDecode(source);
      c.result!.document['result']['layout']['rooms'][0].addAll({
        'name': 'Study',
        'role': 'normal',
        'lock_position': false,
      });
      c.result!.document['stages'] = {};
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(DungeonArchitectApp(controller: c));
      await tester.pump();
      expect(find.text('DUNGEON ARCHITECT'), findsOneWidget);
      for (final tab in ['Analyze', 'Play', 'Design']) {
        await tester.tap(find.text(tab));
        await tester.pump();
        expect(c.selectedRoom, 'room-1');
      }
      tester.view.physicalSize = const Size(800, 650);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(520, 700);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(2880, 1800);
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(c.canonical, source);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

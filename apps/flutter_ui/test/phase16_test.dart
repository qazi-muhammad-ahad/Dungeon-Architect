import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dungeon_architect/editor/camera.dart';
import 'package:dungeon_architect/editor/preview.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/editor/theme.dart';
import 'package:dungeon_architect/engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'project_controller_test.dart' show FakeEngine, source, settle, success;

class ClosingEngine extends FakeEngine {
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
    await super.close();
  }
}

void main() {
  test(
    'resized source safely paints beyond retained stale geometry layers',
    () {
      final painter = CanvasPainter(
        camera: CanvasCamera()..scale = 16,
        source: {
          'settings': {'columns': 24, 'rows': 16},
          'allowed_mask': List.filled(16, '1' * 24),
          'rooms': [],
        },
        payload: {
          'geometry': {
            'layers': {
              'floor': ['1111', '1111'],
              'walls': ['0000', '0000'],
            },
            'doors': [],
            'rooms': [],
          },
        },
        analysis: {},
        colors: const EditorColors(true),
        grid: true,
        diagnostics: true,
        reservations: true,
        floor: true,
        walls: true,
      );
      final recorder = ui.PictureRecorder();
      expect(
        () => painter.paint(Canvas(recorder), const Size(384, 256)),
        returnsNormally,
      );
      recorder.endRecording().dispose();
      // Includes source mask and retained floor/wall visits. The behavioral
      // regression is safe painting across both smaller retained layers.
      expect(painter.visitedCells, greaterThanOrEqualTo(384));
      expect(painter.visitedCells, lessThanOrEqualTo(3 * 384));
    },
  );

  test(
    'uncommitted canvas preview participates in the dirty close guard',
    () async {
      final c = ProjectController(
        engine: FakeEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      expect(c.dirty, false);
      c.setCanvasDraft(true);
      expect(
        c.dirty,
        true,
        reason: 'A preview is unsaved work even before commit',
      );
      expect(c.canSave, false);
      expect(await c.load(source), false);
      c.switchView(EditorView.play);
      expect(c.view, EditorView.design);
      expect(c.canvasDraft, true);
      expect(c.message, contains('Apply or cancel'));
      c.setCanvasDraft(false);
      expect(c.dirty, false);
      c.switchView(EditorView.play);
      expect(c.view, EditorView.play);
    },
  );

  test(
    'failed open, failed run and older save cannot discard a newer edit',
    () async {
      final engine = FakeEngine();
      final c = ProjectController(engine: engine, validator: FakeEngine());
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      await c.run();
      final oldResult = c.result;
      final oldText = c.canonical;
      c.rename('Unsaved revision');
      await settle(c);
      final edited = c.canonical;
      expect(c.dirty, true);
      expect(await c.load('bad'), false);
      expect(c.canonical, edited);
      expect(c.result, same(oldResult));
      engine.replies.add(const EngineResult('', {'outcome': 'invalid_input'}));
      await c.run();
      expect(c.canonical, edited);
      expect(c.result, same(oldResult));
      c.markSaved(oldText, 'older.json');
      expect(c.dirty, true);
      expect(c.message, contains('New edits remain unsaved'));
      expect(c.source['name'], 'Unsaved revision');
    },
  );

  test(
    'undo to saved source clears dirty; redo restores unsaved source',
    () async {
      final c = ProjectController(
        engine: FakeEngine(),
        validator: FakeEngine(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.load(source);
      final changed = jsonDecode(source) as Map<String, dynamic>;
      changed['source']['allowed_mask'][0] = '0${'1' * 23}';
      final next = jsonEncode(changed);
      EngineResult checked(String raw) =>
          EngineResult('', {'outcome': 'success', 'project_json': raw});
      expect(c.commitCanvas(checked(next), c.revision), true);
      expect(c.dirty, true);
      expect(c.commitCanvas(checked(source), c.revision), true);
      expect(c.dirty, false);
      expect(c.commitCanvas(checked(next), c.revision), true);
      expect(c.dirty, true);
      final stamp = c.revision;
      expect(c.commitCanvas(checked(source), stamp - 1), false);
      expect(c.canonical, next);
    },
  );

  test('disposing while native run is pending closes both workers and rejects publication', () async {
    for (var cycle = 0; cycle < 12; cycle++) {
      final engine = ClosingEngine(), validator = ClosingEngine();
      final c = ProjectController(engine: engine, validator: validator);
      await c.initialize();
      await c.load(source);
      engine.pending = Completer<EngineResult>();
      final pending = engine.pending!;
      final work = c.run();
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      pending.complete(success('late result'));
      await work;
      expect(c.result, isNull);
      expect(engine.closes, 1);
      expect(validator.closes, 1);
      expect(c.canonical, source);
    }
  });
}

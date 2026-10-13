import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dungeon_architect/editor/camera.dart';
import 'package:dungeon_architect/editor/canvas_history.dart';
import 'package:dungeon_architect/editor/preview.dart';
import 'package:dungeon_architect/editor/theme.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/main.dart';

import 'project_controller_test.dart' show FakeEngine, source;

void main() {
  test('tooltip text has readable contrast in both themes', () {
    for (final dark in [false, true]) {
      final theme = editorTheme(dark: dark).tooltipTheme;
      final background = (theme.decoration as BoxDecoration).color!
          .computeLuminance();
      final foreground = theme.textStyle!.color!.computeLuminance();
      final ratio = (background > foreground)
          ? (background + .05) / (foreground + .05)
          : (foreground + .05) / (background + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });
  test('camera uses logical pixels at all zooms, edges and pixel ratios', () {
    final camera = CanvasCamera();
    for (final dpi in [1.0, 1.25, 2.0, 3.0]) {
      camera.fit(Size(1000 * dpi, 800 * dpi) / dpi, 150, 150);
      for (final zoom in [.25, 1.0, 7.5, 64.0]) {
        camera.scale = zoom;
        camera.origin = const Offset(-31.3, 12.7);
        for (final tile in [
          const Point(0, 0),
          const Point(149, 149),
          const Point(72, 21),
        ]) {
          final screen = camera.toScreen(Offset(tile.x + .5, tile.y + .5));
          expect(camera.tileAt(screen, 150, 150), tile);
          final before = camera.toWorld(screen);
          camera.zoom(screen, 1.5);
          expect((camera.toWorld(screen) - before).distance, lessThan(1e-9));
        }
        expect(
          camera.tileAt(camera.toScreen(const Offset(-.01, 0)), 150, 150),
          isNull,
        );
        expect(
          camera.tileAt(camera.toScreen(const Offset(150, 149)), 150, 150),
          isNull,
        );
      }
    }
  });
  test('fast strokes cover each intervening tile in every direction', () {
    for (final end in [
      const Point(149, 0),
      const Point(0, 149),
      const Point(149, 149),
      const Point(50, 149),
    ]) {
      final points = strokeLine(const Point(0, 0), end).toList();
      expect(points.first, const Point(0, 0));
      expect(points.last, end);
      for (var i = 1; i < points.length; i++) {
        expect((points[i].x - points[i - 1].x).abs(), lessThanOrEqualTo(1));
        expect((points[i].y - points[i - 1].y).abs(), lessThanOrEqualTo(1));
      }
      expect(strokeLine(end, const Point(0, 0)).length, points.length);
    }
  });
  test(
    'history caps undo and redo memory and clears redo after new gestures',
    () {
      final h = CanvasHistory(limit: 1800),
          s = CanvasSnapshot(10, 10, List.filled(10, '1111111111'));
      for (var i = 0; i < 20; i++) {
        h.record(s);
      }
      expect(h.bytes, lessThanOrEqualTo(h.limit));
      expect(h.undo, isNotEmpty);
      h.redo.add(h.undo.removeLast());
      h.record(s);
      expect(h.redo, isEmpty);
    },
  );
  test('renderer culls offscreen tiles and measures supported canvas sizes', () {
    for (final n in [150, 512]) {
      final source = {
        'settings': {'columns': n, 'rows': n},
        'allowed_mask': List.filled(n, '1' * n),
        'rooms': [],
      };
      final camera = CanvasCamera()
        ..scale = 10
        ..origin = const Offset(-100, -100);
      final p = CanvasPainter(
        camera: camera,
        source: source,
        payload: null,
        analysis: {},
        colors: const EditorColors(true),
        grid: true,
        diagnostics: true,
        reservations: true,
        floor: true,
        walls: true,
      );
      var recorder = ui.PictureRecorder();
      p.paint(Canvas(recorder), const Size(200, 200));
      recorder.endRecording().dispose();
      expect(p.visitedCells, 400);
      camera.fit(const Size(900, 600), n, n);
      final samples = <int>[];
      for (var i = 0; i < 20; i++) {
        recorder = ui.PictureRecorder();
        p.paint(Canvas(recorder), const Size(900, 600));
        recorder.endRecording().dispose();
        samples.add(p.paintMicros);
      }
      samples.sort();
      debugPrint(
        '$n × $n fitted canvas: median ${samples[10]} µs (test painter, excludes rasterization)',
      );
      expect(p.visitedCells, n * n);
    }
  });
  testWidgets('theme switch preserves the project, selection and canvas', (
    tester,
  ) async {
    final c = ProjectController(engine: FakeEngine(), validator: FakeEngine());
    addTearDown(c.dispose);
    await c.initialize();
    await c.load(source);
    c.select('room-1');
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DungeonArchitectApp(controller: c));
    await tester.pump();
    final canvasState = tester.state(find.byType(DungeonPreview));
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      Theme.of(tester.element(find.byType(DungeonPreview))).brightness,
      Brightness.dark,
    );
    expect(tester.state(find.byType(DungeonPreview)), same(canvasState));
    expect(c.canonical, source);
    expect(c.selectedRoom, 'room-1');
    await tester.tap(find.byTooltip('Switch to light mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      Theme.of(tester.element(find.byType(DungeonPreview))).brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

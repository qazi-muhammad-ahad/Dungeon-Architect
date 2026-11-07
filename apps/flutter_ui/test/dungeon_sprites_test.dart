import 'dart:ui' as ui;

import 'package:dungeon_architect/editor/pixel_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sprite art resolves against the accepted effective inventory', () {
    const actor = {'pack_id': 'pack'};
    for (final (name, kind) in [
      ('Archer', 'archer'),
      ('Guard pair', 'guard'),
      ('Ogre Boss', 'ogre'),
      ('Lava spirit', 'lava'),
      ('Custom patrol', 'encounter'),
    ]) {
      expect(
        DungeonPixels.encounterKind(actor, {
          'packs': [],
          'template_catalogue': {
            'version': 'historical',
            'packs': [
              {'id': 'pack', 'name': name},
            ],
          },
        }),
        kind,
      );
    }
    expect(
      DungeonPixels.encounterKind(actor, {
        'packs': [
          {'id': 'pack', 'name': 'Custom patrol'},
        ],
        'template_catalogue': {
          'packs': [
            {'id': 'pack', 'name': 'Ogre Boss'},
          ],
        },
      }),
      'encounter',
    );
  });

  test('original actor and door sprites have distinct multicolor raster shapes', () async {
    final shapes = <String, List<int>>{};
    for (final kind in [
      'archer',
      'guard',
      'ogre',
      'lava',
      'encounter',
      'player',
      'door',
    ]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      DungeonPixels.motif(canvas, const Rect.fromLTWH(16, 16, 32, 32), kind, 1);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);
      final bytes = data!.buffer.asUint8List();
      final colors = <int>{};
      var painted = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i + 3] == 0) continue;
        painted++;
        colors.add(
          (bytes[i] << 24) |
              (bytes[i + 1] << 16) |
              (bytes[i + 2] << 8) |
              bytes[i + 3],
        );
      }
      expect(painted, greaterThan(120), reason: kind);
      expect(colors.length, greaterThanOrEqualTo(4), reason: kind);
      for (final previous in shapes.entries) {
        expect(
          bytes,
          isNot(orderedEquals(previous.value)),
          reason:
              '$kind and ${previous.key} have distinct silhouettes and colors',
        );
      }
      shapes[kind] = bytes.toList();
      image.dispose();
      picture.dispose();
    }
  });
}

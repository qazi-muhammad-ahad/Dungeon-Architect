import 'dart:convert';

import 'package:dungeon_architect/editor/routing_replay.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> record(
  int sequence,
  String kind, {
  String corridor = 'c1',
  List<Map<String, dynamic>> steps = const [],
  int omitted = 0,
}) => {
  'stage': 'routing',
  'source_sequence': sequence,
  'event': {
    'kind': kind,
    'corridor_id': corridor,
    'room_id': 'a',
    'other_room_id': 'b',
    'width': 2,
    'omitted_steps': omitted,
    'steps': steps,
  },
};

Map<String, dynamic> step(
  String kind,
  int x,
  int y, [
  int px = -1,
  int py = -1,
]) => {
  'kind': kind,
  'tile': {'x': x, 'y': y},
  'parent': {'x': px, 'y': py},
};

void main() {
  test(
    'routing prefix separates search, reconstruction and actual carving',
    () {
      final events = [
        record(0, 'routing_started'),
        record(
          1,
          'search_batch',
          steps: [
            step('discovered', 1, 2),
            step('expanded', 1, 2),
            step('discovered', 2, 2, 1, 2),
          ],
        ),
        record(
          2,
          'search_batch',
          steps: [step('expanded', 2, 2), step('discovered', 3, 2, 2, 2)],
        ),
        record(3, 'search_finished'),
        record(
          4,
          'reconstruct_batch',
          steps: [
            step('path', 3, 2, 2, 2),
            step('path', 2, 2, 1, 2),
            step('path', 1, 2),
          ],
        ),
        record(5, 'carve_batch', steps: [step('carve', 1, 2)]),
        record(
          6,
          'carve_batch',
          steps: [step('carve', 2, 2), step('carve', 3, 2)],
        ),
        record(7, 'carving_finished'),
        record(8, 'corridor_routed'),
        record(9, 'routing_started', corridor: 'c2'),
        record(
          10,
          'search_batch',
          corridor: 'c2',
          steps: [step('discovered', 8, 9)],
        ),
        record(11, 'geometry_completed', corridor: ''),
      ];
      final immutableInput = jsonEncode(events);
      final replay = RoutingReplay.fromEvents(events, 1);
      expect(replay.discovered.keys, ['1,2', '2,2']);
      expect(replay.expanded.keys, ['1,2']);
      expect(replay.frontier.map((tile) => tile.key), ['2,2']);
      expect(replay.parents['2,2']!.key, '1,2');
      expect(replay.reconstructed, isEmpty);
      expect(replay.carved, isEmpty);
      replay.update(events, 4);
      expect(replay.reconstructed.map((tile) => tile.key), [
        '3,2',
        '2,2',
        '1,2',
      ]);
      expect(
        replay.carved,
        isEmpty,
        reason: 'A found path has not carved the floor',
      );
      replay.update(events, 5);
      expect(replay.carved.keys, ['c1:1,2']);
      expect(replay.carved.values.single.$2, 2);
      expect(replay.completedCorridors, isEmpty);
      replay.update(events, 10);
      expect(replay.corridorId, 'c2');
      expect(replay.discovered.keys, ['8,9']);
      expect(replay.expanded, isEmpty);
      expect(replay.reconstructed, isEmpty);
      expect(replay.completedCorridors, {'c1'});
      expect(replay.carved.length, 3);
      expect(replay.geometryComplete, false);
      replay.update(events, 11);
      expect(replay.geometryComplete, true);

      replay.update(events, 1);
      expect(replay.geometryComplete, false);
      expect(replay.corridorId, 'c1');
      expect(replay.carved, isEmpty);
      expect(replay.completedCorridors, isEmpty);
      expect(replay.frontier.map((tile) => tile.key), ['2,2']);
      expect(replay.reconstructed, isEmpty);
      expect(replay.sampled, false);
      expect(jsonEncode(events), immutableInput);
      replay.update(events, -1);
      expect(replay.discovered, isEmpty);
      expect(replay.corridorId, isNull);
    },
  );

  test('sampled and legacy traces preserve only captured evidence', () {
    final events = [
      record(0, 'routing_started'),
      record(5, 'search_batch', steps: [step('expanded', 7, 2)]),
      record(6, 'search_finished', omitted: 80),
      record(7, 'corridor_routed'),
      record(12, 'carve_batch', corridor: 'c2', steps: [step('carve', 8, 2)]),
    ];
    final replay = RoutingReplay.fromEvents(events, 2);
    expect(replay.sampled, true);
    expect(replay.omittedSteps, 80);
    expect(replay.discovered, isEmpty);
    expect(replay.expanded.keys, ['7,2']);
    expect(replay.parents, isEmpty);
    expect(replay.carved, isEmpty);
    replay.update(events, 4);
    expect(replay.corridorId, 'c2');
    expect(replay.expanded, isEmpty);
    expect(replay.carved.keys, ['c2:8,2']);
    expect(replay.completedCorridors, {'c1'});
    final legacy = RoutingReplay.fromEvents([
      record(0, 'routing_started'),
      record(1, 'anchor_visited'),
    ], 1);
    expect(legacy.carved, isEmpty);
    expect(legacy.discovered, isEmpty);
    expect(legacy.reconstructed, isEmpty);
  });
}

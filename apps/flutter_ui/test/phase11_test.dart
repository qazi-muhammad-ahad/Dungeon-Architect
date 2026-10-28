import 'dart:async';

import 'package:dungeon_architect/editor/exact_json.dart';
import 'package:dungeon_architect/editor/project_controller.dart';
import 'package:dungeon_architect/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'project_controller_test.dart' show source, success, settle;

// Scripted boundary responses test controller transactions, never duplicate C++ rules.
class ScriptedEngine extends Engine {
  final requests = <({EngineOperation operation, String raw})>[];
  final edits = <EngineResult>[];
  final normalizations = <EngineResult>[];
  Completer<EngineResult>? pending;
  EngineResult? nextRun;

  @override
  Future<void> open() async {}

  @override
  Future<EngineResult> run(
    String raw, {
    EngineOperation operation = EngineOperation.run,
    int maxEvents = 256,
    bool detailedTrace = false,
  }) async {
    requests.add((operation: operation, raw: raw));
    if (operation == EngineOperation.normalize ||
        operation == EngineOperation.newProject) {
      if (normalizations.isNotEmpty) return normalizations.removeAt(0);
      return EngineResult('', {'outcome': 'success', 'project_json': raw});
    }
    if (operation == EngineOperation.edit) return edits.removeAt(0);
    if (pending != null) return pending!.future;
    return nextRun ?? success(raw);
  }

  @override
  EngineProgress get progress => const EngineProgress(1, 4, 0);
}

EngineResult accepted(Map<String, dynamic> project) => EngineResult('', {
  'outcome': 'success',
  'project_json': encodeExact(project),
});
const rejected = EngineResult('', {
  'outcome': 'invalid_input',
  'diagnostics': [
    {'message': 'Edit rejected by C++.', 'recovery': 'Correct the edit.'},
  ],
});

Map<String, dynamic> pack(String id, {bool active = true}) => {
  'id': id,
  'name': 'Skeleton patrol',
  'active': active,
  'slots': 1,
  'threat': 2,
  'score': 5,
  'min_room_width': 2,
  'min_room_height': 2,
  'allowed_roles': ['normal'],
  'required_tags': ['stone'],
};

void main() {
  late ScriptedEngine engine, validator;
  late ProjectController c;
  setUp(() async {
    engine = ScriptedEngine();
    validator = ScriptedEngine();
    c = ProjectController(engine: engine, validator: validator);
    await c.initialize();
    await c.load(source);
  });
  tearDown(() => c.dispose());

  test(
    'rejected pack and room commits preserve canonical source and output',
    () async {
      await c.run();
      final before = c.canonical, old = c.result, revision = c.revision;
      validator.edits.add(rejected);
      expect(await c.savePack({...pack('invalid'), 'slots': 0}), false);
      expect(c.canonical, before);
      expect(c.result, same(old));
      expect(c.revision, revision);
      validator.edits.add(rejected);
      expect(
        await c.saveRoom({
          'id': 'invalid-room',
          'bounds': {'x': -1, 'y': 2, 'width': 4, 'height': 4},
        }),
        false,
      );
      expect(c.canonical, before);
      expect(c.result, same(old));
      expect(c.revision, revision);
      expect(c.canSave, true);
    },
  );

  test(
    'native rejection of a numeric draft preserves source and allows recovery',
    () async {
      await c.run();
      final before = c.canonical, old = c.result;
      validator.normalizations.add(rejected);
      c.editSetting(
        'corridor_width',
        '99',
        min: BigInt.one,
        max: BigInt.from(512),
      );
      await settle(c);
      expect(c.canonical, before);
      expect(c.settings['corridor_width'], isNull);
      expect(c.result, same(old));
      expect(c.canSave, false);
      c.editSetting(
        'corridor_width',
        '2',
        min: BigInt.one,
        max: BigInt.from(512),
      );
      await settle(c);
      expect(c.settings['corridor_width'], 2);
      expect(c.canSave, true);
      expect(c.result, same(old));
    },
  );

  test(
    'room dimension controls edit schema range endpoints without scalar keys',
    () async {
      final project = decodeExact(source) as Map<String, dynamic>;
      project['source']['settings']['room_width'] = [4, 12];
      project['source']['settings']['room_height'] = [5, 14];
      await c.load(encodeExact(project));
      c.editSetting(
        'min_room_width',
        '6',
        min: BigInt.one,
        max: BigInt.from(512),
      );
      await settle(c);
      expect(c.settings['room_width'], [6, 12]);
      expect(c.settings.containsKey('min_room_width'), false);
      c.editSetting(
        'max_room_height',
        '15',
        min: BigInt.one,
        max: BigInt.from(512),
      );
      await settle(c);
      expect(c.settings['room_height'], [5, 15]);
      expect(c.settings.containsKey('max_room_height'), false);
      final saved = c.canonical;
      validator.normalizations.add(rejected);
      c.editSetting(
        'min_room_width',
        '13',
        min: BigInt.one,
        max: BigInt.from(512),
      );
      await settle(c);
      expect(c.canonical, saved);
      expect(c.settings['room_width'], [6, 12]);
      expect(c.canSave, false);
      c.editSetting(
        'min_room_width',
        '7',
        min: BigInt.one,
        max: BigInt.from(512),
      );
      await settle(c);
      expect(c.settings['room_width'], [7, 12]);
      expect(c.canSave, true);
    },
  );

  test('queued dimension edits retain both values in the latest validated draft', () async {
    final project = decodeExact(source) as Map<String, dynamic>;
    project['source']['settings']['room_width'] = [4, 12];
    project['source']['settings']['room_height'] = [5, 14];
    await c.load(encodeExact(project));
    c.editSetting('min_room_width', '6', min: BigInt.one, max: BigInt.from(512));
    c.editSetting('max_room_height', '15', min: BigInt.one, max: BigInt.from(512));
    await settle(c);
    expect(c.settings['room_width'], [6, 12]);
    expect(c.settings['room_height'], [5, 15]);
    expect(c.settingValue('min_room_width'), 6);
    expect(c.settingValue('max_room_height'), 15);
    expect(c.canSave, true);
  });

  test(
    'catalogue and active inventory survive save/reopen with distinct IDs',
    () async {
      final project = decodeExact(c.canonical) as Map<String, dynamic>;
      project['source']['packs'] = [
        pack('copy-1'),
        pack('copy-2', active: false),
      ];
      validator.edits.add(accepted(project));
      expect(await c.savePack(pack('copy-1')), true);
      expect(c.catalogue.length, 2);
      expect(c.activePackCount, 1);
      expect(c.nextPackId(), isNot(anyOf('copy-1', 'copy-2')));
      final saved = c.canonical;
      c.markSaved(saved, 'inventory.json');
      expect(c.dirty, false);
      expect(await c.load(saved, name: 'inventory.json'), true);
      expect(c.catalogue.map((p) => p['id']).toSet(), {'copy-1', 'copy-2'});
      expect(
        c.catalogue.singleWhere((p) => p['id'] == 'copy-2')['active'],
        false,
      );
      expect(c.activePackCount, 1);
    },
  );

  test(
    'duplicate creates a distinct inventory-copy ID and remove targets that ID',
    () async {
      final project = decodeExact(source) as Map<String, dynamic>;
      project['source']['packs'] = [pack('pack-1')];
      await c.load(encodeExact(project));
      final duplicate = {...pack('pack-2'), 'name': 'Skeleton patrol copy'};
      final copied = decodeExact(c.canonical) as Map<String, dynamic>;
      copied['source']['packs'].add(duplicate);
      validator.edits.add(accepted(copied));
      expect(await c.duplicatePack('pack-1'), true);
      final command = decodeExact(validator.requests.last.raw)['command'];
      expect(command['pack'], duplicate);
      expect(c.catalogue.length, 2);
      expect(c.catalogue.first['id'], 'pack-1');
      validator.edits.add(accepted(project));
      expect(await c.removePack('pack-2'), true);
      expect(decodeExact(validator.requests.last.raw)['command'], {
        'type': 'remove_pack',
        'id': 'pack-2',
      });
      expect(c.catalogue.single['id'], 'pack-1');
    },
  );

  test(
    'allocation edits preserve geometry and Optimize uses reallocate only',
    () async {
      await c.run();
      final geometry = c.geometryRevision;
      expect(c.geometryCurrent, true);
      final project = decodeExact(c.canonical) as Map<String, dynamic>;
      project['source']['packs'] = [pack('new-pack')];
      validator.edits.add(accepted(project));
      expect(await c.savePack(pack('new-pack')), true);
      expect(c.geometryRevision, geometry);
      expect(c.geometryCurrent, true);
      expect(c.stale, true);
      expect(c.canOptimize, true);
      await c.optimize();
      expect(engine.requests.last.operation, EngineOperation.reallocate);
      expect(engine.requests.last.raw, c.canonical);
      expect(c.stale, false);
      c.editSetting(
        'seed',
        '43',
        min: BigInt.zero,
        max: BigInt.from(4294967295),
      );
      await settle(c);
      expect(c.geometryCurrent, false);
      expect(c.canOptimize, false);
      final count = engine.requests.length;
      await c.optimize();
      expect(engine.requests.length, count);
    },
  );

  test(
    'Optimize rejects obsolete asynchronous allocation after an edit',
    () async {
      await c.run();
      final old = c.result;
      engine.pending = Completer<EngineResult>();
      final task = c.optimize();
      expect(c.busy, true);
      c.editSetting(
        'threat_budget',
        '1',
        min: BigInt.zero,
        max: BigInt.from(100),
      );
      await settle(c);
      engine.pending!.complete(success('obsolete-allocation'));
      await task;
      expect(c.result, same(old));
      expect(c.stale, true);
      expect(c.geometryCurrent, true);
    },
  );

  test(
    'more than fourteen active packs are saved but cannot execute exact solve',
    () async {
      final project = decodeExact(source) as Map<String, dynamic>;
      project['source']['packs'] = List.generate(15, (i) => pack('copy-$i'));
      expect(await c.load(encodeExact(project)), true);
      expect(c.activePackCount, 15);
      expect(ProjectController.exactPackLimit, 14);
      expect(c.canSave, true);
      expect(c.canOptimize, false);
      expect(c.canRun, true);
      final count = engine.requests.length;
      await c.run();
      expect(engine.requests.length, count);
      await c.run(geometryOnly: true);
      expect(engine.requests.last.operation, EngineOperation.generateDungeon);
    },
  );
}

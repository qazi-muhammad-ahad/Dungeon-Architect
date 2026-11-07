import 'dart:convert';

import 'package:dungeon_architect/editor/allocation_decision.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> acceptedRun() => {
  'stages': {
    'allocation': {
      'pack_bit_order': ['a', 'z'],
    },
  },
  'result': {
    'source_project': {
      'source': {
        'settings': {'threat_budget': 3},
        'packs': [
          {
            'id': 'z',
            'name': 'Guard pair',
            'slots': 2,
            'threat': 7,
            'score': 9,
          },
          {'id': 'a', 'name': 'Archer', 'slots': 1, 'threat': 1, 'score': 5},
        ],
      },
    },
    'layout': {
      'rooms': [
        {'id': 'study', 'name': 'Study'},
      ],
    },
    'geometry': {
      'rooms': [
        {'id': 'study', 'capacity': 4},
      ],
    },
  },
};

Map<String, dynamic> event(String kind, int subset, {String room = 'study'}) =>
    {
      'stage': 'allocation',
      'event': {
        'kind': kind,
        'room_id': room,
        'mask': 3,
        'subset': subset,
        'decision_data': true,
        'sampled': true,
        'predecessor': 1,
        'room_compatible': true,
        'slots_fit': true,
        'predecessor_feasible': true,
        'subset_slots': 2,
        'subset_threat': 7,
        'inventory_threat': 8,
        'room_capacity': 2,
        'budget': 3,
      },
    };

void main() {
  test(
    'decision uses accepted bit order and recorded resource/feasibility facts',
    () {
      final result = acceptedRun();
      final record = event('candidate_feasible', 2);
      final before = jsonEncode([result, record]);
      final decision = AllocationDecision(record, result);
      expect(decision.packs.single['id'], 'z');
      expect(decision.packs.single['name'], 'Guard pair');
      expect(decision.room?['name'], 'Study');
      expect(
        decision.capacity,
        2,
        reason:
            'Recorded capacity takes precedence over final geometry metadata',
      );
      expect(decision.slots, 2);
      expect(decision.subsetThreat, 7);
      expect(decision.inventoryThreat, 8);
      expect(decision.budget, 3);
      expect(decision.predecessor, 1);
      expect(decision.sampled, true);
      expect(
        decision.feasible,
        true,
        reason: 'Room feasibility is separate from final budget selection',
      );
      expect(jsonEncode([result, record]), before);
      record['event']['room_compatible'] = false;
      expect(AllocationDecision(record, result).feasible, false);
    },
  );

  test('legacy or missing-order events do not fabricate pack identities or reasons', () {
    final result = acceptedRun();
    result['stages']['allocation'].remove('pack_bit_order');
    final record = event('candidate_infeasible', 2);
    record['event'].remove('decision_data');
    final decision = AllocationDecision(record, result);
    expect(decision.packs, isEmpty);
    expect(decision.evidence, false);
    expect(decision.compatible, isNull);
    expect(decision.slotsFit, isNull);
    expect(decision.priorFeasible, isNull);
    expect(decision.slots, isNull);
    expect(decision.inventoryThreat, isNull);
    expect(decision.predecessor, isNull);
    expect(
      decision.capacity,
      4,
      reason: 'Accepted final geometry is available context',
    );
    expect(decision.budget, 3);
  });

  test('reconstruction sprites include only the selected recorded prefix', () {
    final result = acceptedRun();
    final records = [
      event('candidate_feasible', 2),
      event('reconstruct', 2),
      {
        'stage': 'generation',
        'event': {'kind': 'reconstruct', 'subset': 1},
      },
      event('reconstruct', 1, room: 'hall'),
    ];
    expect(AllocationDecision.placements(records, -1, result), isEmpty);
    expect(AllocationDecision.placements(records, 0, result), isEmpty);
    expect(AllocationDecision.placements(records, 1, result), {'z': 'study'});
    expect(AllocationDecision.placements(records, 3, result), {
      'z': 'study',
      'a': 'hall',
    });
    expect(AllocationDecision.placements(records, 0, result), isEmpty);
  });
}

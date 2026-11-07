import 'template_catalogue.dart';

/// A presentation of recorded DP evidence using the accepted run's identities.
class AllocationDecision {
  AllocationDecision(Map<String, dynamic> record, Map<String, dynamic> result)
    : event = record['event'] as Map,
      source = result['result']?['source_project']?['source'] as Map? ?? {},
      order = result['stages']?['allocation']?['pack_bit_order'] as List? ?? [],
      payload = result['result'] as Map? ?? {} {
    final selected = kind == 'optimal'
        ? event['mask'] as int? ?? 0
        : event['subset'] as int? ?? 0;
    final inventory = effectivePacks(source);
    packs = [
      for (var i = 0; i < order.length; i++)
        if ((selected & (1 << i)) != 0)
          for (final pack in inventory)
            if (pack['id'] == order[i]) Map<String, dynamic>.from(pack as Map),
    ];
    room =
        (payload['layout']?['rooms'] as List? ?? [])
                .where((r) => r['id'] == roomId)
                .firstOrNull
            as Map?;
    final placed = (payload['geometry']?['rooms'] as List? ?? [])
        .where((r) => r['id'] == roomId)
        .firstOrNull;
    capacity = evidence ? event['room_capacity'] : placed?['capacity'];
    budget = evidence ? event['budget'] : source['settings']?['threat_budget'];
  }
  final Map event, source, payload;
  final List order;
  late final List<Map<String, dynamic>> packs;
  late final Map? room;
  late final dynamic capacity, budget;
  String get kind => event['kind'] as String? ?? '';
  String? get roomId => event['room_id'] as String?;
  bool get evidence => event['decision_data'] == true;
  bool get sampled => event['sampled'] == true;
  bool? get compatible => evidence ? event['room_compatible'] as bool? : null;
  bool? get slotsFit => evidence ? event['slots_fit'] as bool? : null;
  bool? get priorFeasible =>
      evidence ? event['predecessor_feasible'] as bool? : null;
  bool get feasible =>
      compatible == true && slotsFit == true && priorFeasible == true;
  dynamic get slots => evidence ? event['subset_slots'] : null;
  dynamic get subsetThreat => evidence ? event['subset_threat'] : null;
  dynamic get inventoryThreat => evidence ? event['inventory_threat'] : null;
  int? get predecessor => evidence ? event['predecessor'] as int? : null;

  static Map<String, String> placements(
    List<Map<String, dynamic>> events,
    int index,
    Map<String, dynamic> result,
  ) {
    final order =
        result['stages']?['allocation']?['pack_bit_order'] as List? ?? [];
    final placed = <String, String>{};
    for (final record in events.take(index + 1)) {
      if (record['stage'] != 'allocation') continue;
      final event = record['event'] as Map;
      if (event['kind'] != 'reconstruct') continue;
      final subset = event['subset'] as int? ?? 0;
      for (var i = 0; i < order.length; i++) {
        if ((subset & (1 << i)) != 0) {
          placed[order[i] as String] = event['room_id'] as String;
        }
      }
    }
    return placed;
  }
}

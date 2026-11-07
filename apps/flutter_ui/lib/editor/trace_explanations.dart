String traceStage(String stage) => switch (stage) {
  'generation' => 'Room generation (BSP)',
  'routing' => 'Corridor routing',
  'allocation' => 'Encounter allocation (exact subset DP)',
  _ => 'All algorithms',
};

String traceSpeed(double value) => value >= 1e21 || value < .001
    ? value.toString()
    : value.toString().replaceFirst(RegExp(r'\.0$'), '');

(String, String)? describeTrace(Map? record, Map? result) {
  final event = record?['event'] as Map?;
  if (event == null) return null;
  final kind = event['kind'];
  final bounds = event['bounds'];
  final region = 'Region ${event['node']}';
  final room = event['room_id'];
  final tile = event['tile'];
  final corridor = event['corridor_id'];
  final mask = event['mask'] as int? ?? 0;
  final subset = event['subset'] as int? ?? 0;
  final order =
      result?['stages']?['allocation']?['pack_bit_order'] as List? ?? [];
  final packs = [
    for (var i = 0; i < order.length; i++)
      if ((subset & (1 << i)) != 0) order[i],
  ];
  final choice = packs.isEmpty ? 'empty subset' : packs.join(', ');
  final transition =
      'State $mask · $choice (subset $subset) · predecessor ${mask ^ subset}.';
  final rectangle = bounds == null
      ? ''
      : '${bounds['width']} × ${bounds['height']} at (${bounds['x']}, ${bounds['y']})';
  return switch (kind) {
    'region_created' => ('Region created', '$region covers $rectangle.'),
    'fixed_reserved' => (
      'Fixed room preserved',
      '$room reserves $rectangle before partitioning.',
    ),
    'split_selected' => (
      'Split selected',
      '$region splits at ${event['reason']} = ${event['cut']}. The first child requests ${event['first_child_rooms']} rooms.',
    ),
    'split_rejected' => (
      'Split rejected',
      '$region could not fit the requested rooms across its proposed children.',
    ),
    'candidate_rejected' => (
      'Room candidate rejected',
      '$region tried $rectangle. Recorded reason: ${event['reason'].toString().replaceAll('_', ' ')}.',
    ),
    'room_placed' => ('Room placed', '$room fits in $region at $rectangle.'),
    'backtrack' => (
      'Backtracking',
      'The search returned to $region after a branch failed. Attempt ${event['attempt']}.',
    ),
    'routing_started' => (
      'Connection search started',
      'Search $corridor from $room to ${event['other_room_id'] ?? 'its destination'}. Breadth-first search starts at every legal source door and expands the queue until a destination door is reached.',
    ),
    'search_batch' => (
      'Breadth-first search',
      'Recorded queue discoveries and expansions for $corridor. Green squares show the queued frontier; blue links show actual parents.',
    ),
    'search_finished' => (
      'Destination reached',
      '$corridor expanded ${event['visited']} anchors and discovered ${event['discovered']}. ${event['omitted_steps'] == 0 ? 'The search reached a destination-door anchor.' : '${event['omitted_steps']} search operations omitted from this bounded capture.'}',
    ),
    'reconstruct_batch' => (
      'Following parent links',
      'Walk backward from the destination through recorded parents to reconstruct $corridor. Gold marks the recorded reverse path.',
    ),
    'reconstruction_finished' => (
      'Path reconstructed',
      'The parent chain reached its source door. ${event['omitted_steps'] == 0 ? 'Parent reconstruction reached the source door.' : '${event['omitted_steps']} reverse steps omitted; the completed corridor will show final context.'}',
    ),
    'carve_batch' => (
      'Carving corridor width',
      'The router carves ${event['width']} × ${event['width']} floor footprints along the reconstructed path.',
    ),
    'carving_finished' => (
      'Floor footprints carved',
      event['omitted_steps'] == 0
          ? 'Carving reached the end of the path.'
          : '${event['omitted_steps']} carve anchors omitted; completion reveals the accepted corridor.',
    ),
    'anchor_visited' => (
      'Search anchor visited',
      'The router visited (${tile?['x']}, ${tile?['y']}) for $corridor. Only captured visits are highlighted.',
    ),
    'door_selected' => (
      'Door selected',
      '$corridor connects through the door in $room at (${tile?['x']}, ${tile?['y']}).',
    ),
    'corridor_routed' => (
      'Corridor connected',
      '$corridor is complete. Its accepted floor remains visible while the next connection is searched.',
    ),
    'geometry_completed' => (
      'Walkable dungeon verified',
      'Routing and floor derivation finished. The validated final walls, doors and entrance/exit markers are now shown.',
    ),
    'room_reachable' => (
      'Room reachable',
      '$room can be reached from the entrance.',
    ),
    'preflight' => (
      'Allocation prepared',
      'The exact solver prepares eligible rooms and active packs.',
    ),
    'candidate_empty_feasible' || 'candidate_feasible' => (
      'Candidate feasible',
      '$room can take this subset and the previous rooms can supply the remainder. $transition',
    ),
    'candidate_empty_infeasible' || 'candidate_infeasible' => (
      'Candidate infeasible',
      'The subset or its predecessor failed feasibility for $room. $transition',
    ),
    'state_feasible' => (
      'State reachable',
      'The solver stored a feasible predecessor for $room. $transition',
    ),
    'state_infeasible' => (
      'State unreachable',
      'No feasible predecessor was found for $room at state $mask.',
    ),
    'room_summary' => (
      'Room processed',
      '$room leaves ${event['states']} reachable inventory states.',
    ),
    'reconstruct' => (
      'Assignment reconstructed',
      'Backtracking assigns $choice to $room. Inventory before ${mask ^ subset} · assigned subset $subset · remaining $mask.',
    ),
    'optimal' => (
      'Exact optimum selected',
      'The winning inventory mask is $mask. The accepted allocation supplies the encounter sprites.',
    ),
    _ => (
      'Recorded decision',
      'The engine recorded ${kind.toString().replaceAll('_', ' ')}.',
    ),
  };
}

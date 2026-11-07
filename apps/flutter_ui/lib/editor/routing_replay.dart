class TraceTile {
  const TraceTile(this.x, this.y);
  factory TraceTile.fromMap(Map value) =>
      TraceTile(value['x'] as int, value['y'] as int);
  final int x, y;
  String get key => '$x,$y';
}

/// Applies only captured routing events. Rewinding rebuilds their bounded prefix.
class RoutingReplay {
  RoutingReplay();
  factory RoutingReplay.fromEvents(
    List<Map<String, dynamic>> events,
    int index,
  ) => RoutingReplay()..update(events, index);
  List<Map<String, dynamic>>? _events;
  int _index = -1, _sourceSequence = -1;
  String? corridorId, fromRoom, toRoom;
  String phase = '';
  int width = 1, omittedSteps = 0, visited = 0, discoveredCount = 0;
  bool hasGaps = false, geometryComplete = false;
  TraceTile? currentTile;
  final Map<String, TraceTile> discovered = {}, expanded = {}, parents = {};
  final List<TraceTile> reconstructed = [];
  final Map<String, (TraceTile, int)> carved = {};
  final Set<String> completedCorridors = {}, selectedDoors = {};
  Iterable<TraceTile> get frontier => discovered.entries
      .where((entry) => !expanded.containsKey(entry.key))
      .map((entry) => entry.value);
  bool get sampled => hasGaps || omittedSteps > 0;

  void update(List<Map<String, dynamic>> events, int index) {
    final target = index.clamp(-1, events.length - 1);
    if (!identical(_events, events) || target < _index) {
      _events = events;
      _index = -1;
      _sourceSequence = -1;
      corridorId = fromRoom = toRoom = null;
      phase = '';
      width = 1;
      visited = discoveredCount = omittedSteps = 0;
      hasGaps = geometryComplete = false;
      currentTile = null;
      discovered.clear();
      expanded.clear();
      parents.clear();
      reconstructed.clear();
      carved.clear();
      completedCorridors.clear();
      selectedDoors.clear();
    }
    while (_index < target) {
      final record = events[++_index];
      if (record['stage'] != 'routing') continue;
      final sequence = record['source_sequence'] as int?;
      if (sequence != null) {
        if (sequence != _sourceSequence + 1) hasGaps = true;
        _sourceSequence = sequence;
      }
      _apply(record['event'] as Map);
    }
  }

  void _apply(Map event) {
    phase = event['kind'] as String;
    final id = event['corridor_id'] as String? ?? '';
    if (phase == 'routing_started') {
      corridorId = id;
      fromRoom = event['room_id'] as String?;
      toRoom = event['other_room_id'] as String?;
      discovered.clear();
      expanded.clear();
      parents.clear();
      reconstructed.clear();
      currentTile = null;
      visited = discoveredCount = 0;
    } else if (id.isNotEmpty && id != corridorId) {
      // Sampling may omit a connection's start. Never merge its search state.
      corridorId = id;
      fromRoom = toRoom = null;
      discovered.clear();
      expanded.clear();
      parents.clear();
      reconstructed.clear();
      hasGaps = true;
    }
    width = event['width'] as int? ?? width;
    omittedSteps += event['omitted_steps'] as int? ?? 0;
    if (event['visited'] is int) visited = event['visited'] as int;
    if (event['discovered'] is int) {
      discoveredCount = event['discovered'] as int;
    }
    for (final raw in event['steps'] as List? ?? []) {
      final step = raw as Map;
      final tile = TraceTile.fromMap(step['tile'] as Map);
      currentTile = tile;
      final parent = step['parent'] as Map?;
      if (parent != null && (parent['x'] as int) >= 0) {
        parents[tile.key] = TraceTile.fromMap(parent);
      }
      switch (step['kind']) {
        case 'discovered':
          discovered[tile.key] = tile;
        case 'expanded':
          expanded[tile.key] = tile;
        case 'path':
          reconstructed.add(tile);
        case 'carve':
          carved['$id:${tile.key}'] = (tile, width);
      }
    }
    if (phase == 'door_selected') selectedDoors.add('$id:${event['room_id']}');
    if (phase == 'corridor_routed') completedCorridors.add(id);
    if (phase == 'geometry_completed') geometryComplete = true;
  }
}

// Starter versions derive from the teaching project's Archer, Guard pair,
// Ogre crowd and Lava spirit. Keep that fixture's restrictive rules intact.
const _starters = [
  ('archer', 'Archer', 1, 1, 5, <String>[]),
  ('guard', 'Guard pair', 2, 2, 9, <String>[]),
  ('lava', 'Lava spirit', 1, 4, 10, <String>[]),
  ('ogre', 'Ogre Boss', 4, 7, 20, ['exit']),
];

List<dynamic> pinnedPacks(Map? source) =>
    source?['template_catalogue']?['packs'] as List? ?? const [];

List<dynamic> effectivePacks(Map? source) {
  final custom = source?['packs'] as List? ?? const [];
  return custom.isEmpty ? pinnedPacks(source) : custom;
}

Map<String, dynamic> starterCatalogue(Map source) {
  final ids = (source['packs'] as List).map((p) => p['id']).toSet();
  return {
    'version': 'starter-v2',
    'packs': [
      for (final (key, name, slots, threat, score, roles) in _starters)
        {
          'id': _availableId('template-$key', ids),
          'name': name,
          'active': true,
          'slots': slots,
          'threat': threat,
          'score': score,
          'min_room_width': 2,
          'min_room_height': 2,
          'allowed_roles': roles,
          'required_tags': [],
        },
    ],
  };
}

String _availableId(String base, Set<dynamic> ids) {
  var candidate = base;
  var suffix = 1;
  while (!ids.add(candidate)) {
    candidate = '$base-${suffix++}';
  }
  return candidate;
}

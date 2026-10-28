import 'package:flutter/material.dart';

import 'exact_json.dart';
import 'project_controller.dart';

List<String> _tags(String text) =>
    text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
dynamic _integer(String text) {
  final value = BigInt.parse(text);
  return value <= BigInt.from(9007199254740991) ? value.toInt() : value;
}

Future<void> editPack(
  BuildContext context,
  ProjectController c, [
  Map<String, dynamic>? existing,
]) => showDialog<void>(
  context: context,
  builder: (_) => _PackEditor(controller: c, existing: existing),
);

class _PackEditor extends StatefulWidget {
  const _PackEditor({required this.controller, this.existing});
  final ProjectController controller;
  final Map<String, dynamic>? existing;
  @override
  State<_PackEditor> createState() => _PackEditorState();
}

class _PackEditorState extends State<_PackEditor> {
  final form = GlobalKey<FormState>();
  late final c = widget.controller;
  late final Map<String, dynamic> draft = widget.existing == null
      ? {
          'id': c.nextPackId(),
          'name': 'New encounter',
          'active': true,
          'slots': 1,
          'threat': 0,
          'score': 0,
          'min_room_width': 1,
          'min_room_height': 1,
          'allowed_roles': <String>[],
          'required_tags': <String>[],
        }
      : decodeExact(encodeExact(widget.existing)) as Map<String, dynamic>;
  bool saving = false;
  String? error;
  Widget field(
    String label,
    String key, {
    bool number = false,
    bool positive = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: '${draft[key]}',
      decoration: InputDecoration(labelText: label),
      keyboardType: number ? TextInputType.number : TextInputType.text,
      enabled: !saving,
      validator: (text) {
        if (!number) {
          return text == null || text.trim().isEmpty ? 'Enter a name.' : null;
        }
        final value = BigInt.tryParse(text ?? '');
        return value == null ||
                value < BigInt.from(positive ? 1 : 0) ||
                value > BigInt.parse('9223372036854775807')
            ? 'Enter a ${positive ? 'positive' : 'nonnegative'} whole number within int64.'
            : null;
      },
      onSaved: (value) =>
          draft[key] = number ? _integer(value!) : value!.trim(),
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'New pack' : 'Edit pack'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Inventory copy ID: ${draft['id']}'),
              const SizedBox(height: 12),
              field('Pack name', 'name'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active inventory'),
                subtitle: const Text(
                  'Inactive entries stay saved in the catalogue.',
                ),
                value: draft['active'] as bool,
                onChanged: saving
                    ? null
                    : (v) => setState(() => draft['active'] = v),
              ),
              field(
                'Slots (spawn positions)',
                'slots',
                number: true,
                positive: true,
              ),
              field('Threat (points)', 'threat', number: true),
              field('Designer score (points)', 'score', number: true),
              field(
                'Minimum room width (tiles)',
                'min_room_width',
                number: true,
                positive: true,
              ),
              field(
                'Minimum room height (tiles)',
                'min_room_height',
                number: true,
                positive: true,
              ),
              const Text(
                'Allowed roles · none selected means any non-entrance role',
              ),
              Wrap(
                children: [
                  for (final role in ['normal', 'exit', 'boss'])
                    FilterChip(
                      label: Text(role),
                      selected: (draft['allowed_roles'] as List).contains(role),
                      onSelected: saving
                          ? null
                          : (on) => setState(() {
                              final roles = draft['allowed_roles'] as List;
                              on ? roles.add(role) : roles.remove(role);
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: (draft['required_tags'] as List).join(', '),
                decoration: const InputDecoration(
                  labelText: 'Required tags (comma separated)',
                ),
                enabled: !saving,
                onSaved: (v) => draft['required_tags'] = _tags(v!),
              ),
              const SizedBox(height: 12),
              Text(
                'Exact solve supports ${ProjectController.exactPackLimit} active packs. Every duplicate gets its own ID.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                if (!form.currentState!.validate()) return;
                form.currentState!.save();
                setState(() {
                  saving = true;
                  error = null;
                });
                final ok = await c.savePack(draft);
                if (!mounted || !context.mounted) return;
                if (ok) {
                  Navigator.pop(context);
                } else {
                  setState(() {
                    saving = false;
                    error = c.message;
                  });
                }
              },
        child: const Text('Save pack'),
      ),
    ],
  );
}

Future<void> editRoom(
  BuildContext context,
  ProjectController c,
  Map<String, dynamic> room,
) => showDialog<void>(
  context: context,
  builder: (_) => _RoomEditor(controller: c, room: room),
);

class _RoomEditor extends StatefulWidget {
  const _RoomEditor({required this.controller, required this.room});
  final ProjectController controller;
  final Map<String, dynamic> room;
  @override
  State<_RoomEditor> createState() => _RoomEditorState();
}

class _RoomEditorState extends State<_RoomEditor> {
  final form = GlobalKey<FormState>();
  late final c = widget.controller;
  late final draft =
      decodeExact(encodeExact(widget.room)) as Map<String, dynamic>;
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final placed = (c.payload?['geometry']?['rooms'] as List? ?? []).where(
      (r) => r['id'] == draft['id'],
    );
    final positions = placed.isEmpty
        ? <dynamic>[]
        : placed.first['spawn_positions'] as List;
    return AlertDialog(
      title: const Text('Edit room details'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stable ID: ${draft['id']}'),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: draft['name'] as String,
                  decoration: const InputDecoration(labelText: 'Room name'),
                  enabled: !saving,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name.' : null,
                  onSaved: (v) => draft['name'] = v!.trim(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: draft['role'] as String,
                  decoration: const InputDecoration(labelText: 'Room role'),
                  items: [
                    for (final role in ['normal', 'entrance', 'exit', 'boss'])
                      DropdownMenuItem(value: role, child: Text(role)),
                  ],
                  onChanged: saving ? null : (v) => draft['role'] = v,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: (draft['tags'] as List).join(', '),
                  decoration: const InputDecoration(
                    labelText: 'Compatibility tags (comma separated)',
                  ),
                  enabled: !saving,
                  onSaved: (v) => draft['tags'] = _tags(v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: draft['capacity_override']?.toString() ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Capacity (slots; blank = all valid positions)',
                  ),
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v!.trim().isEmpty) return null;
                    final n = int.tryParse(v);
                    if (n == null || n < 0 || n > 262144) {
                      return 'Enter 0–262144 slots or leave blank.';
                    }
                    if (draft['role'] == 'entrance' && n != 0) {
                      return 'Entrance capacity must be 0 slots or blank.';
                    }
                    if (c.geometryCurrent &&
                        placed.isNotEmpty &&
                        draft['role'] == widget.room['role'] &&
                        n > positions.length) {
                      return 'Maximum ${positions.length} slots in the current valid positions.';
                    }
                    return null;
                  },
                  onSaved: (v) => draft['capacity_override'] = v!.trim().isEmpty
                      ? null
                      : int.parse(v),
                ),
                const SizedBox(height: 12),
                Text(
                  '${positions.length} valid spawn positions${c.geometryCurrent ? '' : ' · previous geometry; regenerate to inspect current positions'}',
                ),
                if (positions.isNotEmpty)
                  ExpansionTile(
                    title: const Text('Inspect valid positions'),
                    children: [
                      SelectableText(
                        positions
                            .map(
                              (p) =>
                                  '${p['id']}: (${p['tile']['x']}, ${p['tile']['y']})',
                            )
                            .join('\n'),
                      ),
                    ],
                  ),
                if (!(c.source['rooms'] as List? ?? []).any(
                  (r) => r['id'] == draft['id'],
                ))
                  const Text(
                    'Saving a generated room preserves it at this position and size. Generate again once to refresh geometry.',
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  form.currentState!.save();
                  if (!(c.source['rooms'] as List? ?? []).any(
                    (r) => r['id'] == draft['id'],
                  )) {
                    draft['lock_position'] = true;
                    draft['lock_size'] = true;
                  }
                  setState(() {
                    saving = true;
                    error = null;
                  });
                  final ok = await c.saveRoom(draft);
                  if (!mounted || !context.mounted) return;
                  if (ok) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      saving = false;
                      error = c.message;
                    });
                  }
                },
          child: const Text('Save room'),
        ),
      ],
    );
  }
}

class EncounterCatalogue extends StatelessWidget {
  const EncounterCatalogue({super.key, required this.controller});
  final ProjectController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Encounter catalogue',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'New pack',
              onPressed: c.canRun ? () => editPack(context, c) : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
        Text(
          '${c.activePackCount} active / ${ProjectController.exactPackLimit} exact-solve limit · ${c.catalogue.length} saved',
        ),
        if (c.activePackCount > ProjectController.exactPackLimit)
          const Text(
            'Too many active packs for exact optimization. Deactivate entries; Generate only remains available.',
          ),
        for (final item in c.catalogue)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item['name']} · ${item['id']}',
                        maxLines: 2,
                      ),
                    ),
                    Switch(
                      value: item['active'] as bool,
                      onChanged: c.canRun
                          ? (v) {
                              final p = Map<String, dynamic>.from(item as Map);
                              p['active'] = v;
                              c.savePack(p);
                            }
                          : null,
                    ),
                  ],
                ),
                Text(
                  '${item['slots']} slots · ${item['threat']} threat · ${item['score']} score',
                  style: const TextStyle(fontSize: 11),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: c.canRun
                          ? () => editPack(
                              context,
                              c,
                              Map<String, dynamic>.from(item as Map),
                            )
                          : null,
                      child: const Text('Edit pack'),
                    ),
                    IconButton(
                      tooltip: 'Duplicate pack',
                      onPressed: c.canRun
                          ? () => c.duplicatePack(item['id'] as String)
                          : null,
                      icon: const Icon(Icons.copy, size: 16),
                    ),
                    IconButton(
                      tooltip: 'Remove pack',
                      onPressed: c.canRun
                          ? () => c.removePack(item['id'] as String)
                          : null,
                      icon: const Icon(Icons.delete_outline, size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

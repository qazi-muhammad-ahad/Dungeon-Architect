# Room and encounter editing

The inspector exposes runtime room count, width/height ranges, corridor width,
margin, seed and global threat budget. Width/height edits update the existing
two-element range arrays in the source schema. Pending edits are validated by
C++; rejected proposals preserve the committed source and previous output.

Use **Room tools → Draw fixed room**, drag its interior, inspect the outlined
preview, then **Apply room**. Invalid containment, separation, margins or total
fixed count return native diagnostics. Select rooms from the canvas or Explorer.
**Edit room details** changes name, role, compatibility tags and optional capacity;
the dialog lists actual valid spawn IDs and coordinates after generation.
With current geometry, capacity edits cannot exceed that room's valid position
count; an entrance capacity is zero. Role changes require fresh geometry and
native generation/allocation validates the resulting capacity again.
Saving details for a generated room preserves its current geometry as a source
room and requires one generation before allocation-only reuse.

Fixed rooms keep their stable IDs during regeneration. **Unlock room** is a
separate edit before **Move unlocked room** or **Resize unlocked room**. Drag the
unlocked source room and commit the validated preview; applying the new bounds
fixes them again. A locked room cannot be moved, resized or removed by combining
the geometry change with an unlock. Room role changes require regeneration
because entrance/exit selection and reserved movement space depend on them.

The **Encounter catalogue** stores active and inactive entries together. Create,
edit, duplicate or remove entries without JSON editing. Each inventory copy has
a distinct generated ID. Slots count spawn positions; threat and designer score
are nonnegative integer points. Minimum room dimensions are tile counts.
Allowed roles and required room tags control compatibility. Empty allowed roles
means any non-entrance role; all required tags must match. Large integer fields
retain exact int64 values through source edits and saving.

The active count and 14-pack exact limit appear before solving. Inactive entries
stay saved, and catalogues above the active limit can still be edited and saved.
**Generate only** builds rooms and corridors independently of that limit.
**Generate & solve** performs the full pipeline; **Optimize** reuses the current
verified geometry after pack, threat-budget, room-tag or capacity changes.
The inspector states whether geometry needs generation or only allocation needs
optimization. Geometry inputs cannot be silently reused after they change.

Successful allocation shows assigned packs and slots in the room inspector,
actors on the map, total score/threat/slots, and native unused-pack explanations.
Old output stays visible with the stale label after edits or failed work. Save
and reopen uses the same versioned source format, including room locks and all
catalogue entries; derived output is recomputed after reopening.

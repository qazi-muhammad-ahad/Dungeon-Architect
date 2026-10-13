# Masks and fixed rooms (phase 03)

The public C++ API is `core/include/dungeon_architect/geometry.h`. Link
`dungeon_core`; no Flutter runtime or file IO is needed for these operations.

## Mask operations

All cells use integer `(x, y)`, origin at the top left, and row-major storage.
Rectangles are half-open: `(x, y, width, height)` includes `x..x+width-1` and
`y..y+height-1`. Presets replace the entire mask, leaving cells outside their
specified bounds disallowed. Rectangle fills every cell; ellipse tests cell
centers using exact integer arithmetic; L-shape fills the left half and bottom
half, rounding each arm upward for odd dimensions. An L needs at least 2 × 2.

`paint_tiles` applies a complete stroke, including erase (`allowed=false`).
Out-of-bounds tiles reject the whole stroke. `flood_fill` uses four-neighbor
connectivity, changing only the connected region with the starting tile's old
value. All editing functions copy, validate, and commit through `ProjectSession`.
No-op edits do not bump revisions. Erasing a room or its margin rejects the
edit and preserves all source data and previous result snapshots.

`analyze_mask` returns one label per cell (`-1` outside) and each component's
tiles and bounds. Component IDs follow first encounter in row-major order;
BFS neighbors are north, east, south, west. The largest component is primary;
ties use the lowest ID. All other components can be highlighted as detached.
Disconnected regions remain part of the user's mask. Primary is a display
classification, not an instruction for the future generator to discard islands.

## Geometry validation and reservations

`validate_project` now checks all source room geometry, including unlocked
rooms, after the structural checks from phase 02. Each room and its rectangular
margin must fit the canvas and allowed mask, including every hole. Rooms need
positive dimensions, unique valid IDs, known roles, and no overlap. Entrance
and exit may each appear at most once. Generated room size ranges do not resize
or invalidate a differently sized fixed room that otherwise fits.

Margin `m` means at least `m` tiles between room interiors and `m` allowed tiles
around a room at the mask/canvas boundary. Reservation buffers can overlap: two
rooms separated by one tile are valid with margin 1. With margin 0, interiors
may touch each other or the canvas edge, but never overlap. Diagnostics include
room IDs and a representative offending tile, including coordinates outside the
canvas for a boundary violation. Tile coordinates and IDs survive JSON reporting.

A room with either lock flag is mandatory. `prepare_geometry` takes an immutable
copy of its whole current footprint and reserves its margin conservatively.
Both flags retain their separate editing meaning, but generation must preserve
the complete geometry of a room with either flag set. Fully unlocked source
rooms are editable proposals that generation may replace. The requested total
includes mandatory rooms; a count below that number is invalid.

`PreparedGeometry` exposes component analysis, mandatory/remaining counts, and
an immutable `ReservationMap`. `blocked()` contains the union of fixed interiors
and margins; `footprint_owners()` maps interiors to canonical fixed-room indexes
and uses `-1` elsewhere. The underlying allowed mask is never changed.
`can_place(rect)` checks every candidate and margin tile against the allowed
mask and every candidate interior tile against reservations. An abstract BSP
region crossing a lock cannot clear the reservation or resize its copied room.
Later generation must call this API and preserve its fixed-room collection;
BSP splitting itself belongs to phase 04.

Preflight rejects an empty building area, mandatory rooms on different mask
components, and a total with insufficient non-boss room slots for the terminals.
An empty mask without rooms is still a valid editable source document.
Successful preflight is **not a guarantee** that the requested room count fits,
that corridor width clears a narrow neck, or that a dungeon can be connected.
Those checks belong to the actual generation/routing phases.

## Room editing and terminals

`add_room`, `edit_room`, and `remove_room` address rooms by stable ID. Rename or
reorder does not change identity. An edit cannot replace an ID. Session updates
also enforce old locks: moving a position lock, resizing a size lock, or deleting
a locked room fails. Unlock in one successful edit before moving/resizing/removing
in the next. Loading a different project intentionally replaces the whole source.

Run `select_terminals` on the complete generated room collection. Explicit roles
win. If missing, entrance uses the lowest normal-room ID, then exit uses the
highest remaining normal-room ID. Boss rooms keep their role; terminals must be
distinct. Selection returns IDs without mutating the input collection.
`encounter_capacity` always returns zero for the entrance; otherwise it returns
the smaller of the valid spawn count and optional capacity override. Computing
actual spawn positions is now implemented by phase 05; routing rejects overrides
above the valid count instead of silently clamping an impossible source override.

## Verification

`core.geometry` checks presets, paint/fill transactions, boundary/mask/margin
conflicts, counts, individual lock flags, terminal rules, stable IDs, and immutable
reservations. It independently checks component equivalence for **all 512 possible
3 × 3 masks** against an all-pairs reachability oracle. `cli.geometry` exercises
the real executable, including file preservation after rejected edits, canonical
JSON output, ASCII reservations, and the edge-case fixtures.

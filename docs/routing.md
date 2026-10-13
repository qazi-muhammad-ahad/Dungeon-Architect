# Corridor routing and walkable geometry — phase 05

## Algorithm contract (specified before implementation)

```text
route(source, accepted room layout, cancellation/work/deadline limits):
  refresh fixed-room display/allocation metadata from current source
  validate the room layout; initialize floor from room interiors
  for each abstract connection in recorded order:
    enumerate width-wide doors in N/E/S/W order, then ascending edge coordinate
    represent a corridor by top-left anchors of width × width squares
    require each square wholly inside the mask and outside every room interior
    forbid side contact with room interiors except through explicit door cells
    run multi-source BFS over legal anchors, neighbors N/E/S/W
      start at all legal outside squares of the first room's doors
      stop at the first square of a legal second-room door
      reuse previous corridor/door cells when legal
    if no path: reject this layout, never narrow a corridor or carve a room
    record both doors, the anchor path, and its full square-footprint union
  select room hub cells nearest the rectangle center, preferring non-door cells
  use entrance/exit hubs as distinct markers on their selected rooms' floor
  reserve corridors and deterministic horizontal-then-vertical door-to-hub lanes
  flood the actual floor from entrance; require every floor cell/room reachable
  derive walls on allowed non-floor tiles adjacent (8-neighbor) to floor
  enumerate spawn cells every two tiles on each room's local x/y lattice
    exclude doors, markers and reserved movement lanes; entrance capacity = 0
    reject an override above the number of valid cells (or above 0 at entrance)
  independently validate paths, doors, floor union, walls, connectivity,
    movement lanes, spawn exclusion/spacing, capacity and markers
  publish only the complete candidate if source and room-layout IDs still match
```

A width is never approximated by a centerline. Every BFS position represents an
entire square footprint; adjacent square unions maintain clearance through turns.
Search is global to the mask and can leave BSP child rectangles. Door cells are
existing room-boundary floor; outside squares touch a contiguous width-wide door
line without entering the interior. Unrelated room contact is forbidden unless
it uses an explicitly recorded door from an earlier connection.

Connection order and door order make routing reproducible. BFS finds the shortest
anchor path for the current connection under these rules. Greedy connection
ordering is not a global routing feasibility proof: failure is reported as search
exhausted for this layout, with room IDs/locations and suggestions to regenerate
or change space/width. Width never changes automatically. Bounded source/layout
validation runs before/after interruptible work; cancellation and deadline checks
surround these bounded checks. Work/time limits apply separately to the room
generation and routing stages. The BSP attempt limit does not cap BFS nodes.

Validation/publication is a bounded synchronous section; these limits are
cooperative checkpoints, not real-time thread preemption. Callbacks must not
throw. Standalone callers must hold source inputs immutable during a job;
session overloads copy inputs and reject stale results.

Room spacing can be too small for the requested corridor width even when BSP
succeeds. Such a room layout remains available; it is not published as a connected
floor snapshot. No UI, optimization, or gameplay algorithm is added in this phase.

## API and derived data

`routing.h` exposes `route_corridors(source, room_layout, options)`, its
`ProjectSession` overload, and `validate_routed_geometry`. A failed result has no
geometry value. The session overload requires a current room layout and retains
previous geometry after failure. It rejects changes to either source revision or
the room-layout ID while running. Geometry publication validates complete routed
data when a room layout is present; incomplete/corrupt snapshots are refused.

`GeometrySnapshot` records the originating room-layout ID, corridor anchor paths,
both explicit door records per corridor, room reachability, floor/walls, immutable
room occupancy/reservations, entrance/exit markers, movement reservations, spawn
IDs/cells, and effective room capacities. There is no enemy placement yet.

Hubs use nearest rectangle-center Manhattan distance (doubled integer centers),
preferring non-door cells, then row/column ties. Room-local spawn coordinates use
even offsets in x and y, ensuring Chebyshev separation of at least two tiles.
The complete valid spawn list is retained even when a smaller override limits
capacity. Entrance spawn list/capacity is always zero. Effective capacities are
captured for the source metadata at routing time; later allocation must apply
current source overrides against the stored valid spawn count. Metadata updates
invalidate allocation without discarding valid floor geometry. Rerouting refreshes
fixed-room names/tags/capacity from current source without changing their geometry.

Prefix tables check the mask and room occupancy in constant time per candidate
anchor. A per-connection contact table excludes unrecorded room openings. Each
BFS visits at most the canvas's number of anchor positions, using O(canvas area)
memory; for E abstract connections, routing search is O(E × canvas area), plus
door enumeration, full-footprint rasterization, and independent result checks.
Work budgets count these operations (including charged final-validation work).
Trace storage is capped at 4096 events; changing its capacity does not alter paths.

## CLI testing

```powershell
cd 'E:\Uni\sem5\DAA\Dungeon Architect'
.\tools\build-native.ps1 -Configuration Debug
$cli = '.\build\windows-debug\bin\dungeon_cli.exe'
& $cli route datasets/routing/straight-width2.json
& $cli route datasets/routing/hole-detour-width2.json
& $cli route datasets/generation/standard-150.json --json --events 0

# Same narrow passage: width 1 succeeds, width 2 fails with exit 7.
& $cli route datasets/routing/narrow-neck-width1.json
& $cli route datasets/routing/narrow-neck-width2.json --json
```

`route` runs room generation first, then routing, with each stage's own budget.
The JSON stage identifies which stage failed. Successful route JSON includes
`connected_floor_verified: true`, full tile layers, doors, paths and spawn data.
The ASCII map uses `@` entrance, `>` exit, `+` door, `s` spawn, `.` floor,
`#` wall and `~` disallowed mask. Text is cropped to the top-left 80 × 40; JSON
contains the entire map. Input files are never modified. Result JSON is an
export for inspection, separate from schema-1 source project import/save.

Tests cover straight paths with known exact length/floor count, width-wide turns
around holes, overlapping corridor footprints, same-square door attachments,
too-wide doors, narrow-neck failure, safe entrance/spawn spacing, override limits,
corrupt snapshots, work/time/cancellation, and preservation of old results on
failed or stale publication. A separate flood traversal checks actual floor
connectivity; no assertion uses abstract connection edges as connectivity proof.

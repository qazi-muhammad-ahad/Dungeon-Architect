# Constrained BSP room generation — phase 04

## Algorithm contract (specified before implementation)

```text
generate(source, seed, limits, cancellation):
  check cancellation/deadline; validate source and prepare fixed reservations
  build summed-area tables for disallowed cells, unavailable interiors,
    and valid minimum-room top-left positions
  reject a provably insufficient free interior area or record count
  copy mandatory rooms intact; allocate collision-free generated IDs
  solve(canvas bounds, requested total minus mandatory rooms):
    checkpoint work/time/cancellation; record node and its free-area summaries
    zero target: return empty generated collection
    one target:
      enumerate size pairs and positions from seeded cyclic offsets
      count each candidate against the attempt budget
      require entire interior inside this region; entire margin inside mask
      require interior clear of fixed interiors and separation reservations
      return first valid room; otherwise fail this branch
    multiple targets:
      try longer-axis splits first (seeded choice on equal axes), then other axis
      enumerate cut positions from a seeded cyclic offset, leaving a margin gap
      bound child capacity by free tiles/minimum area, minimum dimensions,
        and the count of valid minimum-room origins inside each child
      enumerate feasible positive child counts, balanced by free area first
      count each split/count plan against the attempt budget
      solve left/top child, then right/bottom child
      on failure roll back this branch's nodes, rooms, and connection requirements
      on success combine children and link their first rooms abstractly
    stop a branch beyond depth 64; report exhausted search, not impossibility
  attach each canonical fixed room to the nearest already connected room
    (doubled-center Manhattan distance; ties by room ID)
  select distinct terminals; rasterize room interiors and reservation margins
  independently validate exact count, all cells, ranges, separation, locks,
    partition tree, and abstract connection tree
  checkpoint again; publish only if source/dependency revisions still match
```

Child bounds are half-open and separated by `margin` tiles. Therefore rooms
from distinct leaves cannot violate separation. Fixed rooms may cross any
abstract split; they are copied from immutable reservations, never extracted
from or cropped to partition bounds. All fixed rooms are attached after child
combination, including when there are no generated rooms.

Summed-area tables count bad mask cells and unavailable interior cells exactly,
so rectangle queries check every covered cell through a zero-count test. Free
area and minimum-dimension capacity are only upper bounds used for pruning;
neither is taken as proof that a room fits. This helper costs O(canvas area)
storage/build time and O(1) per rectangle query. A third table counts valid
minimum-room origins to prune children with no legal placement before recursing.
Origin counts are upper bounds because positions may overlap; even their
presence never proves that multiple rooms fit. Room candidates still require
both an interior reservation query and an expanded mask query.

Attempts mean proposed split/count plans plus proposed leaf rectangles across
the whole backtracking search, not complete dungeon restarts. Work units count
search operations, table cells, metadata scans, and final-validation estimates.
Preflight/source validation is bounded by the existing storage guards and
checked for cancellation/deadline before and after; it is not interruptible
inside its existing phase-03 API. Maximum trace storage is 4096 events, default
256; excess events are counted and dropped. Trace capacity changes neither
random draws nor deterministic work counts. Timed interruption may vary by PC.

No new random engine or primary algorithm is introduced. Raw MT19937 and the
existing rejection mapping drive explicit cyclic enumeration. Sizes enumerate
width fastest, then height; positions enumerate x fastest, then y. Completed
layouts are deterministic for the same source, seed, engine, and work limits.
Generated IDs use `generated-N` in accepted left/top-first traversal order,
skipping all existing source IDs. Canonical source order has no effect.

Outputs are room layouts, not walkable dungeons. Abstract edges are routing
requirements, not corridors. No carved-floor connectivity, spawn positions,
or encounter allocation is claimed in phase 04. The source project remains
unchanged; generated results live in a separate immutable session snapshot.

## API and CLI

`generation.h` exposes `generate_rooms(Project, options)` and its transactional
`ProjectSession` overload, `RoomLayoutSnapshot`, partition metadata, connection
requirements, metrics, and bounded events. A failed result has no layout.
`validate_room_layout` checks the output independently with cell scans. The
session retains the last snapshot on failure and rejects stale source revisions.
Successful publication invalidates allocation/play and makes older carved-floor
snapshots stale by their room-layout ID while retaining them for inspection.

```powershell
cd 'E:\Uni\sem5\DAA\Dungeon Architect'
.\tools\build-native.ps1 -Configuration Debug
$cli = '.\build\windows-debug\bin\dungeon_cli.exe'
& $cli generate datasets/generation/fixed-hole.json
& $cli generate datasets/generation/l-shape.json --seed 42 --json --events 32
& $cli generate datasets/generation/backtracking.json --json
& $cli generate datasets/generation/rectangle.json --attempts 1 --json
$LASTEXITCODE # 7: bounded search exhausted, no partial layout
```

`--seed`, `--attempts`, `--work`, and `--time-ms` override this run only. The input
file is never modified. `--events 0` disables trace storage without affecting
layout decisions. Ctrl+C requests cancellation (exit 6). JSON output is a
`format_version: 1`, `stage: room_layout` result, not an importable source project.
ASCII previews show at most the top-left 80 × 40 cells; JSON includes every cell.
Trace node indexes can be reused after rollback; `backtrack` events and attempt
numbers distinguish search history from the accepted partition tree.

The deterministic test matrix covers 16 seeds each on rectangles, ellipses,
L-shapes, and holed masks; a dense seed-2 case specifically exercises rollback.
Additional checks cover fixed-only/single-leaf layouts, ID collisions, corrupted
snapshots, work/attempt/deadline limits, mid-operation cancellation, stale source
publication, and canonical CLI output without modifying the source file.

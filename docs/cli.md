# CLI contract - phases 02 through 07

Run `dungeon_cli --help` for syntax. All project behavior is implemented in the
shared C++ libraries. No Flutter runtime is needed for these commands.

| Command | Behavior |
| --- | --- |
| `new FILE [--name NAME] [--seed UINT32] [--force] [--json]` | Create default 150 × 150 fully allowed source project; no rooms/packs generated |
| `validate FILE [--for-allocation] [--for-generation] [--json]` | Validate schema/domain data; optionally check inventory limit and/or geometry preflight |
| `inspect FILE [--json]` | Human summary, or canonical full source JSON |
| `save INPUT OUTPUT [--force] [--json]` | Validate input and atomically save its canonical source representation |
| `mask-info FILE [--json]` | Component analysis and ASCII mask/reservations, or full labels and reservation arrays as JSON |
| `mask INPUT OUTPUT rectangle\|ellipse\|l-shape X Y W H [--force] [--json]` | Replace the allowed mask with a bounded preset |
| `paint INPUT OUTPUT X Y 0\|1 [--force] [--json]` | Erase/paint one cell |
| `fill INPUT OUTPUT X Y 0\|1 [--force] [--json]` | Flood-fill the connected region of the starting cell's value |
| `room-add INPUT OUTPUT ID X Y W H [--name NAME] [--role ROLE] [--locked] [--force] [--json]` | Add a room, optionally locking position and size |
| `room-set INPUT OUTPUT ID X Y W H [--name NAME] [--role ROLE] [--force] [--json]` | Edit a room while retaining its ID and existing lock flags |
| `room-lock INPUT OUTPUT ID POSITION_0_OR_1 SIZE_0_OR_1 [--force] [--json]` | Set position/size locks separately |
| `room-remove INPUT OUTPUT ID [--force] [--json]` | Remove an unlocked room |
| `generate FILE [--json] [--seed UINT32] [--attempts N] [--work N] [--time-ms N] [--events 0..4096]` | Exact-count BSP room layout; abstract connections, no floor connectivity claim |
| `route FILE [same options as generate]` | Generate rooms, route full-width corridors, and verify connected floor/spawn capacities |
| `optimize FILE [same options as generate] [--budget N] [--detailed-trace]` | Generate, route, solve exact allocation, and place actors; nonnegative budget override, detailed traces only for small inputs |
| `run FILE [same options as optimize]` | Complete pipeline with one combined source/layout/geometry/allocation report |
| `export FILE OUTPUT [same options as run]` | Run the complete pipeline and atomically export the combined JSON report |

Input/output paths are positional before flags. Quote paths or labels containing
spaces. Windows uses wide command-line arguments and filesystem paths; UTF-8
labels and filenames are supported. Output text/JSON is UTF-8; terminal font
support still determines how labels appear on screen.

`--force` is accepted only for commands that write an output file. Destinations are not overwritten
without it, including a file created concurrently after the initial check.
Parent output directories must already exist. Source-edit/save commands can use
the same input/output path with `--force`. Derived-result exports always reject
the source path, including existing file aliases, even with `--force`.

Human success output goes to stdout; human failures go to stderr. In JSON mode,
operational outcomes go to stdout as a single object with `outcome` and
`diagnostics`, except successful `inspect --json`, which prints the source
document itself, and `mask-info --json`, which prints analysis data. Generation/
routing JSON includes outcome/diagnostics, stage, metrics, bounded events, and
a result only on success. These result documents are not source projects.
`mask-info`
returns 0 if analysis succeeds even when `generation_preflight.outcome` fails;
use `validate --for-generation` for a failing preflight exit code.
Syntax/usage errors (64) and catastrophic unexpected exceptions
may print text to stderr even if `--json` was requested. Never interpret a
nonzero exit status as a successful project or solver result.

| Exit code | Meaning |
| --- | --- |
| 0 | Success |
| 2 | Invalid input/document |
| 3 | Unsupported schema or size/workload |
| 4 | File access/create/replace failure |
| 5 | Resource failure |
| 6 | Generation, routing, allocation or publication cancelled |
| 7 | Bounded generation/routing search exhausted |
| 8 | Stale result (session API; future CLI jobs) |
| 9 | Unexpected internal failure |
| 64 | Invalid command syntax/options |

Each structured diagnostic has `code`, `path`, `message`, `affected_ids`,
`affected_tiles`, and `recovery`. Input paths use JSON Pointer notation; file
errors use the file path. Syntax/duplicate-key/nesting errors apply to the whole
document and use an empty path. Semantic validation retains up to 100 diagnostics.

Example output from the supplied teaching project:

```text
Phase 2 teaching project
Canvas: 12 x 10; allowed tiles: 116
Rooms: 4 requested; 2 source rooms
Room sizes: 2-4 wide, 2-4 high
Packs: 2 catalogue; 2 active (exact-solve cap 14)
Threat budget: 8; seed: 5489
Source document only; no generated dungeon or allocation.
```

Geometry validation checks fixed-room containment, separation, roles, and locks.
`--for-generation` adds mask/reservation/terminal preflight; it does not generate
rooms or prove corridor feasibility. `generate` performs BSP room placement;
`route` additionally carves corridors and validates actual floor connectivity.
`optimize` additionally solves exact encounter allocation. See [geometry contract](geometry.md),
[generation contract](generation.md), and [routing contract](routing.md).

For the new generator and router:

```powershell
$cli = '.\build\windows-debug\bin\dungeon_cli.exe'
& $cli generate datasets/generation/l-shape.json --seed 42
& $cli route datasets/routing/hole-detour-width2.json
& $cli route datasets/generation/standard-150.json --json --events 0

# Intentional failures: bounded room search, then insufficient corridor clearance.
& $cli generate datasets/generation/rectangle.json --attempts 1 --json
& $cli route datasets/routing/narrow-neck-width2.json --json
$LASTEXITCODE # 7; no partial output is published
```

Overrides affect this run only. `route` applies work/time limits separately to
room generation and routing; attempts apply only to BSP. A `route` failure in
room generation reports `stage: room_layout`; a later failure reports
`stage: walkable_geometry`. Ctrl+C requests cancellation. JSON `events` are
bounded debug history; use `--events 0` for compact result-only output. Output
may be redirected to an ignored file with PowerShell `Set-Content -Encoding utf8`.

## Try it in PowerShell or VS Code's terminal

```powershell
Set-Location 'E:\Uni\sem5\DAA\Dungeon Architect'
.\tools\build-native.ps1 -Configuration Debug
$cli = '.\build\windows-debug\bin\dungeon_cli.exe'

# Inspect a saved project and view locked rooms + their margins.
& $cli inspect datasets/teaching/phase02-project.json
& $cli validate datasets/teaching/phase02-project.json --for-generation --json
& $cli mask-info datasets/teaching/phase02-project.json

# Create an L-shaped mask and add a locked entrance.
& $cli new output/app/cli-demo.json --name 'CLI demo' --seed 42
& $cli mask output/app/cli-demo.json output/app/cli-demo.json l-shape 0 0 30 20 --force
& $cli room-add output/app/cli-demo.json output/app/cli-demo.json entrance 2 2 5 5 --role entrance --locked --force
& $cli mask-info output/app/cli-demo.json

# Deliberate failure: a locked room cannot be moved. The file stays unchanged.
& $cli room-set output/app/cli-demo.json output/app/cli-demo.json entrance 3 2 5 5 --force --json
$LASTEXITCODE # Expected: 2

# Unlock, move, and relock.
& $cli room-lock output/app/cli-demo.json output/app/cli-demo.json entrance 0 0 --force
& $cli room-set output/app/cli-demo.json output/app/cli-demo.json entrance 3 2 5 5 --force
& $cli room-lock output/app/cli-demo.json output/app/cli-demo.json entrance 1 1 --force

# Inspect detached regions and precise failures supplied as fixtures.
& $cli mask-info datasets/edge_cases/islands.json
& $cli validate datasets/edge_cases/fixed-overlap.json --for-generation --json
```

The initial `new` refuses to replace an existing `cli-demo.json`; use a fresh
filename or explicitly add `--force` to restart the example. Role values are
`normal`, `entrance`, `exit`, `boss`. Use `room-set` with unchanged bounds and
`--name` to rename even a locked room. Coordinates and sizes are integer tiles.
`mask-info` shows at most the top-left 80 × 40 cells in text; JSON contains the
entire grid. Other settings and pack inventory can currently be edited in the
saved JSON, followed by `validate`; a full editor is deferred to Flutter.

To rerun tests without rebuilding:

```powershell
& '.\.tools\cmake-3.31.10-windows-x86_64\bin\ctest.exe' --preset debug
```

## Exact allocation (Phase 06)

```powershell
$cli = '.\build\windows-debug\bin\dungeon_cli.exe'
& $cli optimize datasets/allocation/teaching.json
& $cli optimize datasets/allocation/teaching.json --budget 2 --json
& $cli optimize datasets/allocation/teaching.json --detailed-trace --json
& $cli optimize datasets/allocation/standard-14.json --json --events 0
```

The teaching case has score 14, threat 3 and three actors; budget 2 changes its
optimum to score 9. The standard 14-pack case has score 74, threat 24 and 20 actors.
Each command runs generation, routing and exact allocation in C++, preserving
the source file. Run overrides are transient. Each stage has its own work/time
budget; a stage failure stops the pipeline and reports that stage.

Allocation JSON contains canonical pack_bit_order, metrics, bounded events,
optimal, and allocation with assignments, actors, unused reasons and totals.
No failed allocation includes a partial result. Exit 3 covers the active-pack
or DP-table memory limit; exit 5 covers allocation work/deadline/memory failure;
exit 6 indicates cancellation. Detailed traces require at most six active packs
and eight eligible rooms. Use --events 0 to suppress stored traces. The complete
contract, C++ API and exactness proof are in [allocation.md](allocation.md).

## Complete pipeline and result export (Phase 07)

```powershell
Set-Location 'E:\Uni\sem5\DAA\Dungeon Architect'
$cli = '.\build\windows-debug\bin\dungeon_cli.exe'
& $cli run datasets/pipeline/teaching.json --metrics
& $cli run datasets/pipeline/irregular-fortress.json --preview 95 100 55 50 --metrics
& $cli export datasets/pipeline/irregular-fortress.json output/app/fortress-result.json --events 0 --no-map
# For a deliberate replacement of that export, repeat with --force.
& $cli run datasets/pipeline/teaching.json --json --events 0
```

`run` executes generation, routing and exact allocation once and reports the
complete result. `export INPUT OUTPUT` is the same workflow with an explicit
output path; `run INPUT --output OUTPUT` is equivalent. Stage commands also
accept `--output OUTPUT`. All exported files are full JSON, independent of text
preview settings. `--json` prints one JSON object to stdout; it never appends a
human save message. With --output and --json, stdout and file bytes are identical.
See [result format and replay](result_format.md).

Additional options shared by generate/route/optimize/run/export:

| Option | Behavior |
| --- | --- |
| `--output FILE` | Atomically write a successful result; use the positional path for export instead |
| `--force` | Explicitly replace an existing result; requires an output path |
| `--rooms N` | Positive room-count override, subsequently checked against domain rules/fixed rooms |
| `--corridor-width N` | Positive width override, subsequently checked against canvas/routing constraints |
| `--metrics` | Add operation counters to human output; JSON always includes counters |
| `--preview X Y W H` | One character per tile, cropped from an in-canvas nonnegative origin; W<=160, H<=80; clipped at canvas edges |
| `--no-map` | Suppress the human map; incompatible with --preview |
| `--cancel-file FILE` | Cooperatively cancel if this marker path exists, including when created during a run |

The default human preview is the top-left 80x40, clipped to the canvas. The
summary labels its origin and dimensions so the crop cannot be mistaken for a
smaller dungeon. `A` marks actors; `@` and `>` mark the entrance and exit. JSON
retains the entire allowed mask, partition data, floor, walls, doors, corridor
paths, movement reservations, spawn lists, assignments and actor positions.

All overrides are transient and are recorded in the embedded source document.
Duplicate or incomplete options return 64. Generation/routing/allocation each
have their own work/time allowance. Each stage retains at most --events events;
zero disables event storage without changing algorithms or operation counts.
Detailed DP traces remain limited to six active packs and eight eligible rooms.

Exports are created only after the requested workflow succeeds. They use a
same-directory exclusive temporary file, flush/close, and atomic replacement.
There is no truncate/delete-first fallback. Existing exports require --force;
create-only publication also rejects a destination created during the run.
The source project and cancellation marker must be separate from the output.
The exporter checks existing file identity as well as normalized paths to reject
source aliases. Parent directories must exist. The maximum serialized file is
128 MiB. Failed, cancelled, unsupported and search-exhausted runs retain any
previous export and leave source bytes unchanged.

Ctrl+C requests cancellation. For scripted/background use, supply an absent
`--cancel-file output/app/stop.request` and create that marker from a second
terminal to request cancellation:

```powershell
Set-Content -LiteralPath 'output/app/stop.request' -Value 'cancel'
# Before the next run, remove only the marker you created:
Remove-Item -LiteralPath 'output/app/stop.request'
```

The marker is never created or removed by the CLI. A pre-existing marker cancels
at the first checkpoint. Marker-access errors report exit 4. Cancellation is
cooperative during algorithms and checked again before output publication;
input/result validation, serialization and the final atomic write are bounded
synchronous operations, not a hard real-time cancellation guarantee. There is
no daemon or scheduler. A failed pipeline reports its failed stage and retains
only stage diagnostics/metrics/events, never a partial combined result.

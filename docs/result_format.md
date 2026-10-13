# CLI result format 1

The source-project format remains schema 1. A derived result is a separate JSON
document with `format_version: 1` and `engine_version`. Source-project commands
reject it as an input project. It is intended for inspection, analysis and future
frontend integration, not as a replacement for the editable project.

## Combined result

`run INPUT --json` and `export INPUT OUTPUT --json` return the same JSON bytes
for identical effective source, engine version and trace options. Destinations,
wall-clock durations and machine-specific paths are not included. `--output`
does not change stdout JSON. File exports always contain JSON, even in text mode.

| Field | Meaning |
| --- | --- |
| `outcome`, `diagnostics` | Stable outcome and structured errors, as in source validation |
| `stage` | `pipeline` after generation has started; earlier input/path failures use `input` or `export` |
| `failed_stage` | `room_layout`, `walkable_geometry`, or `allocation`; null on success |
| `seed` | Effective unsigned 32-bit seed |
| `optimal` | True only when the complete exact pipeline succeeds |
| `stages` | Attempted `generation`, `routing`, `allocation` reports with outcome, metrics and bounded events; unattempted stages absent |
| `result` | Complete result object on success; null on failure or cancellation |

The success `result` object contains:

- `source_project`: a canonical schema-1 document including all effective run
  overrides. Its settings, allowed-mask rows, source rooms and pack inventory
  give the full replay context.
- `layout`: every accepted room and its metadata, partition records, abstract
  connection requirements, entrance/exit IDs and complete occupancy/reservation
  row strings. Its abstract connectivity flag remains false because this stage
  does not establish physical connectivity.
- `geometry`: floor, walls, occupancy, reservations and movement-reserved layers;
  every room's bounds, hub, capacity and complete valid spawn list; all doors,
  door cells, corridors and full footprint-anchor paths; entrance/exit markers;
  and `connected_floor_verified: true`.
- `allocation`: selected pack-to-room assignments, all actor spawn references and
  coordinates, unused active packs with reasons, and total slots/threat/score.

Each layer is an array of strings: outer index y, character index x, values 0/1.
Dimensions come from `result.source_project.source.settings`. Coordinates are
integer tiles; rectangles are half-open. Corridor path points are the top-left
anchors of full corridor-width squares, not a thin centerline.

Dependency links are explicit: `geometry.room_layout_id == layout.id` and
`allocation.geometry_id == geometry.id`. Revisions are included; detached CLI
calls use revision zero. IDs are deterministic within a run and its replay,
not globally unique content hashes. Keep the embedded source with the results.
Canonical pack-bit order is in `stages.allocation.pack_bit_order`.

On a later-stage failure, earlier stages may retain metrics/events, but `result`
remains null. Nothing is exported to a requested output file. A serialization,
path, cancellation-before-publication or atomic-write error returns a compact
`stage: export` report with null result and `optimal: false`. Always inspect
exit code and outcome before reading payload fields.

## Existing stage commands

`generate`, `route` and `optimize` retain their stage-specific payloads (`layout`,
`geometry`, `allocation`) and formats. Successful stage reports additionally
include top-level `source_project` for replay, and snapshots include revisions.
All three now accept `--output FILE [--force]`. These commands and `run` share
the same serializers, C++ algorithms and atomic writer.

## Replay

In PowerShell, extract the embedded source and run it as a normal project:

```powershell
$report = Get-Content 'output/app/fortress-result.json' -Raw | ConvertFrom-Json
$report.result.source_project | ConvertTo-Json -Depth 100 |
    Set-Content 'output/app/fortress-replay.json' -Encoding utf8
.\build\windows-debug\bin\dungeon_cli.exe run output/app/fortress-replay.json --json --events 0
```

Use matching trace options when comparing complete reports; changing trace
capacity changes events/dropped-event counts but not geometry or assignments.
Use a JSON reader that preserves 64-bit integers when processing large totals.
Failed deadline-limited runs are machine-dependent and are not replay guarantees.

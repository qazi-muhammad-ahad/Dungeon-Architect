# Project file format and C++ API - phase 02

The C++ engine owns domain types, validation, revision tracking, and future
algorithms. The CLI exercises that API directly. `dungeon_project_io` is a
separate C++ adapter for JSON and disk access. Flutter is unchanged in this phase.
The exported C DLL still has its phase-01 bootstrap probes; full C ABI ownership,
jobs, and frontend bindings remain Phase 08. Do not confuse a public C++ API
with a finished cross-language ABI.

## Schema 1

See [machine-readable schema](schema/project-v1.schema.json) and the complete
[teaching project](../datasets/teaching/phase02-project.json).

The top-level object requires exactly `schema_version`, `engine_version`, and
`source`. Version must equal integer `1`. `engine_version` records the writer;
the current writer emits `0.7.0`, while other writer versions are accepted when
the schema version matches. Saving updates writer metadata. No migration is
attempted for other schema versions. Unknown fields, duplicate object keys,
missing fields, comments, trailing garbage, and floating-point numeric tokens
are rejected. Future derived-result payloads cannot be silently imported.

Source fields:

| Field | Meaning |
| --- | --- |
| `name` | Nonempty UTF-8 project label |
| `settings` | Canvas, requested room count, room size ranges, margin, corridor width, seed, work/time limits, threat budget |
| `allowed_mask` | One `0`/`1` string per row; each string has exactly `columns` bytes |
| `rooms` | Explicit source room records, including geometry, roles, tags, independent position/size locks, optional capacity override |
| `packs` | Catalogue inventory copies, each with a distinct ID and active flag |

`1` in the mask means allowed **building area**, not carved floor. Coordinates
are integer tiles, origin top left, increasing right/down. Rectangle bounds are
half-open `[x, x + width) × [y, y + height)`. Width/height must be positive;
addition is widened before checking so large values cannot overflow.

Roles are `normal`, `entrance`, `exit`, and `boss`. An entrance's explicit
capacity override must be zero. `null` capacity means derive it later from valid
spawn positions. Position and size locks are stored independently; either true
makes the whole current footprint mandatory for generation. Phase 03 implements
mask containment, overlap, separation, lock consistency, and terminal geometry
checks. Validation does not prove that a layout can be generated. See
[geometry rules](geometry.md) for margins, lock editing, and preflight semantics.

Each pack's positive `slots` is its integer spawn demand. `threat` and `score`
are nonnegative. `allowed_roles: []` means any eligible non-entrance role;
`required_tags: []` adds no tag restriction, otherwise all listed tags must be
present. Room dimension requirements are inclusive minima. Identical catalogue
copies may share a name and attributes, but must have different IDs. No implicit
mandatory boss pack or requirement to fill rooms is added.

IDs and tags are case-sensitive ASCII identifiers: 1-64 bytes using letters,
digits, `_`, `-`, `.`, or `:`. Room and pack IDs have separate namespaces; each
collection is unique. Renaming or reordering a record does not change its ID.
Names are UTF-8, nonempty, at most 256 bytes, without ASCII control characters.

## Limits and numeric precision

- Canvas storage: 1-512 per axis, at most 262,144 cells. Values below 150 support
  small teaching fixtures. Default remains 150 × 150. This is a storage bound,
  **not a measured claim about generation or rendering at 512 × 512**.
- Requested rooms: 2 through the canvas's tile count; geometric feasibility is
  checked later. Source room and catalogue collections: at most 4,096 each.
- Tags: at most 64 unique entries per record. Allowed roles are unique.
- Project input/output: at most 16 MiB; JSON nesting at most 32 levels.
- Coordinates/settings use signed 32-bit integers; seed uses unsigned 32-bit.
- Slots, threat, score, budget, and work/time limits use signed 64-bit integers.
  Work limits are positive; budget, threat, and score may be zero.
- Active-pack slot/threat/score totals must fit signed 64-bit storage. Addition
  is checked before execution. Inactive catalogue values are validated, but are
  not summed into the active inventory totals.
- A project with over 14 active packs can be edited, saved, and reopened.
  `validate_allocation_workload` (CLI `validate --for-allocation`) returns
  `unsupported_size`. No packs are dropped or heuristic solver substituted.

An all-zero mask is valid unfinished editor data; generation will reject an
empty building area. A pack larger than the current rooms is valid input, to be
reported as infeasible by later allocation checks.

JSON integer values are preserved exactly by the C++ adapter, including values
above JavaScript's safe integer range. The future browser adapter must preserve
that precision (e.g. pass raw JSON through C++, or use an explicit lossless
transport); it must not round-trip these fields through JS `Number` silently.
The JSON Schema helps editors, while C++ is authoritative for integer token
types, UTF-8 byte limits, duplicate keys/IDs, sums, and cross-field constraints.

## Canonical serialization and source/result separation

Serialization validates first, sorts object keys lexically, orders rooms/packs
by ID, sorts tag sets lexically, and orders role sets by enum rank
`normal, entrance, exit, boss`. Mask order stays row-major. Output is UTF-8 with
two-space indentation, LF newlines, and a final newline; no timestamps/random
IDs are injected. Equal source data produces identical output independent of
record/set input ordering. Formatting and array presentation order are not
preserved; source meaning is preserved.

Geometry, occupancy, reservations, floor, walls, spawn positions, actors,
allocation results, play state, and runtime revision counters are separate
types and are not saved in a schema-1 source document. Readers reject attempts
to add these as unknown fields. Later phases can add a separately validated
result export instead of treating imported output as authoritative.

## Transactional session updates

`ProjectSession` exposes a const source project, a revision stamp, and shared
immutable result snapshots. `update(candidate)` validates and canonicalizes a
copy, then commits with a nonthrowing swap. Invalid candidates leave source,
revision counters, and retained snapshots unchanged. Failed loads also leave
the live session unchanged. Normal C++ memory allocation can throw before a
commit; the old session remains intact. Adapters translate expected parse/file
failures to structured results, and the CLI handles unexpected exceptions.

Session-scoped unsigned 64-bit revision counters start at 1. They are not
persisted or used as global IDs. Reordering alone is a no-op. Accepted changes:

| Change | Revisions incremented / outputs made stale |
| --- | --- |
| Name/label or inactive catalogue detail | Source only |
| Budget, active inventory data, room tags/capacity | Source, allocation, play |
| Mask, canvas, generation settings, seed, room IDs/bounds/roles/locks | Source, geometry, allocation, play |
| Successful document load, even identical data | All revisions |

Old result pointers remain available, with `*_current()` reporting staleness.
New result publication checks both captured source revision and dependencies.
Publishing geometry invalidates allocation/play even when the source is
unchanged; publishing allocation invalidates play. Counter overflow is rejected
before mutation. Later algorithms must validate result contents before using
the publication hooks: those hooks currently enforce revision rules only.

## Atomic disk saves

`save_atomic` validates/serializes before touching output. It reserves an
exclusive temporary file beside the destination, writes and flushes it, closes
it, then performs a same-directory replacement. Windows uses `CreateFileW`,
`FlushFileBuffers`, and `MoveFileExW`; no delete-and-retry fallback exists.
`SaveMode::create_only` prevents overwriting even if another process creates the
destination between CLI preflight and rename. Temporary files are cleaned on
failure. Missing parents are reported rather than created implicitly.

This protects against partial writes and ordinary replacement failures. It is
not a general power-loss/filesystem durability guarantee. Windows failure paths,
including a target opened without delete sharing, are tested. A POSIX fallback
exists but is not verified in this Windows environment.

## C++ use

```cpp
#include "dungeon_architect/project_io.h"
namespace da = dungeon_architect;
da::ProjectSession session;
auto status = da::project_io::load_into(session, "project.json");
if (status.ok()) {
    auto candidate = session.project();
    candidate.settings.threat_budget = 50;
    status = session.update(std::move(candidate));
    if (status.ok()) {
        status = da::project_io::save_atomic(session.project(), "project.json");
    }
}
```

Link `dungeon_core` for domain/session validation alone, or `dungeon_project_io`
for JSON and disk operations. No Flutter, JSON, Windows, or file-format headers
enter the core's public API. Shared session mutation is single-threaded; later
worker/job adapters must serialize edits/publications and pass immutable copies.

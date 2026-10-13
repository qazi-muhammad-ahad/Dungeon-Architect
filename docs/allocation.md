# Exact encounter allocation (Phase 06)

The C++ solver maximizes additive score for one accepted dungeon, not across all
possible dungeon layouts. No heuristic fallback or partial result is labelled
optimal. Active copies have distinct IDs; at most 14 active packs are supported.

## Algorithm contract and pseudocode

Before allocating DP tables, validate inputs and estimate memory and worst-case
work. Sort active packs and eligible rooms by ID. Entrance, unreachable and
zero-capacity rooms are ineligible. Compatibility requires role, all required
tags and minimum dimensions; slot demand must fit actual capacity.

```
total[0] = (slots=0, threat=0, score=0)
for each nonempty mask M:
    total[M] = checked_add(total[M without its lowest bit], that pack)
for each room r and mask M:
    fits[r,M] = all packs compatible and total[M].slots <= capacity[r]
F[0,0] = true; all other states false
for rooms r in canonical order:
    for masks M in ascending numeric order:
        try S=0 first, then all nonempty submasks of M in ascending order
        if fits[r,S] and F[r-1,M xor S]:
            F[r,M] = true; predecessor[r,M] = S; stop this state
choose a feasible final M within threat budget by:
    highest score, lowest threat, lowest slots, lexical selected-pack-ID list
walk predecessors backwards to reconstruct each room's assigned subset
visit rooms and packs in ID order; consume spawn cells in (y,x,ID) order
independently validate complete assignments, actors, totals and unused reasons
publish only if source revision and geometry snapshot still match
```

Empty subsets make skipping any room legal. Only F(0,empty) is initially true.
Induction: removing the last room's subset yields an exact feasible predecessor;
conversely a feasible predecessor plus a disjoint fitting subset yields a valid
assignment. Every assignment is represented. The final scan enforces the global
budget and chooses the exact optimum. Placement ties follow the explicit DP
traversal above, favoring already assigned earlier rooms when possible.

Worst-case DP time is O(R * 3^N), storage O(R * 2^N), with N <= 14. Threat is
a subset total, not a table dimension. Resource estimates include subset totals,
per-room feasibility, predecessor tables and two reachability rows. Tables are
capped at 64 MiB. A conservative work estimate exceeding the configured work
budget is rejected before allocation, even if early exits might make a run cheap.
Cooperative work/time checks and cancellation return no allocation on interruption.
Validation and input copying are bounded synchronous operations, as in routing.

The work estimate is `(R+3)*2^N + R*3^N + R*N + N + 1 + sum(capacity)`.
Counters count subset-total computations, pack/room compatibility tests,
room/subset feasibility entries, predecessor attempts, final subset scans and
placed actors. They are operation units, not CPU instructions. Input/result
validation, input copying, sorting and event storage are outside these counters.
The memory estimate covers table payloads and reconstruction masks, not total
process RAM. Bounded inputs, events and result storage add memory beyond it.
Actual allocation failure returns `resource_failure`.

## C++ use and snapshot lifecycle

Include `dungeon_architect/allocation.h` and link `dungeon_core`:

```cpp
ProjectSession session;
session.update(project); // Check each Status/Result in application code.
generate_rooms(session);
route_corridors(session);
auto result = allocate_encounters(session);
if (result.ok()) {
    auto immutable = session.allocation();
    // immutable->assignments, actors, unused, total_score/threat/slots
}
```

The session overload copies source inputs, retains immutable layout/geometry,
solves, and publishes only if source, geometry ID and allocation revision still
match. Failed, cancelled, unsupported and stale jobs expose no allocation and
retain the last accepted snapshot. Publication independently checks feasibility;
it does not rerun DP or prove an arbitrary caller-provided snapshot optimal.
The CLI's `optimal: true` comes only from a completed exact solver run.

`prepare_allocation(source, layout, geometry)` validates the actual routed floor,
doors, spawn cells and movement exclusions. It refreshes capacity overrides and
tags from current source metadata in a validation copy. The original geometry
is unchanged. Overrides above available cells are rejected. Automatic entrance/
exit selections become effective compatibility roles; the entrance stays safe.
Budget, score, threat, tag and capacity edits require a full allocation rerun
but do not require BSP or corridor regeneration.

`allocate_encounters(source, layout, geometry, options)` returns a detached result.
`allocate_encounters(AllocationInput, options)` supports isolated solver fixtures
and future reachability scenarios. That low-level input supplies resolved room
roles/capacities and legal spawn lists; its validator checks bounds, uniqueness
and spacing, but it contains no floor mask and cannot certify floor legality.
Use the dungeon adapter for real dungeons. Const-reference inputs must remain
unchanged for the entire call. Session access is serialized by its owner; only
an atomic cancellation flag should be written from another thread. The optional
callback runs on the solving thread and should return promptly without throwing.

Actors use canonical room then pack order and each room's spawn order `(y,x,ID)`.
One actor consumes one slot. Each pack stays wholly in one room. Inactive packs
appear in neither selected nor unused output. Unused active packs have one reason:

| Reason | Meaning |
| --- | --- |
| `no_compatible_eligible_room` | No reachable positive-capacity non-entrance room satisfies roles, dimensions and all tags |
| `oversized` | Some eligible rooms match compatibility, but none can hold this pack alone |
| `unselected_by_optimum` | It fits somewhere individually but is absent from the chosen optimum, including budget, competition and ties; no unique cause is claimed |

All totals use checked signed 64-bit arithmetic. `AllocationSnapshot` includes
explicit pack-to-room assignments plus actor records and full active-inventory
accounting. The independent validator reconstructs totals and per-room demand
from assignments and checks each actor against the legal input spawn catalogue.
It shares input validation but does not use the DP tables or feasibility masks.

## CLI and traces

```powershell
.\build\windows-debug\bin\dungeon_cli.exe optimize datasets/allocation/teaching.json
.\build\windows-debug\bin\dungeon_cli.exe optimize datasets/allocation/teaching.json --budget 2 --json
.\build\windows-debug\bin\dungeon_cli.exe optimize datasets/allocation/teaching.json --detailed-trace --json
.\build\windows-debug\bin\dungeon_cli.exe optimize datasets/allocation/standard-14.json --json --events 0
```

`optimize` runs BSP, routing, then allocation without modifying the source file.
It accepts the existing generation options plus nonnegative `--budget N` and
`--detailed-trace`. Each stage gets its own configured work/time budget. Ctrl+C
uses cooperative cancellation. Earlier-stage failures retain their stage label.
Allocation-stage JSON has `stage: allocation`, metrics, canonical `pack_bit_order`,
bounded events, `optimal`, and `allocation` (null on failure). This is derived
output, not an importable source project. Phase 07 now provides combined geometry+allocation export
through run/export; `route --json` already
exports geometry separately with reproducible IDs.

Default traces record preflight, room-level feasible-state counts, reconstruction
subsets and the final optimum. Detailed state traces require N <= 6 and R <= 8.
All traces are capped at 4096 events (default 256, zero disables storage).
Mask bits use the active pack list sorted by ID. Summaries/truncation do not change
the DP traversal or counters. Interrupted solver runs do not emit `optimal`;
a session run that becomes stale at publication can retain completion events
but has `stale_result` status and no allocation. Always check the final status.
Independent final validation and session publication are bounded synchronous
steps rather than a hard real-time deadline guarantee.

## Verification

`core.allocation` compares 400 seeded small randomized cases with an exhaustive
per-pack room/unselected assignment oracle, including the full score/threat/slot/
selected-ID tie order. It verifies deterministic assignments and spawn cells after
input reordering, golden predecessor traversal, corruption rejection, checked
overflow, zero budget/threat/score, no eligible rooms, over-demand, compatibility,
14/15-pack boundaries, table/work guards, cancellation and deadlines. Session
tests cover metadata edits, geometry reuse, stale jobs and retained old results.
`cli.allocation` checks known optima, actual CLI overrides, full actor records,
failure exit codes, no partial results, repeatable JSON and unchanged input hashes.

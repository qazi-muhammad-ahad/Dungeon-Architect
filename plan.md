# Dungeon Architect - Project Plan

Status: Planning complete; implementation not started.
Date: 2026-10-10 (Asia/Karachi)
Owner: The user. Discuss consequential algorithm or scope changes before implementation.

## 1. Confirmed decisions

- Game-related CEP: procedural dungeon construction and exact encounter allocation.
- Two primary paradigms: divide-and-conquer and dynamic programming.
- C++ core and reusable native API; CLI validation first, Flutter/Dart desktop UI afterward.
- Canvas at least 150 x 150 tiles; one tile is the smallest editing unit.
- Premade shapes and freehand tile painting. Painted tiles define the allowed BUILDING AREA, not final walkable floor.
- Runtime room-count input after drawing; editable room settings.
- Editable rooms and fixed-position rooms placed before generation, such as a boss room.
- Assessed workload: 10-20 total rooms and 12-14 encounter packs. These are target workloads pending measurement.
- Editable threat costs, global threat budget, and designer scores.
- Design, Analyze, and Play views.
- Exploration-only playable demonstration; no combat required initially.
- Pixel-art fantasy dungeon with a clean modern editor UI.
- Feature priority: editable dataset, algorithm/assignment visualization, benchmarks, failure simulation, detailed step explanations.
- Full editable DOCX report, runnable application, tests/datasets, and viva preparation.
- Four placeholder group-member records; the user is currently working alone.
- STL allowed. Implement and explain the assessed algorithms ourselves.
- Initial allocation is exact; no silent heuristic fallback.
- Organize the project professionally in the directory containing this plan.

Routine implementation defaults below are recommendations within this agreed scope. Changing the mathematical problem, primary algorithms, workload strategy, platform architecture, or gameplay scope requires discussion.

## 2. Sources and assignment interpretation

Provided PDFs, currently in the project root:
- CCP Fall 26.pdf: authoritative assignment/rubric.
- D&AA Chapter 01.pdf: formulation, correctness, data structures, graphs.
- D&AA Chapter 02.pdf: invariants, complexity, recurrences, empirical analysis.
- D&AA Chapter 03.pdf: exhaustive search, knapsack, graph traversal.
- D&AA Chapter 04.pdf: decrease-and-conquer, which is distinct from divide-and-conquer.
- D&AA Chapter 05.pdf: divide-and-conquer methods.

The instructor allows any two paradigms genuinely working together. The sample's MST, villages, twenty roads, and incremental MST repair are scenario-specific. Our alternative must preserve comparable engineering depth through formal models, conflicting constraints, correctness arguments, complexity derivations, reconstruction, tests, and integrated experiments.

The three-page brief references a missing Part D and sample dataset. Do not invent bonus requirements. The rubric mentions time decay while the sample allocation requires fixed values; our threat and score are fixed input constants during each run.

Rubric emphasis: problem understanding 10%, conflicting requirements 20%, analysis 30%, implementation 40%. UI polish supports those requirements; it does not substitute for them.

## 3. Original case-study formulation

A roguelite designer must construct a connected dungeon inside a hand-drawn allowed region, preserve specified fixed rooms, and distribute a limited inventory of encounter packs across reachable rooms. Rooms have different spawn capacities and compatibility restrictions. A global threat budget limits the complete dungeon. The system maximizes an explicit additive designer score.

Pipeline:
1. Validate mask, dimensions, fixed rooms, and requested room count.
2. Generate remaining rooms using constrained, mask-aware BSP.
3. Carve corridors and verify actual tile connectivity.
4. Derive reachable rooms, valid spawn positions, and encounter eligibility.
5. Solve exact shared-inventory allocation with subset DP.
6. Reconstruct pack-to-room assignments and place actors.
7. Display the same authoritative result through CLI, Analyze, and Play.

Geometry changes affect allocation feasibility, so the two algorithms have a real dependency.

Scope of optimality: DP is optimal for the generated layout and declared allocation constraints. BSP is a constructive generator, not a globally optimal dungeon-layout solver. We do not claim the pipeline finds the best layout among all possible maps, guarantees enjoyment, or guarantees winnable combat.

## 4. Map drawing, rooms, and editing

### 4.1 Canvas model
- Default 150 columns x 150 rows.
- Integer tile coordinates, origin top left; x increases right, y increases downward.
- Half-open rectangle bounds internally: [x,x+w) x [y,y+h).
- Keep canvas, allowed mask, carved floor, walls, room footprints, and actor positions distinct.
- Canvas tiles are independent of display pixels. Provide pan, zoom, fit-to-view, and tile coordinates.
- Proposed initial configurable canvas range: 150-512 per axis, subject to measured memory/rendering limits.
- Brush supports one-tile precision and larger sizes; a drag is one undoable edit.
- Initial presets: rectangle, ellipse, and L-shape. Include paint, erase, and fill tools.
- Closed-polygon fill is optional if it does not delay required functionality.
- Presets and freehand editing modify the same mask.
- Clearly distinguish painted allowed area from generated walkable floors.

### 4.2 Room parameters
- Runtime room count is an exact target and includes fixed, entrance, and exit rooms.
- Main demonstration uses 10-20 rooms; tiny teaching/tests may use fewer.
- Proposed initial interior width range: 8-22 tiles; height: 8-18 tiles. Both editable.
- Default separation/wall margin: one tile. Default corridor width: two tiles.
- Room size ranges are independent of canvas size.
- Never silently reduce the requested room count.
- Use explicit distinct entrance and exit roles; entrance has zero encounter capacity.
- A boss-room role/geometry lock does not automatically require a specific boss pack.

### 4.3 Fixed and editable rooms
- User draws a rectangular room, names/tags it, and locks position and dimensions.
- Fixed rooms must lie entirely inside the allowed region, preserve margins, and not overlap.
- Stable room IDs survive display reordering.
- Reserve fixed footprints and margins before generating remaining rooms.
- Never move, resize, or remove a locked room to make generation succeed.
- Validate edits transactionally; keep the previous valid dungeon on failure.
- Geometry edits invalidate affected corridors, allocation, and play snapshots.
- Threat/score edits invalidate allocation but reuse valid geometry.
- Explicit Generate/Optimize buttons avoid launching jobs on every brush movement.
- Record input revisions; discard stale results from asynchronous jobs.

## 5. Paradigm A: mask-aware divide-and-conquer generation

### 5.1 Model
BSP recursively divides bounding rectangles, but an occupancy mask records disallowed cells, holes, and reserved fixed-room cells. A leaf bounding rectangle is not necessarily an empty rectangular room.

Treat fixed rooms as reserved features rather than requiring every fixed footprint to be isolated by one clean BSP split. Abstract subdivision may cross reserved space; room extraction must never modify the reserved geometry. Draw diagnostic partition lines accordingly.

### 5.2 Algorithm
1. Validate allowed/free occupancy and fixed geometry.
2. Recursively split bounding regions using explicit minimum dimensions, room-count targets, and seeded choices.
3. Solve child regions for allocated room counts.
4. At leaves, find valid all-allowed rectangular room candidates that avoid reservations.
5. Combine child room collections and record connection requirements.
6. Attach fixed rooms as additional connection terminals and route corridors.
7. Verify connectivity on actual carved floor from the entrance.

Before coding, specify child room-count allocation, candidate search, bounded backtracking/retries, and fixed-room attachment in pseudocode.

A histogram-based all-valid-rectangle helper may be used for candidate discovery, with dimension/range checks. Explain and analyze any material helper. Bounding-box area alone never proves that the requested rooms fit.

### 5.3 Corridor construction
- BFS on a uniform tile grid is an auxiliary routing/connectivity method, not the second claimed paradigm.
- Route entirely inside the allowed mask and enforce corridor width and clearance.
- For widths above one tile, validate full corridor footprints, not only centerlines.
- Preserve fixed-room interiors and connect through explicit door positions.
- Traversing an existing room requires documented doorway rules.
- An irregular mask may require a corridor to leave its BSP child rectangle; permit this within the full allowed mask.
- Validate actual walkability. Abstract room edges alone do not establish connected floor.
- If not user-fixed, choose entrance/exit deterministically and place markers on valid reachable floor.

### 5.4 Failure semantics
- Reject provably invalid input: empty mask, overlap, out-of-bounds rooms, invalid ranges.
- Highlight detached mask components, narrow passages, and inaccessible doors.
- Do not silently remove islands, fill holes, or narrow corridors.
- Use bounded retries/backtracking, cancellation, and work/time limits.
- Search exhaustion is not proof of geometric impossibility. Report: "No valid layout found within the search limit" with actionable adjustments.
- Never fabricate connectivity or overwrite the previous valid snapshot with a partial failure.
- Impossible exact counts and search-limited outcomes have distinct statuses where provable.

### 5.5 Proof and analysis
Establish termination under explicit limits, room containment, non-overlap, lock preservation, corridor containment/clearance, and connectivity on success. Identify divide, recursive solve, and combine stages.

Use A = tile count, R = rooms, D = partition depth, L = routed links, H = bounded attempts. Derive costs from the final implementation, including mask scans, rectangle search, rasterization, retries, and routing. A grid BFS is O(A) time/space per route in the worst case. Do not call the entire generator O(R log R) while ignoring tile work.

## 6. Paradigm B: exact shared-inventory encounter allocation

### 6.1 Inputs and semantics
Each pack contains:
- Unique ID/name; repeated inventory copies use separate IDs.
- Positive integer spawn-position demand.
- Nonnegative integer threat cost and designer score.
- Room-type and minimum-dimension compatibility.
- Static actor definitions occupying its spawn positions.

Each room contains dimensions, role/tags, reachability, valid spawn positions, and editable capacity no greater than the valid-position count.

Spawn positions are actual valid floor cells with defined spacing. Exclude doors, entrance/exit markers, and reserved movement zones. Initial exploration actors do not block essential passage. This is discrete allocation, not geometric packing of arbitrary enemy shapes.

Threat and score are constant for a run. Scores encode designer preferences, not an objective measurement of fun.

### 6.2 Mathematical model
Binary x[i,r] assigns pack i to room r.

Maximize sum(score[i] * x[i,r]) subject to:
- Each pack used at most once: sum_r x[i,r] <= 1.
- Each room capacity: sum_i slots[i] * x[i,r] <= capacity[r].
- Global sum_i,r threat[i] * x[i,r] <= threat_budget.
- No assignment to unreachable/incompatible rooms.
- Entrance capacity is zero.

Unused packs and empty rooms are valid. No hidden requirement fills every room. Mandatory pack placement would be an additional constraint requiring explicit design discussion.

### 6.3 Selected DP formulation
Choose room-by-subset (bitmask) DP. It fits 10-20 rooms and only 12-14 packs better than adding a capacity dimension per room.

Let N = pack count and R = eligible rooms. Canonical pack ordering assigns bits to IDs. Precompute subset slots, threat, score, and per-room compatibility/capacity feasibility.

State F(r,M): whether EXACTLY subset M can be assigned across the first r rooms.
Base: F(0,empty)=true; all other F(0,M)=false.
Transition: F(r,M) is true if a subset S of M fits room r and F(r-1,M minus S) is true. Empty S is allowed.
Answer: choose a feasible F(R,M) with threat(M) <= budget maximizing score(M).
Store predecessor subsets to reconstruct all room assignments.

A feasibility table plus final maximization is sufficient because every placement of the same pack subset has the same fixed score.

Tie order: higher score, lower threat, lower total slots, then canonical pack/room order. Document traversal rules so assignments are reproducible.

Worst-case time O(R * 3^N); reconstruction storage O(R * 2^N), plus preprocessing. Global threat uses subset totals, not another numeric DP dimension.

### 6.4 Exactness and supported size
- Initial optimization cap: 14 active packs, pending benchmarks.
- Larger catalogues can be saved/edited, but exceeding the active exact-solve limit gives a clear unsupported-size message.
- Canvas, room-count, and pack-count limits are separate.
- Estimate state memory/work before allocation; check arithmetic overflow.
- Run off the UI thread with cancellation and previous-result preservation.
- Cancelled, timed-out, or resource-limited runs must not claim optimality.
- Never silently truncate inventory, alter the budget, or substitute a heuristic.

### 6.5 Proof and verification
Prove the DP invariant by induction. Every feasible assignment has a last-room subset S; removing it yields a predecessor. Conversely, combining a predecessor with a disjoint compatible S preserves all per-room and uniqueness constraints. Final selection enforces global threat and maximizes score.

Validate the reconstructed result independently. Compare against exhaustive assignment enumeration on tiny cases. There are (R+1)^N potential choices when each pack is unused or assigned to one of R rooms.

## 7. Native engine and application architecture

### 7.1 Layers
- Domain: tiles, masks, rooms, packs, settings, immutable snapshots.
- Validation: authoritative in C++, shared by CLI/API.
- Generation: masked BSP, reservations, rectangle candidates, routing, connectivity.
- Allocation: subset preprocessing, DP, reconstruction, independent result checks.
- Simulation: exploration movement/collision.
- Trace/metrics: actual algorithm events and operation counters.
- Adapters: CLI, native ABI, local JSON import/export.
- Flutter: canvas renderer, controls, charts, trace playback, input handling.

No Flutter dependencies in the core and no duplicate algorithm implementation in Dart.

### 7.2 ABI
- Initial language target C++17, subject to toolchain verification.
- C-compatible exported interface, opaque handles, fixed-width fields, versioned schemas.
- Do not expose STL containers, C++ class layout, exceptions, or compiler-specific types.
- UTF-8 JSON for project/request/result data; bounded batched or packed events for large traces if measurements justify them.
- Native-owned buffers have matching native release functions.
- Catch exceptions at public boundaries and return structured errors.
- Document ownership, lengths, integer ranges, handle lifetime, thread safety, cancellation, and API version compatibility.
- Use a Flutter worker isolate for expensive FFI calls and a thread-safe cancellation/job contract.
- Windows DLL first; other platforms need separate builds. Browsers need a bridge or WebAssembly adaptation.

### 7.3 State, persistence, determinism
- Versioned local JSON files; no server, account, or database.
- Save mask, fixed rooms, settings, active inventory, seed, and schema/engine version.
- Validate imported data and imported results.
- Commit successful changes atomically; failed import/solve leaves current project intact.
- Match result revision to input revision before applying.
- Specify PRNG mapping and canonical traversal/tie ordering; standard-library distributions are not automatically reproducible across toolchains.

## 8. UI and exploration experience

### Design
Paintable canvas, presets, undo/redo, room count/size controls, fixed-room tools, editable catalogue, threat budget, seed, error panel, Generate and Optimize buttons. Show units/ranges, stale-result state, and safe recovery from invalid edits.

### Analyze
Optional mask, BSP partition/tree, room ID, capacity, connectivity, and assignment overlays. Trace genuine C++ events. Show selected DP decisions and reconstruction; full tables only on tiny teaching cases. Do not animate millions of transitions by default.

Bound trace memory and use sampling/summary modes with clear labels. Sampling affects visualization only. Benchmark timings exclude UI/animation; distinguish traced and untraced runs. Charts show real operation counts, state memory, and measured timing.

### Play
Explore the exact same generated snapshot with WASD/arrows, wall collision, camera follow, entrance/exit markers, and optional key pickup. Static encounter markers expose assigned pack, threat, score, and room. No combat, enemy AI, physics engine, online play, or game economy initially.

Reset/invalidate play state on relevant edits. Use authoritative walkability and frame-rate-independent movement.

### Art direction
Pixel-art fantasy tiles/sprites, nearest-neighbor world rendering where appropriate, restrained highlights, readable typography, and clean editor panels. Diagnostic overlays are optional. Track all asset provenance/licenses.

## 9. Validation and testing matrix

| Area | Cases | Expected behavior |
| --- | --- | --- |
| Numbers | Missing, nonnumeric, negative, overflow, reversed ranges | Specific errors; no overflow/crash |
| Mask | Empty, one tile, holes, islands, thin necks | Highlight defects; classify invalid versus search-limited |
| Rooms | Count below fixed count, excessive count, oversized rooms | Reject provable errors; bounded search otherwise |
| Locks | Outside mask, overlap, margin conflict, duplicate IDs/roles | Reject edit; preserve fixed geometry |
| Corridors | Width mismatch, blocked doors, sealed exit | Enforce footprint clearance; show disconnection |
| DP | No rooms/items, zero budget, zero-threat packs, zero scores | Correct optimum without duplication |
| Capacity | Over-demand, incompatible/oversized pack | Optimal partial allocation and exclusion reasons |
| Inventory | Duplicate IDs, unsupported active count, huge values | Validate and check arithmetic |
| Ties | Equal values and reordered inputs | Stable canonical result |
| Async | Edit/undo/load while job runs | Cancel/discard stale result |
| ABI | Null handles, malformed data, bad lengths/lifecycle use | Defined safe error behavior |
| Files | Corruption, wrong schema, invalid mask length | Atomic rejection |
| Resources | Cancellation, timeout, allocation failure | Non-optimal status; previous result retained |

Use meaningful invariants and independent oracles. Avoid tests that merely duplicate the implementation.

## 10. Datasets and experimental evaluation

Version all fixtures with seeds and expected properties/results:
1. Tiny teaching case with 4-6 packs and full manual/visual trace.
2. Main nonrectangular 150 x 150 or larger case: 10-20 rooms, 12-14 packs, fixed room, differing capacities and compatibility.
3. Required-style edge cases: disconnection, over-demand, pack unsuitable for every room.
4. Additional masked-geometry, input, and API boundary fixtures.
5. Tiny exhaustive-search cross-checks for DP score and assignment validity.
6. Sensitivity: vary threat budget, room capacity, room-size bounds, and fixed-room position.
7. Failure experiment: close three corridor sections, recompute actual reachability, rerun allocation.
8. Disable/remove two explicitly defined high-capacity eligible rooms and compare score, unused inventory, and reachability.
9. Benchmark area/room scaling separately from pack/room DP scaling; record repeated-run median/spread, operation counts, build mode, hardware, and toolchain.
10. Compare reuse of geometry for allocation-only edits against a full pipeline rerun. Do not claim incremental DP or dynamic MST repair.

No fabricated timings or prewritten conclusions. The sample's literal twenty-road dataset does not transfer to BSP geometry.

## 11. Academic depth and deliverables

Comparable depth comes from constrained geometry, arbitrary masks, fixed rooms, corridor clearance, exact shared-inventory multiple-container allocation, added global threat/compatibility constraints, proofs, reconstruction, failures, and integration. It does not come from UI complexity or exponential runtime alone.

Report contents:
- Title with four group placeholders and course/university details.
- Abstract, introduction, verified literature review.
- Original case study and concise formulation/assumptions summary.
- Formal objectives/constraints and scope of optimality.
- Methodology, architecture/block diagrams.
- Pseudocode for both primary algorithms and material helpers.
- Correctness and full time/space analysis.
- Actual worked input, dungeon, assignment, and achieved objective.
- Edge cases, sensitivity/failure experiments, measured benchmarks.
- Limitations, conclusion, references, reproduction instructions.

Meet at least six substantive pages without padding. Produce editable DOCX and verify rendering/PDF export locally. Record fonts/settings; exact export on another Word installation may vary. User edits member details and makes final PDF.

Viva guide: scenario, integration, BSP recursion versus decrease-and-conquer, geometry constraints, DP bitmasks/state/base/recurrence, reconstruction/proof, complexity, why this DP versus capacity DP, exactness limits, native ABI, reproducibility, tests, failures, and honest limitations.

## 12. Planned project organization

Keep supplied PDFs intact during planning. Proposed directories:
- plan.md, README.md, CMakeLists.txt
- core/include/dungeon_architect/
- core/src/domain/, validation/, generation/, allocation/, simulation/, trace/
- api/include/dungeon_architect_c.h and api/src/
- cli/
- apps/flutter_ui/
- datasets/teaching/, worked_case/, edge_cases/
- tests/core/, api/, integration/
- benchmarks/
- docs/case_study.md, mathematical_model.md, algorithms.md, architecture.md
- docs/api_contract.md, experiments.md, viva.md, references.md
- assets/licenses/
- output/report/, figures/, app/

Use focused modules rather than unnecessary frameworks. Ignore generated build directories. CMake/CTest and lightweight tests are preferred subject to toolchain verification. External packages require a clear purpose and documented license.

## 13. Implementation phases and gates

### Phase 0: toolchain and specification
Verify actual directory, applicable instructions, compiler/CMake, Flutter Windows setup, and FFI builds. Finalize schemas, pseudocode, tiny manual DP example, lock/mask semantics, API statuses, and budgets.

Observed during planning: Flutter exists at C:\flutter_windows_3.47.5-stable\flutter\bin\flutter.bat. C:\MinGW\bin\g++.exe failed to launch in a sandbox with a DLL relocation error. Full Windows Flutter toolchain is unverified; these observations do not prove an installation is unusable.

Prefer a consistent supported Windows build chain. Gate: core, CLI, and native-library smoke build plus documented model.

### Phase 1: headless geometry
Implement validation, mask/fixed-room handling, BSP, corridor routing, and connectivity. CLI emits machine-readable map and readable summaries.
Gate: deterministic rectangle/irregular/fixed-room cases and correct invalid/search-limited outcomes.

### Phase 2: exact allocation
Implement subset totals/compatibility, DP, reconstruction, independent checker, cancellation, and pipeline integration.
Gate: agreement with tiny exhaustive oracle, all allocation edge cases, measured memory/work limits.

### Phase 3: native API
Implement ABI wrapper, ownership/errors/versioning, worker and cancellation contract.
Gate: CLI and FFI caller agree; lifecycle/error checks pass.

### Phase 4: Flutter Design and Analyze
Build drawing/presets, room editor/locks, catalogue, save/load, assignment display, algorithm events, counters, and charts in user-priority order.
Gate: draw irregular region, lock room, generate exact target, edit inputs, inspect exact assignment without blocking UI.

### Phase 5: exploration and failures
Implement movement/collision/camera/static interactions, exit objective, corridor closure, reachability overlay, and rerun comparison.
Gate: Play and Analyze use the same valid snapshot; edits invalidate safely.

### Phase 6: experiments and submission
Run fixtures/benchmarks, capture real figures, author and visually verify DOCX, complete viva guide, package CLI/app/build instructions.
Gate: reproducible clean build/run and complete report, case study, code, data, proof, and test evidence.

Use relevant document skills when actually authoring the DOCX. Do not let visual work conceal an incomplete core.

## 14. Completion checklist

- [ ] Original case study and explicit integration of two paradigms.
- [ ] At least 150 x 150 canvas, presets, freehand allowed-area painting.
- [ ] Runtime room settings and fixed-room preservation.
- [ ] Mask-constrained rooms/corridors and verified floor connectivity.
- [ ] Exact allocation with uniqueness, capacities, compatibility, global threat.
- [ ] Reconstructed assignments independently verified.
- [ ] Safe validation, cancellation, unsupported-size, and search-limit handling.
- [ ] CLI, reusable native API, Flutter Design/Analyze/Play.
- [ ] Pixel-art fantasy exploration-only experience.
- [ ] Worked case, tests, measured benchmarks, failure/sensitivity experiments.
- [ ] Editable DOCX, dataset/source bundle, runnable app, viva guide.
- [ ] No unsupported claims of global layout optimality, guaranteed fun, or unlimited exact scaling.

## 15. Initial references

Verify and format sources for the literature review; implement the assessed algorithms ourselves.
- PCG textbook chapter: https://antoniosliapis.com/articles/pcgbook_dungeons.php
- MIT knapsack DP: https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-fall-2011/resources/mit6_006f11_rec21/
- Dart C interop: https://dart.dev/interop/c-interop
- Flutter native integration: https://docs.flutter.dev/platform-integration/bind-native-code
- Flutter Windows setup: https://docs.flutter.dev/platform-integration/windows/setup

Maintain this plan with completed milestones, measured limits, blockers, and user-approved scope changes. Do not silently expand into combat, online services, a different optimization problem, or heuristic replacement.

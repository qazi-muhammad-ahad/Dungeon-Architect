# Dungeon Architect - App Implementation TODO

Created: 2026-10-10
Status: Phases 00-11 complete under the approved Chrome-first scope (2026-10-25). Native Dart FFI/mobile/Windows app packaging remain deferred.
Scope: Application engineering only. Product decisions are recorded in [plan.md](plan.md).

## How to use this backlog

- Work in dependency order. Complete a phase's exit checks before treating it as finished.
- All implementation boxes start unchecked. Check an item only after the behavior is implemented and verified.
- Record a blocker next to its task, with the concrete next action.
- Keep one authoritative C++ implementation of generation, allocation, validation, and movement rules.
- Add focused tests with the feature they protect; use independent checks for algorithm results.
- Preserve working project data and the last valid result when an operation fails.
- Keep optional enhancements separate from required functionality.
- Discuss changes to the main algorithms, exactness guarantees, supported workload strategy, or gameplay scope before implementing them.

## Product baseline

- Default 150 x 150 tile canvas, one-tile editing precision, pan and zoom.
- Paint the allowed building area using presets or freehand tools.
- Runtime room-count and size settings; editable and fixed-position rooms.
- Target workload: 10-20 rooms and 12-14 active encounter packs.
- Mask-aware BSP generation, clearance-aware corridor routing, exact subset-DP allocation.
- Editable pack threat, score, spawn demand, compatibility, and global threat budget.
- Reusable native C++ engine/API; working CLI before Flutter integration.
- Flutter Design, Analyze, and Play views.
- Pixel-art fantasy dungeon inside a clean desktop editor.
- Exploration only: movement, collision, entrance/exit, static encounter interactions.
- Initial optimization cap: 14 active packs, subject to measured revision.
- Proposed canvas range: 150-512 per axis, verified before advertising the upper limit.
- No combat, enemy AI, accounts, server, online play, or silent heuristic fallback.

## Phase 00 - Verify the build environment

Platform adjustment approved on 2026-10-11: Chrome is the primary Flutter target; no Visual Studio installation. Native CLI/DLL use portable LLVM-MinGW x64. The original mandatory Windows-runner checks below are replaced by Chrome startup verification. See [platform decision](docs/platform_decision.md). Native Windows Flutter startup remains deferred, not verified.

Dependencies: None.

- [x] P00.01 Confirm the working project directory and applicable local instructions.
- [x] P00.02 Inventory compiler, linker, CMake, build system, Flutter/Dart, Windows SDK, and native desktop build support.
- [x] P00.03 Investigate the previously observed MinGW sandbox launch error before concluding the compiler is broken.
- [x] P00.04 Select one supported Windows toolchain and matching architecture for the CLI and DLL, with Chrome as the Flutter target (approved replacement of the Windows-runner requirement).
- [x] P00.05 Verify C++17 support and Debug/Release builds with a minimal executable.
- [x] P00.06 Build and load a minimal native DLL through a small caller; check exported symbols and bitness.
- [x] P00.07 Verify a minimal Flutter Chrome app starts; identify missing SDK components for the optional Windows runner (approved platform adjustment).
- [x] P00.08 Record the exact successful build/run commands and tool versions in developer setup notes.
- [x] P00.09 Identify required installations separately from ordinary project dependencies; avoid replacing existing tools unnecessarily.

Exit checks:
- [x] A native x64 executable runs, a matching DLL loads, and a Flutter Chrome smoke app launches using the selected setup (approved platform adjustment).

## Phase 01 - Establish repository structure and module boundaries

Dependencies: Phase 00.

- [x] P01.01 Create core, api, cli, apps/flutter_ui, tests, datasets, benchmarks, assets, and app-output directories.
- [x] P01.02 Keep supplied files and existing planning files intact.
- [x] P01.03 Add root CMake configuration with separate core library, native API library, CLI, and test targets.
- [x] P01.04 Add Debug/Release presets, compiler warnings, and appropriate platform-specific build settings.
- [x] P01.05 Add generated-build, cache, temporary-file, and packaged-output ignore rules.
- [x] P01.06 Define domain, validation, generation, allocation, simulation, trace, and adapter module boundaries.
- [x] P01.07 Keep Flutter and file-format dependencies outside the algorithm modules.
- [x] P01.08 Select minimal JSON/test dependencies, if needed, and record versions/licenses.
- [x] P01.09 Add CTest integration and a single meaningful smoke test proving the core links correctly.
- [x] P01.10 Add a developer README with configure, build, test, and CLI launch commands.

Exit checks:
- [x] A clean build produces separate CLI and native-library targets; core tests run through one documented command.

## Phase 02 - Define domain data, validation, and project persistence

Dependencies: Phase 01.

- [x] P02.01 Define tile coordinates and half-open rectangles with checked bounds and dimensions.
- [x] P02.02 Separate allowed-area mask, occupancy/reservations, carved floor, walls, and actors.
- [x] P02.03 Define settings for canvas, room count, room dimensions, margins, corridor width, seed, and work limits.
- [x] P02.04 Define stable IDs and types for rooms, corridor links, packs, spawn positions, and snapshots.
- [x] P02.05 Define room roles/tags, geometry locks, capacity overrides, and reachability.
- [x] P02.06 Define pack copies as distinct IDs, with integer slots, threat, score, and compatibility.
- [x] P02.07 Define structured errors: code, field/path, readable message, affected IDs/tiles, and suggested recovery.
- [x] P02.08 Distinguish invalid input, search exhausted, unsupported size, cancelled, resource failure, and successful outcomes.
- [x] P02.09 Centralize limits and validate negative values, range reversal, numeric overflow, duplicate IDs, and inconsistent mask lengths.
- [x] P02.10 Define a versioned local JSON project schema and canonical stable serialization.
- [x] P02.11 Save source settings and mask independently of derived generation/allocation/play results.
- [x] P02.12 Validate imported data and define unsupported-schema behavior.
- [x] P02.13 Make loading transactional; invalid input leaves the current project untouched.
- [x] P02.14 Save atomically using a temporary file and replacement, with readable file-access errors.
- [x] P02.15 Add project revision IDs and dependency-based invalidation for derived results.
- [x] P02.16 Specify deterministic random-number mapping and canonical tie/traversal order.
- [x] P02.17 Test serialization round trips, malformed files, boundary coordinates, large integer totals, and failed-load preservation.

Exit checks:
- [x] A project can be saved/reopened without source-data loss, and invalid data cannot partially replace a valid project.

## Phase 03 - Implement masks and fixed-room geometry

Dependencies: Phase 02.

- [x] P03.01 Implement rectangle, ellipse, and L-shaped mask generation in the shared domain representation.
- [x] P03.02 Implement tile paint, erase, and flood-fill operations with bounds checks.
- [x] P03.03 Find allowed-mask connected components and provide highlighted detached regions.
- [x] P03.04 Validate fixed-room containment, separation, overlap, dimensions, roles, and IDs.
- [x] P03.05 Reserve locked footprints and required margins without altering the user's underlying mask.
- [x] P03.06 Count locked rooms toward the requested total and reject counts below mandatory fixed-room requirements.
- [x] P03.07 Define distinct entrance/exit selection and the entrance's safe-room behavior.
- [x] P03.08 Validate room edits as proposed transactions before replacing stored geometry.
- [x] P03.09 Retain stable IDs when rooms are renamed, reordered, or selected.
- [x] P03.10 Add fixtures for holes, islands, narrow necks, touching boundaries, and fixed-room conflicts.
- [x] P03.11 Confirm abstract partitioning cannot erase or resize a reserved room.

Exit checks:
- [x] Valid masks and fixed-room reservations are usable by generation; invalid configurations return precise locations and reasons.

## Phase 04 - Implement constrained BSP room generation

Dependencies: Phase 03.

- [x] P04.01 Define partition-node metadata, parent/child relationships, free-area summaries, and requested room counts.
- [x] P04.02 Specify deterministic split orientation, split-position selection, and child room-count distribution.
- [x] P04.03 Implement minimum-size and reservation-aware split validation.
- [x] P04.04 Implement room-candidate search that verifies all footprint cells, including mask holes and reservations.
- [x] P04.05 Enforce interior width/height ranges and margins; do not use bounding-box area as proof of fit.
- [x] P04.06 Implement recursive child generation and combination into a stable room collection.
- [x] P04.07 Preserve fixed rooms even when abstract partition bounds cross reserved space.
- [x] P04.08 Add bounded retries/backtracking with explicit attempt/work limits and cancellation checkpoints.
- [x] P04.09 Return the exact requested room count on success; never silently lower the count.
- [x] P04.10 Return search-exhausted separately from provably invalid input, retaining diagnostics from useful failed candidates.
- [x] P04.11 Build into an isolated candidate snapshot; commit only after all generation checks succeed.
- [x] P04.12 Emit bounded events for region creation, split decisions, rejected candidates, fixed-room reservations, and placed rooms.
- [x] P04.13 Test reproducible seeds, mask containment, non-overlap, lock preservation, exact counts, retries, and cancellation.

Exit checks:
- [x] Rectangular and irregular fixtures produce valid exact-count room layouts, while failed attempts leave the previous dungeon unchanged.

## Phase 05 - Route corridors and derive walkable dungeon data

Dependencies: Phase 04.

- [x] P05.01 Define door positions and attachment rules for generated and fixed rooms.
- [x] P05.02 Generate connection requirements from BSP child combinations and include fixed-room terminals.
- [x] P05.03 Implement BFS routing through legal corridor-footprint positions.
- [x] P05.04 Validate the entire corridor width around corners and at doors, not only its centerline.
- [x] P05.05 Allow routes outside child partition bounds when necessary, but never outside the allowed mask.
- [x] P05.06 Prevent unintended carving through locked interiors; apply explicit doorway rules.
- [x] P05.07 Rasterize rooms, corridors, and walls into authoritative tile layers.
- [x] P05.08 Verify actual floor connectivity from the entrance, including fixed rooms and exit.
- [x] P05.09 Detect narrow passages or inaccessible attachments without changing corridor width silently.
- [x] P05.10 Choose stable valid entrance/exit marker positions.
- [x] P05.11 Derive valid spawn positions with spacing and reserved movement/door regions.
- [x] P05.12 Derive room capacities and reject overrides above available valid positions.
- [x] P05.13 Record routing/reachability events and operation counters.
- [x] P05.14 Test corner clearance, irregular boundaries, blocked doors, corridor intersections, and disconnected floors.

Exit checks:
- [x] A successful generation is physically walkable, inside the mask, and ready for allocation; abstract links cannot conceal tile disconnection.

## Phase 06 - Implement exact encounter allocation and placement

Dependencies: Phase 05. Isolated optimizer fixtures can be developed after Phase 02.

- [x] P06.01 Build eligible-room inputs from reachability, roles, dimensions, and valid capacities.
- [x] P06.02 Assign canonical bit positions to pack IDs and validate the 14-active-pack limit.
- [x] P06.03 Precompute subset slot, threat, and score totals with checked arithmetic.
- [x] P06.04 Precompute per-room subset compatibility/capacity feasibility.
- [x] P06.05 Estimate DP memory and workload before allocating tables; return a structured unsupported/resource outcome if necessary.
- [x] P06.06 Implement F(r,M): feasibility of assigning exactly pack subset M across the first r rooms.
- [x] P06.07 Initialize only F(0,empty) as feasible and enumerate compatible last-room subsets, including empty subsets.
- [x] P06.08 Select the highest-scoring feasible final subset within the threat budget.
- [x] P06.09 Resolve ties by lower threat, lower slot use, then canonical IDs/traversal.
- [x] P06.10 Store predecessor decisions and reconstruct actual room-to-pack assignments.
- [x] P06.11 Map assigned actors deterministically to distinct legal spawn positions.
- [x] P06.12 Implement an independent result validator for uniqueness, slots, compatibility, budget, reachability, and objective totals.
- [x] P06.13 Explain unused packs accurately: intrinsically incompatible/oversized, or simply unselected by the optimum; avoid inventing one causal explanation.
- [x] P06.14 Add cancellation checkpoints and work/time-budget handling without labelling interrupted results optimal.
- [x] P06.15 Emit compact state summaries and reconstruction events; support detailed traces only for small inputs.
- [x] P06.16 Build a tiny exhaustive-assignment oracle and compare optimal scores across deterministic and randomized small fixtures.
- [x] P06.17 Test zero budgets, zero-threat packs, zero scores, no eligible rooms, oversized packs, over-demand, ties, and input reordering.
- [x] P06.18 Test room capacity and threat edits that change the optimum without changing geometry.

Exit checks:
- [x] Exact results agree with the independent oracle on small inputs; every reconstructed placement passes independent validation.

## Phase 07 - Complete the CLI and end-to-end engine workflow

Dependencies: Phases 02-06. Add useful CLI commands incrementally during those phases.

- [x] P07.01 Provide help and commands for project validation, generation, optimization, combined execution, and result export.
- [x] P07.02 Accept file input, seed, supported overrides, output paths, and trace/metrics options.
- [x] P07.03 Print readable room/assignment/budget summaries and a scaled or cropped text-map preview.
- [x] P07.04 Export full machine-readable geometry and allocation without relying on text-map precision.
- [x] P07.05 Define stable exit codes and separate machine-readable output from diagnostic messages.
- [x] P07.06 Add small sample projects and realistic irregular-mask fixtures under datasets.
- [x] P07.07 Exercise cancellation, invalid files, unsupported sizes, and search exhaustion through the same pipeline.
- [x] P07.08 Verify repeated runs reproduce IDs, geometry, assignment, and objective under the declared determinism contract.

Exit checks:
- [x] All core workflows run from the CLI before a graphical interface is needed.

## Phase 08 - Build the native API and Dart integration boundary

Dependencies: Phase 07.

Platform adjustment confirmed on 2026-10-12: test Flutter in Chrome using the same C++ API compiled to WebAssembly in a browser worker. Keep the native DLL build alongside it; defer native Dart FFI and Windows/mobile application packaging. This replaces P08.10/P08.11 and the original DLL/Dart exit gate below. See [platform decision](docs/platform_decision.md) and [API contract](docs/native_api.md).

- [x] P08.01 Define the versioned public C header and exported symbol/calling-convention policy.
- [x] P08.02 Expose opaque contexts/jobs and fixed-width, length-delimited values; keep C++ types private.
- [x] P08.03 Provide project validation, generation, optimization, result retrieval, metrics, trace retrieval, and the initial authoritative tile-step simulation operation. Full scenarios and Play controls remain Phases 14/15.
- [x] P08.04 Define ownership and matching release functions for every native allocation crossing the boundary.
- [x] P08.05 Catch exceptions at all public entry points and translate to structured outcomes.
- [x] P08.06 Implement safe context/job lifetime rules and cancellation that remains usable while work is running.
- [x] P08.07 Define bounded progress polling/event batches without callbacks into invalid Dart objects.
- [x] P08.08 Implement ABI/schema version negotiation and reject incompatible library/schema contracts clearly; retain compatible older source documents.
- [x] P08.09 Add a standalone native caller and verify results match the CLI.
- [x] P08.10 Add Dart JS interop bindings and a Web Worker adapter for expensive C++ operations (approved Chrome replacement for native Dart FFI/isolate work).
- [x] P08.11 Handle relative Wasm/worker discovery, missing JS/Wasm assets, ABI/schema/bitness mismatch, and load failures gracefully. Native Flutter DLL discovery remains deferred.
- [x] P08.12 Verify cleanup on success, error, cancel, window close, and repeated context creation/destruction.
- [x] P08.13 Add ABI contract tests for null/invalid handles, malformed requests, lengths, repeated calls, and defined lifecycle errors.
- [x] P08.14 Write developer-facing API usage examples and ownership notes.

Exit checks:
- [x] Dart in Chrome can load the shared C++ Wasm API, run/cancel work, retrieve CLI-matching results, and release worker resources without running engine work on the UI thread. The standalone C caller also verifies the side DLL.

## Phase 09 - Build the Flutter shell and shared application state

Dependencies: Phase 08.

- [x] P09.01 Create desktop layout with Design, Analyze, and Play navigation.
- [x] P09.02 Define a restrained editor theme, typography, spacing, focus states, and semantic status colors.
- [x] P09.03 Create one project controller with source inputs, last valid results, revision IDs, selection, and active-job state.
- [x] P09.04 Distinguish idle, running, cancelling, successful, stale, invalid, and failed states.
- [x] P09.05 Connect the shared-C++ WebAssembly worker (approved Chrome-first adaptation); apply only results matching the current input revision. Native Dart FFI remains deferred.
- [x] P09.06 Keep previous valid output visible with a stale label when edits invalidate it.
- [x] P09.07 Build reusable numeric fields with units, ranges, parsing, and inline feedback.
- [x] P09.08 Add accessible keyboard focus, tooltips, status panel, and recoverable error presentation.
- [x] P09.09 Add New/Open/Save/Save As and unsaved-change handling using the shared project format.
- [x] P09.10 Confirm resizing, high-DPI scaling, and view switching preserve project and selection state.

Exit checks:
- [x] A project loads/saves and native C++ jobs run/cancel through the Chrome worker while the shell remains responsive.

## Phase 10 - Implement the Design canvas and shape tools

Dependencies: Phase 09.

- [x] P10.01 Implement a shared camera transform for rendering, cursor hit-testing, zoom, and panning.
- [x] P10.02 Render allowed area, generated floor, walls, and reservations as distinct layers.
- [x] P10.03 Add cursor-centered zoom, fit-to-view, scroll/pan controls, and tile-coordinate readout.
- [x] P10.04 Add one-tile paint/erase precision and configurable brush sizes.
- [x] P10.05 Interpolate fast mouse drags so brush strokes do not leave unintended gaps.
- [x] P10.06 Add rectangle, ellipse, and L-shape presets plus fill operations.
- [x] P10.07 Add a preview before committing a shape that replaces or modifies existing mask content.
- [x] P10.08 Implement gesture-level undo/redo with bounded history memory.
- [x] P10.09 Validate edits that intersect fixed rooms; reject or require an explicit corrective action rather than silently unlocking rooms.
- [x] P10.10 Render detached components, invalid regions, and too-narrow areas as optional diagnostics.
- [x] P10.11 Add canvas resizing with explicit handling of content that would fall outside new bounds.
- [x] P10.12 Cull offscreen tiles and measure interaction at supported canvas sizes.
- [x] P10.13 Test hit-testing and painting at different zoom levels, edges, and DPI scales.

Exit checks:
- [x] Users can draw a precise nonrectangular allowed area, undo edits, and navigate a 150 x 150 or larger canvas comfortably.

## Phase 11 - Implement room and encounter editing

Dependencies: Phase 10.

- [x] P11.01 Add runtime total room count, room size ranges, corridor width, margin, and seed controls.
- [x] P11.02 Implement fixed-room draw/select/move/resize previews with lock toggles and explicit commit.
- [x] P11.03 Add room naming, roles, compatibility tags, capacity, and valid-position inspection.
- [x] P11.04 Prevent locked-room edits until explicitly unlocked; keep stable IDs across regeneration.
- [x] P11.05 Add the encounter catalogue with create/edit/duplicate/remove and unique inventory-copy IDs.
- [x] P11.06 Make threat, designer score, slots, compatibility, and minimum room dimensions editable with clear units.
- [x] P11.07 Separate saved catalogue entries from the active inventory used by optimization.
- [x] P11.08 Show active-pack count and supported exact-solve limit before execution.
- [x] P11.09 Add global threat-budget control and Generate/Optimize actions.
- [x] P11.10 Highlight assignments, room slot use, score, threat use, and unused packs on successful optimization.
- [x] P11.11 Support geometry reuse for allocation-only edits and show which outputs need recomputation.
- [x] P11.12 Test a complete draw -> fix room -> generate -> edit pack -> optimize -> save -> reopen workflow.

Exit checks:
- [x] The main project inputs are editable without JSON hand-editing, and invalid edits cannot corrupt a valid snapshot.

Evidence (2026-10-25): runtime generation inputs, validated room previews/locks/details, catalogue CRUD and active inventory, exact-limit feedback, generation-only and allocation-only actions, assignment/unused-pack display, and dependency-aware reuse implemented. Native Release build and 18/18 CTest suites passed; final extended API contract passed after its last additions. Flutter analyzer clean; 27/27 Flutter tests passed. Wasm and CSP release web builds plus deployment artifact verification passed. Real Chrome phase 11 workflow and phase 10 canvas regression passed; workflow screenshot inspected. Source-save/reopen intentionally regenerates derived output; room/catalogue edits are outside mask undo history. See [room and encounter editor](docs/room_encounter_editor.md).

## Phase 12 - Implement Analyze visualization and trace playback

Dependencies: Phase 11 and native trace events.

- [ ] P12.01 Define common event metadata: run ID, input revision, sequence, stage, affected IDs, and payload schema.
- [ ] P12.02 Add overlay toggles for mask, partition bounds, room IDs, capacities, doors, connectivity, and assignments.
- [ ] P12.03 Render the BSP tree with selection linked to the matching map region.
- [ ] P12.04 Animate real split/placement/connection events with play, pause, step, restart, and speed controls.
- [ ] P12.05 Show fixed rooms as preserved features rather than misrepresenting them as generated leaves.
- [ ] P12.06 Display allocation summaries and animate actual reconstructed pack-to-room decisions.
- [ ] P12.07 Provide a small-state DP inspector showing masks, candidate subsets, and feasible transitions.
- [ ] P12.08 Use compact summaries for full-size runs; visibly label sampled or truncated traces.
- [ ] P12.09 Bound event queues, playback memory, and retained snapshots; define checkpoint/replay behavior.
- [ ] P12.10 Ensure animation speed, pause, or trace sampling cannot change algorithm output.
- [ ] P12.11 Display exact, cancelled, unsupported, and search-limited statuses without misleading optimality labels.
- [ ] P12.12 Test traces from cancelled/stale jobs and switching views during playback.

Exit checks:
- [ ] Users can inspect what the engine actually did without cluttering the normal dungeon view or freezing large runs.

## Phase 13 - Add performance metrics and benchmark charts

Dependencies: Phases 07 and 12.

- [ ] P13.01 Instrument generation stages, routing, subset preprocessing, DP, reconstruction, and serialization separately.
- [ ] P13.02 Track relevant operation counts, retries, explored states, and estimated/observed state storage with accurate labels.
- [ ] P13.03 Separate algorithm timing from tracing, serialization, UI rendering, and playback.
- [ ] P13.04 Add configurable benchmark batches varying tile area, room count, and active pack count independently.
- [ ] P13.05 Use fixed fixture seeds and record engine version, parameters, build mode, and environment metadata.
- [ ] P13.06 Perform repeated runs and show median/spread rather than one unqualified timing.
- [ ] P13.07 Add charts and raw-result inspection/export inside Analyze.
- [ ] P13.08 Add cancellation, progress, workload preview, and history limits for benchmark jobs.
- [ ] P13.09 Measure the target 10-20 room, 12-14 pack workloads before finalizing published limits.
- [ ] P13.10 Optimize only demonstrated bottlenecks and recheck correctness after changes.
- [ ] P13.11 Use results to validate memory/work limits and responsive cancellation targets.

Exit checks:
- [ ] Charts show reproducible engine measurements, and advertised limits are supported by measured runs.

## Phase 14 - Add failure simulation and result comparisons

Dependencies: Phase 12; metrics comparison uses Phase 13.

- [ ] P14.01 Allow selected corridor sections to be temporarily blocked without altering the saved baseline.
- [ ] P14.02 Recompute actual walkability and highlight rooms/exit disconnected from the entrance.
- [ ] P14.03 Rerun allocation using the changed reachable-room set.
- [ ] P14.04 Add temporary room-disable and capacity/budget-change scenarios using explicit controls.
- [ ] P14.05 Show before/after reachable rooms, selected packs, score, threat use, and timings.
- [ ] P14.06 Provide restore-baseline/reset-scenario behavior without losing original inputs.
- [ ] P14.07 Mark old assignments stale immediately after connectivity changes.
- [ ] P14.08 Handle all rooms disconnected, sealed exit, and zero remaining capacity.
- [ ] P14.09 Preserve exact-solver status and describe full reruns accurately; do not claim incremental optimization.
- [ ] P14.10 Test blocked sections intersecting doors or multiple routes, scenario reset, and save/load semantics.

Exit checks:
- [ ] Failure scenarios produce valid changed results and can be reversed safely.

## Phase 15 - Implement exploration-only Play mode

Dependencies: Phase 11; share map rendering and valid snapshots with Analyze.

- [ ] P15.01 Define a play session referencing an immutable validated dungeon/assignment snapshot.
- [ ] P15.02 Place the player at a valid entrance position and expose a restart control.
- [ ] P15.03 Add WASD/arrow movement and authoritative C++ collision rules.
- [ ] P15.04 Make movement frame-rate independent and prevent tunnelling through walls at large frame steps.
- [ ] P15.05 Add camera follow and a clear exit marker.
- [ ] P15.06 Render encounter actors as static nonblocking markers from reconstructed assignments.
- [ ] P15.07 Add nearby-marker interaction displaying pack, room, threat, and score.
- [ ] P15.08 Add a simple reach-the-exit completion state.
- [ ] P15.09 Pause/clear held input on focus loss, modal dialogs, or tab changes.
- [ ] P15.10 Invalidate/restart play after relevant project edits; never mix geometry from different revisions.
- [ ] P15.11 Explain disconnected exits before starting affected scenarios.
- [ ] P15.12 Test walls, narrow corridors, doors, map edges, restart, focus loss, and repeated view switching.

Exit checks:
- [ ] Users can explore exactly the generated dungeon and inspect its assigned encounters without additional combat systems.

## Phase 16 - Visual polish, usability, and robustness

Dependencies: Core Design/Analyze/Play flows are functional.

- [ ] P16.01 Establish a coherent pixel-art tile/actor palette and record asset sources/licenses.
- [ ] P16.02 Render pixel art crisply at supported scales; keep UI text independent of world scaling.
- [ ] P16.03 Improve map layering, walls, doors, selection outlines, and role markers without hiding diagnostics.
- [ ] P16.04 Review screen hierarchy and panel density; keep Analyze overlays optional.
- [ ] P16.05 Add helpful empty states, invalid-field explanations, loading/cancel states, and recovery actions.
- [ ] P16.06 Audit keyboard navigation, focus order, readable contrast, and non-color-only status indicators.
- [ ] P16.07 Test supported window sizes and DPI settings, long room/pack names, and large catalogues.
- [ ] P16.08 Run repeated edit/generate/optimize/cancel/play sessions and check memory/handle cleanup.
- [ ] P16.09 Run malformed-project and randomized small-input checks through native entry points.
- [ ] P16.10 Verify undo, failed operations, and app close never silently discard unsaved project changes.
- [ ] P16.11 Resolve correctness and responsiveness defects before cosmetic refinements.

Exit checks:
- [ ] Main workflows remain legible, responsive, and recoverable under normal and invalid inputs.

## Phase 17 - Package and verify the application

Dependencies: Phases 00-16.

- [ ] P17.01 Build Release versions of the CLI, native DLL, and Flutter Windows app.
- [ ] P17.02 Package required native/runtime dependencies and asset licenses.
- [ ] P17.03 Verify relative DLL/asset discovery without developer-machine absolute paths.
- [ ] P17.04 Include a few ready-to-open sample projects and a blank-start workflow.
- [ ] P17.05 Add concise installation, launch, project-format, controls, known-limit, and troubleshooting instructions.
- [ ] P17.06 Include native API headers and a minimal local integration example for reuse.
- [ ] P17.07 Run core/API/integration tests and the full user workflow from a fresh build directory.
- [ ] P17.08 Launch the packaged app from a different directory, including a path containing spaces.
- [ ] P17.09 Verify open/save, generation, optimization, traces, charts, failures, and exploration in the packaged build.
- [ ] P17.10 Confirm unsupported-size and cancellation behavior matches the development build.
- [ ] P17.11 Record verified platform/toolchain/library versions and remaining product limitations.
- [ ] P17.12 Update this checklist to reflect actual completion; leave unfinished items explicitly unchecked.

Exit checks:
- [ ] The packaged app and CLI run independently of the development checkout and include everything needed for local use.

## Optional backlog - not required for the initial application

- [ ] O01 Closed-polygon mask drawing with editable vertices.
- [ ] O02 Key pickup and a locked-exit exploration objective.
- [ ] O03 Minimap if full-map navigation warrants it.
- [ ] O04 Additional mask presets after the shared shape tools are reliable.
- [ ] O05 Additional native platform builds after Windows packaging is stable.

## End-to-end completion checks

- [ ] Draw a custom allowed area on a 150 x 150 or larger canvas.
- [ ] Place and lock a room, enter room count/sizes, and generate without moving the locked geometry.
- [ ] Edit encounters and threat budget; obtain an exact, validated assignment.
- [ ] Inspect real BSP and allocation behavior in Analyze.
- [ ] View measured benchmark charts.
- [ ] Block a corridor, inspect changed reachability/allocation, and restore the baseline.
- [ ] Explore the same dungeon in Play and reach its exit.
- [ ] Save, close, reopen, and reproduce the project.
- [ ] Cancel expensive work and recover from invalid input without losing the last valid project.
- [ ] Run the packaged app and use the native API from the included standalone example.

## Implementation log

### 2026-10-11 - Phases 00/01

- Created the whole application and a local Git repository on `main` at `E:\Uni\sem5\DAA\Dungeon Architect`. No GitHub remote, commit, or push yet; the user clarified Fork is the installed Git client.
- Preserved original source files in Downloads. Copied plans/deliverables and all six PDFs into the new repository; verified PDF hashes. This project copy is now the active TODO.
- Reproduced the legacy MinGW sandbox launch error; the same compiler ran outside the sandbox. Its GCC 6.3.0/mingw32 toolchain passed basic 32-bit linkage checks but failed the C++17 `<string_view>` probe.
- User declined Visual Studio, approved Chrome, and approved a project-local portable compiler. Installed pinned LLVM-MinGW 20261006 (Clang/LLD 23.1.3, UCRT x64, Make 4.4.1) and CMake/CTest 3.31.10 under ignored `.tools`, with archive SHA-256 verification. No system PATH change or replacement of the old compiler.
- Implemented separate static core, shared C API, CLI, and test targets; Debug/Release presets; C++17 probe; C-compatible dynamic DLL loader; warnings; ignore rules; module boundaries; reproducible setup/build scripts; VS Code tasks; and developer/dependency notes.
- Native Debug and Release: all 3 CTest checks pass. CLI reports version 0.1.0 and 64-bit. DLL export/PE inspection confirms the two unmangled bootstrap exports and x64 architecture.
- Flutter 3.47.5 / Dart 3.13.4: analyzer passes, host widget smoke test passes, release web build passes, and `flutter run -d chrome --release --no-web-resources-cdn` launches Chrome. Browser preview visually checked; corrected heading contrast.
- Extra headless `flutter test --platform chrome` stalled while loading and was stopped. This is not counted as a passing check; investigate the harness before later browser integration tests.
- Windows Flutter remains optional/unverified because MSVC/Windows SDK are absent. Browser engine integration is not implemented; the proposed shared-C++ WebAssembly/worker adapter is recorded for Phase 08. No algorithms or later-phase product behavior were implemented.
- Reproduction: `tools/build-native.ps1 -Configuration Debug` (or `Release`); Flutter commands in `README.md` and `docs/developer_setup.md`.


### 2026-10-11 - Phase 02: C++ API and CLI first

- Followed the user's reaffirmed architecture: shared C++ behavior exercised through CLI outputs before wrapping it in Flutter. No frontend changes. The full C DLL/job ABI is still Phase 08; Phase 02 exposes a reusable public C++ library API.
- Implemented checked tiles/half-open rectangles; separate allowed-mask and derived tile/actor layers; source settings, room locks/roles/tags/capacity, inventory-copy IDs, compatibility, snapshot types, and structured outcome/diagnostic types.
- Added centralized structural/storage limits, strict UTF-8 and identifier checks, integer/range/duplicate validation, checked signed 64-bit active-inventory totals, and a separate 14-active-pack optimizer eligibility check. Oversized active inventories can remain saved without claiming solver support.
- Added schema-1 strict JSON parsing and canonical serialization via privately vendored nlohmann/json 3.12.0 (MIT, published header hash verified). Unknown/duplicate keys, malformed values, unsupported schemas, excessive depth/file size, and invalid source records are rejected. Core remains free of JSON/Flutter/file-format dependencies.
- Added transactional ProjectSession updates/loads; source/geometry/allocation/play revision tracking; immutable retained results with explicit staleness; and stale-job publication rejection. Names/inactive edits do not discard geometry, and budget/pack edits invalidate allocation/play only.
- Implemented same-directory exclusive temporary-file saves, flush/close before replacement, no delete-first fallback, and race-safe create-only mode. Windows Unicode paths, replacement, locked-target failure, old-file preservation, and temporary cleanup are covered by tests.
- Added CLI new/validate/inspect/save, structured --json diagnostics, stable exit codes, explicit --force for overwrite, a small source fixture, JSON Schema, C++ API examples, and a versioned deterministic RNG/traversal contract.
- Verified all 6 CTest suites in Debug and Release: toolchain.cxx17, core.smoke, core.project, project.persistence, cli.project, api.load_library. Core/persistence checks cover malformed input, boundary coordinates, 64-bit totals, canonical reordering, session invalidation, random mapping, failed-load preservation, and atomic-save failures.
- Independently validated the Draft 2020-12 JSON Schema and teaching/CLI-generated documents with Python jsonschema 4.23.0 (optional local verification tool, not a build dependency). Ran a CLI create -> save -> reopen/validate demonstration under ignored output/app.
- At the phase-02 checkpoint, engine version was 0.2.0 and geometry-specific checks were deferred to phase 03 below. POSIX IO fallback is unverified on this Windows host.

### 2026-10-11 - Phase 03: mask and fixed-room C++ API with CLI controls

- Implemented rectangle, exact integer ellipse, and L-shaped mask presets; transactional paint/erase/four-neighbor flood fill; component labels/bounds/tiles with deterministic primary/detached classification.
- Added source-room mask/margin containment, overlap/separation, unique terminal roles, and mandatory room-count validation. Diagnostics carry stable IDs, JSON paths, and representative offending tiles. Margin is the minimum tile gap between interiors; reservation buffers may overlap.
- Added immutable PreparedGeometry/ReservationMap snapshots with canonical fixed-room IDs, footprint ownership, separate reserved cells, and full-cell candidate checks. Tests show crossing candidate/partition rectangles cannot overwrite fixed geometry and later source edits cannot mutate a prepared reservation. Actual BSP integration remains phase 04.
- Any position or size lock makes the whole current footprint mandatory for generation. Edits honor each flag separately; unlock before moving/resizing/removing. Invalid room and mask edits preserve the previous source, revisions, and saved file. Rename/reorder retain stable IDs.
- Added deterministic distinct terminal selection and entrance capacity zero. Geometry preflight rejects empty masks, fixed rooms on separate components, and insufficient non-boss terminal slots. It does not claim exact-count placement or corridor feasibility.
- CLI now supports mask-info (ASCII or full JSON layers), mask, paint, fill, room-add, room-set, room-lock, room-remove, and validate --for-generation. Commands use the shared C++ behavior and atomic project persistence; no Flutter algorithms or frontend changes.
- Added seven edge-case fixtures covering holes, islands, narrow necks, boundary touching/conflict, overlap, and fixed rooms on disconnected islands. All eight dataset documents pass the independent structural JSON Schema check; intentionally invalid geometry is rejected by the domain API.
- All eight CTest suites pass in Debug and Release, including core.geometry (42,080 assertions; exhaustive 512-mask independent reachability oracle) and cli.geometry (actual CLI edits, diagnostics, reservations, and unchanged-file hashes on failure). Native compilation is warning-clean.
- Ran the documented L-mask -> locked entrance -> rejected move -> unlock -> move -> relock -> validate walkthrough. Verified the rejected move leaves identical file bytes; a sample is saved under ignored output/app.
- Engine version is now 0.3.0; project schema remains 1. CLI testing instructions are in docs/cli.md; API semantics in docs/geometry.md. Phase 04 BSP, phase 05 corridors, later optimization, and Flutter/C ABI integration remain unchecked.

### 2026-10-11 - Phase 04: constrained BSP room generation

- Implemented deterministic BSP split/count search, minimum-origin and reservation-aware pruning, full-cell candidate checks, bounded backtracking, cancellation, deadlines, and work/attempt budgets. Exact-count success only; failures expose no partial layout.
- Fixed rooms survive abstract splits unchanged. Accepted partitions retain parents/children, free-area summaries, targets, and fixed intersections; abstract connection requirements include every room.
- Added immutable room-layout publication with independent result validation, stale revision rejection, and retention of the previous layout and floor snapshot. Bounded traces do not affect random choices or work accounting.
- Added generate CLI, ASCII/JSON outputs, transient run overrides, generation fixtures, a 64-seed/shape test matrix, dense rollback coverage, corruption checks, and failure preservation. All 10 CTest suites pass in Debug and Release at version 0.4.0.
- Pseudocode, bounds, deterministic ordering, and reproduction commands are in docs/generation.md. Corridor routing is phase 05 and was authorized as the next step.

### 2026-10-11 - Phase 05: width-aware corridors and verified walkable data

- Implemented explicit width-wide boundary doors and multi-source BFS over full square corridor footprints. Routes may leave BSP regions, reuse corridors, and cross existing corridor footprints. Mask holes, room interiors, and unrecorded room openings are forbidden; corridor width is never silently reduced.
- Rasterized independent floor/walls/occupancy/reservation layers; verified every actual floor tile reachable from the entrance. Added deterministic room hubs, entrance/exit markers, reserved movement lanes, stable spaced spawn cells and capacities. Entrance remains safe; impossible overrides fail with room/tile diagnostics.
- Added bounded routing events/counters, cancellation, cooperative work/time limits, immutable result construction, full result validation at publication, and source/layout-ID stale rejection. Failed/cancelled routing and invalid capacity changes retain the previous floor snapshot.
- Added route CLI, ASCII dungeon preview, full JSON layer/door/path/spawn export, six routing fixtures, and the standard 150x150 source. Generation and routing remain authoritative C++; Flutter and the cross-language C ABI remain deferred.
- Final Debug and Release builds pass all 12 CTest suites with no compiler warnings. Core generation has 76,025 checks including independent cell scans across 64 seed/shape cases and actual abstract cuts through unchanged fixed rooms. Core routing has 2,388 checks including an independent floor traversal, exact-length straight route, width-aware hole turns, corridor intersections, same-square door attachments, narrow-neck failure, capacities, corruption, cancellation, and retained results.
- Independently verified all 20 source fixtures against the JSON Schema. Compared 14 CLI generation/routing cases byte-for-byte across Debug and Release, including failures, with input hashes unchanged. The 150x150 seed-42 run yields 16 rooms, 15 corridors and 4,388 reachable floor cells; a full JSON example is saved in ignored output/app/phase05-standard-697155d9.json.
- Current engine version 0.5.0; source schema remains 1. Algorithms/pseudocode, limits and commands are in docs/generation.md, docs/routing.md and docs/cli.md. Greedy routing failure is not proof of global impossibility; no partial walkable dungeon is published. Phase 06 optimization and later frontend/gameplay work remain unchecked.

### 2026-10-11 - Phase 06: exact encounter allocation and actor placement

- Implemented the planned exact F(r,M) subset DP with canonical active-pack bits, checked 64-bit subset totals, role/tag/dimension/capacity feasibility, empty subsets, stored predecessors, and the existing deterministic score/threat/slots/ID tie contract. No heuristic fallback or partial optimum.
- Added table/work preflight estimates, a 64 MiB DP-table guard, the 14-active-pack limit, cooperative cancellation/deadlines, bounded state summaries and small-input detailed traces. Resource/interruption failures return no allocation.
- Reconstructs pack-to-room assignments and one distinct legal actor spawn per slot. An independent validator checks active-inventory uniqueness, room compatibility/reachability/capacity, actors, budget, totals and accurate unused-pack explanations.
- Added a public C++ allocation API, a validated routed-geometry adapter, and immutable session publication guarded by source/geometry/allocation dependencies. Capacity, tags, threat, score and budget edits can rerun allocation while retaining geometry. Invalid, cancelled and stale jobs preserve previous results.
- Added optimize CLI with transient --budget and --detailed-trace options, readable output and full allocation JSON. Four source fixtures cover a known optimum, zero-budget/zero-threat selection, a 150x150 14-pack case, and unsupported 15-pack inventory. Full combined CLI/export polish remains Phase 07; Flutter/C ABI integration remains Phase 08 onward.
- Debug and Release pass all 14 CTest suites with no compiler warnings. core.allocation passes 4,470 assertions, including 400 randomized tiny cases against an independent exhaustive-assignment oracle, full tie comparisons, reordered-input placement stability, corruption rejection, numeric/resource boundaries, cancellation, deadlines, geometry reuse and stale result preservation.
- All four new fixtures pass independent JSON Schema validation. Nine CLI cases match byte-for-byte between Debug and Release, with source hashes unchanged. An independent 2^14 subset upper-bound enumeration confirms the standard case's optimum score 74; its validated placement uses threat 24 and 20 actors in the 16-room dungeon.
- Standard allocation metrics: 1,163,324 estimated table bytes, 72,040,362 conservative work estimate, 5,295,776 actual operation units. These counters exclude validation/copying and are not a general performance claim. Example output: ignored output/app/phase06-standard-14.json.
- Engine version 0.6.0, source schema still 1. Recurrence/proof, input contract, lifecycle, limits, trace semantics and reproduction commands are in docs/allocation.md and docs/cli.md. All Phase 06 tasks and its exit check are complete.

### 2026-10-11 - Phase 07: complete CLI workflow and full-result exports

- Added run and export commands using the authoritative C++ generation/routing/allocation pipeline. Existing generate/route/optimize commands retain their stage payloads and now share serializers and output handling. Help documents the complete workflow.
- Added atomic --output/positional exports with explicit --force, source/marker alias protection, no-clobber publication and preservation of prior output on failures. Reused the existing flushed temporary-file writer; derived reports have a 128 MiB file limit. Windows JSON stdout uses LF bytes to match exported files exactly.
- Combined result format 1 includes canonical effective source for replay, full partition/room metadata, all tile layers, doors, complete corridor paths, markers, spawn positions, allocation/actor records, dependency IDs/revisions, per-stage metrics and bounded events. A failed combined run exposes no partial result. Engine version is 0.7.0; source schema remains 1.
- Added transient room-count and corridor-width overrides, optional human metrics, labelled tile-accurate preview crops, --no-map, and optional --cancel-file for scripted cooperative cancellation alongside Ctrl+C. Successful source overrides are embedded in exports. Input/output and diagnostics retain documented stable exit codes and stdout/stderr separation.
- Added teaching and realistic 150x150 irregular-fortress fixtures. The fortress has an L-shaped boundary, a 14x14 courtyard hole, three locked rooms, capacity overrides, 14 active packs and compatibility restrictions. Verified seed 2 yields 16 rooms, 15 corridors, 3,614 connected floor cells, score 74, threat 24 and 20 actors. Other seeds may exhaust the bounded search; no algorithm or feasibility guarantee was changed.
- All 16 CTest suites pass in Debug and Release with no compiler warnings. New coverage includes combined exports/replay, byte-level stdout/file equality, crop/override parsing, malformed/missing files, unsupported inventory, generation/routing exhaustion, allocation resources, source/hard-link protection, cancellation and retained old exports. A native Windows test launches an actual hidden CLI process, requests cancellation while it is running, verifies exit 6 and checks both source and prior output preservation.
- Extended atomic-writer checks cover Unicode result filenames, create-only refusal, explicit replacement, locked-file failure and temporary cleanup. Corrected Windows path checking to avoid opening workspace ancestors while still verifying existing file identities.
- Independently validated both new fixtures against JSON Schema; eight success/failure cases match Debug/Release byte-for-byte. Successful embedded-source replays reproduce the entire report. Independently checked exported floor connectivity/containment, locked bounds, spawn membership, actor uniqueness, room demand and objective totals. Source hashes remain unchanged.
- A verified full export is saved under ignored output/app/phase07-fortress-8ec70cd0.json. Commands and replay/format contracts are in docs/cli.md and docs/result_format.md. All Phase 07 checklist items and its exit check are complete. Phase 08 C ABI/browser integration remains unimplemented.


### 2026-10-12 - Phase 08: shared C ABI and Chrome worker integration

- Followed the user's explicit Chrome-first clarification. The same C++ core builds as WebAssembly for Chrome and a Windows x64 DLL with the existing portable compiler. Native Dart FFI/worker-isolate integration, Windows runner packaging and mobile platform builds are deferred; the adapted Phase 08 tasks and exit gate state that explicitly.
- Added ABI 1, cdecl/unmangled exports, opaque non-reused context/job tokens, fixed-width values, caller-owned UTF-8 buffers, exact ABI/schema negotiation, bounded input/result/context/trace limits, and exception-to-status/report translation. Kept bootstrap exports compatible.
- Added validation/generate/route/optimize/run jobs, stage polling, cooperative cancellation, report/metrics reads, bounded trace pages, matching release operations and safe running-job/context release rejection. Failed/cancelled work preserves the last successful report and immutable geometry. The API shares extracted serializers with the CLI; no algorithm or exactness guarantee changed.
- Added the initial shared C++ cardinal tile-step collision operation with a retained-snapshot identity check. It handles walls/edges and nonblocking actors. Full failure scenarios and time-based Play controls remain Phases 14/15.
- Pinned project-local Emscripten 6.0.12 (emsdk 35ff8a6d150541276abbc6bae512ca90bcfbe220). Added reproducible bootstrap/build scripts, enabled exception support and Asyncify checkpoint yielding, and copied generated Wasm assets into Flutter's web build. No permanent PATH change, Visual Studio installation, application server, or duplicate Dart algorithm implementation.
- Added a JS worker/client and Dart web adapter, bounded stage updates, structured startup failures, exact int64 JSON transport, graceful close plus bounded worker-termination fallback, and explicit unsupported-native-platform behavior. Chrome smoke UI can run the teaching/14-pack samples and cancel while retaining successful totals.
- A new byte-length test exposed nlohmann accepting a raw NUL as end-of-input. The shared source parser now rejects raw NUL bytes so trailing data cannot bypass the declared buffer length.
- Native Debug and Release both pass all 18 CTest suites, including C ABI contracts, concurrent cancellation/lifecycle errors, retained results, 40 repeated create/run/release cycles, resource guards, simulation collision, and CLI/C caller parity. Compilation is warning-clean. The DLL has 13 unmangled exports and confirmed x64 bitness; its imports are system Windows/UCRT libraries.
- All 50 Chrome 154.0.8037.98 integration checks pass, including 13 through the actual compiled Dart adapter: CLI parity across all five commands and the 150x150 irregular 14-pack fortress, malformed/schema/workload errors, cancellation, UI timer responsiveness, int64 preservation, metrics/traces, movement, close while running, repeated creation/destruction, and subdirectory asset discovery. Validation stdout parity normalizes legacy Windows CRLF; generated reports match bytes.
- Flutter analysis, host widget test, and release web build pass. A separate Chrome test clicks both sample buttons and Cancel, confirms retained successful results and closes the page. Wide/narrow UI screenshots were inspected in output/app/phase08-chrome.png and phase08-chrome-narrow.png. The build's generated CupertinoIcons font advisory does not prevent startup; no Cupertino icons are used here.
- Public ownership/lifecycle examples, limits, static-host requirements and reproduction commands are in docs/native_api.md. API 1 / source schema 1 / result format 1 / engine 0.8.0. Phase 09 editor shell and state management remain unchecked.

### 2026-10-12 - Phase 09: desktop editor shell and shared state

- Completed P09.01-P09.10 under the approved Chrome-first scope. Built pale, compact Design/Analyze/Play navigation with an explorer, inspector, output console, status bar, purple/green accents, clear focus, tooltips, keyboard shortcuts and a reduced-motion-aware lantern animation.
- Added one project controller for canonical source, saved content, input/dependency revisions, selection, last valid results and explicit job states. A second serialized validation worker keeps input validation independent of computation. Obsolete results cannot replace newer input; stale output remains visible; failed/cancelled work preserves the previous result. Document replacement locks edits until native validation completes.
- Added reusable Room count, Seed and Threat budget inputs with ranges, units and inline feedback. Lossless source transport preserves int64 values through editing and saving. Added additive C ABI operations 6/7 for normalization and native defaults; schema validation, defaults and canonical serialization remain authoritative C++ code. ABI 1 / source schema 1 / result format 1 / engine 0.9.0.
- Implemented transactional New/Open/Save/Save As, dirty indicators, Save/Discard/Cancel confirmation and browser unload protection. Malformed imports and failed/cancelled writes retain the open project. Chrome file handles are adopted only after validation/write success. File-input/download fallbacks are explicit; requesting a download does not falsely clear dirty state.
- Verification: Flutter analyzer clean, all six controller/widget tests pass, and release web build succeeds. All 18 native CTest suites pass in both Debug and Release. All 50 engine/browser regression checks pass, including 13 through the compiled Dart adapter and CLI parity.
- The Phase 09 Chrome suite passes against the built Flutter app and actual C++ workers: New/Open/Save/Save As, cancelled picker, invalid fields, stale output, unsaved confirmation, rejected writes/imports, exact int64 persistence, real cancellation, download, view switching and compact/high-DPI screenshots. File-picker handles are mocked at the browser boundary; the fallback download is real. Desktop, compact and narrow-inspector screenshots were visually reviewed under ignored output/app.
- Usage and architecture are documented in docs/editor_shell.md. The old Flutter smoke-test entry point delegates to the Phase 09 suite. Canvas shape tools, encounter editing, trace playback and full player controls retain their later-phase checklists; the current map is a selectable fitted preview.

### 2026-10-13 - Phase 10: precise Design canvas and light/dark appearance

- Completed P10.01-P10.13 and the exit check. One logical-pixel camera now drives rendering, tile hit-testing, cursor-centered zoom, panning, fit and coordinate readout. Offscreen layer tiles and room/actor drawing are culled; window resizing preserves the viewport center.
- Added one-tile and configurable square paint/erase brushes with interpolated fast strokes; connected Fill/Clear; rectangle, ellipse and L-shape presets with replace/add/subtract modes and native Apply/Cancel previews. Undo/redo is one entry per gesture, capped by an 8 MiB conservative history budget; source changes keep generated output stale until rerun.
- Added additive C ABI operation DA_EDIT (8), using the shared C++ mask functions and ProjectSession validation. Source JSON, int64 values and locked rooms remain authoritative in C++. Mask/resize conflicts reject atomically; no room is deleted or unlocked. Native diagnostics supply detached/narrow/reservation layers and rejected edit coordinates. Narrow means no fully allowed corridor-width square covers that cell, not a routing guarantee.
- Resize preserves the top-left origin, adds disallowed tiles on expansion, and requires explicit consent before cropping allowed tiles. Core room/margin and settings constraints still apply. Accepted resizes are undoable.
- Added light/dark gray themes with persisted browser preference, muted purple/green accents, contrasting controls, visible active tools and theme-aware canvas, fields, dialogs and panels. Theme and workspace switching retain source, selection and canvas state. Existing reduced-motion behavior remains supported.
- Verification: clean Flutter analyzer, all 11 Flutter controller/camera/history/render/theme/widget tests pass, release web build succeeds, and all 18 native suites pass in Debug and Release. The expanded C ABI contract executes 686 checks, including presets, fill, crop consent, fixed margins, sparse diagnostics and a 512x512 transaction. All 50 browser engine checks (13 via Dart) and the Phase 09 editor regression suite pass.
- The new Chrome Phase 10 suite passes with actual Wasm edits and DPR 2 pointer input: exact edge painting, brush clipping, fast stroke interpolation, pan/zoom hit tests, preview cancellation/application, ellipse/L presets, fill, undo/redo, crop/resize, 512x512 editing, protected-room rejection, save/reopen and theme persistence. File picker handles are mocked; engine commands and serialization are real. Dark/light desktop and compact screenshots were visually reviewed.
- Measurements on this PC: native Release 512x512 edit plus diagnostics 33 ms; test-painter medians approximately 0.30 ms (150x150) / 0.65 ms (512x512), excluding rasterization. Final Chrome stroke plus confirmed save measurements were 315-372 ms including browser/test overhead. Measurements and screenshots are under ignored output/app; these are editing, not generation, performance claims.
- Usage, constraints, API format and reproduction are in docs/design_canvas.md. Engine 0.10.0 / ABI 1 / source schema 1 / result format 1. Phase 11 room/encounter editing and later analysis/gameplay tasks remain in their own checklists.

### 2026-10-13 - Phase 10 usability follow-up

- Generate & solve automatically searches consecutive seeds and publishes the first fully verified C++ pipeline result. The winning seed is saved in canonical source; bounded search, cancellation, terminal errors and obsolete-input rejection preserve prior results. A real Chrome fixture confirms seed 12 exhausts and seed 13 succeeds automatically.
- Removed the separate file/title/run toolbar. Generate/Cancel and the inspector control share the workspace tab ribbon; file actions are in File. Fill and Shapes have labeled menus, brush/blend options are contextual, Add is the default shape mode, and each tool has an inline instruction. Dark tooltip foreground/background contrast is corrected.
- Added native-validated Fix room here / Release room actions and visible instructions. Fixed positions and sizes survive subsequent generation; lock indicators follow current source. This is a focused usability addition, not completion of the broader Phase 11 room/encounter editor.
- Analyze describes and displays allocation totals; Play explicitly describes its map-preview status. Full trace playback and movement remain in their existing later-phase checklists.
- Regression coverage includes automatic retry, winning-seed persistence, wraparound, cancellation/deadline, terminal errors, tooltip contrast, native pin/release validation, real Chrome seed recovery, room pin/regenerate/release, File-menu workflows and additive shape defaults. Native Debug and Release suites, browser engine parity and editor/canvas workflows are checked before delivery.

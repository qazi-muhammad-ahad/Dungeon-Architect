# Module boundaries

`todo.md` is the authoritative engineering phase sequence. The older phase
summary in `plan.md` is a product roadmap, not this implementation checklist.

Phase 02 implements source domain types, checked validation, revision-aware
sessions, snapshot types, and deterministic RNG in the core. The project IO
adapter provides JSON parsing/canonical serialization and transactional file
loading/atomic saving. Phase 03 adds mask presets/paint/fill, component analysis,
fixed-room validation, immutable reservations, terminal selection, and room
transactions to the core. The CLI renders ASCII/JSON diagnostics using these APIs.
Phase 04 implements constrained BSP with immutable room-layout snapshots.
Phase 05 routes full-width corridor footprints, derives floor/walls/doors/spawns,
and validates the actual tile graph before publishing GeometrySnapshot.
Phase 06 implements exact subset DP, deterministic actor placement and independent
allocation validation. Metadata edits reuse immutable geometry. Phase 08 adds the initial authoritative cardinal tile-step simulation boundary; full play/scenario controls remain later phases.

| Module | Owns | Allowed dependencies |
| --- | --- | --- |
| core/domain | Tiles, masks, rooms, packs, settings, snapshots | C++ standard library |
| core/validation | Input and independent result checks | domain |
| core/generation | Mask-aware BSP, reservations, corridors, connectivity | domain, validation, trace |
| core/allocation | Exact subset DP and reconstruction | domain, validation, trace |
| core/simulation | Authoritative movement and collision | domain, validation |
| core/trace | Bounded events and operation metrics | domain |
| adapters/project_io | Versioned JSON and transactional file persistence | core, private nlohmann/json 3.12.0 |
| api | ABI 1, handles/jobs, ownership, polling, cancellation, error translation | core and adapters |
| cli | Arguments, diagnostics, orchestration | core, adapters, private nlohmann/json for analysis output |
| apps/flutter_ui | Integration screen and Dart/JS worker boundary; future editor | Flutter; public engine adapter only |

The core must not include Flutter, Windows UI, JSON, filesystem serialization,
or adapter headers. Keep file format choices outside the algorithms. CLI and API
call the same C++ behavior; Dart must not reimplement generation, allocation,
validation, or movement rules.

The root build produces `dungeon_core` (static), `dungeon_api` (shared), and
`dungeon_cli` (executable), plus `dungeon_project_io` (static adapter). The CLI
uses the public C++ API directly; Phase 08 supplies the reusable C DLL ABI.
Flutter has its own generated Windows runner/build;
integrating and packaging that runner is deferred by the Chrome-first decision.
Chrome is the primary UI target by user decision on 2026-10-11. Native Windows
Flutter is optional and unverified. Browser code cannot load a native DLL;
the implemented Phase 08 browser route is the same C++ core compiled by Emscripten
to WebAssembly, with a JavaScript/Dart adapter and worker for expensive calls.
That adapter is verified in Chrome. Do not
substitute Dart versions of the algorithms or introduce a server implicitly.
Browser persistence must use browser-supported import/export rather than assume
native filesystem access. See `docs/platform_decision.md` for deferred gates.

The API exposes ABI 1 context/job operations and retains the two bootstrap probes.
The result_io adapter owns serializers shared by the CLI and native/Wasm API.
See native_api.md for ownership, cancellation, concurrency and lifecycle contracts.

Fixtures go in `datasets`, correctness tests in `tests`, measurement drivers in
`benchmarks`, licensed visual assets in `assets`, and generated artifacts in
ignored `output` subdirectories. Runtime limits and algorithms remain as planned.

Phase 07 completes CLI orchestration and rendering: run/export reuse the same
C++ generators, router and optimizer, stage serializers and shared atomic writer.
The combined report keeps source replay context, full geometry and allocation;
algorithms do not depend on JSON or filesystem concerns. CLI cancellation uses
SIGINT or an optional external marker checked by engine callbacks. The marker
is not an app backend. Phase 08 implements the C ABI/browser integration without changing those algorithms.

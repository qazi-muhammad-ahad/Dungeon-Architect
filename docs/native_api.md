# Native API and Chrome integration (ABI 1)

Phase 08 keeps one C++ implementation for validation, room generation, routing,
exact allocation, result validation, and the initial tile-step collision operation.
The public boundary is `api/include/dungeon_architect_c.h`. Engine version 0.10.0,
C ABI 1, project schema 1, and result format 1 are separate versions.

Chrome runs the C++ API as WebAssembly in a dedicated Web Worker. The Windows
x64 DLL is built alongside it using the existing portable LLVM-MinGW compiler;
Visual Studio is not required for that DLL. A Flutter Windows runner would need
MSVC/Windows SDK. A Windows DLL is not an iOS/Android binary: those targets need
separate platform builds/adapters and have not been tested. Native Dart FFI,
mobile builds and the native Flutter Windows runner remain deferred by the
user's Chrome-first decision on 2026-10-12. Phase 17 packages the Windows x64
CLI/DLL and Chrome static UI/Wasm with a portable loopback host; see
[portable package instructions](portable-package.md).

## C ABI contract

- Only unmangled `da_*` symbols, `__cdecl` on Windows, fixed-width integer values,
  and caller-owned byte storage cross the ABI. No C++ containers or exceptions.
- Context/job IDs are opaque uint32 tokens. Zero is invalid. A released token is
  invalid and is never reused within that loaded library/worker instance. Tokens
  are local to that instance and must not be persisted or shared across workers.
- `da_context_create(1,1,&context)` negotiates ABI and project schema. Both must
  match exactly. Schema mismatches inside source JSON also produce structured
  `unsupported_schema` reports. `engine_version` in a source document records its
  writer; it is not an instruction to reject compatible older source documents.
- Up to 32 contexts and one outstanding job per context. Release a completed job
  before creating the next. Independent contexts can execute on separate threads.
- `da_job_create` copies 1–16 MiB of raw UTF-8 JSON, so the caller may immediately
  free its input. Lengths exclude a terminating NUL. Embedded raw NUL bytes are
  rejected, including bytes after an otherwise valid document. C callers must
  provide valid readable/writable storage; arbitrary forged addresses cannot be
  made safe by this C interface.
- Operations: `DA_VALIDATE`, `DA_GENERATE` (rooms), `DA_ROUTE` (walkable geometry),
  `DA_OPTIMIZE`, `DA_RUN` (combined report). Optimize currently runs the complete
  pipeline, just like the CLI command. `DA_REALLOCATE` (9) instead reuses the
  same context's last successful routed layout. It returns a pipeline-shaped
  report with `geometry_reused: true`, fresh exact allocation and refreshed room
  metadata. Geometry dependencies are compared by the shared C++ session rules;
  changed settings, mask, room bounds/roles/locks require generation first.
  Failures and cancellations preserve the previous retained snapshot.
  `DA_GENERATE_DUNGEON` (10) generates rooms and corridors without allocation,
  returning a pipeline-shaped result with `allocation: null` and `optimal: false`.
  This remains available when the saved active inventory exceeds the exact cap.
- Phase 09 adds `DA_NORMALIZE` (6), returning native-validated canonical source,
  and `DA_NEW_PROJECT` (7), returning shared native defaults. Their reports include
  `project_json` as a string. These source-only operations never replace retained
  generated output; the ABI remains version 1.
- Phase 10 adds `DA_EDIT` (8) for transactional paint/fill/shape/resize commands,
  plus `fix_room` for fixing/releasing a room's position and size.
  It and normalization/New return native editor diagnostic layers. See
  [Design canvas API and verification](design_canvas.md). Edits preserve retained
  generated output, including when a fixed-room conflict rejects the change.
- Phase 11 extends `DA_EDIT` with `upsert_room` (`room` record), `upsert_pack`
  (`pack` record), `remove_room` and `remove_pack` (`id`). Records use the existing
  source schema. Shared parsing and transactional `ProjectSession::update`
  validate the whole candidate; a geometry change cannot unlock and edit a
  previously locked room in one transaction. Unlock in a separate edit first.
  Inactive packs remain saved catalogue entries. See [room and encounter editing](room_encounter_editor.md).
- The caller selects 0–4096 retained events per stage. Only optimize/run accept
  `DA_DETAILED_TRACE` (also supported by reallocate); the core enforces its small-input limit. Work, time, seed,
  room, budget and corridor settings come from the supplied source document.
- `da_job_execute` runs once and blocks its calling native thread. Use a worker
  thread, not a UI thread. No registry mutex is held during engine execution.
  `da_job_poll` and `da_job_cancel` remain available from another thread.
- `DA_OK` means the boundary call completed; the job can still have an invalid,
  exhausted, unsupported, cancelled or resource-failure domain outcome. Inspect
  the report. ABI/lifecycle errors have fixed status codes in the public header.
  Unexpected exceptions never escape public entry points. Execute finishes the
  job even on exceptions; a constant structured failure report remains readable
  if its normal report allocation failed. A caller's own allocation can still fail.
- Jobs transition pending → running → finished. Execution a second time returns
  `DA_BUSY`. Releasing a running job or a context with any unreleased job returns
  `DA_BUSY`; it does not silently delete live work. Releasing pending/finished
  jobs is allowed. Repeated releases return `DA_INVALID_HANDLE`.
- Cancellation is idempotent for a live handle. Cancelling pending work makes its
  eventual execution return a cancelled report. Cancellation racing successful
  completion is serialized at publication; completed success is not retroactively
  changed into cancellation. Join/await execution, release job, then release context.
- `da_job_poll` exposes a stage, not a percentage or an invented ETA. Stage and
  outcome numeric mappings are documented in the header. Terminal outcome is only
  meaningful after `DA_FINISHED`.
- `da_job_read` returns the report or metrics. Probe with `NULL,0,&required`, expect
  `DA_BUFFER_TOO_SMALL`, allocate `required` bytes in the caller, and call again.
  No partial writes; output has no NUL terminator. Report storage is capped at
  128 MiB. Reads before completion return `DA_NOT_READY`.
- `da_job_trace` pages completed traces with a cursor and batch size 1–128. It
  includes job ID, global event sequence, stage, total, next cursor, dropped count
  and a truncation flag. It does not pretend that retained traces are live events.
- Contexts retain the last successful generation/routing/optimization/run report
  and its immutable source/geometry. Failed/cancelled jobs and successful validation,
  normalization and new-project operations leave it intact.
  `da_context_read` retrieves it after the job has been released.
- `da_context_step` moves at most one cardinal tile on that retained geometry.
  A wall/edge leaves position unchanged; invalid direction/origin is rejected.
  Actors do not block movement. Supply the successful snapshot's job token to
  prevent mixing results. The token remains a snapshot identifier after job release;
  it cannot be used again as a live job handle. Full play controls, time-based
  movement and failure scenarios remain Phases 14/15.

## Ownership and native example

Every created context must have one successful `da_context_release`. Every created
job must have one successful `da_job_release`. Input and output buffers belong to
the caller and use its own allocator/free pair. A too-small-output response does
not transfer any allocation. Never unload the DLL while any call/job is running.

The complete C-only example is `api/examples/caller.c`; it validates return codes
and cleans up on all paths. The root build compiles it as C and links the DLL:

```powershell
.\tools\build-native.ps1 -Configuration Release
.\build\windows-release\bin\dungeon_api_caller.exe datasets/pipeline/teaching.json
# Optional numeric operation: 1 validate, 2 generate, 3 route, 4 optimize, 5 run.
```

The DLL is `build/windows-release/bin/libdungeon_api.dll`. Keep it beside the
caller executable when trying the example. It is Windows x64 and depends on the
system Windows/UCRT libraries, not the compiler's bin directory. A different
architecture must use a matching build. The dynamic C loader test checks bitness
and exports. Native Flutter DLL discovery/FFI is not implemented or claimed.

## Browser build and runtime

The local SDK is pinned to Emscripten 6.0.12 and emsdk registry commit
`35ff8a6d150541276abbc6bae512ca90bcfbe220`. Installation stays in ignored `.tools`
without permanent PATH changes. Provide a real Python executable if `python`
resolves to an unavailable Windows Store alias:

```powershell
.\tools\bootstrap-web.ps1 -Python 'C:\path\to\python.exe'
.\tools\build-web-engine.ps1
cd apps/flutter_ui
flutter pub get
flutter run -d chrome --no-web-resources-cdn
# Or build static release files:
flutter build web --release --no-web-resources-cdn
```

`cmake/wasm.cmake` uses the same core, serializers and C boundary. Compiler exception
support is enabled. Asyncify yields at existing cancellation checkpoints (at most
once per 16 ms when checkpoints are reached), allowing worker message processing.
This is not a hard latency guarantee: parsing, independent validation, serialization
and copying also take time. Native algorithm work/time limits are unchanged.

`build-web-engine.ps1` copies generated JS/Wasm into `web/engine`, where Flutter
includes them in its web build. Rebuild the Flutter web output after changing the
engine or adapter. The generated binaries are ignored; sources/build commands
are tracked. SDK temporary files stay under `build/wasm-release/tmp`.

Serve over HTTP(S), with `.wasm` as `application/wasm` and `.js` as JavaScript.
The worker resolves assets relative to itself; the client uses `document.baseURI`,
including deployments under a subdirectory. No application server, SharedArrayBuffer,
COOP/COEP headers or native DLL is required. Standard static HTTP serving suffices;
`file://` does not. A restrictive CSP must allow the worker and WebAssembly compilation.
Serve the JS/Wasm/adapter from one matching build; avoid stale mixed-version caches.

Missing worker, JS or Wasm assets, incompatible ABI/schema/bitness and startup
timeouts produce recoverable adapter errors. `open()` rejects rather than blocking
the UI. Current Chrome is the verified browser; iOS/Safari/Android are unverified.

## Dart usage and cleanup

```dart
import 'engine/engine.dart';

final engine = Engine();
try {
  await engine.open();
  final result = await engine.run(sourceJson, maxEvents: 256);
  if (result.succeeded) {
    // rawJson preserves exact numeric tokens for export.
    final report = result.document;
    final metrics = await engine.metrics();
    final firstEvents = await engine.trace(cursor: 0, count: 128);
  }
} finally {
  await engine.close();
}
```

Call `cancel()` while the run Future is pending; poll `progress` from a UI timer.
The worker holds all native handles and scratch memory, with matching `_malloc` /
`_free` in `finally` blocks. Only one execution is outstanding per client. Native
work never runs on the Flutter UI thread. JSON decoding/rendering in Flutter is
still UI work and is not advertised as free for arbitrarily large reports.

`close()` requests cancellation, awaits completion and releases context/jobs. A
2-second fallback terminates a stalled worker. Page close terminates its worker
and drops pending requests; no native callback can reference disposed Dart objects.
A closed Engine cannot be reopened; create a new instance. Load failures retain
structured error codes and readable messages. Non-web Dart reports
`unsupported_platform` instead of trying to load a DLL.

JavaScript cannot represent every int64 exactly. The adapter accepts the original
JSON text unchanged and retains canonical output text for export. Decoded web
results expose integers outside ±(2^53−1) as exact decimal strings (use `BigInt`
for arithmetic), not rounded numbers. This relies on current Chrome's JSON reviver
source context; unsupported browsers receive an explicit error for such values.

The Flutter Phase 09 editor provides shared project state, Design/Analyze/Play
navigation, settings, project files, preview, status and cancellation. Its bundled
examples come from `datasets/pipeline/teaching.json` and
`datasets/allocation/standard-14.json`. See [editor shell](editor_shell.md) for
file transactions, revision checks, shortcuts and later-phase boundaries.

## Verification

Native Debug and Release: all 18 CTest suites pass, including C header compilation,
DLL load, lifecycle/null/invalid handle and byte-length cases, concurrent live
cancellation, retained results, 40 create/run/release cycles, context resource guard,
trace paging, tile-step collision and CLI/C caller parity. CLI validation differs
only in platform line endings when compared at the raw stdout byte level.

All 50 browser checks (Chrome 154.0.8037.98), including 13 through Dart, pass. They run the actual generated Wasm in Web Workers
and compile/use the actual Dart adapter. They compare stage and full irregular
150×150/14-pack output with the CLI, exercise cancellation and UI timer responsiveness,
malformed/schema/unsupported/work-limit failures, lossless int64 transfer, metrics,
traces, simulation, close while running, repeated lifecycle and subdirectory assets.
The Flutter release UI suite exercises file transactions, invalid edits, stale
results, view switching, cancellation and responsive sizing. Browser picker handles
are mocked; the engine and download fallback are real. Screenshots go to ignored
`output/app`. See `tests/web/editor_test.cjs`.

```powershell
# From the root (Node + Playwright must be available for browser-only tests):
New-Item -ItemType Directory -Path build/browser-tests -Force | Out-Null
dart compile js tests/web/probe.dart -o build/browser-tests/probe.dart.js
node tests/web/browser_test.cjs
node tests/web/flutter_smoke.cjs
# Node resolves Playwright normally, or through NODE_PATH pointing at an existing
# development installation. No Node runtime is shipped with the app.
```

Implementation references: [Emscripten installation](https://emscripten.org/docs/getting_started/downloads.html),
[Asyncify](https://emscripten.org/docs/porting/asyncify.html),
[C++ exceptions](https://emscripten.org/docs/porting/exceptions.html), and
[Dart JS interop](https://dart.dev/interop/js-interop/usage).

## Analyze metadata and instrumentation

Trace envelope schema 1 and separately labeled stage timing/storage telemetry are
documented in [Analyze and benchmarks](analyze_benchmarks.md). ABI and source
project schema remain unchanged. Report telemetry is nondeterministic; compare
source/geometry/allocation content rather than byte-identical whole reports.

## Temporary scenarios and exploration

Operation 11 (DA_SCENARIO) adds independently retained temporary walkability and full exact allocation reruns. Baseline and scenario movement handles remain distinct. See [Scenarios and exploration](scenarios_play.md) for the JSON contract, lifetime, controls and timing semantics.

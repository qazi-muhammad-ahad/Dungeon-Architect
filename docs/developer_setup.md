# Developer setup and verification

Checked on 2026-10-11 (Asia/Karachi), in
`E:\Uni\sem5\DAA\Dungeon Architect`. No applicable `AGENTS.md` was found in
either working directory or its checked parent directories. The original
planning/reference files remain in `C:\Users\ahadm\Downloads\DAA CCP`.
The entire app, Git repository, tools, and build outputs are in the E: folder.

## Selected setup

| Component | Version / result |
| --- | --- |
| OS | Windows 11 25H2, build 26200.9457, x64 |
| Native compiler | LLVM-MinGW 20261006 UCRT x64; Clang 23.1.3 |
| Native linker | LLD 23.1.3 |
| Native build tool | GNU Make 4.4.1 from the same portable bundle |
| CMake / CTest | 3.31.10 |
| C++ standard | C++17; `std::string_view` and structured bindings verified |
| Flutter | 3.47.5 stable, framework 6a19cca564 |
| Dart | 3.13.4 |
| Chrome | 154.0.8037.98 |
| Git | 2.55.0.windows.5 |
| Primary UI target | Flutter web / Chrome |
| Microsoft Windows SDK / MSVC | Not installed; optional native Flutter runner unverified |
| Android SDK | Not found by Flutter doctor; unnecessary for Chrome |

The portable compiler contains the MinGW Windows headers/import libraries needed
by this CLI/DLL. It does not provide the MSVC toolchain that Flutter's optional
Windows runner expects. Chrome does not need that runner.

## Reproduce the native checks

Phases 02-07 add the project/geometry APIs, IO adapter, BSP, routing and allocation. The same
commands now run sixteen CTest suites: C++17, core linkage, core project rules,
core geometry, BSP, routing, persistence, project CLI, geometry CLI, generation
CLI, routing CLI, exact allocation core/CLI, combined pipeline/export, live Windows CLI cancellation, and DLL loading.
Debug and Release both pass. The initial phase-01 three-test
results below are retained as toolchain history.

The preferred one-command workflow is `tools/build-native.ps1`. Its equivalent
explicit commands from the root, after `tools/bootstrap-native.ps1`, are:

```powershell
$cmake = '.\.tools\cmake-3.31.10-windows-x86_64\bin\cmake.exe'
$ctest = '.\.tools\cmake-3.31.10-windows-x86_64\bin\ctest.exe'
& $cmake --preset windows-debug
& $cmake --build --preset debug --parallel
& $ctest --preset debug
& $cmake --preset windows-release
& $cmake --build --preset release --parallel
& $ctest --preset release
.\build\windows-release\bin\dungeon_cli.exe --version
```

The initial native verification used the same CMake 3.31.10 executable from its
official Python wheel at `.tools/cmake/cmake/data/bin`. The setup script also
installs the official portable ZIP at the path above. Both remain ignored.

Both configurations build separate `dungeon_core`, `dungeon_api`, and
`dungeon_cli` targets. All three CTest checks pass in both configurations:

1. `toolchain.cxx17`: runs a C++17 language and library probe.
2. `core.smoke`: calls a real linked core symbol and checks its build metadata.
3. `api.load_library`: C caller loads the DLL dynamically, resolves the two
   unmangled exports, checks the bootstrap ABI and 64-bit architecture, and unloads.

Release checks use explicit failures, not `assert`, so `NDEBUG` cannot disable
them. Compiler warnings are enabled per target. The portable toolchain links
its C++ runtime statically; system Windows/UCRT libraries remain dependencies.

Inspect DLL architecture and exports:

```powershell
& '.\.tools\llvm-mingw-20261006-ucrt-x86_64\bin\llvm-readobj.exe' `
  --file-headers --coff-exports --coff-imports `
  '.\build\windows-release\bin\libdungeon_api.dll'
```

Observed: `COFF-x86-64`, 64-bit address size, exports
`da_bootstrap_abi_version` and `da_pointer_bits`.

## Flutter and browser workflow

```powershell
cd apps/flutter_ui
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
flutter run -d chrome --release --no-web-resources-cdn
```

Analyzer and host widget smoke test pass. The release web build succeeds.
`flutter run -d chrome --release --no-web-resources-cdn --web-hostname 127.0.0.1
--web-port 5318` successfully launches the installed Chrome. The same served
release was visually inspected in the app browser, including readable headings.
`--no-web-resources-cdn` bundles renderer resources with the app rather than
depending on a renderer CDN at startup. The bootstrap screen only demonstrates
Flutter startup; the C++ engine is not connected to Chrome yet.

An extra `flutter test --platform chrome` attempt stalled during test loading
and was stopped; it is not recorded as a passing automated browser test. The
host widget test and actual browser launch are separate checks. Revisit this
test-harness issue before adding browser integration tests.

## Existing MinGW investigation

`C:\MinGW\bin\g++.exe --version` failed inside the agent sandbox with an
Illegal System DLL Relocation error. The same executable ran successfully
outside the sandbox and reported GCC 6.3.0, target `mingw32` (32-bit).
Its initial CLI/core/DLL bootstrap build and two linkage checks passed.
However, the focused C++17 probe failed because `<string_view>` is missing.
That is a separate, demonstrated compiler/library limitation.

The existing compiler was not removed or replaced. The approved modern portable
compiler is selected explicitly by the project's CMake toolchain file. No
machine-wide PATH, Flutter version, or VS Code settings were changed.

## Installations versus project dependencies

- Portable CMake and LLVM-MinGW are development tools, downloaded into `.tools`
  with pinned versions and SHA-256 checks in `tools/bootstrap-native.ps1`.
- Flutter/Dart and Chrome were already installed. Flutter's normal package
  resolution updates its caches and creates the tracked app lockfile.
- nlohmann/json 3.12.0 (MIT) is vendored privately for the IO adapter and CLI output. No external
  native test framework is needed; normal builds require no dependency download.
- Visual Studio was not installed, per user preference.
- Emscripten is a future browser-engine build prerequisite, not installed yet.

See `platform_decision.md` for the explicit change from mandatory Windows runner
verification to Chrome verification. Native Flutter packaging remains optional.

## Phases 02-07 CLI verification

From the root after a build:

```powershell
.\build\windows-release\bin\dungeon_cli.exe inspect datasets/teaching/phase02-project.json
.\build\windows-release\bin\dungeon_cli.exe validate datasets/teaching/phase02-project.json --for-allocation --json
.\build\windows-release\bin\dungeon_cli.exe validate datasets/teaching/phase02-project.json --for-generation --json
.\build\windows-release\bin\dungeon_cli.exe mask-info datasets/teaching/phase02-project.json
.\build\windows-release\bin\dungeon_cli.exe generate datasets/generation/l-shape.json
.\build\windows-release\bin\dungeon_cli.exe route datasets/routing/hole-detour-width2.json
```

CTest covers checked geometry/arithmetic, canonical ordering, MT19937 mapping,
transactional edits/loads, stale-result preservation, strict JSON input, exact
64-bit values, UTF-8, missing/locked paths, atomic replacement failure, no-clobber
saves, and real CLI exit/output contracts. Test checks remain active in Release.
The JSON Schema and teaching/CLI-generated documents were also independently
checked with Python jsonschema 4.23.0 in ignored `.tools/schema-check`; this is
an optional artifact-verification tool, not a native build/runtime dependency.

See `project_format.md`, `cli.md`, and `determinism.md` for API/format contracts.
Geometry checks include all 512 possible 3 × 3 masks against an independent
reachability oracle, lock-preserving edits, immutable reservations, terminal
selection, and invalid geometry fixtures. See `geometry.md` for the rules.
Generation tests cover 64 seed/shape combinations, fixed geometry crossed by
abstract splits, bounded rollback, cancellation, and immutable publication.
Routing tests independently scan full corridor footprints and flood actual floor,
check turns/holes/intersections, enforce doors/spawn lanes/capacities, and retain
old geometry after rejected publication. CLI coverage includes a 150 × 150,
16-room case with corridor width 2. Successful Debug/Release JSON is compared.
Flutter was not changed or retested during Phases 02-07 because the implementation
and verification run through the C++ CLI first.

Phase 06 adds an independent exhaustive-assignment oracle over 400 seeded tiny
cases, deterministic reconstruction/placement checks, numeric/resource boundaries,
allocation-only metadata edits, stale jobs and failed-result preservation.
The CLI fixtures cover known optima and a 150x150 14-active-pack pipeline.

Phase 07 verification: all 16 suites pass in Debug and Release. The pipeline
suite covers combined and stage exports, raw stdout/file byte equality, replay,
source/alias protection, no-clobber replacement, preview/override parsing and
failure preservation. The Windows cancellation suite launches a real hidden
CLI subprocess, creates its cancellation marker while it runs, and verifies
exit 6, no partial result and unchanged source/previous export. Atomic writer
coverage includes Unicode paths and locked-target rejection.

Eight independent combined CLI cases match Debug/Release bytes, with successful
embedded-source replays reproducing the complete report. The new fixture files
pass JSON Schema checks. Independent exported-layer traversal and actor/total
checks validate the 150x150 irregular fortress: 16 rooms, 15 corridors, 3,614
connected floor cells, score 74, threat 24 and 20 actors. The optional Python
verification uses the existing local jsonschema package, not a build dependency.


## Phase 08 current verification (2026-10-12)

All 18 native suites pass in Debug and Release; the two additions are api.contract
and api.cli_parity. Engine version is 0.8.0. The native DLL is Windows x64 with 13
unmangled da_* exports, and the standalone C caller executes all engine workflows.
Older bootstrap-only descriptions above are historical.

Chrome now loads the C++ engine through Emscripten 6.0.12 WebAssembly in a dedicated
worker; native Dart FFI is deferred. Build with `tools/build-web-engine.ps1` before
Flutter run/build. On a fresh checkout first use `tools/bootstrap-web.ps1 -Python
'C:\path\to\python.exe'`. Both scripts keep the SDK/cache/temp outputs within this
project; they do not persist machine environment changes.

Flutter analyze, host widget test, and release web build pass. Actual Chrome tests
cover CLI/Wasm parity, cancellation, Dart interop, UI responsiveness, cleanup and
browser load failures; the separate release-UI smoke test runs both samples and
Cancel through Flutter's semantic buttons. The historical Chrome test-harness
stall above is bypassed by the explicit Playwright/compiled-Dart harness, not
reported as a passing `flutter test --platform chrome` run.

Reproduction, ownership and deployment notes: [native/browser API](native_api.md).
Playwright is a development-only browser test dependency resolved from an existing
Node installation through NODE_PATH on this machine. Generated test JavaScript
and UI verification screenshots stay under ignored build/output folders.

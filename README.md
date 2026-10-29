# Dungeon Architect

**[Open the live app](https://dungeon-architect-daa.vercel.app)** in desktop Chrome.
Public source: [qazi-muhammad-ahad/Dungeon-Architect](https://github.com/qazi-muhammad-ahad/Dungeon-Architect).
For browser hosting, reproducible builds, and traffic protection, see
[deployment](docs/deployment.md) and [security](SECURITY.md).

C++ engine and Flutter editor for constrained dungeon generation and exact
encounter allocation. **Phases 00-17 are implemented (Chrome-first):** the build environment,
module structure, C++ domain/validation API, transactional session updates, and
versioned project persistence, mask editing/connectivity, fixed-room validation,
immutable reservations, constrained BSP rooms, width-aware corridors, verified
walkable floor, spawn capacities, exact encounter allocation/actor placement, a complete CLI with atomic full-result exports, and a versioned C API with Chrome WebAssembly/worker integration.
The Flutter editor has Design/Analyze/Play navigation, light and dark gray themes,
project files, validated settings, a precise Design canvas and revision-safe
run/cancel controls. Paint, fill, preview shapes, undo/redo, pan/zoom, resize and
inspect mask diagnostics. See [editor workflow](docs/editor_shell.md) and
[canvas tools and themes](docs/design_canvas.md). Room tools, runtime generation
settings, the encounter catalogue and allocation-only optimization are described
in [room and encounter editing](docs/room_encounter_editor.md). Analyze includes
bounded real-event playback, linked BSP/DP inspection and reproducible benchmark
charts/export; see [Analyze and benchmarks](docs/analyze_benchmarks.md). Temporary
failure scenarios and exploration-only Play (native collision, encounter
inspection and exit completion) are documented in [scenarios and Play](docs/scenarios_play.md).
Combat and enemy AI are outside this scope.

Chrome is the primary UI target, following the platform decision on 2026-10-11.
VS Code is supported as the editor; Visual Studio is not needed for this setup.
Chrome uses the same C++ engine through WebAssembly. The portable Windows x64
package includes a local Chrome host plus the CLI, DLL, C API example, samples
and runtime notices. Native Flutter Windows/Dart FFI and mobile builds remain
deferred under the agreed [platform decision](docs/platform_decision.md).

## Portable local use

Download the portable Windows x64 ZIP from [GitHub Releases](https://github.com/qazi-muhammad-ahad/Dungeon-Architect/releases), extract the whole folder, and run
**Start Dungeon Architect.cmd**. Open the printed loopback URL in Chrome and keep
the console open while using the app; Ctrl+C stops it. No development checkout,
Flutter SDK, Node or Python is required to run the package. Windows system/UCRT
libraries and Chrome are prerequisites. Do not open its HTML with `file://`.

The same archive contains `bin/dungeon_cli.exe`, `bin/libdungeon_api.dll`, a
standalone C example and import library, ready-to-open samples and SHA-256 file
inventory. See [portable launch, controls and troubleshooting](docs/portable-package.md).

## Use the C++ project API through the CLI

From the repository root, after building the native targets:

```powershell
.\build\windows-debug\bin\dungeon_cli.exe new output/app/my-project.json --name 'My dungeon' --seed 42
.\build\windows-debug\bin\dungeon_cli.exe inspect datasets/teaching/phase02-project.json
.\build\windows-debug\bin\dungeon_cli.exe validate datasets/teaching/phase02-project.json --for-allocation --json
.\build\windows-debug\bin\dungeon_cli.exe validate datasets/teaching/phase02-project.json --for-generation --json
.\build\windows-debug\bin\dungeon_cli.exe mask-info datasets/teaching/phase02-project.json
.\build\windows-debug\bin\dungeon_cli.exe generate datasets/generation/l-shape.json
.\build\windows-debug\bin\dungeon_cli.exe route datasets/routing/hole-detour-width2.json
.\build\windows-debug\bin\dungeon_cli.exe route datasets/generation/standard-150.json --json --events 0
.\build\windows-debug\bin\dungeon_cli.exe optimize datasets/allocation/teaching.json
.\build\windows-debug\bin\dungeon_cli.exe optimize datasets/allocation/standard-14.json --json --events 0
.\build\windows-debug\bin\dungeon_cli.exe run datasets/pipeline/teaching.json --metrics
.\build\windows-debug\bin\dungeon_cli.exe export datasets/pipeline/irregular-fortress.json output/app/fortress-result.json --events 0 --no-map
.\build\windows-debug\bin\dungeon_cli.exe save datasets/teaching/phase02-project.json output/app/teaching-copy.json
```

`save` validates and writes canonical JSON atomically. Existing destinations
require `--force`; invalid input cannot overwrite an existing valid file.
`inspect --json` prints the canonical source document. `validate --json` prints
structured diagnostics. Ordinary document validation allows large catalogues;
`--for-allocation` additionally checks the 14-active-pack limit.

The public C++ headers are `core/include/dungeon_architect/project.h`,
`core/include/dungeon_architect/geometry.h`,
`core/include/dungeon_architect/generation.h`, `core/include/dungeon_architect/routing.h`,
`core/include/dungeon_architect/allocation.h`, and
`adapters/project_io/include/dungeon_architect/project_io.h`. The versioned C ABI is `api/include/dungeon_architect_c.h`; see [native API and browser integration](docs/native_api.md).
See [project format and API](docs/project_format.md), [CLI contract](docs/cli.md),
[mask/fixed-room rules](docs/geometry.md), and [determinism rules](docs/determinism.md).
The CLI guide includes a complete create-mask/add-lock/unlock/move walkthrough.
`generate` returns an exact-count room layout and abstract connection requirements.
`route` generates rooms and builds a connected dungeon with doors, walls, entrance/
exit markers, safe movement lanes, spawn cells and capacities. Neither command
changes the input file. See [BSP generation](docs/generation.md) and
[corridor routing](docs/routing.md) for algorithms, limits, and failure behavior.
`optimize` runs generation/routing followed by exact subset DP, reconstructs room
assignments and legal actor positions, and reports score/threat and unused packs.
Try `--budget 2` on the teaching fixture to change the optimum. See
[exact allocation](docs/allocation.md) for the API, proof, limits and tests.
`run` combines full geometry and allocation in one report. `export` writes it
atomically, including effective source settings for replay. Existing results
require `--force`; unsuccessful runs preserve them. Use `--preview X Y W H` to
inspect another map region, `--no-map` for summaries, and `--metrics` for counters.
See [complete CLI workflow](docs/cli.md) and [result format](docs/result_format.md).

## Run the browser app

For a new PC, start with [clone, setup, and Codex handoff](docs/new-device.md).
Build the engine first from the root after installing the native and web tools:

```powershell
.\tools\build-web-engine.ps1
```

On a fresh checkout, run `tools/bootstrap-web.ps1` once; see [setup](docs/native_api.md). With the existing Flutter SDK on PATH:

```powershell
cd apps/flutter_ui
flutter pub get
flutter run -d chrome --no-web-resources-cdn
```

Use `q` in the Flutter terminal to stop it. In VS Code, open the repository root
and run the **Flutter: Run Chrome** task, or open `apps/flutter_ui` and select
Chrome as the Flutter device.

## Build and test the C++ targets

The native targets use a portable LLVM-MinGW x64 compiler and CMake, stored
under ignored `.tools`. On this PC they are already installed. On a fresh clone:

```powershell
.\tools\bootstrap-native.ps1
```

Build and run all native checks with one command, from the repository root:

```powershell
.\tools\build-native.ps1 -Configuration Debug
.\tools\build-native.ps1 -Configuration Release
```

The script configures CMake, builds the CLI/core/DLL and probes, runs CTest,
and launches the CLI. No system PATH changes are needed. VS Code's default
build task runs the Debug command.

```powershell
.\build\windows-debug\bin\dungeon_cli.exe --help
.\build\windows-release\bin\dungeon_cli.exe --version
```

For direct configure/build/test commands and measured tool versions, see
[developer setup](docs/developer_setup.md).

## Flutter checks

From `apps/flutter_ui`:

```powershell
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --csp
```

Serve `build/web` over HTTP to preview the release; do not open its HTML with
`file://`. Flutter's `run -d chrome` command handles serving during development.

## Layout and status

- `core`: shared C++ domain, validation, revisions, snapshot types, and seeded RNG.
- `api`, `cli`, `adapters`: versioned C boundary, complete CLI, shared JSON/file/result adapters.
- `apps/flutter_ui`: Chrome engine integration screen, JS worker and Dart adapter; optional Windows runner source.
- `tests`, `datasets`, `benchmarks`: checks, future fixtures, measurement drivers.
- `assets`, `output`: asset provenance and ignored generated artifacts.
- `docs/reference`: local copies of course PDFs, excluded from the public repository.
- `todo.md`: authoritative phase sequence and verification log.

Read [architecture](docs/architecture.md), [dependencies](docs/dependencies.md),
and the [Chrome platform decision](docs/platform_decision.md) before extending
the project. Chrome uses the shared C API compiled to WebAssembly in a worker; the browser does not load the Windows DLL.

## Git and Fork

The `Development` branch contains the implemented phases for continued development;
`main` is the production branch. Both use the public GitHub repository above.
Open your clone in Fork with **File > Open Repository**.
Generated tools/builds, credentials, course handouts, and personal documents are
ignored. Source, lockfiles, fixtures, and project documentation are versioned.

# Dungeon Architect portable package

This package targets Windows x64 with Chrome and local HTTP. It contains the
Flutter static browser UI, the authoritative C++ engine compiled to WebAssembly,
and a separate native CLI/C DLL. Native Flutter Windows and Dart FFI remain
deferred under the agreed Chrome platform decision. There is no installer,
account, upload service or external runtime download in the launcher.

## Extract and launch

1. Extract the entire archive into a writable folder. Keep its directory layout.
   Windows x64, the Windows UCRT/system libraries and an installed Chrome browser
   are prerequisites. No Flutter, CMake, Node, Python or C++ SDK is needed to run it.
2. Double-click **Start Dungeon Architect.cmd**. The console prints
   `http://127.0.0.1:4173/` and opens the default browser. If that browser is not
   Chrome, paste the printed address into Chrome.
3. Keep the console open while using the app. Save source projects before
   stopping. Press Ctrl+C in that console to close the local host, then close
   the browser tab. No service, registry entry, PATH edit or firewall rule is
   installed. Delete the extracted folder to remove the application; keep your
   separately saved project files.

Do not open `web/index.html` with `file://`. The worker, Wasm and browser file
features require HTTP. The host binds only `127.0.0.1`; it is not a LAN host.
Only the packaged `web/` directory is served, with read-only GET/HEAD requests.
Samples, native binaries, saved projects and API headers are outside that root.

From PowerShell, using any current directory:

```powershell
& 'D:\Apps\Dungeon Architect\dungeon_launcher.exe' --port 0 --no-browser
```

`--port 0` selects a free port and prints the actual URL; `--port 4174` selects
a fixed alternative. `--no-browser` suppresses browser launch. `--help` lists
options. The default fixed port keeps the browser origin stable between runs.
Browser permissions/storage may differ when changing ports. A second host on
an occupied port fails clearly and leaves the first running.

The local host applies the production CSP and security restrictions, with
HTTPS-only HSTS and `upgrade-insecure-requests` omitted for loopback HTTP.
It uses `Cache-Control: no-store`, correct Wasm/font MIME types, Host validation,
bounded headers/timeouts, and rejects traversal, alternate streams and reparse
points. It provides no application API, CORS access or network proxy. Treat
the extracted package as trusted local application files; do not modify them
while the host runs.

## First project and controls

Use **Open** to select `samples/teaching.json` for a small complete example or
`samples/irregular-fortress.json` for an irregular mask. **Generate & solve**
creates rooms/corridors and an exact encounter assignment (shown as **Run** on
narrow screens). On wider screens, **Generate only** creates geometry
independently; **Optimize** reruns allocation on current valid geometry after
catalogue/budget changes.

For a blank start, open `samples/blank.json`: it has an empty allowed mask,
no explicit rooms and no packs. Paint allowed building area in Design or apply
a shape, set room sizes/count and generate. The app's **New** command is an
alternative starting project with native defaults. Mask cells permit building;
they are not already carved floor. Canvas pan/zoom/fit, brush/fill/shape tools
and fixed-room controls are described in `docs/design_canvas.md`.

Edit room roles, locks, tags/capacity and active catalogue packs in the inspector.
Submit numeric fields with Enter where indicated. Source revisions invalidate
dependent results. **Cancel** requests cooperative native cancellation; failures
retain the last valid result, with stale output labeled until recomputed.

Analyze replays real retained native trace events; detailed traces are enabled
automatically within the teaching-size limit. Benchmarks runs controlled fixtures in a separate
worker and displays measured charts; failed/cancelled points are excluded from
timing aggregates. Temporary scenario blocks/capacity/budget changes require
**Apply scenario**; **Restore baseline** discards them.

In Play, **Start exploration**, click the map to focus it and use WASD/arrows.
E inspects nearby encounters; Escape pauses. Focus loss, workspace changes and
dialogs also pause. Restart returns to the entrance. Reach the exit to complete
exploration. Encounters are markers: combat and enemy AI are outside scope.

## Save and project format

**Save/Save as** stores source JSON using Chrome's local file picker. Choose a
writable location outside the archive if you want to replace/remove the package
later. **Open** reloads that JSON. Dirty changes prompt before replacement;
failed or cancelled file operations preserve the current project.

Project schema 1 stores source settings, allowed mask, explicit rooms and pack
catalogue. It does not store generated output, temporary scenarios, player
position or benchmark history; reopen and generate again. Unknown fields,
unsupported schema versions and malformed JSON fail with diagnostics. Input is
UTF-8, limited to 16 MiB. `docs/schema/project-v1.schema.json` and
`docs/project_format.md` describe the schema; the C++ parser is authoritative.

## Native CLI and standalone C API

From the package root:

```powershell
.\bin\dungeon_cli.exe --version
.\bin\dungeon_cli.exe validate samples/teaching.json --json
.\bin\dungeon_cli.exe run samples/teaching.json --json
.\bin\dungeon_api_caller.exe samples/teaching.json 5
```

The DLL stays beside the prebuilt caller in `bin/`; Windows resolves it from
the executable directory independently of the shell's current directory.
`docs/cli.md` documents commands and exit codes. `api/include/dungeon_architect_c.h`
is the public C ABI 1 header; `api/example.c` is a standalone C-only integration
that runs a job and releases its buffers/job/context. Numeric operations 1–5
are validate, generate rooms, route, optimize and combined run. Inspect the
job's domain outcome in addition to ABI status codes.

To compile the example yourself, use a compatible Windows x64 C compiler
(development only; not required to run the prebuilt example):

```powershell
clang --target=x86_64-w64-mingw32 -Iapi/include api/example.c api/lib/libdungeon_api.dll.a -o bin/example.exe
.\bin\example.exe samples/teaching.json 5
```

Keep your executable beside `libdungeon_api.dll`, or implement explicit safe DLL
loading in your own application. Match architecture, header ABI and import
library. Never unload during active calls. Buffer lengths exclude a NUL;
ownership/cancellation/trace/scenario details are in `docs/native_api.md`.

## Versions and limits

The manifest records actual CLI version and all native imports. This release
uses engine 0.10.0, ABI 1/project schema 1/result format 1, Flutter 3.47.5,
Dart 3.13.4, Emscripten 6.0.12 and LLVM-MinGW 20261006 (Clang/LLD 23.1.3,
UCRT x64). Build verification uses CMake/CTest 3.31.10. Runtime components and
fonts have notices in `licenses/` and `web/assets/NOTICES`; no overall project
license grant has been invented.

Exact allocation supports at most 14 active packs; larger saved catalogues can
still be edited and generate geometry, but must deactivate packs before solving.
DP tables have a 64 MiB guard and jobs obey configured work/time limits.
Detailed traces support at most six packs/eight rooms and retain bounded events;
truncation is reported. No heuristic fallback is used. Performance depends on
the input/device; timing observations are not guarantees. Mobile/native Flutter
Windows, offline `file://`, combat and network multiplayer are unverified or
outside this release's scope. The browser and native binaries share algorithms
but use different platform builds.

## Troubleshooting and package verification

- **Port occupied:** stop the other launcher, or use `--port 0`/another port.
- **Browser did not open:** use the printed URL in Chrome. Keep the console open.
- **Missing web/index.html / blank page:** fully extract the archive, preserving
  `web/` beside the launcher. Confirm the URL uses HTTP and the printed port.
  Refresh or clear old site data after replacing a package.
- **DLL missing / wrong architecture:** keep all `bin/` files together, use
  Windows x64 and do not copy DLLs from SDK/system folders as a workaround.
- **Save denied/cancelled:** choose a writable local destination; retain the
  current tab until a save succeeds.
- **Generation/solver error:** inspect diagnostics, allowed area, room locks,
  margins, active pack count and work limits. The retained map may be stale.
- **Blank sample rejected for generation:** paint allowed area or apply a shape first.

`package-manifest.json` lists SHA-256 and byte size for every packaged file except
itself. Verify it after copying/extracting; it is an integrity inventory, not a
cryptographic publisher signature. No SDK/compiler/browser is included. The
release checklist records actual validation separately from these instructions.

Maintainers use PowerShell 7 to assemble already-built outputs with
`tools/package-portable.ps1`,
passing `-NativeBuildDirectory`, `-WebDirectory`, `-FlutterRoot`, and a new
`-Destination`. It refuses existing destinations and unreviewed native imports.
Run the independent package tests and relocated Chrome workflow before archiving.

## Verified release environment (2026-10-29)

The portable package was built and tested on Windows x64 (Windows NT
10.0.26200.0), Chrome 156.0.8078.73 and PowerShell 7.6.5 for assembly.
Fresh native Release output passes all 20 CTest suites; Flutter analysis is
clean and all 54 Flutter tests pass. Wasm and the CSP/self-hosted Flutter web
release were rebuilt in separate fresh output directories and passed the
artifact verifier.

A relocated package in a path containing spaces passes manifest hashes,
native import closure, samples/save/replay, standalone C ABI, unsupported
inventory and cancellation checks with only Windows System32 on PATH and an
independent working directory. The shipped C source/header/import library were
also recompiled and executed separately with the colocated DLL. Chrome tests
exercise actual packaged traces, BSP/DP inspection, charts/export, scenarios,
Play movement/actor inspection/exit, save/reopen, invalid input and cancellation.
File-picker handles are mocked at the browser boundary; engine jobs, file JSON,
UI interactions, launcher and HTTP assets are real. All runtime requests remain
on the packaged origin. These results do not certify other Windows/Chrome
versions, mobile or a native Flutter Windows runner.

The launcher/CLI/DLL are unsigned. The SHA-256 inventory verifies file integrity,
not publisher identity. Chrome and Windows system libraries are not included.

The shipped empty-mask blank sample was also authored through the real canvas
Rectangle/Replace/Apply controls, generated, saved, reopened exactly and
regenerated. The UI refuses a combined solve above 14 active packs while
Generate only still builds geometry.

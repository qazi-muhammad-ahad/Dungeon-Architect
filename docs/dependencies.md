# Dependencies and licenses

Keep dependency choices outside the algorithm modules. The current native core
uses only the C++ standard library. CTest drives small standalone checks; no
third-party native test framework is needed. Phase 02 vendors nlohmann/json
3.12.0 privately in the project persistence adapter. Phase 03 also uses it for
CLI analysis output; builds do not fetch it and the core remains dependency-free.

| Dependency/tool | Pinned or observed version | Purpose | License/source |
| --- | --- | --- | --- |
| nlohmann/json | 3.12.0 | Private JSON persistence and CLI analysis output | MIT; third_party/nlohmann/LICENSE.MIT |
| Flutter / flutter_test | SDK 3.47.5 | UI and widget test | BSD-3-Clause; SDK LICENSE |
| Dart | 3.13.4, bundled with Flutter | UI language/tooling | BSD-3-Clause; SDK LICENSE |
| flutter_lints | 6.0.0 | Development-time analysis | BSD-3-Clause; pub package LICENSE |
| lints | 6.1.0, transitive | Analysis rules | BSD-3-Clause; pub package LICENSE |
| CMake / CTest | 3.31.10 | Native configure/build/test | BSD-3-Clause; Kitware distribution Copyright.txt |
| LLVM-MinGW | 20261006 UCRT x64 | Portable C++17 Windows toolchain | Composite distribution; upstream component licenses |
| Clang / LLD / libc++ | 23.1.3 | Compile, link, C++ runtime | Apache-2.0 with LLVM exceptions; bundle LICENSE.TXT |
| GNU Make | 4.4.1 | Development build tool | GPL-3.0-or-later; bundle share/make/COPYING |

The generated `apps/flutter_ui/pubspec.lock` records all direct and transitive
package versions and hashes. Preserve it. The Flutter SDK supplies its test
dependencies; there are no additional UI runtime packages beyond Flutter.

Tool archives are not app assets and are excluded from Git. Preserve component
license notices when packaging runtimes in Phase 17. LLVM-MinGW also includes
MinGW-w64 headers/runtime components with their own notices; the distribution
license is not a blanket license for every component. No overall project license
has been chosen for the user.

Supplied academic PDFs are preserved in `docs/reference` with their existing
ownership. Bootstrap Flutter icons are generated framework template assets;
replace them with tracked, licensed dungeon art in the later visual phase.

Sources:
- [nlohmann/json 3.12.0](https://github.com/nlohmann/json/releases/tag/v3.12.0) (header SHA-256/provenance in `third_party/nlohmann/README.md`)
- [LLVM-MinGW release 20261006](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261006)
- [CMake release 3.31.10](https://github.com/Kitware/CMake/releases/tag/v3.31.10)
- [Flutter license](https://github.com/flutter/flutter/blob/master/LICENSE)
- [flutter_lints](https://pub.dev/packages/flutter_lints/versions/6.0.0)


Phase 08 adds Emscripten 6.0.12 as a development tool, installed under `.tools/emsdk`
with its bundled Node 24.19.0 and Python 3.13.3. Emscripten is MIT / University of
Illinois-NCSA (see the SDK LICENSE); LLVM components have their own notices.
The emsdk registry commit is pinned in tools/bootstrap-web.ps1. Generated Wasm
includes its runtime glue; preserve the SDK license notices when packaging in
Phase 17. No new Flutter runtime package was added: Dart's built-in JS interop is
used. Playwright is used only for optional browser development tests, not shipped
as an application dependency. JSON serialization is shared by the result_io
adapter and remains outside the C++ core.

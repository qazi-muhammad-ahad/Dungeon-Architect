# Chrome-first platform decision - 2026-10-11

The user confirmed prior Flutter work used Chrome/Android, declined a Visual
Studio installation, and approved Chrome as the application target. VS Code
remains the editor. The user also approved a portable modern C++ compiler inside
the ignored project `.tools` directory, without replacing existing MinGW or
changing system PATH.

For Phases 00/01 the gate is a native C++17 CLI and DLL build/load plus a Flutter
Chrome smoke app. This explicitly replaces the original mandatory Flutter
Windows startup gate; the optional Windows runner stays available as source.
Windows-only checklist items are recorded as deferred rather than falsely tested.

The native CLI and DLL share the C++ engine. The browser shell currently has no
engine integration. The proposed later integration is Emscripten/WebAssembly
and a browser worker, preserving one authoritative C++ implementation and no
server. Emscripten is not installed during these phases. Confirm the detailed
browser integration contract when starting Phase 08.

Later gates that must be adapted for Chrome:

- Phase 08: build C++ for WebAssembly, define JS/Dart interop, worker cancellation,
  memory ownership, deployment headers/assets, and CLI/browser parity tests.
- Phases 02/09: keep schema/validation in C++; browser import/export and storage
  require an adapter instead of unrestricted native filesystem operations.
- Phase 17: package static web assets with the engine Wasm artifact; test in
  Chrome from a local HTTP server and on the chosen host. Do not claim opening
  `index.html` using `file://` is a supported launch workflow.

Algorithms, exactness, workloads, and exploration-only scope remain unchanged.
The generated Windows runner is optional, unverified support scaffolding.

References:
- [Flutter web setup](https://docs.flutter.dev/platform-integration/web/setup)
- [Emscripten C/C++ to WebAssembly](https://emscripten.org/docs/introducing_emscripten/about_emscripten.html)


## Phase 08 confirmation - 2026-10-12

The user reaffirmed Chrome for development/testing and keeping the Windows DLL
alongside the shared C++ API, with final Windows packaging later. The DLL already
builds with portable LLVM-MinGW; Visual Studio is required for the optional Flutter
Windows runner, not for this DLL. Windows DLLs cannot run directly on iOS/Android.
Those targets require separate compiled libraries/adapters and remain unverified.

The browser integration proposed above is now implemented: Emscripten 6.0.12,
ABI 1, JS Web Worker with Asyncify cancellation checkpoints, Dart JS interop,
relative static assets, explicit ownership/cleanup and CLI/Wasm parity checks.
No SharedArrayBuffer or special cross-origin-isolation headers are required.
Native Dart FFI is deferred, not marked tested. Phase 08's adjusted checklist and
exit gate are recorded in todo.md. See [API usage](native_api.md).

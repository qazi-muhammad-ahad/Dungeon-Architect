# Dungeon Architect Chrome editor

Phase 09 adds a pale desktop editor with Design/Analyze/Play navigation, a project
explorer, inspector, map preview, output console and subtle purple/green accents.
New/Open/Save/Save As, validated settings and revision-safe worker jobs share one
controller. The authoritative C++ engine runs as WebAssembly in Web Workers.
See [workflow, shortcuts and file behavior](../../docs/editor_shell.md).

Phase 10 adds precise canvas painting, fill and shape previews, bounded undo/redo,
camera navigation, protected resizing and native diagnostics. The sun/moon button
switches light/dark gray themes and remembers the choice. See
[Design canvas](../../docs/design_canvas.md).

From the repository root, build the engine before running Flutter:

```powershell
.\tools\build-web-engine.ps1
cd apps/flutter_ui
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --no-web-resources-cdn
```

For a fresh checkout, install the pinned project-local Emscripten SDK with
`tools/bootstrap-web.ps1` first. See `docs/native_api.md` for complete setup,
C/Dart examples, lifecycle/ownership, exact numeric JSON handling and browser tests.

Visual Studio is not required for Chrome or the portable-toolchain Windows DLL.
Native Dart FFI, the optional Windows runner and mobile builds remain deferred.

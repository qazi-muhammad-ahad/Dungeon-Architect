# Editor shell (Phases 09–10)

The Chrome editor uses a pale, dense workspace with an explorer, Design/Analyze/Play
tabs, an inspector, an output console and a status bar. Purple identifies actions
and selection; green identifies verified output. A slow lantern animation respects
the operating system's reduced-motion preference. Panels collapse at narrower
widths; the inspector remains available from the toolbar. Phase 10 adds a persisted
dark gray theme, selectable with the sun/moon toolbar button.

## Workflow

Start with **File → Open** or a bundled example, adjust Room count
and Threat budget, then **Generate & solve** on the Design/Analyze/Play ribbon.
New, Open, Save and Save As live in File; its dot indicates unsaved changes.
The preview and totals come from the
C++ result. Selecting a room in the explorer or preview exposes its properties.
View switching and resizing retain the project, selection and result.

Generate automatically tries consecutive uint32 seeds, beginning with the displayed
seed (wrapping at its maximum), until the first complete, verified native result.
Only search-exhausted outcomes are retried; invalid input and resource/unsupported
errors stop immediately. The search is cancellable and bounded by the project's
`max_time_ms` across all candidates and a 1,000-candidate safety limit. Browser
timer duration is capped at signed int32 milliseconds. An impossible constraint
set cannot be promised a solution; exhaustion keeps the last good result and
suggests reducing room count or widening the allowed area. The successful seed
is native-normalized into the project for reproducible saving. Failed/cancelled
searches do not change the source seed, and input revisions reject obsolete results.
Retry orchestration is in the controller; every candidate uses the unchanged
shared C++ pipeline through `DA_RUN`.

To keep a room, generate, choose **Select room**, click a room or its Explorer
entry, and choose **Fix room here** near the top of the inspector. This fixes both
position and size; subsequent generation arranges other rooms around it. Use
**Release room** to allow regeneration. Fixing requires a current verified result.
The source edit is validated in C++ and marks the previous result stale.

Analyze shows allocation totals, bounded native trace playback, BSP/DP inspection,
optional map overlays and isolated benchmarks. Its temporary failure scenarios can
block floor tiles or change allocation constraints without changing the saved
baseline. Apply changes to rerun native reachability and exact allocation, or
restore the baseline. Stale scenario output suppresses assignments until reapplied.

Play starts an immutable session from the current verified baseline or scenario.
WASD/arrows move using native collision, E inspects nearby static encounters, and
Escape pauses. Focus loss, dialogs and workspace changes pause movement; Resume
returns keyboard focus to the canvas. Reach the exit to complete exploration.

The shared canvas supports painting, fill, shape previews, undo/redo, resizing
and camera navigation; see [Design canvas](design_canvas.md). Encounter editing
is available in the catalogue. Pixel motifs and recovery/accessibility details
are documented in [Visual polish](visual_polish.md).

| Shortcut | Action |
| --- | --- |
| Ctrl+Alt+N | New project |
| Ctrl+O | Open project |
| Ctrl+S | Save |
| Ctrl+Shift+S | Save As |
| F5 | Generate and solve |
| Escape | Request cancellation |

## Source and jobs

One `ProjectController` owns source data, canonical JSON, saved revision content,
input/dependency revisions, selection and active-job state. Explicit states cover
idle, running, cancelling, successful, stale, invalid and failed. Settings are
editable during computation; only a result matching the current input revision
can become current. Previous successful output remains visible with a stale label.
Cancellation and failed jobs preserve it. A completed obsolete job is discarded.

Two C++ Web Workers keep computation and serialized source validation off the UI
thread. The additive ABI operations `DA_NORMALIZE` (6) and `DA_NEW_PROJECT` (7)
use the shared native parser, validator, defaults and serializer. They return a
`project_json` string and never replace retained generated output. Domain rules
and algorithms remain in C++. Dart performs numeric input feedback and lossless
JSON transport, preserving int64 values through unrelated edits and saving.

## Files and recovery

New/Open replacement is transactional: the source, result and adopted file handle
change only after native validation succeeds. Editing is locked during replacement.
Malformed files, unsupported schemas and rejected writes leave the open project
available. New documents and examples begin unsaved. New/Open prompt to Save,
Discard or Cancel when edits exist. Browser close/reload uses its native unsaved
changes warning. Invalid numeric drafts cannot be saved or run.

Chrome on localhost or HTTPS uses the File System Access picker. Save reuses an
adopted handle; Save As always requests a destination. A successful stream close
marks the captured canonical source saved. Source files contain no generated
result. Imports are UTF-8 and capped at 16 MiB, matching the API boundary.

Where the native browser file API is unavailable, Open uses a file input and Save
requests a JSON download. A download request cannot prove that a file was saved,
so it does not clear dirty state or automatically approve replacing an unsaved
document. The status message explains this; the user may explicitly discard.

## Verification

Run `flutter analyze`, `flutter test` and `flutter build web --release
--no-web-resources-cdn` in `apps/flutter_ui`. From the repository root, run
`node tests/web/editor_test.cjs` with Playwright available. It drives the built
Flutter application and actual C++ workers in Chrome. File-picker handles are
mocked at the browser boundary for deterministic success/cancel/write-failure
checks; the fallback download is a real browser download. Screenshots are written
to ignored `output/app`. `tests/web/flutter_smoke.cjs` delegates to this suite.

Controller tests exercise obsolete results, failed replacement, cancellation,
invalid edits, replacement locking and int64 transport. Widget tests cover
navigation, selection retention, compact widths and high-DPI sizing. The separate
50-check `tests/web/browser_test.cjs` verifies the engine/Dart boundary against
the native CLI; native Debug/Release builds run all 18 CTest suites.

## Analyze playback and benchmarks

Analyze now includes bounded real-event playback, linked BSP/map diagnostics, a
tiny-state DP inspector, native metrics and isolated reproducible benchmark
batches. See [Analyze and benchmarks](analyze_benchmarks.md) for controls, limits,
measurement domains and recorded target-workload evidence. Play remains a map
preview; exploration controls are a later phase.

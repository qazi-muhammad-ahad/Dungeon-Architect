# Design canvas and appearance — Phase 10

The Design workspace edits the **allowed building area**. Generated floor and
walls are separate overlays; editing the mask keeps the previous result visible
and marks it stale. Generate again to refresh it. The sun/moon button at the top
switches between pale and dark gray editor themes. The preference is stored in
this browser, independently of project files; blocked browser storage falls back
to the light theme without preventing use.

## Drawing and navigation

- Select a brush tool: Paint or Erase, with square brushes of 1, 2, 3, 5, 8, 16 or
  32 tiles. Brushes clip to the canvas edge. Fast pointer moves interpolate every
  intervening tile. One complete drag is one history entry.
- The **Fill** menu contains Fill and Clear, operating on the four-connected region containing the clicked
  tile. They do not change disconnected regions of the same color.
- Choose Rectangle, Ellipse or L-shape from **Shapes** and drag its bounding rectangle. Select
  Add (the default), Subtract or Replace in the contextual shape mode menu. Brush
  size is shown only for Paint/Erase, and shape blending only for shape tools.
  The options row explains the active tool. The C++ engine produces the
  exact preview; **Apply shape** commits it and **Cancel shape** discards it.
  Save, Run and other source edits are disabled while that preview is pending.
- Wheel zoom anchors the tile under the cursor. Middle drag, Space+drag (with
  canvas focus), or the Pan tool moves the camera. Shift+wheel scrolls the canvas.
  Trackpad pan is supported. Fit and +/- buttons are available in all views;
  press F with canvas focus to fit. The footer reports tile coordinates and
  logical pixels per tile.
- Undo/Redo buttons restore whole gestures. Ctrl+Z and Ctrl+Shift+Z/Ctrl+Y work
  with canvas focus. History covers mask content and dimensions, preserving
  unrelated project settings, and has an 8 MiB conservative storage budget.
  Oldest entries are evicted; a new edit clears redo. New/Open starts fresh history.

Camera rendering and hit testing share one logical-pixel transform. Zoom, pan,
selection and history stay in the shared canvas when switching workspace tabs or
themes. Resizing the window retains the world point at the viewport center.
The toolbar wraps at compact widths so every tool remains available.

## Validation, diagnostics and resizing

All edits are transactional native operations. An edit crossing any source room
or its required margin is rejected; locks are never cleared implicitly. The
status/output panel gives the native diagnostic and recovery instruction.

The Layers menu independently toggles generated floor, walls, fixed-room
reservations and diagnostics. Allowed area remains visible for drawing. Green
reservation overlays show mandatory room footprints plus margins. Amber marks
components detached from the largest allowed component; red marks allowed cells
that cannot be covered by any fully allowed corridor-width square. This is a
clearance diagnostic, not a guarantee that the routing algorithm can connect all
rooms. Native rejection coordinates are outlined red when diagnostics are on.

Resize supports 1–512 tiles per axis, subject to normal project validation.
The top-left origin stays fixed, and expansion adds disallowed cells. Shrinking
that removes allowed content requires **Allow cropping tiles outside the new
bounds**. Even with consent, a source room or margin outside the new bounds
rejects the resize. Requested room counts and size ranges must also remain valid.
An accepted resize is undoable.

## C++ boundary

ABI 1 adds `DA_EDIT` (8) with input
`{"project_json":"<canonical source JSON>","command":{...}}`. The nested source
is parsed by the strict shared project parser, preserving exact int64 tokens.
Commands are `paint` (tiles and allowed), `fill` (x/y and allowed), `shape`
(shape, mode, x/y/width/height), `resize` (columns/rows/allow_crop), and `fix_room`
(`fixed` boolean and `room` with id/name/bounds from a current generated result).
Fixing adds or updates a source room through the core room APIs, setting position
and size locks. Releasing clears both flags on the existing source record without
changing its bounds. Existing source metadata and lock validation are preserved.
Paint/fill/presets reuse existing core APIs. Resize and blending commit through
`ProjectSession`, so core geometry and lock checks run before publication.

Successful edit, normalization and New reports include `project_json` plus
`editor_analysis` (component count and row strings for detached, narrow and
reservation layers). These operations do not replace a retained generated result.
The frontend publishes only an edit validated against its current revision.

## Verification and measurements

`tests/api/contract_test.cpp` covers native shape parity, fill, rejected strokes,
crop consent, expansion, protected margins/rooms, diagnostic layers and a
512×512 transaction. `apps/flutter_ui/test/canvas_test.dart` covers transform
round-trips at 1/1.25/2/3 DPI, zoom anchors, boundaries, stroke continuity, memory
limits, offscreen culling and theme/state preservation.

`node tests/web/canvas_test.cjs` drives the release Flutter app and real Wasm
workers in Chrome at DPR 2. It verifies edge painting, brush sizing, fast strokes,
pan/zoom hit tests, previews, ellipse/L-shape, fill, undo/redo, resize, source
save/reopen, room protection, persisted themes and compact layouts. File picker
handles are mocked; editor operations and serialization are real.

On this PC, the Release native 512×512 edit plus diagnostics took 33 ms in the
contract run. Test-painter medians were approximately 0.30 ms at 150×150 and
0.65 ms at 512×512, excluding GPU rasterization. Five Chrome 512×512 strokes plus
confirmed source saves measured 315–372 ms end to end, including browser/test
overhead. These are editing measurements, not generation-performance claims.
Latest browser measurements and screenshots are under ignored `output/app`.


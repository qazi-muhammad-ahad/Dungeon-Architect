# Visual polish and recovery

The map uses original code-native pixel motifs in
`apps/flutter_ui/lib/editor/pixel_palette.dart`. No downloaded sprites, textures,
image generation, or external art packages are used. These source-drawn motifs
are authored for this repository; they introduce no third-party art dependency
or attribution requirement. This checkout has no project-wide license file, so
this provenance record does not grant a new redistribution license. The bundled symbol font retains
its existing license in `apps/flutter_ui/assets/fonts/`.

## Palette and layers

The dungeon palette uses charcoal void, cold stone floors, slate brick walls and
wood-and-iron arched doors. Floor seams, moss and occasional wall torches are
deterministic decoration. Original 16-pixel sprites depict a hooded adventurer,
archer, armored guard, horned ogre, fire spirit and skeleton. Entrance arches
and exit stairs use distinct silhouettes. Custom packs use a skeleton unless
their descriptive name identifies one of the supported archetypes.

Sprites are selected using the accepted snapshot's pack metadata. Their drawing
does not change spawn positions, movement, encounter counts or inspection.
Overlapping player/encounter positions retain a small encounter sprite beside
the player. At Fit, sprites retain a minimum readable footprint; zoom reveals
the full pixel detail. Room outlines and screen-sized labels stay legible.

Tile fills and pixel motifs disable antialiasing and snap shared edges to device
pixels. Camera position, selection hit testing and native geometry are unchanged.
Design supports 0.25–64 logical pixels per tile; masonry detail appears at 8 or
more, while smaller scales intentionally show solid tiles. Play follows the
player at 22 logical pixels per tile. Overview fit scales can be fractional:
snapping may vary a motif's pixel width by one device pixel, and subpixel tiles
cannot retain all detail. UI and map-label font sizes are independent of world
zoom. No claim of equal-width pixel detail at arbitrary fractional zoom is made.

## Navigation and recovery

The desktop browser layout targets 800×600 and larger, including browser/device
scaling. The explorer/inspector collapse at narrower widths; Project inspector
opens the properties in a scrollable sheet. Canvas tools wrap and panels scroll.
Long room names truncate in lists while the inspector exposes their properties.
The catalogue scrolls; exact optimization still requires at most 14 active packs,
regardless of catalogue length. Catalogue rows are currently built eagerly;
arbitrarily large catalogues are not a responsiveness guarantee.

Keyboard Tab navigation follows visible controls. Numeric fields retain their
labels after typing, and native validation errors explain rejected values.
Play's focus outline identifies the keyboard canvas; WASD/arrows move, E
inspects and Escape pauses. Focus loss, dialogs and view changes pause movement.
Start/Resume returns focus to the canvas. Status messages use text, symbols and
live semantics; the status tooltip exposes the full truncated message.

Empty Play explains Generate & solve and Start exploration. Loading and
cancellation keep the last verified map visible. A stale badge means inputs
changed: generate again before exploring. Disconnected scenario exits explain
why Play cannot start; restore the baseline or reopen a route and apply.

Source edits, invalid drafts and unapplied canvas previews all count as unsaved
for the browser close/reload warning. Apply or cancel a canvas preview before
saving/replacing a document or switching workspace. Workspace changes stay on
the current canvas until its draft is applied or cancelled, preserving previews.
Native validation failures and cancelled operations
retain the open source and last good result. New/Open offers Save, Discard or
Cancel for source changes; failed or cancelled saves do not approve replacement.
Download fallback cannot prove a file was saved and deliberately keeps the dirty
warning. Browser warnings depend on browser policy/user interaction; closing the
browser does not create an autosave. Save explicitly to retain the project.

## Verification boundary

Phase 16 regression coverage is in `tests/core/robustness_test.cpp`,
`apps/flutter_ui/test/phase16_test.dart` and `tests/web/phase16_test.cjs`.
The current coordination handoff records actual commands and results; the
presence of these tests does not itself establish that a run passed. Native
Windows packaging and OS-native window-close behavior belong to Phase 17.

## Completed validation (2026-10-29)

- Native Release: all 20 suites pass. The new robustness suite exercises 24
  randomized small projects, 288 malformed mutations and 192 malformed random
  byte inputs, plus cancellation, stale handles and retained snapshots.
- Flutter: all 54 tests pass and the analyzer is clean. Regression cases cover
  stale-layer painting after resize, unapplied-preview dirty/workspace guards,
  undo/redo, failure/older-save preservation and disposal during pending work.
- The release web build uses `--release --no-web-resources-cdn --csp`;
  `node tools/verify-deployment.mjs` passes.
- Real Chrome checks pass at 1600x1000, 1024x768 and 800x600 (DPR 1), plus
  1280x800 at DPR 1.25 and 2. Valid 250-byte names and 100 saved packs were
  exercised, with real scrolling and visual confirmation of the final entry.
  Keyboard Tab/Enter, numeric recovery, Play start and cancellation with retained
  output pass. At 800x600, Hide output then Fit canvas expands the usable map.
- Repeated edit/generate/optimize/move/fail/cancel/close and active/stalled-close
  checks create and terminate 14 workers with empty pending maps. File-write
  failure stages preserve dirtiness/handles; 100 file-listener lifecycles pass.
  This verifies owned-resource cleanup, not zero heap drift or a formal memory
  leak proof. Stalled close was observed at about two seconds on this run.

The existing canvas history remains bounded to 8 MiB. Native Windows packaging,
OS-native close behavior, arbitrary catalogue sizes and formal assistive-device
certification were not added by this browser-focused phase.

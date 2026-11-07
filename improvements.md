# Dungeon Architect — UX improvement plan

Status: implementation complete and locally validated. Some edge cases were not rerun in Chrome.
Updated: 2026-11-07.

This document tracks the requested encounter visibility fix, seed randomization,
and simpler algorithm tracing. Implementation is now authorized. The initial findings
below come from source inspection; the reported deployed-app encounter problem
has not been reproduced in this session. Existing release evidence is historical,
not validation of these proposed changes.

## 1. Encounters: make the result visible and understandable

### What the current code does

- A new project contains no encounter packs. `make_default_project()` initializes
  the allowed mask, while `Project.packs` starts empty. Generating rooms does not
  invent encounter inventory.
- **Generate only** creates geometry and asks the user to Optimize afterward.
  **Generate & solve** also runs exact encounter allocation. **Optimize** allocates
  against the current geometry without regenerating it.
- The solver considers active packs, eligible reachable rooms, capacity, room
  dimensions, roles, tags, and the threat budget. An empty allocation can be a
  valid optimum; a successful solve does not guarantee encounters. Unused active
  packs already have reason codes such as `oversized`,
  `no_compatible_eligible_room`, and `unselected_by_optimum`. The latter alone does
  not prove a specific budget or compatibility explanation.
- Design/Analyze and Play draw `allocation.actors`. Analyze's `assignments`
  overlay defaults on. The current encounter motif is an amber cross, not a dot.
- Play encounters are static, nonblocking markers. Moving within two tiles and
  pressing **E** opens encounter information; combat is not implemented.
- Packs, assignments, and markers are different counts: a selected pack creates
  one actor marker per slot. Do not label all three counts as “encounters.”

The empty default inventory and geometry-only action are concrete explanations
for missing markers. They do not establish what happened in the user's particular
run. Marker contrast, scale, stale results, and snapshot propagation still need
to be checked with a populated project.

### Planned experience

1. Make the primary generation action clearly include encounters. Keep geometry
   generation and allocation-only actions accessible with plain labels such as
   **Generate layout only** and **Place encounters**. Avoid the ambiguous compact
   label “Run”; preserve accessible full names at narrow widths.
2. Show a small result summary: active packs, placed packs, placed markers, and
   unused packs. Distinguish “not allocated yet” from “allocated: 0 markers.”
3. Give actionable empty states:
   - No custom packs: automatically use built-in template packs and show
     “Using template packs. Add your own packs to replace them.”
   - Custom packs exist but none are active: prompt the user to activate their
     inventory; do not substitute templates for deliberately disabled packs.
   - Geometry only: offer Place encounters.
   - Valid empty optimum: expose actual unused reasons and relevant constraints;
     do not invent a diagnosis or silently change inputs to force placement.
   - Stale/failed/canceled result: clearly identify the retained previous result.
4. Keep encounter markers conspicuous in both editor and Play: yellow/amber,
   contrasting outline, a consistent legend, and a usable appearance at Fit and
   common zoom levels. Prefer a simple dot/badge or a clearly legible existing
   motif after visual comparison. Identify a hidden encounter overlay explicitly.
5. Supply development-derived template packs automatically when there are no
   custom packs, including first launch. Custom packs take precedence over the
   entire template catalogue; do not mix templates into custom inventory.
6. Explain the **E** inspection interaction in Play and show marker counts before
   exploration. Empty maps may remain explorable, with an explicit explanation.

### Template fallback rules (user addition)

Use the existing development/teaching packs as the basis for a small bundled
starter catalogue. The teaching asset at
`apps/flutter_ui/assets/phase08-teaching.json` includes Archer, Guard pair, Ogre
crowd, and Lava spirit. Some deliberately require particular tags/roles or test
capacity constraints, so do not assume copying that fixture unchanged will make
encounters appear on ordinary generated maps. Derive starter-friendly versions
from these packs, validate their defaults, and keep the teaching fixture intact.
Load pack definitions only, not the example's mask, rooms, seed, or other settings.

| Project inventory | Effective inventory used for allocation |
| --- | --- |
| First launch/new project with no custom packs | Built-in template packs |
| Opened project with no custom packs | Built-in template packs, clearly identified |
| One or more custom packs | Custom catalogue only; normal active flags apply |
| Custom packs all inactive, incompatible, or over budget | Custom catalogue only; explain the empty result |
| Last custom pack removed | Return to template fallback; invalidate the prior allocation |

Determine fallback from the presence of custom records, not whether a solve
placed anything. Treat existing saved packs as custom unless explicit template
provenance says otherwise; never guess provenance from names or IDs. Keep bundled
templates separate from custom records so displaying them does not accidentally
disable the fallback. Editing/copying a template into custom inventory must be
explicit and then follows the custom-precedence rule.

Show whether **Template packs** or **Custom packs** are in use and list the actual
effective pack values. Resolve this inventory before invoking the authoritative
C++ solver so validation, active-pack limits, trace, actor metadata, and Play all
use the same definitions. Do not fabricate markers in the renderer. Pin/persist
the effective template definitions and provenance/version needed for deterministic
save/open and replay; a later bundled-template update must not silently change a
saved run. Final schema/API placement is an implementation decision, with backward
compatibility required.

Templates should produce visible encounters on a known-feasible default setup,
but still obey capacity, compatibility, budget, and exact optimization. They do
not guarantee placement for every user configuration. **Generate layout only**
still skips allocation. No new combat behavior is implied.

This requirement supersedes the initial proposal to leave no-pack projects empty
and merely link to an example. Intentional zero encounters remain possible with
an existing custom catalogue whose packs are all inactive.

### Implementation checklist and acceptance

- [x] Reproduce new-project → Generate & solve → Play; record inventory,
      assignment, actor, and rendered-marker counts.
- [x] Repeat with the teaching example and a small known-feasible pack setup;
      trace data through C++ output, bridge payload, editor painter, and Play
      snapshot. Fix the actual failing layer if markers are present but invisible.
- [x] Implement action labels, count summary, empty states, legend, and marker
      visibility changes supported by that reproduction.
- [x] Bundle a starter catalogue derived from development packs and implement
      automatic fallback plus visible template/custom inventory provenance.
- [x] Verify first launch and empty-project open generate template encounters on
      a feasible setup without requiring manual pack entry or opening an example.
- [x] Verify adding/importing the first custom pack replaces template usage;
      removing the last restores it. Never merge templates into custom inventory.
- [x] Verify inactive/incompatible custom packs do not trigger fallback; saved
      legacy packs remain custom, and template IDs cannot collide with custom IDs.
- [x] Verify template values/provenance survive save/open and reproduction across
      template-version changes, with matching editor, trace, and Play metadata.
- [x] Verify no packs, all inactive, geometry only, budget-constrained selection,
      incompatible/oversized packs, and valid nonempty allocation.
- [x] Verify actor count equals selected packs' total slots, all actors render in
      Design/Play, and nearby **E** inspection identifies the correct pack/room.
- [ ] Check scenario application, restart, stale edits, cancellation, and failure
      do not mix actor data from different accepted snapshots.
- [x] Inspect real rendered output at Fit/zoom and narrow/wide widths, including
      overlapping player/marker positions; do not rely on DOM semantics alone.

Relevant source: `core/src/domain/project.cpp`,
`core/include/dungeon_architect/project.h`,
`core/src/allocation/subset_dp.cpp`,
`apps/flutter_ui/lib/editor/project_controller.dart`,
`apps/flutter_ui/lib/editor/record_editors.dart`,
`apps/flutter_ui/lib/editor/preview.dart`,
`apps/flutter_ui/lib/editor/pixel_palette.dart`,
`apps/flutter_ui/lib/editor/play_controller.dart`,
`apps/flutter_ui/lib/editor/play_workspace.dart`, and
`apps/flutter_ui/lib/main.dart`.

## 2. Randomize seed without changing specifications

### Current behavior

The seed is manually editable in the unsigned 32-bit range, 0–4294967295. The
controller searches successive candidate seeds when necessary and saves the
first successful one. There is no adjacent randomize action. A requested starting
seed and the accepted seed can therefore differ.

### Planned experience

Place **Randomize seed** beside the editable Seed field, with a dice/shuffle icon
as a secondary cue. One click chooses a valid seed different from the current
value and updates the visible field through the existing settings transaction.
The action changes the seed only; the user then invokes generation normally.
Helper text: “Choose a new seed, then generate with the same settings.”

Preserve mask, room settings, fixed rooms, packs, budget, limits, and all other
specifications. Mark the previous result stale, pause its trace, and invalidate
Play as with a manual seed edit. Preserve the last valid map until a new result
succeeds. Disable the action during conflicting operations or unapplied canvas
drafts; keep pending invalid field edits intact and explain any disabled state.

Show the accepted seed after generation, and explain candidate searching when it
differs from the requested seed. Different seeds can still produce identical
geometry under constraints; do not promise a unique map on every click.

- [x] Add the button, tooltip/accessibility label, and safe controller action.
- [x] Verify generated values stay in range and differ from the prior seed,
      including boundary values 0 and 4294967295.
- [x] Verify only the seed changes in source settings; repeated clicks, manual
      entry, save/open, stale-state handling, and failure recovery remain sound.
- [ ] Verify identical accepted seed plus identical inputs reproduce the result;
      candidate search and its displayed accepted seed remain truthful.
- [ ] Check keyboard operation and compact layout without clipping.

Relevant source: `apps/flutter_ui/lib/main.dart` and
`apps/flutter_ui/lib/editor/project_controller.dart`. Frontend randomness chooses
an input seed only; C++ remains authoritative for dungeon generation.

## 3. One sequential Trace interface

### Current behavior

Analyze offers five separate views: Trace, BSP tree, DP inspector, Metrics, and
Benchmarks. Trace has playback, stepping, restart, speed, seeking, and raw JSON.
The native pipeline already groups events into generation, routing, and
allocation. Replay uses an immutable bounded event collection without rerunning
the solver. Raw event JSON currently serves as much of the step explanation.

### Planned experience

Use **Trace** as the primary analysis destination, with one algorithm selector:

| Selection | Sequential explanation |
| --- | --- |
| All algorithms (default) | Room generation → corridor routing → encounter allocation |
| Room generation (BSP) | Partition decisions, preserved fixed rooms, placements and recorded backtracking |
| Corridor routing | Recorded route-search/connection decisions and resulting corridors |
| Encounter allocation (exact subset DP) | Candidate/state decisions when recorded, room summaries, reconstruction and placement |

This is a selector for replaying recorded work, not a promise to execute each
algorithm independently. Allocation requires accepted geometry. An allocation-only
run has no fresh generation/routing trace; show those stages as unavailable for
that run rather than combining unrelated histories.

Proposed layout, adapting to available space:

```text
Trace   [All algorithms v]
[Play/Pause] [Back] [Next] [Restart]   [Speed: 1x v]   Step 12 / 80
[---------------- timeline ----------------]
Stage: Room generation · Dividing a region
What happened, why the recorded decision matters, and what changed
[Map highlight]                    [Relevant tree / DP details]
[Advanced details]
```

- Give each step a short human-readable explanation, relevant values, and a map
  highlight. Keep raw JSON behind Advanced details.
- Default to **1 event per second** (1×), with **2×** for two events per second.
  Offer 0.5×, 1×, 2×, 5×, 10×, 50×, and 100× presets plus a custom positive
  multiplier. Display both the multiplier and target events/second so speed has
  an unambiguous meaning. Reject zero, negative, nonfinite, or malformed custom
  values inline; do not silently clamp a requested speed. At rates beyond render
  capacity, show that playback is batching visual updates rather than promising
  that every event receives its own frame.
- Make the trace visually polished and instructional: a clear stage header,
  consistent typography, restrained transitions, a synchronized timeline, and a
  compact explanation of the current decision. Use labels/shapes as well as color
  for candidates, acceptance, rejection, and completion; maintain readable contrast.
- Animate each algorithm using available recorded evidence:
  - BSP: highlight the region under consideration, animate the recorded split,
    and reveal accepted rooms; distinguish preserved rooms and recorded retries.
  - Routing: emphasize the current room pair and reveal recorded route segments.
    Animate a search frontier only if the trace actually records it; otherwise
    show a connection-level explanation without inventing search steps.
  - Exact DP: highlight the current room, candidate pack subset, feasibility
    result, and recorded state/predecessor transition; animate reconstruction
    into room assignments and markers where the data supports that mapping.
- Keep transitions within each event's playback interval. At high speed, shorten
  or suppress transitions and process ordered events in batches per frame; never
  queue a long animation for every event. Keep Pause, seeking, and speed changes
  responsive, cancel superseded transitions, and derive the display from the
  selected recorded event rather than accumulated animation state. Batched visual
  presentation must not discard captured events: all remain accessible by stepping
  or seeking when paused. Intermediate frames may be coalesced; say so clearly.
- Respect reduced-motion preferences and offer a reduced-animation presentation
  with the same labels, highlights, and explanations. Animation must help explain
  the algorithms without obscuring values or changing computation/replay results.
- Integrate BSP tree and DP information contextually beside the relevant step,
  with expandable detail instead of requiring separate top-level views.
- Move metrics and benchmarks into a secondary advanced area. Preserve these
  existing capabilities without making them part of the ordinary trace flow.
- All algorithms follows the actual recorded stage/event order and clearly marks
  stage transitions. Single-stage selection filters the same immutable run.
- Switching selection pauses playback and resets the filtered cursor to its start.
  Preserve original event indices for correct seeking/highlights; counters refer
  to the selected sequence. Back/Next/Restart operate consistently on it.
- Show “Replay of completed run,” the accepted seed, and a clear stale-input badge.
  Keep retained earlier traces explicitly identified; never imply they describe
  newer ungenerated inputs.
- Keep bounded capture and honest summary/truncation notices. Detailed DP
  candidates currently require at most 6 active packs and 8 eligible rooms;
  playback holds at most 4096 events, with additional native per-stage sampling.
  “All algorithms” means all available stages, not every internal operation.
- Use only recorded decisions and supported derived explanations. Do not fabricate
  missing search iterations or animate final geometry as if it were an exact
  historical intermediate state. Label final-map context where reconstruction of
  a full intermediate map is not supported by the recorded events.

### Implementation checklist and acceptance

- [x] Map available event kinds to clear descriptions and supported highlights;
      identify any missing teaching data before expanding native trace capture.
- [x] Implement stage filtering, index mapping, Back/Next, and unified controls.
- [x] Consolidate contextual BSP/DP detail and simplify default overlays/copy.
- [x] Implement 1-event/second default, 2× and requested 5×/10×/50×/100× presets,
      custom multiplier entry, and elapsed-time-based scheduling. The current
      timer's 16 ms minimum and 60-events/second clamp cannot implement 100×
      correctly; replace that constraint with bounded per-frame event batching.
- [x] Implement the algorithm-specific animations, stage transitions, readable
      decision cards, consistent visual states, and reduced-motion behavior.
- [x] Verify All and each individual stage preserve recorded ordering and use the
      same run; filtered replay never regenerates or modifies the dungeon.
- [ ] Verify empty traces, geometry-only and allocation-only runs, failed runs,
      truncated/summary traces, stale inputs, and changing selection mid-playback.
- [x] Verify playback, pause, speed, seek, restart, and backwards inspection agree
      on the selected event and its highlight.
- [x] Verify pacing at 1×/2×, all requested high-speed presets, a custom fractional
      speed, invalid speed input, mid-animation speed changes, and pause/seek at
      100×. Test ordering and final cursor with a controlled clock; inspect actual
      browser responsiveness separately. Avoid unbounded background-tab catch-up.
- [x] Visually review BSP, routing, and DP at slow speed and high speed: labels
      must remain legible, explanation/highlight must agree, and there must be no
      overlapping animation backlog or invented intermediate algorithm states.
- [x] Review readability with the small teaching example and a larger summarized
      run, including keyboard access and responsive layout.

Relevant source: `apps/flutter_ui/lib/editor/analysis_panel.dart`,
`apps/flutter_ui/lib/editor/analysis_controller.dart`,
`apps/flutter_ui/lib/editor/project_controller.dart`,
`apps/flutter_ui/lib/editor/preview.dart`, and `api/src/dungeon_architect_c.cpp`.

## Delivery order and completion gates

| Priority | Work | Exit condition |
| --- | --- | --- |
| 1 | Encounter reproduction and UX correction | A feasible populated project visibly places inspectable encounters; empty results explain why |
| 2 | Randomize seed | One action changes only the seed while preserving normal validation and generation behavior |
| 3 | Unified Trace | One readable sequential flow supports all three stages individually or together |
| 4 | Integrated verification | End-to-end generation, encounter inspection, seed variation, and trace replay pass together |

During later implementation, update these checkboxes and the local handoff after
each milestone. Keep each item incomplete until its acceptance checks pass.
Use focused controller/widget tests for state changes, native tests if engine
behavior changes, then Flutter analysis/tests and the required CSP web build.
Verify real browser rendering and workflows using the resulting artifact. Record
commands/results and any checks not run. Deployment is a separate later action;
if requested, verify the exact release is READY and test the public app before
claiming it is live.

Preserve exact subset DP, BSP generation, C++ authority, deterministic replay,
existing workload limits, static self-hosted deployment, and last-valid-result
recovery. Automatic template fallback is explicitly included by the user's
addition. Combat, new algorithms, servers, and unrelated UI redesign are outside
this plan.

Validation: native Release 20/20, expanded API contract passed, Wasm built, Flutter analysis clean and 60/60 tests passed, CSP release and static artifact verifier passed. Chrome integrated and focused visual workflows passed, including 8 default markers in Design and Play, seed-only edits, 100× playback, recorded DP masks and real 1× BSP animation. Scenario/restart, failure/cancellation, historical pins and catalogue transitions were not all repeated in Chrome. Direct reduced-motion and keyboard activation of Randomize were not verified in Chrome. Publication was not requested.

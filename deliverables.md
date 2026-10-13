# Dungeon Architect - Submission Deliverables Guide

Created: 2026-10-10
Status: Preparation guide only. The application, measured results, and final submission artifacts have not yet been produced.

Purpose: Explain what to submit, how to create each file, and what evidence belongs in it. Use plan.md for project decisions and todo.md for application implementation. This file is the submission checklist and authoring guide, not a second app-development backlog.

## 1. Sources, labels, and interpretation

Primary source: CCP Fall 26.pdf, three pages, in this directory.
- Page 1: assessment rubric, CLO/PLO mapping, total marks.
- Page 2: two-paradigm requirement, flood-relief example, Part A.
- Page 3: Part B, integrated Part C, deliverables, alternative-project note.

The user confirmed that the instructor permits any two algorithm paradigms working together. Our chosen project uses divide-and-conquer for masked dungeon construction and dynamic programming for exact encounter allocation.

Use these labels throughout:
- REQUIRED: explicitly stated in the supplied brief.
- ADAPTED: Dungeon Architect's counterpart to a scenario-specific requirement.
- USER SCOPE: requested project output beyond the brief's explicit minimum.
- RECOMMENDED: supporting material that makes the submission easier to evaluate or reproduce.
- CONFIRM IF SPECIFIED: administrative detail not provided in the available brief; do not invent it or block preparation.

Important distinctions:
1. The brief permits an alternative real-life application after developing its case study. It does not specify a complete alternative-project marking checklist. Clearly explain our mapping to the sample's depth.
2. Do not claim that BSP is an MST algorithm, that our room capacities are truck weights, or that full recomputation is incremental MST repair.
3. At least two primary paradigms are required. Our auxiliary BFS and validation helpers support the system; they do not replace the primary divide-and-conquer plus DP pairing.
4. The brief references Part D and a sample dataset, but neither appears in the supplied PDF. Do not invent a mandatory bonus module.
5. The rubric mentions time decay, but the explicit sample DP requirements use fixed input values. Our threat costs and scores are fixed during a run; describe actual trade-offs without inventing time decay.
6. Use C++ for core algorithms as selected by the user. The brief says the implementation language must be agreed with the instructor; retain any relevant course confirmation if supplied. Flutter/Dart is the presentation layer.
7. Report file type, portal, deadline, naming convention, signatures, and exact page-count policy are not specified. Prepare the agreed files and apply later instructions when available.

## 2. Master requirements and evidence register

| ID | Classification/source | What must be covered | Dungeon Architect evidence | Where to put it |
| --- | --- | --- | --- | --- |
| R01 | REQUIRED, p2-p3 | Develop a real-life case study with two connected paradigms | Dungeon designer's geometry problem and shared encounter-allocation problem | Report introduction/formulation and case-study source |
| R02 | REQUIRED, p3 | Problem formulation and assumptions, approximately half a page | Concise problem, inputs, objectives, constraints, assumptions | Report formulation |
| R03 | REQUIRED, p3 | Pseudocode for every algorithm used, labelled by part | BSP, room/corridor helpers, DP, reconstruction, material supporting methods | Report methodology/appendices |
| R04 | REQUIRED, p3 | Time and space complexity derivations for every algorithm | Implementation-specific generation/helper/DP bounds and brute-force comparison | Report complexity analysis |
| R05 | REQUIRED, p3 | Working source code | C++ core/API/CLI; Flutter source for the selected UI scope | Source package |
| R06 | REQUIRED, p3 | Test dataset | Reproducible project inputs, seed, settings, inventory, schema | Dataset package |
| R07 | REQUIRED, p3 | At least three demonstrated edge-case tests with outputs | Disconnection, over-demand, oversized pack | Results section and raw evidence |
| R08 | REQUIRED, p3 | Minimum six-page report with named sections | Complete report using the outline below | Final report |
| R09 | REQUIRED intent, p1-p2 | Correct models, correctness arguments, meaningful trade-offs | Geometry invariants, DP induction/optimality, space-time/user-control trade-offs | Methodology, analysis, limitations |
| A01 | ADAPTED from Part A, p2 | Valid connectivity despite unavailable links; deterministic choices | Mask-aware generation, blocked corridors, actual reachability, reproducible ties | Generation method and tests |
| A02 | ADAPTED from Part B, p3 | Shared items, distinct capacities, fixed values, partial allocation, reconstruction | Unique packs across rooms, room capacities, global threat, exact assignment | Formal model, DP, results |
| A03 | ADAPTED from Part C, p3 | Worked integrated example | Large custom mask, fixed room, 10-20 rooms, 12-14 packs, complete allocation | Worked example |
| A04 | ADAPTED from Part C, p3 | Change important locations and rerun both stages | Disable/remove two explicitly selected high-capacity rooms and evaluate geometry/reachability/allocation | Sensitivity results |
| U01 | USER SCOPE | Editable DOCX and later final PDF | Polished editable report; user replaces placeholders and exports PDF | Report folder |
| U02 | USER SCOPE | Working attractive interface and exploration | Flutter Design/Analyze/Play with C++ native engine | Runnable application and demo |
| U03 | USER SCOPE | Viva preparation | Questions, concise explanations, trace examples, demo recovery notes | Personal preparation folder |
| S01 | RECOMMENDED | Easy build/run and verification | README, command instructions, result manifest, release package | Submission root |
| S02 | RECOMMENDED | Developer reuse of native engine | Public C header, DLL, integration example, ownership notes | Source/app package |

This table is traceability, not a statement that the alternative scenario has already received separate line-by-line approval.

## 3. Understand the marking rubric

The brief gives 20 total marks with these weights:

| Attribute | Weight | What strong evidence looks like |
| --- | --- | --- |
| WP1: depth of engineering knowledge | 10% | Clearly define both subproblems and justify the selected paradigms |
| WP2: conflicting requirements | 20% | Identify competing requirements, choose a policy, and show consequences |
| WP3: depth of analysis | 30% | Correct model, justified algorithm behavior, and derived time/space bounds |
| WP5: implementation | 40% | Correct, efficient, tested source with clear pseudocode and demonstrated edge cases |

Do not let screenshots substitute for algorithm correctness or testing. A visually attractive app is useful evidence of integration, not evidence that the DP is optimal.

Suggested traceability paragraph for the report: explain which sections contain each attribute's evidence. Do not claim a grade or pre-award marks.

## 4. Recommended submission package

The brief does not mandate these filenames or folders. They are a portable organization to apply unless a course naming convention overrides them.

Dungeon_Architect_Submission/
- README.md
- manifest.csv
- report/
  - Dungeon_Architect_Report.docx
  - Dungeon_Architect_Report.pdf
- source/
  - core/
  - api/
  - cli/
  - apps/flutter_ui/
  - tests/
  - benchmarks/
  - CMakeLists.txt and required dependency/build configuration
- datasets/
  - main_project.json
  - tiny_allocation.json
  - edge_cases/
  - sensitivity/
  - dataset_guide.md
- evidence/
  - run_manifest.csv
  - baseline/
  - edge_cases/
  - sensitivity/
  - benchmarks/
  - figures/
- app/
  - windows/ containing the complete runnable app bundle
  - cli/ containing CLI and required dependencies
  - native/ containing DLL, public header, and a minimal integration example
- preparation/
  - viva_guide.md
  - demo_script.md

Submission rules:
- Source, dataset, demonstrated test outputs, and report are the explicit essentials.
- The app bundle/DOCX/viva materials implement the user's requested scope. Viva notes may remain a personal preparation file rather than being uploaded.
- A slides deck, video, poster, installer, and GitHub link are optional unless later requested by the instructor. Do not treat them as mandatory.
- A standalone case-study/pseudocode file is useful for editing but is not explicitly required if that content is clearly present in the report.
- Keep one authoritative copy of each dataset/result. If the source archive includes the same fixtures, name the canonical copy.
- Exclude caches, temporary renders, irrelevant PDFs, absolute-path-only shortcuts, and unused build products.
- Include files needed to rebuild; exclude secrets and personal machine data.
- Add third-party licenses where assets/libraries require them.
- Create manifest.csv with relative path, purpose, version/run ID where applicable, and optionally a checksum.
- Package only verified artifacts. Do not include empty output files that look complete.

## 5. Create the original case-study specification

Classification: REQUIRED case-study/formulation content, adapted to the selected project.

Suggested working source: docs/case_study.md.
Final destination: report introduction, formulation, and methodology.

### 5.1 Write the scenario in ordinary language

Describe a roguelite designer who:
- Draws the permitted dungeon-building area.
- Chooses room count and room-size ranges.
- Fixes a room at a chosen position before generation.
- Needs non-overlapping rooms and traversable corridors.
- Has a limited shared inventory of encounter packs.
- Must obey room spawn capacities, compatibility rules, and a global threat budget.
- Wants to maximize a stated additive designer score.
- Needs to inspect, edit, and explore the resulting dungeon.

Explain why doing only geometry or only allocation is insufficient. Geometry changes available capacity and eligibility; those outputs become inputs to DP.

State originality accurately: this is our developed scenario and implementation. Do not claim nobody has ever built a procedural dungeon generator or combined these ideas.

### 5.2 Declare inputs and units

Provide a data dictionary:
- Canvas dimensions in tiles; default at least 150 x 150.
- Allowed-area mask versus actual carved floor.
- Coordinate origin and rectangle convention.
- Requested total rooms, including fixed/entrance/exit rooms.
- Minimum/maximum room interior sizes, wall margins, corridor width.
- Fixed-room IDs, positions, dimensions, roles, and locks.
- Seed, engine version, and generation work limits.
- Pack ID, spawn demand, threat, score, and compatibility.
- Per-room spawn capacity and reachability.
- Active inventory count and global threat budget.

Distinguish defaults, user-editable values, tested limits, and algorithmic constraints. A default is not a proof that every input of that size is feasible.

### 5.3 Declare outputs and assumptions

Outputs: validated layout, rooms/corridors, reachable-room set, valid spawn positions, chosen packs, explicit room assignments, objective totals, unused packs, diagnostics, metrics.

Assumptions:
- Tile positions and relevant costs/capacities are integer-valued.
- Unique pack copies can be used at most once.
- Pack threat/score remain fixed within a solve.
- Unused packs and empty rooms are allowed.
- Entrance has zero encounter capacity.
- Actors do not obstruct essential exploration routes.
- A locked boss-room footprint does not automatically force a particular boss pack.
- Scores encode designer preferences, not proven enjoyment.
- No combat balance or global layout optimality is claimed.
- Exactness applies to allocation on the generated layout.
- A bounded generator search can fail to find a layout without proving none exists.

### 5.4 Write the half-page formulation

Keep this compact summary near half a page, as requested in the brief. Include the problem, two subproblems, objectives, integration, and principal assumptions. Put the full data dictionary and equations in subsequent subsections/appendices.

Do not shrink fonts to force the entire technical specification into half a page.

## 6. Assemble the written report

Classification: REQUIRED, p3. Editable DOCX is USER SCOPE; PDF is the user's intended final export.

### 6.1 Length and structure

The brief says minimum six pages and lists sections, but does not say whether title/references count. A conservative recommendation is at least six substantive body pages, plus front matter and references. This is a preparation recommendation, not an extra quoted requirement.

Plan approximately 10-16 total pages if needed for readable diagrams, worked results, and analysis; length is secondary to complete, clear content.

Suggested page allocation, adjustable:
- Title page: 1 page.
- Abstract and optional contents: about 1 page.
- Introduction and literature review: 1-2 pages.
- Formulation and assumptions: 1-2 pages.
- Methodology, pseudocode, block diagram, correctness: 2-4 pages.
- Complexity analysis: 1-2 pages.
- Results, edge cases, sensitivity, benchmarks: 2-4 pages.
- Conclusion/limitations and references: 1-2 pages.
- Appendices only when content would interrupt the main explanation.

### 6.2 Required sections and authoring instructions

1. Title page
   - Project title: Dungeon Architect.
   - Institution: NED University of Engineering and Technology.
   - Department: Computer Science and Information Systems.
   - Course: CT-363 - Design and Analysis of Algorithms.
   - Identify the work as the Complex Engineering Problem project.
   - Four editable member name/ID placeholders; remove unused entries before final submission.
   - Instructor name, section, semester, and submission date as placeholders until supplied.
   - Do not invent a signature. The brief has a faculty-signature field; include a signature area only if the course requires its form.

2. Abstract
   - Write last, using only implemented features and actual results.
   - Recommended 150-250 words: problem, paradigms, integration, main findings, limitation.
   - Replace all numerical placeholders with measured/verified values before submission.

3. Introduction
   - Explain the level-design workflow and why constrained procedural generation matters.
   - State project objectives, user controls, and scope.
   - Identify both primary algorithms and the dependency between them.
   - Explain exploration as a way to inspect generated content, not the main optimization problem.

4. Literature Review
   - Discuss BSP/constructive dungeon generation, knapsack/shared allocation, and relevant algorithm foundations.
   - Compare what sources establish with what this project adds: custom masks, fixed rooms, exact pack allocation, interactive inspection.
   - Prefer original/authoritative technical sources; paraphrase and cite.
   - Clearly distinguish related techniques from methods actually implemented.
   - Framework documentation supports implementation claims, not a correctness proof for our custom solver.

5. Problem Formulation
   - Include the half-page summary and explicit assumptions.
   - Define symbols/units and input/output data.
   - Present optimization equations and geometric constraints.
   - Separate generator success conditions from optimizer optimality.

6. Methodology
   - Explain masked BSP, reservations, corridor routing, reachability, capacity derivation, subset DP, and reconstruction.
   - Include labelled pseudocode and the correctness arguments described below.
   - Explain choices: subset DP versus capacity-vector DP; BFS as a helper; deterministic tie handling.
   - Briefly describe the C++ core/API, Flutter integration, and trace events, without replacing algorithm explanation with framework detail.

7. Block Diagram
   - Required by the brief; place in Methodology or its own short subsection.
   - Show inputs -> geometry -> reachability/capacity/compatibility -> DP -> assignment -> views.
   - Show feedback from edits/failure scenarios to affected stages.
   - Label data passed between stages; distinguish UI, native core, and results.
   - Export a readable figure with caption and refer to it in the text.

8. Complexity Analysis
   - Derive time and space for every material algorithm actually used.
   - Define variables consistently and separate theoretical bounds from timings.
   - Include brute-force comparison and supported-size implications.
   - Include preprocessing, reconstruction, trace storage, and helper work where relevant.

9. Results
   - Present actual baseline dataset, generated dungeon, assignments, totals, edge cases, sensitivity, and benchmarks.
   - Use tables plus selected screenshots/figures; keep raw evidence in the package.
   - Explain observations, including unchanged outcomes.
   - Include limitations observed during testing, not just successful examples.

10. Conclusion and Limitation
    - Summarize implemented capabilities and validated outcomes.
    - State generation search limits, exponential exact-DP scaling, modelling assumptions, and platform limits.
    - Separate completed work from future features.
    - Do not claim global layout optimality or guaranteed player enjoyment.

11. References
    - Use one consistent citation style, such as IEEE unless the instructor specifies otherwise.
    - Match every in-text citation to an entry and every entry to a genuine use.
    - Verify author/title/year/URL before finalizing.
    - Credit third-party assets/libraries and reused concepts honestly.

Optional appendices: long pseudocode, full inventory table, extra outputs, schema details, reproducibility commands. Do not hide the two primary algorithm explanations entirely in appendices.

## 7. Prepare formal models, pseudocode, and correctness evidence

Classification: REQUIRED pseudocode/analysis; adapted correctness arguments for the selected paradigms.

Suggested working files: docs/algorithms.md and docs/mathematical_model.md. Include their essential content in the report.

### 7.1 Geometric model

State successful-layout conditions explicitly:
- Every room and corridor footprint lies inside the allowed mask.
- Generated rooms do not overlap each other or reserved fixed rooms.
- Fixed rooms retain their requested positions and dimensions.
- Room count equals the requested target on success.
- Dimensions, separation, and corridor clearance are respected.
- The entrance can reach all required rooms and the exit on the actual floor grid.

Explain which checks are sufficient to prove invalid input, and why exhausting bounded retries is a different outcome.

### 7.2 Allocation model

Use consistent symbols:
- N: active encounter packs.
- R: eligible rooms.
- s_i: spawn demand of pack i.
- t_i: threat cost of pack i.
- v_i: designer score of pack i.
- c_r: capacity of room r.
- B: global threat budget.
- a_ir: compatibility indicator.
- x_ir in {0,1}: pack i is assigned to room r.

Objective: maximize sum over i,r of v_i * x_ir.

Constraints:
- sum_r x_ir <= 1 for each pack.
- sum_i s_i * x_ir <= c_r for each room.
- sum_i,r t_i * x_ir <= B.
- x_ir <= a_ir; unreachable/forbidden rooms have a_ir = 0.
- Entrance capacity is zero.

Say that capacity is per room, not pooled globally. Total spare capacity in two rooms cannot accommodate one pack that fits neither.

### 7.3 Pseudocode inventory

Prepare labelled pseudocode with inputs, outputs, state, base/termination conditions, error/cancellation behavior, and deterministic decisions:
- Algorithm A1: top-level validated generation pipeline.
- Algorithm A2: recursive masked BSP, child count allocation, bounded search, and combine step.
- Algorithm A3: actual room-candidate selection method used.
- Algorithm A4: corridor routing with full footprint clearance and door rules.
- Algorithm A5: floor reachability and spawn-position/capacity derivation.
- Algorithm B1: subset totals and room compatibility preprocessing.
- Algorithm B2: room-by-subset DP.
- Algorithm B3: assignment reconstruction and independent validation.
- Algorithm C1: integrated generation/allocation workflow.
- Supporting test/benchmark algorithms where used, including the tiny exhaustive oracle.

These labels are a proposed organization, not additional algorithms to invent. Merge helper listings where clear, but cover every material algorithm actually implemented. GUI painting code does not need pages of pseudocode unless a nontrivial algorithm is a subject of analysis.

Do not paste C++ source and call it pseudocode. Use language-independent steps with consistent indexing and definitions.

### 7.4 DP state and recurrence

Define F(r,M) as feasibility of assigning EXACTLY subset M across the first r eligible rooms.

Base:
- F(0,empty) = true.
- F(0,M) = false for nonempty M.

Transition:
- Enumerate S subset of M.
- S must fit room r and all its packs must be compatible with that room.
- F(r,M) is true when such S exists and F(r-1,M minus S) is true.
- Include S = empty so a room can remain unused.

Final decision:
- Among feasible F(R,M) with threat(M) <= B, maximize score(M).
- Apply documented tie rules.
- Follow stored predecessor subsets to recover each room assignment.

Explain why the same selected subset has the same fixed score regardless of placement. Therefore a feasibility DP followed by final maximization is sufficient. Threat is calculated for subsets rather than added as a separate budget dimension.

### 7.5 Correctness structure

For generation:
- Show recursive termination or explicit bounded termination.
- Explain containment and non-overlap from checked candidates/reservations.
- Explain why fixed-room handling preserves locks even when abstract BSP regions cross reservations.
- Explain how corridor footprint checks establish legality.
- Use actual grid connectivity verification to justify success.
- Do not assert a greedy-choice property for BSP; this is a different paradigm.

For allocation:
- Prove the base state.
- Induction: any valid assignment to r rooms has a last-room subset S; removing it gives a predecessor state.
- Converse: a valid predecessor plus a disjoint compatible S preserves uniqueness and per-room capacity.
- Final subset filtering enforces threat and objective selection gives an optimum for the fixed layout.
- Explain reconstruction correctness and independent result validation.

Tests support implementation reliability but are not a substitute for the algorithm argument.

### 7.6 Tiny manual example for explanation

This is an illustrative calculation, not an executed project result. Create a matching fixture and replace/add actual output when implemented.

Eligible room capacities: R1 = 3 slots, R2 = 2 slots.
Global threat budget: 7.
All packs are otherwise compatible.

| Pack | Slots | Threat | Score |
| --- | --- | --- | --- |
| A | 2 | 3 | 6 |
| B | 2 | 4 | 7 |
| C | 1 | 2 | 4 |
| D | 4 | 1 | 20 |

Expected mathematical result:
- D fits neither room, even though aggregate capacity is 5.
- A+B is feasible, threat 7, score 13, one pack in each room.
- A+C scores 10 and B+C scores 11.
- A+B+C exceeds the threat budget.
- Optimum score is 13; equivalent placements are resolved by the actual tie policy.

Use this to explain global versus per-room constraints and why an attractive oversized pack must be excluded. It does not replace the main full-size worked example.

## 8. Create the complexity analysis

Classification: REQUIRED, p3.

For each algorithm, provide:
1. Input-size variables and assumptions.
2. Data structures and basic operations.
3. Loop counts or recurrence.
4. Derived time bound.
5. Auxiliary memory, input/output storage, and reconstruction/trace costs.
6. Best/average/worst case only where justified.
7. Practical implications supported by measured results.

### 8.1 Generator and helpers

Use A = canvas tiles, R = rooms, D = partition depth, L = routed links, H = bounded attempts.

Analyze the implemented mask scanning, fixed-room checks, rectangle candidate search, BSP recursion, corridor routing, rasterization, and reachability. Balanced BSP is an assumption to justify, not an automatic guarantee.

A uniform-grid BFS is O(A) time/space in the worst case. Multiple routes can contribute O(LA); include footprint-clearance checking costs if corridor width is a variable rather than a fixed constant.

Do not assign O(R log R) to all generation while ignoring grid work, retries, or stored masks. If each attempt can consume a configured work budget, explain the resulting bounded execution policy separately from asymptotic analysis.

### 8.2 DP

Explain:
- There are 2^N pack subsets.
- Summing the number of submasks over every mask gives 3^N because each item is outside M, in M minus S, or in S.
- Straightforward room-by-subset transitions therefore have worst-case time O(R * 3^N).
- Predecessor/feasibility storage is O(R * 2^N) in the planned reconstruction implementation.
- Derive preprocessing costs from the actual method. Checking each item for every room/subset may cost more than using precomputed bitmasks.
- Numeric threat budget B does not create an additional DP dimension here.
- Larger integer magnitudes still require range checks and matter if arithmetic is not constant-width.
- Include canonical ordering, result reconstruction, and actor-placement costs where relevant.

Do not call this a capacity-vector DP or claim O(NB) complexity. Do not describe the subset formulation as polynomial merely because the interface limits N to 14.

### 8.3 Brute-force comparison

Each of N packs can be unused or assigned to one of R rooms: (R+1)^N possible assignments before pruning. State any additional cost of validating a complete assignment.

Use brute force only on tiny fixtures. Distinguish a theoretical search-space comparison from a measured runtime comparison.

### 8.4 Measurements

Record generation and allocation separately. Exclude UI animation time from algorithm timings, and label trace-enabled runs. Record build mode, versions, hardware, seeds, repeat count, operation counters, and timing spread.

Charts are recommended supporting evidence, not a substitute for derivations. Do not infer an asymptotic bound from one small timing curve.

## 9. Prepare reproducible datasets

Classification: REQUIRED test dataset; adapted worked-example scale.

### 9.1 Main dataset

Create main_project.json from a saved valid application project, not a screenshot. Include:
- Schema/engine version and stable IDs.
- Canvas at least 150 x 150 and a reproducible irregular allowed mask.
- Room target in the agreed 10-20 range.
- Room ranges, margins, corridor width, fixed-room details, and seed.
- A visible locked room demonstrating preservation.
- 12-14 unique active encounter packs with varied slot demands, threat, scores, and restrictions.
- Global threat budget and any capacity overrides.

Choose values that make allocation nontrivial. If every pack trivially fits within every limit, the example poorly demonstrates optimization.

Provide dataset_guide.md explaining fields, units, seed reproduction, editable parameters, and expected result files.

The sample explicitly specifies at least ten villages and twenty roads. Our worked example adapts this to a substantive dungeon workload; do not claim ten rooms are twenty roads or fabricate unnecessary corridors. State this adaptation plainly.

### 9.2 Supporting datasets

Create:
- Tiny allocation fixture for a complete manual trace and exhaustive cross-check.
- One file per edge case below.
- Baseline and changed-input files for sensitivity tests.
- Small benchmark parameter sets with fixed seeds.

Separate user-provided data from generated output. Save source input even when generation fails, so the failure is reproducible.

### 9.3 Reproduction record

For each run, record:
- Run ID and timestamp.
- Input relative path and optional checksum.
- Engine/build version and random seed.
- Exact CLI command or precise UI actions.
- Settings, active-pack count, and work limits.
- Outcome/status, objective, assignment path, and raw log path.
- Duration/metrics only if actually measured.

Final command strings must match the implemented CLI. Do not invent executable names/flags before checking --help or the final README.

## 10. Capture the worked example and test evidence

Classification: REQUIRED demonstrated outputs; recommended reproducibility structure.

### 10.1 Main worked example checklist

Capture:
- Original painted mask, settings, and fixed-room position.
- BSP partitions/tree with a readable subset of the generation sequence.
- Final room/corridor map and entrance/exit.
- Room table: ID, role, dimensions, capacity, reachability.
- Inventory table: pack ID, slots, threat, score, compatibility.
- Assignment table: room, selected pack IDs, used/available slots.
- Total selected score, total threat/budget, and unused packs.
- Evidence that assigned packs are unique and fixed-room geometry is unchanged.
- A short explanation of one selected and one unused pack without inventing a causal reason the solver does not establish.

Numbers in tables, screenshots, CLI output, and JSON must come from the same run ID. If the source changes, rerun and replace stale evidence.

### 10.2 Required-style edge cases

E01 - Disconnection:
- Use a saved valid dungeon and block a corridor section that actually disconnects rooms, or supply a disconnected mask as a separate generation-validation case.
- Record unreachable room IDs and exit status.
- On a blocked valid dungeon, rerun allocation using only eligible reachable rooms.
- Show no pack is assigned to an unreachable room.
- A disconnected-input rejection and a post-generation reachability response are different behaviors; label both correctly.
- Preserve previous valid data; do not pretend the program computed a minimum spanning forest.

E02 - Over-demand:
- Ensure otherwise eligible inventory exceeds available room capacity and/or threat budget.
- Include at least one positive-score feasible pack.
- Demonstrate a valid nonzero optimal partial allocation with unused packs.
- Use independent validation and, on a tiny version, exhaustive comparison.
- Do not use an all-infeasible dataset as the only over-demand demonstration.

E03 - Oversized pack:
- Add a pack whose spawn demand exceeds every eligible room's individual capacity.
- Give it a tempting high score to make exclusion visible.
- Keep some smaller feasible packs.
- Show the oversized pack is excluded, totals remain correct, and the solver still returns the correct partial optimum.
- Explain why combined free capacity cannot be used to split one pack across rooms.

### 10.3 Additional recommended tests

Include selected tests that expose real implementation risks:
- Fixed room outside mask or overlapping another room.
- Impossible room-size bounds; too many requested rooms.
- Search limit reached without asserting mathematical impossibility.
- Two-tile corridor requested through a one-tile neck.
- Empty inventory; no eligible rooms; zero threat budget.
- Zero-threat positive-score packs.
- Equal-score ties and input reordering.
- More than the supported active-pack count.
- Integer overflow/malformed JSON/duplicate IDs.
- Cancellation and stale asynchronous completion.
- Save/load round trip and packaged-app library loading.

### 10.4 Per-test evidence template

For each test, write:
- Test ID/name and requirement covered.
- Input filename and the exact changed fields.
- Expected behavior before execution.
- How to run it.
- Actual status and output paths.
- Objective/assignment or validation error, as applicable.
- Independent checks performed.
- Pass/fail and a short explanation.

Expected versus actual must remain separate. Do not mark tests passed before execution. A screenshot alone is insufficient where assignment correctness requires machine-readable data.

### 10.5 Evidence naming and manifest

Suggested names:
- evidence/baseline/run_001_result.json
- evidence/baseline/run_001_console.txt
- evidence/edge_cases/E03_oversized_result.json
- evidence/figures/fig_04_assignment.png

run_manifest.csv should map test/run IDs to inputs, commands, versions, outputs, screenshots, and status. Use relative paths to keep the package portable.

## 11. Prepare sensitivity and failure analysis

Classification: ADAPTED integrated analysis; benchmarks are RECOMMENDED supporting evidence.

### 11.1 Required sample experiment versus our adaptation

The sample removes the two highest-severity villages and asks how both algorithm outputs change. Dungeon Architect has no village severity field.

Our declared adaptation:
1. Rank eligible, removable combat rooms by baseline capacity, with stable room ID as the tie-breaker.
2. Identify the two selected room IDs before changing the scenario.
3. Preserve entrance/exit and locked-room rules; explain exclusions from the ranking.
4. Disable the chosen rooms for a failure scenario, or remove them in an explicit geometry-regeneration variant.
5. State which variant was used; disabling capacity is not the same as removing floor or regenerating a layout.
6. Recompute affected reachability/capacities and allocation; regenerate geometry when the chosen change requires it.
7. Compare baseline and changed outputs from the same documented workflow.

Do not say the original PDF explicitly requests removing highest-capacity rooms. This is the project's scenario-specific replacement.

### 11.2 Before/after table

Include:
- Scenario/input ID.
- Removed/disabled room IDs or blocked corridor coordinates.
- Changed generation settings, if any.
- Reachable/eligible room count.
- Total eligible capacity.
- Selected pack IDs and changed assignments.
- Total score and threat.
- Unused/unusable packs.
- Native generation/allocation timings if measured.
- Interpretation and limitations.

An unchanged objective is a valid result. Explain whether spare capacity or alternative rooms absorbed the change; do not force dramatic differences.

### 11.3 Three-corridor failure scenario

The sample's extension requires incremental MST repair after three roads fail. Our project does not implement an MST.

For our supported failure feature:
- Save baseline.
- Block three precisely identified corridor sections.
- Recompute actual floor reachability.
- Rerun exact allocation using changed eligibility.
- Show before/after snapshots and recovery to baseline.

Describe this as a full reachability/allocation rerun, not incremental MST repair. Reusing unchanged geometry on a score-only edit is useful caching/invalidation, but is not evidence of a dynamic graph algorithm.

If a separate instructor instruction demands an incremental algorithm for the alternative scenario, revise the scope explicitly; do not claim the current rerun meets that different requirement.

### 11.4 Other useful parameter changes

Vary one factor at a time:
- Threat budget.
- Capacity of one room.
- Pack threat/score.
- Room-size limits.
- Position of one fixed room.
- Canvas area or requested room count.

Record which stage changes and which can be reused. Avoid comparing unrelated random maps without explaining that both input and seed changed.

## 12. Package working source code and datasets

Classification: REQUIRED source code and datasets; recommended build documentation.

### 12.1 Include

- C++ source and headers for generation, allocation, validation, simulation, CLI, and native API.
- Flutter/Dart source and assets for the actual UI.
- Root and platform-specific build configuration.
- Dependency manifests/lockfiles and required license notices.
- Automated tests and their fixture inputs.
- Actual benchmark driver if benchmark results are included.
- Public native API header and ownership/lifetime documentation.
- Reproducible datasets and evidence or clear relative pointers to their canonical copies.

Do not submit only an executable, screenshots, or source fragments copied into the report.

### 12.2 Source README instructions

Write instructions a person unfamiliar with the development machine can follow:
1. Supported OS/architecture.
2. Required compiler, SDK, CMake, Flutter/Dart versions or tested ranges.
3. Dependency installation/setup.
4. Debug/Release configuration and build commands.
5. CLI launch and sample-project execution.
6. Automated test command.
7. Flutter app launch/build.
8. Native DLL lookup/packaging rules.
9. Where outputs are written.
10. Known input/workload limits and failure statuses.

Verify every command from a clean build directory. Use project-relative paths; avoid relying on private absolute paths from the development machine.

### 12.3 Explain implementation boundaries

State that C++ owns algorithm decisions, validation, and authoritative world data. Dart presents controls, renders snapshots, and visualizes emitted events.

Document that the exported ABI is C-compatible even though the implementation is C++. Explain opaque handles, error values, ownership/release functions, thread/cancellation contract, and API version.

Keep this explanation proportionate in the report. Full API reference belongs with the source, not in place of algorithm analysis.

### 12.4 Final source verification

- Build from the exact copy being submitted.
- Run tests from that copy.
- Run the main dataset and compare output to the evidence manifest.
- Confirm no required files exist only outside the package.
- Remove stale binary outputs or clearly separate them from the final release.
- Check filenames/case and paths containing spaces.
- Ensure the source, report, screenshots, and app identify the same final feature set/version.

## 13. Package and demonstrate the application

Classification: USER SCOPE; a working UI is not explicitly mandated by the supplied brief.

### 13.1 Runnable package

Include the complete Flutter Windows output directory with required DLLs/data/assets, not just its main executable. Include CLI dependencies and native reuse files where appropriate.

Test:
- Launch from a different directory.
- Open the packaged sample project.
- Generate, optimize, inspect, and explore.
- Save/reopen.
- Cancel a job.
- Trigger an invalid input and recover.
- Confirm missing-path assumptions do not depend on the developer checkout.

An installer is optional. A verified portable folder/ZIP can be adequate unless course rules specify otherwise.

### 13.2 Live demonstration script

Suggested duration: approximately 6-10 minutes, adjustable to the actual presentation slot.

1. Introduce the user's design problem and the two connected algorithms.
2. Open a known-good saved project with an irregular mask.
3. Point out the canvas, room-count setting, and fixed room.
4. Generate and show the BSP process briefly.
5. Inspect room capacities/eligibility.
6. Edit a pack threat or global budget.
7. Optimize and show actual assignments and totals.
8. Show one edge case or corridor failure with a clear diagnostic/change.
9. Enter Play and explore the same result.
10. Conclude with exactness scope and the main practical limit.

Use a pretested seed and supported workload. Do not depend on a random last-minute case producing an attractive layout.

### 13.3 Backup and recovery

Prepare:
- A saved known-good project.
- A precomputed result clearly labelled as previously generated.
- CLI commands for the same input.
- Screenshots/raw logs if the UI fails to launch.
- A brief explanation of how to recover from cancellation or invalid data.

Do not present saved playback as live computation without saying so. A backup supports the demonstration; it does not replace a working implementation.

## 14. Create the viva preparation guide

Classification: USER SCOPE. Keep this as a personal aid unless requested for upload.

Suggested file: preparation/viva_guide.md.

Organize each topic as:
- Question.
- Short spoken answer.
- Deeper explanation.
- Relevant code function/file.
- Small input example or figure.
- Common misconception to avoid.

Cover at least:

Problem and integration:
- What does Dungeon Architect solve for a level designer?
- What is a painted allowed region versus a walkable floor?
- Why are two algorithm paradigms necessary?
- Which output of generation becomes an input to allocation?
- How is this different from randomly placing enemies?

Generation:
- What are divide, recursive solve, and combine here?
- Why is BSP not simply binary search or decrease-and-conquer?
- How do masks and holes affect ordinary rectangular BSP?
- How are fixed rooms preserved?
- Why does a room bounding box not prove its cells are allowed?
- How are corridors routed and width checked?
- Why is actual grid reachability checked?
- What does search exhausted mean, and why is it not proof of impossibility?

Allocation:
- What are the decision variables and hard constraints?
- Why not run independent knapsack for every room?
- What does a bitmask represent?
- What exactly does F(r,M) mean?
- What are the base case and transition?
- Why can the DP store feasibility instead of a separate value per placement?
- How does the global threat constraint enter?
- Why can a pack not be split across rooms?
- How is the assignment reconstructed?
- How are ties resolved?
- Why is the result optimal for this layout but not for every possible layout?
- Why choose subset DP rather than capacity-vector DP?

Analysis and verification:
- Where do 2^N and 3^N come from?
- Why does increasing map size affect a different stage from increasing pack count?
- What limits exact-solver scalability?
- What does the tiny exhaustive oracle verify?
- Why do tests alone not prove correctness?
- What changed in the edge/sensitivity scenarios?
- Which timings exclude animation and tracing?

Architecture and limitations:
- Why C++ core plus Dart presentation?
- Why a C-compatible ABI?
- Who allocates and releases native memory?
- How are cancellation and stale results handled?
- What does the seed reproduce?
- What is implemented versus proposed?
- What would need changing for mobile, browser, larger inventory, combat, or mandatory boss placement?

Preparation actions:
- Practice the tiny numerical example without reading code.
- Trace one BSP split and one DP transition by hand.
- Be able to locate the relevant implementation quickly.
- Use measured facts for performance answers.
- Admit limitations precisely; do not invent optimizations or guarantees.
- Replace all member placeholders with real participants and accurately describe contributions.

## 15. Format the DOCX and verify PDF export

Classification: USER SCOPE and recommended quality checks.

### 15.1 Document setup

Unless a course template is provided, use a conservative consistent layout:
- A4 page size and roughly 1-inch margins.
- Readable 11-12 point body text and consistent heading hierarchy.
- Built-in Word heading styles rather than manually formatted headings.
- Consistent paragraph spacing and modest line spacing.
- Page numbers and a restrained header/footer.
- Editable equations, tables, captions, and cross-references.
- Monospaced pseudocode with readable line wrapping.

These are suggested formatting defaults, not requirements stated in the CCP PDF.

### 15.2 Figures and tables

- Use real app/result images from final runs.
- Crop to the relevant region, but keep enough context to interpret it.
- Ensure labels remain readable at the actual printed size.
- Use consistent room/pack IDs across all figures and tables.
- Add numbered captions explaining the point demonstrated.
- Refer to each figure/table from the text.
- Use repeating table headers for long tables.
- Avoid awkward row splits and floating images that move unpredictably.
- Put complete raw output in evidence files rather than shrinking screenshots into unreadability.

Recommended figures:
1. Pipeline/block diagram.
2. Allowed mask and fixed room.
3. BSP partitions/tree.
4. Final connected dungeon.
5. Encounter assignment and capacities.
6. Before/after failure scenario.
7. Benchmark charts where informative.

### 15.3 Export verification

1. Finish content using the final data/version.
2. Update table of contents, captions, cross-references, and page numbers.
3. Save the editable DOCX.
4. Export to PDF using the intended Word environment.
5. Inspect every page at normal reading scale.
6. Check clipped equations, tables, code, captions, blank pages, broken fonts, and displaced figures.
7. Compare DOCX/PDF page flow and figure placement.
8. Fix the DOCX source and re-export until the final PDF is clean.
9. Repeat after replacing member/instructor/date placeholders.
10. Keep both verified files in the final report folder.

Do not promise identical pagination across all computers. Fonts, Word versions, and layout settings can change rendering. Use available fonts, record settings, and verify the actual final PDF the user will submit.

## 16. References, attribution, and evidence integrity

Suggested starting sources to verify when writing:
- Shaker, Liapis, Togelius, Lopes, and Bidarra: Constructive Generation Methods for Dungeons and Levels.
  https://antoniosliapis.com/articles/pcgbook_dungeons.php
- MIT OpenCourseWare: 6.006 knapsack dynamic programming material.
  https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-fall-2011/resources/mit6_006f11_rec21/
- Dart C interoperability:
  https://dart.dev/interop/c-interop
- Flutter native integration:
  https://docs.flutter.dev/platform-integration/bind-native-code
- Flutter Windows setup:
  https://docs.flutter.dev/platform-integration/windows/setup
- Supplied course chapters where used; cite them with available course/author metadata rather than inventing missing publication details.

Before finalizing:
- Verify the source actually supports the associated claim.
- Separate standard concepts from the project's own implementation and empirical results.
- Cite borrowed figures, assets, or code appropriately and retain required licenses.
- Do not fabricate references, measurements, test passes, screenshots, participant contributions, or approval.
- Replace unfinished statements with explicit limitations until the work exists.
- Use one final result version consistently; archive obsolete evidence outside the submitted package.

## 17. Recommended preparation order

1. Finalize the case-study/model text from the agreed plan.
2. Prepare the report outline and source/evidence folder structure.
3. Implement and verify the app using todo.md.
4. Create deterministic tiny, main, edge, and sensitivity fixtures.
5. Run tests and independently validate assignments.
6. Collect raw outputs and populate the run manifest.
7. Capture final figures and benchmark data.
8. Write methodology and complexity from the actual implementation.
9. Write results and limitations from actual evidence.
10. Finish introduction/conclusion, then abstract.
11. Complete references, captions, and traceability checks.
12. Produce and visually inspect the DOCX/PDF.
13. Build the exact source copy and test the packaged app.
14. Practice the live demo and viva using the final version.
15. Replace identity/date placeholders, apply course naming rules, and create the final archive.

Drafting structure can happen early. Final results, measured claims, source listings, and screenshots must wait for real implementation and verification.

## 18. Administrative details to fill in later

These omissions in the brief do not prevent preparing the deliverables:
- Final group members and student IDs.
- Instructor name, section, semester, and submission date.
- Upload portal and permitted archive/file sizes.
- Required naming convention.
- Whether DOCX, PDF, source ZIP, or binaries must be uploaded separately.
- Whether title/references count toward minimum pages.
- Whether a signed cover/rubric page is requested.
- Whether slides/video are required by a later instruction.
- Any course-specific confirmation of the alternative scenario/language.

Record only actual instructions. Do not turn recommendations in this guide into claimed instructor requirements.

## 19. Final submission checklist

### Required content
- [ ] Original case study clearly defines two dependent subproblems.
- [ ] Approximately half-page formulation/assumptions summary is present.
- [ ] Full input/output definitions and constraints are consistent.
- [ ] Pseudocode covers all material algorithms and matches source behavior.
- [ ] Correctness arguments fit BSP and DP rather than copying irrelevant MST claims.
- [ ] Time/space derivations cover both primary algorithms and helpers.
- [ ] Working source code and build instructions are included.
- [ ] Reproducible datasets are included.
- [ ] At least three required-style edge cases have actual demonstrated outputs.
- [ ] Integrated worked example and declared sensitivity adaptation are included.
- [ ] Report meets the minimum length and all named sections are present.

### Project-specific outputs
- [ ] Editable DOCX is complete.
- [ ] Final PDF has been visually checked after placeholder edits.
- [ ] Packaged Flutter app and CLI launch from the submitted folder.
- [ ] Native API header/library/example are consistent with the shipped version.
- [ ] Design, Analyze, and exploration use the same validated result.
- [ ] Viva guide and demo script match implemented behavior.

### Consistency and quality
- [ ] Source, dataset, output tables, figures, and report share the same final version.
- [ ] Scores, capacities, threats, and assignments agree across all evidence.
- [ ] No stale or fabricated timing/test claims remain.
- [ ] Search-limit/cancellation outcomes are not labelled optimal or impossible.
- [ ] Exact allocation is not confused with globally optimal layout generation.
- [ ] Adapted requirements are labelled honestly.
- [ ] All filenames/paths in README and manifests resolve.
- [ ] References and asset licenses are complete.
- [ ] Member details, dates, and other placeholders are replaced or deliberately removed.
- [ ] The final archive opens and contains all required files without irrelevant caches.

## 20. Current status

Only this guide and the existing planning files have been prepared. Do not mark final artifacts, results, proofs tied to an implementation, tests, or app packaging complete until they have actually been created and verified.

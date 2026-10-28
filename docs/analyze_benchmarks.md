# Analyze traces and measured benchmarks

Analyze reads real C++ events after completion. Play, pause, step, restart, speed
and seek operate on an immutable copy; none can change solver input or output.
The map highlights the current event's region, room, door tile or corridor. The
BSP tree represents the accepted partition tree; map clicks and tree selection
share a region selection. Fixed rooms are reserved source features, separately
listed rather than portrayed as generated leaves. Optional overlays keep these
diagnostics out of Design. Allocation reconstruction events identify the room and
actual pack subset, with canonical pack bit order in the DP inspector.

Detailed teaching traces are enabled only for at most six packs and eight rooms.
Candidate events describe only submasks actually examined; the solver stops at
its first feasible predecessor. A feasible state is not a claim that every
candidate was examined. Full workloads emit room summaries and reconstruction.
Non-success outcomes never acquire an optimality label.

Each native event has schema_version 1, run_id, input_revision, sequence, stage,
affected_ids and event payload. input_revision is an FNV-1a identity of exact
submitted input bytes, not an editor revision or cryptographic digest. Dart
attaches its separately captured editor_revision and rejects obsolete output.
Sequence is the retained replay index; source_sequence is the stage event index.
Only one trace is retained. Each native stage stores at most 4096 events; the API
retains at most 4096 overall, reserving up to 1365 per pipeline stage with prefix
and tail sampling. Routing reserves room for completion summaries; allocation
reserves a bounded tail for reconstruction. The displayed truncation count
includes omissions. Playback uses the event index as a checkpoint: seek and
restart read that copy without retaining a snapshot per event or rerunning C++.
Changing views pauses playback; edits invalidate its revision. The last valid map
survives failures or cancellations.

## Measurement contract

Generation reports preflight/search/finalization; routing reports preparation/
routing/derivation/finalization; allocation reports preprocessing/DP/reconstruction.
These are steady-clock wall durations including validation, trace emission and
cooperative Wasm yields. They are not exclusive CPU times. trace_us measures nested
emission overhead already included in these stages, so must not be added again.
API instrumentation separately measures complete execution wall time (including
report construction) and final JSON dump serialization. Bridge wall duration also
includes transport/decoding. Flutter drawing and playback are outside native
stage measurements. Core operation counters and guarded worst-case estimates
remain unchanged.

allocated_table_bytes is actual vector capacity times element size for subset
totals, feasibility, predecessor and rolling state tables. It excludes other
vectors, allocator bookkeeping, source/geometry, Wasm linear-memory reserve and
process RSS. estimated_bytes is a conservative logical solver-table estimate;
neither is an observed process-memory peak. The 64 MiB DP table guard and configured
work/time limits still apply.

## In-app benchmark workflow

The Benchmarks tab previews an independent controlled rectangle fixture. Select
area, room count or active packs, comma-separated values, 2-5 repeats and a fixed
seed. Other axes remain 150 x 150, 16 rooms and 12 packs. Area points must be perfect
squares with sides 64-512. This fixture uses 4-8 tile rooms, width-one corridors,
no fixed rooms and simple unconstrained packs; it is intentionally separate from
the target fixture measured below. Default 1000 candidate attempts, 100 million
work units and 30 seconds apply. No automatic search retries occur. Failed and
cancelled outcomes are retained but excluded from timing aggregates.

A separate engine/worker runs jobs sequentially and cannot replace the editor's
retained geometry. Cancel stops further dispatch and requests native cancellation.
The preview limits a batch to eight points times five repeats; at most 60 raw
records survive. Charts show native stage-wall median and min/max spread for the
latest batch, with success count. Earlier seeds/builds are never pooled into that
chart. Inspect/export preserves raw outcomes, repeats, seed, parameters, version,
build mode, engine environment and browser-reported platform/processors/coarse
device memory (when available). These device hints are not resident-memory data.
No measurements are sent to a server.

## Recorded native target evaluation

The committed [target fixture](../benchmarks/phase13-target.json) and
[raw measurements](../benchmarks/phase13-native-results.json) record 36 runs on
Windows x64, native Release engine 0.10.0, seed 42, three repeats, no stored trace,
and no retry. CPU model was not captured; these numbers describe that measurement
environment and must not be treated as universal latency guarantees. The fixture
is a fully allowed rectangle, no fixed rooms, room widths 8-22/heights 8-18,
margin one, corridor width two, threat budget 24, default 1000-attempt/100-million-
work/30-second guards. The target matrix changes requested rooms (10,16,20) and
packs (12,13,14); the area series holds 16 rooms/12 packs. Pack records and exact
parameters are preserved in the fixture. All 36 runs succeeded, and repeated
geometry/allocation content matched after excluding timing telemetry.

The table measures complete CLI process wall time, including process startup,
parsing and JSON serialization; it is not the in-app native-stage chart metric.

| Dimensions | Rooms | Packs | Median ms | Min-max ms |
| --- | --- | --- | --- | --- |
| 150 x 150 | 10 | 12 | 71.48 | 70.76-73.21 |
| 150 x 150 | 10 | 13 | 72.58 | 69.07-74.48 |
| 150 x 150 | 10 | 14 | 76.14 | 70.80-78.53 |
| 150 x 150 | 16 | 12 | 83.30 | 81.86-87.71 |
| 150 x 150 | 16 | 13 | 92.76 | 89.62-93.52 |
| 150 x 150 | 16 | 14 | 96.33 | 91.34-97.50 |
| 150 x 150 | 20 | 12 | 94.16 | 90.65-94.83 |
| 150 x 150 | 20 | 13 | 89.81 | 89.64-95.07 |
| 150 x 150 | 20 | 14 | 99.30 | 99.11-103.52 |
| 150 x 150 | 16 | 12 | 94.40 | 88.54-94.88 |
| 256 x 256 | 16 | 12 | 197.12 | 186.26-209.31 |
| 512 x 512 | 16 | 12 | 626.75 | 609.35-632.22 |

A recorded 150 x 150, 20-room/14-pack run used 1,359,872 logical table bytes versus
1,359,948 estimated, and 5,426,904 actual allocation work units versus 91,238,019
estimated. This fits the default 100-million-work guard without widening it.
The estimate is deliberately conservative; successful measurements do not waive
preflight guards on harder geometry/inventory. The area series demonstrates
substantial geometry scaling even with fixed allocation axes. No new algorithm
optimization was justified by these measurements, so BSP, routing and exact DP
were preserved. Memory/work guards remain explicit and cancellation remains
cooperative rather than a hard real-time promise.

To reproduce one point after a Release build:

```text
dungeon_cli run benchmarks/phase13-target.json --json --events 0
```

Repeat three times, record the returned stage metrics separately from external
process wall time, and compare geometry/allocation content excluding telemetry.
For other target points modify only room_count or the active pack prefix; for area
points change both dimensions and rebuild the fully allowed mask. Preserve seed,
room bounds, corridor width, budgets, build mode and environment in the record.

## Recorded browser target evaluation

The [browser raw measurements](../benchmarks/phase13-browser-results.json)
record 27 real Wasm Web Worker runs in headless Chrome 156.0.8078.73,
Release engine 0.10.0, the same 150 x 150 target matrix, default work/attempt/time
budgets, fixed seed 42, no retry, three repeats and no stored trace. All succeeded;
repeated geometry/allocation content hashes matched. Cold observations remain in
the sample; no warm-up was silently discarded. These bridge wall measurements
include worker execution, cooperative yields, transfer and parsing. They are
neither pure algorithm time nor an interactive frame-rate guarantee. Native stage
measurements and serialization are available separately in each raw record.

| Rooms | Packs | Median bridge ms | Min-max bridge ms |
| --- | --- | --- | --- |
| 10 | 12 | 976.1 | 915.2-1921.8 |
| 10 | 13 | 869.8 | 857.1-874.2 |
| 10 | 14 | 889.6 | 878.8-912.1 |
| 16 | 12 | 1217.4 | 1208.0-1232.9 |
| 16 | 13 | 1221.2 | 1198.1-1312.1 |
| 16 | 14 | 1310.6 | 1256.4-1339.3 |
| 20 | 12 | 1401.8 | 1352.3-1487.1 |
| 20 | 13 | 1485.3 | 1447.7-1497.7 |
| 20 | 14 | 1390.7 | 1367.9-1439.6 |

The browser/native latency difference is material and preserves the need for a
worker and responsive progress/cancellation. These fixture-specific observations
support the measured 10-20 room/12-14 pack range under default guards on this
environment; arbitrary masks and larger workloads still require explicit guarded
validation. Logical state-table bytes agree across the native/Wasm target cases;
this does not measure browser resident memory or heap peaks.

A real-worker cancellation regression using
`datasets/allocation/standard-14.json` observed 21.3 ms from dispatch through
waiting for the running state, requesting cancellation and receiving the
cancelled report. The previous editor snapshot remained retained in its separate
worker, and the cancelled result reported no optimum. This is one observed
sample under default worker settings, not a worst-case cancellation bound. The
regression guard allows five seconds; cooperative checkpoints and browser
scheduling still determine actual latency.

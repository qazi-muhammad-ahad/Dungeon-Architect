# Temporary scenarios and exploration

Generate and solve a baseline before using these workspaces. Analyze retains its
trace controls and adds temporary scenario controls below them. Source Save/Open
continues to store the project inputs, never the temporary blocks or player.

## Scenarios

Enable **Block floor tiles**, then click floor cells to toggle red blocks. The
entrance marker is protected. Alternatively select a corridor and its zero-based
path index, then **Block width section**: this blocks the actual width-square
footprint at that path anchor, including any door or shared route it intersects.
It may leave an alternative physical path open. Selecting a room exposes its
temporary encounter-disable and capacity controls. Disabling a room removes its
encounter capacity and leaves its walkable floor in place. Submit capacity and
budget fields with Enter. Capacity is capped by surviving reachable legal spawn
positions; the entrance always has zero encounter capacity.

Edits immediately mark scenario assignments stale and hide those actor markers.
**Apply scenario** performs a full native flood traversal from the entrance and
a full exact shared-inventory allocation rerun. There is no incremental solver
or heuristic fallback. A room indicator reports whether its hub is reached;
actor positions are also independently filtered by their own tile reachability.
Disconnected room outlines are red. The exit uses its actual marker tile, so a
sealed exit is reported even if other cells in its room remain reachable.

The comparison shows reachable room hubs, selected packs, score, threat, and
measured wall-clock timing. Scenario connectivity/total include validation,
copying and serialization preparation; allocation stage timers include native
validation and cooperative yields. These are observations, not performance
guarantees. Zero remaining capacity and disconnected rooms produce a valid
empty allocation when that is the exact optimum.

**Restore baseline** drops all temporary controls and immediately restores the
retained baseline without regenerating or changing source. Failed/cancelled
runs preserve the last valid native baseline and scenario; stale UI assignments
remain hidden until a current run succeeds or the scenario resets. Source edits
invalidate temporary state and require current baseline output before reuse.

## Exploration

Play's **Start exploration** captures the current validated baseline/scenario
and allocation as a deeply immutable value, along with its native snapshot job
identity and editor revision. The player starts at the entrance. A disconnected
scenario exit explains why Start is disabled. Generate-only output needs an
allocation before exploration starts.

Click the exploration canvas to focus it, then use WASD or arrows. Movement runs
at eight cardinal tiles per second, with an elapsed-time accumulator and one
serialized native collision request per tile. Each callback processes at most
eight steps; excess suspended time/backlog is capped at one second and dropped
after that bound. Long frames never jump through intervening walls. Each native
step checks the immutable snapshot identity, floor origin and destination.

The camera follows the player; the purple exit has an EXIT label. Gold encounter
markers come from reconstructed assignments and do not block movement. Within
two Manhattan tiles, press E or **Inspect nearby** to see pack, room, threat and
score. Reaching the exit ends the session. **Restart** returns to the entrance;
**Pause exploration** and Escape clear held input. **Resume exploration** starts
with no held keys. Focus loss, browser lifecycle changes, dialogs and workspace
switches also pause and clear input. Relevant source/scenario changes invalidate
the session so geometry and assignments cannot come from different revisions.

There is no combat, enemy AI, physics engine, economy, networking or account
system. All scenario, allocation and collision authority remains native C++.

## ABI and lifetime

ABI 1 adds operation `DA_SCENARIO = 11`. Submit UTF-8 JSON:

```json
{"baseline_job":42,"blocked_tiles":[[12,8]],"disabled_rooms":["room-2"],"capacities":{"room-3":0},"budget":20}
```

Only `baseline_job` is mandatory. The job must identify the context's retained
baseline, which must contain validated layout and geometry. Numeric budget uses
an exact nonnegative int64 token. Tile pairs are bounded actual baseline floor;
room IDs must exist. The report follows the pipeline result shape and adds
`scenario` with baseline/snapshot job identities, controls, reachable room count,
disconnected room IDs, exit reachability, `solver: "full_exact_rerun"`, and
connectivity/total microsecond timings. Embedded `source_project` is always the
unchanged baseline source. Scenario geometry has a distinct identity and
`scenario_walkability_verified`; `connected_floor_verified` is true only if all
remaining floor tiles are reached.

The context retains baseline and scenario independently. `da_context_read`
continues to read the baseline; a successful scenario replaces only the previous
scenario. `da_context_step` accepts either retained snapshot's matching job ID.
A new successful baseline or reallocation invalidates the old scenario. Failed
or cancelled work publishes neither. Released job records do not destroy these
retained snapshots. The browser client keeps `snapshotJob` as the baseline ID;
scenario reports carry their own movement ID explicitly.

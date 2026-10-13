# Determinism contract, version 1

The source format, `DeterministicRandom`, generation, routing and allocation
implement the rules below through Phase 06.

- Persist seed as an unsigned 32-bit integer. Construct `std::mt19937(seed)` and
  consume its standardized raw 32-bit sequence. Do not use a clock, `rand`, a
  standard-library distribution, or an unordered-container iteration order to
  decide algorithm behavior.
- To sample `[0, n)`, reject `n == 0`. Compute `threshold = (uint32(0) - n) % n`
  using defined unsigned wraparound. Draw raw `r` until `r >= threshold`, then
  return `r % n`. This removes modulo bias and specifies exactly which values
  consume another engine draw. Bound 1 consumes one draw and returns zero.
- Golden raw MT19937 sequence for seed 5489 starts
  `3499211612, 581869302, 3890346734, 3586334585`. For bound 10 the mapped sequence
  starts `2, 2, 4, 5`. For bound 3,000,000,000 the first two results are
  `499211612, 890346734` (the second raw value is rejected).
- Traverse tiles in row-major `(y, x)` order. Mask/flood BFS neighbor order is north,
  east, south, west. Traverse partition children in recorded left/top then
  right/bottom order. Record any algorithm-specific candidate ordering when the
  algorithm is implemented; randomness must use this mapping and explicit seed.
- Canonical room and pack order is case-sensitive lexical ASCII ID order.
  Canonical active-pack bit position is its index in that sorted active list;
  inactive catalogue entries do not consume bits. Sort tag sets lexically and
  roles by `normal, entrance, exit, boss`. Never silently deduplicate input.
- DP preference remains higher score, lower threat, lower total slots, then
  lexical selected pack-ID sequence. For equal placement choices, process rooms
  in ID order, subsets in increasing numeric mask order (including empty), and
  retain the first feasible predecessor. This determines reconstruction without
  claiming the geometry generator is globally optimal.
- IDs remain stable source identifiers, not array indexes or display names.
  Future generated IDs must follow a documented deterministic traversal scheme.
- Revision counters are local session bookkeeping and never affect random
  output. Tracing/pause/visualization settings must not consume random draws or
  change tie decisions. Successful results are reproducible under the same
  source, engine/contract version, and completed work limit; timing-based early
  termination can vary by machine and must not be labelled optimal or success.

Changing this mapping or traversal contract requires an explicit versioned
decision and revised golden tests. Do not silently swap the primary algorithms.

Phase 03 component IDs follow row-major discovery; the largest component is
primary with lowest-ID tie breaking. Preset ellipses use integer cell-center
tests, avoiding floating-point rounding differences. Fixed-room owner indexes
follow canonical room IDs. Terminal selection honors explicit roles first,
then picks the lowest normal-room ID for entrance and the highest remaining
normal-room ID for exit. None of these operations consumes random numbers.

Phase 04 BSP uses seeded cyclic enumeration and explicit left/top-first child
combination; see `generation.md` for split/count order, origin pruning, generated
IDs, and fixed attachments. Phase 05 routing consumes no random values: door
order is north/east/south/west then ascending coordinate, BFS neighbors use that
same direction order, and connection order is the BSP layout's recorded order.
Room hubs and spawn cells use integer coordinates with row/column tie breaking.
Runtime counters omit elapsed time from result JSON so completed Debug/Release
results can be compared byte-for-byte. Deadline-limited interruption is still
machine dependent. Trace capacity affects only stored/dropped events.

Phase 06 implements the existing contract: active pack bits and rooms in ASCII
ID order, exact masks ascending, candidate last-room submasks ascending including
zero, first feasible predecessor retained. Final ties use score descending,
threat ascending, slots ascending, then lexical selected-ID lists. Actor placement
visits canonical rooms/packs and consumes spawn cells by (y,x,ID). There are no
random draws in allocation. See allocation.md for the recurrence and proof.

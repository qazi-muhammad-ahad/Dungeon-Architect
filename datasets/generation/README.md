# BSP fixtures

- `rectangle`, `l-shape`: six generated rooms on 30 × 24 masks.
- `backtracking`: 24 rooms, seed 2; exercises rejected split rollback.
- `fixed-hole`: teaching mask, two fixed rooms and two generated rooms.
- `fixed-single-leaf`: two fixed terminals plus one generated room.
- `standard-150`: normal 150 × 150 settings, 16 rooms, seed 42, corridor width 2;
  both room generation and routing pass.

Run `dungeon_cli generate FILE` for rooms or `dungeon_cli route FILE` for connected
floor. Use `--json --events 0` for deterministic machine-readable output.

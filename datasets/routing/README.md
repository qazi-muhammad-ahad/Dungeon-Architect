# Routing fixtures

| Fixture | Expected `route` result |
| --- | --- |
| `straight-width2` | Success; two rooms, width 2, 11 BFS anchors, 56 floor tiles |
| `hole-detour-width2` | Success; full-width turns avoid a central hole |
| `narrow-neck-width1` | Success; width 1 fits the single-tile neck |
| `narrow-neck-width2` | Exit 7, `corridor_disconnected`; never silently narrows |
| `blocked-doors` | Exit 7, `no_door_clearance`; width 5 cannot attach to 4 × 4 rooms |
| `invalid-capacity` | Exit 2, `capacity_exceeds_spawns`; source override exceeds actual valid cells |

All fixtures are structurally valid project files and produce valid room layouts.
Routing results are separate artifacts and never replace these source files.

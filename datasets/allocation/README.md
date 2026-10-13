# Allocation source fixtures

Run `dungeon_cli optimize FILE` (or add `--json`). Each file is an ordinary
schema-1 source project; the CLI generates and routes it before solving exactly.

| Fixture | Expected behavior |
| --- | --- |
| teaching.json | Exit has capacity 3. Archer+guard score 14, threat 3, three actors. Ogre is oversized; lava spirit lacks a compatible room. `--budget 2` selects guard for score 9. |
| zero-budget.json | Archer has zero threat and is selected for score 5 with budget 0. |
| standard-14.json | 150x150, seed 42, 16 rooms, 14 active packs, budget 24. Exact score 74, threat 24, 20 actors. |
| unsupported-15.json | Valid editable document; exact optimization rejects 15 active packs with exit 3. |

The exhaustive tiny oracle and synthetic resource/compatibility cases are in
`tests/core/allocation_test.cpp`. Those isolated inputs do not bypass the full
geometry validation used by this CLI pipeline.

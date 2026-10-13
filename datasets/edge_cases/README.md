# Phase 03 geometry fixtures

Each file uses project schema 1. Some are intentionally invalid domain inputs;
they are not examples to normalize or repair automatically.

| File | Expected result |
| --- | --- |
| `holes.json` | Valid mask with a central hole; two locked rooms; preflight passes |
| `islands.json` | Two equal components; component 0 primary and 1 detached; no locks; preflight passes |
| `narrow-neck.json` | One connected mask with a one-tile neck and corridor width 2; preflight passes, routing feasibility deferred to phase 05 |
| `boundary-touching.json` | Room touches canvas edge with margin 0; valid |
| `boundary-conflict.json` | Same touch with margin 1; `room_margin_boundary` |
| `fixed-overlap.json` | Locked room interiors overlap; `room_overlap` |
| `fixed-islands.json` | Source geometry valid but locked rooms on separate islands; preflight rejects `fixed_rooms_disconnected` |

Use `validate FILE --for-generation --json` for the preflight outcome and tile/ID
diagnostics. `mask-info FILE` displays component and reservation data for valid
source documents. It remains usable on `fixed-islands.json`, reporting the
preflight failure alongside the mask analysis.

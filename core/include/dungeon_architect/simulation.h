#pragma once
#include "dungeon_architect/project.h"

namespace dungeon_architect {
// One authoritative tile step. Callers retain immutable, validated geometry.
// Actors are nonblocking. Continuous controls/cameras belong to Phase 15.
bool walkable(const Settings&, const GeometrySnapshot&, Tile) noexcept;
Result<Tile> step_player(const Settings&, const GeometrySnapshot&, Tile from,
                         std::int32_t dx, std::int32_t dy);
}

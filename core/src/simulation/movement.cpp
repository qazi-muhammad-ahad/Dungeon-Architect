#include "dungeon_architect/simulation.h"

namespace dungeon_architect {
bool walkable(const Settings& s, const GeometrySnapshot& g, Tile t) noexcept {
    if (t.x < 0 || t.y < 0 || t.x >= s.columns || t.y >= s.rows) return false;
    const auto index = static_cast<std::size_t>(t.y) * static_cast<std::size_t>(s.columns) + static_cast<std::size_t>(t.x);
    return index < g.layers.floor.size() && g.layers.floor[index] != 0;
}
Result<Tile> step_player(const Settings& s, const GeometrySnapshot& g, Tile from,
                         std::int32_t dx, std::int32_t dy) {
    if (!walkable(s,g,from) || !((dx == 0 && (dy == -1 || dy == 1)) || (dy == 0 && (dx == -1 || dx == 1))))
        return {failure(Outcome::invalid_input,"invalid_step","/simulation",
            "A step needs a floor origin and one cardinal tile direction.","Restart at the entrance or supply a cardinal direction."),{}};
    const Tile to{from.x+dx,from.y+dy};
    return {{},walkable(s,g,to) ? to : from};
}
}

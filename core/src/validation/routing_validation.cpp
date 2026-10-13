#include "dungeon_architect/routing.h"
#include <algorithm>
#include <array>
#include <map>
#include <set>

namespace dungeon_architect {
namespace {
Status bad(const char* code,const char* message) {
    return failure(Outcome::invalid_input,code,"/routed_geometry",message,"Discard this candidate and retain the previous valid dungeon.");
}
constexpr std::array<Tile,4> neighbors{{{0,-1},{1,0},{0,1},{-1,0}}};
}
Status validate_routed_geometry(const Project& source,const RoomLayoutSnapshot& original,const GeometrySnapshot& g) {
    auto layout = original;
    for (auto& room : layout.rooms) {
        const auto found = std::find_if(source.rooms.begin(),source.rooms.end(),[&](const Room& r) { return r.id == room.id; });
        if (found != source.rooms.end()) { room.name = found->name; room.tags = found->tags; room.capacity_override = found->capacity_override; }
    }
    auto status = validate_room_layout(source,layout);
    if (!status.ok()) return status;
    const auto& s = source.settings;
    const auto area = source.allowed_mask.size(); const int width = s.corridor_width;
    auto index = [&](Tile t) { return static_cast<std::size_t>(t.y*s.columns+t.x); };
    auto inside = [&](Tile t) { return t.x >= 0 && t.y >= 0 && t.x < s.columns && t.y < s.rows; };
    if (g.id.empty() || g.room_layout_id != layout.id || g.geometry_revision != layout.geometry_revision)
        return bad("geometry_dependency","Geometry does not identify its accepted room layout/revision.");
    if (g.layers.occupancy != layout.occupancy || g.layers.reservations != layout.reservations ||
        g.layers.floor.size() != area || g.layers.walls.size() != area || g.movement_reserved.size() != area ||
        g.rooms.size() != layout.rooms.size() || g.corridors.size() != layout.connections.size() || g.doors.size() != 2*g.corridors.size())
        return bad("geometry_shape","Room, corridor, door or tile-layer storage is inconsistent.");
    std::map<RoomId,const Room*> rooms;
    for (const auto& room : layout.rooms) rooms.emplace(room.id,&room);
    std::map<std::string,const Door*> doors;
    std::vector<std::uint8_t> door_cells(area,0),floor = layout.occupancy, movement(area,0);
    for (const auto& d : g.doors) {
        const auto found = rooms.find(d.room_id);
        if (d.id.empty() || !doors.emplace(d.id,&d).second || found == rooms.end() || d.tiles.size() != static_cast<std::size_t>(width))
            return bad("door_identity","Doors need unique IDs, existing rooms and exactly corridor-width tiles.");
        const auto& r = found->second->bounds; const auto first = d.tiles.front();
        Tile expected_anchor;
        if (d.side == DoorSide::north) expected_anchor = {first.x,r.y-width};
        else if (d.side == DoorSide::east) expected_anchor = {r.x+r.width,first.y};
        else if (d.side == DoorSide::south) expected_anchor = {first.x,r.y+r.height};
        else if (d.side == DoorSide::west) expected_anchor = {r.x-width,first.y};
        else return bad("door_side","Unknown door side.");
        if (!(expected_anchor == d.outside_anchor) || !Rect{expected_anchor.x,expected_anchor.y,width,width}.inside(s.columns,s.rows))
            return bad("door_anchor","Door outside footprint does not match its boundary side.");
        for (int k = 0; k < width; ++k) {
            const auto t = d.tiles[static_cast<std::size_t>(k)];
            const bool horizontal = d.side == DoorSide::north || d.side == DoorSide::south;
            const Tile expected{first.x+(horizontal?k:0),first.y+(horizontal?0:k)};
            if (!(t == expected) || !r.contains(t) ||
                (d.side == DoorSide::north && t.y != r.y) || (d.side == DoorSide::south && t.y != r.bottom()-1) ||
                (d.side == DoorSide::west && t.x != r.x) || (d.side == DoorSide::east && t.x != r.right()-1))
                return bad("door_tiles","Door cells must be a contiguous width-wide line on the indicated room boundary.");
            door_cells[index(t)] = 1;
        }
    }
    std::set<std::string> used_doors, corridor_ids;
    for (std::size_t c = 0; c < g.corridors.size(); ++c) {
        const auto& corridor = g.corridors[c]; const auto& edge = layout.connections[c];
        const auto from = doors.find(corridor.from_door), to = doors.find(corridor.to_door);
        if (corridor.id.empty() || !corridor_ids.insert(corridor.id).second || corridor.from_room != edge.from || corridor.to_room != edge.to ||
            from == doors.end() || to == doors.end() || from->second->room_id != edge.from || to->second->room_id != edge.to ||
            !used_doors.insert(corridor.from_door).second || !used_doors.insert(corridor.to_door).second ||
            corridor.path.empty() || corridor.path.size() > area)
            return bad("corridor_identity","Corridors must match routing requirements and reference distinct endpoint door records.");
        if (!(corridor.path.front() == from->second->outside_anchor) || !(corridor.path.back() == to->second->outside_anchor))
            return bad("corridor_endpoints","A path does not terminate at its recorded door footprints.");
        std::set<std::size_t> anchors;
        for (std::size_t j = 0; j < corridor.path.size(); ++j) {
            const auto a = corridor.path[j];
            if (!Rect{a.x,a.y,width,width}.inside(s.columns,s.rows)) return bad("corridor_bounds","A full corridor footprint escapes the canvas.");
            if (!anchors.insert(index(a)).second) return bad("corridor_loop","A corridor repeats an anchor.");
            if (j > 0 && std::abs(std::int64_t{a.x}-corridor.path[j-1].x)+std::abs(std::int64_t{a.y}-corridor.path[j-1].y) != 1)
                return bad("corridor_step","Corridor anchors must advance by one orthogonal tile.");
            for (int y = a.y; y < a.y+width; ++y) for (int x = a.x; x < a.x+width; ++x) {
                const auto i = index({x,y});
                if (!source.allowed_mask[i] || layout.occupancy[i]) return bad("corridor_clearance","A corridor footprint crosses a mask hole or room interior.");
                floor[i] = 1; movement[i] = 1;
            }
            for (int k = 0; k < width; ++k)
                for (auto t : {Tile{a.x+k,a.y-1},Tile{a.x+k,a.y+width},Tile{a.x-1,a.y+k},Tile{a.x+width,a.y+k}})
                    if (inside(t) && layout.occupancy[index(t)] && !door_cells[index(t)])
                        return bad("unrecorded_door","Corridor side contact with a room lacks an explicit door.");
        }
    }
    if (floor != g.layers.floor) return bad("floor_union","Floor must equal exactly the union of room interiors and full corridor footprints.");
    if (g.entrance_room != layout.terminals.entrance || g.exit_room != layout.terminals.exit ||
        !inside(g.entrance_marker) || !inside(g.exit_marker) || g.entrance_marker == g.exit_marker ||
        !rooms.at(g.entrance_room)->bounds.contains(g.entrance_marker) || !rooms.at(g.exit_room)->bounds.contains(g.exit_marker))
        return bad("geometry_markers","Distinct entrance/exit markers must lie inside their designated rooms.");
    std::vector<std::uint8_t> reached(area,0); std::vector<Tile> queue{g.entrance_marker}; reached[index(queue[0])] = 1;
    for (std::size_t head = 0; head < queue.size(); ++head) for (auto d : neighbors) {
        const Tile next{queue[head].x+d.x,queue[head].y+d.y};
        if (inside(next) && floor[index(next)] && !reached[index(next)]) { reached[index(next)] = 1; queue.push_back(next); }
    }
    if (reached != floor) return bad("floor_connectivity","Some actual floor cells cannot be reached from the entrance.");
    std::vector<std::uint8_t> walls(area,0);
    for (int y = 0; y < s.rows; ++y) for (int x = 0; x < s.columns; ++x) {
        const auto i = index({x,y}); if (floor[i] || !source.allowed_mask[i]) continue;
        for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
            const Tile t{x+dx,y+dy}; if (inside(t) && floor[index(t)]) walls[i] = 1;
        }
    }
    if (g.layers.walls != walls) return bad("wall_outline","Walls must outline allowed non-floor neighbors of actual floor.");
    for (std::size_t i = 0; i < g.rooms.size(); ++i) {
        const auto& room = g.rooms[i]; const auto& r = layout.rooms[i];
        if (room.id != r.id || !(room.bounds == r.bounds) || !room.reachable || !r.bounds.contains(room.hub))
            return bad("room_placement","Room placement differs from the accepted layout or is not reachable.");
        auto best = std::make_tuple(true,std::numeric_limits<std::int64_t>::max(),0,0); Tile hub;
        for (int y = r.bounds.y; y < r.bounds.bottom(); ++y) for (int x = r.bounds.x; x < r.bounds.right(); ++x) {
            const auto distance = std::abs(2LL*x+1-(2LL*r.bounds.x+r.bounds.width))+std::abs(2LL*y+1-(2LL*r.bounds.y+r.bounds.height));
            auto candidate = std::make_tuple(door_cells[index({x,y})] != 0,static_cast<std::int64_t>(distance),y,x);
            if (candidate < best) { best = candidate; hub = {x,y}; }
        }
        if (!(hub == room.hub) || (room.id == g.entrance_room && !(hub == g.entrance_marker)) || (room.id == g.exit_room && !(hub == g.exit_marker)))
            return bad("room_hub","Room hubs/markers do not follow deterministic center selection.");
        movement[index(hub)] = 1;
        for (const auto& d : g.doors) if (d.room_id == room.id) for (const auto t : d.tiles) {
            const auto min_x = std::min(t.x,hub.x), max_x = std::max(t.x,hub.x);
            for (int x = min_x; x <= max_x; ++x) movement[index({x,t.y})] = 1;
            const auto min_y = std::min(t.y,hub.y), max_y = std::max(t.y,hub.y);
            for (int y = min_y; y <= max_y; ++y) movement[index({hub.x,y})] = 1;
        }
    }
    if (movement != g.movement_reserved) return bad("movement_lanes","Reserved movement lanes do not match corridors and door-to-hub paths.");
    std::set<SpawnId> spawn_ids;
    for (std::size_t i = 0; i < g.rooms.size(); ++i) {
        const auto& room = g.rooms[i]; const auto& r = layout.rooms[i];
        std::vector<Tile> expected;
        if (room.id != g.entrance_room) for (int y = r.bounds.y; y < r.bounds.bottom(); ++y) for (int x = r.bounds.x; x < r.bounds.right(); ++x) {
            const Tile t{x,y};
            if ((x-r.bounds.x)%2 == 0 && (y-r.bounds.y)%2 == 0 && !movement[index(t)] && !door_cells[index(t)] && !(t == g.entrance_marker) && !(t == g.exit_marker)) expected.push_back(t);
        }
        if (room.spawn_positions.size() != expected.size()) return bad("spawn_count","Spawn positions do not cover the valid spaced room cells.");
        for (std::size_t j = 0; j < expected.size(); ++j) {
            const auto& spawn = room.spawn_positions[j]; const auto t = expected[j];
            if (!(spawn.tile == t) || spawn.id != room.id+":spawn:"+std::to_string(t.x)+":"+std::to_string(t.y) || !spawn_ids.insert(spawn.id).second)
                return bad("spawn_position","Spawn ID, position, spacing or movement exclusion is invalid.");
        }
        const auto available = static_cast<std::int32_t>(expected.size());
        if ((r.capacity_override && *r.capacity_override > available) || room.capacity != r.capacity_override.value_or(available))
            return bad("room_capacity","Room capacity exceeds actual valid spawn positions or differs from its override.");
    }
    return {};
}
} // namespace dungeon_architect

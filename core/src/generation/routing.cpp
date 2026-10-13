#include "dungeon_architect/routing.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <map>

namespace dungeon_architect {
namespace {
constexpr std::array<Tile,4> directions{{{0,-1},{1,0},{0,1},{-1,0}}};
Status error(Outcome outcome, const char* code, const char* message, std::vector<RoomId> ids = {}, std::vector<Tile> tiles = {}) {
    auto status = failure(outcome,code,"/routing",message,"Inspect the indicated rooms/tiles; regenerate or adjust space, width, capacity, or work limits. The previous dungeon is unchanged.");
    status.diagnostics[0].affected_ids = std::move(ids); status.diagnostics[0].affected_tiles = std::move(tiles); return status;
}
struct Prefix {
    int stride;
    std::vector<int> cells;
    Prefix(int columns,int rows) : stride(columns+1),cells(static_cast<std::size_t>((columns+1)*(rows+1)),0) {}
    std::size_t i(int x,int y) const { return static_cast<std::size_t>(y*stride+x); }
    void put(int x,int y,bool v) { cells[i(x+1,y+1)] = (v?1:0)+cells[i(x,y+1)]+cells[i(x+1,y)]-cells[i(x,y)]; }
    int sum(int x,int y,int w,int h) const { return cells[i(x+w,y+h)]-cells[i(x,y+h)]-cells[i(x+w,y)]+cells[i(x,y)]; }
};
bool door_contains(const Door& door, Tile t) {
    if (door.tiles.empty()) return false;
    const auto a = door.tiles.front(), b = door.tiles.back();
    return t.x >= a.x && t.x <= b.x && t.y >= a.y && t.y <= b.y;
}
class Router {
public:
    Router(const Project& p,const RoomLayoutSnapshot& l,const RoutingOptions& o) : source(p),layout(l),options(o),start(std::chrono::steady_clock::now()) {}
    RoutingResult run() {
        if (options.max_events > 4096) { result.status = error(Outcome::unsupported_size,"trace_limit","Trace storage supports at most 4096 events."); return std::move(result); }
        if (options.cancelled && options.cancelled()) { result.status = error(Outcome::cancelled,"cancelled","Corridor routing was cancelled."); return std::move(result); }
        // Allocation metadata can change without invalidating room geometry.
        for (auto& room : layout.rooms) {
            auto found = std::find_if(source.rooms.begin(),source.rooms.end(),[&](const Room& r) { return r.id == room.id; });
            if (found != source.rooms.end()) { room.name = found->name; room.tags = found->tags; room.capacity_override = found->capacity_override; }
        }
        result.status = validate_room_layout(source,layout);
        if (!result.status.ok() || !tick(0)) return std::move(result);
        const auto& s = source.settings;
        width = s.corridor_width;
        geometry.id = "floor-"+layout.id; geometry.room_layout_id = layout.id; geometry.geometry_revision = layout.geometry_revision;
        geometry.layers.occupancy = layout.occupancy; geometry.layers.reservations = layout.reservations;
        geometry.layers.floor = layout.occupancy; geometry.layers.walls.assign(layout.occupancy.size(),0);
        geometry.movement_reserved.assign(layout.occupancy.size(),0);
        door_cells.assign(layout.occupancy.size(),0); basic.assign(layout.occupancy.size(),0);
        Prefix blocked(s.columns,s.rows);
        for (int y = 0; y < s.rows; ++y) for (int x = 0; x < s.columns; ++x) {
            if (!tick()) return std::move(result);
            blocked.put(x,y,!source.allowed_mask[index({x,y})] || layout.occupancy[index({x,y})]);
        }
        for (int y = 0; y+width <= s.rows; ++y) for (int x = 0; x+width <= s.columns; ++x) {
            if (!tick()) return std::move(result);
            basic[index({x,y})] = blocked.sum(x,y,width,width) == 0 ? 1 : 0;
        }
        for (const auto& room : layout.rooms) rooms.emplace(room.id,&room);
        for (std::size_t e = 0; e < layout.connections.size(); ++e) if (!route(layout.connections[e],e)) return std::move(result);
        if (!derive()) return std::move(result);
        std::int64_t final_work = static_cast<std::int64_t>(source.allowed_mask.size())*20 + static_cast<std::int64_t>(layout.rooms.size()*layout.rooms.size());
        for (const auto& n : layout.partitions) final_work += std::int64_t{n.bounds.width}*n.bounds.height;
        for (const auto& c : geometry.corridors) final_work += static_cast<std::int64_t>(c.path.size())*width*width*5;
        if (!tick(final_work)) return std::move(result);
        result.status = validate_routed_geometry(source,layout,geometry);
        if (result.status.ok() && tick(0)) result.geometry = std::move(geometry);
        return std::move(result);
    }
private:
    const Project& source;
    RoomLayoutSnapshot layout;
    const RoutingOptions& options;
    std::chrono::steady_clock::time_point start;
    int width = 1;
    RoutingResult result;
    GeometrySnapshot geometry;
    std::vector<std::uint8_t> basic,door_cells;
    std::map<RoomId,const Room*> rooms;
    std::size_t index(Tile t) const { return static_cast<std::size_t>(t.y*source.settings.columns+t.x); }
    Tile tile(std::size_t i) const { return {static_cast<int>(i%static_cast<std::size_t>(source.settings.columns)),static_cast<int>(i/static_cast<std::size_t>(source.settings.columns))}; }
    bool inside(Tile t) const { return t.x >= 0 && t.y >= 0 && t.x < source.settings.columns && t.y < source.settings.rows; }
    bool tick(std::int64_t work = 1) {
        if (!result.status.ok()) return false;
        if (options.cancelled && options.cancelled()) { result.status = error(Outcome::cancelled,"cancelled","Corridor routing was cancelled."); return false; }
        if (std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count() >= source.settings.max_time_ms) {
            result.status = error(Outcome::search_exhausted,"time_limit","Routing exceeded its time limit."); return false;
        }
        if (work > source.settings.max_work_units-result.metrics.work_units) { result.status = error(Outcome::search_exhausted,"work_limit","Routing exceeded its work-unit limit."); return false; }
        result.metrics.work_units += work; return true;
    }
    void event(const char* kind,const CorridorId& corridor, const RoomId& room, Tile t) {
        if (result.events.size() < options.max_events) result.events.push_back({kind,corridor,room,t}); else ++result.metrics.dropped_events;
    }
    std::vector<Door> doors(const Room& room) {
        std::vector<Door> out;
        const auto& r = room.bounds;
        for (int side = 0; side < 4; ++side) {
            const bool horizontal = side == 0 || side == 2;
            const auto extent = horizontal ? r.width : r.height;
            for (int offset = 0; offset+width <= extent; ++offset) {
                if (!tick()) return out;
                Door d; d.room_id = room.id; d.side = static_cast<DoorSide>(side);
                if (side == 0) d.outside_anchor = {r.x+offset,r.y-width};
                if (side == 1) d.outside_anchor = {r.x+r.width,r.y+offset};
                if (side == 2) d.outside_anchor = {r.x+offset,r.y+r.height};
                if (side == 3) d.outside_anchor = {r.x-width,r.y+offset};
                if (!inside(d.outside_anchor) || !basic[index(d.outside_anchor)]) continue;
                for (int k = 0; k < width; ++k) {
                    if (!tick()) return out;
                    if (side == 0) d.tiles.push_back({r.x+offset+k,r.y});
                    if (side == 1) d.tiles.push_back({r.x+r.width-1,r.y+offset+k});
                    if (side == 2) d.tiles.push_back({r.x+offset+k,r.y+r.height-1});
                    if (side == 3) d.tiles.push_back({r.x,r.y+offset+k});
                }
                out.push_back(std::move(d));
            }
        }
        return out;
    }
    bool route(const RoomConnection& edge,std::size_t edge_index) {
        const auto& from = *rooms.at(edge.from); const auto& to = *rooms.at(edge.to);
        const auto corridor_id = "corridor-"+std::to_string(edge_index+1);
        event("routing_started",corridor_id,from.id,{from.bounds.x,from.bounds.y});
        auto starts = doors(from), goals = doors(to);
        if (!result.status.ok()) return false;
        if (starts.empty() || goals.empty()) {
            result.status = error(Outcome::search_exhausted,"no_door_clearance","No width-wide outside door footprint fits one of the connected rooms.",{from.id,to.id},{{from.bounds.x,from.bounds.y},{to.bounds.x,to.bounds.y}}); return false;
        }
        const auto area = basic.size();
        std::vector<int> start_gate(area,-1),goal_gate(area,-1),parent(area,-2),origin(area,-1);
        for (std::size_t i = 0; i < starts.size(); ++i) start_gate[index(starts[i].outside_anchor)] = static_cast<int>(i);
        for (std::size_t i = 0; i < goals.size(); ++i) goal_gate[index(goals[i].outside_anchor)] = static_cast<int>(i);
        Prefix contacts(source.settings.columns,source.settings.rows);
        for (int y = 0; y < source.settings.rows; ++y) for (int x = 0; x < source.settings.columns; ++x) {
            if (!tick()) return false;
            const auto i = index({x,y}); contacts.put(x,y,layout.occupancy[i] && !door_cells[i]);
        }
        std::vector<std::int8_t> legal_cache(area,-1);
        auto legal = [&](Tile a) {
            if (!inside(a) || !basic[index(a)]) return false;
            const auto i = index(a);
            if (legal_cache[i] >= 0) return legal_cache[i] != 0;
            int count = 0;
            if (a.y > 0) count += contacts.sum(a.x,a.y-1,width,1);
            if (a.x > 0) count += contacts.sum(a.x-1,a.y,1,width);
            if (a.y+width < source.settings.rows) count += contacts.sum(a.x,a.y+width,width,1);
            if (a.x+width < source.settings.columns) count += contacts.sum(a.x+width,a.y,1,width);
            if (count == 0) { legal_cache[i] = 1; return true; }
            const Door* first = start_gate[i] >= 0 ? &starts[static_cast<std::size_t>(start_gate[i])] : nullptr;
            const Door* last = goal_gate[i] >= 0 ? &goals[static_cast<std::size_t>(goal_gate[i])] : nullptr;
            if (!first && !last) { legal_cache[i] = 0; return false; }
            for (int k = 0; k < width; ++k) {
                if (!tick(4)) return false;
                for (auto t : {Tile{a.x+k,a.y-1},Tile{a.x+k,a.y+width},Tile{a.x-1,a.y+k},Tile{a.x+width,a.y+k}})
                    if (inside(t) && layout.occupancy[index(t)] && !door_cells[index(t)] &&
                        !(first && door_contains(*first,t)) && !(last && door_contains(*last,t))) { legal_cache[i] = 0; return false; }
            }
            legal_cache[i] = 1; return true;
        };
        std::vector<std::size_t> queue;
        for (std::size_t j = 0; j < starts.size(); ++j) {
            const auto a = starts[j].outside_anchor;
            const auto i = index(a);
            if (legal(a) && parent[i] == -2) { parent[i] = -1; origin[i] = static_cast<int>(j); queue.push_back(i); }
        }
        std::optional<std::size_t> reached;
        for (std::size_t head = 0; head < queue.size(); ++head) {
            if (!tick()) return false;
            const auto i = queue[head]; const auto a = tile(i);
            ++result.metrics.anchors_visited; event("anchor_visited",corridor_id,{},a);
            if (goal_gate[i] >= 0) { reached = i; break; }
            for (auto delta : directions) {
                if (!tick()) return false;
                Tile next{a.x+delta.x,a.y+delta.y};
                if (!inside(next)) continue;
                const auto ni = index(next);
                if (parent[ni] == -2 && legal(next)) { parent[ni] = static_cast<int>(i); origin[ni] = origin[i]; queue.push_back(ni); }
            }
        }
        if (!result.status.ok()) return false;
        if (!reached) { result.status = error(Outcome::search_exhausted,"corridor_disconnected","No legal corridor footprint path connects these rooms at the requested width.",{from.id,to.id},{{from.bounds.x,from.bounds.y},{to.bounds.x,to.bounds.y}}); return false; }
        auto first = starts[static_cast<std::size_t>(origin[*reached])], last = goals[static_cast<std::size_t>(goal_gate[*reached])];
        first.id = corridor_id+"-from"; last.id = corridor_id+"-to";
        CorridorLink corridor; corridor.id = corridor_id; corridor.from_room = from.id; corridor.to_room = to.id;
        corridor.from_door = first.id; corridor.to_door = last.id;
        for (int i = static_cast<int>(*reached); i >= 0; i = parent[static_cast<std::size_t>(i)]) {
            if (!tick()) return false;
            corridor.path.push_back(tile(static_cast<std::size_t>(i)));
        }
        std::reverse(corridor.path.begin(),corridor.path.end());
        for (const auto& d : {first,last}) { for (auto t : d.tiles) door_cells[index(t)] = 1; event("door_selected",corridor_id,d.room_id,d.tiles.front()); geometry.doors.push_back(d); }
        for (auto anchor : corridor.path) for (int y = anchor.y; y < anchor.y+width; ++y) for (int x = anchor.x; x < anchor.x+width; ++x) {
            if (!tick()) return false;
            geometry.layers.floor[index({x,y})] = 1; geometry.movement_reserved[index({x,y})] = 1;
        }
        geometry.corridors.push_back(std::move(corridor)); ++result.metrics.corridors_routed;
        event("corridor_routed",corridor_id,{},tile(*reached)); return true;
    }
    bool derive() {
        geometry.entrance_room = layout.terminals.entrance; geometry.exit_room = layout.terminals.exit;
        for (const auto& r : layout.rooms) {
            RoomPlacement placement; placement.id = r.id; placement.bounds = r.bounds;
            auto best = std::make_tuple(true,std::numeric_limits<std::int64_t>::max(),0,0);
            for (int y = r.bounds.y; y < r.bounds.bottom(); ++y) for (int x = r.bounds.x; x < r.bounds.right(); ++x) {
                if (!tick()) return false;
                const auto distance = std::abs(2LL*x+1-(2LL*r.bounds.x+r.bounds.width))+std::abs(2LL*y+1-(2LL*r.bounds.y+r.bounds.height));
                auto score = std::make_tuple(door_cells[index({x,y})] != 0,static_cast<std::int64_t>(distance),y,x);
                if (score < best) { best = score; placement.hub = {x,y}; }
            }
            geometry.movement_reserved[index(placement.hub)] = 1;
            if (r.id == geometry.entrance_room) geometry.entrance_marker = placement.hub;
            if (r.id == geometry.exit_room) geometry.exit_marker = placement.hub;
            for (const auto& d : geometry.doors) if (d.room_id == r.id) for (auto t : d.tiles) {
                for (;;) {
                    if (!tick()) return false;
                    geometry.movement_reserved[index(t)] = 1;
                    if (t == placement.hub) break;
                    if (t.x != placement.hub.x) t.x += t.x < placement.hub.x ? 1 : -1;
                    else t.y += t.y < placement.hub.y ? 1 : -1;
                }
            }
            geometry.rooms.push_back(std::move(placement));
        }
        std::vector<std::uint8_t> reached(basic.size(),0); std::vector<Tile> queue{geometry.entrance_marker}; reached[index(queue[0])] = 1;
        for (std::size_t head = 0; head < queue.size(); ++head) {
            if (!tick(4)) return false;
            ++result.metrics.floor_visited;
            for (auto delta : directions) {
                const Tile next{queue[head].x+delta.x,queue[head].y+delta.y};
                if (inside(next) && geometry.layers.floor[index(next)] && !reached[index(next)]) { reached[index(next)] = 1; queue.push_back(next); }
            }
        }
        for (std::size_t i = 0; i < basic.size(); ++i) {
            if (!tick()) return false;
            if (geometry.layers.floor[i] && !reached[i]) { result.status = error(Outcome::search_exhausted,"floor_disconnected","Actual carved floor is disconnected from the entrance.",{}, {tile(i)}); return false; }
            if (geometry.layers.floor[i] || !source.allowed_mask[i]) continue;
            const auto t = tile(i);
            for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
                const Tile neighbor{t.x+dx,t.y+dy};
                if (inside(neighbor) && geometry.layers.floor[index(neighbor)]) geometry.layers.walls[i] = 1;
            }
        }
        for (std::size_t ri = 0; ri < geometry.rooms.size(); ++ri) {
            auto& room = geometry.rooms[ri]; const auto& r = layout.rooms[ri]; room.reachable = reached[index(room.hub)] != 0;
            if (room.id != geometry.entrance_room) for (int y = r.bounds.y; y < r.bounds.bottom(); y += 2) for (int x = r.bounds.x; x < r.bounds.right(); x += 2) {
                if (!tick()) return false;
                const Tile t{x,y}; const auto i = index(t);
                if (!geometry.movement_reserved[i] && !door_cells[i] && !(t == geometry.entrance_marker) && !(t == geometry.exit_marker))
                    room.spawn_positions.push_back({room.id+":spawn:"+std::to_string(x)+":"+std::to_string(y),t});
            }
            const auto available = static_cast<std::int32_t>(room.spawn_positions.size());
            if (r.capacity_override && *r.capacity_override > available) {
                result.status = error(Outcome::invalid_input,"capacity_exceeds_spawns","Room capacity override exceeds actual valid spawn positions (entrance capacity is zero).",{room.id}, {room.hub}); return false;
            }
            room.capacity = r.capacity_override.value_or(available);
            event("room_reachable",{},room.id,room.hub);
        }
        return true;
    }
};
}
RoutingResult route_corridors(const Project& source,const RoomLayoutSnapshot& layout,const RoutingOptions& options) {
    try { return Router(source,layout,options).run(); }
    catch (const std::bad_alloc&) { RoutingResult result; result.status = error(Outcome::resource_failure,"allocation_failure","Insufficient memory for corridor routing."); return result; }
}
RoutingResult route_corridors(ProjectSession& session,const RoutingOptions& options) {
    if (!session.room_layout_current()) { RoutingResult result; result.status = error(Outcome::stale_result,"room_layout_required","Generate a current room layout before routing corridors."); return result; }
    const auto source = session.project(); const auto layout = session.room_layout(); const auto revision = session.revisions().source;
    auto result = route_corridors(source,*layout,options);
    if (result.ok()) {
        result.status = session.publish_geometry(*result.geometry,revision);
        if (!result.status.ok()) result.geometry.reset();
    }
    return result;
}
} // namespace dungeon_architect

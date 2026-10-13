#include "dungeon_architect/routing.h"
#include "../test_support.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <set>
#include <thread>

namespace da = dungeon_architect;
da::Room fixed(std::string id,da::Rect bounds,da::RoomRole role = da::RoomRole::normal) {
    da::Room r; r.id = std::move(id); r.name = r.id; r.bounds = bounds; r.role = role;
    r.lock_position = r.lock_size = true; return r;
}
da::Project source() {
    auto p = da::make_default_project();
    p.settings.columns = 24; p.settings.rows = 16; p.settings.room_count = 2;
    p.settings.min_room_width = p.settings.min_room_height = 2;
    p.settings.max_room_width = p.settings.max_room_height = 5;
    p.settings.corridor_width = 2; p.allowed_mask.assign(384,1);
    p.rooms = {fixed("a",{2,5,4,4},da::RoomRole::entrance),fixed("b",{18,5,4,4},da::RoomRole::exit)};
    return p;
}
da::RoutingResult route(const da::Project& p) {
    auto generated = da::generate_rooms(p); CHECK(generated.ok());
    return da::route_corridors(p,*generated.layout);
}
void independent_floor(const da::Project& p,const da::GeometrySnapshot& g) {
    const auto cols = p.settings.columns, rows = p.settings.rows;
    auto index = [&](da::Tile t) { return static_cast<std::size_t>(t.y*cols+t.x); };
    std::vector<unsigned> expected(p.allowed_mask.size(),0);
    for (const auto& r : g.rooms) for (int y = r.bounds.y; y < r.bounds.y+r.bounds.height; ++y)
        for (int x = r.bounds.x; x < r.bounds.x+r.bounds.width; ++x) expected[index({x,y})] = 1;
    for (const auto& c : g.corridors) for (auto a : c.path)
        for (int y = a.y; y < a.y+p.settings.corridor_width; ++y) for (int x = a.x; x < a.x+p.settings.corridor_width; ++x) {
            CHECK(x >= 0 && y >= 0 && x < cols && y < rows);
            CHECK(p.allowed_mask[index({x,y})] == 1 && g.layers.occupancy[index({x,y})] == 0);
            expected[index({x,y})] = 1;
        }
    for (std::size_t i = 0; i < expected.size(); ++i) CHECK(expected[i] == g.layers.floor[i]);
    std::vector<da::Tile> stack{g.entrance_marker}; std::set<std::size_t> seen;
    while (!stack.empty()) {
        const auto t = stack.back(); stack.pop_back(); if (!seen.insert(index(t)).second) continue;
        for (const auto delta : std::array<da::Tile,4>{{{-1,0},{0,1},{1,0},{0,-1}}}) {
            const da::Tile n{t.x+delta.x,t.y+delta.y};
            if (n.x >= 0 && n.y >= 0 && n.x < cols && n.y < rows && g.layers.floor[index(n)] && !seen.count(index(n))) stack.push_back(n);
        }
    }
    CHECK(seen.size() == static_cast<std::size_t>(std::count(g.layers.floor.begin(),g.layers.floor.end(),1)));
    for (const auto& room : g.rooms) {
        CHECK(room.reachable && room.capacity <= static_cast<int>(room.spawn_positions.size()));
        for (const auto& spawn : room.spawn_positions) CHECK(!g.movement_reserved[index(spawn.tile)] && seen.count(index(spawn.tile)));
        for (std::size_t i = 0; i < room.spawn_positions.size(); ++i) for (std::size_t j = i+1; j < room.spawn_positions.size(); ++j)
            CHECK(std::max(std::abs(room.spawn_positions[i].tile.x-room.spawn_positions[j].tile.x),std::abs(room.spawn_positions[i].tile.y-room.spawn_positions[j].tile.y)) >= 2);
    }
}
void straight_and_corruption() {
    auto p = source(); const auto layout = *da::generate_rooms(p).layout;
    auto result = da::route_corridors(p,layout); CHECK(result.ok()); const auto& g = *result.geometry;
    independent_floor(p,g); CHECK(da::validate_routed_geometry(p,layout,g).ok());
    CHECK(g.corridors.size() == 1 && g.corridors[0].path.size() == 11);
    CHECK(g.corridors[0].path.front() == da::Tile{6,5} && g.corridors[0].path.back() == da::Tile{16,5});
    CHECK(std::count(g.layers.floor.begin(),g.layers.floor.end(),1) == 56);
    CHECK(g.rooms[0].capacity == 0 && g.rooms[0].spawn_positions.empty()); CHECK(g.rooms[1].capacity == 3);
    da::RoutingOptions quiet; quiet.max_events = 0; auto again = da::route_corridors(p,layout,quiet);
    CHECK(again.ok() && again.events.empty() && again.geometry->layers.floor == g.layers.floor);
    CHECK(again.geometry->corridors[0].path == g.corridors[0].path && again.metrics.work_units == result.metrics.work_units);
    quiet.max_events = 2; again = da::route_corridors(p,layout,quiet); CHECK(again.events.size() == 2 && again.metrics.dropped_events > 0);
    auto bad = g; bad.layers.floor[0] = 1; CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    bad = g; bad.layers.walls[0] = 1; CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    bad = g; bad.corridors[0].path[1].y++; CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    bad = g; bad.doors[0].tiles[0].x++; CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    bad = g; bad.entrance_marker = {-1,-1}; CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    bad = g; bad.rooms[1].capacity++; CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    bad = g; bad.rooms[1].spawn_positions[0].tile = g.exit_marker; CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    bad = g; bad.movement_reserved.assign(bad.movement_reserved.size(),0); CHECK(!da::validate_routed_geometry(p,layout,bad).ok());
    p.rooms[1].bounds.x = 8; result = route(p); CHECK(result.ok()); CHECK(result.geometry->corridors[0].path.size() == 1);
}
void obstacles_and_crossings() {
    auto p = source();
    for (int y = 4; y < 12; ++y) for (int x = 10; x < 14; ++x) p.allowed_mask[static_cast<std::size_t>(y*24+x)] = 0;
    auto result = route(p); CHECK(result.ok()); independent_floor(p,*result.geometry);
    CHECK(result.geometry->corridors[0].path.size() > 11);
    bool turn = false; const auto& path = result.geometry->corridors[0].path;
    for (std::size_t i = 2; i < path.size(); ++i) if (path[i].x-path[i-1].x != path[i-1].x-path[i-2].x || path[i].y-path[i-1].y != path[i-1].y-path[i-2].y) turn = true;
    CHECK(turn);
    p = source();
    for (int y = 0; y < 16; ++y) for (int x = 10; x < 14; ++x) if (y != 7) p.allowed_mask[static_cast<std::size_t>(y*24+x)] = 0;
    result = route(p); CHECK(!result.ok() && !result.geometry && result.status.outcome == da::Outcome::search_exhausted);
    CHECK(result.status.diagnostics[0].code == "corridor_disconnected");
    p.settings.corridor_width = 1; result = route(p); CHECK(result.ok()); independent_floor(p,*result.geometry);
    p = source(); p.settings.corridor_width = 5;
    result = route(p); CHECK(result.status.diagnostics[0].code == "no_door_clearance");
    p = source(); p.settings.rows = 24; p.allowed_mask.assign(576,1); p.settings.room_count = 4;
    p.rooms = {fixed("a",{1,10,4,4}),fixed("b",{19,10,4,4}),fixed("c",{10,1,4,4}),fixed("d",{10,19,4,4})};
    auto layout = *da::generate_rooms(p).layout;
    layout.connections = {{"a","b",true},{"c","d",true},{"a","c",true}};
    CHECK(da::validate_room_layout(p,layout).ok());
    result = da::route_corridors(p,layout); CHECK(result.ok()); independent_floor(p,*result.geometry);
    std::set<std::pair<int,int>> first;
    for (auto a : result.geometry->corridors[0].path) for (int y = a.y; y < a.y+2; ++y) for (int x = a.x; x < a.x+2; ++x) first.emplace(x,y);
    bool crossed = false;
    for (auto a : result.geometry->corridors[1].path) for (int y = a.y; y < a.y+2; ++y) for (int x = a.x; x < a.x+2; ++x) crossed = crossed || first.count({x,y}) != 0;
    CHECK(crossed);
}
void capacities_and_transactions() {
    auto p = source(); const auto layout = *da::generate_rooms(p).layout;
    p.rooms[1].capacity_override = 2; auto result = da::route_corridors(p,layout); CHECK(result.ok() && result.geometry->rooms[1].capacity == 2);
    p.rooms[1].capacity_override = 16; result = da::route_corridors(p,layout); CHECK(result.status.diagnostics[0].code == "capacity_exceeds_spawns" && !result.geometry);
    p = source(); p.settings.max_work_units = 1;
    result = da::route_corridors(p,layout); CHECK(result.status.outcome == da::Outcome::search_exhausted && result.metrics.work_units <= 1);
    p = source(); da::RoutingOptions options; options.cancelled = [] { return true; };
    CHECK(da::route_corridors(p,layout,options).status.outcome == da::Outcome::cancelled);
    int polls = 0; options.cancelled = [&] { return ++polls > 900; };
    result = da::route_corridors(p,layout,options); CHECK(result.status.outcome == da::Outcome::cancelled && !result.geometry);
    p.settings.max_time_ms = 1; options.cancelled = [] { std::this_thread::sleep_for(std::chrono::milliseconds(3)); return false; };
    CHECK(da::route_corridors(p,layout,options).status.diagnostics[0].code == "time_limit");
    da::ProjectSession session; CHECK(session.replace_loaded(source()).ok());
    CHECK(da::route_corridors(session).status.outcome == da::Outcome::stale_result);
    CHECK(da::generate_rooms(session).ok()); CHECK(da::route_corridors(session).ok());
    auto previous = session.geometry(); CHECK(session.geometry_current());
    auto corrupt = *previous; corrupt.layers.floor[0] = 1;
    CHECK(!session.publish_geometry(corrupt,session.revisions().source).ok()); CHECK(session.geometry() == previous);
    options.cancelled = [] { return true; };
    CHECK(da::route_corridors(session,options).status.outcome == da::Outcome::cancelled);
    CHECK(session.geometry() == previous && session.geometry_current());
    auto edit = session.project(); edit.rooms[1].capacity_override = 16; CHECK(session.update(edit).ok());
    CHECK(da::route_corridors(session).status.outcome == da::Outcome::invalid_input); CHECK(session.geometry() == previous);
    edit.rooms[1].capacity_override = 2; edit.rooms[1].name = "Renamed after generation"; CHECK(session.update(edit).ok());
    CHECK(da::route_corridors(session).ok()); CHECK(session.geometry()->rooms[1].capacity == 2);
    previous = session.geometry(); bool changed = false;
    options.cancelled = [&] { if (!changed) { auto next = session.project(); next.name = "Concurrent edit"; CHECK(session.update(next).ok()); changed = true; } return false; };
    CHECK(da::route_corridors(session,options).status.outcome == da::Outcome::stale_result); CHECK(session.geometry() == previous);
    changed = false; options.cancelled = [&] { if (!changed) { CHECK(da::generate_rooms(session).ok()); changed = true; } return false; };
    CHECK(da::route_corridors(session,options).status.outcome == da::Outcome::stale_result); CHECK(session.geometry() == previous);
    edit = session.project(); edit.settings.corridor_width = 5; edit.rooms[1].capacity_override.reset();
    CHECK(session.update(edit).ok()); CHECK(da::generate_rooms(session).ok());
    CHECK(da::route_corridors(session).status.outcome == da::Outcome::search_exhausted);
    CHECK(session.geometry() == previous && !session.geometry_current());
}
int main() {
    try { straight_and_corruption(); obstacles_and_crossings(); capacities_and_transactions(); std::cout << checks << " routing checks passed.\n"; }
    catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}

#include "dungeon_architect/generation.h"
#include "../test_support.h"
#include <algorithm>
#include <chrono>
#include <climits>
#include <set>
#include <sstream>
#include <thread>

namespace da = dungeon_architect;
da::Project source() {
    auto p = da::make_default_project();
    p.settings.columns = 30; p.settings.rows = 24; p.settings.room_count = 6;
    p.settings.min_room_width = p.settings.min_room_height = 2;
    p.settings.max_room_width = p.settings.max_room_height = 5;
    p.settings.max_generation_attempts = 30000;
    p.allowed_mask.assign(720,1); return p;
}
da::Room fixed(std::string id, da::Rect bounds) {
    da::Room r; r.id = std::move(id); r.name = "Fixed"; r.bounds = bounds;
    r.lock_position = r.lock_size = true; return r;
}
std::string fingerprint(const da::RoomLayoutSnapshot& layout) {
    std::ostringstream s;
    for (const auto& r : layout.rooms) s << r.id << ':' << r.bounds.x << ',' << r.bounds.y << ',' << r.bounds.width << ',' << r.bounds.height << ';';
    for (const auto& n : layout.partitions) s << n.id << ':' << n.parent << ',' << n.first_child << ',' << n.second_child << ',' << n.cut << ',' << n.requested_rooms << ';';
    for (const auto& c : layout.connections) s << c.from << '>' << c.to << ';';
    s << layout.terminals.entrance << '/' << layout.terminals.exit;
    return s.str();
}
void independent_checks(const da::Project& p, const da::RoomLayoutSnapshot& layout) {
    CHECK(layout.rooms.size() == static_cast<std::size_t>(p.settings.room_count));
    std::set<std::string> ids;
    std::vector<unsigned> occupied(p.allowed_mask.size(),0);
    for (const auto& r : layout.rooms) {
        CHECK(ids.insert(r.id).second);
        for (int y = r.bounds.y-p.settings.margin; y < r.bounds.y+r.bounds.height+p.settings.margin; ++y)
            for (int x = r.bounds.x-p.settings.margin; x < r.bounds.x+r.bounds.width+p.settings.margin; ++x) {
                CHECK(x >= 0 && y >= 0 && x < p.settings.columns && y < p.settings.rows);
                CHECK(p.allowed_mask[static_cast<std::size_t>(y*p.settings.columns+x)] == 1);
            }
        for (int y = r.bounds.y; y < r.bounds.y+r.bounds.height; ++y)
            for (int x = r.bounds.x; x < r.bounds.x+r.bounds.width; ++x)
                CHECK(++occupied[static_cast<std::size_t>(y*p.settings.columns+x)] == 1);
    }
    for (std::size_t i = 0; i < layout.rooms.size(); ++i) for (std::size_t j = i+1; j < layout.rooms.size(); ++j) {
        const auto& a = layout.rooms[i].bounds; const auto& b = layout.rooms[j].bounds;
        CHECK(a.x+a.width+p.settings.margin <= b.x || b.x+b.width+p.settings.margin <= a.x ||
              a.y+a.height+p.settings.margin <= b.y || b.y+b.height+p.settings.margin <= a.y);
    }
    CHECK(ids.count(layout.terminals.entrance) && ids.count(layout.terminals.exit) && layout.terminals.entrance != layout.terminals.exit);
    for (std::size_t i = 0; i < occupied.size(); ++i) CHECK(occupied[i] == layout.occupancy[i]);
}
void reproducibility_and_shapes() {
    auto p = source();
    auto result = da::generate_rooms(p); CHECK(result.ok());
    const auto again = da::generate_rooms(p); CHECK(again.ok());
    CHECK(fingerprint(*result.layout) == fingerprint(*again.layout));
    CHECK(result.metrics.attempts == again.metrics.attempts && result.metrics.work_units == again.metrics.work_units);
    da::GenerationOptions quiet; quiet.max_events = 0;
    auto no_trace = da::generate_rooms(p,quiet); CHECK(no_trace.ok() && no_trace.events.empty());
    CHECK(fingerprint(*result.layout) == fingerprint(*no_trace.layout));
    CHECK(result.metrics.work_units == no_trace.metrics.work_units);
    quiet.max_events = 2; auto capped = da::generate_rooms(p,quiet);
    CHECK(capped.ok() && capped.events.size() == 2 && capped.metrics.dropped_events > 0);
    CHECK(fingerprint(*result.layout) == fingerprint(*capped.layout));
    quiet.max_events = 4097; CHECK(da::generate_rooms(p,quiet).status.outcome == da::Outcome::unsupported_size);
    bool different = false, rejected = false;
    for (int shape = 0; shape < 4; ++shape) for (std::uint32_t seed = 1; seed <= 16; ++seed) {
        auto candidate = source(); candidate.settings.seed = seed;
        if (shape == 1 || shape == 2) candidate.allowed_mask = *da::make_mask(30,24,shape == 1 ? da::MaskPreset::ellipse : da::MaskPreset::l_shape,{0,0,30,24}).value;
        if (shape == 3) for (int y = 9; y < 15; ++y) for (int x = 12; x < 18; ++x) candidate.allowed_mask[static_cast<std::size_t>(y*30+x)] = 0;
        auto actual = da::generate_rooms(candidate);
        if (!actual.ok()) std::cerr << "Failed shape " << shape << " seed " << seed << " code " << actual.status.diagnostics.front().code << '\n';
        CHECK(actual.ok()); independent_checks(candidate,*actual.layout);
        CHECK(da::validate_room_layout(candidate,*actual.layout).ok());
        different = different || fingerprint(*actual.layout) != fingerprint(*result.layout);
        rejected = rejected || actual.metrics.rejected_candidates > 0;
    }
    CHECK(different && rejected);
    auto dense = source(); dense.settings.room_count = 24; dense.settings.seed = 2;
    auto retried = da::generate_rooms(dense); CHECK(retried.ok() && retried.metrics.backtracks > 0);
    independent_checks(dense,*retried.layout);
    auto defaults = da::generate_rooms(da::make_default_project()); CHECK(defaults.ok());
    CHECK(defaults.layout->rooms.size() == 16);
}
void locks_and_validation() {
    auto p = source();
    p.rooms = {fixed("center",{13,9,4,4}),fixed("entrance",{1,1,3,3})};
    p.rooms[1].role = da::RoomRole::entrance; p.rooms[1].capacity_override = 0;
    p.rooms[0].tags = {"stone","boss"}; p.rooms[0].role = da::RoomRole::boss;
    auto result = da::generate_rooms(p); CHECK(result.ok()); independent_checks(p,*result.layout);
    for (const auto& room : p.rooms) {
        CHECK(std::count_if(result.events.begin(),result.events.end(),[&](const auto& event) {
            return event.kind == "fixed_reserved" && event.room_id == room.id && event.bounds == room.bounds && event.node == -1;
        }) == 1);
        CHECK(std::none_of(result.events.begin(),result.events.end(),[&](const auto& event) {
            return event.kind == "room_placed" && event.room_id == room.id;
        }));
        CHECK(std::none_of(result.layout->partitions.begin(),result.layout->partitions.end(),[&](const auto& node) { return node.room_id == room.id; }));
    }
    const auto center = std::find_if(result.layout->rooms.begin(),result.layout->rooms.end(),[](const auto& r) { return r.id == "center"; });
    CHECK(center != result.layout->rooms.end() && center->bounds == p.rooms[0].bounds && center->tags == p.rooms[0].tags);
    const auto root = result.layout->partitions.front();
    CHECK(root.intersecting_fixed_rooms.size() == 2);
    bool crosses_fixed = false;
    for (std::uint32_t seed = 1; seed <= 16 && !crosses_fixed; ++seed) {
        auto crossing_source = p; crossing_source.settings.seed = seed;
        const auto crossed = da::generate_rooms(crossing_source); CHECK(crossed.ok());
        for (const auto& node : crossed.layout->partitions) {
            if (std::find(node.intersecting_fixed_rooms.begin(),node.intersecting_fixed_rooms.end(),"center") == node.intersecting_fixed_rooms.end()) continue;
            const auto& bounds = p.rooms[0].bounds;
            crosses_fixed = crosses_fixed || (node.axis == da::SplitAxis::x && node.cut > bounds.x && node.cut < bounds.right()) ||
                            (node.axis == da::SplitAxis::y && node.cut > bounds.y && node.cut < bounds.bottom());
        }
        const auto preserved = std::find_if(crossed.layout->rooms.begin(),crossed.layout->rooms.end(),[](const auto& r) { return r.id == "center"; });
        CHECK(preserved != crossed.layout->rooms.end() && preserved->bounds == p.rooms[0].bounds);
    }
    CHECK(crosses_fixed);
    auto reordered = p; std::reverse(reordered.rooms.begin(),reordered.rooms.end());
    CHECK(fingerprint(*da::generate_rooms(reordered).layout) == fingerprint(*result.layout));
    auto bad = *result.layout; bad.rooms.pop_back(); CHECK(!da::validate_room_layout(p,bad).ok());
    bad = *result.layout; bad.occupancy[0] = 1; CHECK(!da::validate_room_layout(p,bad).ok());
    bad = *result.layout; bad.partitions[0].free_tiles++; CHECK(!da::validate_room_layout(p,bad).ok());
    bad = *result.layout; bad.partitions[0].first_child = 0; CHECK(!da::validate_room_layout(p,bad).ok());
    bad = *result.layout; bad.partitions[1].requested_rooms = INT_MAX; CHECK(!da::validate_room_layout(p,bad).ok());
    bad = *result.layout; bad.connections[0].to = bad.connections[0].from; CHECK(!da::validate_room_layout(p,bad).ok());
    bad = *result.layout; bad.terminals.exit = bad.terminals.entrance; CHECK(!da::validate_room_layout(p,bad).ok());
    bad = *result.layout; bad.rooms[0].bounds.width++; CHECK(!da::validate_room_layout(p,bad).ok());
    p = source(); p.settings.room_count = 2;
    p.rooms = {fixed("a",{1,1,3,3}),fixed("b",{10,10,3,3})};
    result = da::generate_rooms(p); CHECK(result.ok());
    CHECK(result.layout->partitions.size() == 1 && result.metrics.attempts == 0 && result.layout->connections.size() == 1);
    p.settings.room_count = 3; result = da::generate_rooms(p); CHECK(result.ok());
    CHECK(result.layout->partitions.size() == 1 && result.layout->partitions[0].requested_rooms == 1);
    p = source(); auto unlocked = fixed("generated-1",{1,1,2,2}); unlocked.lock_position = unlocked.lock_size = false;
    p.rooms = {unlocked}; result = da::generate_rooms(p); CHECK(result.ok());
    CHECK(std::none_of(result.layout->rooms.begin(),result.layout->rooms.end(),[](const auto& r) { return r.id == "generated-1"; }));
}
void limits_and_publication() {
    auto p = source(); p.settings.max_generation_attempts = 1;
    auto result = da::generate_rooms(p); CHECK(!result.ok() && !result.layout && result.status.outcome == da::Outcome::search_exhausted);
    CHECK(result.metrics.attempts == 1);
    p = source(); p.settings.max_work_units = 1;
    result = da::generate_rooms(p); CHECK(result.status.outcome == da::Outcome::search_exhausted && result.metrics.work_units <= 1);
    p = source(); p.settings.max_work_units = -1; CHECK(da::generate_rooms(p).status.outcome == da::Outcome::invalid_input);
    p = source(); p.settings.room_count = 200; CHECK(da::generate_rooms(p).status.outcome == da::Outcome::invalid_input);
    p = source(); p.settings.columns = p.settings.rows = 8; p.settings.room_count = 2;
    p.settings.max_room_width = p.settings.max_room_height = 2; p.settings.margin = 0;
    p.allowed_mask.assign(64,0);
    for (int y = 1; y <= 3; ++y) for (int x = 1; x <= 3; ++x) p.allowed_mask[static_cast<std::size_t>(y*8+x)] = 1;
    result = da::generate_rooms(p); CHECK(result.status.outcome == da::Outcome::search_exhausted && !result.layout);
    CHECK(result.status.diagnostics.size() > 1);
    p = source(); da::GenerationOptions options;
    options.cancelled = [] { return true; };
    CHECK(da::generate_rooms(p,options).status.outcome == da::Outcome::cancelled);
    int polls = 0; options.cancelled = [&] { return ++polls > 750; };
    result = da::generate_rooms(p,options); CHECK(result.status.outcome == da::Outcome::cancelled && !result.layout);
    p.settings.max_time_ms = 1; options.cancelled = [] { std::this_thread::sleep_for(std::chrono::milliseconds(3)); return false; };
    result = da::generate_rooms(p,options); CHECK(result.status.diagnostics.front().code == "time_limit");
    da::ProjectSession session; CHECK(session.replace_loaded(source()).ok());
    result = da::generate_rooms(session); CHECK(result.ok() && session.room_layout_current());
    const auto previous = session.room_layout(); const auto revisions = session.revisions();
    CHECK(!session.geometry_current() && !session.allocation_current());
    options.cancelled = [] { return true; };
    CHECK(da::generate_rooms(session,options).status.outcome == da::Outcome::cancelled);
    CHECK(session.room_layout() == previous && session.room_layout_current() && session.revisions().source == revisions.source);
    auto corrupt = *previous; corrupt.rooms.clear();
    CHECK(!session.publish_room_layout(corrupt,revisions.source).ok()); CHECK(session.room_layout() == previous);
    bool modified = false; options.cancelled = [&] {
        if (!modified) { auto edit = session.project(); edit.name = "Changed while generating"; CHECK(session.update(edit).ok()); modified = true; }
        return false;
    };
    result = da::generate_rooms(session,options); CHECK(result.status.outcome == da::Outcome::stale_result && !result.layout);
    CHECK(session.room_layout() == previous && session.room_layout_current());
    auto edit = session.project(); edit.settings.max_generation_attempts = 1; CHECK(session.update(edit).ok());
    result = da::generate_rooms(session); CHECK(result.status.outcome == da::Outcome::search_exhausted);
    CHECK(session.room_layout() == previous && !session.room_layout_current());
    CHECK(session.replace_loaded(source()).ok()); CHECK(da::generate_rooms(session).ok());
    da::GeometrySnapshot geometry; geometry.id = "floor"; geometry.geometry_revision = session.revisions().geometry;
    CHECK(!session.publish_geometry(geometry,session.revisions().source).ok());
    geometry.room_layout_id = session.room_layout()->id;
    CHECK(!session.publish_geometry(geometry,session.revisions().source).ok()); // phase 05 rejects incomplete floor data
}
int main() {
    try { reproducibility_and_shapes(); locks_and_validation(); limits_and_publication(); std::cout << checks << " BSP checks passed.\n"; }
    catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}

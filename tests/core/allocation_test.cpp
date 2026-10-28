#include "dungeon_architect/allocation.h"
#include "../test_support.h"
#include <algorithm>
#include <chrono>
#include <functional>
#include <random>
#include <set>
#include <thread>

namespace da = dungeon_architect;
da::Pack pack(std::string id,std::int64_t slots = 1,std::int64_t threat = 1,std::int64_t score = 1) {
    da::Pack p; p.id = std::move(id); p.name = p.id; p.slots = slots; p.threat = threat; p.score = score; return p;
}
da::AllocationInput fixture(int count = 3) {
    da::AllocationInput in; in.geometry_id = "test-floor"; in.settings.columns = in.settings.rows = 512;
    for (int i = 0; i < count; ++i) {
        da::AllocationRoom r; r.room.id = "room-"+std::to_string(i); r.room.name = r.room.id;
        r.room.bounds = {(i%32)*16,(i/32)*16,12,12}; r.reachable = true; r.capacity = 3;
        r.room.tags = {"stone"};
        for (int k = 0; k < 6; ++k) r.spawns.push_back({r.room.id+"-spawn-"+std::to_string(k),{r.room.bounds.x+2*k,r.room.bounds.y}});
        in.rooms.push_back(r);
    }
    return in;
}
std::vector<std::string> selected(const da::AllocationSnapshot& a) {
    std::vector<std::string> ids; for (const auto& assignment : a.assignments) ids.push_back(assignment.pack_id);
    std::sort(ids.begin(),ids.end()); return ids;
}
struct Oracle { std::int64_t score = 0, threat = 0, slots = 0; std::vector<std::string> ids; };
Oracle exhaustive(const da::AllocationInput& in) {
    Oracle best; std::vector<int> used(in.rooms.size(),0); std::vector<std::string> chosen;
    // Enumerate (unselected or room) for EACH pack, independently of bitmask DP.
    std::function<void(std::size_t,std::int64_t,std::int64_t,std::int64_t)> visit;
    visit = [&](std::size_t k,std::int64_t score,std::int64_t threat,std::int64_t slots) {
        if (threat > in.settings.threat_budget) return;
        if (k == in.packs.size()) {
            auto ids = chosen; std::sort(ids.begin(),ids.end());
            if (score > best.score || (score == best.score && std::tie(threat,slots,ids) < std::tie(best.threat,best.slots,best.ids))) best = {score,threat,slots,ids};
            return;
        }
        visit(k+1,score,threat,slots); const auto& p = in.packs[k]; if (!p.active) return;
        for (std::size_t r = 0; r < in.rooms.size(); ++r) {
            const auto& room = in.rooms[r];
            if (!room.reachable || room.room.role == da::RoomRole::entrance || used[r]+p.slots > room.capacity ||
                room.room.bounds.width < p.min_room_width || room.room.bounds.height < p.min_room_height) continue;
            if (!p.allowed_roles.empty() && std::count(p.allowed_roles.begin(),p.allowed_roles.end(),room.room.role) == 0) continue;
            bool tags = true; for (const auto& tag : p.required_tags) if (std::count(room.room.tags.begin(),room.room.tags.end(),tag) == 0) tags = false;
            if (!tags) continue;
            used[r] += static_cast<int>(p.slots); chosen.push_back(p.id);
            visit(k+1,score+p.score,threat+p.threat,slots+p.slots);
            chosen.pop_back(); used[r] -= static_cast<int>(p.slots);
        }
    };
    visit(0,0,0,0); return best;
}
void compare(const da::AllocationInput& in) {
    const auto expected = exhaustive(in); const auto actual = da::allocate_encounters(in);
    CHECK(actual.ok()); CHECK(da::validate_allocation_result(in,*actual.allocation).ok());
    CHECK(actual.allocation->total_score == expected.score && actual.allocation->total_threat == expected.threat && actual.allocation->total_slots == expected.slots);
    CHECK(selected(*actual.allocation) == expected.ids);
    CHECK(actual.metrics.work_units <= actual.metrics.estimated_work);
    CHECK(actual.allocation->actors.size() == static_cast<std::size_t>(expected.slots));
}
void oracle_matrix() {
    std::mt19937 random(60123);
    for (int trial = 0; trial < 400; ++trial) {
        auto in = fixture(static_cast<int>(random()%5)); in.settings.threat_budget = random()%9;
        for (auto& r : in.rooms) {
            r.capacity = static_cast<int>(random()%7); r.reachable = random()%4 != 0;
            r.room.role = random()%3 == 0 ? da::RoomRole::boss : da::RoomRole::normal;
            if (random()%2) r.room.tags.clear();
        }
        const auto n = random()%7;
        for (unsigned k = 0; k < n; ++k) {
            auto p = pack("pack-"+std::to_string(k),1+random()%5,random()%5,random()%8);
            if (random()%4 == 0) p.required_tags = {"stone"};
            if (random()%4 == 0) p.allowed_roles = {da::RoomRole::boss};
            if (random()%6 == 0) p.min_room_width = 13;
            if (random()%8 == 0) p.active = false;
            in.packs.push_back(p);
        }
        compare(in);
        const auto a = da::allocate_encounters(in);
        std::reverse(in.packs.begin(),in.packs.end()); std::reverse(in.rooms.begin(),in.rooms.end());
        for (auto& r : in.rooms) std::reverse(r.spawns.begin(),r.spawns.end());
        const auto b = da::allocate_encounters(in); CHECK(b.ok());
        CHECK(a.allocation->assignments.size() == b.allocation->assignments.size());
        for (std::size_t i = 0; i < a.allocation->assignments.size(); ++i)
            CHECK(a.allocation->assignments[i].pack_id == b.allocation->assignments[i].pack_id && a.allocation->assignments[i].room_id == b.allocation->assignments[i].room_id);
        CHECK(a.allocation->actors.size() == b.allocation->actors.size());
        for (std::size_t i = 0; i < a.allocation->actors.size(); ++i) CHECK(a.allocation->actors[i].spawn_id == b.allocation->actors[i].spawn_id);
    }
}
void edge_cases() {
    auto in = fixture(1); in.packs = {pack("a",2,0,8),pack("b",1,0,0),pack("c",1,1,20)};
    in.settings.threat_budget = 0; compare(in); CHECK(selected(*da::allocate_encounters(in).allocation) == std::vector<std::string>{"a"});
    in.packs = {pack("a",2,1,8),pack("b",1,2,8),pack("c",1,1,8)}; in.rooms[0].capacity = 2;
    in.settings.threat_budget = 1; compare(in); CHECK(selected(*da::allocate_encounters(in).allocation) == std::vector<std::string>{"c"});
    in.packs = {pack("b"),pack("a")}; in.rooms[0].capacity = 1; compare(in);
    CHECK(selected(*da::allocate_encounters(in).allocation) == std::vector<std::string>{"a"});
    in = fixture(2); in.packs = {pack("copy-1"),pack("copy-2")}; compare(in);
    auto result = da::allocate_encounters(in); CHECK(result.allocation->assignments.size() == 2);
    CHECK(result.allocation->assignments[0].room_id == "room-0" && result.allocation->assignments[1].room_id == "room-0");
    in.rooms[0].capacity = in.rooms[1].capacity = 1; result = da::allocate_encounters(in);
    // For M=3, last-room subset 1 precedes subset 2 under contract v1.
    CHECK(result.allocation->assignments[0].pack_id == "copy-2" && result.allocation->assignments[0].room_id == "room-0");
    CHECK(result.allocation->assignments[1].pack_id == "copy-1" && result.allocation->assignments[1].room_id == "room-1");
    in.rooms[0].room.role = da::RoomRole::entrance; in.rooms[0].capacity = 0; in.rooms[1].reachable = false; compare(in);
    CHECK(da::allocate_encounters(in).allocation->assignments.empty());
    in = fixture(1); in.packs = {pack("huge",7),pack("normal",1,101,100),pack("tag"),pack("size")};
    in.packs[2].required_tags = {"missing"}; in.packs[3].min_room_height = 13;
    result = da::allocate_encounters(in); CHECK(result.ok()); CHECK(result.allocation->unused.size() == 4);
    CHECK(result.allocation->unused[0].reason == "oversized" && result.allocation->unused[1].reason == "unselected_by_optimum");
    compare(in);
    in = fixture(); in.packs = {pack("huge-score",1,0,std::numeric_limits<std::int64_t>::max())}; compare(in);
    in.packs.push_back(pack("overflow")); CHECK(da::allocate_encounters(in).status.outcome == da::Outcome::invalid_input);
    in = fixture(); in.packs = {pack("a",std::numeric_limits<std::int64_t>::max(),0,1)}; compare(in);
    in.packs.push_back(pack("b")); CHECK(!da::allocate_encounters(in).ok());
    in = fixture(); in.packs = {pack("a",1,std::numeric_limits<std::int64_t>::max(),1)}; in.settings.threat_budget = std::numeric_limits<std::int64_t>::max(); compare(in);
    in.packs.push_back(pack("b")); CHECK(!da::allocate_encounters(in).ok());
}
void corruption() {
    auto in = fixture(); in.packs = {pack("a",2),pack("b",1)}; const auto good = *da::allocate_encounters(in).allocation;
    auto bad = good; bad.total_score++; CHECK(!da::validate_allocation_result(in,bad).ok());
    bad = good; bad.assignments.push_back(bad.assignments[0]); CHECK(!da::validate_allocation_result(in,bad).ok());
    bad = good; bad.actors[1] = bad.actors[0]; CHECK(!da::validate_allocation_result(in,bad).ok());
    bad = good; bad.actors[0].tile.x++; CHECK(!da::validate_allocation_result(in,bad).ok());
    bad = good; bad.actors.pop_back(); CHECK(!da::validate_allocation_result(in,bad).ok());
    bad = good; bad.assignments[0].room_id = "missing"; CHECK(!da::validate_allocation_result(in,bad).ok());
    bad = good; bad.geometry_id = "other"; CHECK(!da::validate_allocation_result(in,bad).ok());
    bad = good; bad.unused.push_back({"a","oversized"}); CHECK(!da::validate_allocation_result(in,bad).ok());
    in.rooms[0].capacity = 1; CHECK(!da::validate_allocation_result(in,good).ok());
    in = fixture(); in.packs = {pack("a",99)}; bad = *da::allocate_encounters(in).allocation;
    bad.unused[0].reason = "unselected_by_optimum"; CHECK(!da::validate_allocation_result(in,bad).ok());
    bad.unused.clear(); CHECK(!da::validate_allocation_result(in,bad).ok());
    in.rooms[0].spawns[1] = in.rooms[0].spawns[0]; CHECK(!da::allocate_encounters(in).ok());
    in = fixture(); in.rooms[0].spawns[1].tile.x = 1; CHECK(!da::allocate_encounters(in).ok());
    in = fixture(); in.rooms[0].room.id = "invalid id"; CHECK(!da::allocate_encounters(in).ok());
}
void limits_and_traces() {
    auto in = fixture(20); for (int k = 0; k < 14; ++k) in.packs.push_back(pack("p"+std::to_string(k)));
    auto r = da::allocate_encounters(in); CHECK(r.ok() && r.allocation->assignments.size() == 14);
    CHECK(r.metrics.estimated_work < 100000000 && r.metrics.estimated_bytes < 2000000);
    da::AllocationOptions options; options.max_events = 0;
    auto quiet = da::allocate_encounters(in,options); CHECK(quiet.ok() && quiet.events.empty() && quiet.metrics.dropped_events > 0);
    CHECK(quiet.metrics.work_units == r.metrics.work_units && selected(*quiet.allocation) == selected(*r.allocation));
    options.max_events = 2; CHECK(da::allocate_encounters(in,options).events.size() == 2);
    options.max_events = 4097; CHECK(da::allocate_encounters(in,options).status.outcome == da::Outcome::invalid_input);
    options = {}; options.detailed_trace = true; CHECK(da::allocate_encounters(in,options).status.outcome == da::Outcome::unsupported_size);
    in.packs.push_back(pack("p14")); CHECK(da::allocate_encounters(in).status.outcome == da::Outcome::unsupported_size);
    in.packs.back().active = false; CHECK(da::allocate_encounters(in).ok());
    in.settings.max_work_units = 1; r = da::allocate_encounters(in); CHECK(!r.allocation && r.status.diagnostics[0].code == "allocation_work_estimate");
    in = fixture(1024); for (int k = 0; k < 14; ++k) in.packs.push_back(pack("p"+std::to_string(k)));
    in.settings.max_work_units = std::numeric_limits<std::int64_t>::max();
    // 1024 rows ~48 MiB is supported; add zero-overlap rooms to cross 64 MiB.
    for (int i = 0; i < 512; ++i) {
        da::AllocationRoom room; room.room.id = "extra-"+std::to_string(i); room.room.bounds = {(i%32)*16,(i/32)*16+2,1,1};
        room.capacity = 1; room.reachable = true; room.spawns = {{room.room.id+"-spawn",{room.room.bounds.x,room.room.bounds.y}}}; in.rooms.push_back(room);
    }
    r = da::allocate_encounters(in); CHECK(r.status.diagnostics[0].code == "allocation_memory_estimate" && !r.allocation);
    in = fixture(3); for (int k = 0; k < 6; ++k) in.packs.push_back(pack("p"+std::to_string(k)));
    options = {}; options.detailed_trace = true; r = da::allocate_encounters(in,options); CHECK(r.ok());
    CHECK(std::any_of(r.events.begin(),r.events.end(),[](const da::AllocationEvent& e) { return e.kind == "state_feasible"; }));
    options = {}; options.cancelled = [] { return true; }; r = da::allocate_encounters(in,options); CHECK(r.status.outcome == da::Outcome::cancelled && !r.allocation);
    int polls = 0; options.cancelled = [&] { return ++polls >= 4; }; r = da::allocate_encounters(in,options); CHECK(r.status.outcome == da::Outcome::cancelled && !r.allocation);
    in.settings.max_time_ms = 1; options.cancelled = [] { std::this_thread::sleep_for(std::chrono::milliseconds(3)); return false; };
    r = da::allocate_encounters(in,options); CHECK(r.status.diagnostics[0].code == "allocation_deadline" && !r.allocation);
}
da::Project source() {
    auto p = da::make_default_project(); p.settings.columns = 24; p.settings.rows = 16; p.allowed_mask.assign(384,1);
    p.settings.room_count = 2; p.settings.min_room_width = p.settings.min_room_height = 2;
    p.settings.max_room_width = p.settings.max_room_height = 5;
    da::Room a; a.id = a.name = "entry"; a.bounds = {2,5,4,4}; a.role = da::RoomRole::entrance; a.lock_position = a.lock_size = true;
    auto b = a; b.id = b.name = "exit"; b.bounds.x = 18; b.role = da::RoomRole::exit; b.tags = {"stone"}; p.rooms = {a,b};
    p.packs = {pack("a",2,2,9),pack("b",1,1,5)}; p.settings.threat_budget = 2; return p;
}
void teaching_trace_semantics() {
    auto in = fixture(2); in.rooms[0].capacity = 1; in.rooms[1].capacity = 2;
    in.packs = {pack("a",2,2,7),pack("b",1,1,4),pack("c",1,1,3)};
    in.settings.threat_budget = 3;
    da::AllocationOptions detailed; detailed.detailed_trace = true; detailed.max_events = 4096;
    const auto traced = da::allocate_encounters(in,detailed); CHECK(traced.ok());
    std::set<std::pair<std::string,std::string>> reconstructed;
    std::size_t state_events = 0, candidate_events = 0;
    for (const auto& e : traced.events) {
        if (e.kind.find("candidate_") == 0) {
            ++candidate_events;
            CHECK(e.mask < 8 && (e.subset & ~e.mask) == 0);
            const auto room = std::find_if(in.rooms.begin(),in.rooms.end(),[&](const auto& r) { return r.room.id == e.room_id; });
            CHECK(room != in.rooms.end());
            auto prior = in; prior.rooms.erase(prior.rooms.begin()+(room-in.rooms.begin()),prior.rooms.end());
            prior.packs.clear(); prior.settings.threat_budget = 100;
            std::int64_t slots = 0;
            for (std::size_t k = 0; k < in.packs.size(); ++k) {
                if ((e.mask^e.subset) & (1U<<k)) { auto p=in.packs[k]; p.score=1; prior.packs.push_back(p); }
                if (e.subset & (1U<<k)) slots += in.packs[k].slots;
            }
            const bool feasible = slots <= room->capacity && exhaustive(prior).score == static_cast<std::int64_t>(prior.packs.size());
            CHECK((e.kind == "candidate_feasible" || e.kind == "candidate_empty_feasible") == feasible);
        }
        if (e.kind == "state_feasible" || e.kind == "state_infeasible") {
            ++state_events;
            CHECK(e.mask < 8 && (e.subset & ~e.mask) == 0);
            const auto room = std::find_if(in.rooms.begin(),in.rooms.end(),[&](const auto& r) { return r.room.id == e.room_id; });
            CHECK(room != in.rooms.end());
            auto prefix = in; prefix.rooms.erase(prefix.rooms.begin()+(room-in.rooms.begin())+1,prefix.rooms.end());
            prefix.packs.clear(); prefix.settings.threat_budget = 100;
            for (std::size_t k = 0; k < in.packs.size(); ++k) if (e.mask & (1U<<k)) {
                auto p = in.packs[k]; p.score = 1; prefix.packs.push_back(p);
            }
            // Exhaustive per-pack placement is independent of the native mask DP.
            const bool feasible = exhaustive(prefix).score == static_cast<std::int64_t>(prefix.packs.size());
            CHECK((e.kind == "state_feasible") == feasible);
        }
        if (e.kind == "reconstruct") for (std::size_t k = 0; k < in.packs.size(); ++k)
            if (e.subset & (1U<<k)) CHECK(reconstructed.emplace(in.packs[k].id,e.room_id).second);
    }
    CHECK(state_events == 16);
    CHECK(candidate_events == traced.metrics.transitions);
    CHECK(traced.metrics.allocated_table_bytes > 0 && traced.metrics.allocated_table_bytes <= traced.metrics.estimated_bytes);
    std::set<std::pair<std::string,std::string>> assignments;
    for (const auto& a : traced.allocation->assignments) assignments.emplace(a.pack_id,a.room_id);
    CHECK(reconstructed == assignments);
    for (const std::size_t cap : {0U,1U,7U,4096U}) {
        auto options = detailed; options.max_events = cap;
        const auto result = da::allocate_encounters(in,options); CHECK(result.ok());
        CHECK(result.events.size() <= cap);
        CHECK(result.allocation->total_score == traced.allocation->total_score);
        CHECK(selected(*result.allocation) == selected(*traced.allocation));
        CHECK(result.allocation->assignments.size() == traced.allocation->assignments.size());
        for (std::size_t k = 0; k < result.allocation->assignments.size(); ++k)
            CHECK(result.allocation->assignments[k].room_id == traced.allocation->assignments[k].room_id);
    }
}
void session_edits() {
    da::ProjectSession session; CHECK(session.update(source()).ok());
    CHECK(da::allocate_encounters(session).status.outcome == da::Outcome::stale_result);
    CHECK(da::generate_rooms(session).ok() && da::route_corridors(session).ok()); const auto geometry = session.geometry();
    auto result = da::allocate_encounters(session); CHECK(result.ok() && session.allocation_current()); CHECK(result.allocation->total_score == 9);
    auto bad = *session.allocation(); bad.actors[0].tile.x++; CHECK(!session.publish_allocation(bad,session.revisions().source).ok());
    const auto previous = session.allocation();
    auto p = session.project(); p.settings.threat_budget = 3; CHECK(session.update(p).ok()); CHECK(session.geometry_current() && !session.allocation_current());
    result = da::allocate_encounters(session); CHECK(result.ok() && result.allocation->total_score == 14 && session.geometry() == geometry);
    p = session.project(); p.rooms[1].capacity_override = 1; CHECK(session.update(p).ok());
    result = da::allocate_encounters(session); CHECK(result.ok() && result.allocation->total_score == 5 && session.geometry() == geometry);
    p = session.project(); p.rooms[1].capacity_override = 4; CHECK(session.update(p).ok()); const auto retained = session.allocation();
    result = da::allocate_encounters(session); CHECK(!result.ok() && result.status.diagnostics[0].code == "capacity_exceeds_spawns" && session.allocation() == retained);
    p.rooms[1].capacity_override.reset(); p.packs[0].required_tags = {"lava"}; CHECK(session.update(p).ok());
    result = da::allocate_encounters(session); CHECK(result.ok() && result.allocation->total_score == 5 && session.geometry() == geometry);
    p.rooms[1].tags.push_back("lava"); CHECK(session.update(p).ok()); CHECK(da::allocate_encounters(session).allocation->total_score == 14);
    const auto last = session.allocation(); da::AllocationOptions options; options.cancelled = [] { return true; };
    result = da::allocate_encounters(session,options); CHECK(result.status.outcome == da::Outcome::cancelled && session.allocation() == last);
    bool edited = false; int callbacks = 0; options.cancelled = [&] {
        if (++callbacks > 1 && !edited) { edited = true; auto edit = session.project(); edit.settings.threat_budget = 0; CHECK(session.update(edit).ok()); } return false;
    };
    result = da::allocate_encounters(session,options); CHECK(result.status.outcome == da::Outcome::stale_result && !result.allocation && session.allocation() == last);
    edited = false; callbacks = 0; options.cancelled = [&] { if (++callbacks > 1 && !edited) { edited = true; CHECK(da::route_corridors(session).ok()); } return false; };
    result = da::allocate_encounters(session,options); CHECK(result.status.outcome == da::Outcome::stale_result && !result.allocation && session.allocation() == last);
    CHECK(previous->total_score == 9);
    p = session.project(); p.settings.threat_budget = 3; p.packs[0].threat = 4; CHECK(session.update(p).ok());
    const auto reused = session.geometry(); result = da::allocate_encounters(session);
    CHECK(result.ok() && result.allocation->total_score == 5 && session.geometry() == reused);
    p.packs[0].threat = 2; CHECK(session.update(p).ok()); result = da::allocate_encounters(session);
    CHECK(result.ok() && result.allocation->total_score == 14 && session.geometry() == reused);
}
int main() {
    try { oracle_matrix(); edge_cases(); corruption(); limits_and_traces(); teaching_trace_semantics(); session_edits(); std::cout << checks << " allocation checks passed\n"; return 0; }
    catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}

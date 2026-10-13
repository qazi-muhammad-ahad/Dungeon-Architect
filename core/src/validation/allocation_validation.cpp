#include "dungeon_architect/allocation.h"
#include <algorithm>
#include <map>
#include <set>

namespace dungeon_architect {
namespace {
Status invalid(const char* code,const char* message) {
    return failure(Outcome::invalid_input,code,"/allocation",message,"Discard this allocation and retain the previous valid result.");
}
// Separate from the DP's bit-mask feasibility construction.
bool permits(const Pack& pack,const AllocationRoom& room) {
    if (!room.reachable || room.capacity == 0 || room.room.role == RoomRole::entrance ||
        pack.min_room_width > room.room.bounds.width || pack.min_room_height > room.room.bounds.height) return false;
    if (!pack.allowed_roles.empty()) {
        bool matched = false; for (auto role : pack.allowed_roles) if (role == room.room.role) matched = true;
        if (!matched) return false;
    }
    for (const auto& tag : pack.required_tags) {
        bool matched = false; for (const auto& present : room.room.tags) if (tag == present) matched = true;
        if (!matched) return false;
    }
    return true;
}
}
Status validate_allocation_result(const AllocationInput& input,const AllocationSnapshot& result) {
    auto status = validate_allocation_input(input); if (!status.ok()) return status;
    if (result.id.empty() || result.geometry_id != input.geometry_id || result.geometry_revision != input.geometry_revision ||
        result.allocation_revision != input.allocation_revision)
        return invalid("allocation_dependency","Allocation snapshot does not match its input dependencies.");
    if (result.assignments.size() > input.packs.size() || result.unused.size() > input.packs.size() || result.actors.size() > limits::max_cells)
        return invalid("allocation_size","Result records exceed the bounded input inventory/canvas.");
    std::map<PackId,const Pack*> packs; std::map<RoomId,const AllocationRoom*> rooms;
    for (const auto& p : input.packs) if (p.active) packs.emplace(p.id,&p);
    for (const auto& r : input.rooms) rooms.emplace(r.room.id,&r);
    std::map<PackId,RoomId> assigned; std::map<RoomId,std::int64_t> demands;
    std::int64_t slots = 0,threat = 0,score = 0;
    for (const auto& a : result.assignments) {
        const auto p = packs.find(a.pack_id); const auto r = rooms.find(a.room_id);
        if (p == packs.end() || r == rooms.end() || !assigned.emplace(a.pack_id,a.room_id).second)
            return invalid("allocation_assignment","Assignments require distinct active packs and existing rooms.");
        if (!permits(*p->second,*r->second)) return invalid("allocation_compatibility","A pack is assigned to an ineligible or incompatible room.");
        if (!checked_add(demands[a.room_id],p->second->slots,demands[a.room_id]) || demands[a.room_id] > r->second->capacity)
            return invalid("allocation_capacity","Assigned slot demand exceeds room capacity.");
        if (!checked_add(slots,p->second->slots,slots) || !checked_add(threat,p->second->threat,threat) || !checked_add(score,p->second->score,score))
            return invalid("allocation_totals","Assignment totals overflow signed 64-bit storage.");
    }
    if (slots != result.total_slots || threat != result.total_threat || score != result.total_score || threat > input.settings.threat_budget)
        return invalid("allocation_totals","Reported totals or global threat budget do not match the actual assignments.");
    std::map<SpawnId,std::pair<RoomId,Tile>> valid_spawns;
    for (const auto& r : input.rooms) for (const auto& s : r.spawns) valid_spawns.emplace(s.id,std::make_pair(r.room.id,s.tile));
    std::map<PackId,std::int64_t> actors; std::set<SpawnId> used; std::set<std::pair<int,int>> cells;
    for (const auto& a : result.actors) {
        const auto assignment = assigned.find(a.pack_id); const auto spawn = valid_spawns.find(a.spawn_id);
        if (assignment == assigned.end() || assignment->second != a.room_id || spawn == valid_spawns.end() ||
            spawn->second.first != a.room_id || !(spawn->second.second == a.tile) || !used.insert(a.spawn_id).second || !cells.emplace(a.tile.x,a.tile.y).second)
            return invalid("allocation_actor","Actor is duplicated, unassigned, or outside its room's legal spawn cells.");
        ++actors[a.pack_id];
    }
    for (const auto& entry : assigned) if (actors[entry.first] != packs.at(entry.first)->slots)
        return invalid("allocation_actor_count","Each selected pack must place exactly its slot demand in actors.");
    std::set<PackId> unused;
    for (const auto& u : result.unused) {
        const auto p = packs.find(u.pack_id);
        if (p == packs.end() || assigned.count(u.pack_id) || !unused.insert(u.pack_id).second)
            return invalid("allocation_unused","Unused inventory must contain each unselected active pack exactly once.");
        bool compatible = false, fits = false;
        for (const auto& r : input.rooms) if (permits(*p->second,r)) {
            compatible = true; if (p->second->slots <= r.capacity) fits = true;
        }
        const std::string reason = fits ? "unselected_by_optimum" : compatible ? "oversized" : "no_compatible_eligible_room";
        if (u.reason != reason) return invalid("allocation_unused_reason","Unused-pack explanation overstates or misrepresents its intrinsic feasibility.");
    }
    if (assigned.size()+unused.size() != packs.size()) return invalid("allocation_inventory","Active inventory is missing from assignment/unused records.");
    return {};
}
} // namespace dungeon_architect

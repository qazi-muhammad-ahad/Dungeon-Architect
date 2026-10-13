#include "dungeon_architect/allocation.h"
#include <algorithm>
#include <map>
#include <set>

namespace dungeon_architect {
namespace {
bool identifier(const std::string& value) {
    if (value.empty() || value.size() > limits::max_id_bytes) return false;
    return std::all_of(value.begin(),value.end(),[](unsigned char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == ':';
    });
}
Status bad(const char* code, const char* message) {
    return failure(Outcome::invalid_input,code,"/allocation_input",message,"Correct the input or regenerate valid walkable geometry.");
}
}
Status validate_allocation_input(const AllocationInput& in) {
    auto p = make_default_project(); p.packs = in.packs;
    p.settings.threat_budget = in.settings.threat_budget;
    p.settings.max_work_units = in.settings.max_work_units; p.settings.max_time_ms = in.settings.max_time_ms;
    auto status = validate_allocation_workload(p); if (!status.ok()) return status;
    if (in.geometry_id.empty() || in.settings.columns < 1 || in.settings.rows < 1 ||
        in.settings.columns > limits::max_axis || in.settings.rows > limits::max_axis || in.rooms.size() > limits::max_records)
        return bad("allocation_shape","Missing geometry identity or unsupported room/canvas storage.");
    std::set<RoomId> ids; std::set<SpawnId> spawn_ids;
    std::set<std::pair<int,int>> cells; std::size_t spawn_count = 0;
    for (const auto& r : in.rooms) {
        const auto& room = r.room;
        if (!identifier(room.id) || !ids.insert(room.id).second ||
            !room.bounds.inside(in.settings.columns,in.settings.rows) || room.tags.size() > limits::max_tags ||
            (room.role != RoomRole::normal && room.role != RoomRole::entrance && room.role != RoomRole::exit && room.role != RoomRole::boss))
            return bad("allocation_room","Room IDs, bounds, roles or tags are invalid.");
        std::set<std::string> tags;
        for (const auto& tag : room.tags) if (!identifier(tag) || !tags.insert(tag).second)
            return bad("allocation_tags","Room tags must be valid and unique.");
        if (r.spawns.size() > limits::max_cells - spawn_count) return bad("allocation_spawns","Too many spawn positions.");
        spawn_count += r.spawns.size();
        if (r.capacity < 0 || static_cast<std::size_t>(r.capacity) > r.spawns.size() || (room.role == RoomRole::entrance && r.capacity != 0))
            return bad("allocation_capacity","Capacity must fit valid spawn positions; entrance capacity must be zero.");
        std::set<std::pair<int,int>> local;
        for (const auto& s : r.spawns) {
            if (s.id.empty() || s.id.size() > limits::max_text_bytes || !valid_utf8(s.id) || !spawn_ids.insert(s.id).second ||
                !room.bounds.contains(s.tile) || !cells.emplace(s.tile.x,s.tile.y).second)
                return bad("allocation_spawn","Spawn IDs and cells must be unique and lie inside their room.");
            for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx)
                if (local.count({s.tile.x+dx,s.tile.y+dy})) return bad("allocation_spacing","Spawn cells within a room must be spaced at least two tiles apart.");
            local.emplace(s.tile.x,s.tile.y);
        }
    }
    return {};
}
Result<AllocationInput> prepare_allocation(const Project& source,const RoomLayoutSnapshot& layout,const GeometrySnapshot& geometry) {
    auto status = validate_allocation_workload(source); if (!status.ok()) return {status,{}};
    // Capacity is allocation metadata. Refresh it in a validation copy, preserving
    // the accepted floor snapshot and its original capacity values.
    auto refreshed = geometry;
    for (auto& placed : refreshed.rooms) {
        const auto r = std::find_if(layout.rooms.begin(),layout.rooms.end(),[&](const Room& room) { return room.id == placed.id; });
        if (r == layout.rooms.end()) return {bad("allocation_room","Geometry references a missing layout room."),{}};
        const auto current = std::find_if(source.rooms.begin(),source.rooms.end(),[&](const Room& room) { return room.id == placed.id; });
        const auto override_value = current == source.rooms.end() ? r->capacity_override : current->capacity_override;
        if (placed.spawn_positions.size() > limits::max_cells) return {bad("allocation_spawns","Too many spawn positions."),{}};
        const auto available = static_cast<std::int32_t>(placed.spawn_positions.size());
        if (override_value && *override_value > available) {
            status = bad("capacity_exceeds_spawns","The current capacity override exceeds actual valid spawn positions.");
            status.diagnostics[0].affected_ids = {placed.id}; return {status,{}};
        }
        placed.capacity = override_value.value_or(available);
    }
    status = validate_routed_geometry(source,layout,refreshed); if (!status.ok()) return {status,{}};
    AllocationInput input; input.settings = source.settings; input.geometry_id = geometry.id;
    input.geometry_revision = geometry.geometry_revision; input.packs = source.packs;
    for (const auto& placed : refreshed.rooms) {
        auto room = *std::find_if(layout.rooms.begin(),layout.rooms.end(),[&](const Room& r) { return r.id == placed.id; });
        const auto current = std::find_if(source.rooms.begin(),source.rooms.end(),[&](const Room& r) { return r.id == room.id; });
        if (current != source.rooms.end()) { room.tags = current->tags; room.capacity_override = current->capacity_override; }
        if (room.id == geometry.entrance_room) room.role = RoomRole::entrance;
        else if (room.id == geometry.exit_room) room.role = RoomRole::exit;
        input.rooms.push_back({room,placed.reachable,placed.capacity,placed.spawn_positions});
    }
    status = validate_allocation_input(input); if (!status.ok()) return {status,{}};
    return {{},std::move(input)};
}
} // namespace dungeon_architect

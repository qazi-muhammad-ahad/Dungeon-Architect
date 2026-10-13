#include "dungeon_architect/project.h"
#include "dungeon_architect/geometry.h"

#include <algorithm>
#include <set>

namespace dungeon_architect {
namespace {
bool identifier(const std::string& value) {
    if (value.empty() || value.size() > limits::max_id_bytes) return false;
    for (char raw : value) {
        const auto c = static_cast<unsigned char>(raw);
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == ':')) return false;
    }
    return true;
}
bool text(const std::string& value) {
    return !value.empty() && value.size() <= limits::max_text_bytes && valid_utf8(value) &&
           std::none_of(value.begin(), value.end(), [](unsigned char c) { return c < 32 || c == 127; });
}
bool role_valid(RoomRole role) { return role >= RoomRole::normal && role <= RoomRole::boss; }
}

Status validate_project(const Project& project) {
    Status result;
    auto add = [&](std::string code, std::string path, std::string message,
                   Outcome outcome = Outcome::invalid_input, std::string id = "",
                   std::vector<Tile> tiles = {}) {
        if (result.outcome == Outcome::success || outcome == Outcome::invalid_input) result.outcome = outcome;
        if (result.diagnostics.size() == limits::max_diagnostics) return;
        result.diagnostics.push_back({std::move(code), std::move(path), std::move(message),
            id.empty() ? std::vector<std::string>{} : std::vector<std::string>{id},
            std::move(tiles), "Correct the indicated field and retry; the previous project is unchanged."});
    };
    if (!text(project.name)) add("invalid_text", "/source/name", "Name must be nonempty UTF-8 text of at most 256 bytes without control characters.");
    const auto& s = project.settings;
    const bool canvas_valid = s.columns > 0 && s.rows > 0 && s.columns <= limits::max_axis && s.rows <= limits::max_axis;
    if (s.columns <= 0 || s.rows <= 0) add("invalid_canvas", "/source/settings", "Canvas dimensions must be positive.");
    else if (!canvas_valid) add("canvas_limit", "/source/settings", "Storage supports at most 512 cells per axis; generation limits are not yet measured.", Outcome::unsupported_size);
    const auto area = std::int64_t{s.columns} * s.rows;
    if (canvas_valid && project.allowed_mask.size() != static_cast<std::size_t>(area))
        add("mask_length", "/source/allowed_mask", "Mask length must equal columns times rows.");
    if (project.allowed_mask.size() > limits::max_cells)
        add("mask_limit", "/source/allowed_mask", "Mask exceeds the storage guard.", Outcome::unsupported_size);
    else if (std::any_of(project.allowed_mask.begin(), project.allowed_mask.end(), [](auto cell) { return cell > 1; }))
        add("mask_value", "/source/allowed_mask", "Every mask cell must be zero or one.");
    // An empty painted area is a valid editable document. Generation validates non-emptiness later.
    if (s.room_count < 2) add("room_count", "/source/settings/room_count", "At least two rooms are required for distinct entrance and exit roles.");
    else if (canvas_valid && s.room_count > area) add("room_count", "/source/settings/room_count", "Requested rooms exceed the number of canvas tiles.");
    auto range = [&](std::int32_t lo, std::int32_t hi, std::int32_t extent, const char* path) {
        if (lo <= 0 || hi < lo || (canvas_valid && hi > extent))
            add("dimension_range", path, "Room dimensions must be positive, ordered, and no larger than the canvas axis.");
    };
    range(s.min_room_width, s.max_room_width, s.columns, "/source/settings/room_width");
    range(s.min_room_height, s.max_room_height, s.rows, "/source/settings/room_height");
    if (s.margin < 0 || s.margin > limits::max_axis) add("margin_range", "/source/settings/margin", "Margin must be between zero and 512.");
    if (s.corridor_width <= 0 || (canvas_valid && s.corridor_width > std::min(s.columns, s.rows)))
        add("corridor_width", "/source/settings/corridor_width", "Corridor width must fit within both canvas axes and be positive.");
    if (s.max_generation_attempts <= 0) add("work_limit", "/source/settings/max_generation_attempts", "Attempt limit must be positive.");
    if (s.max_work_units <= 0) add("work_limit", "/source/settings/max_work_units", "Work-unit limit must be positive.");
    if (s.max_time_ms <= 0) add("work_limit", "/source/settings/max_time_ms", "Time limit must be positive.");
    if (s.threat_budget < 0) add("negative_budget", "/source/settings/threat_budget", "Threat budget cannot be negative.");
    if (project.rooms.size() > limits::max_records || project.packs.size() > limits::max_records) {
        add("record_limit", "/source", "A document may contain at most 4096 source rooms and 4096 catalogue packs.", Outcome::unsupported_size);
        return result;
    }
    auto check_tags = [&](const std::vector<std::string>& tags, const std::string& path, const std::string& id) {
        if (tags.size() > limits::max_tags) {
            add("tag_limit", path, "At most 64 tags are supported per record.", Outcome::unsupported_size, id);
            return;
        }
        std::set<std::string> seen;
        for (const auto& tag : tags) {
            if (!identifier(tag) || !seen.insert(tag).second)
                add("invalid_tag", path, "Tags must be unique ASCII identifiers of 1-64 bytes.", Outcome::invalid_input, id);
        }
    };
    std::set<std::string> ids;
    for (std::size_t i = 0; i < project.rooms.size(); ++i) {
        const auto& room = project.rooms[i];
        const auto path = "/source/rooms/" + std::to_string(i);
        if (!identifier(room.id)) add("invalid_id", path + "/id", "Room ID must be a 1-64 byte ASCII identifier.", Outcome::invalid_input, room.id);
        if (!ids.insert(room.id).second) add("duplicate_id", path + "/id", "Room IDs must be unique.", Outcome::invalid_input, room.id);
        if (!text(room.name)) add("invalid_text", path + "/name", "Room name must be nonempty valid UTF-8 text of at most 256 bytes.", Outcome::invalid_input, room.id);
        if (!room.bounds.valid() || (canvas_valid && !room.bounds.inside(s.columns, s.rows)))
            add("room_bounds", path + "/bounds", "Room rectangle must have positive dimensions and fit the canvas.", Outcome::invalid_input, room.id, {{room.bounds.x, room.bounds.y}});
        if (!role_valid(room.role)) add("invalid_role", path + "/role", "Unknown room role.", Outcome::invalid_input, room.id);
        if (room.capacity_override && (*room.capacity_override < 0 ||
            *room.capacity_override > std::int64_t{room.bounds.width} * room.bounds.height))
            add("capacity_range", path + "/capacity_override", "Capacity cannot be negative or exceed the room's tile area.", Outcome::invalid_input, room.id);
        if (room.role == RoomRole::entrance && room.capacity_override && *room.capacity_override != 0)
            add("entrance_capacity", path + "/capacity_override", "The entrance is a safe room with zero encounter capacity.", Outcome::invalid_input, room.id);
        check_tags(room.tags, path + "/tags", room.id);
    }
    ids.clear();
    std::int64_t slots = 0, threat = 0, score = 0;
    for (std::size_t i = 0; i < project.packs.size(); ++i) {
        const auto& pack = project.packs[i];
        const auto path = "/source/packs/" + std::to_string(i);
        if (!identifier(pack.id)) add("invalid_id", path + "/id", "Pack ID must be a 1-64 byte ASCII identifier.", Outcome::invalid_input, pack.id);
        if (!ids.insert(pack.id).second) add("duplicate_id", path + "/id", "Pack inventory copies must have distinct IDs.", Outcome::invalid_input, pack.id);
        if (!text(pack.name)) add("invalid_text", path + "/name", "Pack name must be nonempty valid UTF-8 text of at most 256 bytes.", Outcome::invalid_input, pack.id);
        if (pack.slots <= 0) add("pack_slots", path + "/slots", "Spawn demand must be positive.", Outcome::invalid_input, pack.id);
        if (pack.threat < 0) add("negative_threat", path + "/threat", "Threat cannot be negative.", Outcome::invalid_input, pack.id);
        if (pack.score < 0) add("negative_score", path + "/score", "Score cannot be negative.", Outcome::invalid_input, pack.id);
        if (pack.min_room_width <= 0 || pack.min_room_height <= 0)
            add("pack_dimensions", path, "Minimum compatible room dimensions must be positive.", Outcome::invalid_input, pack.id);
        if (pack.active && pack.slots > 0 && pack.threat >= 0 && pack.score >= 0) {
            if (!checked_add(slots, pack.slots, slots) || !checked_add(threat, pack.threat, threat) || !checked_add(score, pack.score, score))
                add("total_overflow", path, "Active inventory totals exceed signed 64-bit storage.", Outcome::invalid_input, pack.id);
        }
        std::set<RoomRole> roles;
        for (auto role : pack.allowed_roles) {
            if (!role_valid(role) || !roles.insert(role).second)
                add("invalid_role", path + "/allowed_roles", "Allowed roles must be known and unique.", Outcome::invalid_input, pack.id);
        }
        check_tags(pack.required_tags, path + "/required_tags", pack.id);
    }
    return result.ok() ? detail::validate_room_geometry(project) : result;
}
Status validate_allocation_workload(const Project& project) {
    auto result = validate_project(project);
    if (!result.ok()) return result;
    const auto count = std::count_if(project.packs.begin(), project.packs.end(), [](const Pack& p) { return p.active; });
    if (count > static_cast<std::ptrdiff_t>(limits::max_active_packs))
        return failure(Outcome::unsupported_size, "active_pack_limit", "/source/packs",
                       "The exact optimizer supports at most 14 active packs.", "Deactivate packs; the full catalogue can remain saved.");
    return {};
}
}  // namespace dungeon_architect

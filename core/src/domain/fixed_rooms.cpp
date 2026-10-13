#include "dungeon_architect/geometry.h"

#include <algorithm>
#include <set>

namespace dungeon_architect {
namespace {
bool fixed(const Room& room) { return room.lock_position || room.lock_size; }
std::size_t index(std::int32_t x, std::int32_t y, std::int32_t columns) {
    return static_cast<std::size_t>(y) * static_cast<std::size_t>(columns) + static_cast<std::size_t>(x);
}
Rect expand(Rect r, std::int32_t margin) {
    return {r.x - margin, r.y - margin, r.width + 2 * margin, r.height + 2 * margin};
}
bool overlap(Rect a, Rect b) {
    return a.x < b.right() && b.x < a.right() && a.y < b.bottom() && b.y < a.bottom();
}
Status error(std::string code, std::string message, std::vector<std::string> ids = {},
             std::vector<Tile> tiles = {}, std::string path = "/source/rooms") {
    auto status = failure(Outcome::invalid_input, std::move(code), std::move(path), std::move(message),
                          "Correct the indicated rooms or mask and retry; the previous project is unchanged.");
    status.diagnostics.front().affected_ids = std::move(ids);
    status.diagnostics.front().affected_tiles = std::move(tiles);
    return status;
}
}

namespace detail {
Status validate_room_geometry(const Project& p) {
    // Structural validation has already bounded every rectangle, axis, and margin.
    Status result;
    auto append = [&](Status status) {
        if (result.diagnostics.size() >= limits::max_diagnostics) return;
        result.outcome = status.outcome;
        result.diagnostics.push_back(std::move(status.diagnostics.front()));
    };
    const Room* entrance = nullptr;
    const Room* exit = nullptr;
    std::size_t mandatory = 0;
    for (std::size_t i = 0; i < p.rooms.size(); ++i) {
        if (result.diagnostics.size() >= limits::max_diagnostics) break;
        const auto& room = p.rooms[i];
        mandatory += fixed(room) ? 1U : 0U;
        if (room.role == RoomRole::entrance || room.role == RoomRole::exit) {
            auto& existing = room.role == RoomRole::entrance ? entrance : exit;
            if (existing) append(error("duplicate_terminal", "Entrance and exit roles must each be unique.",
                                       {existing->id, room.id}, {{room.bounds.x, room.bounds.y}}));
            else existing = &room;
        }
        const auto buffered = expand(room.bounds, p.settings.margin);
        if (!buffered.inside(p.settings.columns, p.settings.rows)) {
            Tile outside{buffered.x, buffered.y};
            if (outside.x >= 0 && outside.y >= 0) {
                if (buffered.right() > p.settings.columns) outside.x = p.settings.columns;
                else outside.y = p.settings.rows;
            }
            append(error("room_margin_boundary", "Room and its required margin must fit inside the canvas.",
                         {room.id}, {outside}, "/source/rooms/" + std::to_string(i) + "/bounds"));
        } else {
            bool found = false;
            for (auto y = buffered.y; y < buffered.bottom() && !found; ++y) {
                for (auto x = buffered.x; x < buffered.right(); ++x) {
                    if (p.allowed_mask[index(x, y, p.settings.columns)] == 0) {
                        append(error(room.bounds.contains({x, y}) ? "room_mask_hole" : "room_margin_mask",
                                     "Every room tile and margin tile must belong to the allowed mask.",
                                     {room.id}, {{x, y}}, "/source/rooms/" + std::to_string(i) + "/bounds"));
                        found = true;
                        break;
                    }
                }
            }
        }
        for (std::size_t j = 0; j < i && result.diagnostics.size() < limits::max_diagnostics; ++j) {
            const auto& other = p.rooms[j];
            if (overlap(buffered, other.bounds)) {
                append(error(overlap(room.bounds, other.bounds) ? "room_overlap" : "room_separation",
                    "Room interiors must not overlap and must have the configured number of separating tiles.",
                    {other.id, room.id}, {{std::max(buffered.x, other.bounds.x), std::max(buffered.y, other.bounds.y)}}));
            }
        }
    }
    if (mandatory > static_cast<std::size_t>(p.settings.room_count))
        append(error("mandatory_room_count", "Requested total is smaller than the number of locked rooms.", {}, {}, "/source/settings/room_count"));
    return result;
}
Status validate_locked_edits(const Project& previous, const Project& candidate) {
    for (const auto& room : previous.rooms) {
        if (!fixed(room)) continue;
        const auto next = std::find_if(candidate.rooms.begin(), candidate.rooms.end(), [&](const Room& r) { return r.id == room.id; });
        if (next == candidate.rooms.end())
            return error("locked_room_removed", "Unlock the room in a separate edit before removing it or changing its ID.", {room.id});
        if (room.lock_position && (room.bounds.x != next->bounds.x || room.bounds.y != next->bounds.y))
            return error("locked_position", "Unlock position in a separate edit before moving this room.", {room.id}, {{room.bounds.x, room.bounds.y}});
        if (room.lock_size && (room.bounds.width != next->bounds.width || room.bounds.height != next->bounds.height))
            return error("locked_size", "Unlock size in a separate edit before resizing this room.", {room.id}, {{room.bounds.x, room.bounds.y}});
    }
    return {};
}
}

bool ReservationMap::can_place(Rect footprint) const noexcept {
    if (!footprint.inside(columns_, rows_)) return false;
    const auto buffered = expand(footprint, margin_);
    if (!buffered.inside(columns_, rows_)) return false;
    for (auto y = buffered.y; y < buffered.bottom(); ++y)
        for (auto x = buffered.x; x < buffered.right(); ++x)
            if (allowed_[index(x, y, columns_)] == 0) return false;
    for (auto y = footprint.y; y < footprint.bottom(); ++y)
        for (auto x = footprint.x; x < footprint.right(); ++x)
            if (blocked_[index(x, y, columns_)] != 0) return false;
    return true;
}
Result<PreparedGeometry> prepare_geometry(const Project& project) {
    auto status = validate_project(project);
    if (!status.ok()) return {std::move(status), std::nullopt};
    auto analyzed = analyze_mask(project);
    if (!analyzed.ok()) return {std::move(analyzed.status), std::nullopt};
    if (analyzed.value->components.empty())
        return {error("empty_mask", "Generation needs a nonempty building area.", {}, {}, "/source/allowed_mask"), std::nullopt};
    PreparedGeometry result;
    result.mask = std::move(*analyzed.value);
    auto& map = result.reservations;
    map.columns_ = project.settings.columns;
    map.rows_ = project.settings.rows;
    map.margin_ = project.settings.margin;
    map.allowed_ = project.allowed_mask;
    map.blocked_.assign(map.allowed_.size(), 0);
    map.owners_.assign(map.allowed_.size(), -1);
    for (const auto& room : project.rooms) if (fixed(room)) map.rooms_.push_back(room);
    std::sort(map.rooms_.begin(), map.rooms_.end(), [](const Room& a, const Room& b) { return a.id < b.id; });
    result.mandatory_rooms = map.rooms_.size();
    result.remaining_rooms = static_cast<std::size_t>(project.settings.room_count) - result.mandatory_rooms;
    std::int32_t fixed_component = -1;
    std::string first_id;
    bool entrance = false, exit = false;
    std::size_t normals = result.remaining_rooms;
    for (std::size_t i = 0; i < map.rooms_.size(); ++i) {
        const auto& room = map.rooms_[i];
        entrance = entrance || room.role == RoomRole::entrance;
        exit = exit || room.role == RoomRole::exit;
        normals += room.role == RoomRole::normal ? 1U : 0U;
        const auto component = result.mask.labels[index(room.bounds.x, room.bounds.y, map.columns_)];
        if (fixed_component >= 0 && component != fixed_component)
            return {error("fixed_rooms_disconnected", "Locked rooms lie on separate mask islands and cannot be connected within the mask.",
                          {first_id, room.id}, {{room.bounds.x, room.bounds.y}}), std::nullopt};
        if (fixed_component < 0) { fixed_component = component; first_id = room.id; }
        const auto buffered = expand(room.bounds, map.margin_);
        for (auto y = buffered.y; y < buffered.bottom(); ++y)
            for (auto x = buffered.x; x < buffered.right(); ++x) map.blocked_[index(x, y, map.columns_)] = 1;
        for (auto y = room.bounds.y; y < room.bounds.bottom(); ++y)
            for (auto x = room.bounds.x; x < room.bounds.right(); ++x) map.owners_[index(x, y, map.columns_)] = static_cast<std::int32_t>(i);
    }
    const auto missing = (entrance ? 0U : 1U) + (exit ? 0U : 1U);
    if (normals < missing)
        return {error("terminal_room_count", "Reserve enough normal or new rooms for distinct entrance and exit roles; boss rooms keep their role."), std::nullopt};
    return {{}, std::move(result)};
}
Result<Terminals> select_terminals(const std::vector<Room>& rooms) {
    Terminals result;
    std::vector<RoomId> normals;
    std::set<RoomId> ids;
    for (const auto& room : rooms) {
        if (room.id.empty() || !ids.insert(room.id).second)
            return {error("terminal_id", "Terminal selection requires nonempty unique room IDs.", {room.id}), std::nullopt};
        if (room.role == RoomRole::normal) normals.push_back(room.id);
        else if (room.role == RoomRole::entrance || room.role == RoomRole::exit) {
            auto& target = room.role == RoomRole::entrance ? result.entrance : result.exit;
            if (!target.empty()) return {error("duplicate_terminal", "Entrance and exit roles must each be unique.", {target, room.id}), std::nullopt};
            target = room.id;
        } else if (room.role != RoomRole::boss)
            return {error("invalid_role", "Unknown room role.", {room.id}), std::nullopt};
    }
    std::sort(normals.begin(), normals.end());
    if (result.entrance.empty() && !normals.empty()) { result.entrance = normals.front(); normals.erase(normals.begin()); }
    if (result.exit.empty() && !normals.empty()) result.exit = normals.back();
    if (result.entrance.empty() || result.exit.empty())
        return {error("missing_terminals", "Two distinct non-boss rooms are needed for entrance and exit."), std::nullopt};
    return {{}, std::move(result)};
}
Result<std::int32_t> encounter_capacity(const Room& room, const Terminals& terminals, std::int32_t valid_spawn_count) {
    if (terminals.entrance.empty() || terminals.exit.empty() || terminals.entrance == terminals.exit ||
        valid_spawn_count < 0 || !room.bounds.valid() || valid_spawn_count > std::int64_t{room.bounds.width} * room.bounds.height ||
        (room.capacity_override && *room.capacity_override < 0))
        return {error("capacity_input", "Capacity needs distinct terminals, valid geometry, and a nonnegative spawn count within the room area.", {room.id}), std::nullopt};
    if (room.id == terminals.entrance || room.role == RoomRole::entrance) return {{}, 0};
    return {{}, room.capacity_override ? std::min(valid_spawn_count, *room.capacity_override) : valid_spawn_count};
}
Status add_room(ProjectSession& session, Room room) {
    auto candidate = session.project();
    candidate.rooms.push_back(std::move(room));
    return session.update(std::move(candidate));
}
Status edit_room(ProjectSession& session, const RoomId& id, Room replacement) {
    if (replacement.id != id) return error("stable_room_id", "An edit cannot change a room's stable ID.", {id, replacement.id});
    auto candidate = session.project();
    auto found = std::find_if(candidate.rooms.begin(), candidate.rooms.end(), [&](const Room& r) { return r.id == id; });
    if (found == candidate.rooms.end()) return error("room_not_found", "No room has the requested ID.", {id});
    *found = std::move(replacement);
    return session.update(std::move(candidate));
}
Status remove_room(ProjectSession& session, const RoomId& id) {
    auto candidate = session.project();
    auto found = std::find_if(candidate.rooms.begin(), candidate.rooms.end(), [&](const Room& r) { return r.id == id; });
    if (found == candidate.rooms.end()) return error("room_not_found", "No room has the requested ID.", {id});
    candidate.rooms.erase(found);
    return session.update(std::move(candidate));
}
}  // namespace dungeon_architect

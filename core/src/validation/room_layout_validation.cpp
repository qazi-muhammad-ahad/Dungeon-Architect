#include "dungeon_architect/generation.h"
#include <algorithm>
#include <map>
#include <set>

namespace dungeon_architect {
namespace {
Status invalid(const char* code, const char* message) {
    return failure(Outcome::invalid_input,code,"/room_layout",message,"Discard this candidate and retain the previous valid layout.");
}
bool intersects(Rect a, Rect b) { return a.x < b.right() && b.x < a.right() && a.y < b.bottom() && b.y < a.bottom(); }
auto attributes(const Room& r) { return std::tie(r.id,r.name,r.bounds,r.role,r.tags,r.lock_position,r.lock_size,r.capacity_override); }
}
Status validate_room_layout(const Project& source, const RoomLayoutSnapshot& layout) {
    auto prepared = prepare_geometry(source);
    if (!prepared.ok()) return prepared.status;
    const auto& s = source.settings;
    const auto count = layout.rooms.size();
    if (count != static_cast<std::size_t>(s.room_count) || count > limits::max_records)
        return invalid("layout_count","A room layout must contain exactly the requested number of rooms within the record guard.");
    if (layout.id.empty()) return invalid("layout_id","A room layout requires a snapshot ID.");
    auto candidate = source; candidate.rooms = layout.rooms;
    auto status = validate_project(candidate);
    if (!status.ok()) return status;
    std::map<RoomId,std::size_t> room_indexes;
    std::set<RoomId> fixed_ids, source_ids;
    for (const auto& room : source.rooms) source_ids.insert(room.id);
    for (std::size_t i = 0; i < count; ++i) {
        if (i > 0 && !(layout.rooms[i-1].id < layout.rooms[i].id)) return invalid("layout_order","Rooms must be in canonical ID order.");
        room_indexes.emplace(layout.rooms[i].id,i);
    }
    for (auto fixed : prepared.value->reservations.fixed_rooms()) {
        fixed_ids.insert(fixed.id);
        const auto found = room_indexes.find(fixed.id);
        if (found == room_indexes.end()) return invalid("missing_fixed_room","A mandatory room was lost.");
        auto actual = layout.rooms[found->second];
        std::sort(fixed.tags.begin(),fixed.tags.end()); std::sort(actual.tags.begin(),actual.tags.end());
        if (attributes(actual) != attributes(fixed)) return invalid("fixed_room_changed","A mandatory room's geometry or attributes were changed.");
    }
    for (const auto& room : layout.rooms) if (!fixed_ids.count(room.id)) {
        if (source_ids.count(room.id)) return invalid("generated_id_collision","A generated room reused an existing source ID.");
        if (room.lock_position || room.lock_size || room.role != RoomRole::normal ||
            room.bounds.width < s.min_room_width || room.bounds.width > s.max_room_width ||
            room.bounds.height < s.min_room_height || room.bounds.height > s.max_room_height)
            return invalid("generated_room_range","A generated room violates configured dimensions or source-role/lock rules.");
    }
    auto terminals = select_terminals(layout.rooms);
    if (!terminals.ok()) return terminals.status;
    if (layout.terminals.entrance != terminals.value->entrance || layout.terminals.exit != terminals.value->exit)
        return invalid("layout_terminals","Terminals must follow deterministic distinct-room selection.");
    std::vector<std::uint8_t> occupancy(source.allowed_mask.size(),0), reserved(occupancy.size(),0);
    for (const auto& room : layout.rooms) {
        const auto& r = room.bounds;
        for (auto y = r.y-s.margin; y < r.bottom()+s.margin; ++y) for (auto x = r.x-s.margin; x < r.right()+s.margin; ++x) {
            const auto i = static_cast<std::size_t>(y*s.columns+x);
            reserved[i] = 1;
            if (r.contains({x,y})) occupancy[i] = 1;
        }
    }
    if (layout.occupancy != occupancy || layout.reservations != reserved)
        return invalid("layout_layers","Room occupancy/reservation layers disagree with actual room geometry.");
    const auto& nodes = layout.partitions;
    const auto remaining = static_cast<std::int32_t>(prepared.value->remaining_rooms);
    const auto expected_nodes = remaining == 0 ? 1 : 2*remaining-1;
    if (nodes.size() != static_cast<std::size_t>(expected_nodes) || nodes[0].parent != -1 ||
        !(nodes[0].bounds == Rect{0,0,s.columns,s.rows}) || nodes[0].requested_rooms != remaining)
        return invalid("partition_root","The partition tree does not cover the canvas and remaining room target.");
    std::vector<unsigned> incoming(nodes.size(),0), depths(nodes.size(),0);
    std::set<RoomId> leaves;
    for (std::size_t i = 0; i < nodes.size(); ++i) {
        const auto& n = nodes[i];
        if (n.id != static_cast<std::int32_t>(i) || !n.bounds.inside(s.columns,s.rows) || n.requested_rooms < 0 || n.requested_rooms > remaining || depths[i] > 64)
            return invalid("partition_node","Invalid node index, bounds, count, or tree depth.");
        std::int64_t allowed = 0, free = 0;
        for (auto y = n.bounds.y; y < n.bounds.bottom(); ++y) for (auto x = n.bounds.x; x < n.bounds.right(); ++x) {
            const auto cell = static_cast<std::size_t>(y*s.columns+x);
            if (source.allowed_mask[cell]) { ++allowed; if (!prepared.value->reservations.blocked()[cell]) ++free; }
        }
        std::vector<RoomId> intersections;
        for (const auto& fixed : prepared.value->reservations.fixed_rooms()) if (intersects(n.bounds,fixed.bounds)) intersections.push_back(fixed.id);
        if (allowed != n.allowed_tiles || free != n.free_tiles || intersections != n.intersecting_fixed_rooms)
            return invalid("partition_summary","Partition free-area or fixed-room metadata is inaccurate.");
        if (n.requested_rooms <= 1) {
            if (n.first_child != -1 || n.second_child != -1 || n.axis != SplitAxis::none)
                return invalid("partition_leaf","A leaf cannot have child partitions or a split axis.");
            if (n.requested_rooms == 0) {
                if (i != 0 || !n.room_id.empty()) return invalid("partition_empty","Only the fixed-only root may have zero generated rooms.");
            } else {
                const auto found = room_indexes.find(n.room_id);
                if (found == room_indexes.end() || fixed_ids.count(n.room_id) || !leaves.insert(n.room_id).second)
                    return invalid("partition_room","A generated room must belong to exactly one leaf.");
                const auto& r = layout.rooms[found->second].bounds;
                if (r.x < n.bounds.x || r.y < n.bounds.y || r.right() > n.bounds.right() || r.bottom() > n.bounds.bottom())
                    return invalid("partition_containment","A generated room escapes its leaf.");
            }
            continue;
        }
        if (!n.room_id.empty() || n.first_child <= static_cast<std::int32_t>(i) || n.second_child <= static_cast<std::int32_t>(i) ||
            n.first_child == n.second_child || n.first_child >= static_cast<std::int32_t>(nodes.size()) || n.second_child >= static_cast<std::int32_t>(nodes.size()))
            return invalid("partition_children","A split must have two distinct forward children.");
        const auto a_index = static_cast<std::size_t>(n.first_child), b_index = static_cast<std::size_t>(n.second_child);
        const auto& a = nodes[a_index]; const auto& b = nodes[b_index];
        if (++incoming[a_index] != 1 || ++incoming[b_index] != 1 || a.parent != n.id || b.parent != n.id ||
            a.requested_rooms <= 0 || b.requested_rooms <= 0 || std::int64_t{a.requested_rooms}+b.requested_rooms != n.requested_rooms)
            return invalid("partition_counts","Child ownership or requested room counts are inconsistent.");
        depths[a_index] = depths[b_index] = depths[i]+1;
        Rect expected_a = n.bounds, expected_b = n.bounds;
        if (n.axis == SplitAxis::x) {
            if (n.cut <= n.bounds.x || std::int64_t{n.cut}+s.margin >= n.bounds.right()) return invalid("partition_split","Invalid vertical cut.");
            expected_a.width = n.cut-n.bounds.x; expected_b.x = n.cut+s.margin;
            expected_b.width = static_cast<std::int32_t>(n.bounds.right())-expected_b.x;
        } else if (n.axis == SplitAxis::y) {
            if (n.cut <= n.bounds.y || std::int64_t{n.cut}+s.margin >= n.bounds.bottom()) return invalid("partition_split","Invalid horizontal cut.");
            expected_a.height = n.cut-n.bounds.y; expected_b.y = n.cut+s.margin;
            expected_b.height = static_cast<std::int32_t>(n.bounds.bottom())-expected_b.y;
        } else return invalid("partition_axis","A branch requires an x or y split.");
        if (!(a.bounds == expected_a) || !(b.bounds == expected_b)) return invalid("partition_split","Child bounds do not match the cut and separation gap.");
    }
    if (leaves.size() != prepared.value->remaining_rooms || std::any_of(incoming.begin()+1,incoming.end(),[](auto n) { return n != 1; }))
        return invalid("partition_disconnected","Every generated room and partition must belong to the tree.");
    if (layout.connections.size() != count-1) return invalid("connection_count","Abstract routing requirements must form a room tree.");
    std::vector<std::size_t> groups(count);
    for (std::size_t i = 0; i < count; ++i) groups[i] = i;
    auto root = [&](std::size_t i) { while (groups[i] != i) { groups[i] = groups[groups[i]]; i = groups[i]; } return i; };
    for (const auto& edge : layout.connections) {
        const auto a = room_indexes.find(edge.from), b = room_indexes.find(edge.to);
        if (a == room_indexes.end() || b == room_indexes.end()) return invalid("connection_room","Abstract edge references a missing room.");
        const auto ar = root(a->second), br = root(b->second);
        if (ar == br) return invalid("connection_cycle","Abstract routing requirements contain a cycle or self-edge.");
        if (edge.fixed_attachment ? !fixed_ids.count(edge.to) : (fixed_ids.count(edge.from) || fixed_ids.count(edge.to)))
            return invalid("connection_kind","An abstract edge has the wrong fixed/BSP attachment kind.");
        groups[ar] = br;
    }
    return {};
}
} // namespace dungeon_architect

#pragma once
#include "dungeon_architect/project.h"

namespace dungeon_architect {
enum class MaskPreset { rectangle, ellipse, l_shape };
Result<std::vector<std::uint8_t>> make_mask(std::int32_t columns, std::int32_t rows,
                                         MaskPreset preset, Rect bounds);
Status apply_mask_preset(ProjectSession& session, MaskPreset preset, Rect bounds);
Status paint_tiles(ProjectSession& session, const std::vector<Tile>& tiles, bool allowed);
Status flood_fill(ProjectSession& session, Tile start, bool allowed);

struct MaskComponent {
    std::int32_t id = -1;
    Rect bounds;
    std::vector<Tile> tiles;
};
struct MaskAnalysis {
    // -1 = disallowed. Component IDs follow first tile in row-major order.
    std::vector<std::int32_t> labels;
    std::vector<MaskComponent> components;
    // Largest component, ties resolved by the lowest component ID.
    std::int32_t primary_component = -1;
};
Result<MaskAnalysis> analyze_mask(const Project& project);

struct PreparedGeometry;
class ReservationMap {
public:
    std::int32_t columns() const noexcept { return columns_; }
    std::int32_t rows() const noexcept { return rows_; }
    const std::vector<Room>& fixed_rooms() const noexcept { return rooms_; }
    const std::vector<std::uint8_t>& blocked() const noexcept { return blocked_; }
    const std::vector<std::int32_t>& footprint_owners() const noexcept { return owners_; }
    // Tests an entire proposed new footprint against allowed cells and fixed
    // footprints + separation margins; abstract BSP bounds cannot clear these.
    // Its own margin must also fit the canvas/mask; reservation buffers may overlap.
    bool can_place(Rect footprint) const noexcept;
private:
    friend Result<PreparedGeometry> prepare_geometry(const Project& project);
    std::int32_t columns_ = 0, rows_ = 0, margin_ = 0;
    std::vector<std::uint8_t> allowed_, blocked_;
    std::vector<std::int32_t> owners_;
    std::vector<Room> rooms_;
};
struct PreparedGeometry {
    MaskAnalysis mask;
    ReservationMap reservations;
    std::size_t mandatory_rooms = 0;
    std::size_t remaining_rooms = 0;
};
Result<PreparedGeometry> prepare_geometry(const Project& project);

struct Terminals { RoomId entrance, exit; };
// Run against the complete room collection after generation, not just locks.
// Explicit roles win; missing roles use canonical normal rooms. Boss roles stay boss.
Result<Terminals> select_terminals(const std::vector<Room>& rooms);
Result<std::int32_t> encounter_capacity(const Room& room, const Terminals& terminals,
                                      std::int32_t valid_spawn_count);

Status add_room(ProjectSession& session, Room room);
Status edit_room(ProjectSession& session, const RoomId& id, Room replacement);
Status remove_room(ProjectSession& session, const RoomId& id);
// Phase-02 validation/session internals. Call validate_project/update as the public entry points.
namespace detail {
Status validate_room_geometry(const Project& project);
Status validate_locked_edits(const Project& previous, const Project& candidate);
}
}  // namespace dungeon_architect

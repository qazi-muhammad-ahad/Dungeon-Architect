#pragma once

#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <random>
#include <string>
#include <tuple>
#include <vector>

namespace dungeon_architect {
namespace limits {
// Storage/validation guards, not advertised generation/performance guarantees.
constexpr std::int32_t max_axis = 512;
constexpr std::size_t max_cells = 512U * 512U;
constexpr std::size_t max_records = 4096;
constexpr std::size_t max_tags = 64;
constexpr std::size_t max_text_bytes = 256;
constexpr std::size_t max_id_bytes = 64;
constexpr std::size_t max_file_bytes = 16U * 1024U * 1024U;
constexpr std::size_t max_json_depth = 32;
constexpr std::size_t max_diagnostics = 100;
constexpr std::size_t max_active_packs = 14;
}

using RoomId = std::string;
using PackId = std::string;
using CorridorId = std::string;
using SpawnId = std::string;
using SnapshotId = std::string;

struct Tile {
    std::int32_t x = 0, y = 0;
    bool operator==(const Tile& b) const { return x == b.x && y == b.y; }
};
struct Rect {
    std::int32_t x = 0, y = 0, width = 1, height = 1;
    std::int64_t right() const noexcept;
    std::int64_t bottom() const noexcept;
    bool valid() const noexcept;
    bool contains(Tile tile) const noexcept;
    bool inside(std::int32_t columns, std::int32_t rows) const noexcept;
    bool operator==(const Rect& b) const {
        return std::tie(x, y, width, height) == std::tie(b.x, b.y, b.width, b.height);
    }
};

enum class Outcome {
    success, invalid_input, search_exhausted, unsupported_size,
    unsupported_schema, cancelled, resource_failure, io_failure, stale_result
};
const char* outcome_name(Outcome outcome) noexcept;
struct Diagnostic {
    std::string code;
    std::string path;  // JSON Pointer for input fields; UTF-8 file path for IO errors.
    std::string message;
    std::vector<std::string> affected_ids;
    std::vector<Tile> affected_tiles;
    std::string recovery;
};
struct Status {
    Outcome outcome = Outcome::success;
    std::vector<Diagnostic> diagnostics;
    bool ok() const noexcept { return outcome == Outcome::success; }
};
Status failure(Outcome outcome, std::string code, std::string path,
               std::string message, std::string recovery);
template <typename T> struct Result {
    Status status;
    std::optional<T> value;
    bool ok() const noexcept { return status.ok() && value.has_value(); }
};

enum class RoomRole { normal, entrance, exit, boss };
const char* role_name(RoomRole role) noexcept;

struct Settings {
    std::int32_t columns = 150, rows = 150, room_count = 16;
    std::int32_t min_room_width = 8, max_room_width = 22;
    std::int32_t min_room_height = 8, max_room_height = 18;
    std::int32_t margin = 1, corridor_width = 2;
    std::uint32_t seed = 1;
    std::int64_t max_generation_attempts = 1000;
    std::int64_t max_work_units = 100000000;
    std::int64_t max_time_ms = 30000;
    std::int64_t threat_budget = 100;
};
struct Room {
    RoomId id;
    std::string name;
    Rect bounds;
    RoomRole role = RoomRole::normal;
    std::vector<std::string> tags;
    bool lock_position = false, lock_size = false;
    std::optional<std::int32_t> capacity_override;
};
struct Pack {
    PackId id;
    std::string name;
    bool active = true;
    std::int64_t slots = 1, threat = 0, score = 0;
    std::int32_t min_room_width = 1, min_room_height = 1;
    // Empty allowed_roles means any non-entrance role; all required tags must match.
    std::vector<RoomRole> allowed_roles;
    std::vector<std::string> required_tags;
};
struct Project {
    std::string name = "Untitled dungeon";
    Settings settings;
    // Row-major allowed building area. Never reused as carved floor or occupancy.
    std::vector<std::uint8_t> allowed_mask;
    std::vector<Room> rooms;
    std::vector<Pack> packs;
};

struct SpawnPosition { SpawnId id; Tile tile; };
struct RoomPlacement {
    RoomId id;
    Rect bounds;
    bool reachable = false;
    std::vector<SpawnPosition> spawn_positions;
    Tile hub;
    std::int32_t capacity = 0;
};
enum class DoorSide { north, east, south, west };
struct Door {
    std::string id;
    RoomId room_id;
    DoorSide side = DoorSide::north;
    Tile outside_anchor;
    std::vector<Tile> tiles;
};
struct CorridorLink {
    CorridorId id;
    RoomId from_room, to_room;
    std::vector<Tile> path;
    std::string from_door, to_door;
};
struct TileLayers {
    std::vector<std::uint8_t> occupancy, reservations, floor, walls;
};
struct ActorPlacement { PackId pack_id; RoomId room_id; SpawnId spawn_id; Tile tile; };
struct GeometrySnapshot {
    SnapshotId id;
    SnapshotId room_layout_id;
    std::uint64_t geometry_revision = 0;
    TileLayers layers;
    std::vector<RoomPlacement> rooms;
    std::vector<CorridorLink> corridors;
    std::vector<Door> doors;
    RoomId entrance_room, exit_room;
    Tile entrance_marker, exit_marker;
    std::vector<std::uint8_t> movement_reserved;
};
struct PackAssignment { PackId pack_id; RoomId room_id; };
struct UnusedPack { PackId pack_id; std::string reason; };
struct AllocationSnapshot {
    SnapshotId id;
    SnapshotId geometry_id;
    std::uint64_t geometry_revision = 0, allocation_revision = 0;
    std::vector<PackAssignment> assignments;
    std::vector<UnusedPack> unused;
    std::vector<ActorPlacement> actors;
    std::int64_t total_slots = 0, total_threat = 0, total_score = 0;
};
struct PlaySnapshot {
    SnapshotId id;
    std::uint64_t play_revision = 0;
    Tile player;
};

Project make_default_project();
Status validate_project(const Project& project);
// Separate solve eligibility from document validity: oversized active inventories
// can be saved/edited, but cannot be submitted to the exact optimizer.
Status validate_allocation_workload(const Project& project);
void canonicalize(Project& project);
bool checked_add(std::int64_t a, std::int64_t b, std::int64_t& out) noexcept;
bool valid_utf8(const std::string& value) noexcept;

struct Revisions {
    std::uint64_t source = 1, geometry = 1, allocation = 1, play = 1;
};
struct RoomLayoutSnapshot;
class ProjectSession {
public:
    ProjectSession();
    const Project& project() const noexcept { return project_; }
    Revisions revisions() const noexcept { return revisions_; }
    // Validation/canonicalization precede commit. Loading rebases all revision
    // counters so an older in-flight job cannot match a newly opened document.
    Status update(Project candidate);
    Status replace_loaded(Project candidate);
    Status publish_room_layout(RoomLayoutSnapshot snapshot, std::uint64_t expected_source);
    bool room_layout_current() const noexcept;
    std::shared_ptr<const RoomLayoutSnapshot> room_layout() const noexcept { return room_layout_; }

    // Enforce job revision/lifetime rules and, when a room layout is present,
    // independently validate routed geometry and allocation feasibility.
    Status publish_geometry(GeometrySnapshot snapshot, std::uint64_t expected_source);
    Status publish_allocation(AllocationSnapshot snapshot, std::uint64_t expected_source);
    Status publish_play(PlaySnapshot snapshot, std::uint64_t expected_source);
    bool geometry_current() const noexcept;
    bool allocation_current() const noexcept;
    bool play_current() const noexcept;
    std::shared_ptr<const GeometrySnapshot> geometry() const noexcept { return geometry_; }
    std::shared_ptr<const AllocationSnapshot> allocation() const noexcept { return allocation_; }
    std::shared_ptr<const PlaySnapshot> play() const noexcept { return play_; }
private:
    Status commit(Project candidate, bool load);
    Project project_;
    Revisions revisions_;
    std::shared_ptr<const RoomLayoutSnapshot> room_layout_;
    std::shared_ptr<const GeometrySnapshot> geometry_;
    std::shared_ptr<const AllocationSnapshot> allocation_;
    std::shared_ptr<const PlaySnapshot> play_;
};

// MT19937's raw 32-bit sequence plus explicit rejection mapping avoids the
// implementation-dependent mapping of std::uniform_int_distribution.
class DeterministicRandom {
public:
    explicit DeterministicRandom(std::uint32_t seed) : engine_(seed) {}
    std::uint32_t next() { return static_cast<std::uint32_t>(engine_()); }
    Result<std::uint32_t> bounded(std::uint32_t exclusive_upper);
private:
    std::mt19937 engine_;
};
}  // namespace dungeon_architect

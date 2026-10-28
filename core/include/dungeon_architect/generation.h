#pragma once
#include "dungeon_architect/instrumentation.h"
#include "dungeon_architect/geometry.h"
#include <functional>

namespace dungeon_architect {
enum class SplitAxis { none, x, y };
struct PartitionNode {
    std::int32_t id = -1, parent = -1, first_child = -1, second_child = -1;
    Rect bounds;
    std::int32_t requested_rooms = 0;
    std::int64_t allowed_tiles = 0, free_tiles = 0;
    SplitAxis axis = SplitAxis::none;
    std::int32_t cut = 0;
    RoomId room_id;
    std::vector<RoomId> intersecting_fixed_rooms;
};
struct RoomConnection {
    RoomId from, to;
    // A routing requirement only, never a carved corridor.
    bool fixed_attachment = false;
};
struct RoomLayoutSnapshot {
    SnapshotId id;
    std::uint64_t geometry_revision = 0;
    std::vector<Room> rooms;
    std::vector<PartitionNode> partitions;
    std::vector<RoomConnection> connections;
    Terminals terminals;
    std::vector<std::uint8_t> occupancy, reservations;
};
struct GenerationEvent {
    std::string kind, reason;
    std::int32_t node = -1;
    Rect bounds;
    RoomId room_id;
    std::int64_t attempt = 0;
    std::int32_t cut = 0, first_child_rooms = 0;
};
struct GenerationMetrics {
    TimingMap timings_us;
    double trace_us = 0;
    std::int64_t work_units = 0, attempts = 0, rejected_candidates = 0, backtracks = 0;
    std::uint64_t dropped_events = 0;
};
struct GenerationOptions {
    std::size_t max_events = 256; // 0 disables storage; hard cap 4096.
    // Called on the generating thread. Callers may set an atomic flag from UI.
    std::function<bool()> cancelled;
};
struct GenerationResult {
    Status status;
    std::optional<RoomLayoutSnapshot> layout;
    GenerationMetrics metrics;
    std::vector<GenerationEvent> events;
    bool ok() const noexcept { return status.ok() && layout.has_value(); }
};
GenerationResult generate_rooms(const Project& source, const GenerationOptions& options = {});
// Copies source first, validates a complete candidate, and publishes only if current.
GenerationResult generate_rooms(ProjectSession& session, const GenerationOptions& options = {});
Status validate_room_layout(const Project& source, const RoomLayoutSnapshot& layout);
} // namespace dungeon_architect

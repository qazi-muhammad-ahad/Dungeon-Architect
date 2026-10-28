#pragma once
#include "dungeon_architect/instrumentation.h"
#include "dungeon_architect/generation.h"

namespace dungeon_architect {
using RoutingOptions = GenerationOptions;
struct RoutingMetrics {
    TimingMap timings_us;
    double trace_us = 0;
    std::int64_t work_units = 0, anchors_visited = 0, floor_visited = 0, corridors_routed = 0;
    std::uint64_t dropped_events = 0;
};
struct RoutingEvent {
    std::string kind;
    CorridorId corridor_id;
    RoomId room_id;
    Tile tile;
};
struct RoutingResult {
    Status status;
    std::optional<GeometrySnapshot> geometry;
    RoutingMetrics metrics;
    std::vector<RoutingEvent> events;
    bool ok() const noexcept { return status.ok() && geometry.has_value(); }
};
RoutingResult route_corridors(const Project& source, const RoomLayoutSnapshot& layout, const RoutingOptions& options = {});
RoutingResult route_corridors(ProjectSession& session, const RoutingOptions& options = {});
Status validate_routed_geometry(const Project& source, const RoomLayoutSnapshot& layout, const GeometrySnapshot& geometry);
} // namespace dungeon_architect

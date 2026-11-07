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
struct RoutingStep {
    std::string kind;
    Tile tile;
    Tile parent{-1,-1};
};
struct RoutingEvent {
    std::string kind;
    CorridorId corridor_id;
    RoomId room_id;
    Tile tile;
    RoomId other_room_id{};
    std::int32_t width = 1;
    std::uint64_t visited = 0, discovered = 0, omitted_steps = 0;
    std::vector<RoutingStep> steps{};
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

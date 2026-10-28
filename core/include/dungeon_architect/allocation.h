#pragma once
#include "dungeon_architect/instrumentation.h"
#include "dungeon_architect/routing.h"

namespace dungeon_architect {
struct AllocationRoom {
    Room room;
    bool reachable = false;
    std::int32_t capacity = 0;
    std::vector<SpawnPosition> spawns;
};
// Value input for isolated optimization/scenario fixtures. The dungeon adapter
// below additionally validates the full routed geometry before constructing it.
struct AllocationInput {
    Settings settings;
    SnapshotId geometry_id;
    std::uint64_t geometry_revision = 0, allocation_revision = 0;
    std::vector<Pack> packs;
    std::vector<AllocationRoom> rooms;
};
struct AllocationOptions {
    std::size_t max_events = 256;
    bool detailed_trace = false; // At most 6 active packs and 8 eligible rooms.
    std::function<bool()> cancelled;
};
struct AllocationMetrics {
    TimingMap timings_us;
    double trace_us = 0;
    std::uint64_t allocated_table_bytes = 0; // Logical vector storage, not RSS/heap peak.
    std::uint64_t estimated_bytes = 0, estimated_work = 0;
    std::uint64_t work_units = 0, transitions = 0, feasible_states = 0, dropped_events = 0;
    std::size_t active_packs = 0, eligible_rooms = 0;
};
struct AllocationEvent {
    std::string kind;
    RoomId room_id;
    std::uint32_t mask = 0, subset = 0;
    std::uint64_t states = 0;
};
struct AllocationResult {
    Status status;
    std::optional<AllocationSnapshot> allocation;
    AllocationMetrics metrics;
    std::vector<AllocationEvent> events;
    bool ok() const noexcept { return status.ok() && allocation.has_value(); }
};
Status validate_allocation_input(const AllocationInput& input);
Result<AllocationInput> prepare_allocation(const Project& source, const RoomLayoutSnapshot& layout,
                                          const GeometrySnapshot& geometry);
AllocationResult allocate_encounters(const AllocationInput& input, const AllocationOptions& options = {});
AllocationResult allocate_encounters(const Project& source, const RoomLayoutSnapshot& layout,
                                    const GeometrySnapshot& geometry, const AllocationOptions& options = {});
AllocationResult allocate_encounters(ProjectSession& session, const AllocationOptions& options = {});
// Checks feasibility and exact reported totals independently of the DP tables.
// Optimality is established by the solver and tested against an exhaustive oracle.
Status validate_allocation_result(const AllocationInput& input, const AllocationSnapshot& snapshot);
} // namespace dungeon_architect

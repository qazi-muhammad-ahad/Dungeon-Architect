#include "dungeon_architect/result_json.h"
#include "dungeon_architect/project_io.h"
#include "dungeon_architect/build_info.h"
#include <algorithm>
namespace da = dungeon_architect;
namespace io = da::project_io;
namespace dungeon_architect::result_io {
nlohmann::json rectangle(da::Rect r) { return {{"x",r.x},{"y",r.y},{"width",r.width},{"height",r.height}}; }
nlohmann::json rows(const std::vector<std::uint8_t>& cells, const da::Settings& s) {
    auto result = nlohmann::json::array();
    for (std::int32_t y = 0; y < s.rows; ++y) {
        std::string row;
        for (std::int32_t x = 0; x < s.columns; ++x) row += cells[static_cast<std::size_t>(y*s.columns+x)] ? '1' : '0';
        result.push_back(row);
    }
    return result;
}
nlohmann::json point(da::Tile t) { return {{"x",t.x},{"y",t.y}}; }
nlohmann::json allocation_json(const da::Project& p,const da::AllocationResult& result) {
        auto output = nlohmann::json::parse(io::diagnostics_json(result.status));
        output["format_version"] = 1; output["stage"] = "allocation"; output["engine_version"] = da::build_info().version;
        output["seed"] = p.settings.seed; output["threat_budget"] = p.settings.threat_budget;
        output["optimal"] = result.ok(); output["allocation"] = nullptr;
        std::vector<da::PackId> pack_order;
        for (const auto& pack : p.packs) if (pack.active) pack_order.push_back(pack.id);
        std::sort(pack_order.begin(),pack_order.end()); output["pack_bit_order"] = pack_order;
        const auto& m = result.metrics;
        output["metrics"] = {{"allocated_table_bytes",m.allocated_table_bytes},{"storage_domain","logical_capacity_of_subset_feasibility_predecessor_and_rolling_state_vectors_not_process_memory"},{"estimated_bytes",m.estimated_bytes},{"estimated_work",m.estimated_work},
            {"work_units",m.work_units},{"transitions",m.transitions},{"feasible_states",m.feasible_states},
            {"active_packs",m.active_packs},{"eligible_rooms",m.eligible_rooms},{"dropped_events",m.dropped_events}};
        output["metrics"]["timings_us"] = result.metrics.timings_us;
        output["metrics"]["trace_us"] = result.metrics.trace_us;
        output["metrics"]["timing_domain"] = "steady_clock_wall_including_validation_and_cooperative_yields";
        output["metrics"]["trace_timing"] = "nested_emission_overhead_included_in_stage_timings";
        output["events"] = nlohmann::json::array();
        for (const auto& e : result.events) output["events"].push_back({{"kind",e.kind},{"room_id",e.room_id},{"mask",e.mask},{"subset",e.subset},{"states",e.states}});
        if (result.ok()) {
            const auto& a = *result.allocation;
            nlohmann::json data = {{"id",a.id},{"geometry_id",a.geometry_id},{"geometry_revision",a.geometry_revision},
                {"allocation_revision",a.allocation_revision},{"total_slots",a.total_slots},
                {"total_threat",a.total_threat},{"total_score",a.total_score},{"assignments",nlohmann::json::array()},
                {"actors",nlohmann::json::array()},{"unused",nlohmann::json::array()}};
            for (const auto& x : a.assignments) data["assignments"].push_back({{"pack_id",x.pack_id},{"room_id",x.room_id}});
            for (const auto& x : a.actors) data["actors"].push_back({{"pack_id",x.pack_id},{"room_id",x.room_id},{"spawn_id",x.spawn_id},{"tile",{{"x",x.tile.x},{"y",x.tile.y}}}});
            for (const auto& x : a.unused) data["unused"].push_back({{"pack_id",x.pack_id},{"reason",x.reason}});
            output["allocation"] = std::move(data);
        }
    return output;
}
nlohmann::json geometry_json(const da::Project& p,const da::RoutingResult& routed) {
        auto output = nlohmann::json::parse(io::diagnostics_json(routed.status));
        output["format_version"] = 1; output["stage"] = "walkable_geometry"; output["engine_version"] = da::build_info().version;
        output["seed"] = p.settings.seed; output["columns"] = p.settings.columns; output["rows"] = p.settings.rows;
        output["corridor_width"] = p.settings.corridor_width;
        output["metrics"] = {{"work_units",routed.metrics.work_units},{"anchors_visited",routed.metrics.anchors_visited},
            {"floor_visited",routed.metrics.floor_visited},{"corridors_routed",routed.metrics.corridors_routed},{"dropped_events",routed.metrics.dropped_events}};
        output["metrics"]["timings_us"] = routed.metrics.timings_us;
        output["metrics"]["trace_us"] = routed.metrics.trace_us;
        output["metrics"]["timing_domain"] = "steady_clock_wall_including_validation_and_cooperative_yields";
        output["metrics"]["trace_timing"] = "nested_emission_overhead_included_in_stage_timings";
        output["events"] = nlohmann::json::array();
        for (const auto& e : routed.events) output["events"].push_back({{"kind",e.kind},{"corridor_id",e.corridor_id},{"room_id",e.room_id},{"tile",point(e.tile)}});
        output["geometry"] = nullptr;
        if (routed.ok()) {
            const auto& g = *routed.geometry;
            nlohmann::json data = {{"id",g.id},{"room_layout_id",g.room_layout_id},{"geometry_revision",g.geometry_revision},{"connected_floor_verified",true},
                {"entrance_room",g.entrance_room},{"exit_room",g.exit_room},{"entrance_marker",point(g.entrance_marker)},{"exit_marker",point(g.exit_marker)},
                {"rooms",nlohmann::json::array()},{"doors",nlohmann::json::array()},{"corridors",nlohmann::json::array()},
                {"layers",{{"floor",rows(g.layers.floor,p.settings)},{"walls",rows(g.layers.walls,p.settings)},
                    {"occupancy",rows(g.layers.occupancy,p.settings)},{"reservations",rows(g.layers.reservations,p.settings)},
                    {"movement_reserved",rows(g.movement_reserved,p.settings)}}}};
            for (const auto& r : g.rooms) {
                nlohmann::json record = {{"id",r.id},{"bounds",rectangle(r.bounds)},{"hub",point(r.hub)},
                    {"reachable",r.reachable},{"capacity",r.capacity},{"spawn_positions",nlohmann::json::array()}};
                for (const auto& spawn : r.spawn_positions) record["spawn_positions"].push_back({{"id",spawn.id},{"tile",point(spawn.tile)}});
                data["rooms"].push_back(std::move(record));
            }
            for (const auto& d : g.doors) {
                nlohmann::json record = {{"id",d.id},{"room_id",d.room_id},{"outside_anchor",point(d.outside_anchor)},
                    {"side",d.side == da::DoorSide::north ? "north" : d.side == da::DoorSide::east ? "east" : d.side == da::DoorSide::south ? "south" : "west"},
                    {"tiles",nlohmann::json::array()}};
                for (auto t : d.tiles) record["tiles"].push_back(point(t)); data["doors"].push_back(std::move(record));
            }
            for (const auto& c : g.corridors) {
                nlohmann::json record = {{"id",c.id},{"from_room",c.from_room},{"to_room",c.to_room},{"from_door",c.from_door},{"to_door",c.to_door},{"path",nlohmann::json::array()}};
                for (auto t : c.path) record["path"].push_back(point(t)); data["corridors"].push_back(std::move(record));
            }
            output["geometry"] = std::move(data);
        }
    return output;
}
nlohmann::json layout_json(const da::Project& p,const da::GenerationResult& generated) {
        auto output = nlohmann::json::parse(io::diagnostics_json(generated.status));
        output["format_version"] = 1;
        output["engine_version"] = da::build_info().version;
        output["stage"] = "room_layout";
        output["seed"] = p.settings.seed;
        output["columns"] = p.settings.columns; output["rows"] = p.settings.rows;
        output["metrics"] = {{"attempts",generated.metrics.attempts},{"work_units",generated.metrics.work_units},
            {"rejected_candidates",generated.metrics.rejected_candidates},{"backtracks",generated.metrics.backtracks},
            {"dropped_events",generated.metrics.dropped_events}};
        output["metrics"]["timings_us"] = generated.metrics.timings_us;
        output["metrics"]["trace_us"] = generated.metrics.trace_us;
        output["metrics"]["timing_domain"] = "steady_clock_wall_including_validation_and_cooperative_yields";
        output["metrics"]["trace_timing"] = "nested_emission_overhead_included_in_stage_timings";
        output["events"] = nlohmann::json::array();
        for (const auto& e : generated.events) output["events"].push_back({{"kind",e.kind},{"reason",e.reason},
            {"node",e.node},{"bounds",rectangle(e.bounds)},{"room_id",e.room_id},{"attempt",e.attempt},
            {"cut",e.cut},{"first_child_rooms",e.first_child_rooms}});
        output["layout"] = nullptr;
        if (generated.ok()) {
            const auto& layout = *generated.layout;
            nlohmann::json data = {{"id",layout.id},{"geometry_revision",layout.geometry_revision},{"entrance",layout.terminals.entrance},{"exit",layout.terminals.exit},
                {"rooms",nlohmann::json::array()},{"partitions",nlohmann::json::array()},{"connections",nlohmann::json::array()},
                {"occupancy",rows(layout.occupancy,p.settings)},{"reservations",rows(layout.reservations,p.settings)},
                {"connected_floor_verified",false}};
            for (const auto& r : layout.rooms) data["rooms"].push_back({{"id",r.id},{"name",r.name},{"bounds",rectangle(r.bounds)},
                {"role",da::role_name(r.role)},{"tags",r.tags},{"lock_position",r.lock_position},{"lock_size",r.lock_size},
                {"capacity_override",r.capacity_override ? nlohmann::json(*r.capacity_override) : nlohmann::json(nullptr)}});
            for (const auto& n : layout.partitions) data["partitions"].push_back({{"id",n.id},{"parent",n.parent},
                {"first_child",n.first_child},{"second_child",n.second_child},{"bounds",rectangle(n.bounds)},
                {"requested_rooms",n.requested_rooms},{"allowed_tiles",n.allowed_tiles},{"free_tiles",n.free_tiles},
                {"axis",n.axis == da::SplitAxis::none ? "none" : n.axis == da::SplitAxis::x ? "x" : "y"},
                {"cut",n.cut},{"room_id",n.room_id},{"intersecting_fixed_rooms",n.intersecting_fixed_rooms}});
            for (const auto& c : layout.connections) data["connections"].push_back({{"from",c.from},{"to",c.to},{"fixed_attachment",c.fixed_attachment}});
            output["layout"] = std::move(data);
        }
    return output;
}
nlohmann::json error_json(const da::Status& status,const char* stage) {
    auto output = nlohmann::json::parse(io::diagnostics_json(status));
    output["format_version"] = 1; output["engine_version"] = da::build_info().version;
    output["stage"] = stage; output["result"] = nullptr; output["optimal"] = false;
    return output;
}
}

#include "generation_cli.h"
#include "dungeon_architect/result_json.h"
#include "dungeon_architect/generation.h"
#include "dungeon_architect/routing.h"
#include "dungeon_architect/allocation.h"
#include "dungeon_architect/project_io.h"
#include "dungeon_architect/build_info.h"
#include "nlohmann/json.hpp"
#include <algorithm>
#include <charconv>
#include <csignal>
#include <iostream>
#include <set>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#endif

namespace da = dungeon_architect;
namespace io = da::project_io;
namespace {
using namespace da::result_io;
volatile std::sig_atomic_t interrupted = 0;
void interrupt(int) { interrupted = 1; }
struct SignalGuard {
    using Handler = void (*)(int);
    Handler previous;
    SignalGuard() : previous(std::signal(SIGINT,interrupt)) { interrupted = 0; }
    ~SignalGuard() { if (previous != SIG_ERR) std::signal(SIGINT,previous); }
};
template<class T> bool number(const std::string& value, T& output) {
    const auto result = std::from_chars(value.data(),value.data()+value.size(),output);
    return result.ec == std::errc{} && result.ptr == value.data()+value.size();
}
int code(da::Outcome outcome) {
    switch (outcome) {
    case da::Outcome::success: return 0;
    case da::Outcome::invalid_input: return 2;
    case da::Outcome::unsupported_size: case da::Outcome::unsupported_schema: return 3;
    case da::Outcome::io_failure: return 4;
    case da::Outcome::resource_failure: return 5;
    case da::Outcome::cancelled: return 6;
    case da::Outcome::search_exhausted: return 7;
    case da::Outcome::stale_result: return 8;
    }
    return 9;
}
struct RunOptions {
    bool json = false, detailed = false, force = false, metrics = false, no_map = false;
    bool combined = false, optimize = false;
    da::Rect preview{0,0,80,40};
    std::optional<std::uint32_t> seed;
    std::optional<std::int64_t> attempts, work, time, budget;
    std::optional<std::int32_t> rooms, width;
    std::filesystem::path output, cancel_file;
    std::size_t events = 256;
};
int usage() {
    std::cerr << "Usage: dungeon_cli generate|route|optimize|run FILE [options]\n"
        "       dungeon_cli export FILE OUTPUT [options]\n"
        "Options: --json --seed UINT32 --attempts N --work N --time-ms N\n"
        "  --rooms N --corridor-width N --events 0..4096 --metrics\n"
        "  --output FILE --force --cancel-file FILE --preview X Y W H --no-map\n"
        "Optimization/run/export also accept --budget N and --detailed-trace.\n";
    return 64;
}
bool parse_options(const std::vector<std::string>& args,RunOptions& o) {
    o.combined = args[1] == "run" || args[1] == "export";
    o.optimize = o.combined || args[1] == "optimize";
    const std::size_t first = args[1] == "export" ? 4 : 3;
    if (args.size() < first) return false;
    if (first == 4) o.output = std::filesystem::u8path(args[3]);
    std::set<std::string> seen;
    for (std::size_t i = first; i < args.size(); ++i) {
        const auto& flag = args[i]; if (!seen.insert(flag).second) return false;
        if (flag == "--json") { o.json = true; continue; }
        if (flag == "--force") { o.force = true; continue; }
        if (flag == "--metrics") { o.metrics = true; continue; }
        if (flag == "--no-map") { o.no_map = true; continue; }
        if (flag == "--detailed-trace" && o.optimize) { o.detailed = true; continue; }
        if (++i >= args.size()) return false;
        if (flag == "--output" && first != 4) o.output = std::filesystem::u8path(args[i]);
        else if (flag == "--cancel-file") o.cancel_file = std::filesystem::u8path(args[i]);
        else if (flag == "--preview") {
            if (i+3 >= args.size() || !number(args[i],o.preview.x) || !number(args[i+1],o.preview.y) ||
                !number(args[i+2],o.preview.width) || !number(args[i+3],o.preview.height)) return false;
            i += 3;
            if (!o.preview.valid() || o.preview.width > 160 || o.preview.height > 80) return false;
        } else if (flag == "--seed") {
            std::uint32_t value = 0; if (!number(args[i],value)) return false; o.seed = value;
        } else if (flag == "--events") {
            std::uint32_t value = 0; if (!number(args[i],value) || value > 4096) return false; o.events = value;
        } else {
            std::int64_t value = 0; if (!number(args[i],value) || value < 0 || (value == 0 && flag != "--budget")) return false;
            if (flag == "--attempts") o.attempts = value;
            else if (flag == "--work") o.work = value;
            else if (flag == "--time-ms") o.time = value;
            else if (flag == "--budget" && o.optimize) o.budget = value;
            else if ((flag == "--rooms" || flag == "--corridor-width") && value <= std::numeric_limits<std::int32_t>::max()) {
                if (flag == "--rooms") o.rooms = static_cast<std::int32_t>(value);
                else o.width = static_cast<std::int32_t>(value);
            } else return false;
        }
    }
    return !(o.force && o.output.empty()) && !(o.no_map && seen.count("--preview")) &&
        !(seen.count("--output") && o.output.empty()) && !(seen.count("--cancel-file") && o.cancel_file.empty()) &&
        !(first == 4 && o.output.empty());
}
da::Status path_error(const std::filesystem::path& path,const std::string& message) {
    return da::failure(da::Outcome::io_failure,"export_path",path.u8string(),message,"Choose a separate writable result filename; use --force to replace an existing export.");
}
bool same_file(const std::filesystem::path& a,const std::filesystem::path& b) {
    if (a.empty() || b.empty()) return false;
    std::error_code ec;
    const bool first_exists = std::filesystem::exists(a,ec);
    if (ec) throw std::filesystem::filesystem_error("Cannot inspect path",a,ec);
    const bool second_exists = std::filesystem::exists(b,ec);
    if (ec) throw std::filesystem::filesystem_error("Cannot inspect path",b,ec);
    if (first_exists && second_exists) {
        const bool equivalent = std::filesystem::equivalent(a,b,ec);
        if (ec) throw std::filesystem::filesystem_error("Cannot compare file identities",a,b,ec);
        if (equivalent) return true;
    }
    // Lexical normalization does not require opening ancestors outside the
    // workspace. Existing aliases/hard links are covered by file identity above.
    const auto first = std::filesystem::absolute(a).lexically_normal();
    const auto second = std::filesystem::absolute(b).lexically_normal();
#ifdef _WIN32
    return CompareStringOrdinal(first.c_str(),-1,second.c_str(),-1,TRUE) == CSTR_EQUAL;
#else
    return first == second;
#endif
}
da::Status check_paths(const std::filesystem::path& source,const RunOptions& o) {
    try {
        if (!o.cancel_file.empty() && (same_file(source,o.cancel_file) || same_file(o.output,o.cancel_file)))
            return path_error(o.cancel_file,"Cancellation marker must be separate from source and result files.");
        if (o.output.empty()) return {};
        if (same_file(source,o.output)) return path_error(o.output,"A derived result cannot replace its source project, even with --force.");
        if (o.output.filename().empty()) return path_error(o.output,"A result filename is required.");
        std::error_code ec;
        const bool exists = std::filesystem::exists(o.output,ec);
        if (ec) return path_error(o.output,ec.message());
        if (exists && (!o.force || !std::filesystem::is_regular_file(o.output,ec)))
            return path_error(o.output,"The result path already exists or is not a regular file.");
        if (ec) return path_error(o.output,ec.message());
        const auto parent = o.output.has_parent_path() ? o.output.parent_path() : std::filesystem::path(".");
        if (!std::filesystem::is_directory(parent,ec) || ec) return path_error(o.output,"The output directory does not exist or is inaccessible.");
        return {};
    } catch (const std::filesystem::filesystem_error& e) { return path_error(o.output,e.what()); }
}
void print_errors(const da::Status& status) {
    std::cerr << da::outcome_name(status.outcome) << '\n';
    for (const auto& d : status.diagnostics) {
        std::cerr << d.code << " [" << d.path << "]: " << d.message << '\n' << d.recovery << '\n';
        for (const auto& id : d.affected_ids) std::cerr << "  ID: " << id << '\n';
        for (auto t : d.affected_tiles) std::cerr << "  Tile: " << t.x << ',' << t.y << '\n';
    }
}
int report_error(const da::Status& status,const RunOptions& o,const char* stage) {
    if (o.json) std::cout << error_json(status,stage).dump(2) << '\n'; else print_errors(status);
    return code(status.outcome);
}
void preview(const da::Project& p,const da::RoomLayoutSnapshot& layout,const da::GeometrySnapshot* g,
             const da::AllocationSnapshot* allocation,const da::Rect& crop) {
    const auto index = [&](da::Tile t) { return static_cast<std::size_t>(t.y*p.settings.columns+t.x); };
    std::vector<char> cells(p.allowed_mask.size(),' ');
    if (g) {
        for (std::size_t i = 0; i < cells.size(); ++i) {
            if (!p.allowed_mask[i]) cells[i] = '~'; if (g->layers.walls[i]) cells[i] = '#'; if (g->layers.floor[i]) cells[i] = '.';
        }
        for (const auto& room : g->rooms) for (const auto& s : room.spawn_positions) cells[index(s.tile)] = 's';
        for (const auto& door : g->doors) for (auto t : door.tiles) cells[index(t)] = '+';
        if (allocation) for (const auto& a : allocation->actors) cells[index(a.tile)] = 'A';
        cells[index(g->entrance_marker)] = '@'; cells[index(g->exit_marker)] = '>';
        std::cout << "Map: @ entrance, > exit, A actor, + door, s free spawn, . floor, # wall, ~ outside mask\n";
    } else {
        for (std::size_t i = 0; i < cells.size(); ++i) { cells[i] = p.allowed_mask[i] ? '+' : '.'; if (layout.reservations[i]) cells[i] = ':'; }
        for (const auto& room : layout.rooms) for (int y = room.bounds.y; y < room.bounds.bottom(); ++y) for (int x = room.bounds.x; x < room.bounds.right(); ++x)
            cells[index({x,y})] = room.id == layout.terminals.entrance ? 'E' : room.id == layout.terminals.exit ? 'X' : room.role == da::RoomRole::boss ? 'B' : 'R';
        std::cout << "Map: . outside, + allowed, : margin, R room, E entrance, X exit, B boss\n";
    }
    const auto end_x = std::min<std::int64_t>(crop.right(),p.settings.columns), end_y = std::min<std::int64_t>(crop.bottom(),p.settings.rows);
    std::cout << "Preview origin (" << crop.x << ',' << crop.y << "), " << end_x-crop.x << 'x' << end_y-crop.y
        << " of " << p.settings.columns << 'x' << p.settings.rows << " (one character per tile; JSON contains the full map)\n";
    for (int y = crop.y; y < end_y; ++y) { for (int x = crop.x; x < end_x; ++x) std::cout << cells[index({x,y})]; std::cout << '\n'; }
}
void print_summary(const da::Project& p,const da::GenerationResult& generated,const da::RoutingResult* routed,
                   const da::AllocationResult* allocated,const RunOptions& o) {
    const auto& layout = *generated.layout;
    std::cout << "Room layout: " << layout.rooms.size() << " / " << p.settings.room_count << " rooms; seed " << p.settings.seed
        << "; " << layout.partitions.size() << " partition nodes\n";
    for (const auto& r : layout.rooms) std::cout << r.id << ": (" << r.bounds.x << ',' << r.bounds.y << ") " << r.bounds.width << 'x' << r.bounds.height
        << ((r.lock_position || r.lock_size) ? " locked" : " generated") << '\n';
    const auto* g = routed ? &*routed->geometry : nullptr;
    const auto* a = allocated ? &*allocated->allocation : nullptr;
    if (g) {
        std::cout << "Connected dungeon: " << g->rooms.size() << " rooms, " << g->corridors.size() << " corridors, width " << p.settings.corridor_width << '\n'
            << "Reachable floor cells: " << routed->metrics.floor_visited << "; entrance: " << g->entrance_room << "; exit: " << g->exit_room << '\n';
        for (const auto& r : g->rooms) std::cout << r.id << ": " << r.capacity << " capacity, " << r.spawn_positions.size() << " valid spawn cells\n";
    } else std::cout << layout.connections.size() << " abstract connection requirements; use route to build and verify walkable floor.\n";
    if (a) {
        std::cout << "Exact optimum for " << g->rooms.size() << " routed rooms: score " << a->total_score << ", threat " << a->total_threat
            << '/' << p.settings.threat_budget << ", actors " << a->total_slots << '\n';
        for (const auto& x : a->assignments) std::cout << x.room_id << " <- " << x.pack_id << '\n';
        for (const auto& x : a->actors) std::cout << "  " << x.pack_id << " @ " << x.tile.x << ',' << x.tile.y << " (" << x.spawn_id << ")\n";
        for (const auto& x : a->unused) std::cout << "Unused " << x.pack_id << ": " << x.reason << '\n';
    }
    if (o.metrics) {
        std::cout << "Generation work: " << generated.metrics.work_units << "; attempts: " << generated.metrics.attempts << "; backtracks: " << generated.metrics.backtracks << '\n';
        if (routed) std::cout << "Routing work: " << routed->metrics.work_units << "; BFS anchors: " << routed->metrics.anchors_visited << '\n';
        if (allocated) std::cout << "Allocation work: " << allocated->metrics.work_units << "; DP transitions: " << allocated->metrics.transitions
            << "; estimated table bytes: " << allocated->metrics.estimated_bytes << "; estimated work: " << allocated->metrics.estimated_work << '\n';
    }
    if (!o.no_map) preview(p,layout,g,a,o.preview);
}
} // namespace

int run_generation(const std::vector<std::string>& args) {
    RunOptions o; if (!parse_options(args,o)) return usage();
#ifdef _WIN32
    // Match the atomic UTF-8 writer byte-for-byte; CRT text mode expands LF to
    // CRLF on stdout. This process executes exactly one CLI command.
    if (o.json) _setmode(_fileno(stdout),_O_BINARY);
#endif
    const auto source_path = std::filesystem::u8path(args[2]);
    auto loaded = io::read(source_path); if (!loaded.ok()) return report_error(loaded.status,o,"input");
    auto& p = *loaded.value;
    if (o.seed) p.settings.seed = *o.seed;
    if (o.attempts) p.settings.max_generation_attempts = *o.attempts;
    if (o.work) p.settings.max_work_units = *o.work;
    if (o.time) p.settings.max_time_ms = *o.time;
    if (o.budget) p.settings.threat_budget = *o.budget;
    if (o.rooms) p.settings.room_count = *o.rooms;
    if (o.width) p.settings.corridor_width = *o.width;
    auto status = da::validate_project(p); if (!status.ok()) return report_error(status,o,"input");
    if (!o.no_map && (o.preview.x >= p.settings.columns || o.preview.y >= p.settings.rows))
        return report_error(da::failure(da::Outcome::invalid_input,"preview_bounds","/preview","Preview origin is outside the canvas.","Choose an origin inside the canvas."),o,"input");
    status = check_paths(source_path,o); if (!status.ok()) return report_error(status,o,"export");
    SignalGuard signals; da::Status control_status;
    da::GenerationOptions options; options.max_events = o.events;
    options.cancelled = [&] {
        if (interrupted) return true;
        if (o.cancel_file.empty()) return false;
        std::error_code ec; const bool present = std::filesystem::exists(o.cancel_file,ec);
        if (ec) { control_status = path_error(o.cancel_file,"Cannot inspect cancellation marker: "+ec.message()); return true; }
        return present;
    };
    auto generated = da::generate_rooms(p,options);
    if (!control_status.ok()) generated.status = control_status;
    auto doc = layout_json(p,generated);
    nlohmann::json stages = {{"generation",doc}}; stages["generation"].erase("layout");
    std::optional<da::RoutingResult> routed; std::optional<da::AllocationResult> allocated;
    status = generated.status;
    if (status.ok() && args[1] != "generate") {
        routed = da::route_corridors(p,*generated.layout,options);
        if (!control_status.ok()) routed->status = control_status;
        status = routed->status; doc = geometry_json(p,*routed);
        stages["routing"] = doc; stages["routing"].erase("geometry");
    }
    if (status.ok() && o.optimize) {
        da::AllocationOptions opt; opt.max_events = o.events; opt.detailed_trace = o.detailed; opt.cancelled = options.cancelled;
        allocated = da::allocate_encounters(p,*generated.layout,*routed->geometry,opt);
        if (!control_status.ok()) allocated->status = control_status;
        status = allocated->status; doc = allocation_json(p,*allocated);
        stages["allocation"] = doc; stages["allocation"].erase("allocation");
    }
    if (o.combined) {
        const auto failed_stage = status.ok() ? nlohmann::json(nullptr) : doc["stage"];
        doc = error_json(status,"pipeline"); doc["failed_stage"] = failed_stage;
        doc["stages"] = std::move(stages); doc["seed"] = p.settings.seed; doc["optimal"] = status.ok();
        if (status.ok()) doc["result"] = {{"layout",layout_json(p,generated)["layout"]},
            {"geometry",geometry_json(p,*routed)["geometry"]},{"allocation",allocation_json(p,*allocated)["allocation"]}};
    }
    if (status.ok()) {
        auto source = io::serialize(p); if (!source.ok()) return report_error(source.status,o,"export");
        if (o.combined) doc["result"]["source_project"] = nlohmann::json::parse(*source.value);
        else doc["source_project"] = nlohmann::json::parse(*source.value);
        // Stage snapshots use local deterministic IDs, with explicit dependency
        // links; the embedded effective source supplies complete replay context.
        std::string encoded;
        if (o.json || !o.output.empty()) encoded = doc.dump(2)+"\n";
        if (options.cancelled()) {
            if (!control_status.ok()) return report_error(control_status,o,"export");
            return report_error(da::failure(da::Outcome::cancelled,"export_cancelled","/pipeline","Run cancelled before publishing its result.","Clear the cancellation request and rerun."),o,"export");
        }
        if (!o.output.empty()) {
            // Recheck source/marker aliases immediately before the atomic commit.
            status = check_paths(source_path,o); if (!status.ok()) return report_error(status,o,"export");
            status = io::write_text_atomic(encoded,o.output,o.force ? io::SaveMode::replace_existing : io::SaveMode::create_only);
            if (!status.ok()) return report_error(status,o,"export");
        }
        if (o.json) std::cout << encoded;
        else {
            print_summary(p,generated,routed ? &*routed : nullptr,allocated ? &*allocated : nullptr,o);
            if (!o.output.empty()) std::cout << "Exported JSON: " << o.output.u8string() << '\n';
        }
    } else if (o.json) std::cout << doc.dump(2) << '\n';
    else print_errors(status);
    return code(status.outcome);
}

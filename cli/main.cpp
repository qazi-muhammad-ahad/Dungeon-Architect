#include "dungeon_architect/build_info.h"
#include "dungeon_architect/project_io.h"
#include "dungeon_architect/geometry.h"
#include "generation_cli.h"
#include "nlohmann/json.hpp"

#include <algorithm>
#include <charconv>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#endif

namespace da = dungeon_architect;
namespace io = dungeon_architect::project_io;
namespace {
int exit_code(da::Outcome outcome) {
    switch (outcome) {
    case da::Outcome::success: return 0;
    case da::Outcome::invalid_input: return 2;
    case da::Outcome::unsupported_size:
    case da::Outcome::unsupported_schema: return 3;
    case da::Outcome::io_failure: return 4;
    case da::Outcome::resource_failure: return 5;
    case da::Outcome::cancelled: return 6;
    case da::Outcome::search_exhausted: return 7;
    case da::Outcome::stale_result: return 8;
    }
    return 9;
}
int report(const da::Status& status, bool json) {
    if (json) std::cout << io::diagnostics_json(status);
    else if (!status.ok()) {
        std::cerr << da::outcome_name(status.outcome) << '\n';
        for (const auto& error : status.diagnostics) {
            std::cerr << error.code << " at " << (error.path.empty() ? "/" : error.path)
                      << ": " << error.message << '\n' << "  " << error.recovery << '\n';
            if (!error.affected_ids.empty()) {
                std::cerr << "  IDs:";
                for (const auto& id : error.affected_ids) std::cerr << ' ' << id;
                std::cerr << '\n';
            }
            if (!error.affected_tiles.empty()) {
                std::cerr << "  Tiles:";
                for (const auto& tile : error.affected_tiles) std::cerr << " (" << tile.x << ',' << tile.y << ')';
                std::cerr << '\n';
            }
        }
    }
    return exit_code(status.outcome);
}
void help() {
    std::cout << "Dungeon Architect - C++ project API / phases 2 through 7\n"
        "Usage:\n"
        "  dungeon_cli --help | --version\n"
        "  dungeon_cli new FILE [--name NAME] [--seed UINT32] [--force] [--json]\n"
        "  dungeon_cli validate FILE [--for-allocation] [--for-generation] [--json]\n"
        "  dungeon_cli inspect FILE [--json]\n"
        "  dungeon_cli save INPUT OUTPUT [--force] [--json]\n"
        "  dungeon_cli mask-info FILE [--json]\n"
        "  dungeon_cli mask INPUT OUTPUT rectangle|ellipse|l-shape X Y W H [--force] [--json]\n"
        "  dungeon_cli paint|fill INPUT OUTPUT X Y 0|1 [--force] [--json]\n"
        "  dungeon_cli room-add|room-set INPUT OUTPUT ID X Y W H [--name NAME]\n"
        "      [--role normal|entrance|exit|boss] [--locked (add only)] [--force] [--json]\n"
        "  dungeon_cli room-lock INPUT OUTPUT ID POSITION_0_OR_1 SIZE_0_OR_1 [--force] [--json]\n"
        "  dungeon_cli room-remove INPUT OUTPUT ID [--force] [--json]\n"
        "  dungeon_cli generate FILE [--json] [--seed UINT32] [--attempts N]\n"
        "      [--work N] [--time-ms N] [--events 0..4096]\n"
        "  dungeon_cli route FILE [same options as generate]\n"
        "  dungeon_cli optimize FILE [same options, plus --budget N, --detailed-trace]\n"
        "  dungeon_cli run FILE [same options as optimize]\n"
        "  dungeon_cli export FILE OUTPUT [same options as run]\n"
        "Pipeline options: --output FILE --force --metrics --cancel-file FILE\n"
        "  --rooms N --corridor-width N --preview X Y W H (up to 160x80) --no-map\n"
        "run/export include source, layout, geometry, allocation and per-stage metrics/traces.\n"
        "Files use schema version 1. Save writes canonical JSON atomically.\n"
        "Existing output files require --force. Generate emits rooms; route builds and verifies walkable floor.\n";
}
int usage(const std::string& message) {
    std::cerr << message << " Use --help for supported commands.\n";
    return 64;
}
bool integer(const std::string& text, std::int32_t& value) {
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
    return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
}
std::optional<int> geometry_command(const std::vector<std::string>& args) {
    const auto& command = args[1];
    const bool info = command == "mask-info", preset = command == "mask";
    const bool paint = command == "paint", fill = command == "fill";
    const bool add = command == "room-add", edit = command == "room-set";
    const bool lock = command == "room-lock", remove = command == "room-remove";
    if (!(info || preset || paint || fill || add || edit || lock || remove)) return std::nullopt;
    const std::size_t first_option = info ? 3 : (preset || add || edit) ? 9 : (paint || fill || lock) ? 7 : 5;
    if (args.size() < first_option) return usage("Missing geometry command arguments.");
    bool json = false, force = false, locked = false;
    std::optional<std::string> name;
    std::optional<da::RoomRole> role;
    for (auto i = first_option; i < args.size(); ++i) {
        if (args[i] == "--json") json = true;
        else if (args[i] == "--force" && !info) force = true;
        else if (args[i] == "--locked" && add) locked = true;
        else if (args[i] == "--name" && (add || edit) && i + 1 < args.size()) name = args[++i];
        else if (args[i] == "--role" && (add || edit) && i + 1 < args.size()) {
            const auto& value = args[++i];
            if (value == "normal") role = da::RoomRole::normal;
            else if (value == "entrance") role = da::RoomRole::entrance;
            else if (value == "exit") role = da::RoomRole::exit;
            else if (value == "boss") role = da::RoomRole::boss;
            else return usage("Unknown room role.");
        } else return usage("Unknown or incomplete option: " + args[i]);
    }
    da::Rect bounds;
    if ((preset || add || edit) && (!integer(args[5], bounds.x) || !integer(args[6], bounds.y) ||
        !integer(args[7], bounds.width) || !integer(args[8], bounds.height))) return usage("Bounds must be signed 32-bit integers.");
    da::Tile tile;
    std::int32_t value = 0, size_lock = 0;
    if ((paint || fill) && (!integer(args[4], tile.x) || !integer(args[5], tile.y) ||
        !integer(args[6], value) || (value != 0 && value != 1))) return usage("Use integer X Y and a tile value of 0 or 1.");
    if (lock && (!integer(args[5], value) || !integer(args[6], size_lock) ||
        (value != 0 && value != 1) || (size_lock != 0 && size_lock != 1))) return usage("Lock flags must be 0 or 1.");
    da::ProjectSession session;
    auto status = io::load_into(session, std::filesystem::u8path(args[2]));
    if (!status.ok()) return report(status, json);
    if (info) {
        auto analyzed = da::analyze_mask(session.project());
        if (!analyzed.ok()) return report(analyzed.status, json);
        const auto& analysis = *analyzed.value;
        auto prepared = da::prepare_geometry(session.project());
        nlohmann::json components = nlohmann::json::array();
        for (const auto& component : analysis.components) {
            const auto& r = component.bounds;
            components.push_back({{"id", component.id}, {"tiles", component.tiles.size()},
                {"detached", component.id != analysis.primary_component},
                {"bounds", {{"x", r.x}, {"y", r.y}, {"width", r.width}, {"height", r.height}}}});
        }
        if (json) {
            nlohmann::json result = {{"components", components}, {"primary_component", analysis.primary_component},
                {"columns", session.project().settings.columns}, {"rows", session.project().settings.rows},
                {"labels", analysis.labels}, {"generation_preflight", nlohmann::json::parse(io::diagnostics_json(prepared.status))}};
            if (prepared.ok()) {
                result["mandatory_rooms"] = prepared.value->mandatory_rooms;
                result["remaining_rooms"] = prepared.value->remaining_rooms;
                result["reservations"] = prepared.value->reservations.blocked();
                result["footprint_owners"] = prepared.value->reservations.footprint_owners();
                result["fixed_room_ids"] = nlohmann::json::array();
                for (const auto& room : prepared.value->reservations.fixed_rooms()) result["fixed_room_ids"].push_back(room.id);
            }
            std::cout << result.dump(2) << '\n';
        } else {
            std::cout << "Mask components: " << analysis.components.size() << "; primary: " << analysis.primary_component << '\n';
            for (const auto& component : analysis.components)
                std::cout << "  " << component.id << ": " << component.tiles.size() << " tiles"
                          << (component.id == analysis.primary_component ? " (primary)" : " (detached)") << '\n';
            if (prepared.ok()) std::cout << "Locked rooms: " << prepared.value->mandatory_rooms << "; rooms still required: " << prepared.value->remaining_rooms << '\n';
            const auto& s = session.project().settings;
            std::cout << "Map (top-left, at most 80 x 40): . outside, + primary, ! detached, R locked room, : reserved margin\n";
            for (std::int32_t y = 0; y < std::min(s.rows, 40); ++y) {
                for (std::int32_t x = 0; x < std::min(s.columns, 80); ++x) {
                    const auto i = static_cast<std::size_t>(y) * static_cast<std::size_t>(s.columns) + static_cast<std::size_t>(x);
                    char c = analysis.labels[i] < 0 ? '.' : analysis.labels[i] == analysis.primary_component ? '+' : '!';
                    if (prepared.ok() && prepared.value->reservations.blocked()[i]) c = prepared.value->reservations.footprint_owners()[i] >= 0 ? 'R' : ':';
                    std::cout << c;
                }
                std::cout << '\n';
            }
            if (!prepared.ok()) report(prepared.status, false);
        }
        // Analysis remains available even when generation preflight rejects the source.
        return 0;
    }
    if (preset) {
        da::MaskPreset shape;
        if (args[4] == "rectangle") shape = da::MaskPreset::rectangle;
        else if (args[4] == "ellipse") shape = da::MaskPreset::ellipse;
        else if (args[4] == "l-shape") shape = da::MaskPreset::l_shape;
        else return usage("Unknown mask preset.");
        status = da::apply_mask_preset(session, shape, bounds);
    } else if (paint || fill) {
        status = paint ? da::paint_tiles(session, {tile}, value != 0) : da::flood_fill(session, tile, value != 0);
    } else if (remove) status = da::remove_room(session, args[4]);
    else {
        da::Room room;
        if (add) { room.id = args[4]; room.name = args[4]; room.lock_position = room.lock_size = locked; }
        else {
            const auto& rooms = session.project().rooms;
            const auto found = std::find_if(rooms.begin(), rooms.end(), [&](const da::Room& r) { return r.id == args[4]; });
            if (found == rooms.end()) return report(da::failure(da::Outcome::invalid_input, "room_not_found", "/source/rooms", "No room has the requested ID.", "Use inspect to find room IDs."), json);
            room = *found;
        }
        if (lock) { room.lock_position = value != 0; room.lock_size = size_lock != 0; }
        else room.bounds = bounds;
        if (name) room.name = *name;
        if (role) room.role = *role;
        status = add ? da::add_room(session, room) : da::edit_room(session, args[4], room);
    }
    if (!status.ok()) return report(status, json);
    status = io::save_atomic(session.project(), std::filesystem::u8path(args[3]), force ? io::SaveMode::replace_existing : io::SaveMode::create_only);
    if (status.ok() && !json) std::cout << "Saved validated edit: " << args[3] << '\n';
    return report(status, json);
}
int run(const std::vector<std::string>& args) {
    if (args.size() == 1 || (args.size() == 2 && args[1] == "--help")) { help(); return 0; }
    if (args.size() == 2 && args[1] == "--version") {
        const auto info = da::build_info();
        std::cout << "Dungeon Architect " << info.version << " (" << info.pointer_bits << "-bit)\n";
        return 0;
    }
    if (args[1] == "generate" || args[1] == "route" || args[1] == "optimize" || args[1] == "run" || args[1] == "export") return run_generation(args);
    if (auto result = geometry_command(args)) return *result;
    const auto& command = args[1];
    if (command != "new" && command != "validate" && command != "inspect" && command != "save") return usage("Unknown command.");
    const std::size_t first_option = command == "save" ? 4 : 3;
    if (args.size() < first_option) return usage("Missing file argument.");
    bool json = false, force = false, allocation = false, generation = false;
    auto project = da::make_default_project();
    for (std::size_t i = first_option; i < args.size(); ++i) {
        const auto& option = args[i];
        if (option == "--json") json = true;
        else if (option == "--force" && (command == "new" || command == "save")) force = true;
        else if (option == "--for-allocation" && command == "validate") allocation = true;
        else if (option == "--for-generation" && command == "validate") generation = true;
        else if (option == "--name" && command == "new" && i + 1 < args.size()) project.name = args[++i];
        else if (option == "--seed" && command == "new" && i + 1 < args.size()) {
            const auto& value = args[++i];
            const auto parsed = std::from_chars(value.data(), value.data() + value.size(), project.settings.seed);
            if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) return usage("Seed must be an unsigned 32-bit integer.");
        } else return usage("Unknown or incomplete option: " + option + ".");
    }
    if (command != "new") {
        auto loaded = io::read(std::filesystem::u8path(args[2]));
        if (!loaded.ok()) return report(loaded.status, json);
        project = std::move(*loaded.value);
    }
    if (command == "new" || command == "save") {
        const auto path = std::filesystem::u8path(args[command == "save" ? 3 : 2]);
        std::error_code ec;
        const bool exists = std::filesystem::exists(path, ec);
        if (ec || (exists && !force)) {
            return report(da::failure(da::Outcome::io_failure, "output_exists_or_unavailable", path.u8string(),
                ec ? ec.message() : "The destination already exists.", "Choose another path or explicitly pass --force to replace it."), json);
        }
        const auto status = io::save_atomic(project, path, force ? io::SaveMode::replace_existing : io::SaveMode::create_only);
        if (status.ok() && !json) std::cout << "Saved schema 1 project: " << path.u8string() << '\n';
        return report(status, json);
    }
    if (command == "validate") {
        auto status = allocation ? da::validate_allocation_workload(project) : da::validate_project(project);
        if (status.ok() && generation) status = da::prepare_geometry(project).status;
        if (status.ok() && !json) std::cout << "Valid source project: " << project.name
            << (allocation ? " (active inventory within exact-solve limit)" : "")
            << (generation ? " (mask and fixed-room preflight passed; layout not generated)" : "") << '\n';
        return report(status, json);
    }
    if (json) {
        const auto encoded = io::serialize(project);
        if (!encoded.ok()) return report(encoded.status, true);
        std::cout << *encoded.value;
    } else {
        const auto& s = project.settings;
        const auto allowed = std::count(project.allowed_mask.begin(), project.allowed_mask.end(), std::uint8_t{1});
        const auto active = std::count_if(project.packs.begin(), project.packs.end(), [](const da::Pack& p) { return p.active; });
        std::cout << project.name << '\n' << "Canvas: " << s.columns << " x " << s.rows
            << "; allowed tiles: " << allowed << '\n'
            << "Rooms: " << s.room_count << " requested; " << project.rooms.size() << " source rooms\n"
            << "Room sizes: " << s.min_room_width << '-' << s.max_room_width << " wide, "
            << s.min_room_height << '-' << s.max_room_height << " high\n"
            << "Packs: " << project.packs.size() << " catalogue; " << active << " active (exact-solve cap 14)\n"
            << "Threat budget: " << s.threat_budget << "; seed: " << s.seed << '\n'
            << "Source document only; no generated dungeon or allocation.\n";
    }
    return 0;
}
int protected_run(const std::vector<std::string>& args) {
    try { return run(args); }
    catch (const std::bad_alloc&) { std::cerr << "resource_failure: insufficient memory.\n"; return 5; }
    catch (const std::exception& e) { std::cerr << "unexpected_failure: " << e.what() << '\n'; return 9; }
}
}
#ifdef _WIN32
int wmain(int argc, wchar_t* argv[]) {
    try {
        std::vector<std::string> args;
        for (int i = 0; i < argc; ++i) args.push_back(std::filesystem::path(argv[i]).u8string());
        return protected_run(args);
    } catch (const std::exception& e) { std::cerr << "Argument conversion failed: " << e.what() << '\n'; return 64; }
}
#else
int main(int argc, char* argv[]) { return protected_run({argv, argv + argc}); }
#endif

#include "dungeon_architect/project_io.h"
#include "dungeon_architect/build_info.h"
#include <nlohmann/json.hpp>

#include <algorithm>
#include <set>
#include <stdexcept>

namespace dungeon_architect::project_io {
namespace {
using Json = nlohmann::json;
struct InputError { Status status; };
[[noreturn]] void reject(const std::string& code, const std::string& path,
                         const std::string& message, Outcome outcome = Outcome::invalid_input) {
    throw InputError{failure(outcome, code, path, message, "Correct the file using the version 1 schema and retry.")};
}
void object(const Json& value, const std::string& path, std::initializer_list<const char*> keys) {
    if (!value.is_object()) reject("json_type", path, "Expected an object.");
    std::set<std::string> expected;
    for (const auto* key : keys) {
        expected.insert(key);
        if (!value.contains(key)) reject("missing_field", path + "/" + key, "Required field is missing.");
    }
    for (auto it = value.begin(); it != value.end(); ++it) {
        if (!expected.count(it.key())) reject("unknown_field", path, "Unknown field: " + it.key());
    }
}
std::int64_t integer(const Json& value, const std::string& path) {
    if (!value.is_number_integer()) reject("json_integer", path, "Expected an integer token; floating point and booleans are not accepted.");
    if (value.is_number_unsigned()) {
        const auto number = value.get<std::uint64_t>();
        if (number > static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max()))
            reject("integer_range", path, "Integer exceeds signed 64-bit storage.");
        return static_cast<std::int64_t>(number);
    }
    return value.get<std::int64_t>();
}
std::int32_t int32(const Json& value, const std::string& path) {
    const auto number = integer(value, path);
    if (number < std::numeric_limits<std::int32_t>::min() || number > std::numeric_limits<std::int32_t>::max())
        reject("integer_range", path, "Integer exceeds signed 32-bit storage.");
    return static_cast<std::int32_t>(number);
}
std::string string(const Json& value, const std::string& path, std::size_t maximum = limits::max_text_bytes) {
    if (!value.is_string()) reject("json_type", path, "Expected a string.");
    const auto& text = value.get_ref<const std::string&>();
    if (text.size() > maximum) reject("text_limit", path, "String exceeds the field byte limit.", Outcome::unsupported_size);
    return text;
}
bool boolean(const Json& value, const std::string& path) {
    if (!value.is_boolean()) reject("json_type", path, "Expected a boolean.");
    return value.get<bool>();
}
void array(const Json& value, const std::string& path, std::size_t maximum) {
    if (!value.is_array()) reject("json_type", path, "Expected an array.");
    if (value.size() > maximum) reject("array_limit", path, "Array exceeds the storage guard.", Outcome::unsupported_size);
}
std::vector<std::string> tags(const Json& value, const std::string& path) {
    array(value, path, limits::max_tags);
    std::vector<std::string> result;
    for (std::size_t i = 0; i < value.size(); ++i)
        result.push_back(string(value[i], path + "/" + std::to_string(i), limits::max_id_bytes));
    return result;
}
RoomRole role(const Json& value, const std::string& path) {
    const auto name = string(value, path);
    for (auto item : {RoomRole::normal, RoomRole::entrance, RoomRole::exit, RoomRole::boss})
        if (name == role_name(item)) return item;
    reject("invalid_role", path, "Role must be normal, entrance, exit, or boss.");
}
std::pair<std::int32_t, std::int32_t> range(const Json& value, const std::string& path) {
    array(value, path, 2);
    if (value.size() != 2) reject("range_length", path, "Expected [minimum, maximum].");
    return {int32(value[0], path + "/0"), int32(value[1], path + "/1")};
}
Settings settings(const Json& value) {
    const std::string path = "/source/settings";
    object(value, path, {"columns", "rows", "room_count", "room_width", "room_height", "margin",
        "corridor_width", "seed", "max_generation_attempts", "max_work_units", "max_time_ms", "threat_budget"});
    Settings result;
    result.columns = int32(value.at("columns"), path + "/columns");
    result.rows = int32(value.at("rows"), path + "/rows");
    if (result.columns <= 0 || result.rows <= 0) reject("invalid_canvas", path, "Canvas axes must be positive.");
    if (result.columns > limits::max_axis || result.rows > limits::max_axis)
        reject("canvas_limit", path, "Canvas storage supports at most 512 cells per axis.", Outcome::unsupported_size);
    result.room_count = int32(value.at("room_count"), path + "/room_count");
    std::tie(result.min_room_width, result.max_room_width) = range(value.at("room_width"), path + "/room_width");
    std::tie(result.min_room_height, result.max_room_height) = range(value.at("room_height"), path + "/room_height");
    result.margin = int32(value.at("margin"), path + "/margin");
    result.corridor_width = int32(value.at("corridor_width"), path + "/corridor_width");
    const auto seed = integer(value.at("seed"), path + "/seed");
    if (seed < 0 || seed > std::numeric_limits<std::uint32_t>::max()) reject("seed_range", path + "/seed", "Seed must fit an unsigned 32-bit integer.");
    result.seed = static_cast<std::uint32_t>(seed);
    result.max_generation_attempts = integer(value.at("max_generation_attempts"), path + "/max_generation_attempts");
    result.max_work_units = integer(value.at("max_work_units"), path + "/max_work_units");
    result.max_time_ms = integer(value.at("max_time_ms"), path + "/max_time_ms");
    result.threat_budget = integer(value.at("threat_budget"), path + "/threat_budget");
    return result;
}
Room room(const Json& value, const std::string& path) {
    object(value, path, {"id", "name", "bounds", "role", "tags", "lock_position", "lock_size", "capacity_override"});
    Room result;
    result.id = string(value.at("id"), path + "/id", limits::max_id_bytes);
    result.name = string(value.at("name"), path + "/name");
    const auto& bounds = value.at("bounds");
    object(bounds, path + "/bounds", {"x", "y", "width", "height"});
    result.bounds = {int32(bounds.at("x"), path + "/bounds/x"), int32(bounds.at("y"), path + "/bounds/y"),
        int32(bounds.at("width"), path + "/bounds/width"), int32(bounds.at("height"), path + "/bounds/height")};
    result.role = role(value.at("role"), path + "/role");
    result.tags = tags(value.at("tags"), path + "/tags");
    result.lock_position = boolean(value.at("lock_position"), path + "/lock_position");
    result.lock_size = boolean(value.at("lock_size"), path + "/lock_size");
    if (!value.at("capacity_override").is_null()) result.capacity_override = int32(value.at("capacity_override"), path + "/capacity_override");
    return result;
}
Pack pack(const Json& value, const std::string& path) {
    object(value, path, {"id", "name", "active", "slots", "threat", "score", "min_room_width", "min_room_height", "allowed_roles", "required_tags"});
    Pack result;
    result.id = string(value.at("id"), path + "/id", limits::max_id_bytes);
    result.name = string(value.at("name"), path + "/name");
    result.active = boolean(value.at("active"), path + "/active");
    result.slots = integer(value.at("slots"), path + "/slots");
    result.threat = integer(value.at("threat"), path + "/threat");
    result.score = integer(value.at("score"), path + "/score");
    result.min_room_width = int32(value.at("min_room_width"), path + "/min_room_width");
    result.min_room_height = int32(value.at("min_room_height"), path + "/min_room_height");
    const auto& roles = value.at("allowed_roles");
    array(roles, path + "/allowed_roles", 4);
    for (std::size_t i = 0; i < roles.size(); ++i) result.allowed_roles.push_back(role(roles[i], path + "/allowed_roles/" + std::to_string(i)));
    result.required_tags = tags(value.at("required_tags"), path + "/required_tags");
    return result;
}
}

Result<Project> parse(std::string_view document) {
    if (document.size() > limits::max_file_bytes)
        return {failure(Outcome::unsupported_size, "file_limit", "", "Project document exceeds 16 MiB.", "Reduce the document size."), std::nullopt};
    try {
        // nlohmann treats a raw NUL as end-of-input. Our length-delimited
        // contract must reject it rather than silently ignore trailing bytes.
        if (document.find('\0') != std::string_view::npos)
            reject("malformed_json", "", "Raw NUL bytes are not valid JSON text.");
        std::vector<std::set<std::string>> keys;
        auto callback = [&](int depth, Json::parse_event_t event, Json& parsed) {
            if (depth > static_cast<int>(limits::max_json_depth)) reject("json_depth", "", "JSON nesting exceeds 32 levels.", Outcome::unsupported_size);
            if (event == Json::parse_event_t::object_start) keys.emplace_back();
            if (event == Json::parse_event_t::key && !keys.back().insert(parsed.get<std::string>()).second)
                reject("duplicate_key", "", "Duplicate JSON object key: " + parsed.get<std::string>());
            if (event == Json::parse_event_t::object_end) keys.pop_back();
            return true;
        };
        const auto root = Json::parse(document.begin(), document.end(), callback);
        // Check schema before fields that a future schema may change.
        if (!root.is_object() || !root.contains("schema_version")) reject("missing_schema", "/schema_version", "A schema_version is required.");
        if (integer(root.at("schema_version"), "/schema_version") != schema_version)
            reject("unsupported_schema", "/schema_version", "Only schema version 1 is supported; no automatic migration is attempted.", Outcome::unsupported_schema);
        object(root, "", {"schema_version", "engine_version", "source"});
        if (string(root.at("engine_version"), "/engine_version", 64).empty()) reject("engine_version", "/engine_version", "Writer engine version cannot be empty.");
        const auto& source = root.at("source");
        object(source, "/source", {"name", "settings", "allowed_mask", "rooms", "packs"});
        Project result;
        result.name = string(source.at("name"), "/source/name");
        result.settings = settings(source.at("settings"));
        const auto& mask = source.at("allowed_mask");
        array(mask, "/source/allowed_mask", static_cast<std::size_t>(limits::max_axis));
        if (mask.size() != static_cast<std::size_t>(result.settings.rows)) reject("mask_length", "/source/allowed_mask", "Mask must contain exactly one string per canvas row.");
        result.allowed_mask.reserve(static_cast<std::size_t>(result.settings.columns) * mask.size());
        for (std::size_t y = 0; y < mask.size(); ++y) {
            const auto path = "/source/allowed_mask/" + std::to_string(y);
            const auto row = string(mask[y], path, static_cast<std::size_t>(limits::max_axis));
            if (row.size() != static_cast<std::size_t>(result.settings.columns)) reject("mask_length", path, "Row length must equal columns.");
            for (char cell : row) {
                if (cell != '0' && cell != '1') reject("mask_value", path, "Mask strings accept only 0 or 1.");
                result.allowed_mask.push_back(static_cast<std::uint8_t>(cell - '0'));
            }
        }
        const auto& rooms = source.at("rooms");
        const auto& packs = source.at("packs");
        array(rooms, "/source/rooms", limits::max_records);
        array(packs, "/source/packs", limits::max_records);
        for (std::size_t i = 0; i < rooms.size(); ++i) result.rooms.push_back(room(rooms[i], "/source/rooms/" + std::to_string(i)));
        for (std::size_t i = 0; i < packs.size(); ++i) result.packs.push_back(pack(packs[i], "/source/packs/" + std::to_string(i)));
        auto status = validate_project(result);
        if (!status.ok()) return {std::move(status), std::nullopt};
        canonicalize(result);
        return {{}, std::move(result)};
    } catch (const InputError& e) { return {e.status, std::nullopt}; }
      catch (const Json::exception& e) {
        return {failure(Outcome::invalid_input, "malformed_json", "", e.what(), "Correct JSON syntax and integer values, then retry."), std::nullopt};
    } catch (const std::bad_alloc&) {
        return {failure(Outcome::resource_failure, "allocation_failure", "", "Insufficient memory to parse project.", "Close other work or reduce the document."), std::nullopt};
    }
}

Result<std::string> serialize(const Project& project) {
    try {
        auto status = validate_project(project);
        if (!status.ok()) return {std::move(status), std::nullopt};
        Project ordered = project;
        canonicalize(ordered);
        const auto& s = ordered.settings;
        Json mask = Json::array(), rooms = Json::array(), packs = Json::array();
        for (std::int32_t y = 0; y < s.rows; ++y) {
            std::string row;
            row.reserve(static_cast<std::size_t>(s.columns));
            for (std::int32_t x = 0; x < s.columns; ++x) row.push_back(static_cast<char>('0' + ordered.allowed_mask[static_cast<std::size_t>(y) * static_cast<std::size_t>(s.columns) + static_cast<std::size_t>(x)]));
            mask.push_back(std::move(row));
        }
        for (const auto& r : ordered.rooms) {
            rooms.push_back({{"id", r.id}, {"name", r.name}, {"role", role_name(r.role)}, {"tags", r.tags},
                {"bounds", {{"x", r.bounds.x}, {"y", r.bounds.y}, {"width", r.bounds.width}, {"height", r.bounds.height}}},
                {"lock_position", r.lock_position}, {"lock_size", r.lock_size},
                {"capacity_override", r.capacity_override ? Json(*r.capacity_override) : Json(nullptr)}});
        }
        for (const auto& p : ordered.packs) {
            Json roles = Json::array();
            for (auto r : p.allowed_roles) roles.push_back(role_name(r));
            packs.push_back({{"id", p.id}, {"name", p.name}, {"active", p.active}, {"slots", p.slots},
                {"threat", p.threat}, {"score", p.score}, {"min_room_width", p.min_room_width},
                {"min_room_height", p.min_room_height}, {"allowed_roles", roles}, {"required_tags", p.required_tags}});
        }
        Json root = {{"schema_version", schema_version}, {"engine_version", build_info().version},
            {"source", {{"name", ordered.name}, {"allowed_mask", mask}, {"rooms", rooms}, {"packs", packs},
                {"settings", {{"columns", s.columns}, {"rows", s.rows}, {"room_count", s.room_count},
                    {"room_width", {s.min_room_width, s.max_room_width}}, {"room_height", {s.min_room_height, s.max_room_height}},
                    {"margin", s.margin}, {"corridor_width", s.corridor_width}, {"seed", s.seed},
                    {"max_generation_attempts", s.max_generation_attempts}, {"max_work_units", s.max_work_units},
                    {"max_time_ms", s.max_time_ms}, {"threat_budget", s.threat_budget}}}}}};
        auto encoded = root.dump(2) + "\n";
        if (encoded.size() > limits::max_file_bytes)
            return {failure(Outcome::unsupported_size, "file_limit", "", "Serialized document exceeds 16 MiB.", "Reduce catalogue text or record counts."), std::nullopt};
        return {{}, std::move(encoded)};
    } catch (const Json::exception& e) {
        return {failure(Outcome::invalid_input, "serialization_error", "", e.what(), "Correct invalid text and retry."), std::nullopt};
    } catch (const std::bad_alloc&) {
        return {failure(Outcome::resource_failure, "allocation_failure", "", "Insufficient memory to serialize project.", "Close other work or reduce the project."), std::nullopt};
    }
}
std::string diagnostics_json(const Status& status) {
    Json errors = Json::array();
    for (const auto& d : status.diagnostics) {
        Json tiles = Json::array();
        for (auto tile : d.affected_tiles) tiles.push_back({{"x", tile.x}, {"y", tile.y}});
        errors.push_back({{"code", d.code}, {"path", d.path}, {"message", d.message},
            {"affected_ids", d.affected_ids}, {"affected_tiles", tiles}, {"recovery", d.recovery}});
    }
    // Invalid UTF-8 may be the reason a direct C++ input failed validation.
    // Keep the diagnostic transport valid without sanitizing source data itself.
    return Json({{"outcome", outcome_name(status.outcome)}, {"diagnostics", errors}})
        .dump(2, ' ', false, Json::error_handler_t::replace) + "\n";
}
}  // namespace dungeon_architect::project_io

#include "dungeon_architect/project_io.h"
#include "../test_support.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <fstream>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#endif

namespace da = dungeon_architect;
namespace io = da::project_io;
namespace fs = std::filesystem;
using Json = nlohmann::json;
std::string bytes(const fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}
void write(const fs::path& path, const std::string& value) {
    std::ofstream file(path, std::ios::binary); file << value;
    CHECK(file.good());
}
struct Scratch {
    fs::path root;
    explicit Scratch(const fs::path& parent) {
        for (int i = 0; i < 1000; ++i) {
            auto candidate = parent / ("phase02-io-test-" + std::to_string(i));
            if (fs::create_directory(candidate)) { root = std::move(candidate); return; }
        }
        throw std::runtime_error("No available scratch directory");
    }
    ~Scratch() {
        // Only our newly-created directory; no recursive deletion.
        std::error_code ec;
        for (const auto& entry : fs::directory_iterator(root, ec)) fs::remove(entry.path(), ec);
        fs::remove(root, ec);
    }
};
void reject_json(const Json& value, da::Outcome outcome = da::Outcome::invalid_input) {
    const auto parsed = io::parse(value.dump());
    CHECK(!parsed.ok()); CHECK(!parsed.value.has_value());
    CHECK(parsed.status.outcome == outcome); CHECK(!parsed.status.diagnostics.empty());
    CHECK(!parsed.status.diagnostics.front().recovery.empty());
}
void parsing(const da::Project& fixture) {
    const auto serialized = io::serialize(fixture);
    CHECK(serialized.ok());
    const auto roundtrip = io::parse(*serialized.value);
    CHECK(roundtrip.ok()); CHECK(*io::serialize(*roundtrip.value).value == *serialized.value);
    CHECK(roundtrip.value->rooms.size() == 2 && roundtrip.value->packs.size() == 2);
    CHECK(roundtrip.value->rooms[0].id == "boss-1");
    CHECK(roundtrip.value->rooms[1].capacity_override == 0);
    CHECK(roundtrip.value->rooms[0].lock_position && roundtrip.value->rooms[0].lock_size);
    CHECK(!roundtrip.value->rooms[0].capacity_override.has_value());
    CHECK(std::count(roundtrip.value->allowed_mask.begin(), roundtrip.value->allowed_mask.end(), std::uint8_t{1}) == 116);
    auto reordered = fixture;
    std::reverse(reordered.rooms.begin(), reordered.rooms.end());
    std::reverse(reordered.packs.begin(), reordered.packs.end());
    for (auto& room : reordered.rooms) std::reverse(room.tags.begin(), room.tags.end());
    for (auto& pack : reordered.packs) std::reverse(pack.allowed_roles.begin(), pack.allowed_roles.end());
    CHECK(*io::serialize(reordered).value == *serialized.value);
    const auto valid = Json::parse(*serialized.value);
    CHECK(!valid.contains("geometry") && !valid["source"].contains("allocation"));
    Json bad = valid; bad["schema_version"] = 2; reject_json(bad, da::Outcome::unsupported_schema);
    bad = {{"schema_version", 2}, {"future", 17}}; reject_json(bad, da::Outcome::unsupported_schema);
    bad = valid; bad.erase("schema_version"); reject_json(bad);
    bad = valid; bad["extra"] = 0; reject_json(bad);
    bad = valid; bad["source"]["settings"].erase("seed"); reject_json(bad);
    bad = valid; bad["source"]["settings"]["seed"] = -1; reject_json(bad);
    bad = valid; bad["source"]["settings"]["seed"] = 4294967296ULL; reject_json(bad);
    bad = valid; bad["source"]["settings"]["room_count"] = 2.0; reject_json(bad);
    bad = valid; bad["source"]["settings"]["columns"] = true; reject_json(bad);
    bad = valid; bad["source"]["settings"]["columns"] = -4; reject_json(bad);
    bad = valid; bad["source"]["settings"]["columns"] = 513; reject_json(bad, da::Outcome::unsupported_size);
    bad = valid; bad["source"]["settings"]["room_width"] = {5, 2}; reject_json(bad);
    bad = valid; bad["source"]["settings"]["threat_budget"] = UINT64_MAX; reject_json(bad);
    bad = valid; bad["source"]["packs"][0]["slots"] = 1e30; reject_json(bad);
    bad = valid; bad["source"]["packs"][0]["active"] = 1; reject_json(bad);
    bad = valid; bad["source"]["packs"][0]["score"] = -1; reject_json(bad);
    bad = valid; bad["source"]["packs"][0]["id"] = bad["source"]["packs"][1]["id"]; reject_json(bad);
    bad = valid; bad["source"]["rooms"][0]["bounds"]["x"] = INT32_MAX; reject_json(bad);
    bad = valid; bad["source"]["rooms"][0]["role"] = "unknown"; reject_json(bad);
    bad = valid; bad["source"]["allowed_mask"][0] = "1"; reject_json(bad);
    bad = valid; bad["source"]["allowed_mask"][0] = "11111111111x"; reject_json(bad);
    bad = valid; bad["source"]["allowed_mask"].erase(0); reject_json(bad);
    bad = valid; bad["source"]["rooms"][0]["tags"] = {"stone", "stone"}; reject_json(bad);
    CHECK(!io::parse("").ok()); CHECK(!io::parse("{}").ok()); CHECK(!io::parse("{broken").ok());
    CHECK(!io::parse(*serialized.value + "garbage").ok());
    CHECK(!io::parse("{\"schema_version\":1,\"schema_version\":1}").ok());
    CHECK(!io::parse(std::string(40, '[') + "0" + std::string(40, ']')).ok());
    CHECK(io::parse(std::string(da::limits::max_file_bytes + 1, ' ')).status.outcome == da::Outcome::unsupported_size);
    auto duplicate = *serialized.value;
    const auto name_position = duplicate.find("\"name\":");
    duplicate.insert(name_position, "\"name\":\"duplicate\",");
    CHECK(io::parse(duplicate).status.diagnostics.front().code == "duplicate_key");
    auto large = fixture;
    large.settings.threat_budget = INT64_MAX;
    large.settings.seed = UINT32_MAX;
    large.packs[0].score = INT64_MAX - large.packs[1].score;
    large.name = u8"قلعہ — Dungeon";
    auto encoded_large = io::serialize(large); CHECK(encoded_large.ok());
    auto decoded_large = io::parse(*encoded_large.value); CHECK(decoded_large.ok());
    CHECK(decoded_large.value->settings.threat_budget == INT64_MAX);
    CHECK(decoded_large.value->settings.seed == UINT32_MAX);
    CHECK(decoded_large.value->packs[0].score == INT64_MAX - 5);
    CHECK(decoded_large.value->name == large.name);
    large.packs[0].score += 1; CHECK(!io::serialize(large).ok());
    auto invalid_utf8 = fixture; invalid_utf8.name = std::string("\xFF", 1);
    CHECK(!io::serialize(invalid_utf8).ok());
    invalid_utf8 = fixture; invalid_utf8.packs[0].id = std::string("\xFF", 1);
    const auto invalid_id_status = da::validate_project(invalid_utf8);
    CHECK(!invalid_id_status.ok());
    CHECK(Json::parse(io::diagnostics_json(invalid_id_status))["outcome"] == "invalid_input");
    const auto bad_utf8_document = io::parse(std::string("{\"name\":\"") + char(0xFF) + "\"}");
    CHECK(!bad_utf8_document.ok());
    CHECK(Json::parse(io::diagnostics_json(bad_utf8_document.status))["outcome"] == "invalid_input");
}
void files(const da::Project& fixture, const fs::path& parent) {
    Scratch scratch(parent);
    const auto file = scratch.root / fs::u8path(u8"project قلعہ.json");
    CHECK(io::save_atomic(fixture, file).ok());
    auto loaded = io::read(file); CHECK(loaded.ok());
    CHECK(*io::serialize(*loaded.value).value == *io::serialize(fixture).value);
    auto changed = fixture; changed.name = "Replacement";
    CHECK(io::save_atomic(changed, file).ok());
    CHECK(io::read(file).value->name == "Replacement");
    const auto old_bytes = bytes(file);
    CHECK(io::save_atomic(fixture, file, io::SaveMode::create_only).outcome == da::Outcome::io_failure);
    CHECK(bytes(file) == old_bytes);
    changed.settings.threat_budget = -1;
    CHECK(!io::save_atomic(changed, file).ok()); CHECK(bytes(file) == old_bytes);
    CHECK(io::save_atomic(fixture, scratch.root / "missing" / "project.json").outcome == da::Outcome::io_failure);
    CHECK(io::read(scratch.root / "absent.json").status.outcome == da::Outcome::io_failure);
    CHECK(!io::save_atomic(fixture, {}).ok());
    const auto directory_target = scratch.root / "directory.json";
    CHECK(fs::create_directory(directory_target));
    CHECK(io::save_atomic(fixture, directory_target).outcome == da::Outcome::io_failure);
    CHECK(fs::is_directory(directory_target));
    const auto report = scratch.root / fs::u8path(u8"result قلعہ.json");
    CHECK(io::write_text_atomic("{\"result\":1}\n",report).ok());
    CHECK(bytes(report) == "{\"result\":1}\n");
    CHECK(io::write_text_atomic("replacement",report).outcome == da::Outcome::io_failure);
    CHECK(bytes(report) == "{\"result\":1}\n");
    CHECK(io::write_text_atomic("replacement",report,io::SaveMode::replace_existing).ok());
    CHECK(bytes(report) == "replacement");
    CHECK(io::write_text_atomic("result",directory_target).outcome == da::Outcome::io_failure);
#ifdef _WIN32
    const auto lock = CreateFileW(file.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    CHECK(lock != INVALID_HANDLE_VALUE);
    const auto locked_result = io::save_atomic(fixture, file);
    CloseHandle(lock);
    CHECK(locked_result.outcome == da::Outcome::io_failure); CHECK(bytes(file) == old_bytes);
    const auto report_lock = CreateFileW(report.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    CHECK(report_lock != INVALID_HANDLE_VALUE);
    const auto blocked_report = io::write_text_atomic("blocked",report,io::SaveMode::replace_existing);
    CloseHandle(report_lock);
    CHECK(blocked_report.outcome == da::Outcome::io_failure && bytes(report) == "replacement");
#endif
    da::ProjectSession session;
    CHECK(io::load_into(session, file).ok());
    da::GeometrySnapshot snapshot; snapshot.id = "kept"; snapshot.geometry_revision = session.revisions().geometry;
    CHECK(session.publish_geometry(snapshot, session.revisions().source).ok());
    const auto old_source = *io::serialize(session.project()).value;
    const auto old_revision = session.revisions().source;
    const auto old_snapshot = session.geometry();
    const auto bad_file = scratch.root / "bad.json"; write(bad_file, "{broken");
    CHECK(!io::load_into(session, bad_file).ok());
    CHECK(session.revisions().source == old_revision && session.geometry() == old_snapshot && session.geometry_current());
    CHECK(*io::serialize(session.project()).value == old_source);
    auto invalid = Json::parse(old_source); invalid["source"]["packs"][0]["score"] = -5;
    write(bad_file, invalid.dump()); CHECK(!io::load_into(session, bad_file).ok());
    CHECK(session.revisions().source == old_revision && *io::serialize(session.project()).value == old_source);
    CHECK(!io::load_into(session, scratch.root / "missing.json").ok()); CHECK(session.geometry() == old_snapshot);
    CHECK(io::load_into(session, file).ok()); CHECK(!session.geometry_current());
    CHECK(session.geometry() == old_snapshot && session.revisions().source == old_revision + 1);
    for (const auto& entry : fs::directory_iterator(scratch.root)) CHECK(entry.path().filename().u8string().find(".tmp.") == std::string::npos);
}
int main(int argc, char** argv) {
    try {
        CHECK(argc == 3);
        auto fixture = io::read(fs::u8path(argv[1])); CHECK(fixture.ok());
        parsing(*fixture.value); files(*fixture.value, fs::u8path(argv[2]));
        std::cout << checks << " persistence checks passed.\n";
        return 0;
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}

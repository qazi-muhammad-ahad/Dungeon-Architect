#include "dungeon_architect/project.h"

#include <algorithm>
#include <utility>

namespace dungeon_architect {
std::int64_t Rect::right() const noexcept { return std::int64_t{x} + width; }
std::int64_t Rect::bottom() const noexcept { return std::int64_t{y} + height; }
bool Rect::valid() const noexcept {
    return x >= 0 && y >= 0 && width > 0 && height > 0 &&
           right() <= std::numeric_limits<std::int32_t>::max() &&
           bottom() <= std::numeric_limits<std::int32_t>::max();
}
bool Rect::contains(Tile tile) const noexcept {
    return valid() && tile.x >= x && tile.y >= y && tile.x < right() && tile.y < bottom();
}
bool Rect::inside(std::int32_t columns, std::int32_t rows) const noexcept {
    return valid() && columns > 0 && rows > 0 && right() <= columns && bottom() <= rows;
}
const char* outcome_name(Outcome outcome) noexcept {
    switch (outcome) {
    case Outcome::success: return "success";
    case Outcome::invalid_input: return "invalid_input";
    case Outcome::search_exhausted: return "search_exhausted";
    case Outcome::unsupported_size: return "unsupported_size";
    case Outcome::unsupported_schema: return "unsupported_schema";
    case Outcome::cancelled: return "cancelled";
    case Outcome::resource_failure: return "resource_failure";
    case Outcome::io_failure: return "io_failure";
    case Outcome::stale_result: return "stale_result";
    }
    return "invalid_outcome";
}
const char* role_name(RoomRole role) noexcept {
    switch (role) {
    case RoomRole::normal: return "normal";
    case RoomRole::entrance: return "entrance";
    case RoomRole::exit: return "exit";
    case RoomRole::boss: return "boss";
    }
    return "invalid_role";
}
Status failure(Outcome outcome, std::string code, std::string path,
               std::string message, std::string recovery) {
    return {outcome, {{std::move(code), std::move(path), std::move(message), {}, {}, std::move(recovery)}}};
}
Project make_default_project() {
    Project project;
    project.allowed_mask.assign(150U * 150U, 1);
    return project;
}
bool checked_add(std::int64_t a, std::int64_t b, std::int64_t& out) noexcept {
    const auto hi = std::numeric_limits<std::int64_t>::max();
    const auto lo = std::numeric_limits<std::int64_t>::min();
    if ((b > 0 && a > hi - b) || (b < 0 && a < lo - b)) return false;
    out = a + b;
    return true;
}
bool valid_utf8(const std::string& value) noexcept {
    std::size_t i = 0;
    while (i < value.size()) {
        const auto c = static_cast<unsigned char>(value[i++]);
        if (c < 0x80) continue;
        std::uint32_t cp = 0, minimum = 0;
        unsigned remaining = 0;
        if (c >= 0xC2 && c <= 0xDF) { cp = c & 0x1FU; remaining = 1; minimum = 0x80; }
        else if (c >= 0xE0 && c <= 0xEF) { cp = c & 0x0FU; remaining = 2; minimum = 0x800; }
        else if (c >= 0xF0 && c <= 0xF4) { cp = c & 0x07U; remaining = 3; minimum = 0x10000; }
        else return false;
        while (remaining-- > 0) {
            if (i == value.size()) return false;
            const auto next = static_cast<unsigned char>(value[i++]);
            if ((next & 0xC0U) != 0x80U) return false;
            cp = (cp << 6U) | (next & 0x3FU);
        }
        if (cp < minimum || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return false;
    }
    return true;
}
void canonicalize(Project& project) {
    auto by_id = [](const auto& a, const auto& b) { return a.id < b.id; };
    std::sort(project.rooms.begin(), project.rooms.end(), by_id);
    std::sort(project.packs.begin(), project.packs.end(), by_id);
    for (auto& room : project.rooms) std::sort(room.tags.begin(), room.tags.end());
    for (auto& pack : project.packs) {
        std::sort(pack.required_tags.begin(), pack.required_tags.end());
        std::sort(pack.allowed_roles.begin(), pack.allowed_roles.end());
    }
}
Result<std::uint32_t> DeterministicRandom::bounded(std::uint32_t exclusive_upper) {
    if (exclusive_upper == 0) {
        return {failure(Outcome::invalid_input, "empty_random_range", "/random/bound",
                        "The exclusive bound must be positive.", "Provide a nonzero bound."), std::nullopt};
    }
    const auto threshold = (std::uint32_t{0} - exclusive_upper) % exclusive_upper;
    std::uint32_t value;
    do { value = next(); } while (value < threshold);
    return {{}, value % exclusive_upper};
}
}  // namespace dungeon_architect

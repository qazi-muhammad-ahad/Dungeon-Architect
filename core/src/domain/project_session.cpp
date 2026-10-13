#include "dungeon_architect/project.h"
#include "dungeon_architect/geometry.h"
#include "dungeon_architect/generation.h"
#include "dungeon_architect/routing.h"
#include "dungeon_architect/allocation.h"

#include <algorithm>
#include <type_traits>
#include <utility>

namespace dungeon_architect {
namespace {
auto geometry_settings(const Settings& s) {
    return std::tie(s.columns, s.rows, s.room_count, s.min_room_width, s.max_room_width,
        s.min_room_height, s.max_room_height, s.margin, s.corridor_width, s.seed,
        s.max_generation_attempts, s.max_work_units, s.max_time_ms);
}
auto room_geometry(const Room& r) { return std::tie(r.id, r.bounds, r.role, r.lock_position, r.lock_size); }
auto room_allocation(const Room& r) { return std::tie(r.id, r.tags, r.capacity_override); }
auto pack_input(const Pack& p) {
    return std::tie(p.id, p.active, p.slots, p.threat, p.score,
                    p.min_room_width, p.min_room_height, p.allowed_roles, p.required_tags);
}
template <typename T, typename Compare>
bool equal_vectors(const std::vector<T>& a, const std::vector<T>& b, Compare compare) {
    return a.size() == b.size() && std::equal(a.begin(), a.end(), b.begin(), compare);
}
bool geometry_equal(const Project& a, const Project& b) {
    return geometry_settings(a.settings) == geometry_settings(b.settings) && a.allowed_mask == b.allowed_mask &&
           equal_vectors(a.rooms, b.rooms, [](const Room& x, const Room& y) { return room_geometry(x) == room_geometry(y); });
}
bool active_packs_equal(const Project& a, const Project& b) {
    auto x = a.packs.begin(), y = b.packs.begin();
    for (;;) {
        while (x != a.packs.end() && !x->active) ++x;
        while (y != b.packs.end() && !y->active) ++y;
        if (x == a.packs.end() || y == b.packs.end()) return x == a.packs.end() && y == b.packs.end();
        if (pack_input(*x) != pack_input(*y)) return false;
        ++x; ++y;
    }
}
bool allocation_equal(const Project& a, const Project& b) {
    return a.settings.threat_budget == b.settings.threat_budget && active_packs_equal(a, b) &&
           equal_vectors(a.rooms, b.rooms, [](const Room& x, const Room& y) { return room_allocation(x) == room_allocation(y); });
}
bool source_equal(const Project& a, const Project& b) {
    return a.name == b.name && geometry_equal(a, b) && a.settings.threat_budget == b.settings.threat_budget &&
           equal_vectors(a.rooms, b.rooms, [](const Room& x, const Room& y) {
               return x.name == y.name && room_allocation(x) == room_allocation(y);
           }) && equal_vectors(a.packs, b.packs, [](const Pack& x, const Pack& y) {
               return x.name == y.name && pack_input(x) == pack_input(y);
           });
}
bool exhausted(std::uint64_t value) { return value == std::numeric_limits<std::uint64_t>::max(); }
Status revision_failure() {
    return failure(Outcome::resource_failure, "revision_overflow", "/session/revisions",
                   "Revision counter is exhausted.", "Save the project and start a new session.");
}
Status stale() {
    return failure(Outcome::stale_result, "stale_result", "/session",
                   "The result does not match the current project dependencies.", "Run the operation again using the current revision.");
}
}
ProjectSession::ProjectSession() : project_(make_default_project()) {}
Status ProjectSession::update(Project candidate) { return commit(std::move(candidate), false); }
Status ProjectSession::replace_loaded(Project candidate) { return commit(std::move(candidate), true); }
Status ProjectSession::commit(Project candidate, bool load) {
    auto status = validate_project(candidate);
    if (!status.ok()) return status;
    if (!load) {
        status = detail::validate_locked_edits(project_, candidate);
        if (!status.ok()) return status;
    }
    canonicalize(candidate);
    if (!load && source_equal(project_, candidate)) return {};
    const bool geometry_changed = load || !geometry_equal(project_, candidate);
    const bool allocation_changed = geometry_changed || !allocation_equal(project_, candidate);
    if (exhausted(revisions_.source) || (geometry_changed && exhausted(revisions_.geometry)) ||
        (allocation_changed && (exhausted(revisions_.allocation) || exhausted(revisions_.play)))) return revision_failure();
    static_assert(std::is_nothrow_swappable<Project>::value, "Transactional commit must not throw");
    std::swap(project_, candidate);
    ++revisions_.source;
    if (geometry_changed) ++revisions_.geometry;
    if (allocation_changed) { ++revisions_.allocation; ++revisions_.play; }
    // Keep last results available for display, with current() reporting staleness.
    return {};
}
bool ProjectSession::geometry_current() const noexcept {
    return geometry_ && geometry_->geometry_revision == revisions_.geometry &&
           (!room_layout_ || geometry_->room_layout_id == room_layout_->id);
}
bool ProjectSession::allocation_current() const noexcept {
    return geometry_current() && allocation_ && allocation_->geometry_revision == revisions_.geometry &&
           (!room_layout_ || allocation_->geometry_id == geometry_->id) &&
           allocation_->allocation_revision == revisions_.allocation;
}
bool ProjectSession::play_current() const noexcept {
    return allocation_current() && play_ && play_->play_revision == revisions_.play;
}
Status ProjectSession::publish_geometry(GeometrySnapshot snapshot, std::uint64_t expected_source) {
    if (snapshot.id.empty() || expected_source != revisions_.source || snapshot.geometry_revision != revisions_.geometry) return stale();
    if (room_layout_ && (!room_layout_current() || snapshot.room_layout_id != room_layout_->id)) return stale();
    if (room_layout_) {
        auto validation = validate_routed_geometry(project_, *room_layout_, snapshot);
        if (!validation.ok()) return validation;
    }
    if (exhausted(revisions_.allocation) || exhausted(revisions_.play)) return revision_failure();
    auto next = std::make_shared<const GeometrySnapshot>(std::move(snapshot));
    geometry_ = std::move(next);
    ++revisions_.allocation;
    ++revisions_.play;
    return {};
}
Status ProjectSession::publish_allocation(AllocationSnapshot snapshot, std::uint64_t expected_source) {
    if (snapshot.id.empty() || expected_source != revisions_.source || !geometry_current() ||
        snapshot.geometry_revision != revisions_.geometry || snapshot.allocation_revision != revisions_.allocation) return stale();
    if (room_layout_) {
        if (snapshot.geometry_id != geometry_->id) return stale();
        auto input = prepare_allocation(project_,*room_layout_,*geometry_);
        if (!input.ok()) return input.status;
        input.value->allocation_revision = revisions_.allocation;
        auto validation = validate_allocation_result(*input.value,snapshot);
        if (!validation.ok()) return validation;
    }
    if (exhausted(revisions_.play)) return revision_failure();
    auto next = std::make_shared<const AllocationSnapshot>(std::move(snapshot));
    allocation_ = std::move(next);
    ++revisions_.play;
    return {};
}
Status ProjectSession::publish_play(PlaySnapshot snapshot, std::uint64_t expected_source) {
    if (snapshot.id.empty() || expected_source != revisions_.source || !allocation_current() ||
        snapshot.play_revision != revisions_.play) return stale();
    play_ = std::make_shared<const PlaySnapshot>(std::move(snapshot));
    return {};
}
}  // namespace dungeon_architect

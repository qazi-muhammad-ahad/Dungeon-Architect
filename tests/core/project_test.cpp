#include "dungeon_architect/project.h"
#include "../test_support.h"
#include <algorithm>
#include <climits>

namespace da = dungeon_architect;
da::Pack make_pack(std::string id, std::int64_t score = 1) {
    da::Pack pack;
    pack.id = std::move(id); pack.name = "Encounter"; pack.score = score;
    return pack;
}
da::Room make_room() {
    da::Room room;
    room.id = "room-1"; room.name = "Hall"; room.bounds = {1, 2, 8, 8};
    return room;
}
void geometry_and_validation() {
    const da::Rect rect{3, 5, 2, 3};
    CHECK(rect.contains({3, 5})); CHECK(rect.contains({4, 7}));
    CHECK(!rect.contains({5, 7})); CHECK(!rect.contains({4, 8}));
    CHECK(!rect.contains({2, 5})); CHECK(rect.inside(5, 8)); CHECK(!rect.inside(4, 8));
    CHECK(!da::Rect{-1, 0, 1, 1}.valid()); CHECK(!da::Rect{0, 0, 0, 1}.valid());
    CHECK(!da::Rect{INT32_MAX, 0, INT32_MAX, 1}.valid());
    CHECK(da::Rect{INT32_MAX, 0, INT32_MAX, 1}.right() == 4294967294LL);
    std::int64_t sum = 77;
    CHECK(da::checked_add(4000000000LL, 5000000000LL, sum) && sum == 9000000000LL);
    CHECK(!da::checked_add(INT64_MAX, 1, sum) && sum == 9000000000LL);
    CHECK(!da::checked_add(INT64_MIN, -1, sum));
    CHECK(da::checked_add(INT64_MIN, INT64_MAX, sum) && sum == -1);
    CHECK(da::valid_utf8(u8"قلعہ")); CHECK(!da::valid_utf8(std::string("\xC0\x80", 2)));
    CHECK(!da::valid_utf8(std::string("\xED\xA0\x80", 3)));
    CHECK(!da::valid_utf8(std::string("\xF4\x90\x80\x80", 4)));
    auto p = da::make_default_project();
    CHECK(da::validate_project(p).ok());
    p.allowed_mask.assign(p.allowed_mask.size(), 0); CHECK(da::validate_project(p).ok());
    p.allowed_mask.pop_back(); CHECK(!da::validate_project(p).ok());
    p = da::make_default_project(); p.allowed_mask[4] = 2; CHECK(!da::validate_project(p).ok());
    p = da::make_default_project(); p.settings.columns = INT32_MAX;
    CHECK(da::validate_project(p).outcome == da::Outcome::unsupported_size);
    p = da::make_default_project(); p.settings.rows = -1; CHECK(!da::validate_project(p).ok());
    p = da::make_default_project(); p.settings.min_room_width = 23; CHECK(!da::validate_project(p).ok());
    p = da::make_default_project(); p.settings.threat_budget = -1; CHECK(!da::validate_project(p).ok());
    p = da::make_default_project(); p.rooms = {make_room(), make_room()};
    const auto duplicate = da::validate_project(p);
    CHECK(!duplicate.ok()); CHECK(duplicate.diagnostics.front().code == "duplicate_id");
    CHECK(duplicate.diagnostics.front().affected_ids.front() == "room-1");
    p.rooms.resize(1); p.rooms[0].bounds.x = 149;
    const auto bounds = da::validate_project(p);
    CHECK(!bounds.ok()); CHECK(bounds.diagnostics.front().affected_tiles.front().x == 149);
    p.rooms[0] = make_room(); p.rooms[0].tags = {"stone", "stone"}; CHECK(!da::validate_project(p).ok());
    p.rooms[0] = make_room(); p.rooms[0].role = da::RoomRole::entrance; p.rooms[0].capacity_override = 1;
    CHECK(!da::validate_project(p).ok());
    p.rooms[0].capacity_override = 0; CHECK(da::validate_project(p).ok());
    p.name = std::string("Bad\0Name", 8); CHECK(!da::validate_project(p).ok());
    p = da::make_default_project();
    for (int i = 0; i < 15; ++i) p.packs.push_back(make_pack("pack-" + std::to_string(i)));
    CHECK(da::validate_project(p).ok());
    CHECK(da::validate_allocation_workload(p).outcome == da::Outcome::unsupported_size);
    p.packs.back().active = false; CHECK(da::validate_allocation_workload(p).ok());
    p.packs = {make_pack("a", INT64_MAX - 1), make_pack("b", 1)};
    CHECK(da::validate_project(p).ok());
    p.packs[1].score = 2; CHECK(!da::validate_project(p).ok());
    p.packs[1].active = false; CHECK(da::validate_project(p).ok());
    p.packs[1].threat = -1; CHECK(!da::validate_project(p).ok());
    p.packs[1].threat = 0; p.packs[1].id = "a"; CHECK(!da::validate_project(p).ok());
    p = da::make_default_project(); p.packs = {make_pack("b"), make_pack("a")};
    da::canonicalize(p); CHECK(p.packs[0].id == "a");
}
void publish_results(da::ProjectSession& session) {
    da::GeometrySnapshot g; g.id = "geometry"; g.geometry_revision = session.revisions().geometry;
    CHECK(session.publish_geometry(g, session.revisions().source).ok());
    da::AllocationSnapshot a; a.id = "allocation";
    a.geometry_revision = session.revisions().geometry; a.allocation_revision = session.revisions().allocation;
    CHECK(session.publish_allocation(a, session.revisions().source).ok());
    da::PlaySnapshot p; p.id = "play"; p.play_revision = session.revisions().play;
    CHECK(session.publish_play(p, session.revisions().source).ok());
    CHECK(session.geometry_current() && session.allocation_current() && session.play_current());
}
void transactions_and_revisions() {
    da::ProjectSession session;
    auto source = session.project(); source.rooms = {make_room()};
    source.packs = {make_pack("a"), make_pack("b")};
    CHECK(session.update(source).ok());
    publish_results(session);
    const auto geometry = session.geometry(), original_geometry = geometry;
    const auto allocation = session.allocation();
    auto revisions = session.revisions();
    source = session.project(); source.settings.threat_budget = -1;
    CHECK(!session.update(source).ok());
    CHECK(session.revisions().source == revisions.source && session.play_current());
    CHECK(session.geometry() == geometry && session.allocation() == allocation);
    source = session.project(); std::reverse(source.packs.begin(), source.packs.end());
    CHECK(session.update(source).ok()); CHECK(session.revisions().source == revisions.source);
    source.name = "Renamed"; CHECK(session.update(source).ok());
    CHECK(session.revisions().source == revisions.source + 1);
    CHECK(session.play_current());
    da::GeometrySnapshot stale; stale.id = "late-job"; stale.geometry_revision = revisions.geometry;
    CHECK(session.publish_geometry(stale, revisions.source).outcome == da::Outcome::stale_result);
    revisions = session.revisions();
    source = session.project(); source.settings.threat_budget += 1; CHECK(session.update(source).ok());
    CHECK(session.revisions().geometry == revisions.geometry && session.geometry_current());
    CHECK(!session.allocation_current() && !session.play_current());
    CHECK(session.allocation() == allocation);  // Last valid result remains inspectable.
    publish_results(session);
    source = session.project(); source.rooms[0].capacity_override = 2;
    revisions = session.revisions(); CHECK(session.update(source).ok());
    CHECK(session.revisions().geometry == revisions.geometry && !session.allocation_current());
    publish_results(session);
    source = session.project(); source.packs[0].active = false; CHECK(session.update(source).ok());
    publish_results(session); revisions = session.revisions();
    source = session.project(); source.packs[0].score += 1; CHECK(session.update(source).ok());
    CHECK(session.revisions().allocation == revisions.allocation && session.play_current());
    source = session.project(); source.allowed_mask[0] = 0; CHECK(session.update(source).ok());
    CHECK(!session.geometry_current() && !session.allocation_current() && !session.play_current());
    CHECK(original_geometry->geometry_revision == 2);  // Published data is immutable.
    publish_results(session); revisions = session.revisions();
    CHECK(session.replace_loaded(session.project()).ok());
    CHECK(session.revisions().source == revisions.source + 1 && !session.geometry_current());
    publish_results(session);
    const auto old_allocation_revision = session.revisions().allocation;
    da::GeometrySnapshot fresh; fresh.id = "replacement"; fresh.geometry_revision = session.revisions().geometry;
    CHECK(session.publish_geometry(fresh, session.revisions().source).ok());
    CHECK(session.revisions().allocation == old_allocation_revision + 1 && !session.allocation_current());
}
void random_contract() {
    da::DeterministicRandom random(5489);
    // Reference MT19937 outputs, not obtained by calling another implementation here.
    CHECK(random.next() == 3499211612U); CHECK(random.next() == 581869302U);
    CHECK(random.next() == 3890346734U); CHECK(random.next() == 3586334585U);
    da::DeterministicRandom mapped(5489);
    CHECK(*mapped.bounded(10).value == 2); CHECK(*mapped.bounded(10).value == 2);
    CHECK(*mapped.bounded(10).value == 4); CHECK(*mapped.bounded(10).value == 5);
    CHECK(!mapped.bounded(0).ok());
    da::DeterministicRandom rejection(5489);
    CHECK(*rejection.bounded(3000000000U).value == 499211612U);
    CHECK(*rejection.bounded(3000000000U).value == 890346734U); // Skips raw 581869302.
    CHECK(*mapped.bounded(1).value == 0);
}
int main() {
    try {
        geometry_and_validation(); transactions_and_revisions(); random_contract();
        std::cout << checks << " core project checks passed.\n";
        return 0;
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}

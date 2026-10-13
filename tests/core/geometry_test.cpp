#include "dungeon_architect/geometry.h"
#include "../test_support.h"
#include <algorithm>
#include <array>
#include <climits>

namespace da = dungeon_architect;
da::Project canvas(int columns = 12, int rows = 10) {
    auto p = da::make_default_project();
    p.settings.columns = columns; p.settings.rows = rows; p.settings.room_count = 4;
    p.settings.min_room_width = p.settings.min_room_height = 1;
    p.settings.max_room_width = p.settings.max_room_height = 3;
    p.settings.corridor_width = 1;
    p.allowed_mask.assign(static_cast<std::size_t>(columns * rows), 1);
    return p;
}
da::Room room(std::string id, da::Rect bounds, da::RoomRole role = da::RoomRole::normal) {
    da::Room r; r.id = std::move(id); r.name = "Room"; r.bounds = bounds;
    r.role = role; r.lock_position = r.lock_size = true;
    return r;
}
bool has(const da::Status& status, const std::string& code) {
    return std::any_of(status.diagnostics.begin(), status.diagnostics.end(), [&](const auto& d) { return d.code == code; });
}
void masks() {
    auto mask = da::make_mask(6, 6, da::MaskPreset::rectangle, {1, 2, 3, 2});
    CHECK(mask.ok()); CHECK(std::count(mask.value->begin(), mask.value->end(), 1) == 6);
    CHECK((*mask.value)[13] == 1 && (*mask.value)[12] == 0 && (*mask.value)[21] == 1);
    mask = da::make_mask(4, 4, da::MaskPreset::ellipse, {0, 0, 4, 4});
    CHECK(*mask.value == std::vector<std::uint8_t>({0,1,1,0, 1,1,1,1, 1,1,1,1, 0,1,1,0}));
    mask = da::make_mask(4, 4, da::MaskPreset::l_shape, {0, 0, 4, 4});
    CHECK(*mask.value == std::vector<std::uint8_t>({1,1,0,0, 1,1,0,0, 1,1,1,1, 1,1,1,1}));
    CHECK(!da::make_mask(4, 4, da::MaskPreset::l_shape, {0,0,1,4}).ok());
    CHECK(!da::make_mask(4, 4, da::MaskPreset::ellipse, {-1,0,4,4}).ok());
    CHECK(!da::make_mask(INT_MAX, INT_MAX, da::MaskPreset::rectangle, {0,0,1,1}).ok());
    mask = da::make_mask(512, 512, da::MaskPreset::ellipse, {0,0,512,512});
    CHECK(mask.ok()); CHECK((*mask.value)[0] == 0 && (*mask.value)[256 * 512 + 256] == 1);
    da::ProjectSession s;
    CHECK(s.replace_loaded(canvas(6,6)).ok());
    const auto before = s.project().allowed_mask;
    const auto revision = s.revisions().source;
    CHECK(!da::paint_tiles(s, {{1,1}, {6,0}}, false).ok());
    CHECK(s.project().allowed_mask == before && s.revisions().source == revision);
    CHECK(da::paint_tiles(s, {{3,0},{3,1},{3,2},{3,3},{3,4},{3,5}}, false).ok());
    CHECK(da::flood_fill(s, {0,0}, false).ok());
    CHECK(std::count(s.project().allowed_mask.begin(), s.project().allowed_mask.end(), 1) == 12);
    CHECK(da::flood_fill(s, {0,0}, true).ok());
    CHECK(std::count(s.project().allowed_mask.begin(), s.project().allowed_mask.end(), 1) == 36);
    CHECK(!da::flood_fill(s, {-1,0}, false).ok());
    CHECK(da::apply_mask_preset(s, da::MaskPreset::rectangle, {0,0,2,2}).ok());
    auto analysis = da::analyze_mask(s.project());
    CHECK(analysis.value->components.size() == 1 && analysis.value->components[0].bounds == da::Rect{0,0,2,2});
    CHECK(da::paint_tiles(s, {{5,5}}, true).ok());
    analysis = da::analyze_mask(s.project());
    CHECK(analysis.value->components.size() == 2 && analysis.value->primary_component == 0);
    CHECK(analysis.value->labels[35] == 1);
    CHECK(da::flood_fill(s, {0,0}, false).ok());
    CHECK(da::analyze_mask(s.project()).value->primary_component == 0); // remaining island relabelled
    CHECK(da::flood_fill(s, {5,5}, false).ok());
    CHECK(da::analyze_mask(s.project()).value->primary_component == -1);
    CHECK(has(da::prepare_geometry(s.project()).status, "empty_mask"));
}
void connectivity_oracle() {
    // Exhaust all 3x3 masks. Independent all-pairs transitive closure checks
    // every label equivalence, including diagonal contacts and narrow necks.
    auto p = canvas(3,3);
    for (unsigned bits = 0; bits < 512; ++bits) {
        bool reach[9][9]{};
        for (int a = 0; a < 9; ++a) p.allowed_mask[static_cast<std::size_t>(a)] = (bits & (1U << a)) ? 1 : 0;
        for (int a = 0; a < 9; ++a) for (int b = 0; b < 9; ++b)
            reach[a][b] = p.allowed_mask[static_cast<std::size_t>(a)] && p.allowed_mask[static_cast<std::size_t>(b)] &&
                (a == b || (a / 3 == b / 3 && std::abs(a - b) == 1) || std::abs(a - b) == 3);
        for (int k = 0; k < 9; ++k) for (int a = 0; a < 9; ++a) for (int b = 0; b < 9; ++b)
            reach[a][b] = reach[a][b] || (reach[a][k] && reach[k][b]);
        const auto analysis = da::analyze_mask(p);
        CHECK(analysis.ok());
        for (std::size_t a = 0; a < 9; ++a) for (std::size_t b = 0; b < 9; ++b)
            CHECK(reach[a][b] == (analysis.value->labels[a] >= 0 && analysis.value->labels[a] == analysis.value->labels[b]));
    }
}
void fixed_rooms() {
    auto p = canvas(); p.rooms = {room("a", {1,1,2,2}), room("b", {4,1,2,2})};
    CHECK(da::validate_project(p).ok()); // one separating tile, shared margins permitted
    const auto original_mask = p.allowed_mask;
    auto prepared = da::prepare_geometry(p); CHECK(prepared.ok());
    CHECK(prepared.value->mandatory_rooms == 2 && prepared.value->remaining_rooms == 2);
    CHECK(p.allowed_mask == original_mask);
    const auto& reserve = prepared.value->reservations;
    CHECK(reserve.fixed_rooms()[0].id == "a" && reserve.fixed_rooms()[0].bounds == p.rooms[0].bounds);
    CHECK(!reserve.can_place({2,2,1,1})); // abstract partition crossing fixed interior
    CHECK(!reserve.can_place({3,1,1,1})); // required gap is reserved
    CHECK(reserve.can_place({7,1,2,2}));
    CHECK(!reserve.can_place({0,5,2,2})); // new room's own canvas margin
    CHECK(!reserve.can_place({INT_MAX,0,INT_MAX,1}));
    CHECK(reserve.footprint_owners()[13] == 0 && reserve.footprint_owners()[16] == 1);
    CHECK(reserve.blocked()[3] == 1 && reserve.footprint_owners()[3] == -1);
    p.rooms[0].bounds = {8,6,2,2};
    CHECK(reserve.fixed_rooms()[0].bounds == da::Rect{1,1,2,2}); // independent immutable snapshot
    p.rooms[0].bounds = {3,1,2,2}; CHECK(has(da::validate_project(p), "room_overlap"));
    p.rooms[0].bounds = {1,1,3,2}; CHECK(has(da::validate_project(p), "room_separation"));
    p.rooms[0].bounds = {0,5,2,2}; CHECK(has(da::validate_project(p), "room_margin_boundary"));
    p.settings.margin = 0; CHECK(da::validate_project(p).ok());
    p.rooms[0].bounds = {2,1,2,2}; CHECK(da::validate_project(p).ok()); // touching, margin zero
    p.settings.margin = 1; p.rooms[0].bounds = {1,1,2,2};
    p.allowed_mask[13] = 0;
    auto status = da::validate_project(p); CHECK(has(status, "room_mask_hole"));
    CHECK(status.diagnostics.front().affected_ids == std::vector<std::string>{"a"});
    CHECK(status.diagnostics.front().affected_tiles == std::vector<da::Tile>{{1,1}});
    p.allowed_mask[13] = 1; p.allowed_mask[0] = 0; CHECK(has(da::validate_project(p), "room_margin_mask"));
    p.allowed_mask[0] = 1;
    p.rooms.push_back(room("c", {8,6,2,2})); p.settings.room_count = 2;
    CHECK(has(da::validate_project(p), "mandatory_room_count"));
    p.settings.room_count = 4;
    p.rooms[0].role = p.rooms[1].role = da::RoomRole::entrance;
    CHECK(has(da::validate_project(p), "duplicate_terminal"));
    p.rooms[0].role = p.rooms[1].role = da::RoomRole::boss;
    p.settings.room_count = 3;
    CHECK(has(da::prepare_geometry(p).status, "terminal_room_count"));
    p = canvas(); p.rooms = {room("a", {1,1,2,2}), room("b", {8,6,2,2})};
    for (int y = 0; y < 10; ++y) p.allowed_mask[static_cast<std::size_t>(y * 12 + 5)] = 0;
    CHECK(da::validate_project(p).ok());
    CHECK(has(da::prepare_geometry(p).status, "fixed_rooms_disconnected"));
    p.rooms[1].lock_position = p.rooms[1].lock_size = false;
    CHECK(da::prepare_geometry(p).ok());
    p = canvas(); p.allowed_mask[5 * 12 + 5] = 0;
    prepared = da::prepare_geometry(p); CHECK(prepared.ok());
    CHECK(!prepared.value->reservations.can_place({4,4,3,3})); // hole inside candidate
    CHECK(!prepared.value->reservations.can_place({3,4,2,2})); // hole inside its margin
    CHECK(prepared.value->reservations.can_place({1,1,2,2}));
}
void edits_and_terminals() {
    da::ProjectSession s; CHECK(s.replace_loaded(canvas()).ok());
    auto a = room("a", {1,1,2,2}); CHECK(da::add_room(s, a).ok());
    const auto revision = s.revisions().source;
    auto edit = a; edit.bounds.x = 2;
    CHECK(has(da::edit_room(s, "a", edit), "locked_position"));
    edit.lock_position = false;
    CHECK(has(da::edit_room(s, "a", edit), "locked_position")); // cannot unlock+move atomically
    edit = a; edit.bounds.width = 3; CHECK(has(da::edit_room(s, "a", edit), "locked_size"));
    CHECK(has(da::remove_room(s, "a"), "locked_room_removed"));
    CHECK(!da::paint_tiles(s, {{1,1}}, false).ok());
    CHECK(!da::flood_fill(s, {0,0}, false).ok());
    CHECK(!da::apply_mask_preset(s, da::MaskPreset::rectangle, {7,7,3,3}).ok());
    CHECK(s.revisions().source == revision && s.project().rooms[0].bounds == a.bounds);
    edit = a; edit.name = "Renamed";
    CHECK(da::edit_room(s, "a", edit).ok()); CHECK(s.project().rooms[0].id == "a");
    edit.id = "changed"; CHECK(has(da::edit_room(s, "a", edit), "stable_room_id"));
    edit = a; edit.lock_position = false; CHECK(da::edit_room(s, "a", edit).ok());
    edit.bounds.x = 2; CHECK(da::edit_room(s, "a", edit).ok());
    edit.bounds.width = 3; CHECK(has(da::edit_room(s, "a", edit), "locked_size"));
    edit.bounds.width = 2; edit.lock_size = false; CHECK(da::edit_room(s, "a", edit).ok());
    CHECK(da::remove_room(s, "a").ok()); CHECK(s.project().rooms.empty());
    CHECK(!da::remove_room(s, "a").ok());
    auto b = room("b", {4,1,2,2}); auto boss = room("z", {8,6,2,2}, da::RoomRole::boss);
    CHECK(da::add_room(s, a).ok()); CHECK(da::add_room(s, b).ok());
    auto p = s.project(); std::reverse(p.rooms.begin(), p.rooms.end());
    const auto rev = s.revisions().source; CHECK(s.update(p).ok()); CHECK(s.revisions().source == rev);
    auto selected = da::select_terminals({boss,b,a}); CHECK(selected.ok());
    CHECK(selected.value->entrance == "a" && selected.value->exit == "b");
    CHECK(*da::encounter_capacity(a, *selected.value, 4).value == 0);
    b.capacity_override = 3; CHECK(*da::encounter_capacity(b, *selected.value, 2).value == 2);
    CHECK(*da::encounter_capacity(b, *selected.value, 4).value == 3);
    CHECK(!da::encounter_capacity(b, *selected.value, 5).ok());
    CHECK(!da::select_terminals({a,boss}).ok());
    b.role = da::RoomRole::entrance; a.role = da::RoomRole::exit;
    selected = da::select_terminals({a,b,boss}); CHECK(selected.ok());
    CHECK(selected.value->entrance == "b" && selected.value->exit == "a");
    a.role = da::RoomRole::entrance; CHECK(!da::select_terminals({a,b}).ok());
    CHECK(s.replace_loaded(canvas()).ok()); // loading a document intentionally replaces previous locks
}
int main() {
    try {
        masks(); connectivity_oracle(); fixed_rooms(); edits_and_terminals();
        std::cout << checks << " mask/fixed-room checks passed.\n";
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}

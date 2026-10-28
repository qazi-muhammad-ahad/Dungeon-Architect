#include "dungeon_architect/generation.h"
#include <algorithm>
#include <chrono>
#include <set>

namespace dungeon_architect {
namespace {
Status problem(Outcome outcome, const char* code, const char* message) {
    return failure(outcome, code, "/generation", message,
                   "Adjust the mask, fixed rooms, sizes, count, seed, or search limits and retry; the previous result is unchanged.");
}
bool intersects(Rect a, Rect b) {
    return a.x < b.right() && b.x < a.right() && a.y < b.bottom() && b.y < a.bottom();
}
struct Prefix {
    std::int32_t stride = 0;
    std::vector<std::int32_t> cells;
    explicit Prefix(std::int32_t columns, std::int32_t rows) : stride(columns + 1),
        cells(static_cast<std::size_t>(columns + 1) * static_cast<std::size_t>(rows + 1), 0) {}
    std::size_t at(std::int32_t x, std::int32_t y) const { return static_cast<std::size_t>(y * stride + x); }
    void put(std::int32_t x, std::int32_t y, bool bad) {
        cells[at(x+1,y+1)] = (bad ? 1 : 0) + cells[at(x,y+1)] + cells[at(x+1,y)] - cells[at(x,y)];
    }
    std::int32_t sum(Rect r) const {
        const auto right = r.x + r.width, bottom = r.y + r.height;
        return cells[at(right,bottom)] - cells[at(r.x,bottom)] - cells[at(right,r.y)] + cells[at(r.x,r.y)];
    }
};
class Search {
public:
    Search(const Project& p, const GenerationOptions& o) : source(p), options(o), rng(p.settings.seed),
        started(std::chrono::steady_clock::now()) {}
    GenerationResult run() {
        auto out = run_impl(); timing.next("done"); out.metrics.timings_us = timing.values; return out;
    }
    GenerationResult run_impl() {
        if (source.settings.max_time_ms <= 0 || source.settings.max_work_units <= 0 || source.settings.max_generation_attempts <= 0) {
            result.status = validate_project(source); return std::move(result);
        }
        if (options.max_events > 4096) {
            result.status = problem(Outcome::unsupported_size, "trace_limit", "Trace storage supports at most 4096 events.");
            return std::move(result);
        }
        if (!tick(0)) return std::move(result);
        auto preflight = prepare_geometry(source);
        if (!preflight.ok()) { result.status = std::move(preflight.status); return std::move(result); }
        if (!tick(0)) return std::move(result);
        if (source.settings.room_count > static_cast<std::int32_t>(limits::max_records)) {
            result.status = problem(Outcome::unsupported_size, "generated_record_limit", "The requested layout exceeds the 4096-room storage guard.");
            return std::move(result);
        }
        prepared = std::move(*preflight.value);
        const auto& s = source.settings;
        mask.emplace(s.columns, s.rows); unavailable.emplace(s.columns, s.rows);
        for (std::int32_t y = 0; y < s.rows; ++y) for (std::int32_t x = 0; x < s.columns; ++x) {
            if (!tick()) return std::move(result);
            const auto i = static_cast<std::size_t>(y * s.columns + x);
            mask->put(x, y, !source.allowed_mask[i]);
            unavailable->put(x, y, !source.allowed_mask[i] || prepared.reservations.blocked()[i]);
        }
        origins.emplace(s.columns,s.rows);
        for (std::int32_t y = 0; y < s.rows; ++y) for (std::int32_t x = 0; x < s.columns; ++x) {
            if (!tick()) return std::move(result);
            Rect interior{x,y,s.min_room_width,s.min_room_height};
            Rect buffered{x-s.margin,y-s.margin,s.min_room_width+2*s.margin,s.min_room_height+2*s.margin};
            const bool valid = buffered.inside(s.columns,s.rows) && mask->sum(buffered) == 0 && unavailable->sum(interior) == 0;
            origins->put(x,y,valid);
        }
        const Rect root{0,0,s.columns,s.rows};
        if (capacity(root) < static_cast<std::int32_t>(prepared.remaining_rooms)) {
            result.status = problem(Outcome::invalid_input, "insufficient_free_area", "Minimum-room placement upper bounds are below the requested count (area, dimensions, or valid minimum-room origins).");
            return std::move(result);
        }
        std::set<RoomId> used;
        for (const auto& room : source.rooms) used.insert(room.id);
        std::size_t serial = 1;
        while (ids.size() < prepared.remaining_rooms) {
            if (!tick()) return std::move(result);
            auto id = "generated-" + std::to_string(serial++);
            if (used.insert(id).second) ids.push_back(std::move(id));
        }
        timing.next("search");
        for (const auto& room : prepared.reservations.fixed_rooms()) event("fixed_reserved", -1, room.bounds, room.id);
        if (!solve(root, static_cast<std::int32_t>(prepared.remaining_rooms), -1, 0)) {
            if (result.status.ok()) result.status = problem(Outcome::search_exhausted, "no_layout_found", "No valid exact-count layout found within the bounded BSP search.");
            if (last_rejection && result.status.outcome == Outcome::search_exhausted) result.status.diagnostics.push_back(*last_rejection);
            return std::move(result);
        }
        timing.next("finalization");
        for (const auto& fixed : prepared.reservations.fixed_rooms()) {
            const Room* nearest = nullptr;
            std::int64_t distance = std::numeric_limits<std::int64_t>::max();
            for (const auto& other : layout.rooms) {
                if (!tick()) return std::move(result);
                const auto d = std::abs((2LL * fixed.bounds.x + fixed.bounds.width) - (2LL * other.bounds.x + other.bounds.width)) +
                               std::abs((2LL * fixed.bounds.y + fixed.bounds.height) - (2LL * other.bounds.y + other.bounds.height));
                if (!nearest || d < distance || (d == distance && other.id < nearest->id)) { nearest = &other; distance = d; }
            }
            if (nearest) layout.connections.push_back({nearest->id, fixed.id, true});
            layout.rooms.push_back(fixed);
        }
        std::sort(layout.rooms.begin(), layout.rooms.end(), [](const Room& a, const Room& b) { return a.id < b.id; });
        auto terminals = select_terminals(layout.rooms);
        if (!terminals.ok()) { result.status = terminals.status; return std::move(result); }
        layout.terminals = *terminals.value;
        layout.occupancy.assign(source.allowed_mask.size(), 0);
        layout.reservations.assign(source.allowed_mask.size(), 0);
        for (const auto& room : layout.rooms) {
            const auto& r = room.bounds;
            for (auto y = r.y-s.margin; y < r.bottom()+s.margin; ++y) for (auto x = r.x-s.margin; x < r.right()+s.margin; ++x) {
                if (!tick()) return std::move(result);
                const auto i = static_cast<std::size_t>(y * s.columns + x);
                layout.reservations[i] = 1;
                if (r.contains({x,y})) layout.occupancy[i] = 1;
            }
        }
        // Charge bounded final checks up front; final checks use independent cell scans.
        std::int64_t validation_work = static_cast<std::int64_t>(layout.rooms.size() * layout.rooms.size()) +
                                       static_cast<std::int64_t>(source.allowed_mask.size()) * 4;
        for (const auto& node : layout.partitions) validation_work += std::int64_t{node.bounds.width} * node.bounds.height +
                                                                    static_cast<std::int64_t>(prepared.mandatory_rooms);
        if (!tick(validation_work)) return std::move(result);
        layout.id = "rooms-seed-" + std::to_string(s.seed);
        result.status = validate_room_layout(source, layout);
        if (result.status.ok() && tick(0)) result.layout = std::move(layout);
        return std::move(result);
    }
private:
    const Project& source;
    const GenerationOptions& options;
    DeterministicRandom rng;
    std::chrono::steady_clock::time_point started;
    PreparedGeometry prepared;
    std::optional<Prefix> mask, unavailable, origins;
    std::vector<RoomId> ids;
    RoomLayoutSnapshot layout;
    GenerationResult result;
    PhaseClock timing{"preflight"};
    std::optional<Diagnostic> last_rejection;
    bool tick(std::int64_t work = 1) {
        if (!result.status.ok()) return false;
        if (options.cancelled && options.cancelled()) {
            result.status = problem(Outcome::cancelled, "cancelled", "Room generation was cancelled."); return false;
        }
        if (std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-started).count() >= source.settings.max_time_ms) {
            result.status = problem(Outcome::search_exhausted, "time_limit", "No layout was committed before the time limit."); return false;
        }
        if (work > source.settings.max_work_units - result.metrics.work_units) {
            result.status = problem(Outcome::search_exhausted, "work_limit", "No layout was committed within the work-unit limit."); return false;
        }
        result.metrics.work_units += work;
        return true;
    }
    bool attempt() {
        if (!tick()) return false;
        if (result.metrics.attempts >= source.settings.max_generation_attempts) {
            result.status = problem(Outcome::search_exhausted, "attempt_limit", "No layout was committed within the candidate/split attempt limit."); return false;
        }
        ++result.metrics.attempts; return true;
    }
    std::int32_t random(std::int32_t bound) { return static_cast<std::int32_t>(*rng.bounded(static_cast<std::uint32_t>(bound)).value); }
    void event(const char* kind, std::int32_t node, Rect bounds, RoomId id = {}, const char* reason = "", std::int32_t cut = 0, std::int32_t child_count = 0) {
        TraceClock trace_clock(result.metrics.trace_us);
        if (result.events.size() < options.max_events) result.events.push_back({kind,reason,node,bounds,std::move(id),result.metrics.attempts,cut,child_count});
        else ++result.metrics.dropped_events;
    }
    std::int32_t free(Rect r) const { return r.width*r.height - unavailable->sum(r); }
    std::int32_t capacity(Rect r) const {
        const auto& s = source.settings;
        if (r.width < s.min_room_width || r.height < s.min_room_height) return 0;
        const Rect starts{r.x,r.y,r.width-s.min_room_width+1,r.height-s.min_room_height+1};
        return std::min({(r.width / s.min_room_width) * (r.height / s.min_room_height),
                        free(r) / (s.min_room_width*s.min_room_height), origins->sum(starts)});
    }
    bool leaf(Rect region, std::int32_t node) {
        const auto& s = source.settings;
        const auto widths = std::min(region.width,s.max_room_width)-s.min_room_width+1;
        const auto heights = std::min(region.height,s.max_room_height)-s.min_room_height+1;
        if (widths <= 0 || heights <= 0) return false;
        const auto sizes = widths*heights, size_start = random(sizes);
        for (std::int32_t j = 0; j < sizes; ++j) {
            const auto size = (size_start+j)%sizes;
            const auto w = s.min_room_width+size%widths, h = s.min_room_height+size/widths;
            const auto columns = region.width-w+1, rows = region.height-h+1;
            const auto count = columns*rows, start = random(count);
            for (std::int32_t k = 0; k < count; ++k) {
                if (!attempt()) return false;
                const auto pos = (start+k)%count;
                Rect r{region.x+pos%columns,region.y+pos/columns,w,h};
                const Rect buffered{r.x-s.margin,r.y-s.margin,w+2*s.margin,h+2*s.margin};
                const char* rejected = nullptr;
                if (!buffered.inside(s.columns,s.rows)) rejected = "candidate_boundary";
                else if (mask->sum(buffered) != 0) rejected = "candidate_mask_hole";
                else if (unavailable->sum(r) != 0) rejected = "candidate_reserved";
                if (rejected) {
                    ++result.metrics.rejected_candidates;
                    event("candidate_rejected",node,r,{},rejected);
                    last_rejection = Diagnostic{rejected,"/generation/candidate","Last rejected room candidate violates the mask, boundary, or fixed reservation.",{},{{r.x,r.y}},"Inspect this candidate and the mask/reservations, or change seed/search limits."};
                    continue;
                }
                Room room; room.id = ids[layout.rooms.size()]; room.name = "Room " + std::to_string(layout.rooms.size()+1); room.bounds = r;
                layout.partitions[static_cast<std::size_t>(node)].room_id = room.id;
                event("room_placed",node,r,room.id);
                layout.rooms.push_back(std::move(room)); return true;
            }
        }
        return false;
    }
    bool solve(Rect region, std::int32_t count, std::int32_t parent, unsigned depth) {
        if (!tick() || depth > 64 || capacity(region) < count) return false;
        const auto index = static_cast<std::int32_t>(layout.partitions.size());
        PartitionNode node; node.id = index; node.parent = parent; node.bounds = region; node.requested_rooms = count;
        node.allowed_tiles = region.width*region.height-mask->sum(region); node.free_tiles = free(region);
        timing.next("finalization");
        for (const auto& fixed : prepared.reservations.fixed_rooms()) {
            if (!tick()) return false;
            if (intersects(region,fixed.bounds)) node.intersecting_fixed_rooms.push_back(fixed.id);
        }
        layout.partitions.push_back(std::move(node)); event("region_created",index,region);
        if (count == 0) return true;
        if (count == 1) return leaf(region,index);
        const auto& s = source.settings;
        const bool x_first = region.width == region.height ? random(2) == 0 : region.width > region.height;
        for (int orientation = 0; orientation < 2; ++orientation) {
            const bool x = orientation == 0 ? x_first : !x_first;
            const auto extent = x ? region.width : region.height, minimum = x ? s.min_room_width : s.min_room_height;
            const auto cuts = extent-2*minimum-s.margin+1;
            if (cuts <= 0) continue;
            const auto start = random(cuts);
            for (std::int32_t c = 0; c < cuts; ++c) {
                if (!tick()) return false;
                const auto first_extent = minimum+(start+c)%cuts;
                Rect a = region, b = region;
                if (x) { a.width = first_extent; b.x += first_extent+s.margin; b.width -= first_extent+s.margin; }
                else { a.height = first_extent; b.y += first_extent+s.margin; b.height -= first_extent+s.margin; }
                const auto low = std::max(1,count-capacity(b)), high = std::min(count-1,capacity(a));
                if (low > high) {
                    event("split_rejected",index,region,{},"insufficient_child_capacity");
                    last_rejection = Diagnostic{"insufficient_child_capacity","/generation/partition","Last split cannot distribute the requested rooms within child placement upper bounds.",{},{{region.x,region.y}},"Change the split opportunities, requested count, sizes, mask, or seed."};
                    continue;
                }
                const auto desired = static_cast<std::int32_t>((std::int64_t{count}*free(a))/(free(a)+free(b)));
                const auto first_count = std::clamp(desired,low,high);
                for (auto offset = 0; offset <= high-low; ++offset) {
                    if (!attempt()) return false;
                    const auto ac = low+(first_count-low+offset)%(high-low+1);
                    const auto saved_rooms = layout.rooms.size(), saved_edges = layout.connections.size();
                    const auto saved_nodes = layout.partitions.size();
                    event("split_selected",index,region,{},x ? "x" : "y",x ? b.x-s.margin : b.y-s.margin,ac);
                    const auto first_child = static_cast<std::int32_t>(layout.partitions.size());
                    if (solve(a,ac,index,depth+1)) {
                        const auto second_child = static_cast<std::int32_t>(layout.partitions.size());
                        if (solve(b,count-ac,index,depth+1)) {
                            auto& accepted = layout.partitions[static_cast<std::size_t>(index)];
                            accepted.first_child = first_child; accepted.second_child = second_child;
                            accepted.axis = x ? SplitAxis::x : SplitAxis::y;
                            accepted.cut = x ? b.x-s.margin : b.y-s.margin;
                            layout.connections.push_back({layout.rooms[saved_rooms].id,layout.rooms[saved_rooms+static_cast<std::size_t>(ac)].id,false});
                            return true;
                        }
                    }
                    layout.rooms.resize(saved_rooms); layout.connections.resize(saved_edges); layout.partitions.resize(saved_nodes);
                    ++result.metrics.backtracks; event("backtrack",index,region);
                    if (!result.status.ok()) return false;
                }
            }
        }
        return false;
    }
};
}
GenerationResult generate_rooms(const Project& source, const GenerationOptions& options) {
    try { return Search(source,options).run(); }
    catch (const std::bad_alloc&) {
        GenerationResult result;
    PhaseClock timing{"preflight"}; result.status = problem(Outcome::resource_failure,"allocation_failure","Insufficient memory for room generation."); return result;
    }
}
bool ProjectSession::room_layout_current() const noexcept {
    return room_layout_ && room_layout_->geometry_revision == revisions_.geometry;
}
Status ProjectSession::publish_room_layout(RoomLayoutSnapshot snapshot, std::uint64_t expected_source) {
    if (expected_source != revisions_.source || snapshot.geometry_revision != revisions_.geometry)
        return problem(Outcome::stale_result,"stale_result","The source changed while room generation was running.");
    auto status = validate_room_layout(project_,snapshot);
    if (!status.ok()) return status;
    if (revisions_.allocation == std::numeric_limits<std::uint64_t>::max() || revisions_.play == std::numeric_limits<std::uint64_t>::max())
        return problem(Outcome::resource_failure,"revision_overflow","Snapshot revision counter is exhausted.");
    snapshot.id = "rooms-"+std::to_string(expected_source)+"-"+std::to_string(revisions_.allocation+1);
    auto next = std::make_shared<const RoomLayoutSnapshot>(std::move(snapshot));
    room_layout_ = std::move(next);
    ++revisions_.allocation; ++revisions_.play;
    return {};
}
GenerationResult generate_rooms(ProjectSession& session, const GenerationOptions& options) {
    const auto source = session.project();
    const auto revisions = session.revisions();
    auto result = generate_rooms(source,options);
    if (result.ok()) {
        result.layout->geometry_revision = revisions.geometry;
        result.status = session.publish_room_layout(*result.layout,revisions.source);
        if (!result.status.ok()) result.layout.reset();
        else result.layout->id = session.room_layout()->id;
    }
    return result;
}
} // namespace dungeon_architect

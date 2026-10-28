#include "dungeon_architect/allocation.h"
#include <algorithm>
#include <chrono>
#include <new>

namespace dungeon_architect {
namespace {
using Mask = std::uint32_t;
struct Totals { std::int64_t slots = 0, threat = 0, score = 0; };
struct Stop { Status status; };
Status problem(Outcome outcome,const char* code,const char* message) {
    return failure(outcome,code,"/allocation",message,"Adjust the supported workload or limits and rerun optimization.");
}
bool compatible(const Pack& p,const AllocationRoom& r) {
    return r.room.bounds.width >= p.min_room_width && r.room.bounds.height >= p.min_room_height &&
        (p.allowed_roles.empty() || std::find(p.allowed_roles.begin(),p.allowed_roles.end(),r.room.role) != p.allowed_roles.end()) &&
        std::all_of(p.required_tags.begin(),p.required_tags.end(),[&](const std::string& tag) {
            return std::find(r.room.tags.begin(),r.room.tags.end(),tag) != r.room.tags.end();
        });
}
class Solver {
    const AllocationInput& input;
    const AllocationOptions& options;
    AllocationResult result;
    PhaseClock timing{"preprocessing"};
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    void checkpoint() {
        if (options.cancelled && options.cancelled()) throw Stop{problem(Outcome::cancelled,"allocation_cancelled","Optimization was cancelled; no optimum is published.")};
        if (std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-start).count() >= input.settings.max_time_ms)
            throw Stop{problem(Outcome::resource_failure,"allocation_deadline","Optimization exceeded its time limit; no optimum is published.")};
    }
    void work(std::uint64_t n = 1) {
        if (n > static_cast<std::uint64_t>(input.settings.max_work_units)-result.metrics.work_units)
            throw Stop{problem(Outcome::resource_failure,"allocation_work_limit","Optimization exceeded its work limit; no optimum is published.")};
        const auto old = result.metrics.work_units; result.metrics.work_units += n;
        if (old/1024 != result.metrics.work_units/1024) checkpoint();
    }
    void event(std::string kind,RoomId room = {},Mask mask = 0,Mask subset = 0,std::uint64_t states = 0) {
        TraceClock trace_clock(result.metrics.trace_us);
        const bool reconstruction = kind == "reconstruct" || kind == "optimal";
        const auto reserve = std::min(options.max_events/2,result.metrics.eligible_rooms+1);
        const auto limit = reconstruction ? options.max_events : options.max_events-reserve;
        if (result.events.size() < limit) result.events.push_back({std::move(kind),std::move(room),mask,subset,states});
        else ++result.metrics.dropped_events;
    }
    void solve() {
        if (options.cancelled && options.cancelled()) throw Stop{problem(Outcome::cancelled,"allocation_cancelled","Optimization was cancelled; no optimum is published.")};
        auto status = validate_allocation_input(input); if (!status.ok()) throw Stop{status};
        checkpoint();
        if (options.max_events > 4096) throw Stop{problem(Outcome::invalid_input,"allocation_trace_limit","Trace capacity must be at most 4096 events.")};
        std::vector<Pack> packs;
        for (const auto& p : input.packs) if (p.active) packs.push_back(p);
        std::sort(packs.begin(),packs.end(),[](const Pack& a,const Pack& b) { return a.id < b.id; });
        std::vector<AllocationRoom> rooms;
        for (auto r : input.rooms) if (r.reachable && r.capacity > 0 && r.room.role != RoomRole::entrance) {
            std::sort(r.spawns.begin(),r.spawns.end(),[](const SpawnPosition& a,const SpawnPosition& b) {
                return std::tie(a.tile.y,a.tile.x,a.id) < std::tie(b.tile.y,b.tile.x,b.id);
            }); rooms.push_back(std::move(r));
        }
        std::sort(rooms.begin(),rooms.end(),[](const AllocationRoom& a,const AllocationRoom& b) { return a.room.id < b.room.id; });
        const auto n = packs.size(), rcount = rooms.size();
        result.metrics.active_packs = n; result.metrics.eligible_rooms = rcount;
        if (options.detailed_trace && (n > 6 || rcount > 8))
            throw Stop{problem(Outcome::unsupported_size,"detailed_trace_size","Detailed state traces require at most 6 active packs and 8 eligible rooms.")};
        const Mask count = Mask{1} << n;
        std::uint64_t cube = 1; for (std::size_t i = 0; i < n; ++i) cube *= 3;
        std::uint64_t actor_bound = 0; for (const auto& r : rooms) actor_bound += static_cast<std::uint64_t>(r.capacity);
        // Guarded N<=14, R<=4096 makes all products below safely fit uint64_t.
        result.metrics.estimated_bytes = count*(sizeof(Totals)+2ULL+rcount*(sizeof(std::uint16_t)+1ULL))+rcount*sizeof(Mask);
        result.metrics.estimated_work = count*(3ULL+rcount)+rcount*cube+rcount*n+n+1+actor_bound;
        if (result.metrics.estimated_bytes > 64ULL*1024*1024)
            throw Stop{problem(Outcome::unsupported_size,"allocation_memory_estimate","DP table estimate exceeds the supported 64 MiB limit.")};
        if (result.metrics.estimated_work > static_cast<std::uint64_t>(input.settings.max_work_units))
            throw Stop{problem(Outcome::resource_failure,"allocation_work_estimate","Worst-case DP work exceeds the configured budget before table allocation.")};
        checkpoint(); event("preflight");
        std::vector<Totals> totals(count);
        for (Mask m = 1; m < count; ++m) {
            const Mask bit = m & (~m+1); std::size_t k = 0; for (Mask b = bit; b > 1; b >>= 1) ++k;
            const auto& prior = totals[m^bit]; const auto& p = packs[k]; auto& t = totals[m];
            if (!checked_add(prior.slots,p.slots,t.slots) || !checked_add(prior.threat,p.threat,t.threat) || !checked_add(prior.score,p.score,t.score))
                throw Stop{problem(Outcome::invalid_input,"subset_overflow","Subset totals exceed signed 64-bit storage.")};
            work();
        }
        std::vector<std::uint8_t> fits(rcount*count,0);
        for (std::size_t r = 0; r < rcount; ++r) {
            Mask allowed = 0;
            for (std::size_t k = 0; k < n; ++k) { if (compatible(packs[k],rooms[r])) allowed |= Mask{1} << k; work(); }
            for (Mask m = 0; m < count; ++m) {
                fits[r*count+m] = static_cast<std::uint8_t>((m & ~allowed) == 0 && totals[m].slots <= rooms[r].capacity); work();
            }
        }
        timing.next("dp");
        const auto missing = std::numeric_limits<std::uint16_t>::max();
        std::vector<std::uint16_t> predecessors(rcount*count,missing);
        std::vector<std::uint8_t> previous(count,0),next(count,0); previous[0] = 1;
        result.metrics.allocated_table_bytes = totals.capacity()*sizeof(Totals)+fits.capacity()*sizeof(std::uint8_t)+predecessors.capacity()*sizeof(std::uint16_t)+(previous.capacity()+next.capacity())*sizeof(std::uint8_t);
        for (std::size_t r = 0; r < rcount; ++r) {
            std::fill(next.begin(),next.end(),0); std::uint64_t states = 0;
            for (Mask m = 0; m < count; ++m) {
                Mask chosen = 0; bool found = previous[m] != 0;
                work(); ++result.metrics.transitions;
                if (options.detailed_trace) event(previous[m] ? "candidate_empty_feasible" : "candidate_empty_infeasible",rooms[r].room.id,m,0);
                // Unsigned subtraction enumerates submasks in ascending order.
                if (!found) for (Mask sub = (Mask{0}-m)&m; sub; sub = (sub-m)&m) {
                    work(); ++result.metrics.transitions;
                    if (options.detailed_trace) event(fits[r*count+sub] && previous[m^sub] ? "candidate_feasible" : "candidate_infeasible",rooms[r].room.id,m,sub);
                    if (fits[r*count+sub] && previous[m^sub]) { chosen = sub; found = true; break; }
                }
                if (found) { next[m] = 1; predecessors[r*count+m] = static_cast<std::uint16_t>(chosen); ++states; }
                if (options.detailed_trace) event(found ? "state_feasible" : "state_infeasible",rooms[r].room.id,m,chosen);
            }
            result.metrics.feasible_states += states; event("room_summary",rooms[r].room.id,0,0,states);
            previous.swap(next); checkpoint();
        }
        auto ids = [&](Mask m) { std::vector<PackId> list; for (std::size_t k = 0; k < n; ++k) if (m & (Mask{1}<<k)) list.push_back(packs[k].id); return list; };
        Mask best = 0;
        for (Mask m = 0; m < count; ++m) {
            work(); if (!previous[m] || totals[m].threat > input.settings.threat_budget) continue;
            const auto& a = totals[m]; const auto& b = totals[best];
            if (a.score > b.score || (a.score == b.score && (a.threat < b.threat || (a.threat == b.threat &&
                (a.slots < b.slots || (a.slots == b.slots && ids(m) < ids(best))))))) best = m;
        }
        timing.next("reconstruction");
        AllocationSnapshot output; output.id = "allocation-"+input.geometry_id+"-"+std::to_string(input.allocation_revision);
        output.geometry_id = input.geometry_id; output.geometry_revision = input.geometry_revision; output.allocation_revision = input.allocation_revision;
        output.total_slots = totals[best].slots; output.total_threat = totals[best].threat; output.total_score = totals[best].score;
        std::vector<Mask> assigned(rcount,0); Mask remaining = best;
        for (std::size_t r = rcount; r > 0; --r) {
            assigned[r-1] = predecessors[(r-1)*count+remaining]; remaining ^= assigned[r-1];
            event("reconstruct",rooms[r-1].room.id,remaining,assigned[r-1]);
        }
        for (std::size_t r = 0; r < rcount; ++r) {
            std::size_t spawn = 0;
            for (std::size_t k = 0; k < n; ++k) if (assigned[r] & (Mask{1}<<k)) {
                output.assignments.push_back({packs[k].id,rooms[r].room.id});
                for (std::int64_t actor = 0; actor < packs[k].slots; ++actor) {
                    const auto& cell = rooms[r].spawns[spawn++]; output.actors.push_back({packs[k].id,rooms[r].room.id,cell.id,cell.tile});
                    // Placement is bounded by total valid cells; keep it cancellable.
                    work();
                }
            }
        }
        for (std::size_t k = 0; k < n; ++k) if (!(best & (Mask{1}<<k))) {
            bool match = false, fit = false;
            for (const auto& r : rooms) if (compatible(packs[k],r)) { match = true; if (packs[k].slots <= r.capacity) fit = true; }
            output.unused.push_back({packs[k].id,fit ? "unselected_by_optimum" : match ? "oversized" : "no_compatible_eligible_room"});
        }
        checkpoint(); status = validate_allocation_result(input,output); if (!status.ok()) throw Stop{status};
        checkpoint(); event("optimal",{},best); result.allocation = std::move(output);
    }
public:
    Solver(const AllocationInput& in,const AllocationOptions& opt) : input(in),options(opt) {}
    AllocationResult run() {
        try { solve(); }
        catch (const Stop& e) { result.status = e.status; result.allocation.reset(); }
        catch (const std::bad_alloc&) { result.status = problem(Outcome::resource_failure,"allocation_memory","Not enough memory for exact optimization."); result.allocation.reset(); }
        timing.next("done"); result.metrics.timings_us = timing.values;
        return std::move(result);
    }
};
}
AllocationResult allocate_encounters(const AllocationInput& input,const AllocationOptions& options) { return Solver(input,options).run(); }
AllocationResult allocate_encounters(const Project& source,const RoomLayoutSnapshot& layout,const GeometrySnapshot& geometry,const AllocationOptions& options) {
    if (options.cancelled && options.cancelled()) { AllocationResult result; result.status = problem(Outcome::cancelled,"allocation_cancelled","Optimization was cancelled."); return result; }
    try {
        auto prepared = prepare_allocation(source,layout,geometry);
        if (!prepared.ok()) { AllocationResult result; result.status = prepared.status; return result; }
        return allocate_encounters(*prepared.value,options);
    } catch (const std::bad_alloc&) { AllocationResult result; result.status = problem(Outcome::resource_failure,"allocation_memory","Not enough memory to prepare allocation."); return result; }
}
AllocationResult allocate_encounters(ProjectSession& session,const AllocationOptions& options) {
    AllocationResult result;
    PhaseClock timing{"preprocessing"};
    try {
        if (options.cancelled && options.cancelled()) {
            result.status = problem(Outcome::cancelled,"allocation_cancelled","Optimization was cancelled."); return result;
        }
        if (!session.geometry_current() || !session.room_layout_current()) {
            result.status = problem(Outcome::stale_result,"allocation_geometry_stale","Generate and route current geometry before optimizing."); return result;
        }
        const auto revisions = session.revisions(); const auto geometry = session.geometry(); const auto layout = session.room_layout();
        const auto source = session.project();
        auto prepared = prepare_allocation(source,*layout,*geometry);
        if (!prepared.ok()) { result.status = prepared.status; return result; }
        prepared.value->allocation_revision = revisions.allocation;
        result = allocate_encounters(*prepared.value,options);
        if (result.ok()) {
            result.status = session.publish_allocation(*result.allocation,revisions.source);
            if (!result.status.ok()) result.allocation.reset();
        }
    } catch (const std::bad_alloc&) {
        result.status = problem(Outcome::resource_failure,"allocation_memory","Not enough memory to prepare or publish allocation.");
        result.allocation.reset();
    }
    return result;
}
} // namespace dungeon_architect

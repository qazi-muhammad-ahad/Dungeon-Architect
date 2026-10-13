#include "dungeon_architect_c.h"
#include "dungeon_architect/project_io.h"
#include "dungeon_architect/result_json.h"
#include "dungeon_architect/simulation.h"
#include "editor_commands.h"
#include <atomic>
#include <chrono>
#include <cstring>
#include <map>
#include <mutex>
#include <new>
#include <string_view>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif
namespace da = dungeon_architect;
namespace io = da::project_io;
namespace report = da::result_io;
using Json = nlohmann::json;
namespace {
constexpr std::size_t max_report_bytes = 128U * 1024U * 1024U;
struct Snapshot {
    std::string report;
    da::Project source;
    std::optional<da::GeometrySnapshot> geometry;
    da_job job = 0;
};
struct Context { da_job active = 0; std::shared_ptr<const Snapshot> last; };
struct Job {
    std::shared_ptr<Context> context;
    std::string input, report, metrics;
    Json events = Json::array();
    std::uint64_t dropped = 0;
    uint32_t operation = 0, max_events = 0, flags = 0, state = DA_PENDING, outcome = 0;
    std::atomic<uint32_t> stage{0};
    std::atomic<bool> cancelled{false};
};
std::mutex registry;
std::map<da_context,std::shared_ptr<Context>> contexts;
std::map<da_job,std::shared_ptr<Job>> jobs;
uint32_t next_token = 1;
uint32_t token() {
    if (next_token == 0) throw std::bad_alloc();
    return next_token++;
}
template<class Fn> da_status guarded(Fn&& fn) noexcept {
    try { return fn(); }
    catch (const std::bad_alloc&) { return DA_RESOURCE_FAILURE; }
    catch (...) { return DA_INTERNAL_ERROR; }
}
da_status copy(std::string_view text, uint8_t* buffer, uint32_t capacity, uint32_t* required) {
    if (!required || (!buffer && capacity)) return DA_INVALID_ARGUMENT;
    if (text.size() > max_report_bytes) return DA_RESOURCE_FAILURE;
    *required = static_cast<uint32_t>(text.size());
    if (capacity < text.size()) return DA_BUFFER_TOO_SMALL;
    if (!text.empty()) std::memcpy(buffer,text.data(),text.size());
    return DA_OK;
}
da::Status cancelled_status() {
    return da::failure(da::Outcome::cancelled,"job_cancelled","/job",
        "Work was cancelled; the previous result is retained.","Run a new job when ready.");
}
uint32_t outcome_code(da::Outcome o) {
    switch (o) {
    case da::Outcome::success: return 0;
    case da::Outcome::invalid_input: return 1;
    case da::Outcome::search_exhausted: return 2;
    case da::Outcome::unsupported_size: return 3;
    case da::Outcome::unsupported_schema: return 4;
    case da::Outcome::cancelled: return 5;
    case da::Outcome::resource_failure: return 6;
    case da::Outcome::io_failure: return 7;
    case da::Outcome::stale_result: return 8;
    }
    return 9;
}
struct Execution { da::Status status; Json doc; std::shared_ptr<Snapshot> snapshot; };
Execution execute(Job& j, da_job id) {
    auto last_yield = std::chrono::steady_clock::now();
    const auto cancelled = [&] {
#ifdef __EMSCRIPTEN__
        // Asyncify yields only in the worker. No shared memory/COOP/COEP needed.
        // No Dart callback is retained; cancellation/polling use plain exports.
        const auto now = std::chrono::steady_clock::now();
        if (now-last_yield >= std::chrono::milliseconds(16)) {
            emscripten_sleep(0);
            last_yield = std::chrono::steady_clock::now();
        }
#else
        (void)last_yield;
#endif
        return j.cancelled.load();
    };
    j.stage = 1;
    if (cancelled()) { auto s = cancelled_status(); return {s,report::error_json(s,"input"),{}}; }
    if (j.operation == DA_EDIT) {
        auto edited=da::editor_api::execute(j.input);
        return {std::move(edited.status),std::move(edited.doc),{}};
    }
    auto parsed = j.operation == DA_NEW_PROJECT ? da::Result<da::Project>{{},da::make_default_project()} : io::parse(j.input);
    if (!parsed.ok()) return {parsed.status,report::error_json(parsed.status,"input"),{}};
    const auto& p = *parsed.value;
    Execution e;
    if (j.operation == DA_NORMALIZE || j.operation == DA_NEW_PROJECT) {
        const auto source = io::serialize(p);
        e.status = source.status;
        e.doc = Json::parse(io::diagnostics_json(e.status));
        if (source.ok()) { e.doc["project_json"] = *source.value; e.doc["editor_analysis"] = da::editor_api::analysis(p); }
        return e;
    }
    if (j.operation == DA_VALIDATE) {
        e.status = da::validate_project(p);
        e.doc = Json::parse(io::diagnostics_json(e.status));
    } else {
        da::GenerationOptions options; options.max_events = j.max_events; options.cancelled = cancelled;
        j.stage = 2;
        auto generated = da::generate_rooms(p,options);
        e.status = generated.status; e.doc = report::layout_json(p,generated);
        Json stages = {{"generation",e.doc}}; stages["generation"].erase("layout");
        std::optional<da::RoutingResult> routed;
        std::optional<da::AllocationResult> allocated;
        if (e.status.ok() && j.operation != DA_GENERATE) {
            j.stage = 3; routed = da::route_corridors(p,*generated.layout,options);
            e.status = routed->status; e.doc = report::geometry_json(p,*routed);
            stages["routing"] = e.doc; stages["routing"].erase("geometry");
        }
        if (e.status.ok() && (j.operation == DA_OPTIMIZE || j.operation == DA_RUN)) {
            j.stage = 4;
            da::AllocationOptions opt; opt.max_events = j.max_events;
            opt.detailed_trace = (j.flags & DA_DETAILED_TRACE) != 0; opt.cancelled = cancelled;
            allocated = da::allocate_encounters(p,*generated.layout,*routed->geometry,opt);
            e.status = allocated->status; e.doc = report::allocation_json(p,*allocated);
            stages["allocation"] = e.doc; stages["allocation"].erase("allocation");
        }
        if (j.operation == DA_RUN) {
            const auto failed = e.status.ok() ? Json(nullptr) : e.doc["stage"];
            e.doc = report::error_json(e.status,"pipeline"); e.doc["failed_stage"] = failed;
            e.doc["stages"] = std::move(stages); e.doc["seed"] = p.settings.seed; e.doc["optimal"] = e.status.ok();
            if (e.status.ok()) e.doc["result"] = {{"layout",report::layout_json(p,generated)["layout"]},
                {"geometry",report::geometry_json(p,*routed)["geometry"]},
                {"allocation",report::allocation_json(p,*allocated)["allocation"]}};
        }
        if (e.status.ok()) {
            e.snapshot = std::make_shared<Snapshot>();
            if (routed) e.snapshot->geometry = std::move(routed->geometry);
        }
    }
    j.stage = 5;
    if (e.status.ok() && j.operation != DA_VALIDATE) {
        auto source = io::serialize(p);
        if (!source.ok()) return {source.status,report::error_json(source.status,"export"),{}};
        if (j.operation == DA_RUN) e.doc["result"]["source_project"] = Json::parse(*source.value);
        else e.doc["source_project"] = Json::parse(*source.value);
        e.snapshot->source = p; e.snapshot->job = id;
    }
    if (cancelled()) { e.status = cancelled_status(); e.doc = report::error_json(e.status,"export"); e.snapshot.reset(); }
    return e;
}
void extract(const Json& doc, Json& metrics, Json& events, std::uint64_t& dropped) {
    const auto stage = doc.value("stage",std::string("validation"));
    if (doc.contains("metrics")) {
        metrics[stage] = doc["metrics"];
        dropped += doc["metrics"].value("dropped_events",std::uint64_t{0});
    }
    if (doc.contains("events")) for (const auto& event : doc["events"])
        events.push_back({{"sequence",events.size()},{"stage",stage},{"event",event}});
}
}
uint32_t DA_CALL da_bootstrap_abi_version(void) { return DA_ABI_VERSION; }
uint32_t DA_CALL da_pointer_bits(void) { return static_cast<uint32_t>(sizeof(void*)*8); }
da_status DA_CALL da_context_create(uint32_t abi, uint32_t schema, da_context* out) {
    if (!out) return DA_INVALID_ARGUMENT;
    *out = 0;
    return guarded([&]() -> da_status {
        if (abi != DA_ABI_VERSION || schema != DA_PROJECT_SCHEMA) return DA_VERSION_MISMATCH;
        std::lock_guard<std::mutex> lock(registry);
        if (contexts.size() >= 32) return DA_RESOURCE_FAILURE;
        auto context = std::make_shared<Context>(); const auto id = token();
        contexts.emplace(id,std::move(context)); *out = id; return DA_OK;
    });
}
da_status DA_CALL da_context_release(da_context context) {
    return guarded([&]() -> da_status {
        std::lock_guard<std::mutex> lock(registry);
        auto it = contexts.find(context); if (it == contexts.end()) return DA_INVALID_HANDLE;
        if (it->second->active) return DA_BUSY;
        contexts.erase(it); return DA_OK;
    });
}
da_status DA_CALL da_job_create(da_context context, uint32_t operation, const uint8_t* input,
    uint32_t length, uint32_t max_events, uint32_t flags, da_job* out) {
    if (!out) return DA_INVALID_ARGUMENT;
    *out = 0;
    return guarded([&]() -> da_status {
        if (!input || !length || length > DA_MAX_INPUT_BYTES || max_events > 4096 ||
            operation < DA_VALIDATE || operation > DA_EDIT || flags > DA_DETAILED_TRACE ||
            (flags && operation != DA_OPTIMIZE && operation != DA_RUN)) return DA_INVALID_ARGUMENT;
        std::lock_guard<std::mutex> lock(registry);
        const auto it = contexts.find(context); if (it == contexts.end()) return DA_INVALID_HANDLE;
        if (it->second->active) return DA_BUSY;
        if (jobs.size() >= 64) return DA_RESOURCE_FAILURE;
        auto j = std::make_shared<Job>(); j->context = it->second;
        j->input.assign(reinterpret_cast<const char*>(input),length);
        j->operation = operation; j->max_events = max_events; j->flags = flags;
        const auto id = token(); jobs.emplace(id,j); it->second->active = id; *out = id; return DA_OK;
    });
}
da_status DA_CALL da_job_execute(da_job id) {
    return guarded([&]() -> da_status {
        std::shared_ptr<Job> j;
        {
            std::lock_guard<std::mutex> lock(registry);
            const auto it = jobs.find(id); if (it == jobs.end()) return DA_INVALID_HANDLE;
            j = it->second; if (j->state != DA_PENDING) return DA_BUSY; j->state = DA_RUNNING;
        }
        try {
            auto e = execute(*j,id);
            Json metrics = Json::object(), events = Json::array(); std::uint64_t dropped = 0;
            if (e.doc.contains("stages")) {
                for (const auto* stage : {"generation","routing","allocation"})
                    if (e.doc["stages"].contains(stage)) extract(e.doc["stages"][stage],metrics,events,dropped);
            } else extract(e.doc,metrics,events,dropped);
            auto text = e.doc.dump(2)+"\n"; auto metric_text = metrics.dump();
            if (text.size() > max_report_bytes) throw std::bad_alloc();
            if (e.snapshot) e.snapshot->report = text;
            std::lock_guard<std::mutex> lock(registry);
            // Cancellation and successful publication have one linearization point.
            if (j->cancelled && e.status.ok()) {
                e.status = cancelled_status(); e.snapshot.reset();
                text = report::error_json(e.status,"export").dump(2)+"\n";
            }
            j->report = std::move(text); j->metrics = std::move(metric_text);
            j->events = std::move(events); j->dropped = dropped;
            j->outcome = outcome_code(e.status.outcome);
            if (e.status.ok() && e.snapshot) j->context->last = std::move(e.snapshot);
            j->state = DA_FINISHED; j->stage = 6; return DA_OK;
        } catch (...) {
            const auto status = [&]() { try { throw; } catch (const std::bad_alloc&) { return DA_RESOURCE_FAILURE; } catch (...) { return DA_INTERNAL_ERROR; } }();
            std::lock_guard<std::mutex> lock(registry);
            j->report.clear(); j->outcome = status == DA_RESOURCE_FAILURE ? 6u : 9u;
            j->state = DA_FINISHED; j->stage = 6; return status;
        }
    });
}
da_status DA_CALL da_job_cancel(da_job id) {
    return guarded([&]() -> da_status {
        std::lock_guard<std::mutex> lock(registry);
        auto it = jobs.find(id); if (it == jobs.end()) return DA_INVALID_HANDLE;
        if (it->second->state != DA_FINISHED) it->second->cancelled = true;
        return DA_OK;
    });
}
da_status DA_CALL da_job_poll(da_job id, uint32_t* state, uint32_t* stage, uint32_t* outcome) {
    return guarded([&]() -> da_status {
        if (!state || !stage || !outcome) return DA_INVALID_ARGUMENT;
        std::lock_guard<std::mutex> lock(registry);
        auto it = jobs.find(id); if (it == jobs.end()) return DA_INVALID_HANDLE;
        *state = it->second->state; *stage = it->second->stage; *outcome = it->second->outcome; return DA_OK;
    });
}
da_status DA_CALL da_job_read(da_job id, uint32_t kind, uint8_t* buffer, uint32_t capacity, uint32_t* required) {
    return guarded([&]() -> da_status {
        if (kind != DA_REPORT && kind != DA_METRICS) return DA_INVALID_ARGUMENT;
        std::lock_guard<std::mutex> lock(registry);
        auto it = jobs.find(id); if (it == jobs.end()) return DA_INVALID_HANDLE;
        const auto& j = *it->second; if (j.state != DA_FINISHED) return DA_NOT_READY;
        if (j.report.empty()) {
            const std::string_view fallback = j.outcome == 6 ?
                "{\"outcome\":\"resource_failure\",\"optimal\":false,\"result\":null,\"diagnostics\":[{\"code\":\"api_resource\",\"path\":\"/job\",\"message\":\"Native resources exhausted.\",\"recovery\":\"Reduce workload and retry.\"}]}" :
                "{\"outcome\":\"internal_error\",\"optimal\":false,\"result\":null,\"diagnostics\":[{\"code\":\"api_exception\",\"path\":\"/job\",\"message\":\"Unexpected native exception.\",\"recovery\":\"Create a new context and retry.\"}]}";
            return copy(kind == DA_REPORT ? fallback : "{}",buffer,capacity,required);
        }
        return copy(kind == DA_REPORT ? j.report : j.metrics,buffer,capacity,required);
    });
}
da_status DA_CALL da_job_trace(da_job id, uint32_t cursor, uint32_t count, uint8_t* buffer, uint32_t capacity, uint32_t* required) {
    return guarded([&]() -> da_status {
        if (!count || count > DA_MAX_TRACE_BATCH) return DA_INVALID_ARGUMENT;
        std::lock_guard<std::mutex> lock(registry);
        auto it = jobs.find(id); if (it == jobs.end()) return DA_INVALID_HANDLE;
        const auto& j = *it->second; if (j.state != DA_FINISHED) return DA_NOT_READY;
        if (cursor > j.events.size()) return DA_INVALID_ARGUMENT;
        Json batch = Json::array(); const auto end = std::min(j.events.size(),static_cast<std::size_t>(cursor)+count);
        for (std::size_t i = cursor; i < end; ++i) batch.push_back(j.events[i]);
        const Json doc = {{"job",id},{"events",batch},{"next_cursor",end},{"total",j.events.size()},
            {"dropped_events",j.dropped},{"truncated",j.dropped != 0}};
        return copy(doc.dump(),buffer,capacity,required);
    });
}
da_status DA_CALL da_context_read(da_context id, uint8_t* buffer, uint32_t capacity, uint32_t* required) {
    return guarded([&]() -> da_status {
        std::lock_guard<std::mutex> lock(registry);
        const auto it = contexts.find(id); if (it == contexts.end()) return DA_INVALID_HANDLE;
        if (!it->second->last) return DA_NOT_READY;
        return copy(it->second->last->report,buffer,capacity,required);
    });
}
da_status DA_CALL da_job_release(da_job id) {
    return guarded([&]() -> da_status {
        std::lock_guard<std::mutex> lock(registry);
        auto it = jobs.find(id); if (it == jobs.end()) return DA_INVALID_HANDLE;
        if (it->second->state == DA_RUNNING) return DA_BUSY;
        it->second->context->active = 0; jobs.erase(it); return DA_OK;
    });
}
da_status DA_CALL da_context_step(da_context id, da_job snapshot_job, int32_t x, int32_t y,
    int32_t dx, int32_t dy, int32_t* out_x, int32_t* out_y) {
    return guarded([&]() -> da_status {
        if (!out_x || !out_y) return DA_INVALID_ARGUMENT;
        std::shared_ptr<const Snapshot> last;
        {
            std::lock_guard<std::mutex> lock(registry);
            const auto it = contexts.find(id); if (it == contexts.end()) return DA_INVALID_HANDLE;
            last = it->second->last;
        }
        if (!last || !last->geometry) return DA_NOT_READY;
        if (last->job != snapshot_job) return DA_STALE_RESULT;
        auto result = da::step_player(last->source.settings,*last->geometry,{x,y},dx,dy);
        if (!result.ok()) return DA_INVALID_ARGUMENT;
        *out_x = result.value->x; *out_y = result.value->y; return DA_OK;
    });
}

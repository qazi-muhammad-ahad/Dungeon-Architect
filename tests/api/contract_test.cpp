#include "dungeon_architect_c.h"
#include "dungeon_architect/project_io.h"
#include "dungeon_architect/simulation.h"
#include "dungeon_architect/geometry.h"
#include "dungeon_architect/generation.h"
#include "../test_support.h"
#include <nlohmann/json.hpp>
#include <fstream>
#include <thread>
#include <chrono>
#include <limits>
#include <algorithm>
using Json = nlohmann::json;
namespace da = dungeon_architect;
std::string read_file(const char* path) {
    std::ifstream file(path,std::ios::binary);
    CHECK(file.good()); return {std::istreambuf_iterator<char>(file),{}};
}
da_job create(da_context c, const std::string& s, uint32_t op = DA_RUN) {
    da_job job = 0;
    CHECK(da_job_create(c,op,reinterpret_cast<const uint8_t*>(s.data()),static_cast<uint32_t>(s.size()),16,0,&job) == DA_OK);
    CHECK(job != 0); return job;
}
template<class Fn> std::string read(Fn fn) {
    uint32_t size = 0;
    CHECK(fn(nullptr,0,&size) == DA_BUFFER_TOO_SMALL); CHECK(size > 0);
    std::string result(size,'?');
    CHECK(fn(reinterpret_cast<uint8_t*>(result.data()),size-1,&size) == DA_BUFFER_TOO_SMALL);
    CHECK(result[0] == '?');
    CHECK(fn(reinterpret_cast<uint8_t*>(result.data()),size,&size) == DA_OK); return result;
}
std::string report(da_job job) { return read([&](uint8_t* p,uint32_t c,uint32_t* n){return da_job_read(job,DA_REPORT,p,c,n);}); }
int main(int argc, char** argv) {
    try {
        CHECK(argc == 3);
        const auto source = read_file(argv[1]); const auto standard = read_file(argv[2]);
        da_context c = 55; da_job j = 0; uint32_t n = 0, state = 0, stage = 0, outcome = 0;
        CHECK(da_context_create(1,1,nullptr) == DA_INVALID_ARGUMENT);
        CHECK(da_context_create(2,1,&c) == DA_VERSION_MISMATCH); CHECK(c == 0);
        CHECK(da_context_create(1,2,&c) == DA_VERSION_MISMATCH);
        CHECK(da_context_release(0) == DA_INVALID_HANDLE);
        CHECK(da_job_execute(123456) == DA_INVALID_HANDLE);
        CHECK(da_job_release(0) == DA_INVALID_HANDLE);
        CHECK(da_job_cancel(0) == DA_INVALID_HANDLE);
        CHECK(da_context_create(1,1,&c) == DA_OK);
        CHECK(da_context_read(c,nullptr,0,&n) == DA_NOT_READY);
        CHECK(da_job_create(c,DA_RUN,nullptr,1,0,0,&j) == DA_INVALID_ARGUMENT);
        const auto* ptr = reinterpret_cast<const uint8_t*>(source.data());
        CHECK(da_job_create(c,DA_RUN,ptr,DA_MAX_INPUT_BYTES+1,0,0,&j) == DA_INVALID_ARGUMENT);
        CHECK(da_job_create(c,DA_RUN,ptr,1,4097,0,&j) == DA_INVALID_ARGUMENT);
        CHECK(da_job_create(c,0,ptr,1,0,0,&j) == DA_INVALID_ARGUMENT);
        CHECK(da_job_create(c,DA_RUN,ptr,1,0,2,&j) == DA_INVALID_ARGUMENT);
        j = create(c,source);
        CHECK(da_context_release(c) == DA_BUSY);
        CHECK(da_job_create(c,DA_RUN,ptr,1,0,0,&n) == DA_BUSY);
        CHECK(da_job_read(j,DA_REPORT,nullptr,0,&n) == DA_NOT_READY);
        CHECK(da_job_poll(j,nullptr,&stage,&outcome) == DA_INVALID_ARGUMENT);
        CHECK(da_job_poll(j,&state,&stage,&outcome) == DA_OK && state == DA_PENDING);
        CHECK(da_job_execute(j) == DA_OK);
        CHECK(da_job_execute(j) == DA_BUSY);
        CHECK(da_job_poll(j,&state,&stage,&outcome) == DA_OK && state == DA_FINISHED && stage == 6 && outcome == 0);
        const auto baseline = report(j); const auto doc = Json::parse(baseline);
        CHECK(doc["optimal"] == true);
        CHECK(da_job_read(j,DA_REPORT,nullptr,1,&n) == DA_INVALID_ARGUMENT);
        CHECK(da_job_read(j,DA_REPORT,nullptr,0,nullptr) == DA_INVALID_ARGUMENT);
        CHECK(da_job_read(j,42,nullptr,0,&n) == DA_INVALID_ARGUMENT);
        auto metrics = Json::parse(read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_job_read(j,DA_METRICS,p,cap,len);}));
        CHECK(metrics.contains("allocation")); CHECK(metrics.contains("routing"));
        uint32_t cursor = 0; std::size_t count = 0;
        do {
            auto batch = Json::parse(read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_job_trace(j,cursor,7,p,cap,len);}));
            CHECK(batch["events"].size() <= 7);
            CHECK(batch["schema_version"] == 1);
            CHECK(batch["run_id"] == j);
            for (const auto& event : batch["events"]) {
                CHECK(event["sequence"] == count++);
                CHECK(event["schema_version"] == 1 && event["run_id"] == j);
                CHECK(event["input_revision"].is_string());
                CHECK(event["input_revision"].get<std::string>().find("fnv1a32-") == 0);
                CHECK(event["input_revision"] == batch["input_revision"]);
                CHECK(event["stage"] == "generation" || event["stage"] == "routing" || event["stage"] == "allocation");
                CHECK(event["affected_ids"].is_array());
                CHECK(event["event"].contains("kind"));
                for (const auto& id : event["affected_ids"]) CHECK(id.is_string() && !id.get<std::string>().empty());
            }
            cursor = batch["next_cursor"];
            if (cursor == batch["total"]) break;
        } while (true);
        CHECK(count > 0 && count <= 48);
        CHECK(metrics.contains("generation") && metrics.contains("routing") && !metrics.contains("walkable_geometry"));
        for (const auto* name : {"generation","routing","allocation"}) {
            CHECK(metrics[name]["timing_domain"] == "steady_clock_wall_including_validation_and_cooperative_yields");
            CHECK(metrics[name]["timings_us"].is_object());
            for (const auto& value : metrics[name]["timings_us"]) CHECK(value.is_number() && value.get<double>() >= 0);
            CHECK(metrics[name]["trace_us"].is_number() && metrics[name]["trace_us"].get<double>() >= 0);
        }
        CHECK(da_job_trace(j,0,129,nullptr,0,&n) == DA_INVALID_ARGUMENT);
        CHECK(da_job_trace(j,99999,1,nullptr,0,&n) == DA_INVALID_ARGUMENT);
        const auto& marker = doc["result"]["geometry"]["entrance_marker"];
        int32_t x = marker["x"], y = marker["y"], ox = -1, oy = -1;
        CHECK(da_context_step(c,j,x,y,2,0,&ox,&oy) == DA_INVALID_ARGUMENT);
        CHECK(da_context_step(c,j+1,x,y,1,0,&ox,&oy) == DA_STALE_RESULT);
        CHECK(da_context_step(c,j,x,y,1,0,&ox,&oy) == DA_OK);
        const auto& floor = doc["result"]["geometry"]["layers"]["floor"];
        CHECK(floor[static_cast<std::size_t>(oy)].get<std::string>()[static_cast<std::size_t>(ox)] == '1');
        const auto snapshot_job = j;
        CHECK(da_job_release(j) == DA_OK); CHECK(da_job_release(j) == DA_INVALID_HANDLE);
        CHECK(da_context_step(c,snapshot_job,x,y,0,-1,&ox,&oy) == DA_OK);
        for (const auto& invalid : {std::string("{"),std::string("{}"),std::string("\xff"),source+std::string(1,'\0')}) {
            j = create(c,invalid); CHECK(da_job_execute(j) == DA_OK);
            CHECK(Json::parse(report(j))["outcome"] != "success"); CHECK(da_job_release(j) == DA_OK);
        }
        auto wrong_schema = Json::parse(source); wrong_schema["schema_version"] = 99;
        j = create(c,wrong_schema.dump()); CHECK(da_job_execute(j) == DA_OK);
        CHECK(Json::parse(report(j))["outcome"] == "unsupported_schema"); CHECK(da_job_release(j) == DA_OK);
        j = create(c,standard); CHECK(da_job_cancel(j) == DA_OK); CHECK(da_job_cancel(j) == DA_OK);
        CHECK(da_job_execute(j) == DA_OK); CHECK(Json::parse(report(j))["outcome"] == "cancelled"); CHECK(da_job_release(j) == DA_OK);
        // Actual concurrent cancellation, poll and lifecycle rejection while running.
        j = create(c,standard);
        da_status execution = DA_INTERNAL_ERROR;
        std::thread worker([&]{ execution = da_job_execute(j); });
        const auto deadline = std::chrono::steady_clock::now()+std::chrono::seconds(10);
        do {
            da_job_poll(j,&state,&stage,&outcome);
            if (state == DA_RUNNING || state == DA_FINISHED) break;
            std::this_thread::yield();
        } while (std::chrono::steady_clock::now() < deadline);
        const auto release_running = da_job_release(j);
        da_job_cancel(j); worker.join();
        CHECK(state == DA_RUNNING); CHECK(release_running == DA_BUSY); CHECK(execution == DA_OK);
        CHECK(Json::parse(report(j))["outcome"] == "cancelled"); CHECK(da_job_release(j) == DA_OK);
        CHECK(read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_context_read(c,p,cap,len);}) == baseline);
        j = create(c,source,DA_VALIDATE); CHECK(da_job_execute(j) == DA_OK); CHECK(da_job_release(j) == DA_OK);
        j = create(c,source,DA_NORMALIZE); CHECK(da_job_execute(j) == DA_OK);
        auto normalized = Json::parse(report(j))["project_json"].get<std::string>();
        auto parsed_source = da::project_io::parse(source);
        CHECK(normalized == *da::project_io::serialize(*parsed_source.value).value);
        CHECK(da_job_release(j) == DA_OK);
        j = create(c,"{}",DA_NEW_PROJECT); CHECK(da_job_execute(j) == DA_OK);
        auto fresh = da::project_io::parse(Json::parse(report(j))["project_json"].get<std::string>());
        CHECK(fresh.ok() && fresh.value->settings.columns == 150 && fresh.value->packs.empty());
        CHECK(da_job_release(j) == DA_OK);
        // Editor transactions reuse core mask rules and never replace a run snapshot.
        const auto edit = [&](const da::Project& p,const Json& command) {
            const auto encoded=da::project_io::serialize(p); CHECK(encoded.ok());
            const auto job=create(c,Json{{"project_json",*encoded.value},{"command",command}}.dump(),DA_EDIT);
            CHECK(da_job_execute(job)==DA_OK); const auto result=Json::parse(report(job));
            CHECK(da_job_release(job)==DA_OK); return result;
        };
        auto canvas=da::make_default_project(); canvas.settings.columns=16;canvas.settings.rows=16;canvas.settings.room_count=2;canvas.settings.min_room_width=4;canvas.settings.min_room_height=4;canvas.settings.max_room_width=8;canvas.settings.max_room_height=8;canvas.allowed_mask.assign(256,1);
        for(const auto& name:{"rectangle","ellipse","l_shape"}) {
            const auto edited=edit(canvas,{{"type","shape"},{"shape",name},{"mode","replace"},{"x",2},{"y",2},{"width",10},{"height",10}});
            CHECK(edited["outcome"]=="success");
            const auto parsed=da::project_io::parse(edited["project_json"].get<std::string>());CHECK(parsed.ok());
            const auto expected=da::make_mask(16,16,std::string(name)=="rectangle"?da::MaskPreset::rectangle:std::string(name)=="ellipse"?da::MaskPreset::ellipse:da::MaskPreset::l_shape,{2,2,10,10});
            CHECK(parsed.value->allowed_mask==*expected.value);
        }
        const auto cut=edit(canvas,{{"type","shape"},{"shape","rectangle"},{"mode","subtract"},{"x",1},{"y",1},{"width",2},{"height",2}});
        CHECK(cut["outcome"]=="success");
        auto cutProject=da::project_io::parse(cut["project_json"].get<std::string>());CHECK(cutProject.value->allowed_mask[17]==0);
        const auto filled=edit(*cutProject.value,{{"type","fill"},{"x",1},{"y",1},{"allowed",true}});
        CHECK(da::project_io::parse(filled["project_json"].get<std::string>()).value->allowed_mask==canvas.allowed_mask);
        CHECK(edit(canvas,{{"type","paint"},{"allowed",false},{"tiles",Json::array({{{"x",0},{"y",0}},{{"x",16},{"y",0}}})}})["outcome"]=="invalid_input");
        CHECK(edit(canvas,{{"type","resize"},{"columns",15},{"rows",16},{"allow_crop",false}})["outcome"]=="invalid_input");
        CHECK(edit(canvas,{{"type","resize"},{"columns",15},{"rows",16},{"allow_crop",true}})["outcome"]=="success");
        auto grown=edit(canvas,{{"type","resize"},{"columns",20},{"rows",20},{"allow_crop",false}});
        const auto grownProject=da::project_io::parse(grown["project_json"].get<std::string>());
        CHECK(grownProject.ok()&&grownProject.value->allowed_mask[19]==0&&grownProject.value->allowed_mask[15]==1);
        da::Room fixed;fixed.id="fixed";fixed.name="Fixed";fixed.bounds={3,3,4,4};fixed.lock_position=true;canvas.rooms.push_back(fixed);
        auto fixedCommand=Json{{"type","fix_room"},{"fixed",true},{"room",{{"id","pinned"},{"name","Pinned"},{"bounds",{{"x",9},{"y",9},{"width",4},{"height",4}}}}}};
        auto pinned=edit(canvas,fixedCommand); CHECK(pinned["outcome"]=="success");
        auto pinnedProject=da::project_io::parse(pinned["project_json"].get<std::string>()); CHECK(pinnedProject.ok());
        CHECK(pinnedProject.value->rooms.back().lock_position && pinnedProject.value->rooms.back().lock_size);
        auto pinnedLayout=da::generate_rooms(*pinnedProject.value); CHECK(pinnedLayout.status.ok());
        CHECK(pinnedLayout.layout->rooms.size()==2);
        fixedCommand["room"]["bounds"]["x"]=8;
        CHECK(edit(*pinnedProject.value,fixedCommand)["outcome"]=="invalid_input");
        fixedCommand["fixed"]=false;
        auto released=edit(*pinnedProject.value,fixedCommand); CHECK(released["outcome"]=="success");
        auto releasedProject=da::project_io::parse(released["project_json"].get<std::string>());
        CHECK(!releasedProject.value->rooms.back().lock_position && !releasedProject.value->rooms.back().lock_size);
        CHECK(edit(canvas,{{"type","paint"},{"allowed",false},{"tiles",Json::array({{{"x",2},{"y",3}}})}})["outcome"]=="invalid_input");
        CHECK(edit(canvas,{{"type","resize"},{"columns",6},{"rows",16},{"allow_crop",true}})["outcome"]=="invalid_input");
        auto fixedAnalysis=edit(canvas,{{"type","paint"},{"allowed",true},{"tiles",Json::array()}});
        CHECK(fixedAnalysis["editor_analysis"]["reservations"][2].get<std::string>()[2]=='1');
        canvas.rooms.clear();canvas.allowed_mask.assign(256,0);canvas.allowed_mask[0]=1;canvas.allowed_mask[255]=1;
        auto sparse=edit(canvas,{{"type","paint"},{"allowed",true},{"tiles",Json::array()}});
        CHECK(sparse["editor_analysis"]["component_count"]==2);
        CHECK(sparse["editor_analysis"]["detached"][15].get<std::string>()[15]=='1');
        CHECK(sparse["editor_analysis"]["narrow"][0].get<std::string>()[0]=='1');
        canvas.settings.columns=512;canvas.settings.rows=512;canvas.allowed_mask.assign(512*512,1);
        const auto analysisStart=std::chrono::steady_clock::now();
        const auto largeEdit=edit(canvas,{{"type","paint"},{"allowed",false},{"tiles",Json::array({{{"x",511},{"y",511}}})}});
        CHECK(largeEdit["outcome"]=="success");
        std::cout<<"512x512 editor transaction + diagnostics: "<<std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-analysisStart).count()<<" ms\n";
        CHECK(read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_context_read(c,p,cap,len);}) == baseline);
        // Phase 11: explicit room transactions preserve locks, IDs and prior output.
        auto phase11 = *parsed_source.value;
        auto roomJson = Json::parse(source)["source"]["rooms"][0];
        roomJson["name"] = "Renamed entrance";
        auto renamed = edit(phase11, {{"type","upsert_room"},{"room",roomJson}});
        CHECK(renamed["outcome"] == "success");
        auto renamedSource = da::project_io::parse(renamed["project_json"].get<std::string>());
        CHECK(renamedSource.ok());
        CHECK(renamedSource.value->rooms[0].id == phase11.rooms[0].id);
        auto moved = roomJson; moved["bounds"]["x"] = 3;
        CHECK(edit(*renamedSource.value, {{"type","upsert_room"},{"room",moved}})["outcome"] == "invalid_input");
        moved["lock_position"] = false; moved["lock_size"] = false;
        CHECK(edit(*renamedSource.value, {{"type","upsert_room"},{"room",moved}})["outcome"] == "invalid_input");
        roomJson["lock_position"] = false; roomJson["lock_size"] = false;
        auto unlocked = edit(*renamedSource.value, {{"type","upsert_room"},{"room",roomJson}});
        CHECK(unlocked["outcome"] == "success");
        const auto unlockedSource = da::project_io::parse(unlocked["project_json"].get<std::string>());
        auto relocated = edit(*unlockedSource.value, {{"type","upsert_room"},{"room",moved}});
        CHECK(relocated["outcome"] == "success");
        auto removedRoom = edit(*unlockedSource.value, {{"type","remove_room"},{"id",roomJson["id"]}});
        CHECK(removedRoom["outcome"] == "success");
        CHECK(da::project_io::parse(removedRoom["project_json"].get<std::string>()).value->rooms.size() == 1);

        // Inventory copies remain separate records; inactive catalogue entries are persisted.
        auto packJson = Json::parse(source)["source"]["packs"][0];
        packJson["id"] = "archer-copy"; packJson["active"] = false;
        auto copied = edit(phase11, {{"type","upsert_pack"},{"pack",packJson}});
        CHECK(copied["outcome"] == "success");
        auto copiedSource = da::project_io::parse(copied["project_json"].get<std::string>());
        CHECK(copiedSource.ok() && copiedSource.value->packs.size() == phase11.packs.size()+1);
        CHECK(std::count_if(copiedSource.value->packs.begin(),copiedSource.value->packs.end(),[](const da::Pack& p){return p.active;}) == 4);
        packJson["slots"] = 0;
        CHECK(edit(*copiedSource.value, {{"type","upsert_pack"},{"pack",packJson}})["outcome"] == "invalid_input");
        auto removedPack = edit(*copiedSource.value, {{"type","remove_pack"},{"id","archer-copy"}});
        CHECK(removedPack["outcome"] == "success");
        CHECK(da::project_io::parse(removedPack["project_json"].get<std::string>()).value->packs.size() == phase11.packs.size());
        CHECK(read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_context_read(c,p,cap,len);}) == baseline);

        // Reallocation must actually reuse geometry, including its exact floor and routes.
        const auto reallocate = [&](const da::Project& p) {
            const auto encoded=da::project_io::serialize(p); CHECK(encoded.ok());
            const auto job=create(c,*encoded.value,DA_REALLOCATE);
            CHECK(da_job_execute(job)==DA_OK); const auto result=Json::parse(report(job));
            CHECK(da_job_release(job)==DA_OK); return result;
        };
        phase11.settings.threat_budget = 0;
        const auto zeroBudget = reallocate(phase11);
        CHECK(zeroBudget["outcome"] == "success" && zeroBudget["optimal"] == true);
        CHECK(zeroBudget["geometry_reused"] == true);
        CHECK(zeroBudget["stages"].size() == 1 && zeroBudget["stages"].contains("allocation"));
        CHECK(zeroBudget["result"]["geometry"]["layers"] == doc["result"]["geometry"]["layers"]);
        CHECK(zeroBudget["result"]["geometry"]["corridors"] == doc["result"]["geometry"]["corridors"]);
        CHECK(zeroBudget["result"]["layout"] == doc["result"]["layout"]);
        CHECK(zeroBudget["result"]["allocation"]["total_threat"] == 0);
        CHECK(zeroBudget["result"]["allocation"]["total_score"] == 0);
        phase11.settings.threat_budget = 3;
        phase11.packs[0].score = 1000;
        const auto rescored = reallocate(phase11);
        CHECK(rescored["outcome"] == "success");
        CHECK(rescored["result"]["allocation"]["total_score"].get<int>() >= 1000);
        CHECK(rescored["result"]["geometry"]["layers"] == doc["result"]["geometry"]["layers"]);
        auto geometryEdit = phase11; ++geometryEdit.settings.seed;
        CHECK(reallocate(geometryEdit)["outcome"] == "stale_result");
        geometryEdit = phase11; geometryEdit.allowed_mask[0] = 0;
        CHECK(reallocate(geometryEdit)["outcome"] == "stale_result");
        for(int i=0;i<11;++i) { auto copy=phase11.packs[0]; copy.id="inventory-copy-"+std::to_string(i); phase11.packs.push_back(copy); }
        CHECK(reallocate(phase11)["outcome"] == "unsupported_size");
        CHECK(Json::parse(read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_context_read(c,p,cap,len);})) == rescored);
        for(auto& p:phase11.packs) if(p.id.find("inventory-copy-")==0) p.active=false;
        const auto inactiveCatalogue = reallocate(phase11);
        CHECK(inactiveCatalogue["outcome"] == "success");
        CHECK(inactiveCatalogue["result"]["allocation"]["total_score"] == rescored["result"]["allocation"]["total_score"]);
        phase11.rooms[1].name = "Edited exit";
        phase11.rooms[1].tags.push_back("edited");
        phase11.rooms[1].capacity_override = 0;
        const auto metadataOnly = reallocate(phase11);
        CHECK(metadataOnly["outcome"] == "success");
        CHECK(metadataOnly["result"]["geometry"]["layers"] == doc["result"]["geometry"]["layers"]);
        CHECK(metadataOnly["result"]["geometry"]["corridors"] == doc["result"]["geometry"]["corridors"]);
        CHECK(metadataOnly["result"]["allocation"]["total_score"] == 0);
        bool foundEditedExit = false;
        for(const auto& r:metadataOnly["result"]["layout"]["rooms"]) if(r["id"] == phase11.rooms[1].id) {
            CHECK(r["name"] == "Edited exit"); CHECK(r["capacity_override"] == 0);
            CHECK(std::find(r["tags"].begin(),r["tags"].end(),"edited") != r["tags"].end());
            foundEditedExit = true;
        }
        CHECK(foundEditedExit);
        for(const auto& r:metadataOnly["result"]["geometry"]["rooms"]) if(r["id"] == phase11.rooms[1].id) {
            CHECK(r["capacity"] == 0);
            for(const auto& original:doc["result"]["geometry"]["rooms"]) if(original["id"] == r["id"])
                CHECK(r["spawn_positions"] == original["spawn_positions"]);
        }
        const auto metadataSource = da::project_io::serialize(phase11);
        j=create(c,*metadataSource.value,DA_REALLOCATE);
        CHECK(da_job_cancel(j) == DA_OK); CHECK(da_job_execute(j) == DA_OK);
        CHECK(Json::parse(report(j))["outcome"] == "cancelled"); CHECK(da_job_release(j) == DA_OK);
        CHECK(Json::parse(read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_context_read(c,p,cap,len);})) == metadataOnly);
        CHECK(reallocate(phase11)["outcome"] == "success");
        for(auto& p:phase11.packs) p.active=true;
        const auto catalogueSource=da::project_io::serialize(phase11); CHECK(catalogueSource.ok());
        j=create(c,*catalogueSource.value,DA_GENERATE_DUNGEON);
        CHECK(da_job_execute(j)==DA_OK);
        const auto geometryOnly=Json::parse(report(j)); CHECK(da_job_release(j)==DA_OK);
        CHECK(geometryOnly["outcome"]=="success" && geometryOnly["optimal"]==false);
        CHECK(geometryOnly["result"]["allocation"].is_null());
        CHECK(geometryOnly["result"]["geometry"]["connected_floor_verified"]==true);
        CHECK(reallocate(phase11)["outcome"]=="unsupported_size");
        for(auto& p:phase11.packs) if(p.id.find("inventory-copy-")==0) p.active=false;
        CHECK(reallocate(phase11)["outcome"]=="success");
        // A benchmark context may publish its own result without touching editor movement/export state.
        const auto retained = read([&](uint8_t* p,uint32_t cap,uint32_t* len){return da_context_read(c,p,cap,len);});
        da_context benchmark = 0; CHECK(da_context_create(1,1,&benchmark) == DA_OK);
        for (const uint32_t cap : {0U,1U,4096U}) {
            da_job measured = 0;
            CHECK(da_job_create(benchmark,DA_RUN,ptr,static_cast<uint32_t>(source.size()),cap,DA_DETAILED_TRACE,&measured) == DA_OK);
            CHECK(da_job_execute(measured) == DA_OK);
            const auto measuredDoc = Json::parse(report(measured));
            CHECK(measuredDoc["outcome"] == "success");
            CHECK(measuredDoc["result"] == doc["result"]);
            const auto batch = Json::parse(read([&](uint8_t* p,uint32_t size,uint32_t* len){return da_job_trace(measured,0,128,p,size,len);}));
            CHECK(batch["total"].get<std::size_t>() <= 4096);
            if (cap == 0) CHECK(batch["events"].empty() && batch["truncated"] == true);
            CHECK(da_job_release(measured) == DA_OK);
            CHECK(read([&](uint8_t* p,uint32_t size,uint32_t* len){return da_context_read(c,p,size,len);}) == retained);
        }
        CHECK(da_context_release(benchmark) == DA_OK);
        CHECK(da_context_release(c) == DA_OK); CHECK(da_context_release(c) == DA_INVALID_HANDLE);
        for (int i = 0; i < 40; ++i) {
            CHECK(da_context_create(1,1,&c) == DA_OK); j = create(c,source,DA_VALIDATE);
            CHECK(da_job_execute(j) == DA_OK); CHECK(da_job_release(j) == DA_OK); CHECK(da_context_release(c) == DA_OK);
        }
        std::vector<da_context> handles;
        for (int i = 0; i < 32; ++i) { CHECK(da_context_create(1,1,&c) == DA_OK); handles.push_back(c); }
        CHECK(da_context_create(1,1,&c) == DA_RESOURCE_FAILURE);
        for (auto h : handles) CHECK(da_context_release(h) == DA_OK);
        // Independent tiny floor fixture: walls, edge, diagonal, out-of-bounds.
        da::Settings s; s.columns = 3; s.rows = 3;
        da::GeometrySnapshot g; g.layers.floor = {0,0,0,1,1,0,0,1,0};
        CHECK(da::step_player(s,g,{1,1},1,0).value == da::Tile{1,1});
        CHECK(da::step_player(s,g,{1,1},0,1).value == da::Tile{1,2});
        CHECK(da::step_player(s,g,{0,1},-1,0).value == da::Tile{0,1});
        CHECK(!da::step_player(s,g,{1,1},1,1).ok());
        CHECK(!da::walkable(s,g,{std::numeric_limits<int32_t>::max(),0}));
        std::cout << checks << " ABI/lifecycle checks passed\n"; return 0;
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}


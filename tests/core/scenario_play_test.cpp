#include "dungeon_architect_c.h"
#include "../test_support.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <array>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <queue>
#include <set>
#include <tuple>
#include <vector>

using Json = nlohmann::json;
using Point = std::pair<int,int>;
const std::array<Point,4> directions{{{1,0},{0,1},{-1,0},{0,-1}}};
Point point(const Json& p) { return {p.at("x").get<int>(),p.at("y").get<int>()}; }
template<class Fn> std::string bytes(Fn fn) {
    uint32_t n=0; CHECK(fn(nullptr,0,&n)==DA_BUFFER_TOO_SMALL); CHECK(n>0);
    std::string out(n,'\0'); CHECK(fn(reinterpret_cast<uint8_t*>(out.data()),n,&n)==DA_OK); return out;
}
std::string retained(da_context c) { return bytes([&](uint8_t* p,uint32_t n,uint32_t* len){return da_context_read(c,p,n,len);}); }
struct Run { da_job job; Json doc; };
Run run(da_context c,const Json& input,uint32_t operation,bool cancel=false) {
    const auto raw=input.dump(); da_job job=0;
    CHECK(da_job_create(c,operation,reinterpret_cast<const uint8_t*>(raw.data()),static_cast<uint32_t>(raw.size()),0,0,&job)==DA_OK);
    if(cancel) CHECK(da_job_cancel(job)==DA_OK);
    CHECK(da_job_execute(job)==DA_OK);
    const auto rawReport=bytes([&](uint8_t* p,uint32_t n,uint32_t* len){return da_job_read(job,DA_REPORT,p,n,len);});
    CHECK(da_job_release(job)==DA_OK); return {job,Json::parse(rawReport)};
}
std::set<Point> flood(const Json& rows,Point start) {
    std::set<Point> reached; std::queue<Point> queue;
    const int h=static_cast<int>(rows.size()),w=static_cast<int>(rows.at(0).get<std::string>().size());
    const auto floor=[&](Point p){return p.first>=0&&p.second>=0&&p.first<w&&p.second<h&&rows.at(static_cast<std::size_t>(p.second)).get<std::string>().at(static_cast<std::size_t>(p.first))=='1';};
    if(floor(start)) { reached.insert(start); queue.push(start); }
    while(!queue.empty()) {
        const auto p=queue.front(); queue.pop();
        for(auto d:directions) { Point next{p.first+d.first,p.second+d.second}; if(floor(next)&&reached.insert(next).second) queue.push(next); }
    }
    return reached;
}
// Independent pack-to-room enumeration: deliberately no subset DP or native
// allocation helpers, and inputs come from baseline + tile BFS, not the result.
struct Optimum { int64_t score=0,threat=0,slots=0; std::vector<std::string> ids; };
Optimum oracle(const Json& baseline,const Json& request,const std::set<Point>& reach) {
    const auto& result=baseline.at("result"); const auto& packs=result.at("source_project").at("source").at("packs");
    const auto& rooms=result.at("layout").at("rooms"); const auto& placed=result.at("geometry").at("rooms");
    const int64_t budget=request.value("budget",result.at("source_project").at("source").at("settings").at("threat_budget").get<int64_t>());
    std::map<std::string,int64_t> capacities,used;
    for(const auto& r:placed) {
        const auto id=r.at("id").get<std::string>(); int64_t survivors=0;
        for(const auto& s:r.at("spawn_positions")) if(reach.count(point(s.at("tile")))) ++survivors;
        capacities[id]=std::min(r.at("capacity").get<int64_t>(),survivors);
        if(request.contains("capacities")&&request.at("capacities").contains(id)) capacities[id]=std::min(request.at("capacities").at(id).get<int64_t>(),survivors);
        if(!reach.count(point(r.at("hub")))) capacities[id]=0;
        if(request.contains("disabled_rooms")) for(const auto& disabled:request.at("disabled_rooms")) if(disabled==id) capacities[id]=0;
    }
    Optimum best; std::vector<std::string> selected;
    std::function<void(std::size_t,int64_t,int64_t,int64_t)> visit;
    visit=[&](std::size_t i,int64_t score,int64_t threat,int64_t slots) {
        if(threat>budget) return;
        if(i==packs.size()) {
            auto ids=selected; std::sort(ids.begin(),ids.end());
            if(score>best.score||(score==best.score&&std::tie(threat,slots,ids)<std::tie(best.threat,best.slots,best.ids))) best={score,threat,slots,ids};
            return;
        }
        visit(i+1,score,threat,slots); const auto& p=packs.at(i); if(!p.at("active").get<bool>()) return;
        for(const auto& r:rooms) {
            const auto id=r.at("id").get<std::string>(); const auto demand=p.at("slots").get<int64_t>();
            if(r.at("role")=="entrance"||used[id]+demand>capacities[id]) continue;
            if(r.at("bounds").at("width").get<int>()<p.at("min_room_width").get<int>()||r.at("bounds").at("height").get<int>()<p.at("min_room_height").get<int>()) continue;
            if(!p.at("allowed_roles").empty()&&std::find(p.at("allowed_roles").begin(),p.at("allowed_roles").end(),r.at("role"))==p.at("allowed_roles").end()) continue;
            bool compatible=true;
            for(const auto& tag:p.at("required_tags")) if(std::find(r.at("tags").begin(),r.at("tags").end(),tag)==r.at("tags").end()) compatible=false;
            if(!compatible) continue;
            used[id]+=demand; selected.push_back(p.at("id").get<std::string>());
            visit(i+1,score+p.at("score").get<int64_t>(),threat+p.at("threat").get<int64_t>(),slots+demand);
            selected.pop_back(); used[id]-=demand;
        }
    };
    visit(0,0,0,0); return best;
}
void verify(da_context context,const Run& actual,const Json& baseline,const Json& request) {
    CHECK(actual.doc.at("outcome")=="success"); CHECK(actual.doc.at("optimal")==true);
    const auto& before=baseline.at("result"); const auto& result=actual.doc.at("result");
    CHECK(result.at("source_project")==before.at("source_project"));
    CHECK(result.at("layout")==before.at("layout"));
    auto expectedFloor=before.at("geometry").at("layers").at("floor");
    for(const auto& p:request.value("blocked_tiles",Json::array())) {
        const auto x=p.at(0).get<int>(),y=p.at(1).get<int>(); auto row=expectedFloor.at(static_cast<std::size_t>(y)).get<std::string>(); row.at(static_cast<std::size_t>(x))='0'; expectedFloor.at(static_cast<std::size_t>(y))=row;
    }
    const auto& geometry=result.at("geometry"); CHECK(geometry.at("layers").at("floor")==expectedFloor);
    const auto reach=flood(expectedFloor,point(geometry.at("entrance_marker")));
    std::size_t floorCount=0; for(const auto& row:expectedFloor) { const auto cells=row.get<std::string>(); floorCount+=static_cast<std::size_t>(std::count(cells.begin(),cells.end(),'1')); }
    CHECK(geometry.at("connected_floor_verified").get<bool>()==(reach.size()==floorCount));
    CHECK(actual.doc.at("scenario").at("exit_reachable").get<bool>()==(reach.count(point(geometry.at("exit_marker")))!=0));
    std::vector<std::string> disconnected; int reachable=0;
    for(const auto& room:geometry.at("rooms")) {
        const bool connected=reach.count(point(room.at("hub")))!=0;
        CHECK(room.at("reachable").get<bool>()==connected);
        if(connected) ++reachable; else disconnected.push_back(room.at("id").get<std::string>());
        for(const auto& spawn:room.at("spawn_positions")) CHECK(reach.count(point(spawn.at("tile")))!=0);
    }
    CHECK(actual.doc.at("scenario").at("reachable_rooms")==reachable);
    auto reported=actual.doc.at("scenario").at("disconnected_rooms").get<std::vector<std::string>>();
    std::sort(reported.begin(),reported.end()); std::sort(disconnected.begin(),disconnected.end()); CHECK(reported==disconnected);
    const auto expected=oracle(baseline,request,reach); const auto& allocation=result.at("allocation");
    CHECK(allocation.at("total_score")==expected.score); CHECK(allocation.at("total_threat")==expected.threat); CHECK(allocation.at("total_slots")==expected.slots);
    std::vector<std::string> selected; std::set<Point> occupied;
    for(const auto& assignment:allocation.at("assignments")) selected.push_back(assignment.at("pack_id").get<std::string>());
    std::sort(selected.begin(),selected.end()); CHECK(selected==expected.ids);
    for(const auto& actor:allocation.at("actors")) { CHECK(reach.count(point(actor.at("tile")))!=0); CHECK(occupied.insert(point(actor.at("tile"))).second); }
    // Check every floor-origin cardinal transition, including both door sides,
    // room interiors, actors, blocked cuts and outer boundaries.
    for(int y=0;y<static_cast<int>(expectedFloor.size());++y) for(int x=0;x<static_cast<int>(expectedFloor.at(static_cast<std::size_t>(y)).get<std::string>().size());++x) {
        if(expectedFloor.at(static_cast<std::size_t>(y)).get<std::string>().at(static_cast<std::size_t>(x))!='1') continue;
        for(const auto d:directions) {
            int32_t ox=-1,oy=-1; CHECK(da_context_step(context,actual.job,x,y,d.first,d.second,&ox,&oy)==DA_OK);
            const int nx=x+d.first,ny=y+d.second;
            const bool can=ny>=0&&ny<static_cast<int>(expectedFloor.size())&&nx>=0&&nx<static_cast<int>(expectedFloor.at(static_cast<std::size_t>(y)).get<std::string>().size())&&expectedFloor.at(static_cast<std::size_t>(ny)).get<std::string>().at(static_cast<std::size_t>(nx))=='1';
            CHECK(ox==(can?nx:x)&&oy==(can?ny:y));
        }
    }
}
int main(int argc,char** argv) {
    try {
        CHECK(argc==3); std::ifstream f(argv[1]); CHECK(f.good()); Json source; f>>source;
        da_context context=0; CHECK(da_context_create(1,1,&context)==DA_OK);
        const auto baseline=run(context,source,DA_RUN); CHECK(baseline.doc.at("outcome")=="success");
        const auto saved=retained(context); const auto entrance=point(baseline.doc.at("result").at("geometry").at("entrance_marker"));
        const auto scenario=[&](Json request) {
            request["baseline_job"]=baseline.job;
            auto actual=run(context,request,DA_SCENARIO); verify(context,actual,baseline.doc,request);
            CHECK(retained(context)==saved); int32_t ox=0,oy=0;
            CHECK(da_context_step(context,baseline.job,entrance.first,entrance.second,1,0,&ox,&oy)==DA_OK);
            return actual;
        };
        const auto empty=scenario(Json::object());
        CHECK(empty.doc.at("result").at("allocation").at("assignments")==baseline.doc.at("result").at("allocation").at("assignments"));
        // A one-tile hole in a width-two route still permits the other lane.
        const auto& geometry=baseline.doc.at("result").at("geometry");
        const auto& door=geometry.at("doors").at(0);
        const auto first=point(door.at("tiles").at(0));
        scenario({{"blocked_tiles",Json::array({Json::array({first.first,first.second})})}});
        Json doorCut=Json::array(); for(const auto& p:door.at("tiles")) { const auto t=point(p); doorCut.push_back({t.first,t.second}); }
        const auto sealed=scenario({{"blocked_tiles",doorCut}}); CHECK(sealed.doc.at("scenario").at("exit_reachable")==false);
        CHECK(sealed.doc.at("result").at("allocation").at("total_score")==0);
        scenario({{"disabled_rooms",Json::array({"exit"})}});
        scenario({{"capacities",{{"exit",0}}}});
        scenario({{"capacities",{{"exit",1}}},{"budget",1}});
        scenario({{"budget",0}});
        // Isolate a surviving corner tile, even if every room hub and exit
        // remains reachable: the whole-floor connectivity flag must be honest.
        const auto baselineFloor=geometry.at("layers").at("floor"); bool isolated=false;
        for(int y=0;y<static_cast<int>(baselineFloor.size())&&!isolated;++y) for(int x=0;x<static_cast<int>(baselineFloor.at(static_cast<std::size_t>(y)).get<std::string>().size())&&!isolated;++x) {
            if(baselineFloor.at(static_cast<std::size_t>(y)).get<std::string>().at(static_cast<std::size_t>(x))!='1'||Point{x,y}==entrance||Point{x,y}==point(geometry.at("exit_marker"))) continue;
            Json cut=Json::array(); bool safe=true;
            for(const auto d:directions) {
                const Point next{x+d.first,y+d.second};
                if(next.first<0||next.second<0||next.second>=static_cast<int>(baselineFloor.size())||next.first>=static_cast<int>(baselineFloor.at(0).get<std::string>().size())) continue;
                if(baselineFloor.at(static_cast<std::size_t>(next.second)).get<std::string>().at(static_cast<std::size_t>(next.first))=='1') {
                    if(next==entrance) safe=false;
                    cut.push_back({next.first,next.second});
                }
            }
            if(!safe||cut.empty()) continue;
            auto trial=baselineFloor;
            for(const auto& t:cut) { auto row=trial.at(t.at(1).get<std::size_t>()).get<std::string>(); row.at(t.at(0).get<std::size_t>())='0'; trial.at(t.at(1).get<std::size_t>())=row; }
            const auto reached=flood(trial,entrance);
            if(reached.count({x,y})!=0||reached.count(point(geometry.at("exit_marker")))==0) continue;
            bool hubs=true; for(const auto& r:geometry.at("rooms")) if(!reached.count(point(r.at("hub")))) hubs=false;
            if(!hubs) continue;
            const auto orphan=scenario({{"blocked_tiles",cut}}); CHECK(orphan.doc.at("result").at("geometry").at("connected_floor_verified")==false); isolated=true;
        }
        CHECK(isolated);
        const auto reset=scenario(Json::object()); CHECK(reset.doc.at("result").at("geometry").at("layers")==geometry.at("layers"));
        for(const auto& bad:std::vector<Json>{{{"baseline_job",baseline.job+1000}},{{"baseline_job",baseline.job},{"blocked_tiles",{{-1,0}}}},{{"baseline_job",baseline.job},{"disabled_rooms",{"missing"}}},{{"baseline_job",baseline.job},{"capacities",{{"exit",-1}}}},{{"baseline_job",baseline.job},{"budget",-1}}}) {
            CHECK(run(context,bad,DA_SCENARIO).doc.at("outcome")!="success"); CHECK(retained(context)==saved);
        }
        CHECK(run(context,{{"baseline_job",baseline.job}},DA_SCENARIO,true).doc.at("outcome")=="cancelled"); CHECK(retained(context)==saved);
        int32_t ox=0,oy=0;
        CHECK(da_context_step(context,baseline.job,entrance.first,entrance.second,2,0,&ox,&oy)==DA_INVALID_ARGUMENT);
        CHECK(da_context_step(context,baseline.job,entrance.first,entrance.second,1,1,&ox,&oy)==DA_INVALID_ARGUMENT);
        CHECK(da_context_step(context,baseline.job,-1,0,1,0,&ox,&oy)==DA_INVALID_ARGUMENT);
        const auto replacement=run(context,source,DA_RUN); CHECK(replacement.doc.at("outcome")=="success");
        CHECK(da_context_step(context,baseline.job,entrance.first,entrance.second,1,0,&ox,&oy)==DA_STALE_RESULT);
        CHECK(da_context_step(context,reset.job,entrance.first,entrance.second,1,0,&ox,&oy)==DA_STALE_RESULT);
        CHECK(da_context_release(context)==DA_OK);
        // A larger independently generated fixture has overlapping corridor
        // footprints. Closing a shared tile must affect every route using it.
        std::ifstream sharedFile(argv[2]); CHECK(sharedFile.good()); Json sharedSource; sharedFile>>sharedSource;
        while(sharedSource["source"]["packs"].size()>4) sharedSource["source"]["packs"].erase(sharedSource["source"]["packs"].end()-1);
        CHECK(da_context_create(1,1,&context)==DA_OK);
        const auto shared=run(context,sharedSource,DA_RUN); CHECK(shared.doc.at("outcome")=="success");
        const auto sharedSaved=retained(context); const auto& sharedGeometry=shared.doc.at("result").at("geometry");
        const int width=shared.doc.at("result").at("source_project").at("source").at("settings").at("corridor_width");
        std::map<Point,std::set<std::string>> owners;
        for(const auto& corridor:sharedGeometry.at("corridors")) for(const auto& tile:corridor.at("path")) {
            const auto p=point(tile);
            for(int dy=0;dy<width;++dy) for(int dx=0;dx<width;++dx) owners[{p.first+dx,p.second+dy}].insert(corridor.at("id").get<std::string>());
        }
        Json crossing=Json::array();
        for(const auto& [tile,routes]:owners) if(routes.size()>1&&tile!=point(sharedGeometry.at("entrance_marker"))) crossing.push_back({tile.first,tile.second});
        CHECK(!crossing.empty());
        Json sharedRequest={{"baseline_job",shared.job},{"blocked_tiles",crossing}};
        verify(context,run(context,sharedRequest,DA_SCENARIO),shared.doc,sharedRequest); CHECK(retained(context)==sharedSaved);
        Json sharedReset={{"baseline_job",shared.job}};
        verify(context,run(context,sharedReset,DA_SCENARIO),shared.doc,sharedReset); CHECK(retained(context)==sharedSaved);
        CHECK(da_context_release(context)==DA_OK);
        std::cout<<checks<<" independent scenario/oracle/collision checks passed\n"; return 0;
    } catch(const std::exception& e) { std::cerr<<e.what()<<'\n'; return 1; }
}

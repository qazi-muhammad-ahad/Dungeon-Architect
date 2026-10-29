#include "dungeon_architect_c.h"
#include "../test_support.h"
#include <nlohmann/json.hpp>
#include <fstream>
#include <iostream>
#include <random>
#include <set>
using Json = nlohmann::json;
template<class F> std::string bytes(F fn) {
    uint32_t n=0; CHECK(fn(nullptr,0,&n)==DA_BUFFER_TOO_SMALL);
    std::string out(n,'\0'); CHECK(fn(reinterpret_cast<uint8_t*>(out.data()),n,&n)==DA_OK); return out;
}
Json run(da_context c,const std::string& raw,uint32_t operation=DA_RUN,bool cancel=false) {
    da_job job=0; CHECK(da_job_create(c,operation,reinterpret_cast<const uint8_t*>(raw.data()),static_cast<uint32_t>(raw.size()),0,0,&job)==DA_OK);
    if(cancel) CHECK(da_job_cancel(job)==DA_OK);
    CHECK(da_job_execute(job)==DA_OK);
    auto report=Json::parse(bytes([&](uint8_t* p,uint32_t n,uint32_t* len){return da_job_read(job,DA_REPORT,p,n,len);}));
    CHECK(da_job_release(job)==DA_OK); CHECK(da_job_cancel(job)==DA_INVALID_HANDLE);
    return report;
}
int main(int argc,char** argv) {
    try {
        CHECK(argc==2); std::ifstream file(argv[1]); CHECK(file.good()); Json source; file>>source;
        std::mt19937 random(1609); std::set<da_context> released;
        for(int cycle=0;cycle<24;++cycle) {
            da_context c=0; CHECK(da_context_create(1,1,&c)==DA_OK); CHECK(!released.count(c));
            auto input=source; input["source"]["settings"]["seed"]=random();
            input["source"]["settings"]["threat_budget"]=random()%8;
            for(auto& pack:input["source"]["packs"]) { pack["score"]=random()%30; pack["threat"]=random()%6; }
            const auto raw=input.dump(); const auto baseline=run(c,raw); CHECK(baseline.at("outcome")=="success"); CHECK(baseline.at("optimal")==true);
            const auto retained=bytes([&](uint8_t* p,uint32_t n,uint32_t* len){return da_context_read(c,p,n,len);});
            // Invalid structured documents and random byte strings must never
            // replace the last usable authoritative snapshot.
            for(int mutation=0;mutation<12;++mutation) {
                auto invalid=input;
                switch(mutation) {
                    case 0: invalid["schema_version"]=999; break;
                    case 1: invalid["source"]["settings"]["columns"]=-1; break;
                    case 2: invalid["source"]["settings"]["rows"]=1e100; break;
                    case 3: invalid["source"]["allowed_mask"]=Json::array({"x"}); break;
                    case 4: invalid["source"]["rooms"]=false; break;
                    case 5: invalid["source"]["packs"]=42; break;
                    case 6: invalid["source"]["settings"]["seed"]=-1; break;
                    case 7: invalid["source"]["settings"]["threat_budget"]=-1; break;
                    case 8: invalid["source"]["settings"]["room_width"]=Json::array({5,2}); break;
                    case 9: invalid["source"]["rooms"][0]["bounds"]["x"]=-50; break;
                    case 10: invalid["source"]["packs"][0]["slots"]=-1; break;
                    default: invalid["source"]=nullptr;
                }
                CHECK(run(c,invalid.dump()).at("outcome")!="success");
                CHECK(bytes([&](uint8_t* p,uint32_t n,uint32_t* len){return da_context_read(c,p,n,len);})==retained);
            }
            for(int fuzz=0;fuzz<8;++fuzz) {
                std::string junk(1+random()%128,'?'); for(auto& ch:junk) ch=static_cast<char>(random()%256);
                // Prefix guarantees malformed JSON independently of RNG.
                junk.insert(0,"!invalid!"); CHECK(run(c,junk).at("outcome")!="success");
            }
            CHECK(run(c,raw,DA_RUN,true).at("outcome")=="cancelled");
            CHECK(bytes([&](uint8_t* p,uint32_t n,uint32_t* len){return da_context_read(c,p,n,len);})==retained);
            CHECK(run(c,raw,DA_VALIDATE).at("outcome")=="success");
            CHECK(run(c,raw,DA_NORMALIZE).at("outcome")=="success");
            CHECK(da_context_release(c)==DA_OK); CHECK(da_context_release(c)==DA_INVALID_HANDLE); released.insert(c);
            uint32_t n=0; CHECK(da_context_read(c,nullptr,0,&n)==DA_INVALID_HANDLE);
        }
        std::cout<<"24 contexts, 24 randomized small projects, 288 malformed mutations, 192 random byte inputs; snapshot/lifecycle checks passed\n";
        return 0;
    } catch(const std::exception& e) { std::cerr<<e.what()<<'\n'; return 1; }
}

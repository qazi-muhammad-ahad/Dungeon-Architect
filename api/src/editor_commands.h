#pragma once
#include <algorithm>
#include "dungeon_architect/geometry.h"
#include "dungeon_architect/project_io.h"
#include "dungeon_architect/result_json.h"

namespace dungeon_architect::editor_api {
using Json = nlohmann::json;
struct Response { Status status; Json doc; };
inline Json mask_rows(const std::vector<std::uint8_t>& cells,const Settings& settings) {
    Json rows=Json::array();
    for(int y=0;y<settings.rows;++y) {
        std::string row;
        for(int x=0;x<settings.columns;++x) row+=cells[static_cast<std::size_t>(y*settings.columns+x)]?'1':'0';
        rows.push_back(std::move(row));
    }
    return rows;
}
inline Json analysis(const Project& p) {
    const int w=p.settings.columns, h=p.settings.rows, stride=w+1;
    const auto n=p.allowed_mask.size();
    std::vector<std::uint8_t> detached(n), narrow(n), reservations(n);
    const auto components=analyze_mask(p);
    if(components.ok()) for(std::size_t i=0;i<n;++i)
        detached[i]=components.value->labels[i]>=0 && components.value->labels[i]!=components.value->primary_component;
    // A cell is narrow if no fully allowed corridor-width square covers it.
    // Summed areas and a difference grid make this linear in the canvas size.
    std::vector<int> sums(static_cast<std::size_t>((w+1)*(h+1))), coverage(sums.size());
    for(int y=0;y<h;++y) for(int x=0;x<w;++x)
        sums[static_cast<std::size_t>((y+1)*stride+x+1)]=p.allowed_mask[static_cast<std::size_t>(y*w+x)]+sums[static_cast<std::size_t>(y*stride+x+1)]+sums[static_cast<std::size_t>((y+1)*stride+x)]-sums[static_cast<std::size_t>(y*stride+x)];
    const int k=p.settings.corridor_width;
    for(int y=0;y+k<=h;++y) for(int x=0;x+k<=w;++x) {
        const int count=sums[static_cast<std::size_t>((y+k)*stride+x+k)]-sums[static_cast<std::size_t>(y*stride+x+k)]-sums[static_cast<std::size_t>((y+k)*stride+x)]+sums[static_cast<std::size_t>(y*stride+x)];
        if(count==k*k) { ++coverage[static_cast<std::size_t>(y*stride+x)]; --coverage[static_cast<std::size_t>(y*stride+x+k)]; --coverage[static_cast<std::size_t>((y+k)*stride+x)]; ++coverage[static_cast<std::size_t>((y+k)*stride+x+k)]; }
    }
    for(int y=0;y<h;++y) for(int x=0;x<w;++x) {
        auto& v=coverage[static_cast<std::size_t>(y*stride+x)];
        if(x) v+=coverage[static_cast<std::size_t>(y*stride+x-1)]; if(y) v+=coverage[static_cast<std::size_t>((y-1)*stride+x)]; if(x&&y) v-=coverage[static_cast<std::size_t>((y-1)*stride+x-1)];
        narrow[static_cast<std::size_t>(y*w+x)]=p.allowed_mask[static_cast<std::size_t>(y*w+x)] && v==0;
    }
    for(const auto& r:p.rooms) if(r.lock_position||r.lock_size) {
        const int m=p.settings.margin;
        for(int y=std::max(0,r.bounds.y-m);y<std::min(h,r.bounds.y+r.bounds.height+m);++y)
            for(int x=std::max(0,r.bounds.x-m);x<std::min(w,r.bounds.x+r.bounds.width+m);++x) reservations[static_cast<std::size_t>(y*w+x)]=1;
    }
    return {{"detached",mask_rows(detached,p.settings)}, {"narrow",mask_rows(narrow,p.settings)},
        {"reservations",mask_rows(reservations,p.settings)}, {"component_count",components.ok()?components.value->components.size():0}};
}
inline Response finish(const Status& status, const Project* p=nullptr) {
    Response r{status,Json::parse(project_io::diagnostics_json(status))};
    if(status.ok()&&p) {
        const auto encoded=project_io::serialize(*p);
        if(!encoded.ok()) return finish(encoded.status);
        r.doc["project_json"]=*encoded.value; r.doc["editor_analysis"]=analysis(*p);
    }
    return r;
}
inline Response invalid(const std::string& message) {
    return finish(failure(Outcome::invalid_input,"editor_command","/command",message,"Adjust the edit and try again. Existing source and locks were preserved."));
}
inline int integer(const Json& c,const char* key,int min,int max) {
    const auto& v=c.at(key);
    if(!v.is_number_integer() || v < min || v > max) throw std::invalid_argument(key);
    return v.get<int>();
}
inline Response execute(const std::string& raw) {
    try {
        const auto envelope=Json::parse(raw);
        const auto parsed=project_io::parse(envelope.at("project_json").get<std::string>());
        if(!parsed.ok()) return finish(parsed.status);
        ProjectSession session; auto status=session.replace_loaded(*parsed.value);
        if(!status.ok()) return finish(status);
        const auto& c=envelope.at("command"); const auto type=c.at("type").get<std::string>();
        if(type=="upsert_room" || type=="upsert_pack" || type=="remove_room" || type=="remove_pack") {
            // Parse the proposed record through the shared schema, then apply it
            // against the previous source so lock checks cannot be bypassed.
            const bool room=type=="upsert_room"||type=="remove_room";
            const bool remove=type=="remove_room"||type=="remove_pack";
            const auto key=room?"rooms":"packs";
            auto document=Json::parse(envelope.at("project_json").get<std::string>());
            auto& records=document["source"][key];
            const auto id=remove?c.at("id").get<std::string>():c.at(room?"room":"pack").at("id").get<std::string>();
            auto it=std::find_if(records.begin(),records.end(),[&](const Json& v){return v.at("id")==id;});
            if(remove) {
                if(it==records.end()) return invalid("No record has the requested ID.");
                records.erase(it);
            } else if(it==records.end()) records.push_back(c.at(room?"room":"pack"));
            else *it=c.at(room?"room":"pack");
            const auto candidate=project_io::parse(document.dump());
            if(!candidate.ok()) return finish(candidate.status);
            status=session.update(*candidate.value);
        } else if(type=="fix_room") {
            const auto& value=c.at("room"); const auto id=value.at("id").get<std::string>();
            auto candidate=session.project();
            auto it=std::find_if(candidate.rooms.begin(),candidate.rooms.end(),[&](const Room& r){return r.id==id;});
            if(!c.at("fixed").get<bool>()) {
                if(it==candidate.rooms.end()) return invalid("This room is not fixed.");
                it->lock_position=false; it->lock_size=false;
                status=session.update(std::move(candidate));
            } else {
                Room room;
                if(it!=candidate.rooms.end()) room=*it;
                else {
                    room.id=id; room.name=value.value("name",id);
                    const auto role=value.value("role",std::string("normal"));
                    room.role=role=="entrance"?RoomRole::entrance:role=="exit"?RoomRole::exit:role=="boss"?RoomRole::boss:RoomRole::normal;
                    room.tags=value.value("tags",std::vector<std::string>{});
                    if(value.contains("capacity_override")&&!value["capacity_override"].is_null()) room.capacity_override=value["capacity_override"].get<int>();
                }
                const auto& b=value.at("bounds");
                room.bounds={integer(b,"x",0,511),integer(b,"y",0,511),integer(b,"width",1,512),integer(b,"height",1,512)};
                room.lock_position=true; room.lock_size=true;
                status=it==candidate.rooms.end()?add_room(session,std::move(room)):edit_room(session,id,std::move(room));
            }
        } else if(type=="paint") {
            const auto& values=c.at("tiles");
            if(!values.is_array()||values.size()>262144) return invalid("Stroke exceeds the canvas tile limit.");
            std::vector<Tile> tiles; tiles.reserve(values.size());
            for(const auto& v:values) tiles.push_back({integer(v,"x",0,511),integer(v,"y",0,511)});
            status=paint_tiles(session,tiles,c.at("allowed").get<bool>());
        } else if(type=="fill") {
            status=flood_fill(session,{integer(c,"x",0,511),integer(c,"y",0,511)},c.at("allowed").get<bool>());
        } else if(type=="shape") {
            const auto shape=c.at("shape").get<std::string>();
            if(shape!="rectangle"&&shape!="ellipse"&&shape!="l_shape") return invalid("Unknown shape.");
            const auto& p=session.project();
            const auto mask=make_mask(p.settings.columns,p.settings.rows,shape=="ellipse"?MaskPreset::ellipse:shape=="l_shape"?MaskPreset::l_shape:MaskPreset::rectangle,
                {integer(c,"x",0,511),integer(c,"y",0,511),integer(c,"width",1,512),integer(c,"height",1,512)});
            if(!mask.ok()) return finish(mask.status);
            auto candidate=p; const auto mode=c.at("mode").get<std::string>();
            if(mode!="replace"&&mode!="add"&&mode!="subtract") return invalid("Unknown shape blend mode.");
            for(std::size_t i=0;i<candidate.allowed_mask.size();++i)
                candidate.allowed_mask[static_cast<std::size_t>(i)]=mode=="replace"?(*mask.value)[i]:mode=="add"?(p.allowed_mask[static_cast<std::size_t>(i)]||(*mask.value)[i]):(p.allowed_mask[static_cast<std::size_t>(i)]&&!(*mask.value)[i]);
            status=session.update(std::move(candidate));
        } else if(type=="resize") {
            auto candidate=session.project(); const int oldW=candidate.settings.columns, oldH=candidate.settings.rows;
            const int w=integer(c,"columns",1,512),h=integer(c,"rows",1,512);
            bool crops=false;
            for(int y=0;y<oldH;++y) for(int x=0;x<oldW;++x) if((x>=w||y>=h)&&candidate.allowed_mask[static_cast<std::size_t>(y*oldW+x)]) crops=true;
            if(crops&&!c.value("allow_crop",false)) return invalid("Resize would crop allowed tiles. Confirm cropping or choose larger dimensions.");
            std::vector<std::uint8_t> mask(static_cast<std::size_t>(w*h));
            for(int y=0;y<std::min(h,oldH);++y) for(int x=0;x<std::min(w,oldW);++x) mask[static_cast<std::size_t>(y*w+x)]=candidate.allowed_mask[static_cast<std::size_t>(y*oldW+x)];
            candidate.settings.columns=w; candidate.settings.rows=h; candidate.allowed_mask=std::move(mask);
            status=session.update(std::move(candidate));
        } else return invalid("Unknown editor command.");
        return finish(status,status.ok()?&session.project():nullptr);
    } catch(const Json::exception&) { return invalid("Malformed editor command."); }
      catch(const std::invalid_argument&) { return invalid("Coordinates and dimensions must be whole numbers within the supported canvas."); }
}
}


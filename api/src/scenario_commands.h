// Included inside the ABI implementation's private namespace. Scenario snapshots
// are deliberately separate from the fully connected generation representation.
Execution execute_scenario(Job& j, da_job id, const std::function<bool()>& cancelled) {
    const auto start = std::chrono::steady_clock::now();
    const auto bad = [](const char* message) {
        auto status = da::failure(da::Outcome::invalid_input,"scenario_input","/scenario",message,
            "Use a current baseline, valid floor tiles, room IDs and nonnegative capacities/budget; leave the entrance open.");
        return Execution{status,report::error_json(status,"scenario"),{}};
    };
    Json command;
    try { command = Json::parse(j.input); }
    catch (const Json::exception&) { return bad("Scenario must be valid JSON."); }
    const auto baseline = j.context->last;
    if (!command.is_object() || !command.contains("baseline_job") || !command["baseline_job"].is_number_unsigned())
        return bad("A scenario requires its retained baseline job identity.");
    if (!baseline || !baseline->geometry || !baseline->layout || command["baseline_job"] != baseline->job) {
        auto status = da::failure(da::Outcome::stale_result,"scenario_baseline_stale","/baseline_job",
            "The scenario baseline is no longer retained.","Generate and solve a current baseline before applying a scenario.");
        return {status,report::error_json(status,"scenario"),{}};
    }
    auto prepared = da::prepare_allocation(baseline->source,*baseline->layout,*baseline->geometry);
    if (!prepared.ok()) return {prepared.status,report::error_json(prepared.status,"scenario"),{}};
    auto input = std::move(*prepared.value);
    auto geometry = *baseline->geometry;
    geometry.id += "-scenario-"+std::to_string(id);
    input.geometry_id = geometry.id;
    std::set<std::pair<int,int>> blocks;
    std::set<std::string> disabled;
    std::map<std::string,int> capacities;
    try {
        if (command.contains("budget")) {
            if (!command["budget"].is_number_integer()) return bad("Scenario budget must be an exact nonnegative int64.");
            const auto value = command["budget"].get<std::int64_t>();
            if (value < 0 || (command["budget"].is_number_unsigned() && command["budget"].get<std::uint64_t>() > INT64_MAX)) return bad("Scenario budget exceeds int64 limits.");
            input.settings.threat_budget = value;
        }
        const auto tiles = command.value("blocked_tiles",Json::array());
        const auto rooms = command.value("disabled_rooms",Json::array());
        const auto caps = command.value("capacities",Json::object());
        if (!tiles.is_array() || tiles.size() > da::limits::max_cells || !rooms.is_array() || rooms.size() > input.rooms.size() || !caps.is_object()) return bad("Scenario lists exceed their bounds or have invalid types.");
        for (const auto& tile : tiles) {
            if (!tile.is_array() || tile.size()!=2 || !tile[0].is_number_integer() || !tile[1].is_number_integer()) return bad("Blocked tiles must be integer [x,y] pairs.");
            const auto x=tile[0].get<std::int64_t>(), y=tile[1].get<std::int64_t>();
            if (x<0 || y<0 || x>=input.settings.columns || y>=input.settings.rows) return bad("Blocked tile is outside the map.");
            da::Tile t{static_cast<int>(x),static_cast<int>(y)};
            if (t==geometry.entrance_marker || !da::walkable(input.settings,geometry,t)) return bad("Block only existing floor and keep the entrance marker open.");
            blocks.emplace(t.x,t.y);
        }
        const auto known = [&](const std::string& key) { return std::any_of(input.rooms.begin(),input.rooms.end(),[&](const da::AllocationRoom& r){return r.room.id==key;}); };
        for (const auto& room : rooms) {
            if (!room.is_string() || !known(room.get<std::string>())) return bad("Disabled room ID does not exist in the baseline.");
            disabled.insert(room.get<std::string>());
        }
        for (auto it=caps.begin();it!=caps.end();++it) {
            if (!known(it.key()) || !it.value().is_number_integer()) return bad("Capacity controls require known room IDs and whole numbers.");
            const auto value=it.value().get<std::int64_t>();
            if (value<0 || value>static_cast<std::int64_t>(da::limits::max_cells)) return bad("Scenario capacity is outside supported bounds.");
            capacities[it.key()]=static_cast<int>(value);
        }
    } catch (const Json::exception&) { return bad("Scenario controls have invalid values."); }
    const auto index=[&](da::Tile t) { return static_cast<std::size_t>(t.y*input.settings.columns+t.x); };
    for (const auto& [x,y] : blocks) { geometry.layers.floor[index({x,y})]=0; geometry.layers.walls[index({x,y})]=1; }
    std::vector<std::uint8_t> reached(geometry.layers.floor.size());
    std::queue<da::Tile> queue; queue.push(geometry.entrance_marker); reached[index(queue.front())]=1;
    std::size_t visits=0;
    while (!queue.empty()) {
        if ((++visits & 255U)==0 && cancelled()) { auto status=cancelled_status(); return {status,report::error_json(status,"scenario"),{}}; }
        const auto t=queue.front(); queue.pop();
        for (const auto d : {da::Tile{1,0},da::Tile{-1,0},da::Tile{0,1},da::Tile{0,-1}}) {
            const da::Tile next{t.x+d.x,t.y+d.y};
            if (da::walkable(input.settings,geometry,next) && !reached[index(next)]) { reached[index(next)]=1; queue.push(next); }
        }
    }
    Json disconnected=Json::array(); std::size_t reachable_rooms=0;
    for (auto& room : input.rooms) {
        auto& placed=*std::find_if(geometry.rooms.begin(),geometry.rooms.end(),[&](const da::RoomPlacement& r){return r.id==room.room.id;});
        // Hub reachability defines the room indicator; actor eligibility also
        // requires each surviving spawn to be physically reachable.
        room.reachable=reached[index(placed.hub)]!=0;
        room.spawns.erase(std::remove_if(room.spawns.begin(),room.spawns.end(),[&](const da::SpawnPosition& s){return !reached[index(s.tile)];}),room.spawns.end());
        auto capacity=capacities.count(room.room.id)?capacities.at(room.room.id):room.capacity;
        room.capacity=room.reachable && !disabled.count(room.room.id) && room.room.role!=da::RoomRole::entrance ? std::min(capacity,static_cast<int>(room.spawns.size())) : 0;
        placed.reachable=room.reachable; placed.capacity=room.capacity; placed.spawn_positions=room.spawns;
        if (room.reachable) ++reachable_rooms; else disconnected.push_back(room.room.id);
    }
    const auto connectivity_end=std::chrono::steady_clock::now();
    auto status=da::validate_allocation_input(input);
    if (!status.ok()) return {status,report::error_json(status,"scenario"),{}};
    j.stage=4;
    da::AllocationOptions options; options.max_events=j.max_events; options.cancelled=cancelled;
    auto allocated=da::allocate_encounters(input,options);
    if (!allocated.ok()) return {allocated.status,report::error_json(allocated.status,"scenario"),{}};
    if (cancelled()) { status=cancelled_status(); return {status,report::error_json(status,"scenario"),{}}; }
    da::RoutingResult routed; routed.geometry=geometry;
    da::GenerationResult generated; generated.layout=baseline->layout;
    auto source=baseline->source; source.settings.threat_budget=input.settings.threat_budget;
    auto doc=report::error_json({},"pipeline");
    doc["optimal"]=true;
    doc["result"]={{"layout",report::layout_json(source,generated)["layout"]},{"geometry",report::geometry_json(source,routed)["geometry"]},{"allocation",report::allocation_json(source,allocated)["allocation"]}};
    bool all_floor_reached=true;
    for (std::size_t i=0;i<reached.size();++i) if (geometry.layers.floor[i] && !reached[i]) all_floor_reached=false;
    doc["result"]["geometry"]["connected_floor_verified"]=all_floor_reached;
    doc["result"]["geometry"]["scenario_walkability_verified"]=true;
    doc["result"]["source_project"]=Json::parse(*io::serialize(baseline->source).value);
    doc["stages"]={{"allocation",report::allocation_json(source,allocated)}}; doc["stages"]["allocation"].erase("allocation");
    doc["scenario"]={{"baseline_job",baseline->job},{"snapshot_job",id},{"blocked_tiles",command.value("blocked_tiles",Json::array())},{"disabled_rooms",command.value("disabled_rooms",Json::array())},{"capacities",command.value("capacities",Json::object())},{"budget",input.settings.threat_budget},{"disconnected_rooms",disconnected},{"reachable_rooms",reachable_rooms},{"exit_reachable",reached[index(geometry.exit_marker)]!=0},{"solver","full_exact_rerun"},{"timings_us",{{"connectivity",std::chrono::duration<double,std::micro>(connectivity_end-start).count()},{"total",std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-start).count()}}}};
    auto snapshot=std::make_shared<Snapshot>(*baseline); snapshot->geometry=std::move(geometry); snapshot->job=id;
    return {{},std::move(doc),std::move(snapshot)};
}

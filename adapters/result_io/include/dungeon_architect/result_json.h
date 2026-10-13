#pragma once
#include "dungeon_architect/allocation.h"
#include <nlohmann/json.hpp>
namespace dungeon_architect::result_io {
nlohmann::json layout_json(const Project&, const GenerationResult&);
nlohmann::json geometry_json(const Project&, const RoutingResult&);
nlohmann::json allocation_json(const Project&, const AllocationResult&);
nlohmann::json error_json(const Status&, const char* stage);
}

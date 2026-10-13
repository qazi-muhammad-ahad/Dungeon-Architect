#include "dungeon_architect/build_info.h"
#include "da_version.h"

#include <climits>

namespace dungeon_architect {
BuildInfo build_info() noexcept {
    return {DA_ENGINE_VERSION, static_cast<std::uint32_t>(sizeof(void*) * CHAR_BIT)};
}
}  // namespace dungeon_architect

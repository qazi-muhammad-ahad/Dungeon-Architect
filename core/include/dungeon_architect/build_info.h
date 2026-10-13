#pragma once

#include <cstdint>

namespace dungeon_architect {
// Bootstrap metadata only; no domain or algorithm behavior is defined yet.
struct BuildInfo {
    const char* version;
    std::uint32_t pointer_bits;
};

BuildInfo build_info() noexcept;
}  // namespace dungeon_architect

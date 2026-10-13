#include "dungeon_architect/build_info.h"

#include <climits>
#include <cstring>
#include <iostream>

int main() {
    // Exercise a symbol from the linked core, with checks active in Release too.
    const auto info = dungeon_architect::build_info();
    if (info.version == nullptr || std::strlen(info.version) == 0 ||
        info.pointer_bits != sizeof(void*) * CHAR_BIT) {
        std::cerr << "Core build metadata does not match the caller.\n";
        return 1;
    }
    std::cout << "Core linked: " << info.version << ", " << info.pointer_bits << "-bit\n";
    return 0;
}

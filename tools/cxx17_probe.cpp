#include <string_view>
#include <utility>

int main() {
    constexpr std::string_view name = "Dungeon Architect";
    const auto [width, height] = std::pair<int, int>{150, 150};
    return name.size() == 17 && width == height ? 0 : 1;
}

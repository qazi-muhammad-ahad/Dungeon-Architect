#include "dungeon_architect/geometry.h"
#include <algorithm>
#include <array>

namespace dungeon_architect {
namespace {
std::size_t index(Tile t, std::int32_t columns) {
    return static_cast<std::size_t>(t.y) * static_cast<std::size_t>(columns) + static_cast<std::size_t>(t.x);
}
bool inside(Tile t, std::int32_t columns, std::int32_t rows) {
    return t.x >= 0 && t.y >= 0 && t.x < columns && t.y < rows;
}
constexpr std::array<Tile, 4> directions{{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}};
Status bad_tile(Tile tile) {
    auto status = failure(Outcome::invalid_input, "tile_bounds", "/source/allowed_mask",
        "Tile is outside the canvas.", "Use a tile with 0 <= x < columns and 0 <= y < rows.");
    status.diagnostics[0].affected_tiles.push_back(tile);
    return status;
}
Status mask_shape(const Project& project) {
    const auto& s = project.settings;
    if (s.columns <= 0 || s.rows <= 0 || s.columns > limits::max_axis || s.rows > limits::max_axis ||
        project.allowed_mask.size() != static_cast<std::size_t>(std::int64_t{s.columns} * s.rows) ||
        std::any_of(project.allowed_mask.begin(), project.allowed_mask.end(), [](auto cell) { return cell > 1; }))
        return failure(Outcome::invalid_input, "mask_shape", "/source/allowed_mask",
                       "Canvas dimensions and mask storage must be valid before analysis.", "Validate the source project first.");
    return {};
}
}
Result<std::vector<std::uint8_t>> make_mask(std::int32_t columns, std::int32_t rows,
                                         MaskPreset preset, Rect bounds) {
    if (columns <= 0 || rows <= 0 || columns > limits::max_axis || rows > limits::max_axis || !bounds.inside(columns, rows))
        return {failure(Outcome::invalid_input, "preset_bounds", "/mask/bounds",
            "Preset bounds must be a positive rectangle inside a supported canvas.", "Correct the preset rectangle and canvas dimensions."), std::nullopt};
    if ((preset != MaskPreset::rectangle && preset != MaskPreset::ellipse && preset != MaskPreset::l_shape) ||
        (preset == MaskPreset::l_shape && (bounds.width < 2 || bounds.height < 2)))
        return {failure(Outcome::invalid_input, "preset_shape", "/mask/preset",
            "Unknown preset or L-shape smaller than 2 x 2.", "Use rectangle, ellipse, or an L-shape at least 2 x 2."), std::nullopt};
    std::vector<std::uint8_t> cells(static_cast<std::size_t>(columns) * static_cast<std::size_t>(rows), 0);
    const std::int64_t w = bounds.width, h = bounds.height;
    for (std::int32_t y = bounds.y; y < bounds.bottom(); ++y) {
        for (std::int32_t x = bounds.x; x < bounds.right(); ++x) {
            bool allowed = preset == MaskPreset::rectangle;
            if (preset == MaskPreset::ellipse) {
                // Exact integer test of cell centers against the inscribed ellipse.
                const std::int64_t dx = 2 * std::int64_t{x - bounds.x} + 1 - w;
                const std::int64_t dy = 2 * std::int64_t{y - bounds.y} + 1 - h;
                allowed = dx * dx * h * h + dy * dy * w * w <= w * w * h * h;
            } else if (preset == MaskPreset::l_shape) {
                allowed = x - bounds.x < (bounds.width + 1) / 2 ||
                          y - bounds.y >= bounds.height / 2;
            }
            cells[index({x, y}, columns)] = allowed ? 1 : 0;
        }
    }
    return {{}, std::move(cells)};
}
Status apply_mask_preset(ProjectSession& session, MaskPreset preset, Rect bounds) {
    auto candidate = session.project();
    auto mask = make_mask(candidate.settings.columns, candidate.settings.rows, preset, bounds);
    if (!mask.ok()) return mask.status;
    candidate.allowed_mask = std::move(*mask.value);
    return session.update(std::move(candidate));
}
Status paint_tiles(ProjectSession& session, const std::vector<Tile>& tiles, bool allowed) {
    const auto& settings = session.project().settings;
    // Validate the complete stroke before any change; no clipping or partial paint.
    for (auto tile : tiles) if (!inside(tile, settings.columns, settings.rows)) return bad_tile(tile);
    auto candidate = session.project();
    for (auto tile : tiles) candidate.allowed_mask[index(tile, settings.columns)] = allowed ? 1 : 0;
    return session.update(std::move(candidate));
}
Status flood_fill(ProjectSession& session, Tile start, bool allowed) {
    auto candidate = session.project();
    const auto columns = candidate.settings.columns, rows = candidate.settings.rows;
    if (!inside(start, columns, rows)) return bad_tile(start);
    const auto old = candidate.allowed_mask[index(start, columns)];
    const std::uint8_t next = allowed ? 1 : 0;
    if (old == next) return {};
    std::vector<Tile> queue{start};
    candidate.allowed_mask[index(start, columns)] = next;
    for (std::size_t head = 0; head < queue.size(); ++head) {
        const auto tile = queue[head];
        for (auto delta : directions) {
            const Tile neighbor{tile.x + delta.x, tile.y + delta.y};
            if (inside(neighbor, columns, rows) && candidate.allowed_mask[index(neighbor, columns)] == old) {
                candidate.allowed_mask[index(neighbor, columns)] = next;
                queue.push_back(neighbor);
            }
        }
    }
    return session.update(std::move(candidate));
}
Result<MaskAnalysis> analyze_mask(const Project& project) {
    auto status = mask_shape(project);
    if (!status.ok()) return {std::move(status), std::nullopt};
    const auto columns = project.settings.columns, rows = project.settings.rows;
    MaskAnalysis analysis;
    analysis.labels.assign(project.allowed_mask.size(), -1);
    for (std::int32_t y = 0; y < rows; ++y) {
        for (std::int32_t x = 0; x < columns; ++x) {
            const Tile start{x, y};
            if (!project.allowed_mask[index(start, columns)] || analysis.labels[index(start, columns)] != -1) continue;
            MaskComponent component;
            component.id = static_cast<std::int32_t>(analysis.components.size());
            component.bounds = {x, y, 1, 1};
            component.tiles.push_back(start);
            analysis.labels[index(start, columns)] = component.id;
            std::int32_t min_x = x, max_x = x, min_y = y, max_y = y;
            for (std::size_t head = 0; head < component.tiles.size(); ++head) {
                const auto tile = component.tiles[head];
                min_x = std::min(min_x, tile.x); max_x = std::max(max_x, tile.x);
                min_y = std::min(min_y, tile.y); max_y = std::max(max_y, tile.y);
                for (auto delta : directions) {
                    const Tile neighbor{tile.x + delta.x, tile.y + delta.y};
                    if (!inside(neighbor, columns, rows)) continue;
                    const auto i = index(neighbor, columns);
                    if (project.allowed_mask[i] && analysis.labels[i] == -1) {
                        analysis.labels[i] = component.id;
                        component.tiles.push_back(neighbor);
                    }
                }
            }
            component.bounds = {min_x, min_y, max_x - min_x + 1, max_y - min_y + 1};
            if (analysis.primary_component < 0 || component.tiles.size() > analysis.components[static_cast<std::size_t>(analysis.primary_component)].tiles.size())
                analysis.primary_component = component.id;
            analysis.components.push_back(std::move(component));
        }
    }
    return {{}, std::move(analysis)};
}
}  // namespace dungeon_architect

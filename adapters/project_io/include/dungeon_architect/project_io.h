#pragma once

#include "dungeon_architect/project.h"
#include <filesystem>
#include <string_view>

namespace dungeon_architect::project_io {
constexpr std::int32_t schema_version = 1;
// JSON is an adapter dependency and never appears in the public C++ types.
Result<Project> parse(std::string_view document);
Result<std::string> serialize(const Project& project);
Result<Project> read(const std::filesystem::path& path);
Status load_into(ProjectSession& session, const std::filesystem::path& path);
enum class SaveMode { replace_existing, create_only };
Status save_atomic(const Project& project, const std::filesystem::path& path,
                   SaveMode mode = SaveMode::replace_existing);
// Shared atomic writer for derived CLI reports (UTF-8 prepared by the caller).
// Same-directory temporary file; no-clobber by default; maximum 128 MiB.
Status write_text_atomic(std::string_view text, const std::filesystem::path& path,
                         SaveMode mode = SaveMode::create_only);
std::string diagnostics_json(const Status& status);
}  // namespace dungeon_architect::project_io

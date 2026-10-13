#include "dungeon_architect/project_io.h"

#include <array>
#include <atomic>
#include <fstream>
#include <system_error>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>
#endif

namespace dungeon_architect::project_io {
namespace {
Status io_error(const std::filesystem::path& path, const std::string& message) {
    return failure(Outcome::io_failure, "file_access", path.u8string(), message,
                   "Check the path, directory permissions, free space, and whether another program has locked the file.");
}
std::string system_message(unsigned long code) {
    return std::system_category().message(static_cast<int>(code)) + " (code " + std::to_string(code) + ")";
}
std::atomic<std::uint64_t> serial{0};
struct TemporaryFile {
    std::filesystem::path path;
    bool created = false;
#ifdef _WIN32
    HANDLE handle = INVALID_HANDLE_VALUE;
    ~TemporaryFile() {
        if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
        if (created) DeleteFileW(path.c_str());
    }
#else
    int handle = -1;
    ~TemporaryFile() {
        if (handle != -1) ::close(handle);
        if (created) ::unlink(path.c_str());
    }
#endif
};
}
Result<Project> read(const std::filesystem::path& path) {
    try {
        std::error_code ec;
        if (!std::filesystem::is_regular_file(path, ec))
            return {io_error(path, "Project path is not a readable regular file."), std::nullopt};
        const auto size = std::filesystem::file_size(path, ec);
        if (ec) return {io_error(path, ec.message()), std::nullopt};
        if (size > limits::max_file_bytes)
            return {failure(Outcome::unsupported_size, "file_limit", path.u8string(), "Project file exceeds 16 MiB.", "Choose a smaller project file."), std::nullopt};
        std::ifstream stream(path, std::ios::binary);
        if (!stream) return {io_error(path, "Could not open the project for reading."), std::nullopt};
        std::string contents;
        contents.reserve(static_cast<std::size_t>(size));
        std::array<char, 65536> buffer{};
        while (stream) {
            stream.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
            const auto count = static_cast<std::size_t>(stream.gcount());
            if (count > limits::max_file_bytes - contents.size())
                return {failure(Outcome::unsupported_size, "file_limit", path.u8string(), "Project grew beyond 16 MiB during reading.", "Retry with a smaller, stable file."), std::nullopt};
            contents.append(buffer.data(), count);
        }
        if (!stream.eof() || stream.bad()) return {io_error(path, "Reading the project failed."), std::nullopt};
        return parse(contents);
    } catch (const std::bad_alloc&) {
        return {failure(Outcome::resource_failure, "allocation_failure", "", "Insufficient memory to read project.", "Reduce the document size."), std::nullopt};
    } catch (const std::filesystem::filesystem_error& e) {
        return {io_error(path, e.what()), std::nullopt};
    }
}
Status load_into(ProjectSession& session, const std::filesystem::path& path) {
    auto candidate = read(path);
    if (!candidate.ok()) return candidate.status;
    return session.replace_loaded(std::move(*candidate.value));
}
Status save_atomic(const Project& project, const std::filesystem::path& path, SaveMode mode) {
    // Validate and serialize before opening any output, including temporary files.
    auto encoded = serialize(project);
    if (!encoded.ok()) return encoded.status;
    return write_text_atomic(*encoded.value,path,mode);
}
Status write_text_atomic(std::string_view data, const std::filesystem::path& path, SaveMode mode) {
    if (data.size() > 128U*1024U*1024U)
        return failure(Outcome::unsupported_size,"export_size",path.u8string(),"The report exceeds the 128 MiB export limit.","Reduce the workload or trace capacity.");
    if (path.empty() || path.filename().empty()) return io_error(path, "A destination filename is required.");
    try {
        TemporaryFile temp;
#ifdef _WIN32
        const auto process = GetCurrentProcessId();
#else
        const auto process = ::getpid();
#endif
        bool opened = false;
        for (unsigned attempt = 0; attempt < 100; ++attempt) {
            temp.path = path;
            temp.path += ".tmp." + std::to_string(process) + "." + std::to_string(serial.fetch_add(1));
#ifdef _WIN32
            temp.handle = CreateFileW(temp.path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (temp.handle != INVALID_HANDLE_VALUE) { opened = true; break; }
            const auto error = GetLastError();
            if (error != ERROR_FILE_EXISTS && error != ERROR_ALREADY_EXISTS) return io_error(path, "Cannot create temporary file: " + system_message(error));
#else
            temp.handle = ::open(temp.path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0600);
            if (temp.handle != -1) { opened = true; break; }
            if (errno != EEXIST) return io_error(path, "Cannot create temporary file: " + system_message(static_cast<unsigned long>(errno)));
#endif
        }
        if (!opened) return io_error(path, "Cannot reserve a unique temporary filename.");
        temp.created = true;
        std::size_t offset = 0;
        while (offset < data.size()) {
#ifdef _WIN32
            DWORD written = 0;
            if (!WriteFile(temp.handle, data.data() + offset, static_cast<DWORD>(data.size() - offset), &written, nullptr) || written == 0)
                return io_error(path, "Temporary file write failed: " + system_message(GetLastError()));
            offset += written;
#else
            const auto written = ::write(temp.handle, data.data() + offset, data.size() - offset);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) return io_error(path, "Temporary file write failed: " + system_message(static_cast<unsigned long>(errno)));
            offset += static_cast<std::size_t>(written);
#endif
        }
#ifdef _WIN32
        if (!FlushFileBuffers(temp.handle)) return io_error(path, "Flush failed: " + system_message(GetLastError()));
        if (!CloseHandle(temp.handle)) return io_error(path, "Close failed: " + system_message(GetLastError()));
        temp.handle = INVALID_HANDLE_VALUE;
        // Same-directory rename keeps replacement on the same volume. Never
        // remove/truncate the destination as a fallback when replacement fails.
        const DWORD flags = MOVEFILE_WRITE_THROUGH | (mode == SaveMode::replace_existing ? MOVEFILE_REPLACE_EXISTING : 0U);
        if (!MoveFileExW(temp.path.c_str(), path.c_str(), flags))
            return io_error(path, "Atomic replacement failed: " + system_message(GetLastError()));
#else
        if (::fsync(temp.handle) != 0) return io_error(path, "Flush failed: " + system_message(static_cast<unsigned long>(errno)));
        const int descriptor = temp.handle;
        temp.handle = -1;
        if (::close(descriptor) != 0) return io_error(path, "Close failed: " + system_message(static_cast<unsigned long>(errno)));
        if (mode == SaveMode::create_only) {
            if (::link(temp.path.c_str(), path.c_str()) != 0)
                return io_error(path, "Atomic creation failed: " + system_message(static_cast<unsigned long>(errno)));
            // Destructor removes the temporary hard link, leaving the destination.
            return {};
        }
        if (::rename(temp.path.c_str(), path.c_str()) != 0)
            return io_error(path, "Atomic replacement failed: " + system_message(static_cast<unsigned long>(errno)));
#endif
        temp.created = false;
        return {};
    } catch (const std::bad_alloc&) {
        return failure(Outcome::resource_failure, "allocation_failure", "", "Insufficient memory to save project.", "Close other work or reduce the project.");
    } catch (const std::filesystem::filesystem_error& e) {
        return io_error(path, e.what());
    }
}
}  // namespace dungeon_architect::project_io

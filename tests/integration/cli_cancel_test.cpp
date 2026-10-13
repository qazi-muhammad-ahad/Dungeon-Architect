#include "dungeon_architect/project_io.h"
#include "../test_support.h"
#include "nlohmann/json.hpp"
#include <filesystem>
#include <fstream>
#include <iterator>
#define NOMINMAX
#include <windows.h>

namespace fs = std::filesystem;
namespace io = dungeon_architect::project_io;
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    ~Handle() { if (value != INVALID_HANDLE_VALUE && value != nullptr) CloseHandle(value); }
};
struct Child {
    PROCESS_INFORMATION process{};
    ~Child() {
        if (process.hProcess) {
            if (WaitForSingleObject(process.hProcess,0) == WAIT_TIMEOUT) {
                TerminateProcess(process.hProcess,99); WaitForSingleObject(process.hProcess,5000);
            }
            CloseHandle(process.hProcess); CloseHandle(process.hThread);
        }
    }
};
std::string bytes(const fs::path& p) {
    std::ifstream f(p,std::ios::binary); return {std::istreambuf_iterator<char>(f),std::istreambuf_iterator<char>()};
}
std::wstring quoted(const fs::path& p) { return L"\""+p.wstring()+L"\""; }
int wmain(int argc,wchar_t* argv[]) {
    try {
        CHECK(argc == 4);
        const fs::path cli(argv[1]),fixture(argv[2]),parent(argv[3]);
        const auto root = parent / ("cli-cancel-"+std::to_string(GetCurrentProcessId())+"-"+std::to_string(GetTickCount64()));
        CHECK(fs::create_directory(root));
        auto source = io::read(fixture); CHECK(source.ok());
        // Keep exact DP busy, without changing its algorithm or adding test hooks.
        for (auto& p : source.value->packs) p.slots = 1000000;
        const auto input = root / L"stress source.json", marker = root / L"cancel.request", output = root / L"accepted.json";
        CHECK(io::save_atomic(*source.value,input,io::SaveMode::create_only).ok());
        CHECK(io::write_text_atomic("previous accepted export",output).ok());
        const auto original = bytes(input);
        SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES),nullptr,TRUE};
        Handle out{CreateFileW((root/L"stdout.json").c_str(),GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,&security,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr)};
        Handle err{CreateFileW((root/L"stderr.txt").c_str(),GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,&security,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr)};
        Handle nul{CreateFileW(L"NUL",GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,&security,OPEN_EXISTING,0,nullptr)};
        CHECK(out.value != INVALID_HANDLE_VALUE && err.value != INVALID_HANDLE_VALUE && nul.value != INVALID_HANDLE_VALUE);
        STARTUPINFOW startup{}; startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESTDHANDLES;
        startup.hStdOutput = out.value; startup.hStdError = err.value; startup.hStdInput = nul.value;
        auto command = quoted(cli)+L" export "+quoted(input)+L" "+quoted(output)+L" --force --json --events 0 --cancel-file "+quoted(marker);
        Child child;
        CHECK(CreateProcessW(cli.c_str(),command.data(),nullptr,nullptr,TRUE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&child.process));
        CHECK(WaitForSingleObject(child.process.hProcess,50) == WAIT_TIMEOUT);
        CHECK(io::write_text_atomic("cancel",marker).ok());
        CHECK(WaitForSingleObject(child.process.hProcess,10000) == WAIT_OBJECT_0);
        DWORD exit_code = 0; CHECK(GetExitCodeProcess(child.process.hProcess,&exit_code)); CHECK(exit_code == 6);
        const auto result = nlohmann::json::parse(bytes(root/L"stdout.json"));
        CHECK(result["outcome"] == "cancelled" && result["result"].is_null() && result["optimal"] == false);
        CHECK(bytes(root/L"stderr.txt").empty());
        CHECK(bytes(output) == "previous accepted export" && bytes(input) == original);
        for (const auto& item : fs::directory_iterator(root)) CHECK(item.path().filename().wstring().find(L".tmp.") == std::wstring::npos);
        std::cout << checks << " live CLI cancellation checks passed\n";
        return 0;
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}

// Read-only portable loopback host. It intentionally has no application API.
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <shellapi.h>
#include <algorithm>
#include <array>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

namespace fs = std::filesystem;
namespace {
volatile LONG stopping = 0;
BOOL WINAPI interrupt(DWORD signal) {
    if (signal == CTRL_C_EVENT || signal == CTRL_BREAK_EVENT || signal == CTRL_CLOSE_EVENT) {
        InterlockedExchange(&stopping, 1); return TRUE;
    }
    return FALSE;
}
bool send_all(SOCKET socket, const char* bytes, std::size_t count) {
    while (count) {
        const int sent = send(socket, bytes, static_cast<int>((std::min)(count, std::size_t{65536})), 0);
        if (sent <= 0) return false;
        bytes += sent; count -= static_cast<std::size_t>(sent);
    }
    return true;
}
std::string lower(std::string value) {
    for (char& c : value) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return value;
}
const char* mime(const fs::path& file) {
    const auto ext = lower(file.extension().string());
    if (ext == ".html") return "text/html; charset=utf-8";
    if (ext == ".js" || ext == ".mjs") return "text/javascript";
    if (ext == ".wasm") return "application/wasm";
    if (ext == ".json") return "application/json";
    if (ext == ".png") return "image/png";
    if (ext == ".svg") return "image/svg+xml";
    if (ext == ".ico") return "image/x-icon";
    if (ext == ".ttf") return "font/ttf";
    if (ext == ".otf") return "font/otf";
    if (ext == ".woff2") return "font/woff2";
    if (ext == ".css") return "text/css";
    return "application/octet-stream";
}
void headers(SOCKET socket, int status, std::uintmax_t size, const char* type) {
    const char* reason = status == 200 ? "OK" : status == 400 ? "Bad Request" :
        status == 405 ? "Method Not Allowed" : "Not Found";
    std::ostringstream out;
    out << "HTTP/1.1 " << status << ' ' << reason << "\r\nContent-Length: " << size
        << "\r\nContent-Type: " << type << "\r\nConnection: close\r\nCache-Control: no-store\r\n"
        << "Content-Security-Policy: default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; worker-src 'self' blob:; manifest-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'none'\r\n"
        << "X-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\n"
        << "Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), serial=(), bluetooth=()\r\n"
        << "Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Resource-Policy: same-origin\r\n";
    if (status == 405) out << "Allow: GET, HEAD\r\n";
    out << "\r\n";
    const auto data = out.str(); send_all(socket, data.data(), data.size());
}
int hex(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
bool safe_path(std::string target, fs::path& relative) {
    target = target.substr(0, target.find('?'));
    if (target.empty() || target.front() != '/') return false;
    std::string decoded;
    for (std::size_t i = 1; i < target.size(); ++i) {
        unsigned char c = static_cast<unsigned char>(target[i]);
        if (c == '%') {
            if (i + 2 >= target.size() || hex(target[i+1]) < 0 || hex(target[i+2]) < 0) return false;
            c = static_cast<unsigned char>(hex(target[i+1])*16 + hex(target[i+2])); i += 2;
        }
        if (c < 32 || c >= 127 || c == '\\' || c == ':' || c == '%' || c == '#' || c == 127) return false;
        decoded += static_cast<char>(c);
    }
    if (decoded.empty()) decoded = "index.html";
    std::istringstream parts(decoded); std::string part;
    while (std::getline(parts, part, '/')) {
        if (part.empty() || part == "." || part == ".." || part.back() == '.' || part.back() == ' ') return false;
        // Windows reserved device names must never reach filesystem APIs.
        const auto stem = lower(part.substr(0, part.find('.')));
        if (stem == "con" || stem == "prn" || stem == "aux" || stem == "nul" ||
            (stem.size() == 4 && (stem.substr(0,3) == "com" || stem.substr(0,3) == "lpt") && stem[3] >= '0' && stem[3] <= '9')) return false;
        relative /= part;
    }
    return decoded.back() != '/';
}
void serve(SOCKET socket, const fs::path& root, unsigned short port) {
    constexpr std::size_t limit = 16384;
    std::string request;
    const auto deadline = GetTickCount64() + 3000;
    std::array<char, 2048> buffer{};
    while (request.find("\r\n\r\n") == std::string::npos) {
        if (request.size() >= limit || GetTickCount64() >= deadline) { headers(socket,400,0,"text/plain"); return; }
        const int got = recv(socket,buffer.data(),static_cast<int>(buffer.size()),0);
        if (got <= 0) return;
        request.append(buffer.data(),static_cast<std::size_t>(got));
    }
    if (request.size() > limit) { headers(socket,400,0,"text/plain"); return; }
    std::istringstream lines(request); std::string line, method, target, version, extra;
    std::getline(lines,line); std::istringstream first(line);
    first >> method >> target >> version;
    if ((first >> extra) || (version != "HTTP/1.1" && version != "HTTP/1.0")) { headers(socket,400,0,"text/plain"); return; }
    bool valid_host = false; int hosts = 0;
    while (std::getline(lines,line) && line != "\r") {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        const auto colon = line.find(':');
        if (colon == std::string::npos) { headers(socket,400,0,"text/plain"); return; }
        if (lower(line.substr(0,colon)) == "host") {
            auto host = lower(line.substr(colon+1));
            host.erase(0,host.find_first_not_of(" \t")); host.erase(host.find_last_not_of(" \t")+1);
            const auto suffix = ":" + std::to_string(port);
            valid_host = host == "127.0.0.1" + suffix || host == "localhost" + suffix ||
                (port == 80 && (host == "127.0.0.1" || host == "localhost")); ++hosts;
        }
    }
    if (!valid_host || hosts != 1) { headers(socket,400,0,"text/plain"); return; }
    if (method != "GET" && method != "HEAD") { headers(socket,405,0,"text/plain"); return; }
    fs::path relative;
    if (!safe_path(target,relative)) { headers(socket,404,0,"text/plain"); return; }
    fs::path file = root;
    std::error_code error;
    for (const auto& segment : relative) {
        file /= segment;
        const auto attrs = GetFileAttributesW(file.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) { headers(socket,404,0,"text/plain"); return; }
    }
    if (!fs::is_regular_file(file,error) || error) { headers(socket,404,0,"text/plain"); return; }
    const auto size = fs::file_size(file,error);
    std::ifstream input(file,std::ios::binary);
    if (error || !input) { headers(socket,404,0,"text/plain"); return; }
    headers(socket,200,size,mime(file));
    if (method == "HEAD") return;
    std::array<char,65536> bytes{};
    while (input) {
        input.read(bytes.data(),static_cast<std::streamsize>(bytes.size()));
        if (!send_all(socket,bytes.data(),static_cast<std::size_t>(input.gcount()))) break;
    }
}
}
int main(int argc, char** argv) {
    unsigned short port = 4173; bool browser = true;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--help") { std::cout << "Dungeon Architect portable host\n--port 0..65535 (default 4173; 0 selects a free port)\n--no-browser\nStop with Ctrl+C. Only packaged web/ is served.\n"; return 0; }
        if (arg == "--no-browser") { browser = false; continue; }
        if (arg == "--port" && i+1 < argc) {
            const std::string value = argv[++i];
            if (value.empty() || value.size() > 5 || value.find_first_not_of("0123456789") != std::string::npos || std::stoul(value) > 65535) { std::cerr << "Invalid port.\n"; return 2; }
            port = static_cast<unsigned short>(std::stoul(value)); continue;
        }
        std::cerr << "Unknown/incomplete option. Use --help.\n"; return 2;
    }
    std::array<wchar_t,32768> executable{};
    const DWORD length = GetModuleFileNameW(nullptr,executable.data(),static_cast<DWORD>(executable.size()));
    if (!length || length >= executable.size()) { std::cerr << "Cannot locate package.\n"; return 1; }
    const fs::path root = fs::path(executable.data()).parent_path()/"web";
    if (!fs::is_regular_file(root/"index.html") || (GetFileAttributesW(root.c_str()) & FILE_ATTRIBUTE_REPARSE_POINT)) { std::cerr << "Missing/unsafe packaged web/index.html beside launcher. Extract the complete archive.\n"; return 1; }
    WSADATA data{};
    if (WSAStartup(MAKEWORD(2,2),&data)) { std::cerr << "Winsock startup failed.\n"; return 1; }
    const SOCKET listener = socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);
    BOOL exclusive = TRUE;
    setsockopt(listener,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof(exclusive));
    sockaddr_in address{}; address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = htons(port);
    if (listener == INVALID_SOCKET || bind(listener,reinterpret_cast<sockaddr*>(&address),sizeof(address)) || listen(listener,SOMAXCONN)) {
        std::cerr << "Cannot bind loopback port " << port << " (Winsock " << WSAGetLastError() << "). Close the other host or use --port 0.\n";
        if (listener != INVALID_SOCKET) closesocket(listener);
        WSACleanup(); return 1;
    }
    int address_size = sizeof(address); getsockname(listener,reinterpret_cast<sockaddr*>(&address),&address_size); port = ntohs(address.sin_port);
    SetConsoleCtrlHandler(interrupt,TRUE);
    const std::string url = "http://127.0.0.1:" + std::to_string(port) + "/";
    std::cout << "Dungeon Architect: " << url << "\nKeep this window open; Ctrl+C stops the local host.\n" << std::flush;
    if (browser && reinterpret_cast<INT_PTR>(ShellExecuteA(nullptr,"open",url.c_str(),nullptr,nullptr,SW_SHOWNORMAL)) <= 32) std::cerr << "Browser launch failed. Open the printed URL in Chrome.\n";
    while (!InterlockedCompareExchange(&stopping,0,0)) {
        fd_set readable; FD_ZERO(&readable); FD_SET(listener,&readable); timeval timeout{0,200000};
        if (select(0,&readable,nullptr,nullptr,&timeout) <= 0) continue;
        const SOCKET client = accept(listener,nullptr,nullptr);
        if (client == INVALID_SOCKET) continue;
        DWORD socket_timeout = 1000;
        setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,reinterpret_cast<const char*>(&socket_timeout),sizeof(socket_timeout));
        setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,reinterpret_cast<const char*>(&socket_timeout),sizeof(socket_timeout));
        try { serve(client,root,port); } catch (...) { headers(client,400,0,"text/plain"); }
        shutdown(client,SD_BOTH); closesocket(client);
    }
    closesocket(listener); WSACleanup(); return 0;
}

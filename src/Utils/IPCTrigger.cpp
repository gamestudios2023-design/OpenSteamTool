#include "dllmain.h"
#include "IPCTrigger.h"
#include "LuaConfig.h"
#include "Log.h"
#include "Config.h"
#include "Hook/Hooks_Package.h"
#include <thread>
#include <atomic>
#include <shellapi.h>

#pragma comment(lib, "shell32.lib")

namespace IPCTrigger {
    static std::atomic<bool> g_running{false};
    static std::thread g_serverThread;

    static const char* PIPE_NAME = R"(\\.\pipe\OpenSteamTool_Trigger)";

    enum class Command : uint32_t {
        FullReload = 1,
        AppIdReload = 2,
        Shutdown = 3,
    };

    struct Packet {
        Command cmd;
        uint32_t payloadSize;
    };

    static void TriggerSteamUIRefresh() {
        LOG_INFO("[IPCTrigger] Triggering Steam UI refresh (offline)");
        ShellExecuteA(nullptr, "open", "steam://open/gooffline", nullptr, nullptr, SW_HIDE);
        std::this_thread::sleep_for(std::chrono::seconds(1));
        LOG_INFO("[IPCTrigger] Triggering Steam UI refresh (online)");
        ShellExecuteA(nullptr, "open", "steam://open/goonline", nullptr, nullptr, SW_HIDE);
    }

    static void ServerThread() {
        while (g_running) {
            HANDLE pipe = CreateNamedPipeA(
                PIPE_NAME,
                PIPE_ACCESS_DUPLEX,
                PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
                1,
                4096,
                4096,
                1000,
                nullptr
            );

            if (!pipe || pipe == INVALID_HANDLE_VALUE) {
                std::this_thread::sleep_for(std::chrono::milliseconds(500));
                continue;
            }

            BOOL connected = ConnectNamedPipe(pipe, nullptr) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
            if (!connected) {
                CloseHandle(pipe);
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
                continue;
            }

            Packet packet{};
            DWORD bytesRead = 0;

            if (ReadFile(pipe, &packet, sizeof(packet), &bytesRead, nullptr)) {
                if (packet.cmd == Command::FullReload) {
                    LOG_INFO("[IPCTrigger] FullReload command received");
                    if (!Config::luaPaths.empty()) {
                        LuaConfig::ParseDirectory(Config::luaPaths[0], true);
                        for (size_t i = 1; i < Config::luaPaths.size(); ++i) {
                            LuaConfig::ParseDirectory(Config::luaPaths[i], false);
                        }
                    } else {
                        LuaConfig::ParseDirectory(std::string(LuaDir), true);
                    }
                    Hooks_Package::RefreshPackage0();
                    TriggerSteamUIRefresh();
                    LOG_INFO("[IPCTrigger] FullReload completed");
                }
                else if (packet.cmd == Command::AppIdReload) {
                    std::vector<AppId_t> appIds;
                    if (packet.payloadSize > 0) {
                        std::vector<uint8_t> buffer(packet.payloadSize);
                        DWORD bytesReadPayload = 0;
                        if (ReadFile(pipe, buffer.data(), packet.payloadSize, &bytesReadPayload, nullptr)) {
                            const uint32_t* data = reinterpret_cast<const uint32_t*>(buffer.data());
                            uint32_t count = packet.payloadSize / sizeof(uint32_t);
                            appIds.assign(data, data + count);
                        }
                    }
                    LOG_INFO("[IPCTrigger] AppIdReload: {} ids", (uint32_t)appIds.size());
                    for (AppId_t appId : appIds) {
                        LOG_INFO("[IPCTrigger]   - {}", appId);
                    }
                    LuaConfig::RefreshAppIds(appIds);
                    Hooks_Package::RefreshPackage0();
                    TriggerSteamUIRefresh();
                    LOG_INFO("[IPCTrigger] AppIdReload completed");
                }
                else if (packet.cmd == Command::Shutdown) {
                    LOG_INFO("[IPCTrigger] Shutdown command received");
                    g_running = false;
                }
            }

            FlushFileBuffers(pipe);
            DisconnectNamedPipe(pipe);
            CloseHandle(pipe);
        }

        LOG_INFO("[IPCTrigger] Server thread exiting");
    }

    bool StartServer() {
        if (g_running.exchange(true)) {
            LOG_WARN("[IPCTrigger] Server already running");
            return false;
        }

        g_serverThread = std::thread(ServerThread);
        LOG_INFO("[IPCTrigger] Server started on {}", PIPE_NAME);
        return true;
    }

    void StopServer() {
        g_running = false;
        if (g_serverThread.joinable()) {
            g_serverThread.join();
        }
        LOG_INFO("[IPCTrigger] Server stopped");
    }

    void TriggerFullReload() {
        LOG_INFO("[IPCTrigger] TriggerFullReload called");
        if (!Config::luaPaths.empty()) {
            LuaConfig::ParseDirectory(Config::luaPaths[0], true);
            for (size_t i = 1; i < Config::luaPaths.size(); ++i) {
                LuaConfig::ParseDirectory(Config::luaPaths[i], false);
            }
        } else {
            LuaConfig::ParseDirectory(std::string(LuaDir), true);
        }
        Hooks_Package::RefreshPackage0();
        TriggerSteamUIRefresh();
    }

    void TriggerAppIdReload(const std::vector<AppId_t>& appIds) {
        LOG_INFO("[IPCTrigger] TriggerAppIdReload called for {} appIds", (uint32_t)appIds.size());
        LuaConfig::RefreshAppIds(appIds);
        Hooks_Package::RefreshPackage0();
        TriggerSteamUIRefresh();
    }
}
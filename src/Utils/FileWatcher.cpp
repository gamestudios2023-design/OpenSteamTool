#include "dllmain.h"
#include "FileWatcher.h"
#include "LuaConfig.h"
#include "Hook/Hooks_Package.h"
#include "Log.h"
#include <thread>
#include <atomic>
#include <shellapi.h>
#include <vector>
#include <string>

#pragma comment(lib, "shell32.lib")

namespace FileWatcher {
    static std::atomic<bool> g_running{false};
    static std::thread g_watcherThread;
    static std::vector<std::string> g_watchDirs;

    static const DWORD kDebounceMs = 500;

    static std::string WideToString(const std::wstring& wstr) {
        std::string result;
        result.reserve(wstr.size());
        for (wchar_t c : wstr) {
            result.push_back(static_cast<char>(c));
        }
        return result;
    }

    static void TriggerRefresh() {
        LOG_INFO("[FileWatcher] Detected change, triggering refresh after {}ms debounce", kDebounceMs);
        std::this_thread::sleep_for(std::chrono::milliseconds(kDebounceMs));

        LuaConfig::ParseDirectory(g_watchDirs[0], true);
        for (size_t i = 1; i < g_watchDirs.size(); ++i) {
            LuaConfig::ParseDirectory(g_watchDirs[i], false);
        }
        Hooks_Package::RefreshPackage0();

        LOG_INFO("[FileWatcher] Triggering Steam UI refresh (offline)");
        ShellExecuteA(nullptr, "open", "steam://open/gooffline", nullptr, nullptr, SW_HIDE);
        std::this_thread::sleep_for(std::chrono::seconds(1));
        LOG_INFO("[FileWatcher] Triggering Steam UI refresh (online)");
        ShellExecuteA(nullptr, "open", "steam://open/goonline", nullptr, nullptr, SW_HIDE);
        LOG_INFO("[FileWatcher] Refresh completed");
    }

    static bool HasLuaChange(const char* buffer, DWORD bytesReturned) {
        FILE_NOTIFY_INFORMATION* info = reinterpret_cast<FILE_NOTIFY_INFORMATION*>(const_cast<char*>(buffer));
        while (info) {
            std::wstring fname(info->FileName, info->FileNameLength / sizeof(wchar_t));
            std::string name = WideToString(fname);

            if (name.size() > 4 && name.substr(name.size() - 4) == ".lua") {
                LOG_INFO("[FileWatcher] Lua file changed: {}", name);
                return true;
            }

            if (info->NextEntryOffset == 0) break;
            info = reinterpret_cast<FILE_NOTIFY_INFORMATION*>(
                reinterpret_cast<char*>(info) + info->NextEntryOffset
            );
        }
        return false;
    }

    static void WatcherThread() {
        g_running = true;

        const size_t numDirs = g_watchDirs.size();
        std::vector<HANDLE> dirHandles(numDirs);
        std::vector<OVERLAPPED> overlapped(numDirs);
        std::vector<HANDLE> events(numDirs);
        std::vector<std::vector<char>> buffers(numDirs);
        std::vector<bool> hasChange(numDirs, false);

        for (size_t i = 0; i < numDirs; ++i) {
            events[i] = CreateEventA(nullptr, FALSE, FALSE, nullptr);
            overlapped[i] = {};
            overlapped[i].hEvent = events[i];
            buffers[i].resize(65536);

            dirHandles[i] = CreateFileA(
                g_watchDirs[i].c_str(),
                FILE_LIST_DIRECTORY,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                nullptr,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
                nullptr
            );

            if (dirHandles[i] == INVALID_HANDLE_VALUE) {
                LOG_WARN("[FileWatcher] Failed to open directory: {} (err={})", g_watchDirs[i], GetLastError());
                dirHandles[i] = nullptr;
                continue;
            }

            LOG_INFO("[FileWatcher] Started watching: {}", g_watchDirs[i]);
        }

        bool allFailed = true;
        for (auto& h : dirHandles) {
            if (h) { allFailed = false; break; }
        }
        if (allFailed) {
            LOG_WARN("[FileWatcher] No directories could be opened");
            for (auto& e : events) if (e) CloseHandle(e);
            return;
        }

        while (g_running) {
            for (size_t i = 0; i < numDirs; ++i) {
                if (!dirHandles[i]) continue;

                DWORD bytesReturned = 0;
                BOOL success = ReadDirectoryChangesW(
                    dirHandles[i],
                    buffers[i].data(),
                    static_cast<DWORD>(buffers[i].size()),
                    FALSE,
                    FILE_NOTIFY_CHANGE_FILE_NAME |
                    FILE_NOTIFY_CHANGE_LAST_WRITE |
                    FILE_NOTIFY_CHANGE_CREATION,
                    &bytesReturned,
                    &overlapped[i],
                    nullptr
                );

                if (!success) {
                    LOG_WARN("[FileWatcher] ReadDirectoryChangesW failed for {}: {}", g_watchDirs[i], GetLastError());
                }
            }

            DWORD waitResult = WaitForMultipleObjects(static_cast<DWORD>(numDirs), events.data(), FALSE, 1000);

            if (!g_running) break;

            if (waitResult == WAIT_TIMEOUT) continue;

            if (waitResult >= WAIT_OBJECT_0 && waitResult < WAIT_OBJECT_0 + numDirs) {
                size_t idx = waitResult - WAIT_OBJECT_0;
                if (dirHandles[idx]) {
                    DWORD bytesReturned = 0;
                    if (GetOverlappedResult(dirHandles[idx], &overlapped[idx], &bytesReturned, FALSE)) {
                        if (HasLuaChange(buffers[idx].data(), bytesReturned)) {
                            TriggerRefresh();
                        }
                    }
                    ResetEvent(events[idx]);
                }
            }
        }

        for (auto& h : dirHandles) if (h) CloseHandle(h);
        for (auto& e : events) if (e) CloseHandle(e);
        LOG_INFO("[FileWatcher] Stopped");
    }

    void Start(const std::vector<std::string>& directories) {
        if (g_running.exchange(true)) {
            LOG_WARN("[FileWatcher] Already running");
            return;
        }

        g_watchDirs = directories;
        g_watcherThread = std::thread(WatcherThread);
    }

    void Stop() {
        if (!g_running) return;
        g_running = false;
        if (g_watcherThread.joinable()) {
            g_watcherThread.join();
        }
    }
}
#include "Hooks_Manifest.h"
#include "HookMacros.h"
#include "dllmain.h"
#include <winhttp.h>
#include <charconv>
#include <mutex>
#include <unordered_map>

#pragma comment(lib, "winhttp.lib")

namespace {
    // manifest_gid -> request_code, populated lazily on first miss.
    std::mutex                              g_cacheMu;
    std::unordered_map<uint64, uint64>      g_codeCache;
    std::unordered_map<uint64, bool>        g_negativeCache;  // remembers known-bad gids

    // Connect 5s, send/receive 10s. Anything beyond this and we'd rather
    // fall through to the original (which Steam will then surface as a
    // user-visible error) than block a UI thread.
    constexpr DWORD kTimeoutResolveMs = 5000;
    constexpr DWORD kTimeoutConnectMs = 5000;
    constexpr DWORD kTimeoutSendMs    = 10000;
    constexpr DWORD kTimeoutRecvMs    = 10000;

    bool FetchManifestRequestCode(uint64 manifest_gid, uint64* outRequestCode) {
        HINTERNET hSession = WinHttpOpen(L"OpenSteamTool/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        if (!hSession) return false;

        WinHttpSetTimeouts(hSession,
            kTimeoutResolveMs, kTimeoutConnectMs, kTimeoutSendMs, kTimeoutRecvMs);

        bool ok = false;
        HINTERNET hConnect = WinHttpConnect(hSession, L"manifest.steam.run",
            INTERNET_DEFAULT_HTTPS_PORT, 0);
        if (hConnect) {
            wchar_t path[128];
            swprintf_s(path, L"/api/manifest/%llu", manifest_gid);

            HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", path,
                nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                WINHTTP_FLAG_SECURE);
            if (hRequest) {
                if (WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                        WINHTTP_NO_REQUEST_DATA, 0, 0, 0)
                    && WinHttpReceiveResponse(hRequest, nullptr)) {

                    DWORD statusCode = 0, statusSize = sizeof(statusCode);
                    WinHttpQueryHeaders(hRequest,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &statusSize,
                        WINHTTP_NO_HEADER_INDEX);
                    LOG_DEBUG("Manifest request status={} gid={}", statusCode, manifest_gid);
                    if (statusCode == 200) {
                        std::string body;
                        DWORD avail = 0;
                        while (WinHttpQueryDataAvailable(hRequest, &avail) && avail) {
                            size_t off = body.size();
                            body.resize(off + avail);
                            DWORD read = 0;
                            if (!WinHttpReadData(hRequest, body.data() + off, avail, &read)) break;
                            body.resize(off + read);
                            if (body.size() > 64 * 1024) break;
                        }
                        // Response shape: {"content":"1666836470726104466"}
                        if (size_t key = body.find("\"content\""); key != std::string::npos) {
                            if (size_t q1 = body.find('"', key + 9); q1 != std::string::npos) {
                                if (size_t q2 = body.find('"', q1 + 1); q2 != std::string::npos) {
                                    uint64 code = 0;
                                    auto [_, ec] = std::from_chars(
                                        body.data() + q1 + 1, body.data() + q2, code);
                                    if (ec == std::errc{}) {
                                        *outRequestCode = code;
                                        ok = true;
                                    }
                                }
                            }
                        }
                    }
                }
                WinHttpCloseHandle(hRequest);
            }
            WinHttpCloseHandle(hConnect);
        }
        WinHttpCloseHandle(hSession);
        return ok;
    }

    bool ResolveCached(uint64 manifest_gid, uint64* outRequestCode) {
        {
            std::lock_guard lock(g_cacheMu);
            if (auto it = g_codeCache.find(manifest_gid); it != g_codeCache.end()) {
                *outRequestCode = it->second;
                return true;
            }
            if (g_negativeCache.count(manifest_gid)) return false;
        }

        uint64 code = 0;
        bool ok = FetchManifestRequestCode(manifest_gid, &code);

        std::lock_guard lock(g_cacheMu);
        if (ok) {
            g_codeCache[manifest_gid] = code;
            *outRequestCode = code;
        } else {
            g_negativeCache[manifest_gid] = true;
        }
        return ok;
    }

    HOOK_FUNC(GetManifestRequestCode, EResult, void* pObject, AppId_t AppId, AppId_t DepotId,
              uint64 manifest_gid, const char* branch, uint64* outRequestCode) {
        if (LuaConfig::HasDepot(DepotId)) {
            if (ResolveCached(manifest_gid, outRequestCode))
                return k_EResultOK;
        }
        return oGetManifestRequestCode(pObject, AppId, DepotId, manifest_gid, branch, outRequestCode);
    }
}

namespace Hooks_Manifest {
    void Install() {
        HOOK_BEGIN();
        INSTALL_HOOK_D(GetManifestRequestCode);
        HOOK_END();
    }

    void Uninstall() {
        UNHOOK_BEGIN();
        UNINSTALL_HOOK(GetManifestRequestCode);
        UNHOOK_END();

        std::lock_guard lock(g_cacheMu);
        g_codeCache.clear();
        g_negativeCache.clear();
    }
}

#include "dllmain.h"
#include "HookManager.h"

#include <detours.h>
#include <winhttp.h>
#include <charconv>

#pragma comment(lib, "winhttp.lib")


namespace SteamUI {
    using LoadModuleWithPath_t = HMODULE(*)(const char* inputPath, bool flags);
    static LoadModuleWithPath_t oLoadModuleWithPath = nullptr;

    HMODULE __fastcall hkLoadModuleWithPath(const char* inputPath, bool flags) {
        // Always call the original function first.
        HMODULE hModule = oLoadModuleWithPath(inputPath, flags);
        if (!strcmp(inputPath, "steamclient64.dll")) {
            // Replace the return module with our diversion module.
            hModule = diversion_hMdoule;
        }
        return hModule;
    }

    void CoreHook() {
        void* target = ByteSearch(GetModuleHandleA("steamui.dll"), LoadModuleWithPathPattern, LoadModuleWithPathMask);
        if (!target) {
            return;
        }
        oLoadModuleWithPath = reinterpret_cast<LoadModuleWithPath_t>(target);

        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        DetourAttach(reinterpret_cast<PVOID*>(&oLoadModuleWithPath),
                     reinterpret_cast<PVOID>(&hkLoadModuleWithPath));
        DetourTransactionCommit();
    }

    void CoreUnhook() {
        if (!oLoadModuleWithPath) {
            return;
        }
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        DetourDetach(reinterpret_cast<PVOID*>(&oLoadModuleWithPath),
                     reinterpret_cast<PVOID>(&hkLoadModuleWithPath));
        DetourTransactionCommit();
        oLoadModuleWithPath = nullptr;
    }
}

namespace SteamClient {
    
    using CUtlMemoryGrow_t              =           void*(*)(CUtlVector<uint32>* pVec, int grow_size);
    using LoadPackage_t                 =           bool(*)(PackageInfo*, uint8*, int, void*);
    using CheckAppOwnership_t           =           bool(*)(void*, AppId_t, AppOwnership*);
    using GetDecryptionKey_t            =           EResult(*)(void*,uint32,AppId_t,CUtlBuffer*);
    using LoadDepotDecryptionKey_t		=		    int32(*)(void*, uint32, char*, char*, uint32);
    using GetManifestRequestCode_t      =           EResult(*)(void*, AppId_t, AppId_t,uint64,const char*, uint64*);

    static CUtlMemoryGrow_t    oCUtlMemoryGrow    = nullptr;
    static LoadPackage_t       oLoadPackage       = nullptr;
    static CheckAppOwnership_t oCheckAppOwnership = nullptr;
    static GetDecryptionKey_t  oGetDecryptionKey  = nullptr;
    static LoadDepotDecryptionKey_t oLoadDepotDecryptionKey = nullptr;
    static GetManifestRequestCode_t oGetManifestRequestCode = nullptr;

    bool __fastcall hkLoadPackage(PackageInfo* pPackageInfo, uint8* SHA_1_Hash, int ChangeNumber, void* p4) {
        bool result = oLoadPackage(pPackageInfo, SHA_1_Hash, ChangeNumber, p4);
        if (pPackageInfo->PackageId == 0) {
            // Insert Fake Game And Depot Into PackageInfo whose PackageId is 0
            std::vector<AppId_t> AddAppIdVector = LuaConfig::GetAllDepotIds();
            if (!AddAppIdVector.empty()) {
                uint32 oldSize = pPackageInfo->AppIdVec.m_Size;
                uint32 numToAdd = (uint32)AddAppIdVector.size();
                oCUtlMemoryGrow(&pPackageInfo->AppIdVec, numToAdd);
                for (uint32 i = 0; i < numToAdd; i++) {
                    pPackageInfo->AppIdVec.m_Memory.m_pMemory[oldSize + i] = AddAppIdVector[i];
                }
            }
        }
        return result;
    }

    bool __fastcall hkCheckAppOwnership(void* pObject, AppId_t AppId, AppOwnership* pOwnershipInfo) {
        bool result = oCheckAppOwnership(pObject, AppId, pOwnershipInfo);
        if (LuaConfig::HasDepot(AppId)) {
            pOwnershipInfo->PackageId = 0;
            pOwnershipInfo->ReleaseState = EAppReleaseState::Released;
            pOwnershipInfo->GameIDType = EGameIDType::k_EGameIDTypeApp;
            return true;
        }
        return result;
    }

    int32 __fastcall hkLoadDepotDecryptionKey(void* pObject, uint32 foo, char* KeyName, char* Key, uint32 KeySize)
    {
        std::string str_KeyName = std::string(KeyName);
        // Check if the KeyName contains the pattern "\DecryptionKey" and extract the DepotId.
        if (std::size_t last_slash = str_KeyName.find("\\DecryptionKey");last_slash != std::string::npos) {
            if (std::size_t start_pos = str_KeyName.find_last_of("\\", last_slash - 1);start_pos != std::string::npos) {
                // Extract DepotId
                AppId_t DepotId = std::stoul(str_KeyName.substr(start_pos + 1, last_slash - start_pos - 1));
                // Try to get the decryption key from LuaConfig using the extracted DepotId.
                if (const auto& DecryptionKey = LuaConfig::GetDecryptionKey(DepotId);!DecryptionKey.empty())
                {
                    // If a key is found, copy it to the provided buffer and return the key size.
                    if (KeySize >= DecryptionKey.size()) {
                        memcpy(Key, DecryptionKey.data(), DecryptionKey.size());
                        return DecryptionKey.size();
                    }
                    return 0;
                }
            }

        }
        return oLoadDepotDecryptionKey(pObject, foo, KeyName, Key, KeySize);
    }

    static bool FetchManifestRequestCode(uint64 manifest_gid, uint64* outRequestCode) {
        HINTERNET hSession = WinHttpOpen(L"OpenSteamTool/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        if (!hSession) return false;

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

                        // Response: {"content":"1666836470726104466"}
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

    // Thanks to RoGoing for providing manifest request code
    // https://manifest.steam.run/api/manifest/8329114521995004621
    EResult __fastcall hkGetManifestRequestCode(void* pObject, AppId_t AppId, AppId_t DepotId, uint64 manifest_gid, const char* branch, uint64* outRequestCode) {
        if (LuaConfig::HasDepot(DepotId)) {
            if (FetchManifestRequestCode(manifest_gid, outRequestCode)) {
                return k_EResultOK;
            }
        }
        return oGetManifestRequestCode(pObject, AppId, DepotId, manifest_gid, branch, outRequestCode);
    }

    void CoreHook() {
        // Resolve CUtlMemoryGrow (called directly, not hooked).
        oCUtlMemoryGrow = reinterpret_cast<CUtlMemoryGrow_t>(ByteSearch(diversion_hMdoule, CUtlMemoryGrowPattern, CUtlMemoryGrowMask));

        void* loadPackageTarget       = ByteSearch(diversion_hMdoule, LoadPackagePattern, LoadPackageMask);
        void* checkAppOwnershipTarget = ByteSearch(diversion_hMdoule, CheckAppOwnershipPattern, CheckAppOwnershipMask);
        void* loadDepotDecryptionKeyTarget  = ByteSearch(diversion_hMdoule, LoadDepotDecryptionKeyPattern, LoadDepotDecryptionKeyMask);
        void* getManifestRequestCodeTarget = ByteSearch(diversion_hMdoule, GetManifestRequestCodePattern, GetManifestRequestCodeMask);

        oLoadPackage       = reinterpret_cast<LoadPackage_t>(loadPackageTarget);
        oCheckAppOwnership = reinterpret_cast<CheckAppOwnership_t>(checkAppOwnershipTarget);
        oLoadDepotDecryptionKey  = reinterpret_cast<LoadDepotDecryptionKey_t>(loadDepotDecryptionKeyTarget);
        oGetManifestRequestCode = reinterpret_cast<GetManifestRequestCode_t>(getManifestRequestCodeTarget);

        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        if (loadPackageTarget) {
            DetourAttach(reinterpret_cast<PVOID*>(&oLoadPackage),
                         reinterpret_cast<PVOID>(&hkLoadPackage));
        }
        if (checkAppOwnershipTarget) {
            DetourAttach(reinterpret_cast<PVOID*>(&oCheckAppOwnership),
                         reinterpret_cast<PVOID>(&hkCheckAppOwnership));
        }
        if (loadDepotDecryptionKeyTarget) {
            DetourAttach(reinterpret_cast<PVOID*>(&oLoadDepotDecryptionKey),
                         reinterpret_cast<PVOID>(&hkLoadDepotDecryptionKey));
        }
        if (getManifestRequestCodeTarget) {
            DetourAttach(reinterpret_cast<PVOID*>(&oGetManifestRequestCode),
                        reinterpret_cast<PVOID>(&hkGetManifestRequestCode));
        }
        DetourTransactionCommit();
    }

    void CoreUnhook() {
        DetourTransactionBegin();
        DetourUpdateThread(GetCurrentThread());
        if (oLoadPackage) {
            DetourDetach(reinterpret_cast<PVOID*>(&oLoadPackage),
                         reinterpret_cast<PVOID>(&hkLoadPackage));
        }
        if (oCheckAppOwnership) {
            DetourDetach(reinterpret_cast<PVOID*>(&oCheckAppOwnership),
                         reinterpret_cast<PVOID>(&hkCheckAppOwnership));
        }
        if (oLoadDepotDecryptionKey) {
            DetourDetach(reinterpret_cast<PVOID*>(&oLoadDepotDecryptionKey),
                         reinterpret_cast<PVOID>(&hkLoadDepotDecryptionKey));
        }
        if (oGetManifestRequestCode) {
            DetourDetach(reinterpret_cast<PVOID*>(&oGetManifestRequestCode),
                        reinterpret_cast<PVOID>(&hkGetManifestRequestCode));
        }
        DetourTransactionCommit();

        oLoadPackage       = nullptr;
        oCheckAppOwnership = nullptr;
        oLoadDepotDecryptionKey  = nullptr;
        oGetManifestRequestCode = nullptr;
    }
}

#include "Hooks_Package.h"
#include "HookMacros.h"
#include "dllmain.h"

namespace {
    using CUtlMemoryGrow_t = void* (*)(CUtlVector<uint32>* pVec, int grow_size);
    CUtlMemoryGrow_t oCUtlMemoryGrow = nullptr;

    PackageInfo* g_package0 = nullptr;

    HOOK_FUNC(LoadPackage, bool, PackageInfo* pInfo, uint8* sha1, int32 cn, void* p4) {
        bool result = oLoadPackage(pInfo, sha1, cn, p4);

        if (pInfo->PackageId == 0) {
            if (!g_package0) {
                g_package0 = pInfo;
                LOG_INFO("LoadPackage: captured Package0 pointer");
            }

            std::vector<AppId_t> appIds = LuaConfig::GetAllDepotIds();
            if (!appIds.empty()) {
                uint32 oldSize = pInfo->AppIdVec.m_Size;
                uint32 numToAdd = static_cast<uint32>(appIds.size());
                LOG_INFO("LoadPackage(PackageId=0): adding {} apps, oldSize={}", numToAdd, oldSize);
                oCUtlMemoryGrow(&pInfo->AppIdVec, numToAdd);
                for (uint32 i = 0; i < numToAdd; i++)
                    pInfo->AppIdVec.m_Memory.m_pMemory[oldSize + i] = appIds[i];
            }
        }

        return result;
    }

    HOOK_FUNC(CheckAppOwnership, bool, void* pObj, AppId_t appId, AppOwnership* pOwn) {
        bool result = oCheckAppOwnership(pObj, appId, pOwn);
        if (LuaConfig::HasDepot(appId)) {
            if (result && pOwn->ExistInPackageNums > 1) {
                // Actually owned — record so HasDepot excludes it going forward
                LuaConfig::MarkOwned(appId);
            } else {
                pOwn->PackageId    = 0;
                pOwn->ReleaseState = EAppReleaseState::Released;
                pOwn->GameIDType   = EGameIDType::k_EGameIDTypeApp;
                return true;
            }
        }
        return result;
    }
}

namespace Hooks_Package {
    void RefreshPackage0() {
        if (!g_package0) {
            LOG_WARN("RefreshPackage0: no Package0 pointer captured yet");
            return;
        }

        std::vector<AppId_t> allIds = LuaConfig::GetAllDepotIds();
        uint32 currentSize = g_package0->AppIdVec.m_Size;

        std::vector<AppId_t> newIds;
        std::vector<AppId_t> removedIds;

        for (uint32 i = 0; i < currentSize; i++) {
            AppId_t existingId = g_package0->AppIdVec.m_Memory.m_pMemory[i];
            bool found = false;
            for (AppId_t id : allIds) {
                if (id == existingId) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                removedIds.push_back(existingId);
            }
        }

        for (AppId_t id : allIds) {
            bool found = false;
            for (uint32 i = 0; i < currentSize; i++) {
                if (g_package0->AppIdVec.m_Memory.m_pMemory[i] == id) {
                    found = true;
                    break;
                }
            }
            if (!found) newIds.push_back(id);
        }

        if (!removedIds.empty()) {
            LOG_INFO("RefreshPackage0: removing {} apps from Package0", (uint32_t)removedIds.size());
            for (AppId_t id : removedIds) {
                LOG_INFO("RefreshPackage0:   - removing {}", id);
            }
            uint32 writeIdx = 0;
            for (uint32 i = 0; i < currentSize; i++) {
                AppId_t id = g_package0->AppIdVec.m_Memory.m_pMemory[i];
                bool shouldRemove = false;
                for (AppId_t remId : removedIds) {
                    if (remId == id) {
                        shouldRemove = true;
                        break;
                    }
                }
                if (!shouldRemove) {
                    g_package0->AppIdVec.m_Memory.m_pMemory[writeIdx] = id;
                    writeIdx++;
                }
            }
            g_package0->AppIdVec.m_Size = writeIdx;
            currentSize = writeIdx;
        }

        if (!newIds.empty()) {
            LOG_INFO("RefreshPackage0: adding {} new apps to Package0 (current size={})",
                     (uint32_t)newIds.size(), currentSize);
            oCUtlMemoryGrow(&g_package0->AppIdVec, static_cast<int>(newIds.size()));
            for (size_t i = 0; i < newIds.size(); i++) {
                g_package0->AppIdVec.m_Memory.m_pMemory[currentSize + i] = newIds[i];
            }
            g_package0->AppIdVec.m_Size = currentSize + static_cast<uint32>(newIds.size());
        }

        LOG_INFO("RefreshPackage0: Package0 AppIdVec now size={}",
                 g_package0->AppIdVec.m_Size);
    }

    void Install() {
        RESOLVE_D(CUtlMemoryGrow);

        HOOK_BEGIN();
        INSTALL_HOOK_D(LoadPackage);
        INSTALL_HOOK_D(CheckAppOwnership);
        HOOK_END();
    }

    void Uninstall() {
        UNHOOK_BEGIN();
        UNINSTALL_HOOK(LoadPackage);
        UNINSTALL_HOOK(CheckAppOwnership);
        UNHOOK_END();
        oCUtlMemoryGrow = nullptr;
        g_package0 = nullptr;
    }
}

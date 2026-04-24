#include "dllmain.h"
#include "HookManager.h"


namespace SteamUI {
    using LoadModuleWithPath_t = HMODULE(*)(const char* inputPath, bool flags);
    LoadModuleWithPath_t oLoadModuleWithPath = nullptr;

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
        if (target) {
            if (MH_CreateHook(target, &hkLoadModuleWithPath, reinterpret_cast<void**>(&oLoadModuleWithPath)) == MH_OK) {
                MH_EnableHook(target);
            }
        }
    }
}

namespace SteamClient {
    using LoadPackage_t					=		bool(*)(PackageInfo*, uint8*, int, void*);
    LoadPackage_t oLoadPackage = nullptr;
    using CheckAppOwnership_t			=		bool(*)(void*, AppId_t, AppOwnership*);
    CheckAppOwnership_t oCheckAppOwnership = nullptr;
    using CUtlMemoryGrow_t				=		void*(*)(CUtlVector<uint32>* pVec, int grow_size);
    CUtlMemoryGrow_t oCUtlMemoryGrow = nullptr;

    bool __fastcall hkLoadPackage(PackageInfo* pPackageInfo, uint8* SHA_1_Hash, int ChangeNumber, void* p4) {
        bool result = oLoadPackage(pPackageInfo, SHA_1_Hash, ChangeNumber, p4);
        if(pPackageInfo->PackageId == 0){
            // Insert Fake Game And Depot Into PackageInfo whose PackageId is 0
            std::vector<AppId_t> AddAppIdVector = LuaConfig::GetAllDepotIds();
            if (!AddAppIdVector.empty()) {
                uint32 oldSize = pPackageInfo->AppIdVec.m_Size;
                uint32 numToAdd = (uint32)AddAppIdVector.size();
                oCUtlMemoryGrow(&pPackageInfo->AppIdVec, numToAdd);
                for (uint32 i = 0; i < numToAdd; i++) {
                    pPackageInfo->AppIdVec.m_pMemory[oldSize + i] = AddAppIdVector[i];
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

    void CoreHook() {
        // find CUtlMemoryGrow 
        oCUtlMemoryGrow = reinterpret_cast<CUtlMemoryGrow_t>(ByteSearch(diversion_hMdoule, CUtlMemoryGrowPattern, CUtlMemoryGrowMask));

        // hook LoadPackage
        void* target = ByteSearch(diversion_hMdoule, LoadPackagePattern, LoadPackageMask);
        if (target) {
            if (MH_CreateHook(target, &hkLoadPackage, reinterpret_cast<void**>(&oLoadPackage)) == MH_OK) {
                MH_EnableHook(target);
            }
        }

        // hook CheckAppOwnership
        target = ByteSearch(diversion_hMdoule, CheckAppOwnershipPattern, CheckAppOwnershipMask);
        if (target) {
            if (MH_CreateHook(target, &hkCheckAppOwnership, reinterpret_cast<void**>(&oCheckAppOwnership)) == MH_OK) {
                MH_EnableHook(target);
            }
        }

    }

}


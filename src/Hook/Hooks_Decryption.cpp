#include "Hooks_Decryption.h"
#include "HookMacros.h"
#include "dllmain.h"
#include <string>

namespace {
    HOOK_FUNC(LoadDepotDecryptionKey, int32, void* pObject, uint32 foo,char* KeyName, char* Key, uint32 KeySize) {
        std::string name(KeyName);
        // Expected shape: ".../<DepotId>\DecryptionKey"
        if (size_t last = name.find("\\DecryptionKey"); last != std::string::npos) {
            if (size_t start = name.find_last_of("\\", last - 1); start != std::string::npos) {
                AppId_t depotId = std::stoul(name.substr(start + 1, last - start - 1));
                if (const auto& key = LuaConfig::GetDecryptionKey(depotId); !key.empty()) {
                    if (KeySize >= key.size()) {
                        memcpy(Key, key.data(), key.size());
                        return static_cast<int32>(key.size());
                    }
                    return 0;
                }
            }
        }
        return oLoadDepotDecryptionKey(pObject, foo, KeyName, Key, KeySize);
    }
}

namespace Hooks_Decryption {
    void Install() {
        HOOK_BEGIN();
        INSTALL_HOOK_D(LoadDepotDecryptionKey);
        HOOK_END();
    }

    void Uninstall() {
        UNHOOK_BEGIN();
        UNINSTALL_HOOK(LoadDepotDecryptionKey);
        UNHOOK_END();
    }
}

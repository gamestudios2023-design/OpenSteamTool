#pragma once

#include <vector>

namespace IPCTrigger {
    bool StartServer();
    void StopServer();
    void TriggerFullReload();
    void TriggerAppIdReload(const std::vector<AppId_t>& appIds);
}
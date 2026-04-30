#pragma once

#include "dllmain.h"

namespace AppTicket {
    // Reads the app ownership ticket cached by Steam under
    //   HKCU\Software\Valve\Steam\Apps\<AppId>\AppTicket  (REG_BINARY)
    // Returns an empty vector when no ticket is available.
    std::vector<uint8_t> GetAppOwnershipTicketFromRegistry(AppId_t appId);

    // Reads the encrypted app ticket cached by Steam under
    //   HKCU\Software\Valve\Steam\Apps\<AppId>\ETicket  (REG_BINARY)
    // Returns an empty vector when no ticket is available.
    std::vector<uint8_t> GetEncryptedTicketFromRegistry(AppId_t appId);

    //Get spoof steamID according to many factors
    uint64_t GetSpoofSteamID(AppId_t appId);
}
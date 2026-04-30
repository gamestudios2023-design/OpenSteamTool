#include "AppTicket.h"

namespace AppTicket {

    std::vector<uint8_t> GetAppOwnershipTicketFromRegistry(AppId_t appId) {
        LOG_TRACE("AppId={}", appId);
        std::vector<uint8_t> empty{};
        HKEY hKey;
        const std::string regPath = "Software\\Valve\\Steam\\Apps\\" + std::to_string(appId);
        if (RegOpenKeyExA(HKEY_CURRENT_USER, regPath.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
            return empty;
        }

        std::vector<uint8_t> value(1024);
        DWORD valueSize = static_cast<DWORD>(value.size());
        DWORD valueType = 0;
        if (RegQueryValueExA(hKey, "AppTicket", nullptr, &valueType,value.data(), &valueSize) != ERROR_SUCCESS
            || valueType != REG_BINARY) {
            RegCloseKey(hKey);
            return empty;
        }
        RegCloseKey(hKey);

        value.resize(valueSize);
        LOG_INFO("Successfully retrieved App Ownership Ticket from Registry, AppId: {}, Ticket Size: {}", appId, valueSize);
        return value;
    }


    std::vector<uint8_t> GetEncryptedTicketFromRegistry(AppId_t appId) {
        LOG_DEBUG("appid={}", appId);    
        std::vector<uint8_t> empty{};
        HKEY hKey;
        const std::string regPath = "Software\\Valve\\Steam\\Apps\\" + std::to_string(appId);
        if (RegOpenKeyExA(HKEY_CURRENT_USER, regPath.c_str(), 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
            return empty;
        }

        std::vector<uint8_t> value(1024);
        DWORD valueSize = static_cast<DWORD>(value.size());
        DWORD valueType = 0;
        if (RegQueryValueExA(hKey, "ETicket", nullptr, &valueType,value.data(), &valueSize) != ERROR_SUCCESS
            || valueType != REG_BINARY) {
            RegCloseKey(hKey);
            return empty;
        }
        RegCloseKey(hKey);

        value.resize(valueSize);
        LOG_INFO("Successfully retrieved Encrypted App Ticket from Registry, AppId: {}, Ticket Size: {}", appId, valueSize);
        return value;
    }

    uint64_t GetSpoofSteamID(AppId_t appId) {
        // This is a stub implementation. In the future, this could be extended to return different spoofed IDs based on various factors.
        // For now, it simply returns a fixed non-zero CSteamID to pass the DRM-check path.
        uint64_t SpoofSteamID = 0x110000100000001ULL; // Example non-zero CSteamID
        LOG_TRACE("GetSpoofSteamID for AppId {}: returning 0x{:X}", appId, SpoofSteamID);
        return SpoofSteamID;
    }
}

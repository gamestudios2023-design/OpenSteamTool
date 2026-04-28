#ifndef LUACONFIG_H
#define LUACONFIG_H

namespace LuaConfig{
    bool HasDepot(AppId_t appId);
    std::vector<AppId_t> GetAllDepotIds();
    std::vector<uint8> GetDecryptionKey(AppId_t appId);
    uint64_t GetAccessToken(AppId_t appId);
    bool pinApp(AppId_t appId); 
    void ParseDirectory(const std::string& directory);
}

#endif // LUACONFIG_H
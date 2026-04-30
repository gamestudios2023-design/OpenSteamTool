#ifndef LUACONFIG_H
#define LUACONFIG_H

namespace LuaConfig{
    bool HasDepot(AppId_t appId);
    std::vector<AppId_t> GetAllDepotIds();
    std::vector<uint8> GetDecryptionKey(AppId_t appId);
    uint64_t GetAccessToken(AppId_t appId);
    bool pinApp(AppId_t appId); 

    struct ManifestOverride {
          uint64_t gid;
          uint64_t size;
    };
    // depotId → {gid, size}
    const std::unordered_map<uint64_t, ManifestOverride>& GetManifestOverrides();
    
    void ParseDirectory(const std::string& directory);
}

#endif // LUACONFIG_H
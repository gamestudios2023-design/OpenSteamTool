#ifndef LUACONFIG_H
#define LUACONFIG_H

namespace LuaConfig{
    bool HasDepot(AppId_t appId);
    std::vector<AppId_t> GetAllDepotIds();
    void ParseDirectory(const std::string& directory);
}

#endif // LUACONFIG_H
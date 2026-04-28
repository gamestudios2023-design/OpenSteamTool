#include "dllmain.h"
#include "LuaConfig.h"
#include <lua.hpp>

extern "C" {
    struct lua_State;
}

namespace LuaConfig{
    static lua_State* g_lua_state = nullptr;
    std::unordered_map<AppId_t, std::string>DepotKeySet{};
    std::unordered_map<AppId_t, uint64_t>AccessTokenSet{};
    std::unordered_set<AppId_t> PinnedApps{};

    static int lua_addappid(lua_State* L) {
        // addappid(integer, integer, string)
        int argc = lua_gettop(L);
        // Validate argument count and required argument types.
        if (argc == 0) {
            return luaL_error(L, "");
        }
        if (!lua_isinteger(L, 1)) {
            return luaL_error(L, "");
        }

        // Read the first argument as app/depot id.
        lua_Integer value = lua_tointeger(L, 1);
        // Ensure the value fits into uint32_t range.
        if (value < 0 || value > UINT32_MAX)
            return luaL_error(L, "");
        AppId_t DepotId = (uint32_t)value;
        // Read the optional third argument as a key.
        std::string Key = "";
        if (argc > 2) {
            if (!lua_isstring(L, 3))
                return luaL_error(L, "");
            const char* key = lua_tostring(L, 3);
            // Keep only keys with exactly 64 characters.
            if (strlen(key) == 64) {
                Key = std::string(key);
            }
        }
        // Non-empty keys have priority over existing empty keys.
        if (!Key.empty() || !DepotKeySet.count(DepotId)) {
            DepotKeySet[DepotId] = Key;
        }

        return 0;
    }

    static int lua_addtoken(lua_State* L) {
        // addtoken(integer, string(uint64_t))
        int argc = lua_gettop(L);
        // Validate argument count and required argument types.
        if (argc == 0) {
            return luaL_error(L, "");
        }
        if (!lua_isinteger(L, 1)) {
            return luaL_error(L, "");
        }

        // Read the first argument as app/depot id.
        lua_Integer value = lua_tointeger(L, 1);
        // Ensure the value fits into uint32_t range.
        if (value < 0 || value > UINT32_MAX)
            return luaL_error(L, "");
        AppId_t AppId = (uint32_t)value;
        // Read the second argument as a token.
        if (argc > 1) {
            if (!lua_isstring(L, 2))
                return luaL_error(L, "");
            const char* token = lua_tostring(L, 2);
            // Convert the string token to a uint64_t value.
            if(!std::all_of(token, token + strlen(token), ::isdigit)) {
                return luaL_error(L, "");
            }
            AccessTokenSet[AppId] = std::stoull(token);
        }

        return 0;
    }

    static int lua_pinApp(lua_State* L) {
        // pinApp(integer)
        int argc = lua_gettop(L);
        // Validate argument count and required argument types.
        if (argc == 0) {
            return luaL_error(L, "");
        }
        if (!lua_isinteger(L, 1)) {
            return luaL_error(L, "");
        }

        // Read the first argument as appid.
        lua_Integer value = lua_tointeger(L, 1);
        // Ensure the value fits into uint32_t range.
        if (value < 0 || value > UINT32_MAX)
            return luaL_error(L, "");
        AppId_t AppId = (uint32_t)value;
        
        PinnedApps.insert(AppId);

        return 0;
    }

    static bool Initialize() {
        if (g_lua_state)
            return true; 
        g_lua_state = luaL_newstate();
        if (!g_lua_state)
            return false;
        // Load standard Lua libraries.
        luaL_openlibs(g_lua_state);
        // Register custom helper functions for scripts.
        lua_register(g_lua_state, "addappid", lua_addappid);
        lua_register(g_lua_state, "addtoken", lua_addtoken);
        lua_register(g_lua_state, "pinApp", lua_pinApp);
        return true;
    }
    
    static void Cleanup() {
        if (g_lua_state) {
            lua_close(g_lua_state);
            g_lua_state = nullptr;
        }
    }

    bool HasDepot(AppId_t DepotId) {
        return DepotKeySet.count(DepotId);
    }

    std::vector<AppId_t> GetAllDepotIds() {
        std::vector<AppId_t> DepotIds;
        for (const auto& pair : DepotKeySet) {
            DepotIds.push_back(pair.first);
        }
        return DepotIds;
    }

    std::vector<uint8> GetDecryptionKey(AppId_t DepotId) {
        std::vector<uint8> keyBytes;
        if (DepotKeySet.count(DepotId)) {
            const std::string& keyStr = DepotKeySet[DepotId];
            // Convert hex string to byte vector.
            for (size_t i = 0; i < keyStr.length(); i += 2) {
                std::string byteString = keyStr.substr(i, 2);
                uint8 byte = (uint8)strtoul(byteString.c_str(), nullptr, 16);
                keyBytes.push_back(byte);
            }
        }
        return keyBytes;
    }

    uint64_t GetAccessToken(AppId_t AppId) {
        if (AccessTokenSet.count(AppId)) {
            return AccessTokenSet[AppId];
        }
        return 0;
    }
    
    bool pinApp(AppId_t AppId) {
        return PinnedApps.count(AppId);
    }

    void ParseDirectory(const std::string& directory) {
        if (!Initialize()) {
            return;
        }
        // catch error and create lua folder if its not there
        std::error_code ec;
        if (!std::filesystem::exists(directory, ec)) {
            std::filesystem::create_directories(directory, ec);
        }
        // check it exists and is a directory before iterating
        if (std::filesystem::exists(directory, ec) && std::filesystem::is_directory(directory, ec)) {
            // Iterate all files in the directory and execute .lua scripts.
            for (const auto& entry : std::filesystem::directory_iterator(directory, ec)) {
                if (ec) break;
                if (entry.is_regular_file()) {
                    const auto& path = entry.path();
                    if (path.extension() == ".lua") {
                        // Load and execute each Lua script.
                        if (luaL_dofile(g_lua_state, path.string().c_str()) != LUA_OK) {
                            // Clear Lua error object from the stack and continue.
                            lua_pop(g_lua_state, 1);
                        }
                    }
                }
            }
        }
        Cleanup();
    }

}
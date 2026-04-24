cmake_minimum_required(VERSION 3.10)
project(OpenSteamTool VERSION 1.0.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Create a shared library target for OpenSteamTool.
add_library(OpenSteamTool SHARED 
    dllmain.cpp
    ByteSearch.cpp
    HookManager.cpp
    LuaConfig.cpp
)

# Include directories for Lua and MinHook.
set(INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../include)
target_include_directories(OpenSteamTool PRIVATE 
    ${INCLUDE_DIR}
)

# Link against Lua and MinHook libraries.
target_link_libraries(OpenSteamTool PRIVATE 
    ${INCLUDE_DIR}/Lua/lua54.lib
    ${INCLUDE_DIR}/MinHook/libMinHook.x64.lib
)

# Static Runtime Library
target_compile_options(OpenSteamTool PRIVATE
    $<$<AND:$<CONFIG:Debug>,$<CXX_COMPILER_ID:MSVC>>:/MTd>
    $<$<AND:$<CONFIG:Release>,$<CXX_COMPILER_ID:MSVC>>:/MT>
)


# dwmapi.dll HiJack Project
add_library(dwmapi SHARED
    dwmapi/dwmapi.cpp
)
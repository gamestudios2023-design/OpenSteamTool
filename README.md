# OpenSteamTool

OpenSteamTool is a Windows DLL project built with CMake.

## Feature

### Core Unlocks
- Unlock an unlimited number of unowned games.
- Unlock all DLCs for unowned games.

### Bypasses & DRM Compatibility
- Bypass Low Violence (LV) restrictions.
- Bypass Region Locks.

### Client & Architecture Support
- Fully supports the official Steam client.
- Compatible with both x86 and x64 game architectures.

## Future
- Enable stats and achievements for unowned games.
- Bypass Steam Families sharing restrictions.
- Compatible with games protected by Denuvo and SteamStub.
- Steam Cloud synchronization support.

## Usage
1. Run `build.bat` from the project root to build the project.
2. Copy generated `dwmapi.dll` and `OpenSteamTool.dll` to the Steam root directory.
3. Create Lua directory (for example `C:\steam\config\lua`) and place Lua scripts there. The DLL will automatically load and execute them.
4. Lua example:
```lua
addappid(123456) -- unlock game with appid 123456
addappid(123456, 0,"aa11111111111111") -- unlock game with appid 123456 depotKey is "aa11111111111111"  but we don't use depotKey in this project,refer to the next point.      
``` 
5. Downloading still requires manifest and key:
	- You can add the depot key in `config.vdf`.
	- You need to find the manifest by yourself.
	- This project focuses on unlock behavior only.

## Build

### Requirements
- Windows 10/11
- CMake 3.10+
- Visual Studio 2022 with MSVC (x64 toolchain)

### Included prebuilt dependencies
This repository expects these local files:
- `include/Lua/lua54.lib`
- `include/MinHook/libMinHook.x64.lib`

### Toolchain compatibility note
- This project is intended to be built with MSVC only.
- Do not use Clang/lld or other toolchains for this repository.

### Quick build
```powershell
build.bat
```

### Output
- Debug: `build/Debug/OpenSteamTool.dll` and `build/Debug/dwmapi.dll`
- Release: `build/Release/OpenSteamTool.dll` and `build/Release/dwmapi.dll`

## Disclaimer
This project is provided for research and educational purposes only. You are responsible for complying with local laws, platform terms of service, and software licenses.

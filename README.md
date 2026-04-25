# OpenSteamTool

OpenSteamTool is a Windows DLL project built with CMake.

## Feature

### Core Unlocks
- Unlock an unlimited number of unowned games.
- Unlock all DLCs for unowned games.
- Support auto load depot decryption keys from Lua config, no need to manually input them in `config.vdf` anymore.
- Support auto manifest download thanks to RoGoing's manifest API (https://manifest.steam.run/).

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
addappid(123456, 0,"111111") -- unlock game with appid 123456 depotKey is "111111" 
``` 

## Build

### Requirements
- Windows 10/11
- CMake 3.20+
- Visual Studio 2022 with MSVC (x64 toolchain)

### Quick build
```powershell
build.bat
```

### Output
- Debug: `build/Debug/OpenSteamTool.dll` and `build/Debug/dwmapi.dll`
- Release: `build/Release/OpenSteamTool.dll` and `build/Release/dwmapi.dll`

## Disclaimer
This project is provided for research and educational purposes only. You are responsible for complying with local laws, platform terms of service, and software licenses.

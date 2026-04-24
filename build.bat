@echo off
setlocal

REM Always run from the script directory.
cd /d "%~dp0"

REM clean the previous build cache
if exist "build" (
    echo [INFO] Removing build directory...
    rmdir /s /q "build"
)


echo [INFO] Configuring project...
cmake -S src -B build -G "Visual Studio 17 2022" -A x64
if errorlevel 1 goto :fail

echo [INFO] Building Release...
cmake --build build --config Release
if errorlevel 1 goto :fail

echo [INFO] Building Debug...
cmake --build build --config Debug
if errorlevel 1 goto :fail

echo [OK] Build completed successfully.
exit /b 0

:fail
echo [ERROR] Build failed.
exit /b 1
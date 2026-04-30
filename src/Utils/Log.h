#pragma once

// Debug-only file logger backed by spdlog. In Release builds every LOG_*
// macro expands to nothing and Log::Init is a no-op, so callers don't need
// to guard their log statements with #ifdef.
//
// Behaviour:
//   Debug   -> writes to <dll-dir>/opensteamtool.log, level = trace,
//              flush on every record (we'd rather lose perf than lose lines
//              when the host process crashes mid-hook).
//   Release -> all LOG_* are ((void)0); spdlog is not linked.

#ifdef OPENSTEAMTOOL_LOGGING_ENABLED

// Must be defined before <spdlog/spdlog.h> for SPDLOG_TRACE/DEBUG to compile
// into real calls (otherwise spdlog's headers strip them out).
#ifndef SPDLOG_ACTIVE_LEVEL
    #define SPDLOG_ACTIVE_LEVEL SPDLOG_LEVEL_DEBUG
#endif

#include <spdlog/spdlog.h>
#include <windows.h>

namespace Log {
    // Initialise the file sink. Pass the HMODULE of the DLL invoking this so
    // the log file lands next to the DLL itself (independent of the host
    // process working directory). Safe to call multiple times.
    void Init(HMODULE selfModule);
}

#define LOG_TRACE(...) SPDLOG_TRACE(__VA_ARGS__)
#define LOG_DEBUG(...) SPDLOG_DEBUG(__VA_ARGS__)
#define LOG_INFO(...)  SPDLOG_INFO(__VA_ARGS__)
#define LOG_WARN(...)  SPDLOG_WARN(__VA_ARGS__)
#define LOG_ERROR(...) SPDLOG_ERROR(__VA_ARGS__)

#else  // OPENSTEAMTOOL_LOGGING_ENABLED

#include <windows.h>

namespace Log {
    inline void Init(HMODULE) {}
}

#define LOG_TRACE(...) ((void)0)
#define LOG_DEBUG(...) ((void)0)
#define LOG_INFO(...)  ((void)0)
#define LOG_WARN(...)  ((void)0)
#define LOG_ERROR(...) ((void)0)

#endif  // OPENSTEAMTOOL_LOGGING_ENABLED

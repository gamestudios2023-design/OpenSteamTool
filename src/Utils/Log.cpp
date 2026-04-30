#include "Log.h"

#ifdef OPENSTEAMTOOL_LOGGING_ENABLED

#include <spdlog/sinks/basic_file_sink.h>

#include <atomic>
#include <filesystem>
#include <string>

namespace {
    std::atomic_bool g_initialised{false};

    std::filesystem::path ResolveLogPath(HMODULE selfModule) {
        wchar_t buf[MAX_PATH] = {};
        DWORD len = GetModuleFileNameW(selfModule, buf, MAX_PATH);
        if (len == 0 || len == MAX_PATH) {
            // Fall back to CWD if we can't resolve our own module path.
            return L"opensteamtool.log";
        }
        std::filesystem::path p(buf);
        p.replace_filename(L"opensteamtool.log");
        return p;
    }
}

namespace Log {
    void Init(HMODULE selfModule) {
        bool expected = false;
        if (!g_initialised.compare_exchange_strong(expected, true)) return;

        try {
            auto path = ResolveLogPath(selfModule);
            auto logger = spdlog::basic_logger_mt(
                "opensteamtool", path.string(), /*truncate=*/true);
            logger->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] [tid=%t] [%s:%# %!()] %v");
            logger->set_level(spdlog::level::trace);
            // Flush on every record so a crash inside a hook still leaves a
            // usable log behind.
            logger->flush_on(spdlog::level::trace);
            spdlog::set_default_logger(logger);
            SPDLOG_INFO("Log initialised at {}", path.string());
        } catch (const std::exception&) {
            // Swallow — failing to log must never bring down the host process.
            g_initialised.store(false);
        }
    }
}

#endif  // OPENSTEAMTOOL_LOGGING_ENABLED

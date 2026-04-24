#include "ByteSearch.h"
#include <psapi.h>  

void* ByteSearch(const HMODULE& module, const char* pattern, const char* mask, int matchIndex)
{
    MODULEINFO modInfo;
    GetModuleInformation(GetCurrentProcess(), module, &modInfo, sizeof(MODULEINFO));
    BYTE* base = (BYTE*)modInfo.lpBaseOfDll;
    SIZE_T size = modInfo.SizeOfImage;

    SIZE_T patternLength = strlen(mask);
    int currentMatch = 0;
    for (SIZE_T i = 0; i < size - patternLength; ++i) {
        bool found = true;
        for (SIZE_T j = 0; j < patternLength; ++j) {
            if (mask[j] == 'x' && base[i + j] != (BYTE)pattern[j]) {
                found = false;
                break;
            }
        }
        if (found) {
            if (++currentMatch == matchIndex)
                return base + i;
        }
    }
    return nullptr;
}

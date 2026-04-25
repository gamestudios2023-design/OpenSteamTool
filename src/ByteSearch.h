#ifndef BYTESEARCH_H
#define BYTESEARCH_H

#include "dllmain.h"

#define SEARCH_TYPE inline constexpr const char*

void* ByteSearch(const HMODULE& module, const char* pattern, const char* mask, int matchIndex = 1);


/* -------------------------------------------------------------------------- */
/*                                   SteamUI                                  */
/* -------------------------------------------------------------------------- */
// 48 89 5C 24 18 48 89 6C 24 20 56 41 54 41 57 48 83 EC 40
SEARCH_TYPE LoadModuleWithPathPattern = "\x48\x89\x5C\x24\x18\x48\x89\x6C\x24\x20\x56\x41\x54\x41\x57\x48\x83\xEC\x40";
SEARCH_TYPE LoadModuleWithPathMask = "xxxxxxxxxxxxxxxxxxx";



/* -------------------------------------------------------------------------- */
/*									 SteamClient                              */
/* -------------------------------------------------------------------------- */

//48 89 5C 24 18 48 89 6C 24 20 56 57 41 54 41 55 41 57 48 81 EC 20 01
SEARCH_TYPE LoadPackagePattern = "\x48\x89\x5C\x24\x18\x48\x89\x6C\x24\x20\x56\x57\x41\x54\x41\x55\x41\x57\x48\x81\xEC\x20\x01";
SEARCH_TYPE LoadPackageMask = "xxxxxxxxxxxxxxxxxxxxxxx";

//48 8B C4 89 50 10 55 53 48 8D 68 D8
SEARCH_TYPE CheckAppOwnershipPattern = "\x48\x8B\xC4\x89\x50\x10\x55\x53\x48\x8D\x68\xD8";
SEARCH_TYPE CheckAppOwnershipMask = "xxxxxxxxxxxx";

// 48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 30(The Frist Search Result)
SEARCH_TYPE CUtlMemoryGrowPattern = "\x48\x89\x5C\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xEC\x30";
SEARCH_TYPE CUtlMemoryGrowMask = "xxxxxxxxxxxxxxx";

//48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 30 48 63 FA 49 8B E9 8B D7 49 8B D8 48 8B F1
SEARCH_TYPE LoadDepotDecryptionKeyPattern = "\x48\x89\x5C\x24\x08\x48\x89\x6C\x24\x10\x48\x89\x74\x24\x18\x57\x48\x83\xEC\x30\x48\x63\xFA\x49\x8B\xE9\x8B\xD7\x49\x8B\xD8\x48\x8B\xF1";
SEARCH_TYPE LoadDepotDecryptionKeyMask = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

// 48 89 5C 24 18 55 56 57 41 55 41 57 48 8D 6C 24 A0
SEARCH_TYPE GetManifestRequestCodePattern="\x48\x89\x5C\x24\x18\x55\x56\x57\x41\x55\x41\x57\x48\x8D\x6C\x24\xA0";
SEARCH_TYPE GetManifestRequestCodeMask="xxxxxxxxxxxxxxxxx";

#endif // BYTESEARCH_H
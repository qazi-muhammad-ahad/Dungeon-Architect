#include "dungeon_architect_c.h"
#include <windows.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

typedef uint32_t (DA_CALL *probe_fn)(void);

int main(int argc, char** argv) {
    HMODULE library;
    FARPROC abi_symbol;
    FARPROC bits_symbol;
    probe_fn abi;
    probe_fn bits;
    int result = 0;
    if (argc != 2) {
        fprintf(stderr, "Usage: dungeon_api_smoke <DLL path>\n");
        return 2;
    }
    library = LoadLibraryA(argv[1]);
    if (library == NULL) {
        fprintf(stderr, "LoadLibrary failed: %lu\n", GetLastError());
        return 1;
    }
    abi_symbol = GetProcAddress(library, "da_bootstrap_abi_version");
    bits_symbol = GetProcAddress(library, "da_pointer_bits");
    if (abi_symbol == NULL || bits_symbol == NULL) {
        fprintf(stderr, "Required unmangled exports are missing.\n");
        FreeLibrary(library);
        return 1;
    }
    /* Windows function pointers have equal representations. Copy avoids
       incompatible-function-cast warnings in both MSVC and GCC. */
    if (sizeof(abi) != sizeof(abi_symbol) || sizeof(bits) != sizeof(bits_symbol)) {
        FreeLibrary(library);
        return 1;
    }
    memcpy(&abi, &abi_symbol, sizeof(abi));
    memcpy(&bits, &bits_symbol, sizeof(bits));
    if (abi() != 1 || bits() != sizeof(void*) * CHAR_BIT) {
        fprintf(stderr, "Unexpected bootstrap ABI or DLL/caller bitness.\n");
        result = 1;
    } else {
        printf("DLL loaded: bootstrap ABI %u, %u-bit\n", (unsigned)abi(), (unsigned)bits());
    }
    if (!FreeLibrary(library)) {
        fprintf(stderr, "FreeLibrary failed.\n");
        result = 1;
    }
    return result;
}

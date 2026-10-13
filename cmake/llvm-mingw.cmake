# Resolve relative to this file so a checkout in a path with spaces is supported.
get_filename_component(DA_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(DA_LLVM_BIN "${DA_ROOT}/.tools/llvm-mingw-20261006-ucrt-x86_64/bin")
set(CMAKE_C_COMPILER "${DA_LLVM_BIN}/x86_64-w64-mingw32-clang.exe")
set(CMAKE_CXX_COMPILER "${DA_LLVM_BIN}/x86_64-w64-mingw32-clang++.exe")
set(CMAKE_MAKE_PROGRAM "${DA_LLVM_BIN}/mingw32-make.exe" CACHE FILEPATH "Portable Make")
# Make the bootstrap executables/DLL independent of compiler-bin PATH entries.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-static")

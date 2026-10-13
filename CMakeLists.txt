cmake_minimum_required(VERSION 3.24)
project(DungeonArchitect VERSION 0.10.0 LANGUAGES C CXX)

include(CTest)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(EMSCRIPTEN)
  add_compile_options(-fexceptions)
endif()
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
# Match the Flutter runner's dynamically linked MSVC runtime.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

function(da_warnings target)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /permissive- /utf-8)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
  endif()
endfunction()

add_library(dungeon_core STATIC
  core/src/build_info.cpp
  core/src/domain/project.cpp
  core/src/domain/project_session.cpp
  core/src/domain/masks.cpp
  core/src/domain/fixed_rooms.cpp
  core/src/simulation/movement.cpp
  core/src/generation/bsp.cpp
  core/src/generation/routing.cpp
  core/src/allocation/input.cpp
  core/src/allocation/subset_dp.cpp
  core/src/validation/allocation_validation.cpp
  core/src/validation/room_layout_validation.cpp
  core/src/validation/routing_validation.cpp
  core/src/validation/project_validation.cpp)
target_include_directories(dungeon_core PUBLIC core/include PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
set_target_properties(dungeon_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
configure_file(cmake/version.h.in generated/da_version.h @ONLY)
da_warnings(dungeon_core)

add_library(dungeon_project_io STATIC
  adapters/project_io/project_json.cpp
  adapters/project_io/project_file.cpp)
target_include_directories(dungeon_project_io PUBLIC adapters/project_io/include)
target_include_directories(dungeon_project_io SYSTEM PRIVATE third_party)
target_link_libraries(dungeon_project_io PUBLIC dungeon_core)
set_target_properties(dungeon_project_io PROPERTIES POSITION_INDEPENDENT_CODE ON)
da_warnings(dungeon_project_io)

add_library(dungeon_result_io STATIC adapters/result_io/result_json.cpp)
target_include_directories(dungeon_result_io PUBLIC adapters/result_io/include)
target_include_directories(dungeon_result_io SYSTEM PUBLIC third_party)
target_link_libraries(dungeon_result_io PUBLIC dungeon_project_io)
set_target_properties(dungeon_result_io PROPERTIES POSITION_INDEPENDENT_CODE ON)
da_warnings(dungeon_result_io)

if(EMSCRIPTEN)
  include(cmake/wasm.cmake)
  return()
endif()

add_library(dungeon_api SHARED api/src/dungeon_architect_c.cpp)
target_include_directories(dungeon_api PUBLIC api/include)
target_link_libraries(dungeon_api PRIVATE dungeon_result_io)
target_compile_definitions(dungeon_api PRIVATE DA_BUILDING_DLL)
set_target_properties(dungeon_api PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)
da_warnings(dungeon_api)

add_executable(dungeon_api_caller api/examples/caller.c)
target_link_libraries(dungeon_api_caller PRIVATE dungeon_api)
da_warnings(dungeon_api_caller)

add_executable(dungeon_cli cli/main.cpp cli/generation_cli.cpp)
target_include_directories(dungeon_cli SYSTEM PRIVATE third_party)
target_link_libraries(dungeon_cli PRIVATE dungeon_result_io)
if(MINGW)
  target_link_options(dungeon_cli PRIVATE -municode)
endif()
da_warnings(dungeon_cli)

# Explicitly verify language AND standard-library support on the chosen toolchain.
# GCC 6.3 is deliberately rejected by this probe (missing <string_view>).
add_executable(dungeon_cxx17_probe tools/cxx17_probe.cpp)
da_warnings(dungeon_cxx17_probe)

if(BUILD_TESTING)
  add_executable(dungeon_api_contract tests/api/contract_test.cpp)
  target_link_libraries(dungeon_api_contract PRIVATE dungeon_api dungeon_result_io)
  da_warnings(dungeon_api_contract)
  add_test(NAME api.contract COMMAND dungeon_api_contract
    "${CMAKE_CURRENT_SOURCE_DIR}/datasets/pipeline/teaching.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/datasets/allocation/standard-14.json")
  set_tests_properties(api.contract PROPERTIES TIMEOUT 30)
  add_test(NAME api.cli_parity COMMAND "${CMAKE_COMMAND}"
    "-DCLI=$<TARGET_FILE:dungeon_cli>" "-DCALLER=$<TARGET_FILE:dungeon_api_caller>"
    "-DFIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/datasets/pipeline/teaching.json"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/api/parity.cmake")
  add_test(NAME toolchain.cxx17 COMMAND dungeon_cxx17_probe)
  add_executable(dungeon_core_smoke tests/core/smoke.cpp)
  target_link_libraries(dungeon_core_smoke PRIVATE dungeon_core)
  da_warnings(dungeon_core_smoke)
  add_test(NAME core.smoke COMMAND dungeon_core_smoke)

  add_executable(dungeon_project_test tests/core/project_test.cpp)
  target_link_libraries(dungeon_project_test PRIVATE dungeon_core)
  da_warnings(dungeon_project_test)
  add_test(NAME core.project COMMAND dungeon_project_test)

  add_executable(dungeon_geometry_test tests/core/geometry_test.cpp)
  target_link_libraries(dungeon_geometry_test PRIVATE dungeon_core)
  da_warnings(dungeon_geometry_test)
  add_test(NAME core.geometry COMMAND dungeon_geometry_test)

  add_executable(dungeon_generation_test tests/core/generation_test.cpp)
  target_link_libraries(dungeon_generation_test PRIVATE dungeon_core)
  da_warnings(dungeon_generation_test)
  add_test(NAME core.generation COMMAND dungeon_generation_test)
  add_executable(dungeon_routing_test tests/core/routing_test.cpp)
  target_link_libraries(dungeon_routing_test PRIVATE dungeon_core)
  da_warnings(dungeon_routing_test)
  add_test(NAME core.routing COMMAND dungeon_routing_test)
  add_executable(dungeon_allocation_test tests/core/allocation_test.cpp)
  target_link_libraries(dungeon_allocation_test PRIVATE dungeon_core)
  da_warnings(dungeon_allocation_test)
  add_test(NAME core.allocation COMMAND dungeon_allocation_test)

  add_executable(dungeon_project_io_test tests/integration/project_io_test.cpp)
  target_link_libraries(dungeon_project_io_test PRIVATE dungeon_project_io)
  target_include_directories(dungeon_project_io_test SYSTEM PRIVATE third_party)
  da_warnings(dungeon_project_io_test)
  add_test(NAME project.persistence COMMAND dungeon_project_io_test
    "${CMAKE_CURRENT_SOURCE_DIR}/datasets/teaching/phase02-project.json" "${CMAKE_CURRENT_BINARY_DIR}")
  add_test(NAME cli.project COMMAND "${CMAKE_COMMAND}"
    "-DCLI=$<TARGET_FILE:dungeon_cli>"
    "-DFIXTURE=${CMAKE_CURRENT_SOURCE_DIR}/datasets/teaching/phase02-project.json"
    "-DTEST_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/cli_test.cmake")
  add_test(NAME cli.geometry COMMAND "${CMAKE_COMMAND}"
    "-DCLI=$<TARGET_FILE:dungeon_cli>"
    "-DDATASETS=${CMAKE_CURRENT_SOURCE_DIR}/datasets/edge_cases"
    "-DTEST_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/geometry_cli_test.cmake")
  add_test(NAME cli.generation COMMAND "${CMAKE_COMMAND}"
    "-DCLI=$<TARGET_FILE:dungeon_cli>"
    "-DDATASETS=${CMAKE_CURRENT_SOURCE_DIR}/datasets/generation"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/generation_cli_test.cmake")
  add_test(NAME cli.routing COMMAND "${CMAKE_COMMAND}"
    "-DCLI=$<TARGET_FILE:dungeon_cli>"
    "-DDATASETS=${CMAKE_CURRENT_SOURCE_DIR}/datasets/routing"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/routing_cli_test.cmake")
  add_test(NAME cli.allocation COMMAND "${CMAKE_COMMAND}"
    "-DCLI=$<TARGET_FILE:dungeon_cli>"
    "-DDATASETS=${CMAKE_CURRENT_SOURCE_DIR}/datasets/allocation"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/allocation_cli_test.cmake")
  add_test(NAME cli.pipeline COMMAND "${CMAKE_COMMAND}"
    "-DCLI=$<TARGET_FILE:dungeon_cli>"
    "-DDATASETS=${CMAKE_CURRENT_SOURCE_DIR}/datasets"
    "-DTEST_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration/pipeline_cli_test.cmake")

  if(WIN32)
    add_executable(dungeon_cli_cancel_test tests/integration/cli_cancel_test.cpp)
    target_link_libraries(dungeon_cli_cancel_test PRIVATE dungeon_project_io)
    target_include_directories(dungeon_cli_cancel_test SYSTEM PRIVATE third_party)
    add_dependencies(dungeon_cli_cancel_test dungeon_cli)
    if(MINGW)
      target_link_options(dungeon_cli_cancel_test PRIVATE -municode)
    endif()
    da_warnings(dungeon_cli_cancel_test)
    add_test(NAME cli.cancellation COMMAND dungeon_cli_cancel_test
      "$<TARGET_FILE:dungeon_cli>" "${CMAKE_CURRENT_SOURCE_DIR}/datasets/allocation/standard-14.json" "${CMAKE_CURRENT_BINARY_DIR}")
    set_tests_properties(cli.cancellation PROPERTIES TIMEOUT 20)
    # Compile the standalone loader as C to check that the header is C-compatible.
    add_executable(dungeon_api_smoke tests/api/load_library.c)
    target_include_directories(dungeon_api_smoke PRIVATE api/include)
    add_dependencies(dungeon_api_smoke dungeon_api)
    da_warnings(dungeon_api_smoke)
    add_test(NAME api.load_library COMMAND dungeon_api_smoke "$<TARGET_FILE:dungeon_api>")
  endif()
endif()


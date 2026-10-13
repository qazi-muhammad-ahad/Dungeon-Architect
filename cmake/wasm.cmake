# Same C++ domain/algorithms and ABI, hosted in one dedicated Web Worker.
add_executable(dungeon_engine api/src/dungeon_architect_c.cpp)
target_include_directories(dungeon_engine PRIVATE api/include)
target_link_libraries(dungeon_engine PRIVATE dungeon_result_io)
da_warnings(dungeon_engine)
set_target_properties(dungeon_engine PROPERTIES SUFFIX ".js")
target_link_options(dungeon_engine PRIVATE
  --no-entry -fexceptions
  "-sMODULARIZE=1" "-sEXPORT_NAME=createDungeonEngine"
  "-sENVIRONMENT=worker,node" "-sALLOW_MEMORY_GROWTH=1"
  "-sMAXIMUM_MEMORY=536870912" "-sSTACK_SIZE=1048576"
  "-sASYNCIFY=1" "-sASYNCIFY_STACK_SIZE=1048576"
  "-sASSERTIONS=1" "-sFILESYSTEM=0"
  "-sEXPORTED_FUNCTIONS=['_malloc','_free','_da_bootstrap_abi_version','_da_pointer_bits','_da_context_create','_da_context_release','_da_job_create','_da_job_execute','_da_job_cancel','_da_job_poll','_da_job_read','_da_job_trace','_da_context_read','_da_job_release','_da_context_step']"
  "-sEXPORTED_RUNTIME_METHODS=['ccall','HEAPU8','HEAPU32','HEAP32']")

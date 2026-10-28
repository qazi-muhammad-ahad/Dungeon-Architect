# Ignore only nondeterministic timing telemetry. Results, counters and events
# remain byte-equal for repeated runs with identical inputs and seed.
function(remove_timing input output)
  string(REGEX REPLACE "\"timings_us\"[ \t\r\n]*:[ \t\r\n]*\\{[^}]*\\}" "\"timings_us\": {}" normalized "${input}")
  string(REGEX REPLACE "\"trace_us\"[ \t\r\n]*:[ \t\r\n]*[0-9.eE+-]+" "\"trace_us\": 0" normalized "${normalized}")
  set(${output} "${normalized}" PARENT_SCOPE)
endfunction()

function(expect_semantic_equal first second message)
  remove_timing("${first}" first_semantic)
  remove_timing("${second}" second_semantic)
  if(NOT first_semantic STREQUAL second_semantic)
    message(FATAL_ERROR "${message}")
  endif()
endfunction()

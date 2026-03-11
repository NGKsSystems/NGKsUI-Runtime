add_library(ngk_core STATIC
  src/core.cpp
  src/event_loop.cpp
  src/event_queue.cpp
  src/task_queue.cpp
  src/timer.cpp
)

target_include_directories(ngk_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_definitions(ngk_core PUBLIC NGK_PLATFORM_WINDOWS=1)

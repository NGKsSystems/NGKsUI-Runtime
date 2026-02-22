add_library(ngk_platform_win32 STATIC
  src/platform_win32.cpp
  src/win32_window.cpp
)

target_include_directories(ngk_platform_win32 PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(ngk_platform_win32 PUBLIC ngk_core)
target_link_libraries(ngk_platform_win32 PUBLIC user32)

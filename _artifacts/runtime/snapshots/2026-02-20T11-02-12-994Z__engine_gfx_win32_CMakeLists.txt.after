add_library(ngk_gfx_win32 STATIC
  src/d3d11_renderer.cpp
)

target_include_directories(ngk_gfx_win32 PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Core types + any shared gfx headers
target_link_libraries(ngk_gfx_win32 PUBLIC ngk_core)

# D3D11 + DXGI
if (WIN32)
  target_link_libraries(ngk_gfx_win32 PRIVATE d3d11 dxgi)
endif()
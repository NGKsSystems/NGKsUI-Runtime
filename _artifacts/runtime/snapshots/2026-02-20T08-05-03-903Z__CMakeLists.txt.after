cmake_minimum_required(VERSION 3.24)
project(NGKsUIRuntime LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if (MSVC)
	add_compile_options(/EHsc)
endif()

# Output dirs
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

add_subdirectory(engine/core)
add_subdirectory(engine/platform/win32)
add_subdirectory(engine/gfx)
add_subdirectory(engine/ui)
add_subdirectory(apps/sandbox_app)
add_subdirectory(apps/loop_tests)
add_subdirectory(apps/win32_sandbox)

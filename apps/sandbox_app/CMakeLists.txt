add_executable(sandbox_app
  main.cpp
)

target_link_libraries(sandbox_app PRIVATE
  ngk_ui
)

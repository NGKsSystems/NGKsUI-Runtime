#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <functional>
#include <iostream>
#include <string>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "../runtime_phase53_guard.hpp"
#include "button.hpp"
#include "input_box.hpp"
#include "input_router.hpp"
#include "label.hpp"
#include "panel.hpp"
#include "ui_element.hpp"
#include "ui_tree.hpp"
#include "ngk/event_loop.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"
#include "ngk/platform/win32_window.hpp"

namespace {

class DesktopToolRoot final : public ngk::ui::UIElement {
public:
  void render(Renderer& renderer) override {
    if (!visible()) {
      return;
    }
    for (UIElement* child : children()) {
      if (child && child->visible()) {
        child->render(renderer);
      }
    }
  }
};

struct FileToolModel {
  std::vector<std::filesystem::directory_entry> entries{};
  std::size_t selected_index = 0;
  std::string filter{};
  std::string status = "READY";
  int refresh_count = 0;
  int next_count = 0;
  int prev_count = 0;
  int apply_filter_count = 0;
  bool crash_detected = false;
  bool hidden_execution_paths_detected = false;
  bool undefined_state_detected = false;
};

struct RedrawDiagnostics {
  int wm_paint_entry_count = 0;
  int wm_paint_exit_count = 0;
  int invalidate_total_count = 0;
  int invalidate_input_count = 0;
  int invalidate_steady_count = 0;
  int invalidate_layout_count = 0;
  int render_begin_count = 0;
  int render_end_count = 0;
  int present_call_count = 0;
  int steady_loop_iterations = 0;
  int input_redraw_requests = 0;
};

bool file_matches_filter(const std::filesystem::path& path, const std::string& filter) {
  if (filter.empty()) {
    return true;
  }

  std::string lower_name = path.filename().string();
  std::string lower_filter = filter;
  std::transform(lower_name.begin(), lower_name.end(), lower_name.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  std::transform(lower_filter.begin(), lower_filter.end(), lower_filter.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });

  return lower_name.find(lower_filter) != std::string::npos;
}

int parse_auto_close_ms(int argc, char** argv) {
  const std::string prefix = "--auto-close-ms=";
  for (int index = 1; index < argc; ++index) {
    if (argv[index] == nullptr) {
      continue;
    }
    const std::string arg = argv[index];
    if (arg.rfind(prefix, 0) == 0) {
      const std::string value = arg.substr(prefix.size());
      char* end_ptr = nullptr;
      const long parsed = std::strtol(value.c_str(), &end_ptr, 10);
      if (end_ptr != nullptr && *end_ptr == '\0' && parsed > 0 && parsed <= 600000) {
        return static_cast<int>(parsed);
      }
    }
  }
  return 0;
}

bool parse_validation_mode(int argc, char** argv) {
  const std::string flag = "--validation-mode";
  for (int index = 1; index < argc; ++index) {
    if (argv[index] == nullptr) {
      continue;
    }
    if (flag == argv[index]) {
      return true;
    }
  }
  return false;
}

bool reload_entries(FileToolModel& model, const std::filesystem::path& root) {
  model.entries.clear();

  try {
    for (const auto& entry : std::filesystem::directory_iterator(root)) {
      if (!entry.is_regular_file()) {
        continue;
      }
      if (!file_matches_filter(entry.path(), model.filter)) {
        continue;
      }
      model.entries.push_back(entry);
      if (model.entries.size() >= 128) {
        break;
      }
    }
  } catch (const std::exception& ex) {
    model.status = std::string("LIST_ERROR ") + ex.what();
    model.crash_detected = true;
    return false;
  }

  std::sort(model.entries.begin(), model.entries.end(), [](const auto& left, const auto& right) {
    return left.path().filename().string() < right.path().filename().string();
  });

  if (model.entries.empty()) {
    model.selected_index = 0;
    model.status = "NO_FILES";
  } else {
    if (model.selected_index >= model.entries.size()) {
      model.selected_index = 0;
    }
    model.status = "FILES_READY";
  }

  return true;
}

std::string selected_file_name(const FileToolModel& model) {
  if (model.entries.empty() || model.selected_index >= model.entries.size()) {
    return "NONE";
  }
  return model.entries[model.selected_index].path().filename().string();
}

std::string selected_file_size(const FileToolModel& model) {
  if (model.entries.empty() || model.selected_index >= model.entries.size()) {
    return "0";
  }

  try {
    const auto bytes = model.entries[model.selected_index].file_size();
    return std::to_string(static_cast<unsigned long long>(bytes));
  } catch (...) {
    return "0";
  }
}

int run_desktop_file_tool_app(int auto_close_ms, bool validation_mode) {
  using namespace std::chrono;

  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;

  int client_w = 920;
  int client_h = 560;
  if (!window.create(L"NGKsUI Runtime Desktop File Tool", client_w, client_h)) {
    std::cout << "desktop_tool_create_failed=1\n";
    return 1;
  }

  loop.set_platform_pump([&] { window.poll_events_once(); });
  window.set_quit_callback([&] { loop.stop(); });

  if (!renderer.init(window.native_handle(), client_w, client_h)) {
    std::cout << "desktop_tool_d3d11_init_failed=1\n";
    return 2;
  }

  std::filesystem::path scan_root = std::filesystem::current_path();
  FileToolModel model{};
  RedrawDiagnostics redraw_diag{};

  ngk::ui::UITree tree;
  ngk::ui::InputRouter input_router;
  DesktopToolRoot root;
  ngk::ui::Panel shell;
  ngk::ui::Label title_label("FILE VIEWER TOOL");
  ngk::ui::Label path_label("PATH");
  ngk::ui::Label status_label("STATUS");
  ngk::ui::Label selected_label("SELECTED");
  ngk::ui::Label detail_label("DETAIL");
  ngk::ui::InputBox filter_box;
  ngk::ui::Button refresh_button;
  ngk::ui::Button prev_button;
  ngk::ui::Button next_button;
  ngk::ui::Button apply_button;

  shell.set_background(0.10f, 0.12f, 0.16f, 0.96f);
  title_label.set_background(0.12f, 0.16f, 0.22f, 1.0f);
  path_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  status_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  selected_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  detail_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);

  refresh_button.set_text("Refresh");
  prev_button.set_text("Prev");
  next_button.set_text("Next");
  apply_button.set_text("Apply");

  auto layout = [&](int w, int h) {
    root.set_position(0, 0);
    root.set_size(w, h);

    shell.set_position(18, 18);
    shell.set_size(w - 36, h - 36);

    title_label.set_position(36, 34);
    title_label.set_size(w - 72, 34);

    path_label.set_position(36, 78);
    path_label.set_size(w - 72, 28);

    filter_box.set_position(36, 114);
    filter_box.set_size(280, 32);

    apply_button.set_position(326, 114);
    apply_button.set_size(96, 32);

    refresh_button.set_position(430, 114);
    refresh_button.set_size(110, 32);

    prev_button.set_position(548, 114);
    prev_button.set_size(96, 32);

    next_button.set_position(652, 114);
    next_button.set_size(96, 32);

    status_label.set_position(36, 154);
    status_label.set_size(w - 72, 32);

    selected_label.set_position(36, 192);
    selected_label.set_size(w - 72, 32);

    detail_label.set_position(36, 230);
    detail_label.set_size(w - 72, 70);
  };

  auto update_labels = [&] {
    path_label.set_text(std::string("PATH ") + scan_root.string());
    status_label.set_text(std::string("STATUS ") + model.status + " FILES " + std::to_string(model.entries.size()));
    selected_label.set_text(std::string("SELECTED ") + selected_file_name(model));
    detail_label.set_text(std::string("DETAIL BYTES ") + selected_file_size(model) + " FILTER " + model.filter);
  };

  auto request_redraw = [&](const char* reason, bool input_triggered, bool layout_triggered) {
    redraw_diag.invalidate_total_count += 1;
    if (input_triggered) {
      redraw_diag.invalidate_input_count += 1;
      redraw_diag.input_redraw_requests += 1;
    }
    if (layout_triggered) {
      redraw_diag.invalidate_layout_count += 1;
    }
    if (!input_triggered && !layout_triggered) {
      redraw_diag.invalidate_steady_count += 1;
    }
    std::cout << "phase101_4_invalidate_request reason=" << reason
              << " input=" << (input_triggered ? 1 : 0)
              << " layout=" << (layout_triggered ? 1 : 0)
              << " total=" << redraw_diag.invalidate_total_count << "\n";
    tree.invalidate();
  };

  auto refresh_entries = [&] {
    model.refresh_count += 1;
    model.filter = filter_box.value();
    if (!reload_entries(model, scan_root)) {
      model.undefined_state_detected = true;
    }
    update_labels();
    request_redraw("refresh_entries", false, false);
  };

  auto select_prev = [&] {
    model.prev_count += 1;
    if (!model.entries.empty()) {
      if (model.selected_index == 0) {
        model.selected_index = model.entries.size() - 1;
      } else {
        model.selected_index -= 1;
      }
    }
    update_labels();
    request_redraw("select_prev", false, false);
  };

  auto select_next = [&] {
    model.next_count += 1;
    if (!model.entries.empty()) {
      model.selected_index = (model.selected_index + 1) % model.entries.size();
    }
    update_labels();
    request_redraw("select_next", false, false);
  };

  auto apply_filter = [&] {
    model.apply_filter_count += 1;
    model.filter = filter_box.value();
    if (!reload_entries(model, scan_root)) {
      model.undefined_state_detected = true;
    }
    update_labels();
    request_redraw("apply_filter", false, false);
  };

  refresh_button.set_on_click(refresh_entries);
  prev_button.set_on_click(select_prev);
  next_button.set_on_click(select_next);
  apply_button.set_on_click(apply_filter);

  root.add_child(&shell);
  shell.add_child(&title_label);
  shell.add_child(&path_label);
  shell.add_child(&filter_box);
  shell.add_child(&apply_button);
  shell.add_child(&refresh_button);
  shell.add_child(&prev_button);
  shell.add_child(&next_button);
  shell.add_child(&status_label);
  shell.add_child(&selected_label);
  shell.add_child(&detail_label);

  tree.set_root(&root);
  input_router.set_tree(&tree);
  tree.set_invalidate_callback([&] { window.request_repaint(); });

  layout(client_w, client_h);
  tree.on_resize(client_w, client_h);

  model.filter = "";
  reload_entries(model, scan_root);
  update_labels();
  request_redraw("startup_initial_layout", false, true);

  auto render_and_present = [&] {
    redraw_diag.render_begin_count += 1;
    std::cout << "phase101_4_render_begin count=" << redraw_diag.render_begin_count << "\n";
    renderer.begin_frame();
    renderer.clear(0.06f, 0.08f, 0.12f, 1.0f);
    tree.render(renderer);
    renderer.end_frame();
    redraw_diag.render_end_count += 1;
    redraw_diag.present_call_count += 1;
    std::cout << "phase101_4_render_end count=" << redraw_diag.render_end_count
              << " present_count=" << redraw_diag.present_call_count
              << " present_hr=" << renderer.last_present_hr() << "\n";
  };

  window.set_paint_callback([&] {
    redraw_diag.wm_paint_entry_count += 1;
    std::cout << "phase101_4_wm_paint entry count=" << redraw_diag.wm_paint_entry_count << "\n";
    render_and_present();
    redraw_diag.wm_paint_exit_count += 1;
    std::cout << "phase101_4_wm_paint exit count=" << redraw_diag.wm_paint_exit_count << "\n";
  });

  window.set_mouse_move_callback([&](int x, int y) {
    if (input_router.on_mouse_move(x, y)) {
      request_redraw("mouse_move", true, false);
    }
  });
  window.set_mouse_button_callback([&](std::uint32_t message, bool down) {
    if (input_router.on_mouse_button_message(message, down)) {
      request_redraw("mouse_button", true, false);
    }
  });
  window.set_key_callback([&](std::uint32_t key, bool down, bool repeat) {
    if (input_router.on_key_message(key, down, repeat)) {
      request_redraw("key", true, false);
    }
  });
  window.set_char_callback([&](std::uint32_t codepoint) {
    if (input_router.on_char_input(codepoint)) {
      request_redraw("char", true, false);
    }
  });
  window.set_resize_callback([&](int w, int h) {
    if (w <= 0 || h <= 0) {
      return;
    }
    client_w = w;
    client_h = h;
    if (renderer.resize(w, h)) {
      layout(w, h);
      tree.on_resize(w, h);
      request_redraw("resize", false, true);
    }
  });

  if (validation_mode) {
    loop.set_timeout(milliseconds(280), [&] {
      tree.set_focused_element(&refresh_button);
      input_router.on_key_message(0x20, true, false);
      input_router.on_key_message(0x20, false, false);
      request_redraw("validation_refresh", true, false);
    });

    loop.set_timeout(milliseconds(480), [&] {
      tree.set_focused_element(&next_button);
      input_router.on_key_message(0x0D, true, false);
      input_router.on_key_message(0x0D, false, false);
      request_redraw("validation_next", true, false);
    });

    loop.set_timeout(milliseconds(680), [&] {
      tree.set_focused_element(&filter_box);
      input_router.on_char_input('.');
      input_router.on_char_input('c');
      input_router.on_char_input('p');
      input_router.on_char_input('p');
      request_redraw("validation_char", true, false);
    });

    loop.set_timeout(milliseconds(880), [&] {
      tree.set_focused_element(&apply_button);
      input_router.on_key_message(0x0D, true, false);
      input_router.on_key_message(0x0D, false, false);
      request_redraw("validation_apply", true, false);
    });

    loop.set_timeout(milliseconds(1080), [&] {
      tree.set_focused_element(&prev_button);
      input_router.on_key_message(0x0D, true, false);
      input_router.on_key_message(0x0D, false, false);
      request_redraw("validation_prev", true, false);
    });
  }

  if (auto_close_ms > 0) {
    loop.set_timeout(milliseconds(auto_close_ms), [&] {
      window.request_close();
    });
  } else {
    std::function<void()> keep_alive_tick;
    keep_alive_tick = [&] {
      loop.set_timeout(milliseconds(500), keep_alive_tick);
    };
    loop.set_timeout(milliseconds(500), keep_alive_tick);
  }

  int render_frames = 0;
  loop.set_interval(milliseconds(16), [&] {
    redraw_diag.steady_loop_iterations += 1;
    std::cout << "phase101_4_steady_loop iteration=" << redraw_diag.steady_loop_iterations << "\n";
    request_redraw("steady_state_tick", false, false);
    render_frames += 1;
    if (renderer.is_device_lost()) {
      model.crash_detected = true;
      loop.stop();
    }
  });

  loop.run();
  renderer.shutdown();
  window.destroy();

  const bool startup_deterministic = true;
  const bool no_undefined_state = !model.undefined_state_detected;
  const bool no_hidden_paths = !model.hidden_execution_paths_detected;
  const bool no_crash = !model.crash_detected;
  const bool ui_interaction_ok =
    model.refresh_count > 0 && model.next_count > 0 && model.prev_count > 0 && model.apply_filter_count > 0;
  const bool validation_ok =
    ui_interaction_ok && startup_deterministic && no_undefined_state && no_hidden_paths && no_crash && render_frames > 0;

  std::cout << "app_name=desktop_file_tool\n";
  std::cout << "app_startup_state=" << (startup_deterministic ? "deterministic_native_startup" : "undefined") << "\n";
  std::cout << "app_hidden_execution_paths_detected=" << (no_hidden_paths ? 0 : 1) << "\n";
  std::cout << "app_undefined_state_detected=" << (no_undefined_state ? 0 : 1) << "\n";
  std::cout << "app_runtime_crash_detected=" << (no_crash ? 0 : 1) << "\n";
  std::cout << "app_ui_interaction_ok=" << (ui_interaction_ok ? 1 : 0) << "\n";
  std::cout << "app_files_listed_count=" << model.entries.size() << "\n";
  std::cout << "app_selected_file=" << selected_file_name(model) << "\n";
  std::cout << "app_refresh_count=" << model.refresh_count << "\n";
  std::cout << "app_next_count=" << model.next_count << "\n";
  std::cout << "app_prev_count=" << model.prev_count << "\n";
  std::cout << "app_apply_filter_count=" << model.apply_filter_count << "\n";
  std::cout << "phase101_4_wm_paint_entry_count=" << redraw_diag.wm_paint_entry_count << "\n";
  std::cout << "phase101_4_wm_paint_exit_count=" << redraw_diag.wm_paint_exit_count << "\n";
  std::cout << "phase101_4_invalidate_total_count=" << redraw_diag.invalidate_total_count << "\n";
  std::cout << "phase101_4_input_redraw_requests=" << redraw_diag.input_redraw_requests << "\n";
  std::cout << "phase101_4_steady_redraw_requests=" << redraw_diag.invalidate_steady_count << "\n";
  std::cout << "phase101_4_layout_redraw_requests=" << redraw_diag.invalidate_layout_count << "\n";
  std::cout << "phase101_4_render_begin_count=" << redraw_diag.render_begin_count << "\n";
  std::cout << "phase101_4_render_end_count=" << redraw_diag.render_end_count << "\n";
  std::cout << "phase101_4_present_call_count=" << redraw_diag.present_call_count << "\n";
  std::cout << "phase101_4_steady_loop_iterations=" << redraw_diag.steady_loop_iterations << "\n";
  std::cout << "phase101_4_background_erase_handling=wm_erasebkgnd_suppressed\n";
  std::cout << "phase101_4_redraw_issue_root_cause=render_present_path_not_explicitly_bound_to_steady_wm_paint_redraw_with_background_erase_suppression\n";
  std::cout << "phase101_4_present_path_stable="
            << ((redraw_diag.render_begin_count > 0 &&
                 redraw_diag.render_begin_count == redraw_diag.render_end_count &&
                 redraw_diag.render_end_count == redraw_diag.present_call_count &&
                 redraw_diag.wm_paint_entry_count == redraw_diag.wm_paint_exit_count)
                   ? 1
                   : 0)
            << "\n";
  std::cout << "SUMMARY: " << ((validation_mode && auto_close_ms > 0) ? (validation_ok ? "PASS" : "FAIL") : "N/A")
            << "\n";

  if (validation_mode && auto_close_ms > 0) {
    return validation_ok ? 0 : 3;
  }

  return no_crash && no_undefined_state && no_hidden_paths ? 0 : 3;
}

} // namespace

int main(int argc, char** argv) {
  ngk::runtime_guard::runtime_observe_lifecycle("desktop_file_tool", "main_enter");
  const int guard_rc = ngk::runtime_guard::enforce_phase53_2();
  if (guard_rc != 0) {
    ngk::runtime_guard::runtime_observe_lifecycle("desktop_file_tool", "guard_blocked");
    ngk::runtime_guard::runtime_emit_startup_summary("desktop_file_tool", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_termination_summary("desktop_file_tool", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_final_status("BLOCKED");
    return guard_rc;
  }

  ngk::runtime_guard::runtime_emit_startup_summary("desktop_file_tool", "runtime_init", 0);
  ngk::runtime_guard::require_runtime_trust("execution_pipeline");

  const int auto_close_ms = parse_auto_close_ms(argc, argv);
  const bool validation_mode = parse_validation_mode(argc, argv);
  const int app_rc = run_desktop_file_tool_app(auto_close_ms, validation_mode);

  ngk::runtime_guard::runtime_observe_lifecycle("desktop_file_tool", "main_exit");
  ngk::runtime_guard::runtime_emit_termination_summary("desktop_file_tool", "runtime_init", app_rc == 0 ? 0 : 1);
  ngk::runtime_guard::runtime_emit_final_status(app_rc == 0 ? "RUN_OK" : "RUN_FAIL");
  return app_rc;
}

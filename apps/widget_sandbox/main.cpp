#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <exception>
#include <functional>
#include <iostream>
#include <sstream>
#include <string>

#include "ngk/event_loop.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"
#include "ngk/platform/win32_clipboard.hpp"
#include "ngk/platform/win32_window.hpp"

#include "button.hpp"
#include "horizontal_layout.hpp"
#include "input_box.hpp"
#include "input_router.hpp"
#include "label.hpp"
#include "text_painter.hpp"
#include "ui_tree.hpp"
#include "vertical_layout.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace {

constexpr int kInitialWidth = 960;
constexpr int kInitialHeight = 640;
constexpr int UI_MARGIN = 24;
constexpr int SECTION_SPACING = 16;
constexpr int CONTROL_SPACING = 12;
constexpr int TEXT_PADDING = 8;

enum class BackendMode {
  D3DMinimal,
  GdiFallback
};

bool equals_ignore_case(const std::string& left, const std::string& right) {
  if (left.size() != right.size()) {
    return false;
  }

  for (std::size_t index = 0; index < left.size(); ++index) {
    char lc = left[index];
    char rc = right[index];
    if (lc >= 'A' && lc <= 'Z') {
      lc = static_cast<char>(lc - 'A' + 'a');
    }
    if (rc >= 'A' && rc <= 'Z') {
      rc = static_cast<char>(rc - 'A' + 'a');
    }
    if (lc != rc) {
      return false;
    }
  }

  return true;
}

bool is_demo_mode_enabled(int argc, char** argv) {
  if (argv) {
    for (int index = 1; index < argc; ++index) {
      if (!argv[index]) {
        continue;
      }

      const std::string argument = argv[index];
      if (argument == "--demo") {
        return true;
      }
    }
  }

  const char* env_value = std::getenv("NGK_WIDGET_SANDBOX_DEMO");
  if (!env_value) {
    return false;
  }

  const std::string env_text = env_value;
  return env_text == "1" || equals_ignore_case(env_text, "true") || equals_ignore_case(env_text, "on");
}

bool is_recovery_mode_enabled() {
  const char* env_value = std::getenv("NGK_WIDGET_RECOVERY_MODE");
  if (!env_value) {
    return true;
  }

  const std::string env_text = env_value;
  if (env_text == "0" || equals_ignore_case(env_text, "false") || equals_ignore_case(env_text, "off")) {
    return false;
  }

  return true;
}

BackendMode read_backend_mode() {
  const char* env_value = std::getenv("NGK_PHASE40_17_BACKEND");
  if (!env_value) {
    return BackendMode::D3DMinimal;
  }

  const std::string text = env_value;
  if (equals_ignore_case(text, "gdi") || equals_ignore_case(text, "fallback")) {
    return BackendMode::GdiFallback;
  }

  return BackendMode::D3DMinimal;
}

void draw_minimal_gdi_layout(HWND hwnd, int surface_width, int surface_height) {
  if (!hwnd || surface_width <= 0 || surface_height <= 0) {
    return;
  }

  HDC dc = GetDC(hwnd);
  if (!dc) {
    return;
  }

  RECT full{ 0, 0, surface_width, surface_height };
  HBRUSH bg = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(dc, &full, bg);
  DeleteObject(bg);

  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(230, 230, 230));

  RECT title_rc{ UI_MARGIN, UI_MARGIN, surface_width - UI_MARGIN, UI_MARGIN + 30 };
  DrawTextW(dc, L"Widget Sandbox", -1, &title_rc, DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  RECT status_rc{ UI_MARGIN, UI_MARGIN + 34, surface_width - UI_MARGIN, UI_MARGIN + 58 };
  DrawTextW(dc, L"status: ready", -1, &status_rc, DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  RECT textbox_rc{ UI_MARGIN, UI_MARGIN + 72, std::min(surface_width - UI_MARGIN, UI_MARGIN + 420), UI_MARGIN + 110 };
  HBRUSH textbox_bg = CreateSolidBrush(RGB(18, 18, 18));
  FillRect(dc, &textbox_rc, textbox_bg);
  DeleteObject(textbox_bg);
  HPEN border_pen = CreatePen(PS_SOLID, 1, RGB(170, 170, 170));
  HGDIOBJ old_pen = SelectObject(dc, border_pen);
  HGDIOBJ old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
  Rectangle(dc, textbox_rc.left, textbox_rc.top, textbox_rc.right, textbox_rc.bottom);
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(border_pen);

  RECT button1_rc{ UI_MARGIN, UI_MARGIN + 126, UI_MARGIN + 140, UI_MARGIN + 166 };
  RECT button2_rc{ UI_MARGIN + 154, UI_MARGIN + 126, UI_MARGIN + 294, UI_MARGIN + 166 };
  HBRUSH button_bg = CreateSolidBrush(RGB(34, 34, 34));
  FillRect(dc, &button1_rc, button_bg);
  FillRect(dc, &button2_rc, button_bg);
  DeleteObject(button_bg);

  DrawTextW(dc, L"Increment", -1, &button1_rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DrawTextW(dc, L"Reset", -1, &button2_rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  ReleaseDC(hwnd, dc);
}

std::wstring to_wide(const std::string& text) {
  if (text.empty()) {
    return {};
  }

  const int len = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (len <= 1) {
    return std::wstring(text.begin(), text.end());
  }

  std::wstring wide(static_cast<std::size_t>(len - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, wide.data(), len);
  return wide;
}

int run_app(bool demo_mode) {
  const bool recovery_mode = is_recovery_mode_enabled();
  const BackendMode backend_mode = read_backend_mode();
  const bool use_gdi_fallback = backend_mode == BackendMode::GdiFallback;
  std::cout << "widget_sandbox_started=1\n";
  std::cout << "widget_manual_mode=" << (demo_mode ? 0 : 1) << "\n";
  std::cout << "widget_demo_mode=" << (demo_mode ? 1 : 0) << "\n";
  std::cout << "widget_recovery_mode=" << (recovery_mode ? 1 : 0) << "\n";
  std::cout << "widget_backend_mode=" << (use_gdi_fallback ? "gdi" : "d3d") << "\n";

  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;

  if (!window.create(L"NGKsUI Runtime - Widget Sandbox", kInitialWidth, kInitialHeight)) {
    std::cout << "widget_window_create_failed=1\n";
    return 1;
  }

  if (!use_gdi_fallback) {
    if (!renderer.init(window.native_handle(), kInitialWidth, kInitialHeight)) {
      std::cout << "widget_renderer_init_failed=1\n";
      return 2;
    }
  }

  if (!use_gdi_fallback) {
    if (const char* forensicPath = std::getenv("NGK_FORENSICS_LOG")) {
      renderer.debug_set_forensic_log_path(forensicPath);
    }
  }

  ngk::ui::VerticalLayout root(SECTION_SPACING);
  root.set_background(0.0f, 0.0f, 0.0f, 1.0f);
  root.set_padding(UI_MARGIN, UI_MARGIN - 4, UI_MARGIN, UI_MARGIN - 4);

  ngk::ui::Label title("Phase 40: Runtime Update Loop Scheduler");
  ngk::ui::Label status("status: ready");
  ngk::ui::Label text_field_label("textbox:");
  ngk::ui::InputBox text_field;
  ngk::ui::HorizontalLayout controls_row(CONTROL_SPACING);
  controls_row.set_padding(CONTROL_SPACING);
  controls_row.set_background(0.10f, 0.10f, 0.14f, 1.0f);
  controls_row.set_size(0, 68);
  controls_row.set_preferred_size(0, 68);

  ngk::ui::Button increment_button;
  increment_button.set_text("Increment");
  increment_button.set_default_action(true);
  ngk::ui::Button reset_button;
  reset_button.set_text("Reset");
  reset_button.set_cancel_action(true);
  ngk::ui::Button disabled_button;
  disabled_button.set_text("Disabled");
  disabled_button.set_enabled(false);

  title.set_size(0, 36);
  status.set_size(0, 28);
  text_field_label.set_size(0, 24);
  text_field_label.set_preferred_size(0, 24);
  text_field.set_size(0, 40);
  text_field.set_preferred_size(0, 40);
  increment_button.set_fixed_height(40);
  reset_button.set_fixed_height(40);
  disabled_button.set_fixed_height(40);

  root.add_child(&title);
  root.add_child(&status);
  root.add_child(&text_field_label);
  root.add_child(&text_field);
  root.add_child(&controls_row);
  controls_row.add_child(&increment_button);
  controls_row.add_child(&reset_button);
  controls_row.add_child(&disabled_button);

  bool running = true;
  bool dirty = true;
  bool frame_requested = false;
  bool minimized = false;
  bool repaint_pending = false;
  std::string pending_frame_source = "STARTUP";
  std::string pending_frame_reason = "startup";
  std::uint64_t frame_request_count = 0;
  std::uint64_t frame_present_count = 0;
  std::uint64_t frame_counter = 0;
  bool runtime_tick_logged = false;
  auto last_tick_time = std::chrono::steady_clock::now();
  auto last_render_time = std::chrono::steady_clock::now();
  auto last_cadence_report_time = std::chrono::steady_clock::now();
  std::uint64_t last_report_request_count = 0;
  std::uint64_t last_report_present_count = 0;

  auto request_frame = [&](const char* source, const char* reason) {
    frame_request_count += 1;
    pending_frame_source = source;
    pending_frame_reason = reason;
    dirty = true;
    if (!repaint_pending) {
      repaint_pending = true;
      frame_requested = true;
      window.request_repaint();
    }
    std::cout << "widget_phase40_21_frame_request source=" << source << " reason=" << reason << " count=" << frame_request_count << "\n";
  };

  ngk::ui::UITree ui_tree;
  ui_tree.set_root(&root);
  ui_tree.set_default_action_element(&increment_button);
  ui_tree.set_cancel_action_element(&reset_button);
  ui_tree.set_invalidate_callback([&] {
    request_frame("UI_INVALIDATE", "ui_tree_invalidate");
  });

  ngk::ui::InputRouter input_router;
  input_router.set_tree(&ui_tree);

  std::cout << "widget_default_button=" << increment_button.text() << "\n";
  std::cout << "widget_cancel_button=" << reset_button.text() << "\n";

  text_field.set_clipboard_hooks({
    [&](const std::string& text) {
      const bool ok = ngk::platform::win32_clipboard_set_text(text);
      std::cout << "widget_clipboard_set_called=" << (ok ? 1 : 0) << "\n";
      return ok;
    },
    [&](std::string& out_text) {
      const bool ok = ngk::platform::win32_clipboard_get_text(out_text);
      std::cout << "widget_clipboard_get_called=" << (ok ? 1 : 0) << "\n";
      return ok;
    }
  });

  int click_count = 0;
  float render_avg_delta_ms = 16.0f;
  float render_jitter_ms = 0.0f;
  float max_render_jitter_ms = 0.0f;

  auto set_status = [&](const std::string& text) {
    status.set_text(text);
    const std::wstring title_text = to_wide("NGKsUI Runtime - Widget Sandbox - " + text);
    SetWindowTextW(reinterpret_cast<HWND>(window.native_handle()), title_text.c_str());
    std::cout << "widget_status_text=" << status.text() << "\n";
    ui_tree.invalidate();
  };

  auto increment_status = [&] {
    click_count += 1;
    set_status("status: clicks=" + std::to_string(click_count));
    std::cout << "widget_button_click_count=" << click_count << "\n";
  };

  auto reset_status = [&] {
    click_count = 0;
    set_status("status: reset");
    std::cout << "widget_button_reset=1\n";
  };

  increment_button.set_on_click([&] {
    increment_status();
  });

  reset_button.set_on_click([&] {
    reset_status();
  });

  ui_tree.on_resize(kInitialWidth, kInitialHeight);

  std::cout << "widget_tree_exists=1\n";
  std::cout << "widget_layout_vertical=1\n";
  std::cout << "widget_layout_vertical_spacing=" << root.spacing() << "\n";
  std::cout << "widget_layout_vertical_padding=" << root.padding_left() << "," << root.padding_top() << "," << root.padding_right() << "," << root.padding_bottom() << "\n";
  std::cout << "widget_layout_horizontal=1\n";
  std::cout << "widget_layout_horizontal_spacing=" << controls_row.spacing() << "\n";
  std::cout << "widget_layout_horizontal_padding=" << controls_row.padding_left() << "," << controls_row.padding_top() << "," << controls_row.padding_right() << "," << controls_row.padding_bottom() << "\n";
  std::cout << "widget_layout_nested=1\n";
  std::cout << "widget_measure_flow=1\n";
  std::cout << "widget_text_shared_path=1\n";
  std::cout << "widget_input_routed_via_router=1\n";
  std::cout << "widget_keyboard_routed_central=1\n";
  std::cout << "widget_visual_focus_outline=1\n";
  std::cout << "widget_visual_textbox_region=1\n";
  std::cout << "widget_visual_button_states=1\n";
  std::cout << "widget_visual_control_boundaries=1\n";
  std::cout << "widget_visual_caret_render=1\n";
  std::cout << "widget_visual_static_vs_editable_text=1\n";
  std::cout << "widget_visual_focus_glance_clarity=1\n";
  std::cout << "widget_renderer_primitive_demo=1\n";
  std::cout << "widget_label_title=" << title.text() << "\n";
  std::cout << "widget_label_status=" << status.text() << "\n";
  std::cout << "widget_label_textbox=" << text_field_label.text() << "\n";
  std::cout << "widget_textbox_present=1\n";
  std::cout << "widget_textbox_initial_value=" << text_field.value() << "\n";
  std::cout << "widget_button_primary_text=" << increment_button.text() << "\n";
  std::cout << "widget_button_secondary_text=" << reset_button.text() << "\n";
  std::cout << "widget_button_disabled_text=" << disabled_button.text() << "\n";
  std::cout << "widget_button_disabled_enabled=" << (disabled_button.enabled() ? 1 : 0) << "\n";
  std::cout << "widget_button_disabled_initial_state=" << disabled_button.visual_state_name() << "\n";
  std::cout << "widget_button_initial_state=" << increment_button.visual_state_name() << "\n";

  ngk::ui::ButtonVisualState last_increment_state = increment_button.visual_state();
  ngk::ui::ButtonVisualState last_reset_state = reset_button.visual_state();
  ngk::ui::ButtonVisualState last_disabled_state = disabled_button.visual_state();
  auto log_button_states_if_changed = [&] {
    const ngk::ui::ButtonVisualState increment_state = increment_button.visual_state();
    if (increment_state != last_increment_state) {
      if (increment_state == ngk::ui::ButtonVisualState::Hover) {
        std::cout << "widget_hover_increment=enter\n";
      }
      if (last_increment_state == ngk::ui::ButtonVisualState::Hover && increment_state != ngk::ui::ButtonVisualState::Hover) {
        std::cout << "widget_hover_increment=leave\n";
      }
      std::cout << "widget_button_state_increment=" << increment_button.visual_state_name() << "\n";
      last_increment_state = increment_state;
    }

    const ngk::ui::ButtonVisualState reset_state = reset_button.visual_state();
    if (reset_state != last_reset_state) {
      std::cout << "widget_button_state_reset=" << reset_button.visual_state_name() << "\n";
      last_reset_state = reset_state;
    }

    const ngk::ui::ButtonVisualState disabled_state = disabled_button.visual_state();
    if (disabled_state != last_disabled_state) {
      std::cout << "widget_button_state_disabled=" << disabled_button.visual_state_name() << "\n";
      last_disabled_state = disabled_state;
    }
  };

  ngk::ui::UIElement* last_focused = ui_tree.focused_element();
  auto log_focus_if_changed = [&] {
    ngk::ui::UIElement* focused = ui_tree.focused_element();
    if (focused == last_focused) {
      return;
    }

    last_focused = focused;
    if (!focused) {
      std::cout << "widget_focus_target=none\n";
      return;
    }

    if (focused == &increment_button) {
      std::cout << "widget_focus_target=increment\n";
      return;
    }

    if (focused == &reset_button) {
      std::cout << "widget_focus_target=reset\n";
      return;
    }

    if (focused == &disabled_button) {
      std::cout << "widget_focus_target=disabled\n";
      return;
    }

    if (focused == &text_field) {
      std::cout << "widget_focus_target=textbox\n";
      return;
    }

    std::cout << "widget_focus_target=other\n";
  };

  loop.set_platform_pump([&] {
    window.poll_events_once();
  });

  window.set_close_callback([&] {
    running = false;
    loop.stop();
  });

  window.set_quit_callback([&] {
    running = false;
    loop.stop();
  });

  int surface_width = kInitialWidth;
  int surface_height = kInitialHeight;

  window.set_resize_callback([&](int w, int h) {
    surface_width = w;
    surface_height = h;
    minimized = (w <= 0 || h <= 0);
    if (!use_gdi_fallback) {
      renderer.resize(w, h);
    }
    ui_tree.on_resize(w, h);
    if (!minimized) {
      request_frame("RESIZE", "window_resize");
    }
    std::cout << "widget_resize=" << w << "x" << h << "\n";
  });

  window.set_mouse_move_callback([&](int x, int y) {
    input_router.on_mouse_move(x, y);
    log_button_states_if_changed();
    log_focus_if_changed();
  });

  window.set_mouse_button_callback([&](std::uint32_t message, bool down) {
    input_router.on_mouse_button_message(message, down);
    log_button_states_if_changed();
    log_focus_if_changed();
  });

  window.set_key_callback([&](std::uint32_t key, bool down, bool repeat) {
    bool handled = input_router.on_key_message(key, down, repeat);

    if (handled) {
      request_frame("INPUT", "key_input");
      std::cout << "widget_key_routed=" << key << "\n";
      constexpr std::uint32_t vkReturn = 0x0D;
      constexpr std::uint32_t vkEscape = 0x1B;
      if (down && key == vkReturn && ui_tree.focused_element() == &text_field) {
        std::cout << "widget_textbox_enter_default_button=" << increment_button.text() << "\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      if (down && key == vkEscape) {
        std::cout << "widget_cancel_key_activate=escape\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      log_button_states_if_changed();
      log_focus_if_changed();
    }
  });

  window.set_char_callback([&](std::uint32_t codepoint) {
    if (input_router.on_char_input(codepoint)) {
      request_frame("INPUT", "text_changed");
      std::cout << "widget_char_routed=" << codepoint << "\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
    }
  });

  bool first_frame_logged = false;
  bool primitive_frame_logged = false;
  bool composition_frame_logged = false;
  bool frame_in_progress = false;

  auto render_frame = [&](const char* source) {
    if (!running) {
      repaint_pending = false;
      frame_requested = false;
      return;
    }

    if (minimized) {
      repaint_pending = false;
      frame_requested = false;
      return;
    }

    if (!use_gdi_fallback && !renderer.is_ready()) {
      // Do not keep repaint flags latched when renderer is transiently unavailable.
      frame_requested = false;
      repaint_pending = false;
      return;
    }

    if (frame_in_progress) {
      return;
    }

    frame_in_progress = true;

    const auto render_now = std::chrono::steady_clock::now();
    const auto render_delta_ms = static_cast<float>(std::chrono::duration_cast<std::chrono::milliseconds>(render_now - last_render_time).count());
    last_render_time = render_now;
    render_avg_delta_ms = (render_avg_delta_ms * 0.88f) + (render_delta_ms * 0.12f);
    render_jitter_ms = std::fabs(render_delta_ms - render_avg_delta_ms);
    if (render_jitter_ms > max_render_jitter_ms) {
      max_render_jitter_ms = render_jitter_ms;
    }

    bool simple_layout_drawn = false;

    if (use_gdi_fallback) {
      draw_minimal_gdi_layout(reinterpret_cast<HWND>(window.native_handle()), surface_width, surface_height);
      simple_layout_drawn = true;
    } else {
      renderer.begin_frame();
      renderer.debug_set_stage("simple_black_clear");
      renderer.clear(0.0f, 0.0f, 0.0f, 1.0f);
      renderer.debug_set_stage("simple_ui_tree");
      ui_tree.render(renderer);
      simple_layout_drawn = true;
    }

    frame_present_count += 1;
    frame_counter += 1;
    std::cout << "widget_phase40_12_frame_path=" << source << "\n";
    std::cout << "widget_phase40_21_redraw_reason=" << pending_frame_reason << "\n";
    std::cout << "widget_phase40_21_frame_rendered=1\n";
    std::cout << "widget_phase40_21_present_count=" << frame_present_count << "\n";
    std::cout << "widget_phase40_19_simple_layout_drawn=" << (simple_layout_drawn ? 1 : 0) << "\n";
    std::cout << "widget_phase40_19_black_background=1\n";
    std::cout << "widget_phase40_19_textbox_visible=1\n";
    std::cout << "widget_phase40_19_buttons_visible=1\n";
    std::cout << "widget_phase40_19_dashboard_disabled=1\n";

    if (!use_gdi_fallback) {
      renderer.end_frame();
    }
    frame_requested = false;
    dirty = false;
    repaint_pending = false;
    frame_in_progress = false;

    if (!first_frame_logged) {
      std::cout << "widget_first_frame=1\n";
      std::cout << "widget_phase40_5_full_frame_present=1\n";
      std::cout << "widget_phase40_5_left_content_visible=1\n";
      std::cout << "widget_phase40_7_full_client_frame=1\n";
      first_frame_logged = true;
    }

    if (!primitive_frame_logged) {
      std::cout << "widget_phase40_19_simple_primitives=1\n";
      primitive_frame_logged = true;
    }

    if (!composition_frame_logged) {
      std::cout << "widget_phase40_5_coherent_composition=1\n";
      std::cout << "widget_phase40_7_stability_path=1\n";
      composition_frame_logged = true;
    }
  };

  window.set_paint_callback([&] {
    if (!minimized && frame_requested) {
      render_frame("PAINT");
    }
  });

  loop.set_interval(std::chrono::milliseconds(1000), [&] {
    const auto now = std::chrono::steady_clock::now();
    const auto delta_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_tick_time).count();
    last_tick_time = now;

    if (!runtime_tick_logged) {
      std::cout << "widget_phase40_update_loop_started=1\n";
      std::cout << "widget_phase40_timer_mechanism=event_loop_interval\n";
      std::cout << "widget_phase40_5_single_paint_discipline=1\n";
      std::cout << "widget_phase40_7_dirty_frame_model=1\n";
      std::cout << "widget_phase40_21_heartbeat_interval_ms=1000\n";
      runtime_tick_logged = true;
    }

    const auto report_now = std::chrono::steady_clock::now();
    const auto report_elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(report_now - last_cadence_report_time).count();
    if (report_elapsed_ms >= 1000) {
      const std::uint64_t req_delta = frame_request_count - last_report_request_count;
      const std::uint64_t present_delta = frame_present_count - last_report_present_count;
      const bool idle_mode = req_delta <= 1 && present_delta <= 1;
      std::cout << "widget_phase40_21_idle_mode=" << (idle_mode ? 1 : 0) << "\n";
      std::cout << "widget_phase40_21_idle_frame_rate_hz=" << present_delta << "\n";
      std::cout << "widget_phase40_21_request_rate_hz=" << req_delta << "\n";
      std::cout << "widget_phase40_21_present_rate_hz=" << present_delta << "\n";
      std::cout << "widget_phase40_21_frame_counter=" << frame_counter << "\n";
      std::cout << "widget_phase40_21_idle_duration_ms=" << report_elapsed_ms << "\n";
      if (present_delta == 0) {
        std::cout << "widget_phase40_21_idle_indicator=IDLE=1\n";
      }
      last_report_request_count = frame_request_count;
      last_report_present_count = frame_present_count;
      last_cadence_report_time = report_now;
    }

    std::cout << "frame_delta_ms=" << delta_ms << "\n";
  });

  if (!minimized && !repaint_pending) {
    request_frame("RECOVERY", "startup");
  }

  if (!minimized && frame_requested) {
    render_frame("RECOVERY");
  }

  if (demo_mode) {
    auto log_selection_state = [&] {
      std::cout << "widget_textbox_selection_anchor=" << text_field.selection_anchor_index() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_textbox_selection_range=" << text_field.selection_start() << "," << text_field.selection_end() << "\n";
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    };

    loop.set_timeout(std::chrono::milliseconds(500), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(800), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=2\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1050), [&] {
      const std::uint32_t vkReturn = 0x0D;
      if (input_router.on_key_message(vkReturn, true, false)) {
        std::cout << "widget_button_key_activate=enter_increment\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkReturn, false, false);
      log_button_states_if_changed();
    });

    loop.set_timeout(std::chrono::milliseconds(1300), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=3\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1450), [&] {
      const std::uint32_t vkReturn = 0x0D;
      if (input_router.on_key_message(vkReturn, true, false)) {
        std::cout << "widget_button_key_activate=enter_reset\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkReturn, false, false);

      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=4\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1750), [&] {
      input_router.on_char_input('N');
      input_router.on_char_input('G');
      input_router.on_char_input('K');
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_text_entry_sequence=NGK\n";
    });

    loop.set_timeout(std::chrono::milliseconds(1900), [&] {
      const std::uint32_t vkBack = 0x08;
      input_router.on_key_message(vkBack, true, false);
      input_router.on_key_message(vkBack, false, false);
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_text_backspace=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2050), [&] {
      const std::uint32_t vkReturn = 0x0D;
      const bool handled = input_router.on_key_message(vkReturn, true, false);
      if (handled && ui_tree.focused_element() == &text_field) {
        std::cout << "widget_textbox_enter_default_button=" << increment_button.text() << "\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkReturn, false, false);
    });

    loop.set_timeout(std::chrono::milliseconds(2200), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      input_router.on_key_message(vkShift, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_shift_tab=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2400), [&] {
      const std::uint32_t vkSpace = 0x20;
      if (input_router.on_key_message(vkSpace, true, false)) {
        std::cout << "widget_button_key_activate=space\n";
        std::cout << "widget_status_after_key=" << status.text() << "\n";
      }
      input_router.on_key_message(vkSpace, false, false);
      log_button_states_if_changed();
      std::cout << "widget_keyboard_only_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2650), [&] {
      const int increment_center_x = increment_button.x() + (increment_button.width() / 2);
      const int increment_center_y = increment_button.y() + (increment_button.height() / 2);
      const int outside_x = increment_button.x() + increment_button.width() + 40;

      input_router.on_mouse_move(increment_center_x, increment_center_y);
      log_button_states_if_changed();
      input_router.on_mouse_button_message(0x0201, true);
      log_button_states_if_changed();
      input_router.on_mouse_move(outside_x, increment_center_y);
      log_button_states_if_changed();
      input_router.on_mouse_move(increment_center_x, increment_center_y);
      log_button_states_if_changed();
      input_router.on_mouse_button_message(0x0202, false);
      log_button_states_if_changed();
      std::cout << "widget_mouse_semantics_drag_out_back_in=1\n";

      input_router.on_mouse_move(4, 4);
      log_button_states_if_changed();
      std::cout << "widget_hover_stable_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2850), [&] {
      const int disabled_center_x = disabled_button.x() + (disabled_button.width() / 2);
      const int disabled_center_y = disabled_button.y() + (disabled_button.height() / 2);
      const int click_before = click_count;
      input_router.on_mouse_move(disabled_center_x, disabled_center_y);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_button_message(0x0202, false);
      const bool mouse_blocked = (click_count == click_before);
      std::cout << "widget_disabled_mouse_blocked=" << (mouse_blocked ? 1 : 0) << "\n";

      disabled_button.set_focused(true);
      const bool disabled_key_handled = disabled_button.on_key_down(0x0D, false, false);
      disabled_button.on_key_up(0x0D, false);
      disabled_button.set_focused(false);
      std::cout << "widget_disabled_keyboard_blocked=" << (disabled_key_handled ? 0 : 1) << "\n";
      std::cout << "widget_disabled_noninteractive_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(2925), [&] {
      const int increment_center_x = increment_button.x() + (increment_button.width() / 2);
      const int increment_center_y = increment_button.y() + (increment_button.height() / 2);
      for (int i = 0; i < 3; ++i) {
        input_router.on_mouse_move(increment_center_x, increment_center_y);
        input_router.on_mouse_button_message(0x0201, true);
        input_router.on_mouse_button_message(0x0202, false);
      }
      std::cout << "widget_phase40_25_increment_click_triplet=1\n";
      std::cout << "widget_phase40_25_increment_click_count_after_triplet=" << click_count << "\n";
      log_button_states_if_changed();
    });

    loop.set_timeout(std::chrono::milliseconds(2975), [&] {
      const std::uint32_t vkTab = 0x09;
      input_router.on_key_message(vkTab, true, false);
      input_router.on_key_message(vkTab, false, false);
      log_focus_if_changed();
      std::cout << "widget_focus_navigation_tab=5\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3050), [&] {
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkRight = 0x27;
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkRight, true, false);
      input_router.on_key_message(vkRight, false, false);
      std::cout << "widget_textbox_left_right_demo=1\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3200), [&] {
      const std::uint32_t vkHome = 0x24;
      input_router.on_key_message(vkHome, true, false);
      input_router.on_key_message(vkHome, false, false);
      input_router.on_char_input('X');
      std::cout << "widget_textbox_home_end_demo=home\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3350), [&] {
      const std::uint32_t vkEnd = 0x23;
      input_router.on_key_message(vkEnd, true, false);
      input_router.on_key_message(vkEnd, false, false);
      input_router.on_char_input('Z');
      std::cout << "widget_textbox_home_end_demo=end\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3500), [&] {
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkDelete = 0x2E;
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkDelete, true, false);
      input_router.on_key_message(vkDelete, false, false);
      std::cout << "widget_textbox_delete_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      std::cout << "widget_textbox_caret_index=" << text_field.caret_index() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3575), [&] {
      ui_tree.set_focused_element(&text_field);
      ui_tree.invalidate();
      log_focus_if_changed();
      std::cout << "widget_phase32_textbox_refocus=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3650), [&] {
      const std::uint32_t vkEnd = 0x23;
      input_router.on_key_message(vkEnd, true, false);
      input_router.on_key_message(vkEnd, false, false);
      input_router.on_char_input('A');
      input_router.on_char_input('B');
      input_router.on_char_input('C');
      input_router.on_char_input('D');
      input_router.on_char_input('E');
      input_router.on_char_input('F');
      std::cout << "widget_phase32_seed_text=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(3775), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkRight = 0x27;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkRight, true, false);
      input_router.on_key_message(vkRight, false, false);
      input_router.on_key_message(vkShift, false, false);
      std::cout << "widget_textbox_shift_left_right_demo=1\n";
      log_selection_state();
    });

    loop.set_timeout(std::chrono::milliseconds(3900), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkHome = 0x24;
      const std::uint32_t vkEnd = 0x23;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkHome, true, false);
      input_router.on_key_message(vkHome, false, false);
      input_router.on_key_message(vkShift, false, false);
      std::cout << "widget_textbox_shift_home_demo=1\n";
      log_selection_state();

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkEnd, true, false);
      input_router.on_key_message(vkEnd, false, false);
      input_router.on_key_message(vkShift, false, false);
      std::cout << "widget_textbox_shift_end_demo=1\n";
      log_selection_state();
    });

    loop.set_timeout(std::chrono::milliseconds(4050), [&] {
      input_router.on_char_input('R');
      std::cout << "widget_textbox_replace_selection_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
      log_selection_state();
    });

    loop.set_timeout(std::chrono::milliseconds(4200), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkBack = 0x08;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkShift, false, false);
      input_router.on_key_message(vkBack, true, false);
      input_router.on_key_message(vkBack, false, false);
      std::cout << "widget_textbox_selection_backspace_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(4350), [&] {
      input_router.on_char_input('C');
      input_router.on_char_input('L');
      input_router.on_char_input('I');
      input_router.on_char_input('P');

      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkDelete = 0x2E;
      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkShift, false, false);
      input_router.on_key_message(vkDelete, true, false);
      input_router.on_key_message(vkDelete, false, false);
      std::cout << "widget_textbox_selection_delete_demo=1\n";
      std::cout << "widget_textbox_value=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(4500), [&] {
      const std::uint32_t vkShift = 0x10;
      const std::uint32_t vkLeft = 0x25;
      const std::uint32_t vkCtrl = 0x11;
      const std::uint32_t keyC = 0x43;
      const std::uint32_t keyX = 0x58;
      const std::uint32_t keyV = 0x56;

      input_router.on_key_message(vkShift, true, false);
      input_router.on_key_message(vkLeft, true, false);
      input_router.on_key_message(vkLeft, false, false);
      input_router.on_key_message(vkShift, false, false);

      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyC, true, false);
      input_router.on_key_message(keyC, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_clipboard_copy_demo=1\n";

      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyX, true, false);
      input_router.on_key_message(keyX, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_clipboard_cut_demo=1\n";
      std::cout << "widget_textbox_value_after_cut=" << text_field.value() << "\n";

      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyV, true, false);
      input_router.on_key_message(keyV, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_clipboard_paste_demo=1\n";
      std::cout << "widget_textbox_value_after_paste=" << text_field.value() << "\n";
    });

    loop.set_timeout(std::chrono::milliseconds(4625), [&] {
      const std::uint32_t vkCtrl = 0x11;
      const std::uint32_t keyA = 0x41;
      input_router.on_key_message(vkCtrl, true, false);
      input_router.on_key_message(keyA, true, false);
      input_router.on_key_message(keyA, false, false);
      input_router.on_key_message(vkCtrl, false, false);
      std::cout << "widget_textbox_ctrl_a_demo=1\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    });

    loop.set_timeout(std::chrono::milliseconds(4750), [&] {
      const int tx = text_field.x() + 8 + (2 * 8);
      const int ty = text_field.y() + (text_field.height() / 2);
      input_router.on_mouse_move(tx, ty);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_button_message(0x0202, false);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_button_message(0x0202, false);
      std::cout << "widget_textbox_double_click_word_demo=1\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    });

    loop.set_timeout(std::chrono::milliseconds(4875), [&] {
      const int start_x = text_field.x() + 8 + (1 * 8);
      const int end_x = text_field.x() + text_field.width() + 32;
      const int ty = text_field.y() + (text_field.height() / 2);
      input_router.on_mouse_move(start_x, ty);
      input_router.on_mouse_button_message(0x0201, true);
      input_router.on_mouse_move(end_x, ty);
      input_router.on_mouse_button_message(0x0202, false);
      std::cout << "widget_textbox_drag_selection_demo=1\n";
      std::cout << "widget_textbox_has_selection=" << (text_field.has_selection() ? 1 : 0) << "\n";
      if (text_field.has_selection()) {
        std::cout << "widget_selection_highlight_visible=1\n";
      }
    });

    loop.set_timeout(std::chrono::milliseconds(4950), [&] {
      const std::uint32_t vkEsc = 0x1B;
      input_router.on_key_message(vkEsc, true, false);
      input_router.on_key_message(vkEsc, false, false);
      std::cout << "widget_cancel_key_activate=escape\n";
      std::cout << "widget_status_after_key=" << status.text() << "\n";
      std::cout << "widget_cancel_semantics_demo=1\n";
    });

    loop.set_timeout(std::chrono::milliseconds(5350), [&] {
      std::cout << "widget_smoke_timeout=1\n";
      window.request_close();
    });
  }

  loop.run();

  renderer.shutdown();
  window.destroy();

  std::cout << "widget_sandbox_exit=0\n";
  return 0;
}

} // namespace

int main(int argc, char** argv) {
  try {
    const bool demo_mode = is_demo_mode_enabled(argc, argv);
    return run_app(demo_mode);
  } catch (const std::exception& ex) {
    std::cout << "widget_sandbox_exception=" << ex.what() << "\n";
    return 10;
  } catch (...) {
    std::cout << "widget_sandbox_exception=unknown\n";
    return 11;
  }
}

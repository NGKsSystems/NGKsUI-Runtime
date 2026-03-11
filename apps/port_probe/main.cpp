#include <chrono>
#include <cstdint>
#include <exception>
#include <iostream>
#include <string>
#include <vector>

#include "ngk/event_loop.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"
#include "ngk/platform/win32_window.hpp"

#include "button.hpp"
#include "checkbox.hpp"
#include "focus_manager.hpp"
#include "input_box.hpp"
#include "label.hpp"
#include "list_panel.hpp"
#include "scroll_container.hpp"
#include "status_bar.hpp"
#include "vertical_layout.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace {

constexpr int kInitialWidth = 960;
constexpr int kInitialHeight = 640;

int to_button_code(std::uint32_t message) {
  switch (message) {
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
      return 0;
    case WM_MBUTTONDOWN:
    case WM_MBUTTONUP:
      return 1;
    case WM_RBUTTONDOWN:
    case WM_RBUTTONUP:
      return 2;
    default:
      return -1;
  }
}

int run_app() {
  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;

  if (!window.create(L"NGKsUI Runtime - Port Probe", kInitialWidth, kInitialHeight)) {
    std::cout << "port_probe_window_create_failed=1\n";
    return 1;
  }

  if (!renderer.init(window.native_handle(), kInitialWidth, kInitialHeight)) {
    std::cout << "port_probe_renderer_init_failed=1\n";
    return 2;
  }

  ngk::ui::VerticalLayout root(8);
  root.set_position(0, 0);
  root.set_size(kInitialWidth, kInitialHeight);
  root.set_background(0.02f, 0.04f, 0.10f, 1.0f);

  ngk::ui::Label title("Port Probe");
  ngk::ui::InputBox textbox;
  ngk::ui::ScrollContainer scroll_container;
  ngk::ui::ListPanel list_panel;
  ngk::ui::Button add_button;
  ngk::ui::Button remove_button;
  ngk::ui::Checkbox filter_checkbox;
  ngk::ui::StatusBar status_bar;
  ngk::ui::FocusManager focus_manager;

  textbox.set_size(0, 32);
  filter_checkbox.set_size(0, 28);
  scroll_container.set_size(0, 260);
  list_panel.set_size(0, 420);
  list_panel.set_row_height(28);
  status_bar.set_size(0, 28);

  std::vector<std::string> items;
  for (int index = 1; index <= 12; ++index) {
    items.push_back("seed_" + std::to_string(index));
  }

  auto refresh_list = [&] {
    list_panel.set_rows(items);
  };

  int selected_index = -1;

  auto set_status = [&](const std::string& status_text, const char* reason) {
    status_bar.set_text(status_text);
    std::cout << "port_probe_status=" << status_bar.text() << " reason=" << reason << "\n";
  };

  filter_checkbox.set_on_toggled([&](bool checked) {
    std::cout << "port_probe_checkbox checked=" << (checked ? 1 : 0) << "\n";
    set_status(checked ? "status=filter_on" : "status=filter_off", "checkbox");
  });

  list_panel.set_on_selection_changed([&](int index, const std::string& text) {
    selected_index = index;
    std::cout << "port_probe_select index=" << index << " text=" << text << "\n";
    set_status("status=selected:" + text, "select");
  });

  refresh_list();
  scroll_container.add_child(&list_panel);

  auto set_textbox_focus = [&](bool focused, const char* reason) {
    const bool previous = textbox.focused();
    if (focused) {
      focus_manager.set_focus(&textbox);
      textbox.set_focused(true);
    } else {
      if (focus_manager.is_focused(&textbox)) {
        focus_manager.clear_focus();
      }
      textbox.set_focused(false);
    }

    if (previous != textbox.focused()) {
      std::cout << "port_probe_focus textbox=" << (textbox.focused() ? 1 : 0) << " reason=" << reason << "\n";
    }
  };

  auto log_input = [&](const char* reason) {
    std::cout << "port_probe_input value=" << textbox.value() << " caret=" << textbox.caret_index()
              << " reason=" << reason << "\n";
  };

  add_button.set_on_click([&] {
    const std::string new_item = textbox.value();
    if (!new_item.empty()) {
      items.push_back(new_item);
      refresh_list();
      std::cout << "port_probe_add item=" << new_item << " count=" << items.size() << "\n";
      set_status("status=added:" + new_item, "add");
      textbox.set_value("");
      log_input("add_cleared");
    } else {
      std::cout << "port_probe_add item=<empty> count=" << items.size() << "\n";
      set_status("status=add_skipped_empty", "add_empty");
    }
  });

  remove_button.set_on_click([&] {
    if (selected_index >= 0 && selected_index < static_cast<int>(items.size())) {
      const std::string removed = items[static_cast<std::size_t>(selected_index)];
      items.erase(items.begin() + selected_index);
      selected_index = -1;
      refresh_list();
      std::cout << "port_probe_remove item=" << removed << " count=" << items.size() << "\n";
      set_status("status=removed:" + removed, "remove");
    } else {
      std::cout << "port_probe_remove item=<none> count=" << items.size() << "\n";
      set_status("status=remove_skipped_none", "remove_none");
    }
  });

  root.add_child(&title);
  root.add_child(&textbox);
  root.add_child(&filter_checkbox);
  root.add_child(&scroll_container);
  root.add_child(&add_button);
  root.add_child(&remove_button);
  root.add_child(&status_bar);
  root.layout();

  std::cout << "port_probe_startup=1\n";
  std::cout << "port_probe_label title=" << title.text() << "\n";
  set_status("status=ready", "startup");

  int mouse_x = 0;
  int mouse_y = 0;

  auto apply_layout_resize = [&](int width, int height, const char* source) {
    renderer.resize(width, height);
    root.set_size(width, height);
    root.on_resize(width, height);
    std::cout << "port_probe_resize source=" << source << " w=" << width << " h=" << height << "\n";
  };

  loop.set_platform_pump([&] {
    window.poll_events_once();
  });

  window.set_close_callback([&] {
    loop.stop();
  });

  window.set_quit_callback([&] {
    loop.stop();
  });

  window.set_resize_callback([&](int width, int height) {
    apply_layout_resize(width, height, "window");
  });

  window.set_mouse_move_callback([&](int x, int y) {
    mouse_x = x;
    mouse_y = y;
    root.on_mouse_move(x, y);
  });

  window.set_mouse_button_callback([&](std::uint32_t message, bool down) {
    const int button = to_button_code(message);
    if (button < 0) {
      return;
    }

    if (down && button == 0 && !textbox.contains_point(mouse_x, mouse_y) && textbox.focused()) {
      set_textbox_focus(false, "mouse_outside");
    }

    if (down) {
      root.on_mouse_down(mouse_x, mouse_y, button);
      if (button == 0 && textbox.contains_point(mouse_x, mouse_y)) {
        set_textbox_focus(true, "mouse_textbox");
      }
    } else {
      root.on_mouse_up(mouse_x, mouse_y, button);
    }
  });

  window.set_key_callback([&](std::uint32_t key, bool down, bool /*repeat*/) {
    if (!down) {
      return;
    }

    if (focus_manager.is_focused(&textbox) && textbox.on_key(key)) {
      log_input("key");
    }
  });

  window.set_char_callback([&](std::uint32_t ch) {
    if (focus_manager.is_focused(&textbox) && textbox.on_char(ch)) {
      log_input("char");
    }
  });

  window.set_mouse_wheel_callback([&](int delta) {
    if (root.on_mouse_wheel(mouse_x, mouse_y, delta)) {
      std::cout << "port_probe_scroll offset=" << scroll_container.scroll_offset() << " delta=" << delta << "\n";
    }
  });

  loop.set_interval(std::chrono::milliseconds(16), [&] {
    if (!renderer.is_ready()) {
      return;
    }

    renderer.begin_frame();
    root.render(renderer);
    renderer.end_frame();
  });

  loop.set_timeout(std::chrono::milliseconds(220), [&] {
    const int tx = textbox.x() + (textbox.width() / 2);
    const int ty = textbox.y() + (textbox.height() / 2);
    root.on_mouse_move(tx, ty);
    root.on_mouse_down(tx, ty, 0);
    root.on_mouse_up(tx, ty, 0);
    set_textbox_focus(true, "simulated_click");
  });

  loop.set_timeout(std::chrono::milliseconds(280), [&] {
    textbox.on_char(static_cast<std::uint32_t>('a'));
    log_input("simulated_char");
    textbox.on_char(static_cast<std::uint32_t>('l'));
    log_input("simulated_char");
    textbox.on_char(static_cast<std::uint32_t>('p'));
    log_input("simulated_char");
    textbox.on_char(static_cast<std::uint32_t>('h'));
    log_input("simulated_char");
    textbox.on_char(static_cast<std::uint32_t>('a'));
    log_input("simulated_char");
  });

  loop.set_timeout(std::chrono::milliseconds(340), [&] {
    const int add_x = add_button.x() + (add_button.width() / 2);
    const int add_y = add_button.y() + (add_button.height() / 2);
    root.on_mouse_move(add_x, add_y);
    root.on_mouse_down(add_x, add_y, 0);
    root.on_mouse_up(add_x, add_y, 0);
  });

  loop.set_timeout(std::chrono::milliseconds(420), [&] {
    const int sx = scroll_container.x() + 12;
    const int sy = scroll_container.y() + 16;
    root.on_mouse_move(sx, sy);
    if (root.on_mouse_wheel(sx, sy, -120)) {
      std::cout << "port_probe_scroll offset=" << scroll_container.scroll_offset() << " delta=-120 source=simulated\n";
    }
    if (root.on_mouse_wheel(sx, sy, -120)) {
      std::cout << "port_probe_scroll offset=" << scroll_container.scroll_offset() << " delta=-120 source=simulated\n";
    }
  });

  loop.set_timeout(std::chrono::milliseconds(500), [&] {
    const int lx = scroll_container.x() + 20;
    const int ly = scroll_container.y() + 44;
    root.on_mouse_move(lx, ly);
    root.on_mouse_down(lx, ly, 0);
    root.on_mouse_up(lx, ly, 0);
  });

  loop.set_timeout(std::chrono::milliseconds(620), [&] {
    const int remove_x = remove_button.x() + (remove_button.width() / 2);
    const int remove_y = remove_button.y() + (remove_button.height() / 2);
    root.on_mouse_move(remove_x, remove_y);
    root.on_mouse_down(remove_x, remove_y, 0);
    root.on_mouse_up(remove_x, remove_y, 0);
  });

  loop.set_timeout(std::chrono::milliseconds(700), [&] {
    const int cx = filter_checkbox.x() + (filter_checkbox.width() / 2);
    const int cy = filter_checkbox.y() + (filter_checkbox.height() / 2);
    root.on_mouse_move(cx, cy);
    root.on_mouse_down(cx, cy, 0);
    root.on_mouse_up(cx, cy, 0);
  });

  loop.set_timeout(std::chrono::milliseconds(5000), [&] {
    std::cout << "port_probe_exit=clean\n";
    window.request_close();
  });

  loop.run();

  renderer.shutdown();
  window.destroy();
  return 0;
}

} // namespace

int main() {
  try {
    return run_app();
  }
  catch (const std::exception& ex) {
    std::cout << "port_probe_exception=" << ex.what() << "\n";
    return 10;
  }
  catch (...) {
    std::cout << "port_probe_exception=unknown\n";
    return 11;
  }
}

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>

#include "../runtime_phase53_guard.hpp"
#include "../../engine/ui/input_router.hpp"
#include "../../engine/ui/panel.hpp"
#include "../../engine/ui/ui_element.hpp"
#include "../../engine/ui/ui_tree.hpp"
#include "ngk/core.hpp"
#include "ngk/event_loop.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"
#include "ngk/platform/win32_window.hpp"

namespace {

bool is_phase85_1_migration_slice_enabled(int argc, char** argv) {
  for (int index = 1; index < argc; ++index) {
    if (argv[index] != nullptr && std::string(argv[index]) == "--migration-slice") {
      return true;
    }
  }
  const char* env_flag = std::getenv("NGK_SANDBOX_APP_MIGRATION_SLICE");
  return env_flag != nullptr && std::string(env_flag) == "1";
}

bool is_phase87_1_legacy_fallback_enabled(int argc, char** argv) {
  for (int index = 1; index < argc; ++index) {
    if (argv[index] != nullptr && std::string(argv[index]) == "--legacy-fallback") {
      return true;
    }
  }
  const char* env_flag = std::getenv("NGK_SANDBOX_APP_LEGACY_FALLBACK");
  return env_flag != nullptr && std::string(env_flag) == "1";
}

class SandboxAppShellRoot final : public ngk::ui::UIElement {
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

class SandboxAppActionTile final : public ngk::ui::Panel {
public:
  using ActivateCallback = std::function<void()>;

  SandboxAppActionTile() {
    set_size(180, 36);
    set_preferred_size(180, 36);
    set_focusable(true);
    set_background(0.20f, 0.24f, 0.32f, 1.0f);
  }

  void set_on_activate(ActivateCallback callback) {
    on_activate_ = std::move(callback);
  }

  bool on_mouse_down(int x, int y, int button) override {
    if (button != 0 || !contains_point(x, y)) {
      return Panel::on_mouse_down(x, y, button);
    }
    pressed_ = true;
    hover_ = true;
    return true;
  }

  bool on_mouse_up(int x, int y, int button) override {
    if (button != 0) {
      return Panel::on_mouse_up(x, y, button);
    }
    const bool was_pressed = pressed_;
    pressed_ = false;
    hover_ = contains_point(x, y);
    if (was_pressed && hover_) {
      activate();
      return true;
    }
    return was_pressed;
  }

  bool on_mouse_move(int x, int y) override {
    const bool inside = contains_point(x, y);
    const bool changed = (hover_ != inside);
    hover_ = inside;
    if (!inside) {
      pressed_ = false;
    }
    return changed;
  }

  bool on_key_down(std::uint32_t key, bool /*shift*/, bool repeat) override {
    constexpr std::uint32_t vkReturn = 0x0D;
    constexpr std::uint32_t vkSpace = 0x20;
    if (!focused() || repeat) {
      return false;
    }
    if (key == vkReturn || key == vkSpace) {
      activate();
      return true;
    }
    return false;
  }

  void render(Renderer& renderer) override {
    if (!visible()) {
      return;
    }

    if (pressed_) {
      set_background(0.82f, 0.28f, 0.24f, 1.0f);
    } else if (hover_) {
      set_background(0.34f, 0.42f, 0.60f, 1.0f);
    } else if (focused()) {
      set_background(0.24f, 0.36f, 0.60f, 1.0f);
    } else {
      set_background(0.20f, 0.24f, 0.32f, 1.0f);
    }

    Panel::render(renderer);
    renderer.queue_rect_outline(x(), y(), width(), height(), 0.90f, 0.92f, 0.95f, 1.0f);
    if (focused()) {
      renderer.queue_rect_outline(x() + 2, y() + 2, width() - 4, height() - 4, 0.98f, 0.82f, 0.22f, 1.0f);
    }
  }

private:
  void activate() {
    if (on_activate_) {
      on_activate_();
    }
  }

  ActivateCallback on_activate_{};
  bool hover_ = false;
  bool pressed_ = false;
};

class SandboxAppStatusStrip final : public ngk::ui::Panel {
public:
  SandboxAppStatusStrip() {
    set_size(360, 18);
    set_preferred_size(360, 18);
    set_background(0.10f, 0.12f, 0.16f, 0.96f);
  }

  void set_value(int value) {
    if (value < 0) {
      value_ = 0;
    } else if (value > 10) {
      value_ = 10;
    } else {
      value_ = value;
    }
  }

  void render(Renderer& renderer) override {
    if (!visible()) {
      return;
    }

    Panel::render(renderer);
    renderer.queue_rect_outline(x(), y(), width(), height(), 0.72f, 0.78f, 0.88f, 1.0f);

    const int inner_x = x() + 2;
    const int inner_y = y() + 2;
    const int inner_w = width() - 4;
    const int inner_h = height() - 4;
    if (inner_w > 0 && inner_h > 0 && value_ > 0) {
      const int fill_w = (inner_w * value_) / 10;
      renderer.queue_rect(inner_x, inner_y, fill_w, inner_h, 0.22f, 0.70f, 0.30f, 1.0f);
    }
  }

private:
  int value_ = 0;
};

int run_legacy_sandbox_app() {
  std::cout << "NGKsUI Runtime Sandbox\n";
  std::cout << "core version: " << ngk::version() << "\n";

  ngk::EventLoop loop;
  std::uint64_t interval_id = 0;
  int tick_count = 0;

  loop.post([] {
    std::cout << "task ran\n";
  });

  interval_id = loop.set_interval(std::chrono::milliseconds(100), [&] {
    ++tick_count;
    std::cout << "tick " << tick_count << "\n";
    if (tick_count >= 5) {
      loop.cancel(interval_id);
      loop.stop();
    }
  });

  loop.run();
  std::cout << "shutdown ok\n";
  return 0;
}

int run_phase85_2_native_slice_app() {
  using namespace std::chrono;

  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;

  int client_w = 700;
  int client_h = 420;
  if (!window.create(L"NGKsUI Runtime Sandbox App - PHASE85_2 Native Slice", client_w, client_h)) {
    std::cout << "phase85_1_create_failed=1\n";
    return 1;
  }

  std::cout << "phase85_1_window_created=1\n";
  loop.set_platform_pump([&] { window.poll_events_once(); });
  window.set_quit_callback([&] { loop.stop(); });
  window.set_close_callback([&] { std::cout << "phase85_1_close_requested=1\n"; });

  if (!renderer.init(window.native_handle(), client_w, client_h)) {
    std::cout << "phase85_1_d3d11_init_failed=1\n";
    return 2;
  }
  std::cout << "phase85_1_d3d11_ready=1\n";

  ngk::ui::UITree native_tree;
  ngk::ui::InputRouter native_input_router;
  SandboxAppShellRoot native_root;
  ngk::ui::Panel native_shell;
  SandboxAppActionTile native_primary_action_tile;
  SandboxAppActionTile native_secondary_action_tile;
  SandboxAppStatusStrip native_status_strip;
  int native_primary_action_count = 0;
  int native_secondary_action_count = 0;
  int native_status_value = 0;

  auto layout_native_slice = [&](int w, int h) {
    native_root.set_position(0, 0);
    native_root.set_size(w, h);
    native_shell.set_position(16, 16);
    native_shell.set_size(430, 110);
    native_shell.set_preferred_size(430, 110);
    native_shell.set_background(0.14f, 0.16f, 0.21f, 0.94f);
    native_primary_action_tile.set_position(30, 36);
    native_primary_action_tile.set_size(185, 36);
    native_secondary_action_tile.set_position(223, 36);
    native_secondary_action_tile.set_size(185, 36);
    native_status_strip.set_position(30, 80);
    native_status_strip.set_size(378, 18);
  };

  native_root.add_child(&native_shell);
  native_shell.add_child(&native_primary_action_tile);
  native_shell.add_child(&native_secondary_action_tile);
  native_shell.add_child(&native_status_strip);
  native_tree.set_root(&native_root);
  native_input_router.set_tree(&native_tree);
  native_tree.set_invalidate_callback([&] { window.request_repaint(); });
  layout_native_slice(client_w, client_h);
  native_status_strip.set_value(0);
  native_tree.on_resize(client_w, client_h);
  native_tree.set_focused_element(&native_primary_action_tile);
  native_tree.invalidate();

  native_primary_action_tile.set_on_activate([&] {
    native_primary_action_count += 1;
    if (native_status_value < 10) {
      native_status_value += 1;
    }
    native_status_strip.set_value(native_status_value);
    std::cout << "phase85_2_primary_action_count=" << native_primary_action_count << "\n";
    std::cout << "phase85_2_status_value=" << native_status_value << "\n";
    native_tree.invalidate();
  });

  native_secondary_action_tile.set_on_activate([&] {
    native_secondary_action_count += 1;
    native_status_value = 0;
    native_status_strip.set_value(native_status_value);
    std::cout << "phase85_2_secondary_action_count=" << native_secondary_action_count << "\n";
    std::cout << "phase85_2_status_value=" << native_status_value << "\n";
    native_tree.invalidate();
  });

  window.set_mouse_move_callback([&](int x, int y) {
    if (native_input_router.on_mouse_move(x, y)) {
      native_tree.invalidate();
    }
  });
  window.set_mouse_button_callback([&](std::uint32_t message, bool down) {
    if (native_input_router.on_mouse_button_message(message, down)) {
      native_tree.invalidate();
    }
  });
  window.set_key_callback([&](std::uint32_t key, bool down, bool repeat) {
    if (native_input_router.on_key_message(key, down, repeat)) {
      native_tree.invalidate();
    }
  });
  window.set_char_callback([&](std::uint32_t codepoint) {
    if (native_input_router.on_char_input(codepoint)) {
      native_tree.invalidate();
    }
  });
  window.set_resize_callback([&](int w, int h) {
    if (w == 0 || h == 0) {
      return;
    }
    client_w = w;
    client_h = h;
    if (renderer.resize(w, h)) {
      layout_native_slice(w, h);
      native_tree.on_resize(w, h);
      native_tree.invalidate();
    }
  });

  const int auto_close_ms = 3500;
  loop.set_timeout(milliseconds(auto_close_ms), [&] {
    std::cout << "phase85_1_autoclose_fired=1\n";
    window.request_close();
  });

  loop.set_interval(milliseconds(1), [&] {
    renderer.begin_frame();
    renderer.clear(0.08f, 0.10f, 0.14f, 1.0f);
    native_tree.render(renderer);
    renderer.end_frame();
    if (renderer.is_device_lost()) {
      std::cout << "phase85_1_present_failed=1\n";
      loop.stop();
    }
  });

  loop.run();
  renderer.shutdown();
  window.destroy();
  std::cout << "phase85_1_shutdown_ok=1\n";
  return 0;
}

} // namespace

int main(int argc, char** argv) {
  ngk::runtime_guard::runtime_observe_lifecycle("sandbox_app", "main_enter");
  const int guard_rc = ngk::runtime_guard::enforce_phase53_2();
  if (guard_rc != 0) {
    ngk::runtime_guard::runtime_observe_lifecycle("sandbox_app", "guard_blocked");
    ngk::runtime_guard::runtime_emit_startup_summary("sandbox_app", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_termination_summary("sandbox_app", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_final_status("BLOCKED");
    return guard_rc;
  }
  ngk::runtime_guard::runtime_observe_lifecycle("sandbox_app", "guard_pass");
  ngk::runtime_guard::runtime_emit_startup_summary("sandbox_app", "runtime_init", guard_rc);

  // PHASE85_1: sandbox_app first native migration slice markers.
  std::cout << "phase85_1_sandbox_app_migration_slice_available=1\n";
  std::cout << "phase85_1_sandbox_app_migration_slice_features=win32window_d3d11_uitree_input_router_single_action_tile\n";

  // PHASE85_2: sandbox_app native migration slice expansion.
  std::cout << "phase85_2_sandbox_app_migration_expansion_available=1\n";
  std::cout << "phase85_2_sandbox_app_migration_expansion_features=dual_action_tiles_status_value_strip_shared_uitree_input_router_state_redraw\n";

  // PHASE87_1: sandbox_app wave-1 migration rollout step.
  std::cout << "phase87_1_sandbox_app_wave1_rollout_available=1\n";
  std::cout << "phase87_1_sandbox_app_wave1_rollout_features=native_slice_default_legacy_fallback_flag_and_env_preserved_trust_lifecycle_order\n";

  // PHASE89_3: default-adoption enforcement expansion for sandbox_app.
  std::cout << "phase89_3_default_adoption_enforcement_available=1\n";
  std::cout << "phase89_3_default_adoption_enforcement_contract=native_default_with_explicit_fallback_and_deterministic_mode_logging\n";

  ngk::runtime_guard::require_runtime_trust("execution_pipeline");

  const bool legacy_fallback_mode = is_phase87_1_legacy_fallback_enabled(argc, argv);
  const bool explicit_slice_mode = is_phase85_1_migration_slice_enabled(argc, argv);
  const bool use_native_rollout_path = explicit_slice_mode || !legacy_fallback_mode;
  std::cout << "phase89_3_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default\n";
  std::cout << "phase89_3_policy_fallback_requested=" << (legacy_fallback_mode ? 1 : 0) << "\n";
  std::cout << "phase89_3_policy_native_default=" << (use_native_rollout_path ? 1 : 0) << "\n";
  std::cout << "phase89_3_policy_mode_selected=" << (use_native_rollout_path ? "native_default" : "legacy_fallback") << "\n";

  const int app_rc = use_native_rollout_path
    ? run_phase85_2_native_slice_app()
    : run_legacy_sandbox_app();

  ngk::runtime_guard::runtime_observe_lifecycle("sandbox_app", "main_exit");
  ngk::runtime_guard::runtime_emit_termination_summary("sandbox_app", "runtime_init", app_rc == 0 ? 0 : 1);
  ngk::runtime_guard::runtime_emit_final_status("RUN_OK");
  return app_rc;
}

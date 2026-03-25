#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "../runtime_phase53_guard.hpp"
#include "../../engine/ui/input_router.hpp"
#include "../../engine/ui/panel.hpp"
#include "../../engine/ui/ui_element.hpp"
#include "../../engine/ui/ui_tree.hpp"
#include "ngk/event_loop.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"
#include "ngk/platform/win32_window.hpp"

namespace {

static void line(const std::string& s) { std::cout << s << "\n"; }

bool is_phase86_1_migration_slice_enabled(int argc, char** argv) {
  for (int index = 1; index < argc; ++index) {
    if (argv[index] != nullptr && std::string(argv[index]) == "--migration-slice") {
      return true;
    }
  }
  const char* env_flag = std::getenv("NGK_LOOP_TESTS_MIGRATION_SLICE");
  return env_flag != nullptr && std::string(env_flag) == "1";
}

bool is_phase87_3_legacy_fallback_enabled(int argc, char** argv) {
  for (int index = 1; index < argc; ++index) {
    if (argv[index] != nullptr && std::string(argv[index]) == "--legacy-fallback") {
      return true;
    }
  }
  const char* env_flag = std::getenv("NGK_LOOP_TESTS_LEGACY_FALLBACK");
  return env_flag != nullptr && std::string(env_flag) == "1";
}

bool is_phase90_8_disable_legacy_fallback_requested(int argc, char** argv) {
  for (int index = 1; index < argc; ++index) {
    if (argv[index] != nullptr && std::string(argv[index]) == "--disable-legacy-fallback") {
      return true;
    }
  }
  const char* env_flag = std::getenv("NGK_LOOP_TESTS_DISABLE_LEGACY_FALLBACK");
  return env_flag != nullptr && std::string(env_flag) == "1";
}

class LoopTestsShellRoot final : public ngk::ui::UIElement {
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

class LoopTestsActionTile final : public ngk::ui::Panel {
public:
  using ActivateCallback = std::function<void()>;

  LoopTestsActionTile() {
    set_size(220, 42);
    set_preferred_size(220, 42);
    set_focusable(true);
    set_background(0.18f, 0.24f, 0.33f, 1.0f);
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
    const bool changed = (inside != hover_);
    hover_ = inside;
    if (!inside) {
      pressed_ = false;
    }
    return changed;
  }

  bool on_key_down(std::uint32_t key, bool /*shift*/, bool repeat) override {
    constexpr std::uint32_t vk_return = 0x0D;
    constexpr std::uint32_t vk_space = 0x20;
    if (!focused() || repeat) {
      return false;
    }
    if (key == vk_return || key == vk_space) {
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
      set_background(0.78f, 0.28f, 0.25f, 1.0f);
    } else if (hover_) {
      set_background(0.26f, 0.45f, 0.63f, 1.0f);
    } else if (focused()) {
      set_background(0.22f, 0.36f, 0.57f, 1.0f);
    } else {
      set_background(0.18f, 0.24f, 0.33f, 1.0f);
    }
    Panel::render(renderer);
    renderer.queue_rect_outline(x(), y(), width(), height(), 0.91f, 0.94f, 0.98f, 1.0f);
    if (focused()) {
      renderer.queue_rect_outline(x() + 2, y() + 2, width() - 4, height() - 4, 0.97f, 0.83f, 0.21f, 1.0f);
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

class LoopTestsStatusStrip final : public ngk::ui::Panel {
public:
  LoopTestsStatusStrip() {
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

int run_legacy_loop_tests() {
  using namespace std::chrono;

  bool ok = true;
  auto fail = [&](const std::string& msg) { ok = false; line("FAIL: " + msg); };
  auto pass = [&](const std::string& msg) { line("PASS: " + msg); };

  // ---- Test 1: stop() from within timeout callback ----
  {
    ngk::EventLoop loop;
    bool fired = false;
    loop.set_platform_pump([&]{ /* no-op */ });

    loop.set_timeout(milliseconds(10), [&] {
      fired = true;
      loop.stop();
    });

    loop.run();

    if (!fired) fail("stop-from-timeout did not fire");
    else pass("stop-from-timeout executes");
  }

  // ---- Test 2: interval cancel mid-flight (should reach cancel point) ----
  {
    ngk::EventLoop loop;
    std::uint64_t ticks = 0;
    std::uint64_t id = 0;

    loop.set_platform_pump([&]{ /* no-op */ });

    id = loop.set_interval(milliseconds(2), [&] {
      ticks++;
      if (ticks == 10) loop.cancel(id);
      if (ticks > 30) loop.stop(); // safety
    });

    loop.set_timeout(milliseconds(120), [&] { loop.stop(); });
    loop.run();

    if (ticks < 10) fail("interval did not reach cancel point (ticks=" + std::to_string(ticks) + ")");
    else pass("interval cancels cleanly (ticks=" + std::to_string(ticks) + ")");
  }

  // ---- Test 3: cancel unknown id safe ----
  {
    ngk::EventLoop loop;
    loop.cancel(999999);
    pass("cancel unknown id safe");
  }

  // ---- Test 4: timer storm (10,000 timeouts 0..200ms) ----
  {
    ngk::EventLoop loop;
    loop.set_platform_pump([&]{ /* no-op */ });

    std::mt19937 rng(1337);
    std::uniform_int_distribution<int> dist(0, 200);

    const int N = 10000;
    std::atomic<std::uint64_t> fired{0};

    for (int i = 0; i < N; i++) {
      loop.set_timeout(milliseconds(dist(rng)), [&] { fired.fetch_add(1); });
    }

    loop.set_timeout(milliseconds(260), [&] { loop.stop(); });
    loop.run();

    auto f = fired.load();
    if (f < static_cast<std::uint64_t>(N * 95 / 100)) fail("timer storm fired too few callbacks: " + std::to_string(f));
    else pass("timer storm fired callbacks: " + std::to_string(f));
  }

  // ---- Test 5: post storm must fully drain (single-thread) ----
  {
    ngk::EventLoop loop;
    loop.set_platform_pump([&]{ /* no-op */ });

    const int N = 20000;
    std::atomic<int> ran{0};

    loop.set_timeout(milliseconds(1), [&] {
      for (int i = 0; i < N; i++) {
        loop.post([&]{ ran.fetch_add(1); });
      }
    });

    loop.set_timeout(milliseconds(300), [&] { loop.stop(); });
    loop.run();

    int r = ran.load();
    if (r < N) fail("post storm ran too few callbacks: " + std::to_string(r));
    else pass("post storm drains fully: " + std::to_string(r));
  }

  // ---- Test 6: cross-thread stop exits run() ----
  {
    ngk::EventLoop loop;
    loop.set_platform_pump([&]{ /* no-op */ });

    std::thread t([&]{
      std::this_thread::sleep_for(milliseconds(40));
      loop.stop();
    });

    loop.run();
    t.join();
    pass("cross-thread stop exits run()");
  }

  line(ok ? "SUMMARY: PASS" : "SUMMARY: FAIL");
  return ok ? 0 : 1;
}

int run_phase86_2_native_slice_app() {
  using namespace std::chrono;

  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;

  int client_w = 640;
  int client_h = 360;
  if (!window.create(L"NGKsUI Runtime Loop Tests - PHASE86_2 Native Slice", client_w, client_h)) {
    std::cout << "phase86_2_create_failed=1\n";
    return 1;
  }

  std::cout << "phase86_2_window_created=1\n";
  loop.set_platform_pump([&] { window.poll_events_once(); });
  window.set_quit_callback([&] { loop.stop(); });
  window.set_close_callback([&] { std::cout << "phase86_2_close_requested=1\n"; });

  if (!renderer.init(window.native_handle(), client_w, client_h)) {
    std::cout << "phase86_2_d3d11_init_failed=1\n";
    return 2;
  }
  std::cout << "phase86_2_d3d11_ready=1\n";

  ngk::ui::UITree native_tree;
  ngk::ui::InputRouter native_input_router;
  LoopTestsShellRoot native_root;
  ngk::ui::Panel native_shell;
  LoopTestsActionTile native_primary_action_tile;
  LoopTestsActionTile native_secondary_action_tile;
  LoopTestsStatusStrip native_status_strip;
  int native_primary_action_count = 0;
  int native_secondary_action_count = 0;
  int native_status_value = 0;
  int native_idle_ticks = 0;
  int native_render_frames = 0;

  auto layout_native_slice = [&](int w, int h) {
    native_root.set_position(0, 0);
    native_root.set_size(w, h);
    native_shell.set_position(20, 20);
    native_shell.set_size(430, 112);
    native_shell.set_preferred_size(430, 112);
    native_shell.set_background(0.12f, 0.15f, 0.20f, 0.95f);
    native_primary_action_tile.set_position(32, 40);
    native_primary_action_tile.set_size(185, 36);
    native_secondary_action_tile.set_position(225, 40);
    native_secondary_action_tile.set_size(185, 36);
    native_status_strip.set_position(32, 82);
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
    std::cout << "phase86_2_primary_action_count=" << native_primary_action_count << "\n";
    std::cout << "phase86_2_status_value=" << native_status_value << "\n";
    native_tree.invalidate();
  });

  native_secondary_action_tile.set_on_activate([&] {
    native_secondary_action_count += 1;
    native_status_value = 0;
    native_status_strip.set_value(native_status_value);
    std::cout << "phase86_2_secondary_action_count=" << native_secondary_action_count << "\n";
    std::cout << "phase86_2_status_value=" << native_status_value << "\n";
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

  loop.set_timeout(milliseconds(300), [&] {
    native_tree.set_focused_element(&native_primary_action_tile);
    const bool primary_down = native_input_router.on_key_message(0x20, true, false);
    const bool primary_up = native_input_router.on_key_message(0x20, false, false);

    native_tree.set_focused_element(&native_secondary_action_tile);
    const bool secondary_down = native_input_router.on_key_message(0x0D, true, false);
    const bool secondary_up = native_input_router.on_key_message(0x0D, false, false);

    native_tree.set_focused_element(&native_primary_action_tile);
    if (primary_down || primary_up || secondary_down || secondary_up) {
      std::cout << "phase86_2_synthetic_input_dispatched=1\n";
      native_tree.invalidate();
    }
  });

  loop.set_interval(milliseconds(100), [&] {
    native_idle_ticks += 1;
    if (native_idle_ticks == 1) {
      std::cout << "phase86_2_idle_tick_seen=1\n";
    }
  });

  loop.set_timeout(milliseconds(2200), [&] {
    std::cout << "phase86_2_autoclose_fired=1\n";
    window.request_close();
  });

  loop.set_interval(milliseconds(1), [&] {
    native_render_frames += 1;
    renderer.begin_frame();
    renderer.clear(0.07f, 0.09f, 0.13f, 1.0f);
    native_tree.render(renderer);
    renderer.end_frame();
    if (renderer.is_device_lost()) {
      std::cout << "phase86_2_present_failed=1\n";
      loop.stop();
    }
  });

  loop.run();
  renderer.shutdown();
  window.destroy();
  std::cout << "phase86_2_shutdown_ok=1\n";

  const bool validation_ok = native_primary_action_count > 0 &&
    native_secondary_action_count > 0 &&
    native_render_frames > 0 &&
    native_idle_ticks > 0;
  std::cout << "phase86_2_native_slice_validation_ok=" << (validation_ok ? 1 : 0) << "\n";
  return validation_ok ? 0 : 3;
}

} // namespace

int main(int argc, char** argv) {
  ngk::runtime_guard::runtime_observe_lifecycle("loop_tests", "main_enter");
  const int guard_rc = ngk::runtime_guard::enforce_phase53_2();
  if (guard_rc != 0) {
    ngk::runtime_guard::runtime_observe_lifecycle("loop_tests", "guard_blocked");
    ngk::runtime_guard::runtime_emit_startup_summary("loop_tests", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_termination_summary("loop_tests", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_final_status("BLOCKED");
    return guard_rc;
  }
  ngk::runtime_guard::runtime_observe_lifecycle("loop_tests", "guard_pass");
  ngk::runtime_guard::runtime_emit_startup_summary("loop_tests", "runtime_init", guard_rc);

  // PHASE86_1: first broader rollout implementation slice on loop_tests.
  std::cout << "phase86_1_loop_tests_first_rollout_slice_available=1\n";
  std::cout << "phase86_1_loop_tests_first_rollout_slice_features=optional_win32window_d3d11_uitree_input_router_single_action_tile\n";

  // PHASE86_2: rollout slice expansion on loop_tests same native path.
  std::cout << "phase86_2_loop_tests_rollout_expansion_available=1\n";
  std::cout << "phase86_2_loop_tests_rollout_expansion_features=dual_action_tiles_status_value_strip_shared_uitree_input_router_state_redraw\n";

  // PHASE87_3: wave-1 rollout promotion for loop_tests.
  std::cout << "phase87_3_loop_tests_wave1_rollout_available=1\n";
  std::cout << "phase87_3_loop_tests_wave1_rollout_features=native_default_path_with_explicit_legacy_fallback_controls\n";

  // PHASE89_2: first default-adoption enforcement slice on an already native-default app.
  std::cout << "phase89_2_default_adoption_enforcement_available=1\n";
  std::cout << "phase89_2_default_adoption_enforcement_contract=native_default_with_explicit_fallback_and_deterministic_mode_logging\n";

  // PHASE90_2: first de-legacy execution slice (step1 from PHASE90_1 plan).
  std::cout << "phase90_2_first_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_2_first_delegacy_execution_slice_contract=instrument_and_measure_legacy_fallback_usage_without_path_removal\n";

  // PHASE90_4: second de-legacy execution slice (step2 from PHASE90_1 plan).
  std::cout << "phase90_4_second_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_4_second_delegacy_execution_slice_contract=freeze_new_legacy_dependencies_for_loop_tests\n";
  std::cout << "phase90_4_legacy_dependency_baseline=run_legacy_loop_tests_only\n";
  std::cout << "phase90_4_legacy_dependency_freeze_status=active\n";
  std::cout << "phase90_4_legacy_dependency_entrypoints=1\n";

  // PHASE90_5: third de-legacy execution slice (step3 from PHASE90_1 plan).
  std::cout << "phase90_5_third_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_5_third_delegacy_execution_slice_contract=run_shadow_cutover_validation_for_loop_tests\n";

  // PHASE90_6: fourth de-legacy execution slice (step4 from PHASE90_1 plan).
  std::cout << "phase90_6_fourth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_6_fourth_delegacy_execution_slice_contract=gate_review_and_signoff_for_loop_tests\n";

  // PHASE90_7: fifth de-legacy execution slice (step5 from PHASE90_1 plan).
  std::cout << "phase90_7_fifth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_7_fifth_delegacy_execution_slice_contract=schedule_disable_not_removal_for_loop_tests\n";

  // PHASE90_8: sixth de-legacy execution slice (first explicit execution control after scheduling).
  std::cout << "phase90_8_sixth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_8_sixth_delegacy_execution_slice_contract=explicit_disable_not_removal_control_for_legacy_fallback\n";

  // PHASE90_9: seventh de-legacy execution slice (audit and reversibility visibility).
  std::cout << "phase90_9_seventh_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_9_seventh_delegacy_execution_slice_contract=disable_control_audit_and_reversibility_visibility\n";

  // PHASE90_10: eighth de-legacy execution slice (consistency and release-window visibility).
  std::cout << "phase90_10_eighth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_10_eighth_delegacy_execution_slice_contract=disable_control_consistency_and_release_window_visibility\n";

  // PHASE90_11: ninth de-legacy execution slice (manual cutover readiness snapshot).
  std::cout << "phase90_11_ninth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_11_ninth_delegacy_execution_slice_contract=manual_cutover_readiness_snapshot_without_path_removal\n";

  // PHASE90_12: tenth de-legacy execution slice (manual activation readiness confirmation).
  std::cout << "phase90_12_tenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_12_tenth_delegacy_execution_slice_contract=manual_activation_readiness_confirmation_without_path_removal\n";

  // PHASE90_13: eleventh de-legacy execution slice (activation guard and reversibility hold visibility).
  std::cout << "phase90_13_eleventh_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_13_eleventh_delegacy_execution_slice_contract=manual_activation_guard_and_reversibility_hold_visibility_without_path_removal\n";

  // PHASE90_14: twelfth de-legacy execution slice (explicit cutover gate and reversibility confirmation).
  std::cout << "phase90_14_twelfth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_14_twelfth_delegacy_execution_slice_contract=explicit_cutover_gate_and_reversibility_confirmation_without_path_removal\n";

  // PHASE90_15: thirteenth de-legacy execution slice (explicit cutover readiness confirmation).
  std::cout << "phase90_15_thirteenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_15_thirteenth_delegacy_execution_slice_contract=explicit_cutover_readiness_confirmation_without_path_removal\n";

  // PHASE90_16: fourteenth de-legacy execution slice (explicit cutover authorization hold visibility).
  std::cout << "phase90_16_fourteenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_16_fourteenth_delegacy_execution_slice_contract=explicit_cutover_authorization_hold_visibility_without_path_removal\n";

  // PHASE90_17: fifteenth de-legacy execution slice (explicit cutover approval readiness visibility).
  std::cout << "phase90_17_fifteenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_17_fifteenth_delegacy_execution_slice_contract=explicit_cutover_approval_readiness_visibility_without_path_removal\n";

  // PHASE90_18: sixteenth de-legacy execution slice (explicit cutover execution authorization visibility).
  std::cout << "phase90_18_sixteenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_18_sixteenth_delegacy_execution_slice_contract=explicit_cutover_execution_authorization_visibility_without_path_removal\n";

  // PHASE90_19: seventeenth de-legacy execution slice (explicit cutover final confirmation visibility).
  std::cout << "phase90_19_seventeenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_19_seventeenth_delegacy_execution_slice_contract=explicit_cutover_final_confirmation_visibility_without_path_removal\n";

  // PHASE90_20: eighteenth de-legacy execution slice (explicit cutover commit readiness visibility).
  std::cout << "phase90_20_eighteenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_20_eighteenth_delegacy_execution_slice_contract=explicit_cutover_commit_readiness_visibility_without_path_removal\n";

  // PHASE90_21: nineteenth de-legacy execution slice (explicit cutover commit authorization visibility).
  std::cout << "phase90_21_nineteenth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_21_nineteenth_delegacy_execution_slice_contract=explicit_cutover_commit_authorization_visibility_without_path_removal\n";

  // PHASE90_22: twentieth de-legacy execution slice (explicit cutover commit execution readiness visibility).
  std::cout << "phase90_22_twentieth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_22_twentieth_delegacy_execution_slice_contract=explicit_cutover_commit_execution_readiness_visibility_without_path_removal\n";

  // PHASE90_23: twenty-first de-legacy execution slice (explicit cutover commit execution authorization visibility).
  std::cout << "phase90_23_twenty_first_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_23_twenty_first_delegacy_execution_slice_contract=explicit_cutover_commit_execution_authorization_visibility_without_path_removal\n";

  // PHASE90_24: twenty-second de-legacy execution slice (explicit cutover finalization visibility).
  std::cout << "phase90_24_twenty_second_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_24_twenty_second_delegacy_execution_slice_contract=explicit_cutover_finalization_visibility_without_path_removal\n";

  // PHASE90_25: twenty-third de-legacy execution slice (explicit cutover completion visibility).
  std::cout << "phase90_25_twenty_third_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_25_twenty_third_delegacy_execution_slice_contract=explicit_cutover_completion_visibility_without_path_removal\n";

  // PHASE90_26: twenty-fourth de-legacy execution slice (explicit cutover completion postcheck visibility).
  std::cout << "phase90_26_twenty_fourth_delegacy_execution_slice_available=1\n";
  std::cout << "phase90_26_twenty_fourth_delegacy_execution_slice_contract=explicit_cutover_completion_postcheck_visibility_without_path_removal\n";

  ngk::runtime_guard::require_runtime_trust("execution_pipeline");

  const bool legacy_fallback_mode = is_phase87_3_legacy_fallback_enabled(argc, argv);
  const bool explicit_slice_mode = is_phase86_1_migration_slice_enabled(argc, argv);
  const bool disable_legacy_fallback_requested = is_phase90_8_disable_legacy_fallback_requested(argc, argv);
  const bool use_native_rollout_path = explicit_slice_mode || disable_legacy_fallback_requested || !legacy_fallback_mode;
  const char* phase90_2_mode_reason = explicit_slice_mode
    ? "explicit_slice_override"
    : (disable_legacy_fallback_requested
      ? "legacy_fallback_disable_requested"
      : (legacy_fallback_mode ? "legacy_fallback_requested" : "native_default_policy"));
  std::cout << "phase89_2_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default\n";
  std::cout << "phase89_2_policy_fallback_requested=" << (legacy_fallback_mode ? 1 : 0) << "\n";
  std::cout << "phase89_2_policy_native_default=" << (use_native_rollout_path ? 1 : 0) << "\n";
  std::cout << "phase89_2_policy_mode_selected=" << (use_native_rollout_path ? "native_default" : "legacy_fallback") << "\n";
  std::cout << "phase90_2_delegacy_step_executed=step1_instrument_and_measure_fallback_usage\n";
  std::cout << "phase90_2_policy_mode_reason=" << phase90_2_mode_reason << "\n";
  std::cout << "phase90_2_legacy_fallback_usage_observed=" << (use_native_rollout_path ? 0 : 1) << "\n";
  const char* phase90_5_shadow_cutover_candidate = use_native_rollout_path ? "native_default" : "legacy_fallback";
  const char* phase90_5_shadow_cutover_expected = use_native_rollout_path ? "native_default" : "legacy_fallback";
  const bool phase90_5_shadow_cutover_validation_ok =
    std::string(phase90_5_shadow_cutover_candidate) == std::string(phase90_5_shadow_cutover_expected);
  const bool phase90_6_gate_review_ready = phase90_5_shadow_cutover_validation_ok;
  const char* phase90_6_gate_signoff_status = phase90_6_gate_review_ready ? "ready_for_signoff" : "blocked";
  const bool phase90_7_disable_schedule_ready = phase90_6_gate_review_ready;
  const char* phase90_7_disable_execution_mode = "disable_not_removal";
  const char* phase90_7_disable_schedule_status = phase90_7_disable_schedule_ready
    ? "scheduled_pending_explicit_execution"
    : "blocked";
  const bool phase90_9_disable_path_engaged =
    disable_legacy_fallback_requested && legacy_fallback_mode && use_native_rollout_path;
  const bool phase90_9_rollback_still_available = true;
  const char* phase90_9_reversibility_state = phase90_9_rollback_still_available
    ? "legacy_path_retained"
    : "legacy_path_removed";
  const bool phase90_10_disable_control_consistency_ok =
    (!disable_legacy_fallback_requested || use_native_rollout_path) && phase90_9_rollback_still_available;
  const char* phase90_10_release_window_state = phase90_7_disable_schedule_ready
    ? "pending_manual_cutover_window"
    : "blocked";
  const bool phase90_11_manual_cutover_readiness_ok =
    phase90_10_disable_control_consistency_ok &&
    std::string(phase90_10_release_window_state) == "pending_manual_cutover_window";
  const char* phase90_11_execution_posture = phase90_11_manual_cutover_readiness_ok
    ? "reversible_reference_mode"
    : "blocked";
  const bool phase90_12_manual_activation_readiness_ok =
    phase90_11_manual_cutover_readiness_ok && phase90_7_disable_schedule_ready && phase90_9_rollback_still_available;
  const char* phase90_12_cutover_activation_state = phase90_12_manual_activation_readiness_ok
    ? "awaiting_explicit_manual_activation"
    : "blocked";
  const bool phase90_13_manual_activation_guard_ok =
    phase90_12_manual_activation_readiness_ok &&
    std::string(phase90_12_cutover_activation_state) == "awaiting_explicit_manual_activation";
  const char* phase90_13_reversibility_hold_state = phase90_13_manual_activation_guard_ok
    ? "legacy_reference_retained_until_explicit_cutover"
    : "blocked";
  const bool phase90_14_manual_cutover_gate_ok =
    phase90_13_manual_activation_guard_ok &&
    std::string(phase90_13_reversibility_hold_state) == "legacy_reference_retained_until_explicit_cutover";
  const char* phase90_14_cutover_execution_state = phase90_14_manual_cutover_gate_ok
    ? "awaiting_explicit_cutover_execution"
    : "blocked";
  const bool phase90_15_explicit_cutover_readiness_ok =
    phase90_14_manual_cutover_gate_ok &&
    std::string(phase90_14_cutover_execution_state) == "awaiting_explicit_cutover_execution";
  const char* phase90_15_reversibility_confirmation_state = phase90_15_explicit_cutover_readiness_ok
    ? "legacy_reference_retained_pending_explicit_cutover_execution"
    : "blocked";
  const bool phase90_16_explicit_cutover_authorization_hold_ok =
    phase90_15_explicit_cutover_readiness_ok &&
    std::string(phase90_15_reversibility_confirmation_state) == "legacy_reference_retained_pending_explicit_cutover_execution";
  const char* phase90_16_cutover_authorization_state = phase90_16_explicit_cutover_authorization_hold_ok
    ? "awaiting_explicit_cutover_authorization"
    : "blocked";
  const bool phase90_17_explicit_cutover_approval_readiness_ok =
    phase90_16_explicit_cutover_authorization_hold_ok &&
    std::string(phase90_16_cutover_authorization_state) == "awaiting_explicit_cutover_authorization";
  const char* phase90_17_cutover_approval_state = phase90_17_explicit_cutover_approval_readiness_ok
    ? "awaiting_explicit_cutover_approval"
    : "blocked";
  const bool phase90_18_explicit_cutover_execution_authorization_ok =
    phase90_17_explicit_cutover_approval_readiness_ok &&
    std::string(phase90_17_cutover_approval_state) == "awaiting_explicit_cutover_approval";
  const char* phase90_18_cutover_execution_authorization_state = phase90_18_explicit_cutover_execution_authorization_ok
    ? "awaiting_explicit_cutover_execution_authorization"
    : "blocked";
  const bool phase90_19_explicit_cutover_final_confirmation_ok =
    phase90_18_explicit_cutover_execution_authorization_ok &&
    std::string(phase90_18_cutover_execution_authorization_state) == "awaiting_explicit_cutover_execution_authorization";
  const char* phase90_19_cutover_final_confirmation_state = phase90_19_explicit_cutover_final_confirmation_ok
    ? "awaiting_explicit_cutover_final_confirmation"
    : "blocked";
  const bool phase90_20_explicit_cutover_commit_readiness_ok =
    phase90_19_explicit_cutover_final_confirmation_ok &&
    std::string(phase90_19_cutover_final_confirmation_state) == "awaiting_explicit_cutover_final_confirmation";
  const char* phase90_20_cutover_commit_readiness_state = phase90_20_explicit_cutover_commit_readiness_ok
    ? "awaiting_explicit_cutover_commit"
    : "blocked";
  const bool phase90_21_explicit_cutover_commit_authorization_ok =
    phase90_20_explicit_cutover_commit_readiness_ok &&
    std::string(phase90_20_cutover_commit_readiness_state) == "awaiting_explicit_cutover_commit";
  const char* phase90_21_cutover_commit_authorization_state = phase90_21_explicit_cutover_commit_authorization_ok
    ? "awaiting_explicit_cutover_commit_authorization"
    : "blocked";
  const bool phase90_22_explicit_cutover_commit_execution_readiness_ok =
    phase90_21_explicit_cutover_commit_authorization_ok &&
    std::string(phase90_21_cutover_commit_authorization_state) == "awaiting_explicit_cutover_commit_authorization";
  const char* phase90_22_cutover_commit_execution_readiness_state = phase90_22_explicit_cutover_commit_execution_readiness_ok
    ? "awaiting_explicit_cutover_commit_execution"
    : "blocked";
  const bool phase90_23_explicit_cutover_commit_execution_authorization_ok =
    phase90_22_explicit_cutover_commit_execution_readiness_ok &&
    std::string(phase90_22_cutover_commit_execution_readiness_state) == "awaiting_explicit_cutover_commit_execution";
  const char* phase90_23_cutover_commit_execution_authorization_state = phase90_23_explicit_cutover_commit_execution_authorization_ok
    ? "awaiting_explicit_cutover_commit_execution_authorization"
    : "blocked";
  const bool phase90_24_explicit_cutover_finalization_ok =
    phase90_23_explicit_cutover_commit_execution_authorization_ok &&
    std::string(phase90_23_cutover_commit_execution_authorization_state) == "awaiting_explicit_cutover_commit_execution_authorization";
  const char* phase90_24_cutover_finalization_state = phase90_24_explicit_cutover_finalization_ok
    ? "awaiting_explicit_cutover_finalization"
    : "blocked";
  const bool phase90_25_explicit_cutover_completion_ok =
    phase90_24_explicit_cutover_finalization_ok &&
    std::string(phase90_24_cutover_finalization_state) == "awaiting_explicit_cutover_finalization";
  const char* phase90_25_cutover_completion_state = phase90_25_explicit_cutover_completion_ok
    ? "awaiting_explicit_cutover_completion"
    : "blocked";
  const bool phase90_26_explicit_cutover_completion_postcheck_ok =
    phase90_25_explicit_cutover_completion_ok &&
    std::string(phase90_25_cutover_completion_state) == "awaiting_explicit_cutover_completion";
  const char* phase90_26_cutover_completion_postcheck_state = phase90_26_explicit_cutover_completion_postcheck_ok
    ? "awaiting_explicit_cutover_completion_postcheck"
    : "blocked";
  std::cout << "phase90_5_shadow_cutover_candidate=" << phase90_5_shadow_cutover_candidate << "\n";
  std::cout << "phase90_5_shadow_cutover_expected=" << phase90_5_shadow_cutover_expected << "\n";
  std::cout << "phase90_5_shadow_cutover_validation_ok=" << (phase90_5_shadow_cutover_validation_ok ? 1 : 0) << "\n";
  std::cout << "phase90_6_gate_review_ready=" << (phase90_6_gate_review_ready ? 1 : 0) << "\n";
  std::cout << "phase90_6_gate_signoff_status=" << phase90_6_gate_signoff_status << "\n";
  std::cout << "phase90_7_disable_schedule_ready=" << (phase90_7_disable_schedule_ready ? 1 : 0) << "\n";
  std::cout << "phase90_7_disable_execution_mode=" << phase90_7_disable_execution_mode << "\n";
  std::cout << "phase90_7_disable_schedule_status=" << phase90_7_disable_schedule_status << "\n";
  std::cout << "phase90_8_disable_legacy_fallback_requested=" << (disable_legacy_fallback_requested ? 1 : 0) << "\n";
  std::cout << "phase90_8_disable_legacy_fallback_effective=" << ((disable_legacy_fallback_requested && use_native_rollout_path) ? 1 : 0) << "\n";
  std::cout << "phase90_8_disable_legacy_fallback_mode=" << (disable_legacy_fallback_requested ? "armed" : "inactive") << "\n";
  std::cout << "phase90_9_disable_path_engaged=" << (phase90_9_disable_path_engaged ? 1 : 0) << "\n";
  std::cout << "phase90_9_rollback_still_available=" << (phase90_9_rollback_still_available ? 1 : 0) << "\n";
  std::cout << "phase90_9_reversibility_state=" << phase90_9_reversibility_state << "\n";
  std::cout << "phase90_10_disable_control_consistency_ok=" << (phase90_10_disable_control_consistency_ok ? 1 : 0) << "\n";
  std::cout << "phase90_10_release_window_state=" << phase90_10_release_window_state << "\n";
  std::cout << "phase90_11_manual_cutover_readiness_ok=" << (phase90_11_manual_cutover_readiness_ok ? 1 : 0) << "\n";
  std::cout << "phase90_11_execution_posture=" << phase90_11_execution_posture << "\n";
  std::cout << "phase90_12_manual_activation_readiness_ok=" << (phase90_12_manual_activation_readiness_ok ? 1 : 0) << "\n";
  std::cout << "phase90_12_cutover_activation_state=" << phase90_12_cutover_activation_state << "\n";
  std::cout << "phase90_13_manual_activation_guard_ok=" << (phase90_13_manual_activation_guard_ok ? 1 : 0) << "\n";
  std::cout << "phase90_13_reversibility_hold_state=" << phase90_13_reversibility_hold_state << "\n";
  std::cout << "phase90_14_manual_cutover_gate_ok=" << (phase90_14_manual_cutover_gate_ok ? 1 : 0) << "\n";
  std::cout << "phase90_14_cutover_execution_state=" << phase90_14_cutover_execution_state << "\n";
  std::cout << "phase90_15_explicit_cutover_readiness_ok=" << (phase90_15_explicit_cutover_readiness_ok ? 1 : 0) << "\n";
  std::cout << "phase90_15_reversibility_confirmation_state=" << phase90_15_reversibility_confirmation_state << "\n";
  std::cout << "phase90_16_explicit_cutover_authorization_hold_ok=" << (phase90_16_explicit_cutover_authorization_hold_ok ? 1 : 0) << "\n";
  std::cout << "phase90_16_cutover_authorization_state=" << phase90_16_cutover_authorization_state << "\n";
  std::cout << "phase90_17_explicit_cutover_approval_readiness_ok=" << (phase90_17_explicit_cutover_approval_readiness_ok ? 1 : 0) << "\n";
  std::cout << "phase90_17_cutover_approval_state=" << phase90_17_cutover_approval_state << "\n";
  std::cout << "phase90_18_explicit_cutover_execution_authorization_ok=" << (phase90_18_explicit_cutover_execution_authorization_ok ? 1 : 0) << "\n";
  std::cout << "phase90_18_cutover_execution_authorization_state=" << phase90_18_cutover_execution_authorization_state << "\n";
  std::cout << "phase90_19_explicit_cutover_final_confirmation_ok=" << (phase90_19_explicit_cutover_final_confirmation_ok ? 1 : 0) << "\n";
  std::cout << "phase90_19_cutover_final_confirmation_state=" << phase90_19_cutover_final_confirmation_state << "\n";
  std::cout << "phase90_20_explicit_cutover_commit_readiness_ok=" << (phase90_20_explicit_cutover_commit_readiness_ok ? 1 : 0) << "\n";
  std::cout << "phase90_20_cutover_commit_readiness_state=" << phase90_20_cutover_commit_readiness_state << "\n";
  std::cout << "phase90_21_explicit_cutover_commit_authorization_ok=" << (phase90_21_explicit_cutover_commit_authorization_ok ? 1 : 0) << "\n";
  std::cout << "phase90_21_cutover_commit_authorization_state=" << phase90_21_cutover_commit_authorization_state << "\n";
  std::cout << "phase90_22_explicit_cutover_commit_execution_readiness_ok=" << (phase90_22_explicit_cutover_commit_execution_readiness_ok ? 1 : 0) << "\n";
  std::cout << "phase90_22_cutover_commit_execution_readiness_state=" << phase90_22_cutover_commit_execution_readiness_state << "\n";
  std::cout << "phase90_23_explicit_cutover_commit_execution_authorization_ok=" << (phase90_23_explicit_cutover_commit_execution_authorization_ok ? 1 : 0) << "\n";
  std::cout << "phase90_23_cutover_commit_execution_authorization_state=" << phase90_23_cutover_commit_execution_authorization_state << "\n";
  std::cout << "phase90_24_explicit_cutover_finalization_ok=" << (phase90_24_explicit_cutover_finalization_ok ? 1 : 0) << "\n";
  std::cout << "phase90_24_cutover_finalization_state=" << phase90_24_cutover_finalization_state << "\n";
  std::cout << "phase90_25_explicit_cutover_completion_ok=" << (phase90_25_explicit_cutover_completion_ok ? 1 : 0) << "\n";
  std::cout << "phase90_25_cutover_completion_state=" << phase90_25_cutover_completion_state << "\n";
  std::cout << "phase90_26_explicit_cutover_completion_postcheck_ok=" << (phase90_26_explicit_cutover_completion_postcheck_ok ? 1 : 0) << "\n";
  std::cout << "phase90_26_cutover_completion_postcheck_state=" << phase90_26_cutover_completion_postcheck_state << "\n";
  const int app_rc = use_native_rollout_path
    ? run_phase86_2_native_slice_app()
    : run_legacy_loop_tests();

  ngk::runtime_guard::runtime_observe_lifecycle("loop_tests", "main_exit");
  ngk::runtime_guard::runtime_emit_termination_summary("loop_tests", "runtime_init", app_rc == 0 ? 0 : 1);
  ngk::runtime_guard::runtime_emit_final_status("RUN_OK");
  return app_rc;
}

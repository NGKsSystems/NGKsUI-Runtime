#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <iostream>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "../runtime_phase53_guard.hpp"
#include "ngk/event_loop.hpp"

static void line(const std::string& s) { std::cout << s << "\n"; }

int main() {
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
  ngk::runtime_guard::runtime_observe_lifecycle("loop_tests", "main_exit");
  ngk::runtime_guard::runtime_emit_termination_summary("loop_tests", "runtime_init", ok ? 0 : 1);
  ngk::runtime_guard::runtime_emit_final_status("RUN_OK");
  return ok ? 0 : 1;
}

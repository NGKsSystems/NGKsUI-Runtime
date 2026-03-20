#include <iostream>
#include <chrono>
#include <cstdint>
#include "../runtime_phase53_guard.hpp"
#include "ngk/core.hpp"
#include "ngk/event_loop.hpp"

int main() {
  const int guard_rc = ngk::runtime_guard::enforce_phase53_2();
  if (guard_rc != 0) {
    return guard_rc;
  }

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

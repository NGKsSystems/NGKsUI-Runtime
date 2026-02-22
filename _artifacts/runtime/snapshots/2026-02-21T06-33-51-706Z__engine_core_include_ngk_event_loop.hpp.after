#pragma once

#include <chrono>
#include <cstdint>
#include <functional>

namespace ngk {

class EventLoop {
public:
  EventLoop();
  ~EventLoop();

  // Platform pump (e.g., Win32 message pump). Called every turn.
  void set_platform_pump(std::function<void()> pump);

  // Timers
  std::uint64_t set_timeout(std::chrono::milliseconds delay, std::function<void()> cb);
  std::uint64_t set_interval(std::chrono::milliseconds period, std::function<void()> cb);

  // Cancel timeout/interval by id (safe if id unknown).
  void cancel(std::uint64_t id);

  // Post immediate task (thread-safe).
  void post(std::function<void()> cb);

  // Stop loop (thread-safe).
  void stop();

  // Run loop (blocking until stop requested).
  void run();

private:
  struct Impl;
  Impl* impl_;
};

} // namespace ngk

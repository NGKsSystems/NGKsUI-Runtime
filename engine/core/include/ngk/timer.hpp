#pragma once

#include <chrono>
#include <cstdint>
#include <functional>

namespace ngk {

class EventLoop;

class Timer {
public:
  explicit Timer(EventLoop& loop);
  ~Timer();

  Timer(const Timer&) = delete;
  Timer& operator=(const Timer&) = delete;

  Timer(Timer&& other) noexcept;
  Timer& operator=(Timer&& other) noexcept;

  void start_once(std::chrono::milliseconds delay, std::function<void()> cb);
  void stop();
  bool active() const;

private:
  EventLoop* loop_;
  std::uint64_t timer_id_;
};

} // namespace ngk

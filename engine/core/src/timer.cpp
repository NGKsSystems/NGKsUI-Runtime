#include "ngk/timer.hpp"

#include <utility>

#include "ngk/event_loop.hpp"

namespace ngk {

Timer::Timer(EventLoop& loop)
  : loop_(&loop), timer_id_(0) {}

Timer::~Timer() {
  stop();
}

Timer::Timer(Timer&& other) noexcept
  : loop_(other.loop_), timer_id_(other.timer_id_) {
  other.loop_ = nullptr;
  other.timer_id_ = 0;
}

Timer& Timer::operator=(Timer&& other) noexcept {
  if (this == &other) {
    return *this;
  }
  stop();
  loop_ = other.loop_;
  timer_id_ = other.timer_id_;
  other.loop_ = nullptr;
  other.timer_id_ = 0;
  return *this;
}

void Timer::start_once(std::chrono::milliseconds delay, std::function<void()> cb) {
  stop();
  if (!loop_) {
    return;
  }
  timer_id_ = loop_->set_timeout(delay, [fn = std::move(cb)]() mutable {
    if (fn) {
      fn();
    }
  });
}

void Timer::stop() {
  if (!loop_ || timer_id_ == 0) {
    return;
  }
  loop_->cancel(timer_id_);
  timer_id_ = 0;
}

bool Timer::active() const {
  return timer_id_ != 0;
}

} // namespace ngk

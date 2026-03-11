#include "ngk/event_queue.hpp"

#include <atomic>
#include <deque>
#include <mutex>
#include <utility>

#include "ngk/event_loop.hpp"

namespace ngk {

struct EventQueue::Impl {
  std::mutex mu;
  std::deque<std::function<void()>> pending;
  std::atomic<bool> drain_scheduled{false};
};

EventQueue::EventQueue(EventLoop& loop)
  : loop_(&loop), impl_(new Impl()) {}

EventQueue::~EventQueue() {
  delete impl_;
}

void EventQueue::post_event(std::function<void()> event_handler) {
  if (!loop_ || !event_handler) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(impl_->mu);
    impl_->pending.push_back(std::move(event_handler));
  }

  schedule_drain();
}

void EventQueue::schedule_drain() {
  bool expected = false;
  if (!impl_->drain_scheduled.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
    return;
  }

  loop_->post([this] {
    drain_once();
  });
}

void EventQueue::drain_once() {
  while (true) {
    std::function<void()> next;
    {
      std::lock_guard<std::mutex> lock(impl_->mu);
      if (impl_->pending.empty()) {
        impl_->drain_scheduled.store(false, std::memory_order_release);
        break;
      }
      next = std::move(impl_->pending.front());
      impl_->pending.pop_front();
    }

    if (next) {
      next();
    }
  }

  std::lock_guard<std::mutex> lock(impl_->mu);
  if (!impl_->pending.empty() &&
      !impl_->drain_scheduled.exchange(true, std::memory_order_acq_rel)) {
    loop_->post([this] {
      drain_once();
    });
  }
}

} // namespace ngk

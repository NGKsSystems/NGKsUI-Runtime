#include "ngk/event_loop.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

namespace ngk {

using Clock = std::chrono::steady_clock;

struct EventLoop::Impl {
  std::atomic<bool> stop_requested{false};

  // Platform pump (called every turn)
  std::function<void()> platform_pump;

  // Wake mechanics for cross-thread post/stop
  std::mutex wake_mu;
  std::condition_variable wake_cv;
  std::atomic<bool> wake_flag{false};

  struct Timeout {
    std::uint64_t id = 0;
    Clock::time_point due{};
    std::function<void()> cb;
    bool cancelled = false;
  };

  struct Interval {
    std::uint64_t id = 0;
    std::chrono::milliseconds period{0};
    Clock::time_point next_due{};
    std::function<void()> cb;
    bool cancelled = false;
  };

  std::uint64_t next_id = 1;
  std::vector<Timeout> timeouts;
  std::vector<Interval> intervals;

  // Thread-safe post queue
  std::mutex post_mu;
  std::vector<std::function<void()>> post_q;

  void request_wake() {
    wake_flag.store(true, std::memory_order_release);
    wake_cv.notify_one();
  }

  std::vector<std::function<void()>> take_posts() {
    std::lock_guard<std::mutex> lk(post_mu);
    std::vector<std::function<void()>> out;
    out.swap(post_q);
    return out;
  }

  void compact() {
    timeouts.erase(
      std::remove_if(timeouts.begin(), timeouts.end(),
        [](const Timeout& t) { return t.cancelled; }),
      timeouts.end());

    intervals.erase(
      std::remove_if(intervals.begin(), intervals.end(),
        [](const Interval& it) { return it.cancelled; }),
      intervals.end());
  }
};

static constexpr int kMaxTimerCallbacksPerTurn = 8;
static constexpr int kMaxPostCallbacksPerTurn  = 256; // posts can be bursty; keep bounded
static constexpr int kMaxTotalCallbacksPerTurn = 300; // global safety cap

EventLoop::EventLoop() : impl_(new Impl()) {}
EventLoop::~EventLoop() { delete impl_; }

void EventLoop::set_platform_pump(std::function<void()> pump) {
  impl_->platform_pump = std::move(pump);
}

std::uint64_t EventLoop::set_timeout(std::chrono::milliseconds delay, std::function<void()> cb) {
  auto* s = impl_;
  Impl::Timeout t;
  t.id = s->next_id++;
  t.due = Clock::now() + delay;
  t.cb = std::move(cb);
  s->timeouts.push_back(std::move(t));
  s->request_wake();
  return t.id;
}

std::uint64_t EventLoop::set_interval(std::chrono::milliseconds period, std::function<void()> cb) {
  auto* s = impl_;
  Impl::Interval it;
  it.id = s->next_id++;
  it.period = period;
  it.next_due = Clock::now() + period; // anti-catchup schedule
  it.cb = std::move(cb);
  s->intervals.push_back(std::move(it));
  s->request_wake();
  return it.id;
}

void EventLoop::cancel(std::uint64_t id) {
  auto* s = impl_;
  for (auto& t : s->timeouts)  if (t.id  == id) t.cancelled  = true;
  for (auto& it : s->intervals) if (it.id == id) it.cancelled = true;
  s->request_wake();
}

void EventLoop::post(std::function<void()> cb) {
  if (!cb) return;
  {
    std::lock_guard<std::mutex> lk(impl_->post_mu);
    impl_->post_q.push_back(std::move(cb));
  }
  impl_->request_wake();
}

void EventLoop::stop() {
  impl_->stop_requested.store(true, std::memory_order_release);
  impl_->request_wake();
}

void EventLoop::run() {
  auto* s = impl_;
  s->stop_requested.store(false, std::memory_order_release);

  while (!s->stop_requested.load(std::memory_order_acquire)) {
    // Always pump platform messages first to keep UI responsive.
    if (s->platform_pump) s->platform_pump();

    int callbacks_run = 0;

    // 1) Drain posted work (bounded)
    {
      auto batch = s->take_posts();
      int ran = 0;
      for (auto& fn : batch) {
        if (callbacks_run >= kMaxTotalCallbacksPerTurn) break;
        if (ran >= kMaxPostCallbacksPerTurn) break;
        if (fn) fn();
        ran++;
        callbacks_run++;
      }

      // If there were more posts than we ran, push remainder back to front.
      if (static_cast<int>(batch.size()) > ran) {
        std::lock_guard<std::mutex> lk(s->post_mu);
        // Put unprocessed items back (preserve order)
        s->post_q.insert(s->post_q.begin(), batch.begin() + ran, batch.end());
      }
    }

    const auto now = Clock::now();

    // 2) Due timeouts (bounded)
    int timer_ran = 0;
    for (auto& t : s->timeouts) {
      if (callbacks_run >= kMaxTotalCallbacksPerTurn) break;
      if (timer_ran >= kMaxTimerCallbacksPerTurn) break;
      if (!t.cancelled && t.due <= now) {
        t.cancelled = true;
        if (t.cb) t.cb();
        timer_ran++;
        callbacks_run++;
      }
    }

    // 3) Due intervals (bounded) — reschedule from NOW+period (no catch-up bursts)
    for (auto& it : s->intervals) {
      if (callbacks_run >= kMaxTotalCallbacksPerTurn) break;
      if (timer_ran >= kMaxTimerCallbacksPerTurn) break;
      if (!it.cancelled && it.next_due <= now) {
        if (it.cb) it.cb();
        timer_ran++;
        callbacks_run++;
        it.next_due = Clock::now() + it.period;
      }
    }

    s->compact();

    // 4) Sleep / wait policy
    if (callbacks_run > 0) {
      continue;
    }

    // Compute next timer deadline (cap wait to keep responsiveness)
    Clock::time_point next_due = now + std::chrono::milliseconds(8);
    for (const auto& t : s->timeouts)  if (!t.cancelled && t.due < next_due) next_due = t.due;
    for (const auto& it : s->intervals) if (!it.cancelled && it.next_due < next_due) next_due = it.next_due;

    auto wait_ms = std::chrono::duration_cast<std::chrono::milliseconds>(next_due - Clock::now()).count();
    if (wait_ms < 1) wait_ms = 1;
    if (wait_ms > 8) wait_ms = 8;

    if (wait_ms <= 2) {
      std::this_thread::yield();
      continue;
    }

    // Wait can be interrupted by post()/stop()
    std::unique_lock<std::mutex> lk(s->wake_mu);
    s->wake_cv.wait_for(lk, std::chrono::milliseconds(wait_ms), [&] {
      return s->wake_flag.exchange(false, std::memory_order_acq_rel) ||
             s->stop_requested.load(std::memory_order_acquire);
    });
  }
}

} // namespace ngk

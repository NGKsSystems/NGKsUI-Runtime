#pragma once

#include <functional>

namespace ngk {

class EventLoop;

class EventQueue {
public:
  explicit EventQueue(EventLoop& loop);
  ~EventQueue();

  void post_event(std::function<void()> event_handler);

private:
  void schedule_drain();
  void drain_once();

  EventLoop* loop_;
  struct Impl;
  Impl* impl_;
};

} // namespace ngk

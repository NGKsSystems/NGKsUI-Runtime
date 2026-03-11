#pragma once

#include <functional>

namespace ngk {

class EventLoop;

class TaskQueue {
public:
  explicit TaskQueue(EventLoop& loop);

  void post_task(std::function<void()> task);

private:
  EventLoop* loop_;
};

} // namespace ngk

#include "ngk/task_queue.hpp"

#include "ngk/event_loop.hpp"

namespace ngk {

TaskQueue::TaskQueue(EventLoop& loop)
  : loop_(&loop) {}

void TaskQueue::post_task(std::function<void()> task) {
  if (!loop_) {
    return;
  }
  loop_->post(std::move(task));
}

} // namespace ngk

#pragma once

#include <algorithm>

#include "panel.hpp"

namespace ngk::ui {

// ScrollContainer: clips child content to its own viewport bounds and
// supports vertical scrolling via mouse-wheel or direct offset control.
// Expects exactly one child (typically a VerticalLayout).
// The child's preferred_height() determines the full content height;
// the scroll container itself acts as the clipped viewport.
class ScrollContainer : public Panel {
public:
  int scroll_offset_y() const { return scroll_y_; }
  int max_scroll_y() const { return max_scroll_y_; }
  int content_height() const { return content_h_; }

  void set_scroll_offset_y(int offset) {
    scroll_y_ = std::max(0, std::min(offset, max_scroll_y_));
  }

  void set_wheel_step(int step) {
    wheel_step_ = step > 0 ? step : 40;
  }

  void layout() override {
    if (children_.empty()) {
      return;
    }
    UIElement* content = children_[0];
    const int preferred_h = content->preferred_height();
    content_h_ = preferred_h > height_ ? preferred_h : height_;
    max_scroll_y_ = std::max(0, content_h_ - height_);
    scroll_y_ = std::min(scroll_y_, max_scroll_y_);
    content->set_position(x_, y_ - scroll_y_);
    content->set_size(width_, content_h_);
    content->layout();
  }

  bool on_mouse_wheel(int x, int y, int delta) override {
    if (!contains_point(x, y)) {
      return false;
    }
    const int old_scroll_y = scroll_y_;
    set_scroll_offset_y(scroll_y_ - (delta * wheel_step_ / 120));
    return scroll_y_ != old_scroll_y;
  }

  void render(Renderer& renderer) override {
    // Draw the viewport background.
    renderer.queue_rect(x_, y_, width_, height_, bg_r_, bg_g_, bg_b_, bg_a_);
    // Clip all child rendering to the viewport bounds.
    renderer.set_clip_rect(x_, y_, width_, height_);
    for (UIElement* child : children_) {
      if (child && child->visible()) {
        child->render(renderer);
      }
    }
    renderer.reset_clip_rect();
  }

private:
  int scroll_y_ = 0;
  int max_scroll_y_ = 0;
  int content_h_ = 0;
  int wheel_step_ = 40;
};

} // namespace ngk::ui

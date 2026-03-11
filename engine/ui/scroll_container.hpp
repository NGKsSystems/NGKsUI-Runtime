#pragma once

#include <algorithm>

#include "panel.hpp"

namespace ngk::ui {

class ScrollContainer : public Panel {
public:
  ScrollContainer() {
    set_size(0, 240);
    set_background(0.10f, 0.10f, 0.12f, 1.0f);
  }

  int scroll_offset() const {
    return scroll_offset_;
  }

  int max_scroll_offset() const {
    const int max_offset = content_height_ - height();
    return max_offset > 0 ? max_offset : 0;
  }

  void set_scroll_offset(int offset) {
    scroll_offset_ = std::max(0, std::min(offset, max_scroll_offset()));
    layout();
  }

  void set_wheel_step(int step) {
    wheel_step_ = step > 0 ? step : 24;
  }

  int wheel_step() const {
    return wheel_step_;
  }

  bool on_mouse_wheel(int x, int y, int delta) override {
    if (!contains_point(x, y)) {
      return false;
    }

    const int sign = (delta > 0) ? 1 : ((delta < 0) ? -1 : 0);
    if (sign == 0) {
      return true;
    }

    set_scroll_offset(scroll_offset_ - (sign * wheel_step_));
    return true;
  }

  bool on_mouse_move(int x, int y) override {
    if (!contains_point(x, y)) {
      return false;
    }
    return Panel::on_mouse_move(x, y);
  }

  bool on_mouse_down(int x, int y, int button) override {
    if (!contains_point(x, y)) {
      return false;
    }
    return Panel::on_mouse_down(x, y, button);
  }

  bool on_mouse_up(int x, int y, int button) override {
    if (!contains_point(x, y)) {
      return false;
    }
    return Panel::on_mouse_up(x, y, button);
  }

  void on_resize(int width, int height) override {
    set_size(width, height);
    set_scroll_offset(scroll_offset_);
    layout();
  }

  void layout() override {
    int cursor_y = y() - scroll_offset_;
    int computed_height = 0;

    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }

      child->set_position(x(), cursor_y);
      child->set_size(width(), child->height() > 0 ? child->height() : 24);
      child->layout();

      cursor_y += child->height();
      computed_height += child->height();
    }

    content_height_ = computed_height;
    scroll_offset_ = std::max(0, std::min(scroll_offset_, max_scroll_offset()));

    cursor_y = y() - scroll_offset_;
    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }
      child->set_position(x(), cursor_y);
      cursor_y += child->height();
    }
  }

  void render(Renderer& renderer) override {
    if (!visible()) {
      return;
    }

    if (parent() == nullptr) {
      renderer.clear(bg_r_, bg_g_, bg_b_, bg_a_);
    }

    const int top = y();
    const int bottom = y() + height();

    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }

      const int child_top = child->y();
      const int child_bottom = child->y() + child->height();
      const bool overlaps = (child_bottom > top) && (child_top < bottom);
      if (overlaps) {
        child->render(renderer);
      }
    }
  }

private:
  int scroll_offset_ = 0;
  int content_height_ = 0;
  int wheel_step_ = 24;
};

} // namespace ngk::ui

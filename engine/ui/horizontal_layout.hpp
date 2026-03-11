#pragma once

#include <algorithm>

#include "panel.hpp"

namespace ngk::ui {

class HorizontalLayout : public Panel {
public:
  explicit HorizontalLayout(int spacing = 8) : spacing_(spacing < 0 ? 0 : spacing) {}

  void set_spacing(int spacing) {
    spacing_ = spacing < 0 ? 0 : spacing;
  }

  int spacing() const {
    return spacing_;
  }

  void set_padding(int all) {
    const int clamped = all < 0 ? 0 : all;
    padding_left_ = clamped;
    padding_top_ = clamped;
    padding_right_ = clamped;
    padding_bottom_ = clamped;
  }

  void set_padding(int left, int top, int right, int bottom) {
    padding_left_ = left < 0 ? 0 : left;
    padding_top_ = top < 0 ? 0 : top;
    padding_right_ = right < 0 ? 0 : right;
    padding_bottom_ = bottom < 0 ? 0 : bottom;
  }

  int padding_left() const { return padding_left_; }
  int padding_top() const { return padding_top_; }
  int padding_right() const { return padding_right_; }
  int padding_bottom() const { return padding_bottom_; }

  void measure(int available_width, int available_height) override {
    const int content_height = std::max(0, available_height - padding_top_ - padding_bottom_);

    int total_child_width = 0;
    int max_child_height = 0;
    int child_count = 0;
    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }

      child->measure(available_width, content_height);
      total_child_width += child->desired_width();
      max_child_height = std::max(max_child_height, child->desired_height());
      child_count += 1;
    }

    if (child_count > 1) {
      total_child_width += spacing_ * (child_count - 1);
    }

    desired_width_ = std::max(preferred_width(), total_child_width + padding_left_ + padding_right_);
    desired_height_ = std::max(preferred_height(), max_child_height + padding_top_ + padding_bottom_);
  }

  void layout() override {
    const int content_x = x_ + padding_left_;
    const int content_y = y_ + padding_top_;
    const int content_height = std::max(0, height_ - padding_top_ - padding_bottom_);

    int cursor_x = content_x;
    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }

      int child_w = child->preferred_width();
      int child_h = child->preferred_height();
      if (child_w <= 0) {
        child_w = 100;
      }
      if (child_h <= 0) {
        child_h = content_height > 0 ? content_height : 24;
      }

      const int clamped_h = std::min(content_height, child_h);
      const int y_offset = (content_height > clamped_h) ? ((content_height - clamped_h) / 2) : 0;

      child->set_position(cursor_x, content_y + y_offset);
      child->set_size(child_w, clamped_h);
      child->layout();

      cursor_x += child_w + spacing_;
    }
  }

private:
  int spacing_ = 8;
  int padding_left_ = 0;
  int padding_top_ = 0;
  int padding_right_ = 0;
  int padding_bottom_ = 0;
};

} // namespace ngk::ui

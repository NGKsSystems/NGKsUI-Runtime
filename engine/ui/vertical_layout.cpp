#include "vertical_layout.hpp"

#include <algorithm>

namespace ngk::ui {

VerticalLayout::VerticalLayout(int spacing) : spacing_(spacing < 0 ? 0 : spacing) {}

void VerticalLayout::set_spacing(int spacing) {
  spacing_ = spacing < 0 ? 0 : spacing;
}

int VerticalLayout::spacing() const { return spacing_; }

void VerticalLayout::set_padding(int all) {
  const int clamped = all < 0 ? 0 : all;
  padding_left_ = clamped;
  padding_top_ = clamped;
  padding_right_ = clamped;
  padding_bottom_ = clamped;
}

void VerticalLayout::set_padding(int left, int top, int right, int bottom) {
  padding_left_ = left < 0 ? 0 : left;
  padding_top_ = top < 0 ? 0 : top;
  padding_right_ = right < 0 ? 0 : right;
  padding_bottom_ = bottom < 0 ? 0 : bottom;
}

int VerticalLayout::padding_left() const { return padding_left_; }
int VerticalLayout::padding_top() const { return padding_top_; }
int VerticalLayout::padding_right() const { return padding_right_; }
int VerticalLayout::padding_bottom() const { return padding_bottom_; }

void VerticalLayout::measure(int available_width, int available_height) {
  const int content_width = std::max(0, available_width - padding_left_ - padding_right_);

  int max_child_width = 0;
  int total_child_height = 0;
  int child_count = 0;
  for (UIElement* child : children_) {
    if (!child || !child->visible()) {
      continue;
    }

    child->measure(content_width, available_height);
    max_child_width = std::max(max_child_width, child->desired_width());
    total_child_height += child->desired_height();
    child_count += 1;
  }

  if (child_count > 1) {
    total_child_height += spacing_ * (child_count - 1);
  }

  desired_width_ = std::max(preferred_width(), max_child_width + padding_left_ + padding_right_);
  desired_height_ = std::max(preferred_height(), total_child_height + padding_top_ + padding_bottom_);
}

void VerticalLayout::layout() {
  const int content_x = x_ + padding_left_;
  const int content_y = y_ + padding_top_;
  const int content_width = std::max(0, width_ - padding_left_ - padding_right_);

  int cursor_y = content_y;
  for (UIElement* child : children_) {
    if (!child || !child->visible()) {
      continue;
    }

    int child_h = child->preferred_height();
    if (child_h <= 0) {
      child_h = 24;
    }

    child->set_position(content_x, cursor_y);
    child->set_size(content_width, child_h);
    child->layout();

    cursor_y += child_h + spacing_;
  }
}

} // namespace ngk::ui

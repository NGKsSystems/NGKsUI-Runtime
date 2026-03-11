#pragma once

#include <algorithm>

#include "panel.hpp"

namespace ngk::ui {

class VerticalLayout : public Panel {
public:
  explicit VerticalLayout(int spacing = 0) : spacing_(spacing) {}

  void set_spacing(int spacing) { spacing_ = spacing; }
  int spacing() const { return spacing_; }

  void set_padding(int all) {
    padding_left_ = all;
    padding_top_ = all;
    padding_right_ = all;
    padding_bottom_ = all;
  }

  void set_padding(int left, int top, int right, int bottom) {
    padding_left_ = left;
    padding_top_ = top;
    padding_right_ = right;
    padding_bottom_ = bottom;
  }

  int padding_left() const { return padding_left_; }
  int padding_top() const { return padding_top_; }
  int padding_right() const { return padding_right_; }
  int padding_bottom() const { return padding_bottom_; }

  void layout() override {
    const int inner_x = x_ + padding_left_;
    const int inner_w = std::max(0, width_ - padding_left_ - padding_right_);

    int cursor_y = y_ + padding_top_;
    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }

      const int ch = child->preferred_height() > 0 ? child->preferred_height() : child->height();
      child->set_position(inner_x, cursor_y);
      child->set_size(inner_w, std::max(0, ch));
      child->layout();
      cursor_y += ch + spacing_;
    }
  }

private:
  int spacing_ = 0;
  int padding_left_ = 0;
  int padding_top_ = 0;
  int padding_right_ = 0;
  int padding_bottom_ = 0;
};

} // namespace ngk::ui

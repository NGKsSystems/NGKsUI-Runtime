#pragma once

#include <algorithm>

#include "panel.hpp"

namespace ngk::ui {

class HorizontalLayout : public Panel {
public:
  explicit HorizontalLayout(int spacing = 0) : spacing_(spacing) {}

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
    const int inner_y = y_ + padding_top_;
    const int inner_h = std::max(0, height_ - padding_top_ - padding_bottom_);

    int cursor_x = inner_x;
    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }

      const int cw = child->preferred_width() > 0 ? child->preferred_width() : child->width();
      const int ch = child->preferred_height() > 0 ? child->preferred_height() : inner_h;
      child->set_position(cursor_x, inner_y);
      child->set_size(cw, std::max(0, ch));
      child->layout();
      cursor_x += cw + spacing_;
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

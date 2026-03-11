#pragma once

#include "panel.hpp"

namespace ngk::ui {

class Toolbar : public Panel {
public:
  Toolbar() {
    set_size(0, 40);
    set_background(0.10f, 0.10f, 0.14f, 1.0f);
  }

  void set_spacing(int spacing) {
    spacing_ = spacing >= 0 ? spacing : 0;
  }

  void set_item_width(int width) {
    item_width_ = width > 0 ? width : 100;
  }

  void set_item_height(int height) {
    item_height_ = height > 0 ? height : 30;
  }

  void layout() override {
    int cursor_x = x() + spacing_;
    const int y_pos = y() + ((height() - item_height_) / 2);

    for (UIElement* child : children_) {
      if (!child || !child->visible()) {
        continue;
      }

      child->set_position(cursor_x, y_pos);
      child->set_size(item_width_, item_height_);
      child->layout();
      cursor_x += item_width_ + spacing_;
    }
  }

private:
  int spacing_ = 8;
  int item_width_ = 112;
  int item_height_ = 30;
};

} // namespace ngk::ui

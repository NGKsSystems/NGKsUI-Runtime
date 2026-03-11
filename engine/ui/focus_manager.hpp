#pragma once

#include "ui_element.hpp"

namespace ngk::ui {

class FocusManager {
public:
  UIElement* focused() const {
    return focused_;
  }

  bool is_focused(UIElement* element) const {
    return focused_ == element;
  }

  bool set_focus(UIElement* element) {
    if (focused_ == element) {
      return false;
    }
    focused_ = element;
    return true;
  }

  bool clear_focus() {
    if (!focused_) {
      return false;
    }
    focused_ = nullptr;
    return true;
  }

private:
  UIElement* focused_ = nullptr;
};

} // namespace ngk::ui

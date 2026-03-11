#pragma once

#include <cstdint>
#include <functional>
#include <utility>

#include "panel.hpp"

namespace ngk::ui {

class Checkbox : public Panel {
public:
  Checkbox() {
    set_size(0, 28);
    update_visual_state();
  }

  bool checked() const {
    return checked_;
  }

  void set_checked(bool checked) {
    if (checked_ == checked) {
      return;
    }
    checked_ = checked;
    if (on_toggled_) {
      on_toggled_(checked_);
    }
    update_visual_state();
  }

  void set_on_toggled(std::function<void(bool)> on_toggled) {
    on_toggled_ = std::move(on_toggled);
  }

  bool on_mouse_down(int x, int y, int button) override {
    if (button != 0 || !contains_point(x, y)) {
      return Panel::on_mouse_down(x, y, button);
    }
    pressed_ = true;
    update_visual_state();
    return true;
  }

  bool on_mouse_up(int x, int y, int button) override {
    if (button != 0) {
      return Panel::on_mouse_up(x, y, button);
    }

    const bool inside = contains_point(x, y);
    if (pressed_ && inside) {
      set_checked(!checked_);
    }
    pressed_ = false;
    update_visual_state();
    return inside;
  }

  bool on_mouse_move(int x, int y) override {
    hovered_ = contains_point(x, y);
    update_visual_state();
    return hovered_;
  }

private:
  void update_visual_state() {
    if (pressed_) {
      set_background(0.18f, 0.22f, 0.28f, 1.0f);
      return;
    }

    if (checked_) {
      set_background(0.10f, 0.30f, 0.16f, 1.0f);
      return;
    }

    if (hovered_) {
      set_background(0.18f, 0.18f, 0.24f, 1.0f);
      return;
    }

    set_background(0.12f, 0.12f, 0.16f, 1.0f);
  }

  bool checked_ = false;
  bool hovered_ = false;
  bool pressed_ = false;
  std::function<void(bool)> on_toggled_;
};

} // namespace ngk::ui

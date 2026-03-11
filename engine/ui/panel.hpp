#pragma once

#include "ui_element.hpp"

namespace ngk::ui {

class Panel : public UIElement {
public:
  void set_background(float r, float g, float b, float a = 1.0f) {
    bg_r_ = r;
    bg_g_ = g;
    bg_b_ = b;
    bg_a_ = a;
  }

  void layout() override {
    for (UIElement* child : children_) {
      if (child && child->visible()) {
        child->layout();
      }
    }
  }

  void render(Renderer& renderer) override {
    if (!visible_) {
      return;
    }

    if (parent_ == nullptr) {
      renderer.clear(bg_r_, bg_g_, bg_b_, bg_a_);
    }

    for (UIElement* child : children_) {
      if (child && child->visible()) {
        child->render(renderer);
      }
    }
  }

protected:
  float bg_r_ = 0.12f;
  float bg_g_ = 0.12f;
  float bg_b_ = 0.12f;
  float bg_a_ = 1.0f;
};

} // namespace ngk::ui

#include "panel.hpp"

namespace ngk::ui {

void Panel::set_background(float r, float g, float b, float a) {
  bg_r_ = r;
  bg_g_ = g;
  bg_b_ = b;
  bg_a_ = a;
}

void Panel::layout() {
  for (UIElement* child : children_) {
    if (child && child->visible()) {
      child->layout();
    }
  }
}

void Panel::render(Renderer& renderer) {
  if (!visible_) {
    return;
  }

  if (parent_ == nullptr) {
    renderer.clear(bg_r_, bg_g_, bg_b_, bg_a_);
  } else if (width_ > 0 && height_ > 0) {
    renderer.queue_rect(x_, y_, width_, height_, bg_r_, bg_g_, bg_b_, bg_a_);
  }

  for (UIElement* child : children_) {
    if (child && child->visible()) {
      child->render(renderer);
    }
  }
}

} // namespace ngk::ui

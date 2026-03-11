#pragma once

#include "ui_element.hpp"

namespace ngk::ui {

class Panel : public UIElement {
public:
  void set_background(float r, float g, float b, float a = 1.0f);

  void layout() override;
  void render(Renderer& renderer) override;

protected:
  float bg_r_ = 0.12f;
  float bg_g_ = 0.12f;
  float bg_b_ = 0.12f;
  float bg_a_ = 1.0f;
};

} // namespace ngk::ui

#pragma once

#include <string>
#include <utility>

#include "panel.hpp"
#include "text_painter.hpp"

namespace ngk::ui {

class Label : public Panel {
public:
  Label() = default;
  explicit Label(std::string text) : text_(std::move(text)) {}

  void set_text(std::string text) {
    text_ = std::move(text);
  }

  const std::string& text() const {
    return text_;
  }

  void render(Renderer& renderer) override {
    Panel::render(renderer);
    text_painter::draw(*this, renderer, text_, 0.94f, 0.94f, 0.94f, 1.0f);
  }

private:
  std::string text_;
};

} // namespace ngk::ui

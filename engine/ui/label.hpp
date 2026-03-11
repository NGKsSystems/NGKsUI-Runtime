#pragma once

#include <string>

#include "ui_element.hpp"

namespace ngk::ui {

class Label : public UIElement {
public:
  explicit Label(std::string text = "");

  void set_text(const std::string& text);
  const std::string& text() const;

  void render(Renderer& renderer) override;

private:
  std::string text_;
};

} // namespace ngk::ui

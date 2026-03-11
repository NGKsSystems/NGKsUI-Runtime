#pragma once

#include <string>
#include <utility>

#include "panel.hpp"

namespace ngk::ui {

class StatusBar : public Panel {
public:
  StatusBar() {
    set_size(0, 28);
    set_background(0.08f, 0.10f, 0.14f, 1.0f);
  }

  const std::string& text() const {
    return text_;
  }

  void set_text(std::string text) {
    text_ = std::move(text);
  }

private:
  std::string text_ = "status=idle";
};

} // namespace ngk::ui

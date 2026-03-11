#pragma once

#include <algorithm>
#include <string>

#include "ui_element.hpp"

namespace ngk::ui::text_painter {

inline int text_origin_x(const UIElement& element) {
  return element.x() + 8;
}

inline int baseline_y(const UIElement& element) {
  return element.y() + 10;
}

inline int text_line_height() {
  return 16;
}

inline int measure_prefix_width(const std::string& text, int index) {
  if (index < 0) {
    index = 0;
  }
  if (index > static_cast<int>(text.size())) {
    index = static_cast<int>(text.size());
  }
  return index * 8;
}

inline int caret_index_from_x(const std::string& text, int x) {
  if (x <= 0) {
    return 0;
  }
  const int idx = x / 8;
  return std::clamp(idx, 0, static_cast<int>(text.size()));
}

inline void draw(const UIElement& /*element*/, UIElement::Renderer& /*renderer*/, const std::string& /*text*/, float /*r*/, float /*g*/, float /*b*/, float /*a*/) {
  // Text drawing is a no-op in this minimal header restoration.
}

} // namespace ngk::ui::text_painter

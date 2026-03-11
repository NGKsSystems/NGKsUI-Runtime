#include "label.hpp"

#include <utility>

#include "text_painter.hpp"

namespace ngk::ui {

Label::Label(std::string text) : text_(std::move(text)) {
  set_size(0, 24);
  const int text_width = static_cast<int>(text_.size()) * 8;
  set_preferred_size(text_width + 16, 24);
}

void Label::set_text(const std::string& text) {
  text_ = text;
  const int text_width = static_cast<int>(text_.size()) * 8;
  set_preferred_size(text_width + 16, preferred_height() > 0 ? preferred_height() : 24);
}

const std::string& Label::text() const {
  return text_;
}

void Label::render(Renderer& renderer) {
  text_painter::draw(*this, renderer, text_);
}

} // namespace ngk::ui

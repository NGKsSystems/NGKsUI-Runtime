#include "ui_element.hpp"

namespace ngk::ui {

int UIElement::x() const { return x_; }
int UIElement::y() const { return y_; }
int UIElement::width() const { return width_; }
int UIElement::height() const { return height_; }
int UIElement::desired_width() const { return desired_width_; }
int UIElement::desired_height() const { return desired_height_; }

void UIElement::set_preferred_size(int width, int height) {
  preferred_width_ = width > 0 ? width : 0;
  preferred_height_ = height > 0 ? height : 0;
}

int UIElement::preferred_width() const {
  return preferred_width_ > 0 ? preferred_width_ : width_;
}

int UIElement::preferred_height() const {
  return preferred_height_ > 0 ? preferred_height_ : height_;
}

bool UIElement::focusable() const { return focusable_; }
void UIElement::set_focusable(bool focusable) {
  focusable_ = focusable;
  if (!focusable_ && focused_) {
    set_focused(false);
  }
}

bool UIElement::focused() const { return focused_; }
void UIElement::set_focused(bool focused) {
  if (focused_ == focused) {
    return;
  }

  focused_ = focused;
  on_focus_changed(focused_);
}

bool UIElement::wants_focus_on_click() const {
  return focusable_;
}

void UIElement::set_position(int x, int y) {
  x_ = x;
  y_ = y;
}

void UIElement::set_size(int width, int height) {
  width_ = width;
  height_ = height;
}

bool UIElement::visible() const { return visible_; }
void UIElement::set_visible(bool visible) { visible_ = visible; }

UIElement* UIElement::parent() const { return parent_; }
const std::vector<UIElement*>& UIElement::children() const { return children_; }

void UIElement::add_child(UIElement* child) {
  if (!child || child == this) {
    return;
  }
  child->parent_ = this;
  children_.push_back(child);
}

void UIElement::measure(int available_width, int available_height) {
  desired_width_ = preferred_width_ > 0 ? preferred_width_ : available_width;
  desired_height_ = preferred_height_ > 0 ? preferred_height_ : available_height;

  for (UIElement* child : children_) {
    if (child && child->visible()) {
      child->measure(available_width, available_height);
    }
  }
}

void UIElement::layout() {
  for (UIElement* child : children_) {
    if (child && child->visible()) {
      child->layout();
    }
  }
}

void UIElement::render(Renderer& renderer) {
  for (UIElement* child : children_) {
    if (child && child->visible()) {
      child->render(renderer);
    }
  }
}

bool UIElement::on_mouse_down(int x, int y, int button) {
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (child && child->visible() && child->on_mouse_down(x, y, button)) {
      return true;
    }
  }
  return false;
}

bool UIElement::on_mouse_up(int x, int y, int button) {
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (child && child->visible() && child->on_mouse_up(x, y, button)) {
      return true;
    }
  }
  return false;
}

bool UIElement::on_mouse_move(int x, int y) {
  bool handled = false;
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (child && child->visible()) {
      handled = child->on_mouse_move(x, y) || handled;
    }
  }
  return handled;
}

bool UIElement::on_mouse_wheel(int x, int y, int delta) {
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (child && child->visible() && child->on_mouse_wheel(x, y, delta)) {
      return true;
    }
  }
  return false;
}

bool UIElement::on_key_down(std::uint32_t key, bool shift, bool repeat) {
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (child && child->visible() && child->on_key_down(key, shift, repeat)) {
      return true;
    }
  }
  return false;
}

bool UIElement::on_key_up(std::uint32_t key, bool shift) {
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (child && child->visible() && child->on_key_up(key, shift)) {
      return true;
    }
  }
  return false;
}

bool UIElement::on_char(std::uint32_t codepoint) {
  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (child && child->visible() && child->on_char(codepoint)) {
      return true;
    }
  }
  return false;
}

bool UIElement::is_text_input() const {
  return false;
}

bool UIElement::perform_primary_action() {
  return false;
}

void UIElement::on_resize(int width, int height) {
  set_size(width, height);
  measure(width, height);
  layout();
}

void UIElement::on_focus_changed(bool) {}

bool UIElement::contains_point(int x, int y) const {
  return visible_ && x >= x_ && y >= y_ && x < (x_ + width_) && y < (y_ + height_);
}

UIElement* UIElement::find_topmost_focus_target_at(int x, int y) {
  if (!visible_ || !contains_point(x, y)) {
    return nullptr;
  }

  for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
    UIElement* child = *it;
    if (!child) {
      continue;
    }

    UIElement* found = child->find_topmost_focus_target_at(x, y);
    if (found) {
      return found;
    }
  }

  if (wants_focus_on_click()) {
    return this;
  }

  return nullptr;
}

} // namespace ngk::ui

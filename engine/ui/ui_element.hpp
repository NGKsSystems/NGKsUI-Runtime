#pragma once

#include <cstdint>
#include <vector>

#include "ngk/gfx/d3d11_renderer.hpp"

namespace ngk::ui {

class UIElement {
public:
  using Renderer = ngk::gfx::D3D11Renderer;

  virtual ~UIElement() = default;

  int x() const { return x_; }
  int y() const { return y_; }
  int width() const { return width_; }
  int height() const { return height_; }

  void set_position(int x, int y) {
    x_ = x;
    y_ = y;
  }

  void set_size(int width, int height) {
    width_ = width;
    height_ = height;
  }

  bool visible() const { return visible_; }
  void set_visible(bool visible) { visible_ = visible; }

  UIElement* parent() const { return parent_; }
  const std::vector<UIElement*>& children() const { return children_; }

  void add_child(UIElement* child) {
    if (!child || child == this) {
      return;
    }
    child->parent_ = this;
    children_.push_back(child);
  }

  virtual void measure(int available_width, int available_height) {
    desired_width_ = preferred_width_ > 0 ? preferred_width_ : available_width;
    desired_height_ = preferred_height_ > 0 ? preferred_height_ : available_height;

    for (UIElement* child : children_) {
      if (child && child->visible()) {
        child->measure(available_width, available_height);
      }
    }
  }

  int desired_width() const { return desired_width_; }
  int desired_height() const { return desired_height_; }

  void set_preferred_size(int width, int height) {
    preferred_width_ = width > 0 ? width : 0;
    preferred_height_ = height > 0 ? height : 0;
  }

  int preferred_width() const {
    return preferred_width_ > 0 ? preferred_width_ : width_;
  }

  int preferred_height() const {
    return preferred_height_ > 0 ? preferred_height_ : height_;
  }

  bool focusable() const { return focusable_; }
  void set_focusable(bool focusable) {
    focusable_ = focusable;
    if (!focusable_ && focused_) {
      set_focused(false);
    }
  }

  bool focused() const { return focused_; }
  void set_focused(bool focused) {
    if (focused_ == focused) {
      return;
    }

    focused_ = focused;
    on_focus_changed(focused_);
  }

  virtual bool wants_focus_on_click() const { return focusable_; }

  UIElement* find_topmost_focus_target_at(int x, int y) {
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

  virtual void layout() {
    for (UIElement* child : children_) {
      if (child && child->visible()) {
        child->layout();
      }
    }
  }

  virtual void render(Renderer& renderer) {
    for (UIElement* child : children_) {
      if (child && child->visible()) {
        child->render(renderer);
      }
    }
  }

  virtual bool on_mouse_down(int x, int y, int button) {
    for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
      UIElement* child = *it;
      if (child && child->visible() && child->on_mouse_down(x, y, button)) {
        return true;
      }
    }
    return false;
  }

  virtual bool on_mouse_up(int x, int y, int button) {
    for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
      UIElement* child = *it;
      if (child && child->visible() && child->on_mouse_up(x, y, button)) {
        return true;
      }
    }
    return false;
  }

  virtual bool on_mouse_move(int x, int y) {
    bool handled = false;
    for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
      UIElement* child = *it;
      if (child && child->visible()) {
        handled = child->on_mouse_move(x, y) || handled;
      }
    }
    return handled;
  }

  virtual bool on_mouse_wheel(int x, int y, int delta) {
    for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
      UIElement* child = *it;
      if (child && child->visible() && child->on_mouse_wheel(x, y, delta)) {
        return true;
      }
    }
    return false;
  }

  virtual bool on_key_down(std::uint32_t key, bool shift, bool repeat) {
    for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
      UIElement* child = *it;
      if (child && child->visible() && child->on_key_down(key, shift, repeat)) {
        return true;
      }
    }
    return false;
  }

  virtual bool on_key_up(std::uint32_t key, bool shift) {
    for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
      UIElement* child = *it;
      if (child && child->visible() && child->on_key_up(key, shift)) {
        return true;
      }
    }
    return false;
  }

  virtual bool on_char(std::uint32_t codepoint) {
    for (auto it = children_.rbegin(); it != children_.rend(); ++it) {
      UIElement* child = *it;
      if (child && child->visible() && child->on_char(codepoint)) {
        return true;
      }
    }
    return false;
  }

  virtual bool is_text_input() const { return false; }
  virtual bool perform_primary_action() { return false; }

  virtual void on_resize(int width, int height) {
    set_size(width, height);
    measure(width, height);
    layout();
  }

  virtual void on_focus_changed(bool focused) {
    (void)focused;
  }

  bool contains_point(int x, int y) const {
    return visible_ && x >= x_ && y >= y_ && x < (x_ + width_) && y < (y_ + height_);
  }

protected:
  int x_ = 0;
  int y_ = 0;
  int width_ = 0;
  int height_ = 0;
  int preferred_width_ = 0;
  int preferred_height_ = 0;
  int desired_width_ = 0;
  int desired_height_ = 0;
  bool visible_ = true;
  bool focusable_ = false;
  bool focused_ = false;
  UIElement* parent_ = nullptr;
  std::vector<UIElement*> children_;
};

} // namespace ngk::ui

#include "button.hpp"

#include <cstdlib>
#include <utility>

#include "text_painter.hpp"

namespace ngk::ui {

namespace {
constexpr int kMouseLeftButton = 0;

bool phase40_23_static_interaction_style() {
  const char* v = std::getenv("NGK_PHASE40_23_STATIC_INTERACTION_STYLE");
  return v && v[0] == '1';
}

bool phase40_22_static_button_style() {
  const char* v = std::getenv("NGK_PHASE40_22_STATIC_BUTTON_STYLE");
  return (v && v[0] == '1') || phase40_23_static_interaction_style();
}
}

Button::Button() {
  set_size(0, 32);
  set_preferred_size(160, 32);
  set_focusable(true);
  update_visual_state();
}

void Button::set_text(std::string text) {
  text_ = std::move(text);
  const int text_width = static_cast<int>(text_.size()) * 8;
  set_preferred_size(text_width + 28, preferred_height() > 0 ? preferred_height() : 32);
}

const std::string& Button::text() const {
  return text_;
}

ButtonVisualState Button::visual_state() const {
  return state_;
}

const char* Button::visual_state_name() const {
  switch (state_) {
    case ButtonVisualState::Normal:
      return "normal";
    case ButtonVisualState::Hover:
      return "hover";
    case ButtonVisualState::Pressed:
      return "pressed";
    case ButtonVisualState::Released:
      return "released";
    case ButtonVisualState::Disabled:
      return "disabled";
    default:
      return "unknown";
  }
}

bool Button::enabled() const {
  return enabled_;
}

bool Button::is_default_action() const {
  return default_action_;
}

void Button::set_default_action(bool is_default) {
  default_action_ = is_default;
  update_visual_state();
}

bool Button::is_cancel_action() const {
  return cancel_action_;
}

void Button::set_cancel_action(bool is_cancel) {
  cancel_action_ = is_cancel;
  update_visual_state();
}

void Button::set_enabled(bool enabled) {
  if (enabled_ == enabled) {
    return;
  }

  enabled_ = enabled;
  set_focusable(enabled_);
  if (!enabled_) {
    hovered_ = false;
    pressed_ = false;
    released_ = false;
    mouse_down_ = false;
    press_started_inside_ = false;
    if (focused()) {
      set_focused(false);
    }
  }

  update_visual_state();
}

bool Button::wants_focus_on_click() const {
  return enabled_ && focusable();
}

bool Button::perform_primary_action() {
  if (!enabled_ || !on_click_) {
    return false;
  }

  pressed_ = false;
  released_ = true;
  hovered_ = false;
  update_visual_state();
  on_click_();
  return true;
}

void Button::set_on_click(std::function<void()> on_click) {
  on_click_ = std::move(on_click);
}

void Button::set_fixed_height(int height) {
  const int fixed_height = height > 0 ? height : 32;
  set_size(width(), fixed_height);
  set_preferred_size(preferred_width() > 0 ? preferred_width() : 160, fixed_height);
}

bool Button::on_mouse_down(int x, int y, int button) {
  if (!enabled_) {
    return false;
  }

  if (button != kMouseLeftButton || !contains_point(x, y)) {
    return Panel::on_mouse_down(x, y, button);
  }

  const bool old_pressed = pressed_;
  const bool old_released = released_;
  const bool old_hovered = hovered_;

  mouse_down_ = true;
  press_started_inside_ = true;
  pressed_ = true;
  released_ = false;
  hovered_ = true;

  if (old_pressed != pressed_ || old_released != released_ || old_hovered != hovered_) {
    update_visual_state();
  }
  return true;
}

bool Button::on_mouse_up(int x, int y, int button) {
  if (!enabled_) {
    return false;
  }

  if (button != kMouseLeftButton) {
    return Panel::on_mouse_up(x, y, button);
  }

  const bool old_pressed = pressed_;
  const bool old_released = released_;
  const bool old_hovered = hovered_;

  const bool was_pressed = mouse_down_ && press_started_inside_;
  const bool inside = contains_point(x, y);
  mouse_down_ = false;
  press_started_inside_ = false;
  pressed_ = false;
  released_ = was_pressed;
  hovered_ = inside;
  if (old_pressed != pressed_ || old_released != released_ || old_hovered != hovered_) {
    update_visual_state();
  }

  if (was_pressed && inside && on_click_) {
    on_click_();
  }

  return was_pressed || inside;
}

bool Button::on_mouse_move(int x, int y) {
  if (!enabled_) {
    const bool old_hovered = hovered_;
    const bool old_pressed = pressed_;
    const bool old_released = released_;
    hovered_ = false;
    pressed_ = false;
    released_ = false;
    mouse_down_ = false;
    press_started_inside_ = false;
    if (old_hovered != hovered_ || old_pressed != pressed_ || old_released != released_) {
      update_visual_state();
      return true;
    }
    return false;
  }

  const bool old_hovered = hovered_;
  const bool old_pressed = pressed_;
  const bool old_released = released_;

  hovered_ = contains_point(x, y);
  released_ = false;
  if (mouse_down_ && press_started_inside_) {
    pressed_ = hovered_;
  } else if (!hovered_ && pressed_) {
    pressed_ = false;
  }

  const bool changed = (old_hovered != hovered_) || (old_pressed != pressed_) || (old_released != released_);
  if (changed) {
    update_visual_state();
  }
  return changed;
}

bool Button::on_key_down(std::uint32_t key, bool /*shift*/, bool repeat) {
  constexpr std::uint32_t vkReturn = 0x0D;
  constexpr std::uint32_t vkSpace = 0x20;
  if (!enabled_ || !focused() || repeat) {
    return false;
  }

  if (key != vkReturn && key != vkSpace) {
    return false;
  }

  return perform_primary_action();
}

bool Button::on_key_up(std::uint32_t key, bool /*shift*/) {
  constexpr std::uint32_t vkReturn = 0x0D;
  constexpr std::uint32_t vkSpace = 0x20;
  if (!enabled_ || !focused()) {
    return false;
  }

  if (key != vkReturn && key != vkSpace) {
    return false;
  }

  return true;
}

void Button::render(Renderer& renderer) {
  update_visual_state();
  Panel::render(renderer);

  if (width() > 0 && height() > 0) {
    if (phase40_22_static_button_style()) {
      renderer.queue_rect_outline(x(), y(), width(), height(), 0.70f, 0.70f, 0.72f, 1.0f);
    } else if (default_action_ && enabled_) {
      renderer.queue_rect_outline(x(), y(), width(), height(), 0.95f, 0.78f, 0.20f, 1.0f);
      if (width() > 2 && height() > 2) {
        renderer.queue_rect_outline(x() + 1, y() + 1, width() - 2, height() - 2, 0.95f, 0.78f, 0.20f, 1.0f);
      }
    } else {
      renderer.queue_rect_outline(x(), y(), width(), height(), 0.72f, 0.72f, 0.78f, 1.0f);
    }

    if (focused() && enabled_ && !phase40_22_static_button_style()) {
      renderer.queue_rect_outline(x() + 1, y() + 1, width() - 2, height() - 2, 0.96f, 0.86f, 0.22f, 1.0f);
    }
  }

  if (enabled_) {
    text_painter::draw(*this, renderer, text_, 0.96f, 0.96f, 0.96f, 1.0f);
  } else {
    text_painter::draw(*this, renderer, text_, 0.60f, 0.62f, 0.68f, 1.0f);
  }

  if (released_) {
    released_ = false;
    update_visual_state();
  }
}

void Button::update_visual_state() {
  if (phase40_22_static_button_style()) {
    state_ = enabled_ ? ButtonVisualState::Normal : ButtonVisualState::Disabled;
    if (enabled_) {
      set_background(0.18f, 0.20f, 0.24f, 1.0f);
    } else {
      set_background(0.11f, 0.12f, 0.15f, 1.0f);
    }
    return;
  }

  if (!enabled_) {
    state_ = ButtonVisualState::Disabled;
    set_background(0.11f, 0.12f, 0.15f, 1.0f);
    return;
  }

  if (pressed_) {
    state_ = ButtonVisualState::Pressed;
    set_background(0.78f, 0.28f, 0.24f, 1.0f);
    return;
  }

  if (released_) {
    state_ = ButtonVisualState::Released;
    set_background(0.18f, 0.56f, 0.24f, 1.0f);
    return;
  }

  if (hovered_) {
    state_ = ButtonVisualState::Hover;
    if (focused_) {
      set_background(0.24f, 0.46f, 0.86f, 1.0f);
    } else if (default_action_) {
      set_background(0.34f, 0.38f, 0.22f, 1.0f);
    } else {
      set_background(0.32f, 0.36f, 0.44f, 1.0f);
    }
    return;
  }

  state_ = ButtonVisualState::Normal;
  if (focused_) {
    set_background(0.20f, 0.32f, 0.58f, 1.0f);
  } else if (default_action_) {
    set_background(0.30f, 0.30f, 0.20f, 1.0f);
  } else {
    set_background(0.18f, 0.20f, 0.24f, 1.0f);
  }
}

} // namespace ngk::ui

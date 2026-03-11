#pragma once

#include <cstdint>
#include <functional>
#include <string>

#include "panel.hpp"

namespace ngk::ui {

enum class ButtonVisualState {
  Normal,
  Hover,
  Pressed,
  Released,
  Disabled,
};

class Button : public Panel {
public:
  Button();

  void set_text(std::string text);
  const std::string& text() const;

  ButtonVisualState visual_state() const;
  const char* visual_state_name() const;

  bool enabled() const;
  void set_enabled(bool enabled);

  bool is_default_action() const;
  void set_default_action(bool is_default);

  bool is_cancel_action() const;
  void set_cancel_action(bool is_cancel);

  void set_on_click(std::function<void()> on_click);
  void set_fixed_height(int height);

  bool wants_focus_on_click() const override;
  bool perform_primary_action() override;

  bool on_mouse_down(int x, int y, int button) override;
  bool on_mouse_up(int x, int y, int button) override;
  bool on_mouse_move(int x, int y) override;
  bool on_key_down(std::uint32_t key, bool shift, bool repeat) override;
  bool on_key_up(std::uint32_t key, bool shift) override;

  void render(Renderer& renderer) override;

private:
  void update_visual_state();

  std::string text_;
  std::function<void()> on_click_;
  ButtonVisualState state_ = ButtonVisualState::Normal;
  bool enabled_ = true;
  bool default_action_ = false;
  bool cancel_action_ = false;
  bool hovered_ = false;
  bool pressed_ = false;
  bool released_ = false;
  bool mouse_down_ = false;
  bool press_started_inside_ = false;
};

} // namespace ngk::ui

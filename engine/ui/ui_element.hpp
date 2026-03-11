#pragma once

#include <cstdint>
#include <vector>

#include "ngk/gfx/d3d11_renderer.hpp"

namespace ngk::ui {

class UIElement {
public:
  using Renderer = ngk::gfx::D3D11Renderer;

  virtual ~UIElement() = default;

  int x() const;
  int y() const;
  int width() const;
  int height() const;

  void set_position(int x, int y);
  void set_size(int width, int height);

  bool visible() const;
  void set_visible(bool visible);

  UIElement* parent() const;
  const std::vector<UIElement*>& children() const;

  void add_child(UIElement* child);

  virtual void measure(int available_width, int available_height);
  int desired_width() const;
  int desired_height() const;

  void set_preferred_size(int width, int height);
  int preferred_width() const;
  int preferred_height() const;

  bool focusable() const;
  void set_focusable(bool focusable);
  bool focused() const;
  void set_focused(bool focused);

  virtual bool wants_focus_on_click() const;

  UIElement* find_topmost_focus_target_at(int x, int y);

  virtual void layout();
  virtual void render(Renderer& renderer);

  virtual bool on_mouse_down(int x, int y, int button);
  virtual bool on_mouse_up(int x, int y, int button);
  virtual bool on_mouse_move(int x, int y);
  virtual bool on_mouse_wheel(int x, int y, int delta);
  virtual bool on_key_down(std::uint32_t key, bool shift, bool repeat);
  virtual bool on_key_up(std::uint32_t key, bool shift);
  virtual bool on_char(std::uint32_t codepoint);
  virtual bool is_text_input() const;
  virtual bool perform_primary_action();

  virtual void on_resize(int width, int height);
  virtual void on_focus_changed(bool focused);

  bool contains_point(int x, int y) const;

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

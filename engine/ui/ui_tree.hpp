#pragma once

#include <cstdlib>
#include <cstdint>
#include <functional>
#include <utility>
#include <vector>

#include "ui_element.hpp"

namespace ngk::ui {

namespace {
inline bool phase40_24_strict_coupling_mode() {
  const char* v = std::getenv("NGK_PHASE40_24_STRICT_COUPLING");
  return v && v[0] == '1';
}

inline bool phase40_25_mouse_down_up_decouple_enabled() {
  const char* v = std::getenv("NGK_PHASE40_25_MOUSE_DOWN_UP_DECOUPLE");
  if (v && v[0] == '0') {
    return false;
  }
  return true;
}
}

class UITree {
public:
  using Renderer = UIElement::Renderer;
  using InvalidateCallback = std::function<void()>;

  UITree() = default;

  void set_root(UIElement* root) {
    root_ = root;
    mark_dirty(false);
  }

  UIElement* root() const {
    return root_;
  }

  void set_invalidate_callback(InvalidateCallback callback) {
    invalidate_callback_ = std::move(callback);
  }

  void invalidate() {
    mark_dirty(true);
  }

  bool needs_redraw() const {
    return dirty_;
  }

  void on_resize(int width, int height) {
    if (!root_) {
      return;
    }

    root_->set_position(0, 0);
    root_->set_size(width, height);
    root_->measure(width, height);
    root_->layout();
    mark_dirty(true);
  }

  bool on_mouse_move(int x, int y) {
    if (!root_) {
      return false;
    }

    const bool handled = root_->on_mouse_move(x, y);
    if (handled) {
      mark_dirty(true);
    }
    return handled;
  }

  bool on_mouse_down(int x, int y, int button) {
    if (!root_) {
      return false;
    }

    const bool handled = root_->on_mouse_down(x, y, button);
    UIElement* focus_target = root_->find_topmost_focus_target_at(x, y);
    if (focus_target) {
      const bool focus_changed = set_focused_element(focus_target);
      if (focus_changed) {
        mark_dirty(true);
      }
    }
    const bool decouple = phase40_25_mouse_down_up_decouple_enabled() || phase40_24_strict_coupling_mode();
    if (handled && !decouple) {
      mark_dirty(true);
    }
    return handled || (focus_target != nullptr);
  }

  bool on_mouse_up(int x, int y, int button) {
    if (!root_) {
      return false;
    }

    const bool handled = root_->on_mouse_up(x, y, button);
    const bool decouple = phase40_25_mouse_down_up_decouple_enabled() || phase40_24_strict_coupling_mode();
    if (handled && !decouple) {
      mark_dirty(true);
    }
    return handled;
  }

  bool on_mouse_wheel(int x, int y, int delta) {
    if (!root_) {
      return false;
    }

    const bool handled = root_->on_mouse_wheel(x, y, delta);
    if (handled) {
      mark_dirty(true);
    }
    return handled;
  }

  bool on_key_down(std::uint32_t key, bool shift, bool repeat) {
    constexpr std::uint32_t vkReturn = 0x0D;
    constexpr std::uint32_t vkEscape = 0x1B;
    constexpr std::uint32_t vkTab = 0x09;

    if (!repeat && key == vkReturn && focused_element_ && focused_element_->is_text_input()) {
      if (default_action_element_ && default_action_element_->perform_primary_action()) {
        mark_dirty(true);
        return true;
      }
    }

    if (!repeat && key == vkEscape && cancel_action_element_) {
      if (cancel_action_element_->perform_primary_action()) {
        mark_dirty(true);
        return true;
      }
    }

    if (key == vkTab) {
      const bool moved = shift ? focus_previous() : focus_next();
      if (moved) {
        mark_dirty(true);
        return true;
      }
    }

    if (!focused_element_) {
      return false;
    }

    const bool handled = focused_element_->on_key_down(key, shift, repeat);
    if (handled) {
      mark_dirty(true);
    }
    return handled;
  }

  bool on_key_up(std::uint32_t key, bool shift) {
    if (!focused_element_) {
      return false;
    }

    const bool handled = focused_element_->on_key_up(key, shift);
    if (handled) {
      mark_dirty(true);
    }
    return handled;
  }

  bool on_char(std::uint32_t codepoint) {
    if (!focused_element_) {
      return false;
    }

    const bool handled = focused_element_->on_char(codepoint);
    if (handled) {
      mark_dirty(true);
    }
    return handled;
  }

  UIElement* focused_element() const {
    return focused_element_;
  }

  bool set_focused_element(UIElement* element) {
    if (focused_element_ == element) {
      return false;
    }

    if (focused_element_) {
      focused_element_->set_focused(false);
    }

    focused_element_ = (element && element->focusable()) ? element : nullptr;
    if (focused_element_) {
      focused_element_->set_focused(true);
    }

    return true;
  }

  bool focus_next() {
    if (!root_) {
      return false;
    }

    std::vector<UIElement*> focusables;
    collect_focusable_elements(root_, focusables);
    if (focusables.empty()) {
      return false;
    }

    std::size_t next_index = 0;
    if (focused_element_) {
      for (std::size_t index = 0; index < focusables.size(); ++index) {
        if (focusables[index] == focused_element_) {
          next_index = (index + 1) % focusables.size();
          break;
        }
      }
    }

    return set_focused_element(focusables[next_index]);
  }

  bool focus_previous() {
    if (!root_) {
      return false;
    }

    std::vector<UIElement*> focusables;
    collect_focusable_elements(root_, focusables);
    if (focusables.empty()) {
      return false;
    }

    std::size_t previous_index = focusables.size() - 1;
    if (focused_element_) {
      for (std::size_t index = 0; index < focusables.size(); ++index) {
        if (focusables[index] == focused_element_) {
          previous_index = (index + focusables.size() - 1) % focusables.size();
          break;
        }
      }
    }

    return set_focused_element(focusables[previous_index]);
  }

  void render(Renderer& renderer) {
    if (!root_ || !dirty_) {
      return;
    }

    root_->render(renderer);
    dirty_ = false;
  }

  void set_default_action_element(UIElement* element) {
    default_action_element_ = element;
  }

  UIElement* default_action_element() const {
    return default_action_element_;
  }

  void set_cancel_action_element(UIElement* element) {
    cancel_action_element_ = element;
  }

  UIElement* cancel_action_element() const {
    return cancel_action_element_;
  }

private:
  void mark_dirty(bool request_os_repaint) {
    dirty_ = true;
    if (request_os_repaint && invalidate_callback_) {
      invalidate_callback_();
    }
  }

  UIElement* root_ = nullptr;
  UIElement* focused_element_ = nullptr;
  UIElement* default_action_element_ = nullptr;
  UIElement* cancel_action_element_ = nullptr;
  InvalidateCallback invalidate_callback_;
  bool dirty_ = false;

  static void collect_focusable_elements(UIElement* element, std::vector<UIElement*>& out) {
    if (!element || !element->visible()) {
      return;
    }

    if (element->focusable()) {
      out.push_back(element);
    }

    for (UIElement* child : element->children()) {
      collect_focusable_elements(child, out);
    }
  }
};

} // namespace ngk::ui

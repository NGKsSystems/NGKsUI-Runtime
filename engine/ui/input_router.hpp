#pragma once

#include <cstdint>

#include "ui_tree.hpp"

namespace ngk::ui {

class InputRouter {
public:
  void set_tree(UITree* tree) {
    tree_ = tree;
  }

  int mouse_x() const {
    return mouse_x_;
  }

  int mouse_y() const {
    return mouse_y_;
  }

  bool on_mouse_move(int x, int y) {
    mouse_x_ = x;
    mouse_y_ = y;
    if (!tree_) {
      return false;
    }

    return tree_->on_mouse_move(x, y);
  }

  bool on_mouse_button_message(std::uint32_t message, bool down) {
    if (!tree_) {
      return false;
    }

    const int button = to_button_code(message);
    if (button < 0) {
      return false;
    }

    if (down) {
      return tree_->on_mouse_down(mouse_x_, mouse_y_, button);
    }

    return tree_->on_mouse_up(mouse_x_, mouse_y_, button);
  }

  bool on_key_message(std::uint32_t key, bool down, bool repeat) {
    update_modifier_state(key, down);

    if (!tree_) {
      return false;
    }

    if (down && !repeat && ctrl_down_) {
      constexpr std::uint32_t keyC = 0x43;
      constexpr std::uint32_t keyX = 0x58;
      constexpr std::uint32_t keyV = 0x56;
      constexpr std::uint32_t keyA = 0x41;
      constexpr std::uint32_t ctrlSelectAll = 1;
      constexpr std::uint32_t ctrlCopy = 3;
      constexpr std::uint32_t ctrlCut = 24;
      constexpr std::uint32_t ctrlPaste = 22;

      if (key == keyA) {
        return tree_->on_char(ctrlSelectAll);
      }
      if (key == keyC) {
        return tree_->on_char(ctrlCopy);
      }
      if (key == keyX) {
        return tree_->on_char(ctrlCut);
      }
      if (key == keyV) {
        return tree_->on_char(ctrlPaste);
      }
    }

    if (down) {
      return tree_->on_key_down(key, shift_down_, repeat);
    }

    return tree_->on_key_up(key, shift_down_);
  }

  bool on_char_input(std::uint32_t codepoint) {
    if (!tree_) {
      return false;
    }

    return tree_->on_char(codepoint);
  }

private:
  static int to_button_code(std::uint32_t message) {
    constexpr std::uint32_t wmLButtonDown = 0x0201;
    constexpr std::uint32_t wmLButtonUp = 0x0202;
    constexpr std::uint32_t wmRButtonDown = 0x0204;
    constexpr std::uint32_t wmRButtonUp = 0x0205;
    constexpr std::uint32_t wmMButtonDown = 0x0207;
    constexpr std::uint32_t wmMButtonUp = 0x0208;

    switch (message) {
      case wmLButtonDown:
      case wmLButtonUp:
        return 0;
      case wmMButtonDown:
      case wmMButtonUp:
        return 1;
      case wmRButtonDown:
      case wmRButtonUp:
        return 2;
      default:
        return -1;
    }
  }

  void update_modifier_state(std::uint32_t key, bool down) {
    constexpr std::uint32_t vkShift = 0x10;
    constexpr std::uint32_t vkLShift = 0xA0;
    constexpr std::uint32_t vkRShift = 0xA1;
    constexpr std::uint32_t vkControl = 0x11;
    constexpr std::uint32_t vkLControl = 0xA2;
    constexpr std::uint32_t vkRControl = 0xA3;

    if (key == vkShift || key == vkLShift || key == vkRShift) {
      shift_down_ = down;
      return;
    }

    if (key == vkControl || key == vkLControl || key == vkRControl) {
      ctrl_down_ = down;
    }
  }

  UITree* tree_ = nullptr;
  int mouse_x_ = 0;
  int mouse_y_ = 0;
  bool shift_down_ = false;
  bool ctrl_down_ = false;
};

} // namespace ngk::ui

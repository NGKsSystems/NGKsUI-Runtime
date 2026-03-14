#pragma once

#include <cstdint>
#include <functional>
#include <chrono>
#include <string>
#include <utility>

#include "panel.hpp"
#include "text_painter.hpp"

namespace ngk::ui {

class InputBox : public Panel {
public:
  struct ClipboardHooks {
    std::function<bool(const std::string&)> set_text;
    std::function<bool(std::string&)> get_text;
  };

  InputBox() {
    set_size(0, 32);
    set_preferred_size(220, 36);
    set_focusable(true);
    update_visual_state();
  }

  const std::string& value() const {
    return value_;
  }

  int caret_index() const {
    return caret_index_;
  }

  int selection_anchor_index() const {
    return selection_anchor_index_;
  }

  bool has_selection() const {
    return caret_index_ != selection_anchor_index_;
  }

  int selection_start() const {
    return caret_index_ < selection_anchor_index_ ? caret_index_ : selection_anchor_index_;
  }

  int selection_end() const {
    return caret_index_ > selection_anchor_index_ ? caret_index_ : selection_anchor_index_;
  }

  void set_clipboard_hooks(ClipboardHooks hooks) {
    clipboard_hooks_ = std::move(hooks);
  }

  void set_value(std::string value) {
    value_ = std::move(value);
    caret_index_ = static_cast<int>(value_.size());
    selection_anchor_index_ = caret_index_;
  }

  bool on_mouse_down(int x, int y, int button) override {
    if (button != 0) {
      return Panel::on_mouse_down(x, y, button);
    }

    if (!contains_point(x, y)) {
      dragging_selection_ = false;
      return false;
    }

    hovered_ = true;
    const int click_index = index_from_mouse_x(x);
    const auto now = std::chrono::steady_clock::now();
    const bool double_click = (last_click_inside_) && ((now - last_click_time_) <= std::chrono::milliseconds(350));
    last_click_time_ = now;
    last_click_inside_ = true;

    if (double_click) {
      select_word_at(click_index);
      dragging_selection_ = false;
      return true;
    }

    if (has_selection()) {
      const int start = selection_start();
      const int end = selection_end();
      if (click_index >= start && click_index <= end) {
        caret_index_ = click_index;
        collapse_selection_to_caret();
      } else {
        set_caret_position(click_index, false);
      }
    } else {
      set_caret_position(click_index, false);
    }

    dragging_selection_ = true;
    drag_anchor_index_ = caret_index_;
    selection_anchor_index_ = drag_anchor_index_;
    return true;
  }

  bool on_mouse_up(int x, int y, int button) override {
    if (button != 0) {
      return Panel::on_mouse_up(x, y, button);
    }

    if (dragging_selection_) {
      const int up_index = index_from_mouse_x(x);
      caret_index_ = up_index;
      selection_anchor_index_ = drag_anchor_index_;
    }
    dragging_selection_ = false;
    return contains_point(x, y);
  }

  bool on_mouse_move(int x, int y) override {
    const bool old_hovered = hovered_;
    const int old_caret_index = caret_index_;
    const int old_selection_anchor = selection_anchor_index_;

    hovered_ = contains_point(x, y);

    if (dragging_selection_) {
      caret_index_ = index_from_mouse_x(x);
      selection_anchor_index_ = drag_anchor_index_;
    }

    const bool changed = (old_hovered != hovered_) || (old_caret_index != caret_index_) || (old_selection_anchor != selection_anchor_index_);
    if (changed) {
      update_visual_state();
    }
    return changed;
  }

  bool on_char(std::uint32_t ch) override {
    if (!focused()) {
      return false;
    }

    clamp_caret();

    constexpr std::uint32_t backspace = 8;
    constexpr std::uint32_t ctrlCopy = 3;
    constexpr std::uint32_t ctrlCut = 24;
    constexpr std::uint32_t ctrlPaste = 22;
    constexpr std::uint32_t ctrlSelectAll = 1;

    if (ch == ctrlSelectAll) {
      selection_anchor_index_ = 0;
      caret_index_ = static_cast<int>(value_.size());
      return true;
    }

    if (ch == ctrlCopy) {
      return copy_selection_to_clipboard();
    }

    if (ch == ctrlCut) {
      if (!copy_selection_to_clipboard()) {
        return false;
      }
      return delete_selection();
    }

    if (ch == ctrlPaste) {
      if (!clipboard_hooks_.get_text) {
        return false;
      }

      std::string clip;
      if (!clipboard_hooks_.get_text(clip)) {
        return false;
      }

      if (has_selection()) {
        delete_selection();
      }

      if (!clip.empty()) {
        value_.insert(static_cast<std::size_t>(caret_index_), clip);
        caret_index_ += static_cast<int>(clip.size());
      }
      collapse_selection_to_caret();
      return true;
    }

    if (ch == backspace) {
      if (has_selection()) {
        return delete_selection();
      }
      erase_before_caret();
      return true;
    }

    if (ch >= 32 && ch <= 126) {
      if (has_selection()) {
        delete_selection();
      }
      value_.insert(static_cast<std::size_t>(caret_index_), 1, static_cast<char>(ch));
      caret_index_++;
      collapse_selection_to_caret();
      return true;
    }

    return false;
  }

  bool on_key_down(std::uint32_t key, bool shift, bool repeat) override {
    if (!focused() || repeat) {
      return false;
    }

    clamp_caret();

    constexpr std::uint32_t kVkBack = 0x08;
    constexpr std::uint32_t kVkLeft = 0x25;
    constexpr std::uint32_t kVkRight = 0x27;
    constexpr std::uint32_t kVkHome = 0x24;
    constexpr std::uint32_t kVkEnd = 0x23;
    constexpr std::uint32_t kVkDelete = 0x2E;

    switch (key) {
      case kVkBack:
        erase_before_caret();
        return true;
      case kVkLeft:
        move_caret_left(shift);
        return true;
      case kVkRight:
        move_caret_right(shift);
        return true;
      case kVkHome:
        set_caret_position(0, shift);
        return true;
      case kVkEnd:
        set_caret_position(static_cast<int>(value_.size()), shift);
        return true;
      case kVkDelete:
        if (has_selection()) {
          return delete_selection();
        }
        if (caret_index_ >= 0 && caret_index_ < static_cast<int>(value_.size())) {
          value_.erase(static_cast<std::size_t>(caret_index_), 1);
        }
        collapse_selection_to_caret();
        return true;
      default:
        return false;
    }
  }

  void on_focus_changed(bool /*focused*/) override {
    if (!focused()) {
      dragging_selection_ = false;
    }
    update_visual_state();
  }

  bool is_text_input() const override {
    return true;
  }

  void render(Renderer& renderer) override {
    update_visual_state();
    Panel::render(renderer);

    if (width() > 0 && height() > 0) {
      renderer.queue_rect_outline(x(), y(), width(), height(), 0.82f, 0.82f, 0.88f, 1.0f);
      if (focused()) {
        renderer.queue_rect_outline(x() + 1, y() + 1, width() - 2, height() - 2, 0.98f, 0.82f, 0.18f, 1.0f);
        renderer.queue_rect_outline(x() + 2, y() + 2, width() - 4, height() - 4, 0.98f, 0.82f, 0.18f, 1.0f);
      }
    }

    std::string draw_text = value_;
    if (draw_text.empty() && !focused()) {
      draw_text = "Type here";
    }

    if (value_.empty() && !focused()) {
      text_painter::draw(*this, renderer, draw_text, 0.72f, 0.78f, 0.84f, 1.0f);
    } else {
      const int text_x = text_painter::text_origin_x(*this);
      const int text_y = text_painter::baseline_y(*this);
      const int line_h = text_painter::text_line_height();

      if (has_selection()) {
        const int sel_start = selection_start();
        const int sel_end = selection_end();
        const int left_x = text_x + text_painter::measure_prefix_width(value_, sel_start);
        const int right_x = text_x + text_painter::measure_prefix_width(value_, sel_end);
        const int span_w = right_x - left_x;
        if (span_w > 0) {
          const int highlight_y = text_y - 1;
          const int highlight_h = line_h + 2;
          renderer.queue_rect(left_x, highlight_y, span_w, highlight_h, 0.26f, 0.46f, 0.84f, 0.75f);
        }
      }
      text_painter::draw(*this, renderer, draw_text, 0.98f, 0.98f, 0.98f, 1.0f);
    }

    if (focused()) {
      const int caret_clamped = caret_index_ < 0 ? 0 : (caret_index_ > static_cast<int>(value_.size()) ? static_cast<int>(value_.size()) : caret_index_);
      const int text_x = text_painter::text_origin_x(*this);
      const int text_y = text_painter::baseline_y(*this);
      const int caret_x = text_x + text_painter::measure_prefix_width(value_, caret_clamped);
      const int caret_y = text_y - 1;
      const int caret_h = text_painter::text_line_height() + 2;
      renderer.queue_rect(caret_x, caret_y, 3, caret_h, 1.0f, 0.96f, 0.28f, 1.0f);
    }
  }

private:
  void clamp_caret() {
    if (caret_index_ < 0) {
      caret_index_ = 0;
      return;
    }

    const int max_index = static_cast<int>(value_.size());
    if (caret_index_ > max_index) {
      caret_index_ = max_index;
    }
  }

  void collapse_selection_to_caret() {
    selection_anchor_index_ = caret_index_;
  }

  void set_caret_position(int index, bool keep_anchor) {
    const int max_index = static_cast<int>(value_.size());
    if (index < 0) {
      index = 0;
    }
    if (index > max_index) {
      index = max_index;
    }

    caret_index_ = index;

    if (!keep_anchor) {
      selection_anchor_index_ = caret_index_;
    }
  }

  void move_caret_left(bool keep_anchor) {
    if (!keep_anchor && has_selection()) {
      caret_index_ = selection_start();
      collapse_selection_to_caret();
      return;
    }

    if (caret_index_ > 0) {
      caret_index_--;
    }
    if (!keep_anchor) {
      collapse_selection_to_caret();
    }
  }

  void move_caret_right(bool keep_anchor) {
    if (!keep_anchor && has_selection()) {
      caret_index_ = selection_end();
      collapse_selection_to_caret();
      return;
    }

    if (caret_index_ < static_cast<int>(value_.size())) {
      caret_index_++;
    }
    if (!keep_anchor) {
      collapse_selection_to_caret();
    }
  }

  bool delete_selection() {
    if (!has_selection()) {
      return false;
    }

    const int start = selection_start();
    const int end = selection_end();
    value_.erase(static_cast<std::size_t>(start), static_cast<std::size_t>(end - start));
    caret_index_ = start;
    collapse_selection_to_caret();
    return true;
  }

  bool is_word_char(char c) const {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
  }

  void select_word_at(int index) {
    clamp_caret();
    if (value_.empty()) {
      collapse_selection_to_caret();
      return;
    }

    if (index < 0) {
      index = 0;
    }
    if (index >= static_cast<int>(value_.size())) {
      index = static_cast<int>(value_.size()) - 1;
    }

    int start = index;
    int end = index;
    const bool word = is_word_char(value_[static_cast<std::size_t>(index)]);

    while (start > 0 && (is_word_char(value_[static_cast<std::size_t>(start - 1)]) == word)) {
      start--;
    }
    while (end < static_cast<int>(value_.size()) && (is_word_char(value_[static_cast<std::size_t>(end)]) == word)) {
      end++;
    }

    selection_anchor_index_ = start;
    caret_index_ = end;
  }

  int index_from_mouse_x(int mouse_x) const {
    const int text_start = text_painter::text_origin_x(*this);
    const int local_x = mouse_x - text_start;
    return text_painter::caret_index_from_x(value_, local_x);
  }

  bool copy_selection_to_clipboard() {
    if (!has_selection() || !clipboard_hooks_.set_text) {
      return false;
    }

    const int start = selection_start();
    const int end = selection_end();
    const std::string selected = value_.substr(static_cast<std::size_t>(start), static_cast<std::size_t>(end - start));
    return clipboard_hooks_.set_text(selected);
  }

  void set_caret_from_mouse_x(int mouse_x) {
    caret_index_ = index_from_mouse_x(mouse_x);
  }

  void erase_before_caret() {
    if (caret_index_ > 0 && !value_.empty()) {
      value_.erase(static_cast<std::size_t>(caret_index_ - 1), 1);
      caret_index_--;
      collapse_selection_to_caret();
    }
  }

  void update_visual_state() {
    if (focused()) {
      set_background(0.10f, 0.20f, 0.34f, 1.0f);
      return;
    }

    if (hovered_) {
      set_background(0.16f, 0.18f, 0.24f, 1.0f);
      return;
    }

    set_background(0.10f, 0.12f, 0.16f, 1.0f);
  }

  bool hovered_ = false;
  bool dragging_selection_ = false;
  std::string value_;
  int caret_index_ = 0;
  int selection_anchor_index_ = 0;
  int drag_anchor_index_ = 0;
  bool last_click_inside_ = false;
  std::chrono::steady_clock::time_point last_click_time_{};
  ClipboardHooks clipboard_hooks_;
};

} // namespace ngk::ui

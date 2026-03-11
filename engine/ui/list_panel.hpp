#pragma once

#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "panel.hpp"

namespace ngk::ui {

class ListPanel : public Panel {
public:
  ListPanel() {
    set_size(0, 240);
  }

  void set_rows(std::vector<std::string> rows) {
    rows_ = std::move(rows);
    if (selected_index_ >= static_cast<int>(rows_.size())) {
      selected_index_ = -1;
    }
    if (hover_index_ >= static_cast<int>(rows_.size())) {
      hover_index_ = -1;
    }
  }

  const std::vector<std::string>& rows() const {
    return rows_;
  }

  int row_count() const {
    return static_cast<int>(rows_.size());
  }

  int row_height() const {
    return row_height_;
  }

  void set_row_height(int row_height) {
    row_height_ = row_height > 0 ? row_height : 24;
  }

  int hover_index() const {
    return hover_index_;
  }

  int selected_index() const {
    return selected_index_;
  }

  const std::string& selected_text() const {
    static const std::string empty;
    if (selected_index_ < 0 || selected_index_ >= static_cast<int>(rows_.size())) {
      return empty;
    }
    return rows_[selected_index_];
  }

  void set_on_selection_changed(std::function<void(int, const std::string&)> callback) {
    on_selection_changed_ = std::move(callback);
  }

  bool on_mouse_move(int x, int y) override {
    hover_index_ = hit_row_index(x, y);
    update_visual_state();
    return contains_point(x, y);
  }

  bool on_mouse_down(int x, int y, int button) override {
    if (button != 0 || !contains_point(x, y)) {
      return Panel::on_mouse_down(x, y, button);
    }

    const int row_index = hit_row_index(x, y);
    if (row_index >= 0 && row_index < static_cast<int>(rows_.size()) && row_index != selected_index_) {
      selected_index_ = row_index;
      if (on_selection_changed_) {
        on_selection_changed_(selected_index_, rows_[selected_index_]);
      }
    }

    update_visual_state();
    return true;
  }

  bool on_mouse_up(int x, int y, int button) override {
    if (button != 0) {
      return Panel::on_mouse_up(x, y, button);
    }
    return contains_point(x, y);
  }

  void render(Renderer& renderer) override {
    update_visual_state();
    Panel::render(renderer);
  }

private:
  int hit_row_index(int x, int y) const {
    if (!contains_point(x, y)) {
      return -1;
    }

    if (row_height_ <= 0) {
      return -1;
    }

    const int local_y = y - this->y();
    const int index = local_y / row_height_;
    if (index < 0 || index >= static_cast<int>(rows_.size())) {
      return -1;
    }
    return index;
  }

  void update_visual_state() {
    if (selected_index_ >= 0) {
      set_background(0.16f, 0.26f, 0.20f, 1.0f);
      return;
    }

    if (hover_index_ >= 0) {
      set_background(0.20f, 0.20f, 0.26f, 1.0f);
      return;
    }

    set_background(0.12f, 0.12f, 0.16f, 1.0f);
  }

  std::vector<std::string> rows_;
  int row_height_ = 24;
  int hover_index_ = -1;
  int selected_index_ = -1;
  std::function<void(int, const std::string&)> on_selection_changed_;
};

} // namespace ngk::ui

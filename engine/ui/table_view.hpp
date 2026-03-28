#pragma once

#include <algorithm>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "label.hpp"
#include "panel.hpp"

namespace ngk::ui {

class TableView : public Panel {
public:
  using SelectionChangedCallback = std::function<void(int)>;

  TableView() = default;

  void set_data(std::vector<std::string> headers, const std::vector<std::vector<std::string>>& rows) {
    children_.clear();
    row_views_.clear();
    header_cells_.clear();

    headers_ = std::move(headers);
    rows_data_ = rows;
    selected_index_ = -1;

    if (!headers_.empty()) {
      header_panel_ = std::make_unique<Panel>();
      header_panel_->set_background(0.18f, 0.20f, 0.24f, 1.0f);
      header_panel_->set_preferred_size(0, kHeaderHeight);
      header_panel_->set_min_size(0, kHeaderHeight);

      for (const auto& header : headers_) {
        auto cell = std::make_unique<Label>(header);
        cell->set_background(0.18f, 0.20f, 0.24f, 1.0f);
        cell->set_min_size(0, kHeaderHeight - 8);
        header_panel_->add_child(cell.get());
        header_cells_.push_back(std::move(cell));
      }
      add_child(header_panel_.get());
    } else {
      header_panel_.reset();
    }

    for (const auto& row_data : rows_data_) {
      auto row = std::make_unique<RowView>();
      row->panel = std::make_unique<Panel>();
      row->panel->set_background(0.12f, 0.14f, 0.18f, 1.0f);
      row->panel->set_preferred_size(0, kRowHeight);
      row->panel->set_min_size(0, 24);

      for (size_t i = 0; i < headers_.size(); ++i) {
        std::string text;
        if (i < row_data.size()) {
          text = row_data[i];
        }
        auto cell = std::make_unique<Label>(std::move(text));
        cell->set_background(0.12f, 0.14f, 0.18f, 1.0f);
        cell->set_min_size(0, kRowHeight - 8);
        row->panel->add_child(cell.get());
        row->cells.push_back(std::move(cell));
      }

      add_child(row->panel.get());
      row_views_.push_back(std::move(row));
    }

    const int content_h = kHeaderHeight +
                          static_cast<int>(row_views_.size()) * kRowHeight +
                          std::max(0, static_cast<int>(row_views_.size()) - 1) * kRowSpacing;
    set_preferred_size(0, std::max(content_h, kMinPreferredHeight));

    if (!row_views_.empty()) {
      set_selected_index(0);
    }
  }

  int selected_index() const { return selected_index_; }
  int row_count() const { return static_cast<int>(row_views_.size()); }
  int column_count() const { return static_cast<int>(headers_.size()); }
  bool has_headers() const { return !headers_.empty(); }

  void set_selected_index(int index) {
    if (index < -1 || index >= static_cast<int>(row_views_.size())) {
      return;
    }
    if (selected_index_ == index) {
      return;
    }

    selected_index_ = index;
    update_selection_highlight();
    if (selection_changed_callback_) {
      selection_changed_callback_(selected_index_);
    }
  }

  void set_selection_changed_callback(SelectionChangedCallback callback) {
    selection_changed_callback_ = std::move(callback);
  }

  void layout() override {
    const int columns = std::max(1, static_cast<int>(headers_.size()));
    const int column_w = columns > 0 ? std::max(1, width_ / columns) : width_;

    int cy = y_;
    if (header_panel_) {
      header_panel_->set_position(x_, cy);
      header_panel_->set_size(width_, kHeaderHeight);
      for (size_t i = 0; i < header_cells_.size(); ++i) {
        const int cell_x = x_ + static_cast<int>(i) * column_w;
        const int cell_w = (i + 1 == header_cells_.size()) ? (x_ + width_ - cell_x) : column_w;
        header_cells_[i]->set_position(cell_x + 4, cy + 4);
        header_cells_[i]->set_size(std::max(0, cell_w - 8), std::max(0, kHeaderHeight - 8));
      }
      header_panel_->layout();
      cy += kHeaderHeight + kRowSpacing;
    }

    for (auto& row : row_views_) {
      row->panel->set_position(x_, cy);
      row->panel->set_size(width_, kRowHeight);
      for (size_t i = 0; i < row->cells.size(); ++i) {
        const int cell_x = x_ + static_cast<int>(i) * column_w;
        const int cell_w = (i + 1 == row->cells.size()) ? (x_ + width_ - cell_x) : column_w;
        row->cells[i]->set_position(cell_x + 4, cy + 6);
        row->cells[i]->set_size(std::max(0, cell_w - 8), std::max(0, kRowHeight - 12));
      }
      row->panel->layout();
      cy += kRowHeight + kRowSpacing;
    }
  }

  bool on_mouse_down(int x, int y, int button) override {
    if (button != 0) {
      return false;
    }
    for (size_t i = 0; i < row_views_.size(); ++i) {
      const Panel* row = row_views_[i]->panel.get();
      if (x >= row->x() && x < row->x() + row->width() &&
          y >= row->y() && y < row->y() + row->height()) {
        set_selected_index(static_cast<int>(i));
        return true;
      }
    }
    return false;
  }

private:
  static constexpr int kHeaderHeight = 34;
  static constexpr int kRowHeight = 32;
  static constexpr int kRowSpacing = 4;
  static constexpr int kMinPreferredHeight = 800;

  struct RowView {
    std::unique_ptr<Panel> panel;
    std::vector<std::unique_ptr<Label>> cells;
  };

  std::vector<std::string> headers_;
  std::vector<std::vector<std::string>> rows_data_;
  std::unique_ptr<Panel> header_panel_;
  std::vector<std::unique_ptr<Label>> header_cells_;
  std::vector<std::unique_ptr<RowView>> row_views_;
  int selected_index_ = -1;
  SelectionChangedCallback selection_changed_callback_;

  void update_selection_highlight() {
    for (size_t i = 0; i < row_views_.size(); ++i) {
      const bool selected = (i == static_cast<size_t>(selected_index_));
      const float r = selected ? 0.24f : 0.12f;
      const float g = selected ? 0.32f : 0.14f;
      const float b = selected ? 0.44f : 0.18f;
      row_views_[i]->panel->set_background(r, g, b, 1.0f);
      for (auto& cell : row_views_[i]->cells) {
        cell->set_background(r, g, b, 1.0f);
      }
    }
  }
};

} // namespace ngk::ui

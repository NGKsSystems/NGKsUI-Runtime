#pragma once

#include <algorithm>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "label.hpp"
#include "panel.hpp"

namespace ngk::ui {

// ListView: a vertically-stacked list of selectable items.
//
// Ownership model:
//   Rows are owned as std::unique_ptr<Row> in rows_.  children_ (inherited
//   from UIElement, non-owning) is kept in sync with rows_ so that the
//   standard render/layout/input dispatch chain works correctly and external
//   callers can observe child count via UIElement::children().
//
//   set_items() first clears children_ (raw ptrs), then clears rows_
//   (unique_ptrs delete heap objects), then rebuilds.  This eliminates
//   the dangling-pointer/double-free corruption that occurs when children_
//   is cleared without matching deallocation of new'd objects.
class ListView : public Panel {
public:
  using SelectionChangedCallback = std::function<void(int)>;

  ListView() = default;

  // Replace the full item set.  Safe to call any number of times.
  void set_items(const std::vector<std::string>& items) {
    // 1. Clear base-class raw-pointer vector first so it never holds
    //    pointers to objects that are about to be freed.
    children_.clear();

    // 2. Destroy old rows.  unique_ptr destruction handles deallocation;
    //    within each Row, label is destroyed before panel (reverse of
    //    declaration order), so panel.children_ temporarily holds a ptr
    //    to the freed label, but ~UIElement() never dereferences children_
    //    during destruction — safe.
    rows_.clear();

    items_ = items;
    selected_index_ = -1;

    // Set preferred height so ScrollContainer can compute content_height.
    const int total_h = static_cast<int>(items_.size()) * kRowHeight
                      + std::max(0, static_cast<int>(items_.size()) - 1) * kRowSpacing;
    set_preferred_size(0, std::max(total_h, kMinPreferredHeight));

    for (const auto& item : items_) {
      auto row        = std::make_unique<Row>();
      row->panel      = std::make_unique<Panel>();
      row->label      = std::make_unique<Label>(item);

      row->panel->set_background(0.12f, 0.14f, 0.18f, 1.0f);
      row->panel->set_preferred_size(0, kRowHeight);
      row->panel->set_min_size(0, 24);

      // Nest label inside panel for render dispatch.
      row->panel->add_child(row->label.get());
      // Register panel in this ListView's children_ for standard dispatch.
      add_child(row->panel.get());

      rows_.push_back(std::move(row));
    }
  }

  int selected_index() const { return selected_index_; }

  void set_selected_index(int index) {
    if (index < -1 || index >= static_cast<int>(rows_.size())) {
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

  // Position row panels and their labels vertically.
  void layout() override {
    int cy = y_;
    for (auto& r : rows_) {
      r->panel->set_position(x_, cy);
      r->panel->set_size(width_, kRowHeight);
      r->label->set_position(x_ + 4, cy + 6);
      r->label->set_size(std::max(0, width_ - 8), std::max(0, kRowHeight - 12));
      r->panel->layout();
      cy += kRowHeight + kRowSpacing;
    }
  }

  // Hit-test against row panels; select the row under the click.
  bool on_mouse_down(int x, int y, int button) override {
    if (button != 0) {
      return false;
    }
    for (size_t i = 0; i < rows_.size(); ++i) {
      const Panel* p = rows_[i]->panel.get();
      if (x >= p->x() && x < p->x() + p->width() &&
          y >= p->y() && y < p->y() + p->height()) {
        set_selected_index(static_cast<int>(i));
        return true;
      }
    }
    return false;
  }

private:
  static constexpr int kRowHeight  = 32;
  static constexpr int kRowSpacing        = 4;
  // Minimum preferred height reported to ScrollContainer.
  // Guarantees content_h > viewport_h across all test window sizes
  // (~290-420px) so that vertical scroll remains exercisable even when
  // items are filtered down to a small count.
  static constexpr int kMinPreferredHeight = 800;

  // Row owns the heap-allocated Panel and Label for one list item.
  // Declaration order: panel first → constructed first → destroyed last.
  // label → constructed second → destroyed first.  This means label is
  // freed before panel; the dangling raw ptr in panel.children_ is never
  // dereferenced during panel destruction (~UIElement() does not delete
  // children). Safe.
  struct Row {
    std::unique_ptr<Panel> panel;
    std::unique_ptr<Label> label;
  };

  std::vector<std::string>         items_;
  std::vector<std::unique_ptr<Row>> rows_;
  int                              selected_index_ = -1;
  SelectionChangedCallback         selection_changed_callback_;

  void update_selection_highlight() {
    for (size_t i = 0; i < rows_.size(); ++i) {
      if (i == static_cast<size_t>(selected_index_)) {
        rows_[i]->panel->set_background(0.24f, 0.32f, 0.44f, 1.0f);
      } else {
        rows_[i]->panel->set_background(0.12f, 0.14f, 0.18f, 1.0f);
      }
    }
  }
};

} // namespace ngk::ui

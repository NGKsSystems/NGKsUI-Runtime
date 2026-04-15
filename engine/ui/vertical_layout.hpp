#pragma once

#include <algorithm>

#include "panel.hpp"

namespace ngk::ui {

class VerticalLayout : public Panel {
public:
  explicit VerticalLayout(int spacing = 0) : spacing_(spacing) {}

  void set_spacing(int spacing) { spacing_ = spacing; }
  int spacing() const { return spacing_; }

  void set_padding(int all) {
    padding_left_ = all;
    padding_top_ = all;
    padding_right_ = all;
    padding_bottom_ = all;
  }

  void set_padding(int left, int top, int right, int bottom) {
    padding_left_ = left;
    padding_top_ = top;
    padding_right_ = right;
    padding_bottom_ = bottom;
  }

  int padding_left() const { return padding_left_; }
  int padding_top() const { return padding_top_; }
  int padding_right() const { return padding_right_; }
  int padding_bottom() const { return padding_bottom_; }

  void layout() override {
    const int inner_x = x_ + padding_left_;
    const int inner_w = std::max(0, width_ - padding_left_ - padding_right_);
    const int inner_h = std::max(0, height_ - padding_top_ - padding_bottom_);

    std::vector<UIElement*> visible_children{};
    visible_children.reserve(children_.size());
    for (UIElement* child : children_) {
      if (!child) {
        continue;
      }
      if (child->visible()) {
        visible_children.push_back(child);
      }
    }

    const int spacing_total = visible_children.empty()
      ? 0
      : spacing_ * static_cast<int>(visible_children.size() - 1);
    const int available_h = std::max(0, inner_h - spacing_total);

    int fixed_total_h = 0;
    int fill_min_total_h = 0;
    int total_fill_weight = 0;
    for (UIElement* child : visible_children) {
      const bool fill_height = child->layout_height_policy() == UIElement::LayoutSizePolicy::Fill;
      const int preferred_h = child->preferred_height() > 0 ? child->preferred_height() : 0;
      const int min_h = child->min_height();
      if (fill_height) {
        fill_min_total_h += min_h;
        total_fill_weight += child->layout_weight();
      } else {
        fixed_total_h += std::max(min_h, preferred_h);
      }
    }

    int remaining_fill_h = std::max(0, available_h - fixed_total_h - fill_min_total_h);
    int cursor_y = y_ + padding_top_;
    int remaining_weight = std::max(1, total_fill_weight);
    for (std::size_t index = 0; index < visible_children.size(); ++index) {
      UIElement* child = visible_children[index];
      const bool fill_height = child->layout_height_policy() == UIElement::LayoutSizePolicy::Fill;
      const int min_h = child->min_height();

      int child_h = 0;
      if (fill_height) {
        const int child_weight = std::max(1, child->layout_weight());
        const int extra_h = (index + 1 == visible_children.size() || remaining_weight <= 0)
          ? remaining_fill_h
          : (remaining_fill_h * child_weight) / remaining_weight;
        child_h = min_h + extra_h;
        remaining_fill_h -= extra_h;
        remaining_weight -= child_weight;
      } else {
        const int preferred_h = child->preferred_height() > 0 ? child->preferred_height() : child->height();
        child_h = std::max(min_h, preferred_h);
      }

      const int preferred_w = child->preferred_width() > 0 ? child->preferred_width() : inner_w;
      const int child_w = child->layout_width_policy() == UIElement::LayoutSizePolicy::Fill
        ? inner_w
        : std::max(child->min_width(), std::min(inner_w, preferred_w));

      child->set_position(inner_x, cursor_y);
      child->set_size(std::max(0, child_w), std::max(0, child_h));
      child->layout();
      cursor_y += child_h + spacing_;
    }
  }

private:
  int spacing_ = 0;
  int padding_left_ = 0;
  int padding_top_ = 0;
  int padding_right_ = 0;
  int padding_bottom_ = 0;
};

} // namespace ngk::ui

#pragma once

#include <algorithm>

#include "panel.hpp"

namespace ngk::ui {

class HorizontalLayout : public Panel {
public:
  explicit HorizontalLayout(int spacing = 0) : spacing_(spacing) {}

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
    const int inner_y = y_ + padding_top_;
    const int inner_w = std::max(0, width_ - padding_left_ - padding_right_);
    const int inner_h = std::max(0, height_ - padding_top_ - padding_bottom_);

    std::vector<UIElement*> visible_children{};
    visible_children.reserve(children_.size());
    for (UIElement* child : children_) {
      if (child && child->visible()) {
        visible_children.push_back(child);
      }
    }

    const int spacing_total = visible_children.empty()
      ? 0
      : spacing_ * static_cast<int>(visible_children.size() - 1);
    const int available_w = std::max(0, inner_w - spacing_total);

    int fixed_total_w = 0;
    int fill_min_total_w = 0;
    int total_fill_weight = 0;
    for (UIElement* child : visible_children) {
      const bool fill_width = child->layout_width_policy() == UIElement::LayoutSizePolicy::Fill;
      const int preferred_w = child->preferred_width() > 0 ? child->preferred_width() : 0;
      const int min_w = child->min_width();
      if (fill_width) {
        fill_min_total_w += min_w;
        total_fill_weight += child->layout_weight();
      } else {
        fixed_total_w += std::max(min_w, preferred_w);
      }
    }

    int remaining_fill_w = std::max(0, available_w - fixed_total_w - fill_min_total_w);
    int cursor_x = inner_x;
    int remaining_weight = std::max(1, total_fill_weight);
    for (std::size_t index = 0; index < visible_children.size(); ++index) {
      UIElement* child = visible_children[index];
      const bool fill_width = child->layout_width_policy() == UIElement::LayoutSizePolicy::Fill;
      const int min_w = child->min_width();

      int child_w = 0;
      if (fill_width) {
        const int child_weight = std::max(1, child->layout_weight());
        const int extra_w = (index + 1 == visible_children.size() || remaining_weight <= 0)
          ? remaining_fill_w
          : (remaining_fill_w * child_weight) / remaining_weight;
        child_w = min_w + extra_w;
        remaining_fill_w -= extra_w;
        remaining_weight -= child_weight;
      } else {
        const int preferred_w = child->preferred_width() > 0 ? child->preferred_width() : child->width();
        child_w = std::max(min_w, preferred_w);
      }

      const int preferred_h = child->preferred_height() > 0 ? child->preferred_height() : inner_h;
      const int child_h = child->layout_height_policy() == UIElement::LayoutSizePolicy::Fill
        ? inner_h
        : std::max(child->min_height(), std::min(inner_h, preferred_h));

      child->set_position(cursor_x, inner_y);
      child->set_size(std::max(0, child_w), std::max(0, child_h));
      child->layout();
      cursor_x += child_w + spacing_;
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

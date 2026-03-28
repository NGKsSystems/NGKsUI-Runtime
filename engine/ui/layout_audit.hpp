#pragma once

#include <algorithm>

#include "ui_element.hpp"

namespace ngk::ui::builder {

struct LayoutAuditResult {
  bool no_overlap = true;
  bool minimums_ok = true;
  int overlap_count = 0;
  int minimum_violations = 0;
  int checked_nodes = 0;
};

inline bool rects_overlap(const UIElement* a, const UIElement* b) {
  if (!a || !b) {
    return false;
  }

  const int ax0 = a->x();
  const int ay0 = a->y();
  const int ax1 = a->x() + a->width();
  const int ay1 = a->y() + a->height();

  const int bx0 = b->x();
  const int by0 = b->y();
  const int bx1 = b->x() + b->width();
  const int by1 = b->y() + b->height();

  return (ax0 < bx1) && (ax1 > bx0) && (ay0 < by1) && (ay1 > by0);
}

inline void audit_subtree(const UIElement* node, LayoutAuditResult& result) {
  if (!node || !node->visible()) {
    return;
  }

  result.checked_nodes += 1;

  if (node->width() < node->min_width() || node->height() < node->min_height()) {
    result.minimums_ok = false;
    result.minimum_violations += 1;
  }

  const auto& children = node->children();
  for (size_t i = 0; i < children.size(); ++i) {
    const UIElement* left = children[i];
    if (!left || !left->visible()) {
      continue;
    }

    for (size_t j = i + 1; j < children.size(); ++j) {
      const UIElement* right = children[j];
      if (!right || !right->visible()) {
        continue;
      }

      if (rects_overlap(left, right)) {
        result.no_overlap = false;
        result.overlap_count += 1;
      }
    }
  }

  for (const UIElement* child : children) {
    audit_subtree(child, result);
  }
}

inline LayoutAuditResult audit_layout_tree(const UIElement* root) {
  LayoutAuditResult result{};
  audit_subtree(root, result);
  return result;
}

} // namespace ngk::ui::builder

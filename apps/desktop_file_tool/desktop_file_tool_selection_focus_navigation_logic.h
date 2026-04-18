#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"

namespace desktop_file_tool {

struct SelectionFocusNavigationLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  bool& focus_selection_rules_defined;
  bool& stale_focus_rejected;
  bool& selection_coherence_hardened;
  bool& stale_selection_rejected;
  bool& undefined_state_detected;
  std::function<void()> refresh_tree_surface_label;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool(const std::string&)> node_exists;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> is_node_in_multi_selection;
};

class SelectionFocusNavigationLogic {
 public:
  explicit SelectionFocusNavigationLogic(SelectionFocusNavigationLogicBinding& binding) : binding_(binding) {}

  bool sync_focus_with_selection_or_fail() const {
    binding_.focus_selection_rules_defined = true;

    if (!binding_.focused_builder_node_id.empty()) {
      const bool focused_exists = binding_.node_exists(binding_.focused_builder_node_id);
      if (!focused_exists) {
        binding_.focused_builder_node_id.clear();
        binding_.stale_focus_rejected = true;
        binding_.refresh_tree_surface_label();
        return false;
      }
    }

    if (binding_.selected_builder_node_id.empty()) {
      binding_.multi_selected_node_ids.clear();
      binding_.focused_builder_node_id.clear();
      binding_.builder_selection_anchor_node_id.clear();
      binding_.refresh_tree_surface_label();
      return true;
    }

    if (!binding_.node_exists(binding_.selected_builder_node_id)) {
      binding_.focused_builder_node_id.clear();
      binding_.builder_selection_anchor_node_id.clear();
      binding_.stale_focus_rejected = true;
      binding_.refresh_tree_surface_label();
      return false;
    }

    binding_.focused_builder_node_id = binding_.selected_builder_node_id;
    binding_.sync_multi_selection_with_primary();
    binding_.builder_selection_anchor_node_id = binding_.selected_builder_node_id;
    binding_.refresh_tree_surface_label();
    return true;
  }

  bool add_node_to_multi_selection(const std::string& node_id) const {
    if (node_id.empty() || !binding_.node_exists(node_id)) {
      return false;
    }

    binding_.sync_multi_selection_with_primary();
    if (binding_.is_node_in_multi_selection(node_id)) {
      return false;
    }

    if (binding_.selected_builder_node_id.empty()) {
      binding_.selected_builder_node_id = node_id;
      binding_.focused_builder_node_id = node_id;
      binding_.builder_selection_anchor_node_id = node_id;
      binding_.multi_selected_node_ids.clear();
      binding_.multi_selected_node_ids.push_back(node_id);
      binding_.refresh_tree_surface_label();
      return true;
    }

    binding_.multi_selected_node_ids.push_back(node_id);
    binding_.sync_multi_selection_with_primary();
    if (binding_.builder_selection_anchor_node_id.empty() || !binding_.node_exists(binding_.builder_selection_anchor_node_id)) {
      binding_.builder_selection_anchor_node_id = binding_.selected_builder_node_id;
    }
    binding_.refresh_tree_surface_label();
    return true;
  }

  bool remove_node_from_multi_selection(const std::string& node_id) const {
    if (node_id.empty()) {
      return false;
    }

    binding_.sync_multi_selection_with_primary();
    auto it = std::find(binding_.multi_selected_node_ids.begin(), binding_.multi_selected_node_ids.end(), node_id);
    if (it == binding_.multi_selected_node_ids.end()) {
      return false;
    }

    const bool removing_primary = (node_id == binding_.selected_builder_node_id);
    binding_.multi_selected_node_ids.erase(it);
    if (removing_primary) {
      if (!binding_.multi_selected_node_ids.empty()) {
        binding_.selected_builder_node_id = binding_.multi_selected_node_ids.front();
      } else {
        binding_.selected_builder_node_id.clear();
      }
    }

    binding_.sync_multi_selection_with_primary();
    if (binding_.selected_builder_node_id.empty()) {
      binding_.focused_builder_node_id.clear();
      binding_.builder_selection_anchor_node_id.clear();
    } else if (binding_.focused_builder_node_id.empty() || !binding_.node_exists(binding_.focused_builder_node_id)) {
      binding_.focused_builder_node_id = binding_.selected_builder_node_id;
    }
    if (binding_.selected_builder_node_id.empty()) {
      binding_.builder_selection_anchor_node_id.clear();
    } else {
      binding_.builder_selection_anchor_node_id = binding_.selected_builder_node_id;
    }
    binding_.refresh_tree_surface_label();
    return true;
  }

  void clear_multi_selection() const {
    binding_.multi_selected_node_ids.clear();
    binding_.selected_builder_node_id.clear();
    binding_.focused_builder_node_id.clear();
    binding_.builder_selection_anchor_node_id.clear();
    binding_.refresh_tree_surface_label();
  }

  std::vector<std::string> collect_preorder_node_ids() const {
    std::vector<std::string> ordered{};
    if (binding_.builder_doc.root_node_id.empty() || !binding_.node_exists(binding_.builder_doc.root_node_id)) {
      return ordered;
    }

    std::vector<std::string> stack{};
    stack.push_back(binding_.builder_doc.root_node_id);

    while (!stack.empty()) {
      const std::string current_id = stack.back();
      stack.pop_back();
      if (!binding_.node_exists(current_id)) {
        continue;
      }
      ordered.push_back(current_id);

      auto* current = binding_.find_node_by_id(current_id);
      if (!current) {
        continue;
      }
      for (auto it = current->child_ids.rbegin(); it != current->child_ids.rend(); ++it) {
        if (!it->empty() && binding_.node_exists(*it)) {
          stack.push_back(*it);
        }
      }
    }

    return ordered;
  }

  std::vector<std::string> build_authoritative_selection_range(const std::string& anchor_id,
                                                               const std::string& extent_id) const {
    std::vector<std::string> range{};
    if (anchor_id.empty() || extent_id.empty() || !binding_.node_exists(anchor_id) || !binding_.node_exists(extent_id)) {
      return range;
    }

    const auto ordered = collect_preorder_node_ids();
    auto anchor_it = std::find(ordered.begin(), ordered.end(), anchor_id);
    auto extent_it = std::find(ordered.begin(), ordered.end(), extent_id);
    if (anchor_it == ordered.end() || extent_it == ordered.end()) {
      return range;
    }

    const auto begin_it = (anchor_it <= extent_it) ? anchor_it : extent_it;
    const auto end_it = (anchor_it <= extent_it) ? extent_it : anchor_it;
    for (auto it = begin_it; it != end_it + 1; ++it) {
      range.push_back(*it);
    }
    return range;
  }

  bool apply_tree_navigation(bool forward) const {
    if (!binding_.selected_builder_node_id.empty() && !binding_.node_exists(binding_.selected_builder_node_id)) {
      if (!binding_.builder_doc.root_node_id.empty() && binding_.node_exists(binding_.builder_doc.root_node_id)) {
        binding_.selected_builder_node_id = binding_.builder_doc.root_node_id;
      } else {
        binding_.selected_builder_node_id.clear();
      }
    }

    auto ordered = collect_preorder_node_ids();
    if (ordered.empty()) {
      binding_.selected_builder_node_id.clear();
      binding_.focused_builder_node_id.clear();
      return false;
    }

    if (binding_.selected_builder_node_id.empty()) {
      binding_.selected_builder_node_id = ordered.front();
      return sync_focus_with_selection_or_fail();
    }

    auto it = std::find(ordered.begin(), ordered.end(), binding_.selected_builder_node_id);
    if (it == ordered.end()) {
      binding_.selected_builder_node_id = ordered.front();
      binding_.stale_focus_rejected = true;
      return sync_focus_with_selection_or_fail();
    }

    if (forward) {
      ++it;
      if (it == ordered.end()) {
        it = ordered.begin();
      }
    } else {
      if (it == ordered.begin()) {
        it = ordered.end();
      }
      --it;
    }
    binding_.selected_builder_node_id = *it;
    return sync_focus_with_selection_or_fail();
  }

  bool apply_focus_navigation(bool forward) const {
    auto ordered = collect_preorder_node_ids();
    if (ordered.empty()) {
      binding_.focused_builder_node_id.clear();
      binding_.builder_selection_anchor_node_id.clear();
      binding_.refresh_tree_surface_label();
      return false;
    }

    if (binding_.focused_builder_node_id.empty() || !binding_.node_exists(binding_.focused_builder_node_id)) {
      if (!binding_.selected_builder_node_id.empty() && binding_.node_exists(binding_.selected_builder_node_id)) {
        binding_.focused_builder_node_id = binding_.selected_builder_node_id;
      } else {
        binding_.focused_builder_node_id = ordered.front();
      }
    }

    auto it = std::find(ordered.begin(), ordered.end(), binding_.focused_builder_node_id);
    if (it == ordered.end()) {
      binding_.focused_builder_node_id = ordered.front();
      binding_.refresh_tree_surface_label();
      return true;
    }

    if (forward) {
      ++it;
      if (it == ordered.end()) {
        it = ordered.begin();
      }
    } else {
      if (it == ordered.begin()) {
        it = ordered.end();
      }
      --it;
    }

    binding_.focused_builder_node_id = *it;
    binding_.refresh_tree_surface_label();
    return true;
  }

  bool apply_keyboard_multi_selection_add_focused() const {
    if (binding_.focused_builder_node_id.empty() || !binding_.node_exists(binding_.focused_builder_node_id)) {
      return false;
    }

    if (binding_.is_node_in_multi_selection(binding_.focused_builder_node_id)) {
      return false;
    }

    if (binding_.selected_builder_node_id.empty()) {
      binding_.selected_builder_node_id = binding_.focused_builder_node_id;
      binding_.multi_selected_node_ids = {binding_.selected_builder_node_id};
      binding_.sync_multi_selection_with_primary();
      binding_.refresh_tree_surface_label();
      return true;
    }

    binding_.multi_selected_node_ids.push_back(binding_.focused_builder_node_id);
    binding_.sync_multi_selection_with_primary();
    binding_.refresh_tree_surface_label();
    return true;
  }

  bool apply_keyboard_multi_selection_remove_focused() const {
    if (binding_.focused_builder_node_id.empty() || !binding_.node_exists(binding_.focused_builder_node_id)) {
      return false;
    }
    return remove_node_from_multi_selection(binding_.focused_builder_node_id);
  }

  bool apply_keyboard_multi_selection_clear() const {
    clear_multi_selection();
    return true;
  }

  bool apply_keyboard_multi_selection_navigate(bool forward, bool extend_selection) const {
    binding_.sync_multi_selection_with_primary();
    if (extend_selection) {
      const auto ordered = collect_preorder_node_ids();
      if (ordered.empty()) {
        binding_.focused_builder_node_id.clear();
        binding_.builder_selection_anchor_node_id.clear();
        binding_.refresh_tree_surface_label();
        return false;
      }
      if (binding_.selected_builder_node_id.empty() || !binding_.node_exists(binding_.selected_builder_node_id)) {
        binding_.selected_builder_node_id = (!binding_.focused_builder_node_id.empty() && binding_.node_exists(binding_.focused_builder_node_id))
          ? binding_.focused_builder_node_id
          : ordered.front();
      }
      binding_.sync_multi_selection_with_primary();
      if (binding_.builder_selection_anchor_node_id.empty() || !binding_.node_exists(binding_.builder_selection_anchor_node_id)) {
        binding_.builder_selection_anchor_node_id = binding_.selected_builder_node_id;
      }
    }

    if (!apply_focus_navigation(forward)) {
      return false;
    }

    if (!extend_selection) {
      return true;
    }

    const auto range = build_authoritative_selection_range(binding_.builder_selection_anchor_node_id, binding_.focused_builder_node_id);
    if (range.empty()) {
      return false;
    }

    binding_.selected_builder_node_id = binding_.builder_selection_anchor_node_id;
    binding_.multi_selected_node_ids = range;
    binding_.sync_multi_selection_with_primary();
    binding_.refresh_tree_surface_label();
    return true;
  }

  bool apply_tree_parent_child_navigation(bool to_parent) const {
    if (binding_.selected_builder_node_id.empty() || !binding_.node_exists(binding_.selected_builder_node_id)) {
      if (!binding_.builder_doc.root_node_id.empty() && binding_.node_exists(binding_.builder_doc.root_node_id)) {
        binding_.selected_builder_node_id = binding_.builder_doc.root_node_id;
        return sync_focus_with_selection_or_fail();
      }
      return false;
    }

    auto* current = binding_.find_node_by_id(binding_.selected_builder_node_id);
    if (!current) {
      return false;
    }

    if (to_parent) {
      if (current->parent_id.empty() || !binding_.node_exists(current->parent_id)) {
        return false;
      }
      binding_.selected_builder_node_id = current->parent_id;
      return sync_focus_with_selection_or_fail();
    }

    if (current->child_ids.empty()) {
      return false;
    }

    for (const auto& child_id : current->child_ids) {
      if (!child_id.empty() && binding_.node_exists(child_id)) {
        binding_.selected_builder_node_id = child_id;
        return sync_focus_with_selection_or_fail();
      }
    }

    return false;
  }

  bool remap_selection_or_fail() const {
    binding_.selection_coherence_hardened = true;

    binding_.sync_multi_selection_with_primary();

    if (binding_.selected_builder_node_id.empty()) {
      if (!binding_.builder_doc.root_node_id.empty() && binding_.node_exists(binding_.builder_doc.root_node_id)) {
        binding_.selected_builder_node_id = binding_.builder_doc.root_node_id;
        binding_.sync_multi_selection_with_primary();
        return true;
      }
      binding_.multi_selected_node_ids.clear();
      binding_.builder_selection_anchor_node_id.clear();
      return true;
    }

    if (binding_.node_exists(binding_.selected_builder_node_id)) {
      binding_.sync_multi_selection_with_primary();
      return true;
    }

    binding_.stale_selection_rejected = true;

    if (!binding_.builder_doc.root_node_id.empty() && binding_.node_exists(binding_.builder_doc.root_node_id)) {
      binding_.selected_builder_node_id = binding_.builder_doc.root_node_id;
      binding_.sync_multi_selection_with_primary();
      return true;
    }

    binding_.selected_builder_node_id.clear();
    binding_.multi_selected_node_ids.clear();
    binding_.builder_selection_anchor_node_id.clear();
    binding_.undefined_state_detected = true;
    return false;
  }

 private:
  SelectionFocusNavigationLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_SELECTION_FOCUS_NAVIGATION_LOGIC(logic_object) \
  auto sync_focus_with_selection_or_fail = [&]() -> bool { \
    return (logic_object).sync_focus_with_selection_or_fail(); \
  }; \
  auto add_node_to_multi_selection = [&](const std::string& node_id) -> bool { \
    return (logic_object).add_node_to_multi_selection(node_id); \
  }; \
  auto remove_node_from_multi_selection = [&](const std::string& node_id) -> bool { \
    return (logic_object).remove_node_from_multi_selection(node_id); \
  }; \
  auto clear_multi_selection = [&]() { \
    (logic_object).clear_multi_selection(); \
  }; \
  auto collect_preorder_node_ids = [&]() -> std::vector<std::string> { \
    return (logic_object).collect_preorder_node_ids(); \
  }; \
  auto build_authoritative_selection_range = [&](const std::string& anchor_id, const std::string& extent_id) -> std::vector<std::string> { \
    return (logic_object).build_authoritative_selection_range(anchor_id, extent_id); \
  }; \
  auto apply_tree_navigation = [&](bool forward) -> bool { \
    return (logic_object).apply_tree_navigation(forward); \
  }; \
  auto apply_focus_navigation = [&](bool forward) -> bool { \
    return (logic_object).apply_focus_navigation(forward); \
  }; \
  auto apply_keyboard_multi_selection_add_focused = [&]() -> bool { \
    return (logic_object).apply_keyboard_multi_selection_add_focused(); \
  }; \
  auto apply_keyboard_multi_selection_remove_focused = [&]() -> bool { \
    return (logic_object).apply_keyboard_multi_selection_remove_focused(); \
  }; \
  auto apply_keyboard_multi_selection_clear = [&]() -> bool { \
    return (logic_object).apply_keyboard_multi_selection_clear(); \
  }; \
  auto apply_keyboard_multi_selection_navigate = [&](bool forward, bool extend_selection) -> bool { \
    return (logic_object).apply_keyboard_multi_selection_navigate(forward, extend_selection); \
  }; \
  auto apply_tree_parent_child_navigation = [&](bool to_parent) -> bool { \
    return (logic_object).apply_tree_parent_child_navigation(to_parent); \
  }; \
  auto remap_selection_or_fail = [&]() -> bool { \
    return (logic_object).remap_selection_or_fail(); \
  };
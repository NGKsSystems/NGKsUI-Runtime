#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"

namespace desktop_file_tool {

struct BuilderDragDropMutationPlan {
  bool valid = false;
  bool is_reparent = false;
  std::string reason{};
  std::vector<std::string> moved_node_ids{};
  std::string target_parent_id{};
  std::size_t insert_index = 0;
};

struct DragDropPlanningLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& drag_source_node_id;
  bool& drag_active;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
  std::string& drag_target_preview_parent_id;
  std::size_t& drag_target_preview_insert_index;
  std::string& drag_target_preview_resolution_kind;
  std::string& hover_node_id;
  bool& tree_drag_reorder_present;
  bool& illegal_drop_rejected;
  std::function<bool(const std::string&)> node_exists;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> is_node_in_multi_selection;
  std::function<std::vector<std::string>()> collect_preorder_node_ids;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<void()> refresh_preview_surface_label;
};

class DragDropPlanningLogic {
 public:
  explicit DragDropPlanningLogic(DragDropPlanningLogicBinding& binding) : binding_(binding) {}

  bool begin_tree_drag(const std::string& source_id) const {
    binding_.tree_drag_reorder_present = true;
    if (source_id.empty() || !binding_.node_exists(source_id)) {
      return false;
    }
    if (source_id == binding_.builder_doc.root_node_id) {
      return false;
    }
    binding_.drag_source_node_id = source_id;
    binding_.drag_active = true;
    binding_.selected_builder_node_id = source_id;
    binding_.remap_selection_or_fail();
    binding_.sync_focus_with_selection_or_fail();
    return true;
  }

  void cancel_tree_drag() const {
    binding_.drag_source_node_id.clear();
    binding_.drag_active = false;
    binding_.drag_target_preview_node_id.clear();
    binding_.drag_target_preview_is_illegal = false;
    binding_.drag_target_preview_parent_id.clear();
    binding_.drag_target_preview_insert_index = 0;
    binding_.drag_target_preview_resolution_kind.clear();
  }

  std::vector<std::string> collect_drag_requested_node_ids(const std::string& source_id) const {
    if (source_id == binding_.selected_builder_node_id &&
        binding_.multi_selected_node_ids.size() > 1 &&
        binding_.is_node_in_multi_selection(source_id)) {
      return binding_.multi_selected_node_ids;
    }
    return std::vector<std::string>{source_id};
  }

  bool resolve_bulk_move_reparent_request(const std::vector<std::string>& requested_node_ids,
                                          const std::string& requested_target_id,
                                          std::string& reason_out,
                                          std::vector<std::string>* normalized_ids_out) const {
    reason_out.clear();
    if (requested_target_id.empty()) {
      reason_out = "missing_target";
      return false;
    }
    if (!binding_.node_exists(requested_target_id)) {
      reason_out = "target_lookup_failed";
      return false;
    }

    auto* target_node = binding_.find_node_by_id(requested_target_id);
    if (!target_node) {
      reason_out = "target_lookup_failed";
      return false;
    }
    if (requested_target_id == binding_.builder_doc.root_node_id) {
      reason_out = "protected_target_root";
      return false;
    }
    if (target_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
      reason_out = "protected_target_shell";
      return false;
    }
    if (target_node->widget_type != ngk::ui::builder::BuilderWidgetType::VerticalLayout) {
      reason_out = "target_not_vertical_layout";
      return false;
    }

    std::vector<std::string> unique_ids{};
    for (const auto& node_id : requested_node_ids) {
      if (node_id.empty()) {
        continue;
      }
      if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
        unique_ids.push_back(node_id);
      }
    }
    if (unique_ids.empty()) {
      reason_out = "no_selected_nodes";
      return false;
    }

    for (const auto& node_id : unique_ids) {
      auto* source_node = binding_.find_node_by_id(node_id);
      if (!source_node) {
        reason_out = "selected_node_lookup_failed_" + node_id;
        return false;
      }
      if (node_id == binding_.builder_doc.root_node_id || source_node->parent_id.empty()) {
        reason_out = "protected_source_root_" + node_id;
        return false;
      }
      if (source_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
        reason_out = "protected_source_shell_" + node_id;
        return false;
      }
      if (!binding_.node_exists(source_node->parent_id)) {
        reason_out = "source_parent_missing_" + node_id;
        return false;
      }
      if (node_id == requested_target_id) {
        reason_out = "target_in_selected_set_" + node_id;
        return false;
      }
      if (is_in_subtree_of(requested_target_id, node_id)) {
        reason_out = "circular_target_" + node_id;
        return false;
      }
    }

    const auto ordered = binding_.collect_preorder_node_ids();
    std::vector<std::string> normalized{};
    normalized.reserve(unique_ids.size());
    for (const auto& node_id : ordered) {
      if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
        continue;
      }
      bool covered_by_ancestor = false;
      auto* current = binding_.find_node_by_id(node_id);
      while (current && !current->parent_id.empty()) {
        if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
          covered_by_ancestor = true;
          break;
        }
        current = binding_.find_node_by_id(current->parent_id);
      }
      if (!covered_by_ancestor) {
        normalized.push_back(node_id);
      }
    }

    if (normalized.empty()) {
      reason_out = "no_eligible_move_sources";
      return false;
    }

    for (const auto& node_id : normalized) {
      auto* source_node = binding_.find_node_by_id(node_id);
      if (!source_node) {
        reason_out = "selected_node_lookup_failed_" + node_id;
        return false;
      }
      if (source_node->parent_id == requested_target_id) {
        reason_out = "already_child_of_target_" + node_id;
        return false;
      }
    }

    if (normalized_ids_out != nullptr) {
      *normalized_ids_out = normalized;
    }
    return true;
  }

  BuilderDragDropMutationPlan resolve_tree_drag_drop_plan(const std::string& target_id,
                                                          bool is_reparent) const {
    BuilderDragDropMutationPlan plan{};
    plan.is_reparent = is_reparent;

    if (!binding_.drag_active || binding_.drag_source_node_id.empty()) {
      plan.reason = "drag_not_active";
      return plan;
    }
    if (target_id.empty()) {
      plan.reason = "missing_target";
      return plan;
    }
    if (!binding_.node_exists(target_id)) {
      plan.reason = "target_lookup_failed";
      return plan;
    }

    const auto requested_ids = collect_drag_requested_node_ids(binding_.drag_source_node_id);
    if (is_reparent) {
      std::vector<std::string> normalized_ids{};
      if (!resolve_bulk_move_reparent_request(requested_ids, target_id, plan.reason, &normalized_ids)) {
        return plan;
      }
      plan.valid = true;
      plan.moved_node_ids = normalized_ids;
      plan.target_parent_id = target_id;
      if (auto* target_node = binding_.find_node_by_id(target_id)) {
        plan.insert_index = target_node->child_ids.size();
      }
      return plan;
    }

    auto* target_node = binding_.find_node_by_id(target_id);
    if (!target_node) {
      plan.reason = "target_lookup_failed";
      return plan;
    }
    if (target_id == binding_.builder_doc.root_node_id || target_node->parent_id.empty()) {
      plan.reason = "protected_target_root";
      return plan;
    }

    auto* target_parent = binding_.find_node_by_id(target_node->parent_id);
    if (!target_parent) {
      plan.reason = "target_parent_missing";
      return plan;
    }

    std::vector<std::string> unique_ids{};
    for (const auto& node_id : requested_ids) {
      if (node_id.empty()) {
        continue;
      }
      if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
        unique_ids.push_back(node_id);
      }
    }
    if (unique_ids.empty()) {
      plan.reason = "no_selected_nodes";
      return plan;
    }

    std::vector<std::string> normalized_ids{};
    for (const auto& sibling_id : target_parent->child_ids) {
      if (std::find(unique_ids.begin(), unique_ids.end(), sibling_id) != unique_ids.end()) {
        normalized_ids.push_back(sibling_id);
      }
    }
    if (normalized_ids.empty()) {
      plan.reason = "no_eligible_move_sources";
      return plan;
    }

    for (const auto& node_id : normalized_ids) {
      auto* source_node = binding_.find_node_by_id(node_id);
      if (!source_node) {
        plan.reason = "selected_node_lookup_failed_" + node_id;
        return plan;
      }
      if (node_id == binding_.builder_doc.root_node_id || source_node->parent_id.empty()) {
        plan.reason = "protected_source_root_" + node_id;
        return plan;
      }
      if (source_node->parent_id != target_parent->node_id) {
        plan.reason = "mixed_parent_selection_" + node_id;
        return plan;
      }
      if (node_id == target_id) {
        plan.reason = "target_in_selected_set_" + node_id;
        return plan;
      }
    }

    std::vector<std::string> remaining_siblings{};
    remaining_siblings.reserve(target_parent->child_ids.size());
    for (const auto& sibling_id : target_parent->child_ids) {
      if (std::find(normalized_ids.begin(), normalized_ids.end(), sibling_id) == normalized_ids.end()) {
        remaining_siblings.push_back(sibling_id);
      }
    }

    auto target_it = std::find(remaining_siblings.begin(), remaining_siblings.end(), target_id);
    if (target_it == remaining_siblings.end()) {
      plan.reason = "target_elided_from_parent_order";
      return plan;
    }

    plan.valid = true;
    plan.moved_node_ids = normalized_ids;
    plan.target_parent_id = target_parent->node_id;
    plan.insert_index = static_cast<std::size_t>(std::distance(remaining_siblings.begin(), target_it)) + 1;
    return plan;
  }

  bool is_legal_drop_target_reorder(const std::string& target_id) const {
    return resolve_tree_drag_drop_plan(target_id, false).valid;
  }

  bool is_legal_drop_target_reparent(const std::string& target_id) const {
    return resolve_tree_drag_drop_plan(target_id, true).valid;
  }

  bool reject_illegal_tree_drag_drop(const std::string& target_id, bool is_reparent) const {
    const bool would_be_legal = is_reparent
      ? is_legal_drop_target_reparent(target_id)
      : is_legal_drop_target_reorder(target_id);
    if (would_be_legal) {
      return false;
    }
    binding_.illegal_drop_rejected = true;
    cancel_tree_drag();
    return true;
  }

  void set_preview_hover(const std::string& node_id) const {
    binding_.hover_node_id = node_id;
    binding_.refresh_preview_surface_label();
  }

  void clear_preview_hover() const {
    binding_.hover_node_id.clear();
    binding_.refresh_preview_surface_label();
  }

  void set_drag_target_preview(const std::string& target_id, bool is_reparent) const {
    const auto plan = resolve_tree_drag_drop_plan(target_id, is_reparent);
    binding_.drag_target_preview_node_id = target_id;
    binding_.drag_target_preview_is_illegal = !plan.valid;
    binding_.drag_target_preview_parent_id = plan.valid ? plan.target_parent_id : std::string{};
    binding_.drag_target_preview_insert_index = plan.valid ? plan.insert_index : 0;
    binding_.drag_target_preview_resolution_kind = plan.valid
      ? (plan.is_reparent ? std::string("reparent") : std::string("reorder"))
      : std::string("invalid");
    binding_.refresh_preview_surface_label();
  }

  void clear_drag_target_preview() const {
    binding_.drag_target_preview_node_id.clear();
    binding_.drag_target_preview_is_illegal = false;
    binding_.drag_target_preview_parent_id.clear();
    binding_.drag_target_preview_insert_index = 0;
    binding_.drag_target_preview_resolution_kind.clear();
    binding_.refresh_preview_surface_label();
  }

 private:
  bool is_in_subtree_of(const std::string& node_id, const std::string& ancestor_id) const {
    if (node_id.empty() || ancestor_id.empty()) {
      return false;
    }
    if (node_id == ancestor_id) {
      return true;
    }
    std::vector<std::string> to_visit{ancestor_id};
    for (std::size_t i = 0; i < to_visit.size(); ++i) {
      auto* node = binding_.find_node_by_id(to_visit[i]);
      if (!node) {
        continue;
      }
      for (const auto& child_id : node->child_ids) {
        if (child_id == node_id) {
          return true;
        }
        to_visit.push_back(child_id);
      }
    }
    return false;
  }

  DragDropPlanningLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_DRAG_DROP_PLANNING_LOGIC(logic_object) \
  auto begin_tree_drag = [&](const std::string& source_id) -> bool { \
    return (logic_object).begin_tree_drag(source_id); \
  }; \
  auto cancel_tree_drag = [&]() { \
    (logic_object).cancel_tree_drag(); \
  }; \
  auto collect_drag_requested_node_ids = [&](const std::string& source_id) -> std::vector<std::string> { \
    return (logic_object).collect_drag_requested_node_ids(source_id); \
  }; \
  auto resolve_bulk_move_reparent_request = [&](const std::vector<std::string>& requested_node_ids, const std::string& requested_target_id, std::string& reason_out, std::vector<std::string>* normalized_ids_out) -> bool { \
    return (logic_object).resolve_bulk_move_reparent_request(requested_node_ids, requested_target_id, reason_out, normalized_ids_out); \
  }; \
  auto resolve_tree_drag_drop_plan = [&](const std::string& target_id, bool is_reparent) -> ::desktop_file_tool::BuilderDragDropMutationPlan { \
    return (logic_object).resolve_tree_drag_drop_plan(target_id, is_reparent); \
  }; \
  auto is_legal_drop_target_reorder = [&](const std::string& target_id) -> bool { \
    return (logic_object).is_legal_drop_target_reorder(target_id); \
  }; \
  auto is_legal_drop_target_reparent = [&](const std::string& target_id) -> bool { \
    return (logic_object).is_legal_drop_target_reparent(target_id); \
  }; \
  auto reject_illegal_tree_drag_drop = [&](const std::string& target_id, bool is_reparent) -> bool { \
    return (logic_object).reject_illegal_tree_drag_drop(target_id, is_reparent); \
  }; \
  auto set_preview_hover = [&](const std::string& node_id) { \
    (logic_object).set_preview_hover(node_id); \
  }; \
  auto clear_preview_hover = [&]() { \
    (logic_object).clear_preview_hover(); \
  }; \
  auto set_drag_target_preview = [&](const std::string& target_id, bool is_reparent) { \
    (logic_object).set_drag_target_preview(target_id, is_reparent); \
  }; \
  auto clear_drag_target_preview = [&]() { \
    (logic_object).clear_drag_target_preview(); \
  };
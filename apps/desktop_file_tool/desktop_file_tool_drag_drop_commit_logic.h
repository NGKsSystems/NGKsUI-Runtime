#pragma once

#include <algorithm>
#include <any>
#include <cstddef>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_drag_drop_planning_logic.h"

namespace desktop_file_tool {

struct DragDropCommitLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& last_bulk_move_reparent_status_code;
  std::string& last_bulk_move_reparent_reason;
  bool& bulk_move_reparent_present;
  bool& invalid_or_protected_bulk_target_rejected;
  bool& eligible_selected_nodes_moved;
  bool& post_move_selection_deterministic;
  bool& legal_reorder_drop_applied;
  bool& legal_reparent_drop_applied;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> node_exists;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool(const std::vector<std::string>&, const std::string&, std::string&, std::vector<std::string>*)>
    resolve_bulk_move_reparent_request;
  std::function<BuilderDragDropMutationPlan(const std::string&, bool)> resolve_tree_drag_drop_plan;
  std::function<void()> cancel_tree_drag;
  std::function<std::any()> capture_mutation_checkpoint;
  std::function<void(const char*,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>&,
                     const std::any&)> push_to_history;
  std::function<void(bool)> recompute_builder_dirty_state;
  std::function<void()> scrub_stale_lifecycle_references;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<void()> refresh_inspector_surface_label;
  std::function<void()> refresh_preview_surface_label;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(const std::any&, const char*)> enforce_global_invariant_or_rollback;
};

class DragDropCommitLogic {
 public:
  explicit DragDropCommitLogic(DragDropCommitLogicBinding& binding) : binding_(binding) {}

  bool apply_bulk_move_reparent_selected_nodes_command(const std::vector<std::string>& requested_ids,
                                                       const std::string& target_id) const {
    const std::any checkpoint = binding_.capture_mutation_checkpoint();
    binding_.bulk_move_reparent_present = true;

    std::string rejection_reason;
    std::vector<std::string> normalized_ids{};
    if (!binding_.resolve_bulk_move_reparent_request(requested_ids, target_id, rejection_reason, &normalized_ids)) {
      binding_.invalid_or_protected_bulk_target_rejected = true;
      binding_.last_bulk_move_reparent_status_code = "REJECTED";
      binding_.last_bulk_move_reparent_reason =
        rejection_reason.empty() ? std::string("bulk_move_reparent_rejected") : rejection_reason;
      binding_.refresh_inspector_surface_label();
      binding_.refresh_preview_surface_label();
      return false;
    }

    auto* target_node = binding_.find_node_by_id(target_id);
    if (!target_node) {
      binding_.invalid_or_protected_bulk_target_rejected = true;
      binding_.last_bulk_move_reparent_status_code = "REJECTED";
      binding_.last_bulk_move_reparent_reason = "target_lookup_failed";
      binding_.refresh_inspector_surface_label();
      binding_.refresh_preview_surface_label();
      return false;
    }

    for (const auto& node_id : normalized_ids) {
      auto* source_node = binding_.find_node_by_id(node_id);
      if (!source_node) {
        continue;
      }
      auto* old_parent = binding_.find_node_by_id(source_node->parent_id);
      if (!old_parent) {
        continue;
      }
      auto& siblings = old_parent->child_ids;
      siblings.erase(std::remove(siblings.begin(), siblings.end(), node_id), siblings.end());
    }

    for (const auto& node_id : normalized_ids) {
      target_node->child_ids.push_back(node_id);
      auto* source_node = binding_.find_node_by_id(node_id);
      if (source_node) {
        source_node->parent_id = target_id;
      }
    }

    binding_.scrub_stale_lifecycle_references();
    binding_.sync_multi_selection_with_primary();
    binding_.eligible_selected_nodes_moved = true;
    binding_.post_move_selection_deterministic =
      !binding_.selected_builder_node_id.empty() &&
      binding_.node_exists(binding_.selected_builder_node_id) &&
      !binding_.multi_selected_node_ids.empty() &&
      binding_.multi_selected_node_ids.front() == binding_.selected_builder_node_id;
    binding_.last_bulk_move_reparent_status_code = "SUCCESS";
    binding_.last_bulk_move_reparent_reason = "none";
    binding_.refresh_inspector_surface_label();
    binding_.refresh_preview_surface_label();
    return binding_.enforce_global_invariant_or_rollback(
      checkpoint,
      "apply_bulk_move_reparent_selected_nodes_command");
  }

  bool commit_tree_drag_reorder(const std::string& target_id) const {
    const std::any checkpoint = binding_.capture_mutation_checkpoint();
    const auto plan = binding_.resolve_tree_drag_drop_plan(target_id, false);
    if (!plan.valid) {
      binding_.cancel_tree_drag();
      return false;
    }

    const auto before_nodes = binding_.builder_doc.nodes;
    const std::string before_root = binding_.builder_doc.root_node_id;
    const std::string before_sel = binding_.selected_builder_node_id;
    const auto before_multi = binding_.multi_selected_node_ids;

    auto* parent = binding_.find_node_by_id(plan.target_parent_id);
    if (!parent) {
      return false;
    }

    auto& child_ids = parent->child_ids;
    std::vector<std::string> remaining{};
    remaining.reserve(child_ids.size());
    for (const auto& child_id : child_ids) {
      if (std::find(plan.moved_node_ids.begin(), plan.moved_node_ids.end(), child_id) == plan.moved_node_ids.end()) {
        remaining.push_back(child_id);
      }
    }
    if (plan.insert_index > remaining.size()) {
      return false;
    }

    child_ids = remaining;
    child_ids.insert(
      child_ids.begin() + static_cast<std::ptrdiff_t>(plan.insert_index),
      plan.moved_node_ids.begin(),
      plan.moved_node_ids.end());
    binding_.selected_builder_node_id = plan.moved_node_ids.front();
    binding_.multi_selected_node_ids = plan.moved_node_ids;
    binding_.sync_multi_selection_with_primary();
    binding_.push_to_history("drag_reorder", before_nodes, before_root, before_sel, before_multi, checkpoint);
    binding_.recompute_builder_dirty_state(true);
    binding_.cancel_tree_drag();
    binding_.remap_selection_or_fail();
    binding_.sync_focus_with_selection_or_fail();
    binding_.refresh_inspector_or_fail();
    binding_.refresh_preview_or_fail();
    binding_.check_cross_surface_sync();
    binding_.legal_reorder_drop_applied = true;
    return binding_.enforce_global_invariant_or_rollback(checkpoint, "commit_tree_drag_reorder");
  }

  bool commit_tree_drag_reparent(const std::string& target_id) const {
    const std::any checkpoint = binding_.capture_mutation_checkpoint();
    const auto plan = binding_.resolve_tree_drag_drop_plan(target_id, true);
    if (!plan.valid) {
      binding_.cancel_tree_drag();
      return false;
    }

    const auto before_nodes = binding_.builder_doc.nodes;
    const std::string before_root = binding_.builder_doc.root_node_id;
    const std::string before_sel = binding_.selected_builder_node_id;
    const auto before_multi = binding_.multi_selected_node_ids;
    binding_.selected_builder_node_id = plan.moved_node_ids.front();
    if (!apply_bulk_move_reparent_selected_nodes_command(plan.moved_node_ids, target_id)) {
      binding_.cancel_tree_drag();
      return false;
    }

    binding_.push_to_history("drag_reparent", before_nodes, before_root, before_sel, before_multi, checkpoint);
    binding_.recompute_builder_dirty_state(true);
    binding_.cancel_tree_drag();
    binding_.remap_selection_or_fail();
    binding_.sync_focus_with_selection_or_fail();
    binding_.refresh_inspector_or_fail();
    binding_.refresh_preview_or_fail();
    binding_.check_cross_surface_sync();
    binding_.legal_reparent_drop_applied = true;
    return binding_.enforce_global_invariant_or_rollback(checkpoint, "commit_tree_drag_reparent");
  }

 private:
  DragDropCommitLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_DRAG_DROP_COMMIT_LOGIC(logic_object) \
  auto apply_bulk_move_reparent_selected_nodes_command = [&](const std::vector<std::string>& requested_ids, const std::string& target_id) -> bool { \
    return (logic_object).apply_bulk_move_reparent_selected_nodes_command(requested_ids, target_id); \
  }; \
  auto commit_tree_drag_reorder = [&](const std::string& target_id) -> bool { \
    return (logic_object).commit_tree_drag_reorder(target_id); \
  }; \
  auto commit_tree_drag_reparent = [&](const std::string& target_id) -> bool { \
    return (logic_object).commit_tree_drag_reparent(target_id); \
  };
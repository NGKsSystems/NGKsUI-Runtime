#pragma once

#include <algorithm>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_history_checkpoint.h"

namespace desktop_file_tool {

struct DeleteCommandLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  bool& bulk_delete_present;
  bool& protected_or_invalid_bulk_delete_rejected;
  bool& eligible_selected_nodes_deleted;
  bool& post_delete_selection_deterministic;
  bool& shell_delete_control_present;
  bool& protected_delete_rejected;
  bool& legal_delete_applied;
  bool& post_delete_selection_remapped_or_cleared;
  std::string& last_bulk_delete_status_code;
  std::string& last_bulk_delete_reason;
  std::function<BuilderMutationCheckpoint()> capture_mutation_checkpoint;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> node_exists;
  std::function<void(const std::string&)> remove_node_and_descendants;
  std::function<void()> scrub_stale_lifecycle_references;
  std::function<void()> refresh_inspector_surface_label;
  std::function<void()> refresh_preview_surface_label;
  std::function<bool(const BuilderMutationCheckpoint&, const char*)> enforce_global_invariant_or_rollback;
};

class DeleteCommandLogic {
 public:
  explicit DeleteCommandLogic(DeleteCommandLogicBinding& binding) : binding_(binding) {}

  std::string delete_rejection_reason_for_node(const std::string& node_id) const {
    if (node_id.empty()) {
      return "no_selected_node";
    }

    auto* target = binding_.find_node_by_id(node_id);
    if (!target) {
      return "selected_node_lookup_failed";
    }

    const bool is_root = (node_id == binding_.builder_doc.root_node_id) || target->parent_id.empty();
    const bool shell_critical = target->container_type == ngk::ui::builder::BuilderContainerType::Shell;
    if (is_root) {
      return "protected_root";
    }
    if (shell_critical) {
      return "protected_shell";
    }
    if (target->parent_id.empty() || !binding_.node_exists(target->parent_id)) {
      return "parent_missing_for_delete";
    }
    return "";
  }

  std::vector<std::string> collect_bulk_delete_target_ids(const std::vector<std::string>& requested_ids,
                                                          std::string& rejection_reason) const {
    rejection_reason.clear();
    std::vector<std::string> normalized{};
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
      rejection_reason = "no_selected_nodes";
      return normalized;
    }

    for (const auto& node_id : unique_ids) {
      const std::string reason = delete_rejection_reason_for_node(node_id);
      if (!reason.empty()) {
        rejection_reason = reason + "_" + node_id;
        return {};
      }
    }

    for (const auto& node_id : unique_ids) {
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

    return normalized;
  }

  std::string compute_post_delete_selection_fallback(const std::vector<std::string>& deleted_ids) const {
    if (deleted_ids.empty()) {
      return binding_.selected_builder_node_id;
    }

    auto is_deleted = [&](const std::string& node_id) {
      return std::find(deleted_ids.begin(), deleted_ids.end(), node_id) != deleted_ids.end();
    };

    std::string anchor_deleted_id{};
    if (!binding_.selected_builder_node_id.empty() && is_deleted(binding_.selected_builder_node_id)) {
      anchor_deleted_id = binding_.selected_builder_node_id;
    } else {
      for (const auto& deleted_id : deleted_ids) {
        if (!deleted_id.empty()) {
          anchor_deleted_id = deleted_id;
          break;
        }
      }
    }

    const auto* anchor_node = anchor_deleted_id.empty() ? nullptr : binding_.find_node_by_id(anchor_deleted_id);
    std::string fallback_parent_id = anchor_node ? anchor_node->parent_id : std::string{};
    while (!fallback_parent_id.empty()) {
      if (!is_deleted(fallback_parent_id) && binding_.node_exists(fallback_parent_id)) {
        return fallback_parent_id;
      }
      const auto* fallback_parent = binding_.find_node_by_id(fallback_parent_id);
      if (fallback_parent == nullptr) {
        break;
      }
      fallback_parent_id = fallback_parent->parent_id;
    }

    if (!binding_.builder_doc.root_node_id.empty() &&
        !is_deleted(binding_.builder_doc.root_node_id) &&
        binding_.node_exists(binding_.builder_doc.root_node_id)) {
      return binding_.builder_doc.root_node_id;
    }
    return std::string{};
  }

  bool apply_bulk_delete_selected_nodes_command(const std::vector<std::string>& requested_ids) {
    const BuilderMutationCheckpoint checkpoint = binding_.capture_mutation_checkpoint();
    binding_.bulk_delete_present = true;
    binding_.shell_delete_control_present = true;

    std::string rejection_reason;
    const auto delete_targets = collect_bulk_delete_target_ids(requested_ids, rejection_reason);
    if (delete_targets.empty()) {
      binding_.protected_or_invalid_bulk_delete_rejected = true;
      binding_.protected_delete_rejected = true;
      binding_.last_bulk_delete_status_code = "REJECTED";
      binding_.last_bulk_delete_reason = rejection_reason.empty() ? std::string("no_eligible_delete_targets") : rejection_reason;
      binding_.refresh_inspector_surface_label();
      binding_.refresh_preview_surface_label();
      return false;
    }

    const std::string fallback_selection = compute_post_delete_selection_fallback(delete_targets);
    for (const auto& deleting_id : delete_targets) {
      binding_.remove_node_and_descendants(deleting_id);
    }

    binding_.scrub_stale_lifecycle_references();

    if (!fallback_selection.empty() && binding_.node_exists(fallback_selection)) {
      binding_.selected_builder_node_id = fallback_selection;
      binding_.multi_selected_node_ids = {fallback_selection};
    } else {
      binding_.selected_builder_node_id.clear();
      binding_.multi_selected_node_ids.clear();
    }

    binding_.legal_delete_applied = true;
    binding_.post_delete_selection_remapped_or_cleared =
      binding_.selected_builder_node_id.empty() || binding_.node_exists(binding_.selected_builder_node_id);
    binding_.eligible_selected_nodes_deleted = true;
    binding_.post_delete_selection_deterministic =
      (binding_.selected_builder_node_id.empty() && binding_.multi_selected_node_ids.empty()) ||
      (!binding_.selected_builder_node_id.empty() &&
       binding_.multi_selected_node_ids.size() == 1 &&
       binding_.multi_selected_node_ids.front() == binding_.selected_builder_node_id);
    binding_.last_bulk_delete_status_code = "SUCCESS";
    binding_.last_bulk_delete_reason = "none";
    binding_.refresh_inspector_surface_label();
    binding_.refresh_preview_surface_label();
    return binding_.enforce_global_invariant_or_rollback(checkpoint, "apply_bulk_delete_selected_nodes_command");
  }

  bool apply_delete_selected_node_command() {
    binding_.shell_delete_control_present = true;
    binding_.last_bulk_delete_status_code = "not_run";
    binding_.last_bulk_delete_reason = "none";
    return apply_bulk_delete_selected_nodes_command({binding_.selected_builder_node_id});
  }

  bool apply_delete_command_for_current_selection() {
    if (binding_.multi_selected_node_ids.size() > 1) {
      return apply_bulk_delete_selected_nodes_command(binding_.multi_selected_node_ids);
    }
    return apply_delete_selected_node_command();
  }

 private:
  DeleteCommandLogicBinding& binding_;
};

}  // namespace desktop_file_tool
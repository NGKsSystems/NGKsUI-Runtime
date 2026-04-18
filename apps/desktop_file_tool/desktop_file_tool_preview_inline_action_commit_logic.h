#pragma once

#include <algorithm>
#include <any>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct PreviewInlineActionCommitLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  int& preview_inline_action_commit_sequence;
  std::string& last_preview_inline_action_commit_status_code;
  std::string& last_preview_inline_action_commit_reason;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> node_exists;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<std::vector<PreviewInlineActionAffordanceEntry>(const ngk::ui::builder::BuilderNode&)>
    build_preview_inline_action_entries;
  std::function<std::any()> capture_mutation_checkpoint;
  std::function<void(const char*,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>&,
                     const std::any&)> push_to_history;
  std::function<bool(const std::any&, const char*)> enforce_global_invariant_or_rollback;
  std::function<void(bool)> recompute_builder_dirty_state;
  std::function<bool(const std::string&)> apply_inspector_text_edit_command;
  std::function<bool()> apply_delete_command_for_current_selection;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<void()> refresh_preview_surface_label;
  std::function<bool()> check_cross_surface_sync;
};

class PreviewInlineActionCommitLogic {
 public:
  explicit PreviewInlineActionCommitLogic(PreviewInlineActionCommitLogicBinding& binding) : binding_(binding) {}

  bool apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType type,
                                  const std::string& under_node_id,
                                  const std::string& new_node_id) const {
    const std::any checkpoint = binding_.capture_mutation_checkpoint();
    auto* parent = binding_.find_node_by_id(under_node_id);
    if (parent == nullptr) {
      return false;
    }
    if (!is_container_type(parent->widget_type)) {
      return false;
    }
    for (const auto& node : binding_.builder_doc.nodes) {
      if (node.node_id == new_node_id) {
        return false;
      }
    }

    const auto before_nodes = binding_.builder_doc.nodes;
    const std::string before_root = binding_.builder_doc.root_node_id;
    const std::string before_sel = binding_.selected_builder_node_id;
    const auto before_multi = binding_.multi_selected_node_ids;

    ngk::ui::builder::BuilderNode new_node{};
    new_node.node_id = new_node_id;
    new_node.parent_id = under_node_id;
    new_node.widget_type = type;
    new_node.text = std::string(ngk::ui::builder::to_string(type));
    parent->child_ids.push_back(new_node_id);
    binding_.builder_doc.nodes.push_back(std::move(new_node));
    binding_.selected_builder_node_id = new_node_id;
    binding_.multi_selected_node_ids = {new_node_id};
    binding_.sync_multi_selection_with_primary();
    binding_.push_to_history("typed_insert", before_nodes, before_root, before_sel, before_multi, checkpoint);
    return binding_.enforce_global_invariant_or_rollback(checkpoint, "apply_typed_palette_insert");
  }

  bool apply_preview_inline_action_commit(const std::string& action_id) const {
    if (binding_.selected_builder_node_id.empty() || !binding_.node_exists(binding_.selected_builder_node_id)) {
      return reject_commit("no_valid_selection");
    }

    auto* selected_node = binding_.find_node_by_id(binding_.selected_builder_node_id);
    if (!selected_node) {
      return reject_commit("selection_lookup_failed");
    }

    const auto entries = binding_.build_preview_inline_action_entries(*selected_node);
    auto it = std::find_if(entries.begin(), entries.end(), [&](const PreviewInlineActionAffordanceEntry& entry) {
      return entry.action_id == action_id;
    });
    if (it == entries.end()) {
      return reject_commit("unknown_action_" + action_id);
    }
    if (!it->available || !it->commit_capable) {
      return reject_commit("action_not_commit_capable_" + action_id);
    }

    bool committed = false;
    std::string success_reason = "none";
    if (action_id == "INSERT_LEAF_UNDER_SELECTED") {
      const std::string new_node_id =
        "preview29-inline-leaf-" + std::to_string(++binding_.preview_inline_action_commit_sequence);
      committed = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label,
        binding_.selected_builder_node_id,
        new_node_id);
      if (committed) {
        binding_.recompute_builder_dirty_state(true);
        success_reason = "typed_insert_leaf:" + new_node_id;
      }
    } else if (action_id == "EDIT_TEXT_SELECTED") {
      committed = binding_.apply_inspector_text_edit_command("Preview29 Edited");
      if (committed) {
        success_reason = "inspector_text_edit";
      }
    } else if (action_id == "DELETE_SELECTED") {
      committed = binding_.apply_delete_command_for_current_selection();
      if (committed) {
        success_reason = "delete_selected";
      }
    } else {
      return reject_commit("action_not_supported_" + action_id);
    }

    if (!committed) {
      return reject_commit("command_handler_rejected_" + action_id);
    }

    const bool remap_ok = binding_.remap_selection_or_fail();
    const bool focus_ok = binding_.sync_focus_with_selection_or_fail();
    const bool insp_ok = binding_.refresh_inspector_or_fail();
    const bool prev_ok = binding_.refresh_preview_or_fail();
    const bool sync_ok = binding_.check_cross_surface_sync();
    if (!(remap_ok && focus_ok && insp_ok && prev_ok && sync_ok)) {
      return reject_commit("post_commit_coherence_failed_" + action_id);
    }

    binding_.last_preview_inline_action_commit_status_code = "success";
    binding_.last_preview_inline_action_commit_reason = success_reason;
    binding_.refresh_preview_surface_label();
    return true;
  }

 private:
  static bool is_container_type(ngk::ui::builder::BuilderWidgetType type) {
    using WType = ngk::ui::builder::BuilderWidgetType;
    return type == WType::VerticalLayout || type == WType::HorizontalLayout ||
           type == WType::ScrollContainer || type == WType::ToolbarContainer ||
           type == WType::SidebarContainer || type == WType::ContentPanel ||
           type == WType::StatusBarContainer;
  }

  bool reject_commit(const std::string& reason) const {
    binding_.last_preview_inline_action_commit_status_code = "rejected";
    binding_.last_preview_inline_action_commit_reason = reason.empty() ? std::string("unknown") : reason;
    binding_.refresh_preview_surface_label();
    return false;
  }

  PreviewInlineActionCommitLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_PREVIEW_INLINE_ACTION_COMMIT_LOGIC(logic_object) \
  auto apply_typed_palette_insert = [&](ngk::ui::builder::BuilderWidgetType type, const std::string& under_node_id, const std::string& new_node_id) -> bool { \
    return (logic_object).apply_typed_palette_insert(type, under_node_id, new_node_id); \
  }; \
  apply_preview_inline_action_commit = [&](const std::string& action_id) -> bool { \
    return (logic_object).apply_preview_inline_action_commit(action_id); \
  };
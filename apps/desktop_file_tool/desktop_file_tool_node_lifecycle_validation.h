#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct NodeLifecyclePhase10356Binding {
  BuilderNodeLifecycleIntegrityDiagnostics& node_lifecycle_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  std::string& hover_node_id;
  std::string& drag_source_node_id;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
  bool& drag_active;
  bool& inline_edit_active;
  std::string& inline_edit_node_id;
  std::string& inline_edit_buffer;
  std::string& inline_edit_original_text;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& preview_visual_feedback_node_id;
  std::string& tree_visual_feedback_node_id;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<void()> refresh_tree_surface_label;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<void()> update_add_child_target_display;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, std::vector<PreviewExportParityEntry>&, std::string&, const char*)>
    build_preview_export_parity_entries;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<void()> run_phase103_2;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool()> apply_delete_command_for_current_selection;
  std::function<void(const std::string&,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*)> push_to_history;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::vector<std::string>&, const std::string&)> apply_bulk_move_reparent_selected_nodes_command;
  std::function<bool(const ngk::ui::builder::BuilderDocument&)> document_has_unique_node_ids;
  std::function<bool(const std::string&)> preview_row_visible;
  std::function<bool(const std::string&)> tree_row_visible;
  std::function<std::size_t(const std::string&)> find_visible_preview_row_index;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&, const char*)> build_document_signature;
  std::function<bool()> apply_undo_command;
  std::function<bool(const std::string&)> node_exists;
};

inline bool run_phase103_56_node_lifecycle_phase(NodeLifecyclePhase10356Binding& binding) {
  bool flow_ok = true;
  binding.node_lifecycle_integrity_diag = BuilderNodeLifecycleIntegrityDiagnostics{};

  auto refresh_all_surfaces = [&]() -> bool {
    bool ok = true;
    ok = binding.remap_selection_or_fail() && ok;
    ok = binding.sync_focus_with_selection_or_fail() && ok;
    binding.refresh_tree_surface_label();
    ok = binding.refresh_inspector_or_fail() && ok;
    ok = binding.refresh_preview_or_fail() && ok;
    binding.update_add_child_target_display();
    ok = binding.check_cross_surface_sync() && ok;
    return ok;
  };

  auto preview_matches_structure = [&]() -> bool {
    std::vector<PreviewExportParityEntry> entries{};
    std::string reason;
    if (!binding.build_preview_export_parity_entries(binding.builder_doc, entries, reason, "phase103_56")) {
      return false;
    }

    std::vector<std::pair<std::string, int>> visible_entries{};
    visible_entries.reserve(entries.size());
    for (const auto& entry : entries) {
      if (binding.preview_row_visible(entry.node_id)) {
        visible_entries.emplace_back(entry.node_id, entry.depth);
      }
    }

    if (visible_entries.size() != entries.size()) {
      return false;
    }
    for (std::size_t idx = 0; idx < entries.size(); ++idx) {
      if (visible_entries[idx].first != entries[idx].node_id || visible_entries[idx].second != entries[idx].depth) {
        return false;
      }
    }
    return true;
  };

  auto count_in_parent = [&](const std::string& parent_id, const std::string& child_id) -> std::size_t {
    auto* parent = binding.find_node_by_id(parent_id);
    if (!parent) {
      return 0;
    }
    std::size_t count = 0;
    for (const auto& id : parent->child_ids) {
      if (id == child_id) {
        count += 1;
      }
    }
    return count;
  };

  auto reset_phase = [&]() -> bool {
    binding.run_phase103_2();
    binding.undo_history.clear();
    binding.redo_stack.clear();
    binding.builder_doc_dirty = false;
    binding.hover_node_id.clear();
    binding.drag_source_node_id.clear();
    binding.drag_target_preview_node_id.clear();
    binding.drag_target_preview_is_illegal = false;
    binding.drag_active = false;
    binding.inline_edit_active = false;
    binding.inline_edit_node_id.clear();
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    return refresh_all_surfaces();
  };

  auto apply_recorded_delete = [&](const std::string& history_tag) -> bool {
    const auto before_nodes = binding.builder_doc.nodes;
    const std::string before_root = binding.builder_doc.root_node_id;
    const std::string before_sel = binding.selected_builder_node_id;
    const auto before_multi = binding.multi_selected_node_ids;
    const bool ok = binding.apply_delete_command_for_current_selection();
    if (!ok) {
      return false;
    }
    binding.push_to_history(history_tag,
                            before_nodes,
                            before_root,
                            before_sel,
                            &before_multi,
                            binding.builder_doc.nodes,
                            binding.builder_doc.root_node_id,
                            binding.selected_builder_node_id,
                            &binding.multi_selected_node_ids);
    return true;
  };

  flow_ok = reset_phase() && flow_ok;

  const std::string parent_id = binding.builder_doc.root_node_id;
  const std::string created_id = "phase103_56-created-a";
  const bool created_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Label,
    parent_id,
    created_id);
  flow_ok = created_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  binding.node_lifecycle_integrity_diag.created_node_has_valid_identity =
    created_ok &&
    binding.node_exists(created_id) &&
    count_in_parent(parent_id, created_id) == 1 &&
    binding.document_has_unique_node_ids(binding.builder_doc) &&
    binding.preview_row_visible(created_id) &&
    binding.tree_row_visible(created_id);

  binding.hover_node_id = created_id;
  binding.drag_source_node_id = created_id;
  binding.drag_active = true;
  binding.drag_target_preview_node_id = created_id;
  binding.preview_visual_feedback_node_id = created_id;
  binding.tree_visual_feedback_node_id = created_id;
  binding.inline_edit_active = true;
  binding.inline_edit_node_id = created_id;
  binding.inline_edit_buffer = "phase103_56-inline";
  binding.inline_edit_original_text = "phase103_56-inline";
  binding.selected_builder_node_id = created_id;
  binding.focused_builder_node_id = created_id;
  binding.multi_selected_node_ids = {created_id};
  binding.sync_multi_selection_with_primary();

  const bool delete_created_ok = binding.apply_delete_command_for_current_selection();
  flow_ok = delete_created_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  binding.node_lifecycle_integrity_diag.deleted_node_fully_removed =
    delete_created_ok &&
    !binding.node_exists(created_id) &&
    !binding.preview_row_visible(created_id) &&
    !binding.tree_row_visible(created_id);

  binding.node_lifecycle_integrity_diag.no_stale_references_after_delete =
    binding.hover_node_id.empty() &&
    binding.drag_source_node_id.empty() &&
    binding.drag_target_preview_node_id.empty() &&
    binding.preview_visual_feedback_node_id.empty() &&
    binding.tree_visual_feedback_node_id.empty() &&
    binding.inline_edit_node_id.empty() &&
    !binding.drag_active;

  const std::string container_a = "phase103_56-container-a";
  const std::string container_b = "phase103_56-container-b";
  const std::string moving_child = "phase103_56-moving-child";
  const bool add_container_a_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::VerticalLayout,
    parent_id,
    container_a);
  const bool add_container_b_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::VerticalLayout,
    parent_id,
    container_b);
  const bool add_moving_child_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Label,
    container_a,
    moving_child);
  flow_ok = add_container_a_ok && add_container_b_ok && add_moving_child_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;

  const std::size_t before_move_row_index = binding.find_visible_preview_row_index(moving_child);
  const bool move_ok = binding.apply_bulk_move_reparent_selected_nodes_command({moving_child}, container_b);
  flow_ok = move_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  auto* moved_node = binding.find_node_by_id(moving_child);
  binding.node_lifecycle_integrity_diag.move_reparent_updates_relations_exact =
    move_ok &&
    moved_node != nullptr &&
    moved_node->parent_id == container_b &&
    count_in_parent(container_a, moving_child) == 0 &&
    count_in_parent(container_b, moving_child) == 1;

  const std::size_t moved_row_index = binding.find_visible_preview_row_index(moving_child);
  const bool hit_test_move_ok =
    before_move_row_index != static_cast<std::size_t>(-1) &&
    moved_row_index != static_cast<std::size_t>(-1) &&
    moved_row_index != before_move_row_index;
  binding.node_lifecycle_integrity_diag.preview_mapping_updates_after_lifecycle_change =
    move_ok &&
    binding.preview_row_visible(moving_child) &&
    binding.tree_row_visible(moving_child) &&
    hit_test_move_ok;

  const std::string recreate_id = "phase103_56-recreate-node";
  const bool create_recreate_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Button,
    parent_id,
    recreate_id);
  flow_ok = create_recreate_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  binding.selected_builder_node_id = recreate_id;
  binding.focused_builder_node_id = recreate_id;
  binding.multi_selected_node_ids = {recreate_id};
  binding.sync_multi_selection_with_primary();
  binding.hover_node_id = recreate_id;
  binding.drag_source_node_id = recreate_id;
  binding.drag_target_preview_node_id = recreate_id;
  binding.drag_active = true;
  const bool delete_recreate_ok = binding.apply_delete_command_for_current_selection();
  flow_ok = delete_recreate_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool recreate_again_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Button,
    parent_id,
    recreate_id);
  flow_ok = recreate_again_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool duplicate_while_live_rejected = !binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Button,
    parent_id,
    recreate_id);
  binding.node_lifecycle_integrity_diag.recreated_node_does_not_collide_or_inherit_stale_state =
    create_recreate_ok &&
    delete_recreate_ok &&
    recreate_again_ok &&
    duplicate_while_live_rejected &&
    binding.node_exists(recreate_id) &&
    count_in_parent(parent_id, recreate_id) == 1 &&
    binding.hover_node_id.empty() &&
    binding.drag_source_node_id.empty() &&
    binding.drag_target_preview_node_id.empty() &&
    !binding.drag_active;

  const std::string subtree_parent = "phase103_56-subtree-parent";
  const std::string subtree_child_a = "phase103_56-subtree-child-a";
  const std::string subtree_child_b = "phase103_56-subtree-child-b";
  const bool add_subtree_parent_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::VerticalLayout,
    parent_id,
    subtree_parent);
  const bool add_subtree_child_a_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Label,
    subtree_parent,
    subtree_child_a);
  const bool add_subtree_child_b_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Button,
    subtree_parent,
    subtree_child_b);
  flow_ok = add_subtree_parent_ok && add_subtree_child_a_ok && add_subtree_child_b_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string subtree_before_delete = binding.build_document_signature(binding.builder_doc, "phase103_56_subtree_before_delete");
  binding.selected_builder_node_id = subtree_parent;
  binding.focused_builder_node_id = subtree_parent;
  binding.multi_selected_node_ids = {subtree_parent};
  binding.sync_multi_selection_with_primary();
  const bool subtree_delete_ok = apply_recorded_delete("phase103_56_subtree_delete");
  flow_ok = subtree_delete_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool subtree_removed_ok =
    !binding.node_exists(subtree_parent) &&
    !binding.node_exists(subtree_child_a) &&
    !binding.node_exists(subtree_child_b);
  const bool subtree_undo_ok = binding.apply_undo_command();
  flow_ok = subtree_undo_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string subtree_after_undo = binding.build_document_signature(binding.builder_doc, "phase103_56_subtree_after_undo");
  binding.node_lifecycle_integrity_diag.subtree_delete_and_restore_exact =
    subtree_delete_ok &&
    subtree_removed_ok &&
    subtree_undo_ok &&
    subtree_after_undo == subtree_before_delete;

  binding.node_lifecycle_integrity_diag.selection_focus_drag_states_clean_after_lifecycle_change =
    (binding.selected_builder_node_id.empty() || binding.node_exists(binding.selected_builder_node_id)) &&
    (binding.focused_builder_node_id.empty() || binding.node_exists(binding.focused_builder_node_id)) &&
    (binding.hover_node_id.empty() || binding.node_exists(binding.hover_node_id)) &&
    (binding.drag_source_node_id.empty() || binding.node_exists(binding.drag_source_node_id)) &&
    (binding.drag_target_preview_node_id.empty() || binding.node_exists(binding.drag_target_preview_node_id)) &&
    (binding.inline_edit_node_id.empty() || binding.node_exists(binding.inline_edit_node_id)) &&
    binding.check_cross_surface_sync();

  bool rapid_ok = true;
  for (int i = 0; i < 4; ++i) {
    const std::string rapid_id = "phase103_56-rapid-" + std::to_string(i + 1);
    const bool create_ok = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label,
      parent_id,
      rapid_id);
    rapid_ok = rapid_ok && create_ok;
    flow_ok = create_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    binding.selected_builder_node_id = rapid_id;
    binding.focused_builder_node_id = rapid_id;
    binding.multi_selected_node_ids = {rapid_id};
    binding.sync_multi_selection_with_primary();
    const bool delete_ok = binding.apply_delete_command_for_current_selection();
    rapid_ok = rapid_ok && delete_ok;
    flow_ok = delete_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    rapid_ok = rapid_ok && !binding.node_exists(rapid_id);
  }
  binding.node_lifecycle_integrity_diag.rapid_lifecycle_sequence_stable =
    rapid_ok &&
    binding.document_has_unique_node_ids(binding.builder_doc) &&
    binding.check_cross_surface_sync();

  binding.node_lifecycle_integrity_diag.preview_matches_structure_after_all_lifecycle_ops =
    preview_matches_structure() &&
    binding.check_cross_surface_sync();

  flow_ok = binding.node_lifecycle_integrity_diag.created_node_has_valid_identity && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.deleted_node_fully_removed && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.no_stale_references_after_delete && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.move_reparent_updates_relations_exact && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.preview_mapping_updates_after_lifecycle_change && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.recreated_node_does_not_collide_or_inherit_stale_state && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.subtree_delete_and_restore_exact && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.selection_focus_drag_states_clean_after_lifecycle_change && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.rapid_lifecycle_sequence_stable && flow_ok;
  flow_ok = binding.node_lifecycle_integrity_diag.preview_matches_structure_after_all_lifecycle_ops && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
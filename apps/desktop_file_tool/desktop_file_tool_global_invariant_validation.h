#pragma once

#include <algorithm>
#include <any>
#include <cstddef>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct GlobalInvariantPhase10359Binding {
  BuilderGlobalInvariantEnforcementDiagnostics& global_invariant_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& hover_node_id;
  std::string& drag_source_node_id;
  bool& drag_active;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
  int& global_invariant_checks_total;
  int& global_invariant_failures_total;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<void()> refresh_tree_surface_label;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<void()> update_add_child_target_display;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, std::vector<PreviewExportParityEntry>&, std::string&, const char*)>
    build_preview_export_parity_entries;
  std::function<void()> run_phase103_2;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool(const std::string&)> node_exists;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<std::any()> capture_mutation_checkpoint;
  std::function<void(const std::any&)> restore_mutation_checkpoint;
  std::function<bool(std::string&)> validate_global_document_invariant;
  std::function<bool(const std::any&, const std::string&)> enforce_global_invariant_or_rollback;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::vector<std::pair<std::string, std::string>>&, const std::string&)> apply_inspector_property_edits_command;
  std::function<bool(const std::vector<std::string>&, const std::string&)> apply_bulk_move_reparent_selected_nodes_command;
  std::function<bool()> apply_delete_selected_node_command;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
  std::function<bool()> apply_save_document_command;
  std::function<bool(bool)> apply_load_document_command;
  std::function<bool(const std::vector<CommandHistoryEntry>&)> validate_command_history_snapshot;
  std::function<void(std::vector<std::string>&, std::vector<int>&)> collect_visible_preview_rows;
};

inline bool run_phase103_59_global_invariant_phase(GlobalInvariantPhase10359Binding& binding) {
  bool flow_ok = true;
  binding.global_invariant_diag = BuilderGlobalInvariantEnforcementDiagnostics{};

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
    if (!binding.build_preview_export_parity_entries(binding.builder_doc, entries, reason, "phase103_59")) {
      return false;
    }
    std::vector<std::string> preview_ids{};
    std::vector<int> preview_depths{};
    binding.collect_visible_preview_rows(preview_ids, preview_depths);
    if (preview_ids.size() != entries.size()) {
      return false;
    }
    for (std::size_t idx = 0; idx < entries.size(); ++idx) {
      if (preview_ids[idx] != entries[idx].node_id || preview_depths[idx] != entries[idx].depth) {
        return false;
      }
    }
    return true;
  };

  auto reset_phase = [&]() -> bool {
    binding.run_phase103_2();
    binding.undo_history.clear();
    binding.redo_stack.clear();
    binding.builder_doc_dirty = false;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.hover_node_id.clear();
    binding.drag_source_node_id.clear();
    binding.drag_active = false;
    binding.drag_target_preview_node_id.clear();
    binding.drag_target_preview_is_illegal = false;
    binding.sync_multi_selection_with_primary();
    return refresh_all_surfaces();
  };

  struct DocumentIntegritySummary {
    bool no_orphans = false;
    bool all_node_ids_unique_and_valid = false;
    bool selection_refs_valid = false;
  };

  auto summarize_document_integrity = [&]() -> DocumentIntegritySummary {
    DocumentIntegritySummary out{};
    if (binding.builder_doc.root_node_id.empty() || !binding.node_exists(binding.builder_doc.root_node_id)) {
      return out;
    }

    bool ids_ok = true;
    std::vector<std::string> seen_ids{};
    for (const auto& node : binding.builder_doc.nodes) {
      if (node.node_id.empty()) {
        ids_ok = false;
        break;
      }
      if (std::find(seen_ids.begin(), seen_ids.end(), node.node_id) != seen_ids.end()) {
        ids_ok = false;
        break;
      }
      seen_ids.push_back(node.node_id);

      if (node.node_id != binding.builder_doc.root_node_id) {
        if (node.parent_id.empty() || !binding.node_exists(node.parent_id)) {
          ids_ok = false;
          break;
        }
      }

      for (const auto& child_id : node.child_ids) {
        if (child_id.empty() || !binding.node_exists(child_id)) {
          ids_ok = false;
          break;
        }
        const auto* child = binding.find_node_by_id(child_id);
        if (child == nullptr || child->parent_id != node.node_id) {
          ids_ok = false;
          break;
        }
      }
      if (!ids_ok) {
        break;
      }
    }
    out.all_node_ids_unique_and_valid = ids_ok;

    std::vector<std::string> reachable{};
    std::vector<std::string> stack{};
    stack.push_back(binding.builder_doc.root_node_id);
    while (!stack.empty()) {
      const std::string current = stack.back();
      stack.pop_back();
      if (!binding.node_exists(current)) {
        ids_ok = false;
        break;
      }
      if (std::find(reachable.begin(), reachable.end(), current) != reachable.end()) {
        continue;
      }
      reachable.push_back(current);
      const auto* node = binding.find_node_by_id(current);
      if (node == nullptr) {
        ids_ok = false;
        break;
      }
      for (auto it = node->child_ids.rbegin(); it != node->child_ids.rend(); ++it) {
        if (!it->empty()) {
          stack.push_back(*it);
        }
      }
    }
    out.no_orphans = ids_ok && reachable.size() == binding.builder_doc.nodes.size();

    bool selection_ok = !binding.selected_builder_node_id.empty() && binding.node_exists(binding.selected_builder_node_id);
    if (selection_ok) {
      selection_ok = !binding.multi_selected_node_ids.empty() && binding.multi_selected_node_ids.front() == binding.selected_builder_node_id;
    }
    std::vector<std::string> seen_multi{};
    for (const auto& node_id : binding.multi_selected_node_ids) {
      if (node_id.empty() || !binding.node_exists(node_id) ||
          std::find(seen_multi.begin(), seen_multi.end(), node_id) != seen_multi.end()) {
        selection_ok = false;
        break;
      }
      seen_multi.push_back(node_id);
    }
    out.selection_refs_valid = selection_ok;
    return out;
  };

  flow_ok = reset_phase() && flow_ok;

  const int checks_before = binding.global_invariant_checks_total;
  const int failures_before = binding.global_invariant_failures_total;

  {
    const std::any checkpoint = binding.capture_mutation_checkpoint();
    binding.selected_builder_node_id = "phase103-59-stale-selection";
    std::string reason;
    const bool rejected = !binding.validate_global_document_invariant(reason) && !reason.empty();
    binding.restore_mutation_checkpoint(checkpoint);
    flow_ok = refresh_all_surfaces() && flow_ok;
    binding.global_invariant_diag.global_invariant_detects_invalid_state = rejected;
  }

  binding.selected_builder_node_id = binding.builder_doc.root_node_id;
  binding.focused_builder_node_id = binding.builder_doc.root_node_id;
  binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool insert_container_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::VerticalLayout,
    binding.builder_doc.root_node_id,
    "phase103-59-cont");
  flow_ok = insert_container_ok && flow_ok;

  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool property_edit_ok = binding.apply_inspector_property_edits_command(
    {{"layout.min_width", "180"}},
    "phase103_59_property_edit");
  flow_ok = property_edit_ok && flow_ok;

  const bool move_ok = binding.apply_bulk_move_reparent_selected_nodes_command({"label-001"}, "phase103-59-cont");
  flow_ok = move_ok && flow_ok;

  binding.selected_builder_node_id = "phase103-59-cont";
  binding.focused_builder_node_id = "phase103-59-cont";
  binding.multi_selected_node_ids = {"phase103-59-cont"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool insert_leaf_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Label,
    "phase103-59-cont",
    "phase103-59-temp-leaf");
  flow_ok = insert_leaf_ok && flow_ok;

  binding.selected_builder_node_id = "phase103-59-temp-leaf";
  binding.focused_builder_node_id = "phase103-59-temp-leaf";
  binding.multi_selected_node_ids = {"phase103-59-temp-leaf"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool delete_ok = binding.apply_delete_selected_node_command();
  flow_ok = delete_ok && flow_ok;

  const bool undo_ok = binding.apply_undo_command();
  const bool redo_ok = binding.apply_redo_command();
  flow_ok = undo_ok && redo_ok && flow_ok;

  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool save_ok = binding.apply_save_document_command();
  const bool mutate_before_load_ok = binding.apply_inspector_property_edits_command(
    {{"layout.min_height", "44"}},
    "phase103_59_mutate_before_load");
  const bool load_ok = binding.apply_load_document_command(true);
  flow_ok = save_ok && mutate_before_load_ok && load_ok && flow_ok;

  const int checks_after_mutations = binding.global_invariant_checks_total;
  const int failures_after_mutations = binding.global_invariant_failures_total;
  const int mutation_check_delta = checks_after_mutations - checks_before;
  const int mutation_failure_delta = failures_after_mutations - failures_before;

  binding.global_invariant_diag.all_mutations_checked_by_invariant =
    mutation_check_delta >= 7 && mutation_failure_delta == 0;

  {
    const std::any checkpoint = binding.capture_mutation_checkpoint();
    auto* node = binding.find_node_by_id("label-001");
    const int before_min_width = node ? node->layout.min_width : -1;
    if (node) {
      node->layout.min_width = -999;
    }
    const bool rejected = !binding.enforce_global_invariant_or_rollback(checkpoint, "phase103_59_injected_invalid");
    const auto* restored_node = binding.find_node_by_id("label-001");
    const bool restored = restored_node != nullptr && restored_node->layout.min_width == before_min_width;
    std::string reason;
    const bool invariant_now_valid = binding.validate_global_document_invariant(reason);
    binding.global_invariant_diag.invalid_mutation_rejected_or_rolled_back = rejected && restored && invariant_now_valid;
    flow_ok = refresh_all_surfaces() && flow_ok;
  }

  const auto integrity = summarize_document_integrity();
  binding.global_invariant_diag.no_orphan_nodes_possible = integrity.no_orphans;
  binding.global_invariant_diag.all_node_ids_unique_and_valid = integrity.all_node_ids_unique_and_valid;
  binding.global_invariant_diag.selection_references_valid_nodes_only = integrity.selection_refs_valid;

  std::string invariant_reason;
  const bool invariant_valid_now = binding.validate_global_document_invariant(invariant_reason);
  binding.global_invariant_diag.preview_structure_parity_enforced_by_invariant =
    invariant_valid_now && preview_matches_structure();
  binding.global_invariant_diag.layout_constraints_enforced_by_invariant =
    ngk::ui::builder::validate_builder_document(binding.builder_doc, nullptr) && invariant_valid_now;
  binding.global_invariant_diag.command_history_references_valid_state =
    binding.validate_command_history_snapshot(binding.undo_history) && binding.validate_command_history_snapshot(binding.redo_stack);
  binding.global_invariant_diag.no_false_positive_rejections =
    insert_container_ok && property_edit_ok && move_ok && insert_leaf_ok && delete_ok &&
    undo_ok && redo_ok && save_ok && mutate_before_load_ok && load_ok &&
    mutation_failure_delta == 0;

  flow_ok = binding.global_invariant_diag.global_invariant_detects_invalid_state && flow_ok;
  flow_ok = binding.global_invariant_diag.all_mutations_checked_by_invariant && flow_ok;
  flow_ok = binding.global_invariant_diag.invalid_mutation_rejected_or_rolled_back && flow_ok;
  flow_ok = binding.global_invariant_diag.no_orphan_nodes_possible && flow_ok;
  flow_ok = binding.global_invariant_diag.all_node_ids_unique_and_valid && flow_ok;
  flow_ok = binding.global_invariant_diag.selection_references_valid_nodes_only && flow_ok;
  flow_ok = binding.global_invariant_diag.preview_structure_parity_enforced_by_invariant && flow_ok;
  flow_ok = binding.global_invariant_diag.layout_constraints_enforced_by_invariant && flow_ok;
  flow_ok = binding.global_invariant_diag.command_history_references_valid_state && flow_ok;
  flow_ok = binding.global_invariant_diag.no_false_positive_rejections && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
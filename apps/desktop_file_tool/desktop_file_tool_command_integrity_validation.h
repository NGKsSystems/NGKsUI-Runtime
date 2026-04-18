#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct CommandIntegrityPhase10353Binding {
  BuilderCommandIntegrityDiagnostics& command_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  std::string& preview_visual_feedback_message;
  std::string& preview_visual_feedback_node_id;
  std::string& tree_visual_feedback_node_id;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<void()> refresh_tree_surface_label;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<void()> update_add_child_target_display;
  std::function<bool()> check_cross_surface_sync;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&, const char*)> build_document_signature;
  std::function<std::string(const std::vector<std::string>&)> join_ids;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, std::vector<PreviewExportParityEntry>&, std::string&, const char*)>
    build_preview_export_parity_entries;
  std::function<std::vector<std::pair<std::string, int>>()> collect_visible_preview_entries;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, const std::string&)> node_exists_in_document;
  std::function<const ngk::ui::builder::BuilderNode*(const ngk::ui::builder::BuilderDocument&, const std::string&)>
    find_node_by_id_in_document;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, std::string*)> validate_builder_document;
  std::function<void()> run_phase103_2;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool(const std::string&)> apply_inspector_text_edit_command;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool()> apply_delete_command_for_current_selection;
  std::function<void()> apply_move_sibling_up;
  std::function<void(const std::string&,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*)> push_to_history;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
  std::function<bool(const ngk::ui::builder::BuilderDocument&)> document_has_unique_node_ids;
  std::function<bool(const std::string&)> node_exists;
};

inline bool run_phase103_53_command_integrity_phase(CommandIntegrityPhase10353Binding& binding) {
  bool flow_ok = true;
  binding.command_integrity_diag = BuilderCommandIntegrityDiagnostics{};

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

  auto build_live_state_signature = [&](const char* context_name) -> std::string {
    std::ostringstream oss;
    oss << binding.build_document_signature(binding.builder_doc, context_name) << "\n";
    oss << "selected=" << binding.selected_builder_node_id << "\n";
    oss << "multi=" << binding.join_ids(binding.multi_selected_node_ids) << "\n";
    return oss.str();
  };

  auto preview_matches_structure = [&]() -> bool {
    std::vector<PreviewExportParityEntry> entries{};
    std::string reason;
    if (!binding.build_preview_export_parity_entries(binding.builder_doc, entries, reason, "phase103_53")) {
      return false;
    }

    const auto visible_entries = binding.collect_visible_preview_entries();
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

  auto history_entry_has_valid_references = [&](const CommandHistoryEntry& entry) -> bool {
    auto normalize_selected_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                  const std::string& preferred_selected_id,
                                                  const std::vector<std::string>& preferred_multi_selected_ids,
                                                  const ngk::ui::builder::BuilderDocument* counterpart_doc,
                                                  const std::string& counterpart_selected_id) -> std::string {
      if (!preferred_selected_id.empty() && binding.node_exists_in_document(target_doc, preferred_selected_id)) {
        return preferred_selected_id;
      }
      for (const auto& node_id : preferred_multi_selected_ids) {
        if (!node_id.empty() && binding.node_exists_in_document(target_doc, node_id)) {
          return node_id;
        }
      }
      if (counterpart_doc != nullptr && !counterpart_selected_id.empty()) {
        const auto* counterpart_selected = binding.find_node_by_id_in_document(*counterpart_doc, counterpart_selected_id);
        if (counterpart_selected != nullptr) {
          std::string fallback_parent_id = counterpart_selected->parent_id;
          while (!fallback_parent_id.empty()) {
            if (binding.node_exists_in_document(target_doc, fallback_parent_id)) {
              return fallback_parent_id;
            }
            const auto* fallback_parent = binding.find_node_by_id_in_document(*counterpart_doc, fallback_parent_id);
            if (fallback_parent == nullptr) {
              break;
            }
            fallback_parent_id = fallback_parent->parent_id;
          }
        }
      }
      if (!target_doc.root_node_id.empty() && binding.node_exists_in_document(target_doc, target_doc.root_node_id)) {
        return target_doc.root_node_id;
      }
      return std::string{};
    };

    auto normalize_multi_selection_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                      const std::string& selected_id,
                                                      const std::vector<std::string>& preferred_multi_selected_ids) {
      std::vector<std::string> stable{};
      stable.reserve(preferred_multi_selected_ids.size() + 1);
      auto append_unique_valid = [&](const std::string& node_id) {
        if (node_id.empty() || !binding.node_exists_in_document(target_doc, node_id)) {
          return;
        }
        if (std::find(stable.begin(), stable.end(), node_id) == stable.end()) {
          stable.push_back(node_id);
        }
      };
      append_unique_valid(selected_id);
      for (const auto& node_id : preferred_multi_selected_ids) {
        append_unique_valid(node_id);
      }
      return stable;
    };

    CommandHistoryEntry normalized = entry;
    ngk::ui::builder::BuilderDocument before_doc{};
    before_doc.root_node_id = normalized.before_root_node_id;
    before_doc.nodes = normalized.before_nodes;
    ngk::ui::builder::BuilderDocument after_doc{};
    after_doc.root_node_id = normalized.after_root_node_id;
    after_doc.nodes = normalized.after_nodes;

    std::string before_error;
    std::string after_error;
    if (!binding.validate_builder_document(before_doc, &before_error) ||
        !binding.validate_builder_document(after_doc, &after_error)) {
      return false;
    }

    normalized.before_selected_id = normalize_selected_id_for_snapshot(
      before_doc,
      normalized.before_selected_id,
      normalized.before_multi_selected_ids,
      &after_doc,
      normalized.after_selected_id);
    normalized.before_multi_selected_ids = normalize_multi_selection_for_snapshot(
      before_doc,
      normalized.before_selected_id,
      normalized.before_multi_selected_ids);
    normalized.after_selected_id = normalize_selected_id_for_snapshot(
      after_doc,
      normalized.after_selected_id,
      normalized.after_multi_selected_ids,
      &before_doc,
      normalized.before_selected_id);
    normalized.after_multi_selected_ids = normalize_multi_selection_for_snapshot(
      after_doc,
      normalized.after_selected_id,
      normalized.after_multi_selected_ids);

    return normalized.before_selected_id == entry.before_selected_id &&
           normalized.before_multi_selected_ids == entry.before_multi_selected_ids &&
           normalized.after_selected_id == entry.after_selected_id &&
           normalized.after_multi_selected_ids == entry.after_multi_selected_ids;
  };

  auto history_stacks_valid = [&]() -> bool {
    for (const auto& entry : binding.undo_history) {
      if (!history_entry_has_valid_references(entry)) {
        return false;
      }
    }
    for (const auto& entry : binding.redo_stack) {
      if (!history_entry_has_valid_references(entry)) {
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
    binding.preview_visual_feedback_message.clear();
    binding.preview_visual_feedback_node_id.clear();
    binding.tree_visual_feedback_node_id.clear();
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

  auto apply_recorded_move_up = [&](const std::string& history_tag) -> bool {
    const std::string before_signature = binding.build_document_signature(binding.builder_doc, "phase103_53_move_before");
    const auto before_nodes = binding.builder_doc.nodes;
    const std::string before_root = binding.builder_doc.root_node_id;
    const std::string before_sel = binding.selected_builder_node_id;
    const auto before_multi = binding.multi_selected_node_ids;
    binding.apply_move_sibling_up();
    const std::string after_signature = binding.build_document_signature(binding.builder_doc, "phase103_53_move_after");
    if (before_signature == after_signature) {
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

  bool preview_parity_ok = true;
  bool stack_integrity_ok = true;

  flow_ok = reset_phase() && flow_ok;
  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string edit_before_state = build_live_state_signature("phase103_53_edit_before");
  const bool edit_ok = binding.apply_inspector_text_edit_command("phase103_53_label_edited");
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string edit_after_state = build_live_state_signature("phase103_53_edit_after");
  const bool edit_undo_ok = edit_ok && binding.apply_undo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool edit_undo_exact = edit_undo_ok && build_live_state_signature("phase103_53_edit_undo") == edit_before_state;
  const bool edit_redo_ok = edit_undo_ok && binding.apply_redo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool edit_redo_exact = edit_redo_ok && build_live_state_signature("phase103_53_edit_redo") == edit_after_state;
  preview_parity_ok = preview_parity_ok && preview_matches_structure();
  stack_integrity_ok = stack_integrity_ok && history_stacks_valid();

  flow_ok = reset_phase() && flow_ok;
  const bool move_setup_a = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Label, binding.builder_doc.root_node_id, "phase103_53-move-a");
  const bool move_setup_b = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Button, binding.builder_doc.root_node_id, "phase103_53-move-b");
  flow_ok = move_setup_a && move_setup_b && flow_ok;
  binding.undo_history.clear();
  binding.redo_stack.clear();
  binding.selected_builder_node_id = "phase103_53-move-b";
  binding.focused_builder_node_id = "phase103_53-move-b";
  binding.multi_selected_node_ids = {"phase103_53-move-b"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string move_before_state = build_live_state_signature("phase103_53_move_before");
  const bool move_ok = apply_recorded_move_up("phase103_53_move");
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string move_after_state = build_live_state_signature("phase103_53_move_after");
  const bool move_undo_ok = move_ok && binding.apply_undo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool move_undo_exact = move_undo_ok && build_live_state_signature("phase103_53_move_undo") == move_before_state;
  const bool move_redo_ok = move_undo_ok && binding.apply_redo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool move_redo_exact = move_redo_ok && build_live_state_signature("phase103_53_move_redo") == move_after_state;
  preview_parity_ok = preview_parity_ok && preview_matches_structure();
  stack_integrity_ok = stack_integrity_ok && history_stacks_valid();

  flow_ok = reset_phase() && flow_ok;
  const std::string root_id = binding.builder_doc.root_node_id;
  const bool seq_add_1_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Label, root_id, "phase103_53-seq-a");
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string seq_state_after_add_1 = build_live_state_signature("phase103_53_seq_after_add_1");
  const bool seq_add_2_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Button, root_id, "phase103_53-seq-b");
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string seq_state_after_add_2 = build_live_state_signature("phase103_53_seq_after_add_2");
  const std::size_t seq_node_count_after_add_2 = binding.builder_doc.nodes.size();
  const std::string deleted_node_id = binding.selected_builder_node_id;
  const auto* deleted_before = binding.find_node_by_id_in_document(binding.builder_doc, deleted_node_id);
  const std::string deleted_parent_id = deleted_before ? deleted_before->parent_id : root_id;
  const bool seq_delete_ok = apply_recorded_delete("phase103_53_delete");
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string seq_state_after_delete = build_live_state_signature("phase103_53_seq_after_delete");
  const bool fallback_ok = seq_delete_ok &&
    (binding.selected_builder_node_id == deleted_parent_id || binding.selected_builder_node_id == root_id) &&
    binding.node_exists(binding.selected_builder_node_id);

  const bool seq_undo_delete_ok = seq_delete_ok && binding.apply_undo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string seq_state_after_undo_delete = build_live_state_signature("phase103_53_seq_after_undo_delete");
  const bool seq_undo_delete_exact = seq_undo_delete_ok && seq_state_after_undo_delete == seq_state_after_add_2;
  const bool seq_undo_delete_selection = seq_undo_delete_ok &&
    binding.selected_builder_node_id == deleted_node_id &&
    binding.multi_selected_node_ids.size() == 1 &&
    binding.multi_selected_node_ids.front() == deleted_node_id;
  const bool no_missing_after_undo =
    seq_undo_delete_ok &&
    binding.node_exists(deleted_node_id) &&
    binding.builder_doc.nodes.size() == seq_node_count_after_add_2;

  const bool seq_undo_add_2_ok = seq_undo_delete_ok && binding.apply_undo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool seq_undo_add_2_exact = seq_undo_add_2_ok &&
    build_live_state_signature("phase103_53_seq_after_undo_add_2") == seq_state_after_add_1;

  const bool seq_redo_add_2_ok = seq_undo_add_2_ok && binding.apply_redo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const bool seq_redo_add_2_exact = seq_redo_add_2_ok &&
    build_live_state_signature("phase103_53_seq_after_redo_add_2") == seq_state_after_add_2;

  const bool seq_redo_delete_ok = seq_redo_add_2_ok && binding.apply_redo_command();
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string seq_state_after_redo_delete = build_live_state_signature("phase103_53_seq_after_redo_delete");
  const bool seq_redo_delete_exact = seq_redo_delete_ok && seq_state_after_redo_delete == seq_state_after_delete;
  const bool no_duplicate_on_redo =
    seq_redo_delete_ok &&
    binding.document_has_unique_node_ids(binding.builder_doc) &&
    !binding.node_exists(deleted_node_id);

  preview_parity_ok = preview_parity_ok && preview_matches_structure();
  stack_integrity_ok = stack_integrity_ok && history_stacks_valid();

  binding.command_integrity_diag.undo_restores_exact_structure =
    edit_undo_exact && move_undo_exact && seq_undo_delete_exact;
  binding.command_integrity_diag.undo_restores_selection =
    edit_undo_exact && move_undo_exact && seq_undo_delete_selection;
  binding.command_integrity_diag.redo_reapplies_exact_state =
    edit_redo_exact && move_redo_exact && seq_redo_delete_exact;
  binding.command_integrity_diag.no_duplicate_nodes_on_redo = no_duplicate_on_redo;
  binding.command_integrity_diag.no_missing_nodes_after_undo = no_missing_after_undo;
  binding.command_integrity_diag.command_stack_no_invalid_references = stack_integrity_ok;
  binding.command_integrity_diag.selection_fallback_deterministic = fallback_ok;
  binding.command_integrity_diag.multi_step_sequence_stable =
    seq_add_1_ok &&
    seq_add_2_ok &&
    seq_delete_ok &&
    seq_undo_delete_exact &&
    seq_undo_add_2_exact &&
    seq_redo_add_2_exact &&
    seq_redo_delete_exact &&
    binding.undo_history.size() == 3 &&
    binding.redo_stack.empty();
  binding.command_integrity_diag.no_side_effect_mutations =
    seq_undo_delete_exact &&
    seq_undo_add_2_exact &&
    seq_redo_add_2_exact &&
    seq_redo_delete_exact;
  binding.command_integrity_diag.preview_matches_structure_after_undo_redo = preview_parity_ok;

  flow_ok = binding.command_integrity_diag.undo_restores_exact_structure && flow_ok;
  flow_ok = binding.command_integrity_diag.undo_restores_selection && flow_ok;
  flow_ok = binding.command_integrity_diag.redo_reapplies_exact_state && flow_ok;
  flow_ok = binding.command_integrity_diag.no_duplicate_nodes_on_redo && flow_ok;
  flow_ok = binding.command_integrity_diag.no_missing_nodes_after_undo && flow_ok;
  flow_ok = binding.command_integrity_diag.command_stack_no_invalid_references && flow_ok;
  flow_ok = binding.command_integrity_diag.selection_fallback_deterministic && flow_ok;
  flow_ok = binding.command_integrity_diag.multi_step_sequence_stable && flow_ok;
  flow_ok = binding.command_integrity_diag.no_side_effect_mutations && flow_ok;
  flow_ok = binding.command_integrity_diag.preview_matches_structure_after_undo_redo && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
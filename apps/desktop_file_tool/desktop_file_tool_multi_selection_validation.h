#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct MultiSelectionPhase10364Binding {
  BuilderMultiSelectionIntegrityHardeningDiagnostics& multi_selection_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& builder_doc_save_path;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(const std::string&)> node_exists;
  std::function<void()> run_phase103_2;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, std::vector<PreviewExportParityEntry>&, std::string&, const char*)>
    build_preview_export_parity_entries;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::vector<std::string>&, const std::string&)> apply_bulk_text_suffix_selected_nodes_command;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<void(const std::string&,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*)> push_to_history;
  std::function<bool(const std::vector<std::string>&, const std::string&)> apply_bulk_move_reparent_selected_nodes_command;
  std::function<bool()> apply_delete_command_for_current_selection;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
  std::function<bool(const std::string&)> save_builder_document_to_path;
  std::function<bool(const std::string&)> load_builder_document_from_path;
};

inline bool run_phase103_64_multi_selection_phase(MultiSelectionPhase10364Binding& binding) {
  bool flow_ok = true;
  binding.multi_selection_integrity_diag = BuilderMultiSelectionIntegrityHardeningDiagnostics{};

  auto refresh_all_surfaces = [&]() -> bool {
    bool ok = true;
    ok = binding.remap_selection_or_fail() && ok;
    ok = binding.sync_focus_with_selection_or_fail() && ok;
    ok = binding.refresh_inspector_or_fail() && ok;
    ok = binding.refresh_preview_or_fail() && ok;
    ok = binding.check_cross_surface_sync() && ok;
    return ok;
  };

  auto selection_set_valid = [&]() -> bool {
    for (const auto& node_id : binding.multi_selected_node_ids) {
      if (node_id.empty() || !binding.node_exists(node_id)) {
        return false;
      }
    }
    return true;
  };

  auto has_duplicate_selection_ids = [&]() -> bool {
    std::vector<std::string> seen{};
    for (const auto& node_id : binding.multi_selected_node_ids) {
      if (std::find(seen.begin(), seen.end(), node_id) != seen.end()) {
        return true;
      }
      seen.push_back(node_id);
    }
    return false;
  };

  auto reset_phase = [&]() -> bool {
    binding.run_phase103_2();
    binding.undo_history.clear();
    binding.redo_stack.clear();
    binding.builder_doc_dirty = false;
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.sync_multi_selection_with_primary();
    return refresh_all_surfaces();
  };

  auto build_structure_signature = [&](const char* context_name) -> std::string {
    std::vector<PreviewExportParityEntry> entries{};
    std::string reason;
    if (!binding.build_preview_export_parity_entries(binding.builder_doc, entries, reason, context_name)) {
      return std::string("invalid:") + reason;
    }
    std::ostringstream oss;
    oss << "root=" << binding.builder_doc.root_node_id << "\n";
    for (const auto& entry : entries) {
      oss << entry.depth << "|" << entry.node_id << "|" << entry.widget_type << "|" << entry.text << "|";
      for (std::size_t idx = 0; idx < entry.child_ids.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << entry.child_ids[idx];
      }
      oss << "\n";
    }
    return oss.str();
  };

  flow_ok = reset_phase() && flow_ok;

  {
    binding.multi_selected_node_ids = {"label-001", "label-001", "phase103_64_stale_id"};
    binding.sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    binding.multi_selection_integrity_diag.selection_set_contains_only_valid_nodes = selection_set_valid();
    binding.multi_selection_integrity_diag.no_duplicate_ids_in_selection = !has_duplicate_selection_ids();
    binding.multi_selection_integrity_diag.primary_and_multi_selection_consistent =
      !binding.selected_builder_node_id.empty() &&
      !binding.multi_selected_node_ids.empty() &&
      binding.multi_selected_node_ids.front() == binding.selected_builder_node_id;

    flow_ok = binding.multi_selection_integrity_diag.selection_set_contains_only_valid_nodes && flow_ok;
    flow_ok = binding.multi_selection_integrity_diag.no_duplicate_ids_in_selection && flow_ok;
    flow_ok = binding.multi_selection_integrity_diag.primary_and_multi_selection_consistent && flow_ok;
  }

  const bool ins64_a = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-label-a");
  const bool ins64_b = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-label-b");
  const bool ins64_c = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-label-c");
  const bool ins64_target = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p64-target");
  flow_ok = ins64_a && ins64_b && ins64_c && ins64_target && flow_ok;
  binding.selected_builder_node_id = "p64-label-a";
  binding.multi_selected_node_ids = {"p64-label-a", "p64-label-b", "p64-label-c"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    const bool edit_ok = binding.apply_bulk_text_suffix_selected_nodes_command(binding.multi_selected_node_ids, "_P64");
    const auto* a = binding.find_node_by_id("p64-label-a");
    const auto* b = binding.find_node_by_id("p64-label-b");
    const auto* c = binding.find_node_by_id("p64-label-c");
    binding.multi_selection_integrity_diag.multi_operations_apply_to_all_selected_nodes =
      edit_ok &&
      a != nullptr && b != nullptr && c != nullptr &&
      a->text.size() >= 4 && a->text.substr(a->text.size() - 4) == "_P64" &&
      b->text.size() >= 4 && b->text.substr(b->text.size() - 4) == "_P64" &&
      c->text.size() >= 4 && c->text.substr(c->text.size() - 4) == "_P64";
    flow_ok = binding.multi_selection_integrity_diag.multi_operations_apply_to_all_selected_nodes && flow_ok;
  }

  {
    const bool add_button = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Button, "root-001", "p64-button-mixed");
    flow_ok = add_button && flow_ok;
    const std::size_t hist_before = binding.undo_history.size();
    const std::string sig_before_reject = build_structure_signature("phase103_64_reject_before");
    binding.selected_builder_node_id = "p64-label-a";
    binding.multi_selected_node_ids = {"p64-label-a", "p64-button-mixed"};
    binding.sync_multi_selection_with_primary();
    const bool mixed_rejected = !binding.apply_bulk_text_suffix_selected_nodes_command(binding.multi_selected_node_ids, "_MIX");
    const std::string sig_after_reject = build_structure_signature("phase103_64_reject_after");

    binding.selected_builder_node_id = "p64-label-a";
    binding.multi_selected_node_ids = {"p64-label-a", "p64-label-b"};
    binding.sync_multi_selection_with_primary();
    const auto before_nodes = binding.builder_doc.nodes;
    const std::string before_root = binding.builder_doc.root_node_id;
    const std::string before_sel = binding.selected_builder_node_id;
    const auto before_multi = binding.multi_selected_node_ids;
    const bool committed_ok = binding.apply_bulk_text_suffix_selected_nodes_command(binding.multi_selected_node_ids, "_OK");
    if (committed_ok) {
      binding.push_to_history("phase103_64_bulk_property_edit",
                              before_nodes,
                              before_root,
                              before_sel,
                              &before_multi,
                              binding.builder_doc.nodes,
                              binding.builder_doc.root_node_id,
                              binding.selected_builder_node_id,
                              &binding.multi_selected_node_ids);
    }
    const bool single_command_backed = committed_ok && (binding.undo_history.size() == hist_before + 1) &&
                                       !binding.undo_history.empty() &&
                                       binding.undo_history.back().command_type == "phase103_64_bulk_property_edit";

    binding.multi_selection_integrity_diag.multi_operations_atomic_and_command_backed =
      mixed_rejected && (sig_before_reject == sig_after_reject) && single_command_backed;
    flow_ok = binding.multi_selection_integrity_diag.multi_operations_atomic_and_command_backed && flow_ok;
  }

  {
    binding.selected_builder_node_id = "p64-label-a";
    binding.multi_selected_node_ids = {"p64-label-a", "p64-label-b"};
    binding.sync_multi_selection_with_primary();
    const bool move_ok = binding.apply_bulk_move_reparent_selected_nodes_command(binding.multi_selected_node_ids, "p64-target");
    const auto* la = binding.find_node_by_id("p64-label-a");
    const auto* lb = binding.find_node_by_id("p64-label-b");
    const bool moved = move_ok && la != nullptr && lb != nullptr &&
      la->parent_id == "p64-target" && lb->parent_id == "p64-target";

    binding.selected_builder_node_id = "p64-label-a";
    binding.multi_selected_node_ids = {"p64-label-a", "p64-label-b"};
    binding.sync_multi_selection_with_primary();
    const bool delete_ok = binding.apply_delete_command_for_current_selection();
    const bool deleted = delete_ok && !binding.node_exists("p64-label-a") && !binding.node_exists("p64-label-b");
    const bool selection_clean =
      (binding.selected_builder_node_id.empty() && binding.multi_selected_node_ids.empty()) ||
      (!binding.selected_builder_node_id.empty() && binding.node_exists(binding.selected_builder_node_id) &&
       binding.multi_selected_node_ids.size() == 1 && binding.multi_selected_node_ids.front() == binding.selected_builder_node_id);

    binding.multi_selection_integrity_diag.delete_move_reparent_clean_selection_state =
      moved && deleted && selection_clean;
    flow_ok = binding.multi_selection_integrity_diag.delete_move_reparent_clean_selection_state && flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const bool ua = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-undo-a");
    const bool ub = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-undo-b");
    flow_ok = ua && ub && flow_ok;
    binding.selected_builder_node_id = "p64-undo-a";
    binding.multi_selected_node_ids = {"p64-undo-a", "p64-undo-b"};
    binding.sync_multi_selection_with_primary();

    const auto before_nodes = binding.builder_doc.nodes;
    const std::string before_root = binding.builder_doc.root_node_id;
    const std::string before_sel = binding.selected_builder_node_id;
    const auto before_multi = binding.multi_selected_node_ids;
    const bool delete_ok = binding.apply_delete_command_for_current_selection();
    flow_ok = delete_ok && flow_ok;
    const std::string redo_sel = binding.selected_builder_node_id;
    const auto redo_multi = binding.multi_selected_node_ids;
    if (delete_ok) {
      binding.push_to_history("phase103_64_bulk_delete",
                              before_nodes,
                              before_root,
                              before_sel,
                              &before_multi,
                              binding.builder_doc.nodes,
                              binding.builder_doc.root_node_id,
                              binding.selected_builder_node_id,
                              &binding.multi_selected_node_ids);
    }

    const bool undo_ok = binding.apply_undo_command();
    const bool undo_exact = undo_ok && binding.node_exists("p64-undo-a") && binding.node_exists("p64-undo-b") &&
      binding.selected_builder_node_id == "p64-undo-a" &&
      binding.multi_selected_node_ids.size() == 2 &&
      binding.multi_selected_node_ids[0] == "p64-undo-a" &&
      binding.multi_selected_node_ids[1] == "p64-undo-b";
    const bool redo_ok = binding.apply_redo_command();
    const bool redo_exact = redo_ok && !binding.node_exists("p64-undo-a") && !binding.node_exists("p64-undo-b") &&
      binding.selected_builder_node_id == redo_sel && binding.multi_selected_node_ids == redo_multi;

    binding.multi_selection_integrity_diag.undo_redo_restore_full_selection_state = undo_exact && redo_exact;
    flow_ok = binding.multi_selection_integrity_diag.undo_redo_restore_full_selection_state && flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const bool sa = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-stale-a");
    flow_ok = sa && flow_ok;
    binding.selected_builder_node_id = "p64-stale-a";
    binding.multi_selected_node_ids = {"p64-stale-a", "p64-stale-missing"};
    binding.sync_multi_selection_with_primary();
    const bool stale_removed_after_sync =
      std::find(binding.multi_selected_node_ids.begin(), binding.multi_selected_node_ids.end(), "p64-stale-missing") ==
      binding.multi_selected_node_ids.end();

    const bool saved = binding.save_builder_document_to_path(binding.builder_doc_save_path);
    const bool loaded = saved && binding.load_builder_document_from_path(binding.builder_doc_save_path);
    const bool lifecycle_selection_valid = loaded &&
      ((binding.selected_builder_node_id.empty() && binding.multi_selected_node_ids.empty()) ||
       (!binding.selected_builder_node_id.empty() && binding.node_exists(binding.selected_builder_node_id) &&
        !binding.multi_selected_node_ids.empty() && binding.multi_selected_node_ids.front() == binding.selected_builder_node_id));

    binding.multi_selection_integrity_diag.no_stale_ids_after_lifecycle_events =
      stale_removed_after_sync && lifecycle_selection_valid;
    flow_ok = binding.multi_selection_integrity_diag.no_stale_ids_after_lifecycle_events && flow_ok;
  }

  {
    auto run_order_case = [&]() -> std::string {
      binding.run_phase103_2();
      binding.undo_history.clear();
      binding.redo_stack.clear();
      const bool i1 = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-order-a");
      const bool i2 = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-order-b");
      const bool i3 = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-order-c");
      const bool it = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p64-order-target");
      if (!(i1 && i2 && i3 && it)) {
        return std::string("invalid:setup");
      }
      const bool mv = binding.apply_bulk_move_reparent_selected_nodes_command(
        {"p64-order-c", "p64-order-a", "p64-order-b"}, "p64-order-target");
      if (!mv) {
        return std::string("invalid:move");
      }
      return build_structure_signature("phase103_64_order");
    };

    const std::string sig1 = run_order_case();
    const std::string sig2 = run_order_case();
    binding.multi_selection_integrity_diag.multi_operation_order_deterministic =
      !sig1.empty() && !sig2.empty() && sig1 == sig2;
    flow_ok = binding.multi_selection_integrity_diag.multi_operation_order_deterministic && flow_ok;
  }

  {
    binding.run_phase103_2();
    binding.undo_history.clear();
    binding.redo_stack.clear();
    const bool ins_a = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-cross-a");
    const bool ins_b = binding.apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p64-cross-b");
    flow_ok = ins_a && ins_b && flow_ok;
    const auto* untouched_before = binding.find_node_by_id("label-001");
    const std::string untouched_text_before = untouched_before ? untouched_before->text : std::string{};

    binding.selected_builder_node_id = "p64-cross-a";
    binding.multi_selected_node_ids = {"p64-cross-a", "p64-cross-b"};
    binding.sync_multi_selection_with_primary();
    const bool op_ok = binding.apply_bulk_text_suffix_selected_nodes_command(binding.multi_selected_node_ids, "_CROSS");
    flow_ok = op_ok && flow_ok;
    flow_ok = binding.remap_selection_or_fail() && flow_ok;
    flow_ok = binding.sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = binding.refresh_inspector_or_fail() && flow_ok;
    flow_ok = binding.refresh_preview_or_fail() && flow_ok;

    const auto* untouched_after = binding.find_node_by_id("label-001");
    const auto* cross_a = binding.find_node_by_id("p64-cross-a");
    const auto* cross_b = binding.find_node_by_id("p64-cross-b");
    const bool sync_ok = binding.check_cross_surface_sync();
    binding.multi_selection_integrity_diag.no_cross_node_state_corruption =
      op_ok &&
      cross_a != nullptr && cross_b != nullptr &&
      cross_a->text.size() >= 6 && cross_a->text.substr(cross_a->text.size() - 6) == "_CROSS" &&
      cross_b->text.size() >= 6 && cross_b->text.substr(cross_b->text.size() - 6) == "_CROSS" &&
      untouched_after != nullptr && untouched_after->text == untouched_text_before &&
      selection_set_valid() && !has_duplicate_selection_ids() && sync_ok;
    flow_ok = binding.multi_selection_integrity_diag.no_cross_node_state_corruption && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
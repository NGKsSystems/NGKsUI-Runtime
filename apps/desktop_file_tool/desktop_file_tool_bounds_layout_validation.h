#pragma once

#include <algorithm>
#include <cstddef>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct BoundsLayoutPhase10357Binding {
  BuilderBoundsLayoutConstraintIntegrityDiagnostics& bounds_layout_constraint_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  const std::filesystem::path& builder_doc_save_path;
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
  std::function<std::string(const ngk::ui::builder::BuilderDocument&, const char*)> build_document_signature;
  std::function<bool(const std::vector<std::pair<std::string, std::string>>&, const std::string&)> apply_inspector_property_edits_command;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::vector<std::string>&, const std::string&)> apply_bulk_move_reparent_selected_nodes_command;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
  std::function<bool(const std::filesystem::path&, const std::string&)> write_text_file;
  std::function<bool(const std::string&)> load_builder_document_from_path;
  std::function<bool()> apply_save_document_command;
  std::function<bool(bool)> apply_load_document_command;
  std::function<bool(const std::string&)> node_exists;
  std::function<void(std::vector<std::string>&, std::vector<int>&)> collect_visible_preview_rows;
};

inline bool run_phase103_57_bounds_layout_phase(BoundsLayoutPhase10357Binding& binding) {
  bool flow_ok = true;
  binding.bounds_layout_constraint_diag = BuilderBoundsLayoutConstraintIntegrityDiagnostics{};

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
    if (!binding.build_preview_export_parity_entries(binding.builder_doc, entries, reason, "phase103_57")) {
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
    binding.sync_multi_selection_with_primary();
    return refresh_all_surfaces();
  };

  flow_ok = reset_phase() && flow_ok;

  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const std::string sig_before_neg = binding.build_document_signature(binding.builder_doc, "phase103_57_before_neg");
  const std::size_t history_before_neg = binding.undo_history.size();
  const bool neg_width_rejected = !binding.apply_inspector_property_edits_command(
    {{"layout.min_width", "-10"}}, "phase103_57_neg_width");
  const bool neg_height_rejected = !binding.apply_inspector_property_edits_command(
    {{"layout.min_height", "-5"}}, "phase103_57_neg_height");
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string sig_after_neg = binding.build_document_signature(binding.builder_doc, "phase103_57_after_neg");

  binding.bounds_layout_constraint_diag.negative_dimensions_rejected =
    neg_width_rejected &&
    neg_height_rejected &&
    history_before_neg == binding.undo_history.size() &&
    sig_before_neg == sig_after_neg;

  const std::string sig_before_weight = binding.build_document_signature(binding.builder_doc, "phase103_57_before_weight");
  const std::size_t history_before_weight = binding.undo_history.size();
  const bool zero_weight_rejected = !binding.apply_inspector_property_edits_command(
    {{"layout.weight", "0"}}, "phase103_57_zero_weight");
  const bool neg_preferred_rejected = !binding.apply_inspector_property_edits_command(
    {{"layout.preferred_width", "-8"}}, "phase103_57_neg_preferred");
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string sig_after_weight = binding.build_document_signature(binding.builder_doc, "phase103_57_after_weight");

  binding.bounds_layout_constraint_diag.invalid_child_parent_geometry_rejected =
    zero_weight_rejected &&
    neg_preferred_rejected &&
    history_before_weight == binding.undo_history.size() &&
    sig_before_weight == sig_after_weight;

  binding.selected_builder_node_id = binding.builder_doc.root_node_id;
  binding.focused_builder_node_id = binding.builder_doc.root_node_id;
  binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool insert_container_ok = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::VerticalLayout,
    binding.builder_doc.root_node_id,
    "phase103-57-cont");
  flow_ok = insert_container_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;

  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool move_ok = insert_container_ok &&
    binding.apply_bulk_move_reparent_selected_nodes_command({"label-001"}, "phase103-57-cont");
  flow_ok = move_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;

  std::string validation_err_after_move;
  binding.bounds_layout_constraint_diag.move_reparent_respects_layout_constraints =
    move_ok &&
    ngk::ui::builder::validate_builder_document(binding.builder_doc, &validation_err_after_move) &&
    preview_matches_structure() &&
    binding.check_cross_surface_sync();

  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const std::size_t history_before_compound_reject = binding.undo_history.size();
  const bool compound_reject_ok = !binding.apply_inspector_property_edits_command(
    {{"layout.min_width", "-1"}, {"layout.min_height", "-2"}},
    "phase103_57_compound_reject");
  const std::size_t history_after_compound_reject = binding.undo_history.size();
  flow_ok = refresh_all_surfaces() && flow_ok;

  binding.bounds_layout_constraint_diag.invalid_layout_not_committed_to_history =
    compound_reject_ok &&
    history_before_compound_reject == history_after_compound_reject;

  binding.bounds_layout_constraint_diag.preview_never_reflects_invalid_document_state =
    preview_matches_structure() &&
    ngk::ui::builder::validate_builder_document(binding.builder_doc, nullptr) &&
    binding.check_cross_surface_sync();

  const std::string before_layout_edit_sig = binding.build_document_signature(binding.builder_doc, "phase103_57_before_layout_edit");
  const bool valid_layout_edit_ok = binding.apply_inspector_property_edits_command(
    {{"layout.min_width", "160"}, {"layout.min_height", "40"}},
    "phase103_57_valid_layout_edit");
  flow_ok = valid_layout_edit_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string after_layout_edit_sig = binding.build_document_signature(binding.builder_doc, "phase103_57_after_layout_edit");

  const auto* node_after_edit = binding.find_node_by_id("label-001");
  const bool edit_values_correct =
    node_after_edit != nullptr &&
    node_after_edit->layout.min_width == 160 &&
    node_after_edit->layout.min_height == 40;

  const bool undo_layout_ok = binding.apply_undo_command();
  flow_ok = undo_layout_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string after_undo_sig = binding.build_document_signature(binding.builder_doc, "phase103_57_after_undo");

  const bool redo_layout_ok = binding.apply_redo_command();
  flow_ok = redo_layout_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;
  const std::string after_redo_sig = binding.build_document_signature(binding.builder_doc, "phase103_57_after_redo");

  binding.bounds_layout_constraint_diag.undo_redo_restore_valid_layout_exact =
    valid_layout_edit_ok &&
    edit_values_correct &&
    undo_layout_ok && redo_layout_ok &&
    after_undo_sig == before_layout_edit_sig &&
    after_redo_sig == after_layout_edit_sig;

  const std::filesystem::path invalid_payload_path =
    binding.builder_doc_save_path.parent_path() / "phase103_57_invalid_layout_payload.ngkb";
  const std::string valid_serial = ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
  bool invalid_rejected = false;
  if (!valid_serial.empty()) {
    std::string corrupted = valid_serial;
    const std::string search_tok = "layout.min_width=";
    const std::size_t tok_pos = corrupted.find(search_tok);
    if (tok_pos != std::string::npos) {
      const std::size_t value_start = tok_pos + search_tok.size();
      const std::size_t value_end = corrupted.find('\n', value_start);
      if (value_end != std::string::npos) {
        corrupted.replace(value_start, value_end - value_start, "-99");
        const std::string sig_before_bad_load = binding.build_document_signature(binding.builder_doc, "phase103_57_before_bad_load");
        if (binding.write_text_file(invalid_payload_path, corrupted)) {
          const bool load_returned_false = !binding.load_builder_document_from_path(invalid_payload_path.string());
          const std::string sig_after_bad_load = binding.build_document_signature(binding.builder_doc, "phase103_57_after_bad_load");
          invalid_rejected = load_returned_false &&
            ngk::ui::builder::validate_builder_document(binding.builder_doc, nullptr) &&
            sig_before_bad_load == sig_after_bad_load;
        }
      }
    }
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  binding.bounds_layout_constraint_diag.save_load_rejects_constraint_violating_payload = invalid_rejected;

  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const std::string sig_before_save = binding.build_document_signature(binding.builder_doc, "phase103_57_before_save");
  const bool save_ok = binding.apply_save_document_command();
  flow_ok = save_ok && flow_ok;

  const bool mutate_ok = binding.apply_inspector_property_edits_command(
    {{"layout.min_width", "999"}},
    "phase103_57_mutate_before_load");
  flow_ok = mutate_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;

  const bool load_ok = binding.apply_load_document_command(true);
  flow_ok = load_ok && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;

  const std::string sig_after_roundtrip = binding.build_document_signature(binding.builder_doc, "phase103_57_after_roundtrip");
  const auto* roundtrip_node = binding.find_node_by_id("label-001");
  const bool roundtrip_layout_correct =
    roundtrip_node != nullptr &&
    roundtrip_node->layout.min_width == 160 &&
    roundtrip_node->layout.min_height == 40;

  binding.bounds_layout_constraint_diag.valid_layout_roundtrip_preserved =
    save_ok && load_ok &&
    roundtrip_layout_correct &&
    sig_after_roundtrip == sig_before_save;

  binding.selected_builder_node_id = "label-001";
  binding.focused_builder_node_id = "label-001";
  binding.multi_selected_node_ids = {"label-001"};
  binding.sync_multi_selection_with_primary();
  flow_ok = refresh_all_surfaces() && flow_ok;

  const auto* pre_node = binding.find_node_by_id("label-001");
  const int pre_min_width = pre_node ? pre_node->layout.min_width : -1;
  const int pre_min_height = pre_node ? pre_node->layout.min_height : -1;

  const bool autocorrect_rejected = !binding.apply_inspector_property_edits_command(
    {{"layout.min_width", "-50"}}, "phase103_57_autocorrect_test");
  flow_ok = refresh_all_surfaces() && flow_ok;

  const auto* post_node = binding.find_node_by_id("label-001");
  const int post_min_width = post_node ? post_node->layout.min_width : -1;
  const int post_min_height = post_node ? post_node->layout.min_height : -1;

  binding.bounds_layout_constraint_diag.no_silent_geometry_autocorrection =
    autocorrect_rejected &&
    pre_min_width >= 0 &&
    pre_min_height >= 0 &&
    post_min_width == pre_min_width &&
    post_min_height == pre_min_height;

  binding.bounds_layout_constraint_diag.preview_matches_structure_after_layout_mutations =
    preview_matches_structure() &&
    ngk::ui::builder::validate_builder_document(binding.builder_doc, nullptr) &&
    binding.check_cross_surface_sync();

  flow_ok = binding.bounds_layout_constraint_diag.negative_dimensions_rejected && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.invalid_child_parent_geometry_rejected && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.move_reparent_respects_layout_constraints && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.invalid_layout_not_committed_to_history && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.preview_never_reflects_invalid_document_state && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.undo_redo_restore_valid_layout_exact && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.save_load_rejects_constraint_violating_payload && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.valid_layout_roundtrip_preserved && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.no_silent_geometry_autocorrection && flow_ok;
  flow_ok = binding.bounds_layout_constraint_diag.preview_matches_structure_after_layout_mutations && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
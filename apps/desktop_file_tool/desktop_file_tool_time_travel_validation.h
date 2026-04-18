#pragma once

#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct TimeTravelPhase10373Binding {
  BuilderUndoRedoTimeTravelIntegrityHardeningDiagnostics& undo_redo_time_travel_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& builder_projection_filter_query;
  std::string& model_filter;
  std::string& inspector_binding_node_id;
  std::string& preview_binding_node_id;
  std::string& hover_node_id;
  std::string& drag_source_node_id;
  bool& drag_active;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
  std::string& drag_target_preview_parent_id;
  std::size_t& drag_target_preview_insert_index;
  std::string& drag_target_preview_resolution_kind;
  std::string& preview_visual_feedback_message;
  std::string& preview_visual_feedback_node_id;
  std::string& tree_visual_feedback_node_id;
  bool& inline_edit_active;
  std::string& inline_edit_node_id;
  std::string& inline_edit_buffer;
  std::string& inline_edit_original_text;
  std::string& preview_inline_loaded_text;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  bool& builder_doc_dirty;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<std::string()> filter_box_value;
  std::function<std::string()> collect_visible_tree_row_ids;
  std::function<std::string()> collect_visible_preview_row_ids;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(std::string&)> validate_global_document_invariant;
  std::function<void(const std::string&)> set_builder_projection_filter_state;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<void()> update_add_child_target_display;
  std::function<bool(const std::string&, const std::string&)> restore_exact_selection_focus_anchor_state;
  std::function<bool(bool, bool)> apply_keyboard_multi_selection_navigate;
  std::function<bool(const std::string&)> apply_inspector_text_edit_command;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
};

struct Phase10373TimeTravelSnapshot {
  std::string signature{};
  std::string selected{};
  std::string focused{};
  std::string anchor{};
  std::string multi{};
  std::string filter_query{};
  std::string model_filter{};
  std::string filter_box_value{};
  std::string tree_visible{};
  std::string preview_visible{};
  std::string inspector{};
  std::string preview{};
  std::string baseline{};
  std::size_t undo_size = 0;
  std::size_t redo_size = 0;
  bool dirty = false;
  bool cross_surface_ok = false;
  bool invariant_ok = false;
};

inline std::string phase103_73_join_ids(const std::vector<std::string>& ids) {
  std::ostringstream oss;
  for (std::size_t index = 0; index < ids.size(); ++index) {
    if (index > 0) {
      oss << ",";
    }
    oss << ids[index];
  }
  return oss.str();
}

inline Phase10373TimeTravelSnapshot capture_phase103_73_snapshot(TimeTravelPhase10373Binding& binding) {
  Phase10373TimeTravelSnapshot snapshot{};
  snapshot.signature = binding.current_document_signature(binding.builder_doc);
  snapshot.selected = binding.selected_builder_node_id;
  snapshot.focused = binding.focused_builder_node_id;
  snapshot.anchor = binding.builder_selection_anchor_node_id;
  snapshot.multi = phase103_73_join_ids(binding.multi_selected_node_ids);
  snapshot.filter_query = binding.builder_projection_filter_query;
  snapshot.model_filter = binding.model_filter;
  snapshot.filter_box_value = binding.filter_box_value();
  snapshot.tree_visible = binding.collect_visible_tree_row_ids();
  snapshot.preview_visible = binding.collect_visible_preview_row_ids();
  snapshot.inspector = binding.inspector_binding_node_id;
  snapshot.preview = binding.preview_binding_node_id;
  snapshot.baseline = binding.clean_builder_baseline_signature;
  snapshot.undo_size = binding.undo_history.size();
  snapshot.redo_size = binding.redo_stack.size();
  snapshot.dirty = binding.builder_doc_dirty;
  snapshot.cross_surface_ok = binding.check_cross_surface_sync();
  std::string invariant_reason;
  snapshot.invariant_ok = binding.validate_global_document_invariant(invariant_reason);
  return snapshot;
}

inline bool phase103_73_snapshots_equal(
  const Phase10373TimeTravelSnapshot& lhs,
  const Phase10373TimeTravelSnapshot& rhs) {
  return lhs.signature == rhs.signature &&
         lhs.selected == rhs.selected &&
         lhs.focused == rhs.focused &&
         lhs.anchor == rhs.anchor &&
         lhs.multi == rhs.multi &&
         lhs.filter_query == rhs.filter_query &&
         lhs.model_filter == rhs.model_filter &&
         lhs.filter_box_value == rhs.filter_box_value &&
         lhs.tree_visible == rhs.tree_visible &&
         lhs.preview_visible == rhs.preview_visible &&
         lhs.inspector == rhs.inspector &&
         lhs.preview == rhs.preview &&
         lhs.baseline == rhs.baseline &&
         lhs.undo_size == rhs.undo_size &&
         lhs.redo_size == rhs.redo_size &&
         lhs.dirty == rhs.dirty;
}

inline bool phase103_73_snapshots_equal_except_history(
  const Phase10373TimeTravelSnapshot& lhs,
  const Phase10373TimeTravelSnapshot& rhs) {
  return lhs.signature == rhs.signature &&
         lhs.selected == rhs.selected &&
         lhs.focused == rhs.focused &&
         lhs.anchor == rhs.anchor &&
         lhs.multi == rhs.multi &&
         lhs.filter_query == rhs.filter_query &&
         lhs.model_filter == rhs.model_filter &&
         lhs.filter_box_value == rhs.filter_box_value &&
         lhs.tree_visible == rhs.tree_visible &&
         lhs.preview_visible == rhs.preview_visible &&
         lhs.inspector == rhs.inspector &&
         lhs.preview == rhs.preview &&
         lhs.baseline == rhs.baseline &&
         lhs.dirty == rhs.dirty;
}

inline bool apply_phase103_73_projection_filter(
  TimeTravelPhase10373Binding& binding,
  const std::string& query) {
  binding.set_builder_projection_filter_state(query);
  const bool remap_ok = binding.remap_selection_or_fail();
  const bool focus_ok = binding.sync_focus_with_selection_or_fail();
  const bool inspector_ok = binding.refresh_inspector_or_fail();
  const bool preview_ok = binding.refresh_preview_or_fail();
  binding.update_add_child_target_display();
  const bool sync_ok = binding.check_cross_surface_sync();
  return remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;
}

inline ngk::ui::builder::BuilderDocument make_phase103_73_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_73_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.child_ids = {"phase103_73_label_a", "phase103_73_label_b", "phase103_73_group"};

  ngk::ui::builder::BuilderNode label_a{};
  label_a.node_id = "phase103_73_label_a";
  label_a.parent_id = root.node_id;
  label_a.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  label_a.text = "alpha";

  ngk::ui::builder::BuilderNode label_b{};
  label_b.node_id = "phase103_73_label_b";
  label_b.parent_id = root.node_id;
  label_b.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  label_b.text = "beta";

  ngk::ui::builder::BuilderNode group{};
  group.node_id = "phase103_73_group";
  group.parent_id = root.node_id;
  group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  group.child_ids = {"phase103_73_nested"};

  ngk::ui::builder::BuilderNode nested{};
  nested.node_id = "phase103_73_nested";
  nested.parent_id = group.node_id;
  nested.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  nested.text = "nested";

  doc.root_node_id = root.node_id;
  doc.nodes = {root, label_a, label_b, group, nested};
  return doc;
}

inline bool load_phase103_73_document(
  TimeTravelPhase10373Binding& binding,
  const ngk::ui::builder::BuilderDocument& doc) {
  binding.builder_doc = doc;
  binding.undo_history.clear();
  binding.redo_stack.clear();
  binding.selected_builder_node_id = "phase103_73_label_a";
  binding.multi_selected_node_ids = {binding.selected_builder_node_id};
  binding.focused_builder_node_id.clear();
  binding.builder_selection_anchor_node_id.clear();
  binding.set_builder_projection_filter_state("");
  binding.inspector_binding_node_id.clear();
  binding.preview_binding_node_id.clear();
  binding.hover_node_id.clear();
  binding.drag_source_node_id.clear();
  binding.drag_active = false;
  binding.drag_target_preview_node_id.clear();
  binding.drag_target_preview_is_illegal = false;
  binding.drag_target_preview_parent_id.clear();
  binding.drag_target_preview_insert_index = 0;
  binding.drag_target_preview_resolution_kind.clear();
  binding.preview_visual_feedback_message.clear();
  binding.preview_visual_feedback_node_id.clear();
  binding.tree_visual_feedback_node_id.clear();
  binding.inline_edit_active = false;
  binding.inline_edit_node_id.clear();
  binding.inline_edit_buffer.clear();
  binding.inline_edit_original_text.clear();
  binding.preview_inline_loaded_text.clear();
  const std::string sig = binding.current_document_signature(binding.builder_doc);
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = sig;
  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = sig;
  binding.builder_doc_dirty = false;
  return apply_phase103_73_projection_filter(binding, "");
}

inline bool establish_phase103_73_rich_state(TimeTravelPhase10373Binding& binding) {
  bool ok = load_phase103_73_document(binding, make_phase103_73_document());
  ok = apply_phase103_73_projection_filter(binding, "label") && ok;
  binding.selected_builder_node_id = "phase103_73_label_a";
  binding.multi_selected_node_ids = {binding.selected_builder_node_id};
  ok = binding.restore_exact_selection_focus_anchor_state(
         binding.selected_builder_node_id,
         binding.selected_builder_node_id) && ok;
  ok = binding.apply_keyboard_multi_selection_navigate(true, true) && ok;
  ok = binding.refresh_inspector_or_fail() && ok;
  ok = binding.refresh_preview_or_fail() && ok;
  binding.update_add_child_target_display();
  ok = binding.check_cross_surface_sync() && ok;
  return ok;
}

inline bool run_phase103_73_time_travel_phase(TimeTravelPhase10373Binding& binding) {
  binding.undo_redo_time_travel_integrity_diag = {};
  bool flow_ok = true;

  {
    flow_ok = establish_phase103_73_rich_state(binding) && flow_ok;
    const Phase10373TimeTravelSnapshot before_edit = capture_phase103_73_snapshot(binding);
    const bool edit_ok = binding.apply_inspector_text_edit_command("phase103_73_edit_a");
    const Phase10373TimeTravelSnapshot after_edit = capture_phase103_73_snapshot(binding);
    const bool undo_ok = binding.apply_undo_command();
    const Phase10373TimeTravelSnapshot after_undo = capture_phase103_73_snapshot(binding);
    const bool redo_ok = binding.apply_redo_command();
    const Phase10373TimeTravelSnapshot after_redo = capture_phase103_73_snapshot(binding);

    binding.undo_redo_time_travel_integrity_diag.undo_restores_full_system_state =
      edit_ok && undo_ok && phase103_73_snapshots_equal_except_history(after_undo, before_edit);
    binding.undo_redo_time_travel_integrity_diag.redo_restores_full_system_state =
      edit_ok && redo_ok && phase103_73_snapshots_equal(after_redo, after_edit);
    binding.undo_redo_time_travel_integrity_diag.selection_anchor_focus_restore_exact =
      edit_ok && undo_ok && redo_ok &&
      after_undo.selected == before_edit.selected &&
      after_undo.focused == before_edit.focused &&
      after_undo.anchor == before_edit.anchor &&
      after_redo.selected == after_edit.selected &&
      after_redo.focused == after_edit.focused &&
      after_redo.anchor == after_edit.anchor;
    binding.undo_redo_time_travel_integrity_diag.multi_selection_restore_exact =
      edit_ok && undo_ok && redo_ok &&
      after_undo.multi == before_edit.multi &&
      after_redo.multi == after_edit.multi;
    binding.undo_redo_time_travel_integrity_diag.cross_surface_state_consistent_after_time_travel =
      after_undo.cross_surface_ok && after_redo.cross_surface_ok &&
      after_undo.tree_visible == after_undo.preview_visible &&
      after_redo.tree_visible == after_redo.preview_visible &&
      after_undo.inspector == after_undo.selected && after_undo.preview == after_undo.selected &&
      after_redo.inspector == after_redo.selected && after_redo.preview == after_redo.selected;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.undo_restores_full_system_state && flow_ok;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.redo_restores_full_system_state && flow_ok;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.selection_anchor_focus_restore_exact && flow_ok;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.multi_selection_restore_exact && flow_ok;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.cross_surface_state_consistent_after_time_travel && flow_ok;
  }

  {
    flow_ok = establish_phase103_73_rich_state(binding) && flow_ok;
    const Phase10373TimeTravelSnapshot before_cycle = capture_phase103_73_snapshot(binding);
    const bool edit_ok = binding.apply_inspector_text_edit_command("phase103_73_cycle");
    const Phase10373TimeTravelSnapshot after_cycle = capture_phase103_73_snapshot(binding);
    bool cycles_ok = edit_ok;
    for (int cycle = 0; cycle < 8 && cycles_ok; ++cycle) {
      cycles_ok = binding.apply_undo_command() && cycles_ok;
      const Phase10373TimeTravelSnapshot undo_state = capture_phase103_73_snapshot(binding);
      cycles_ok = phase103_73_snapshots_equal_except_history(undo_state, before_cycle) && cycles_ok;
      cycles_ok = binding.apply_redo_command() && cycles_ok;
      const Phase10373TimeTravelSnapshot redo_state = capture_phase103_73_snapshot(binding);
      cycles_ok = phase103_73_snapshots_equal_except_history(redo_state, after_cycle) && cycles_ok;
    }
    binding.undo_redo_time_travel_integrity_diag.no_state_drift_after_repeated_cycles = cycles_ok;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.no_state_drift_after_repeated_cycles && flow_ok;
  }

  {
    flow_ok = establish_phase103_73_rich_state(binding) && flow_ok;
    const bool edit_a_ok = binding.apply_inspector_text_edit_command("phase103_73_branch_a");
    const Phase10373TimeTravelSnapshot after_edit_a = capture_phase103_73_snapshot(binding);
    const bool undo_ok = binding.apply_undo_command();
    const bool redo_available_before_branch = binding.redo_stack.size() == 1;
    const bool branch_edit_ok = binding.apply_inspector_text_edit_command("phase103_73_branch_b");
    const Phase10373TimeTravelSnapshot after_branch = capture_phase103_73_snapshot(binding);
    const bool redo_blocked = !binding.apply_redo_command();
    const Phase10373TimeTravelSnapshot after_redo_attempt = capture_phase103_73_snapshot(binding);

    binding.undo_redo_time_travel_integrity_diag.redo_stack_invalidated_on_new_mutation =
      edit_a_ok && undo_ok && redo_available_before_branch && branch_edit_ok && redo_blocked && binding.redo_stack.empty();
    binding.undo_redo_time_travel_integrity_diag.no_branching_history_corruption =
      binding.undo_redo_time_travel_integrity_diag.redo_stack_invalidated_on_new_mutation &&
      !phase103_73_snapshots_equal(after_branch, after_edit_a) &&
      phase103_73_snapshots_equal(after_branch, after_redo_attempt);
    flow_ok = binding.undo_redo_time_travel_integrity_diag.redo_stack_invalidated_on_new_mutation && flow_ok;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.no_branching_history_corruption && flow_ok;
  }

  {
    flow_ok = establish_phase103_73_rich_state(binding) && flow_ok;
    const Phase10373TimeTravelSnapshot before_valid_edit = capture_phase103_73_snapshot(binding);
    const bool valid_edit_ok = binding.apply_inspector_text_edit_command("phase103_73_failure_seed");
    const std::size_t history_before_failed_edit = binding.undo_history.size();
    const std::size_t redo_before_failed_edit = binding.redo_stack.size();

    const bool filter_cleared_ok = apply_phase103_73_projection_filter(binding, "");
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.selected_builder_node_id};
    const bool root_state_ok = binding.restore_exact_selection_focus_anchor_state(
      binding.selected_builder_node_id,
      binding.selected_builder_node_id);
    const bool inspector_ok = binding.refresh_inspector_or_fail();
    const bool preview_ok = binding.refresh_preview_or_fail();
    binding.update_add_child_target_display();
    const Phase10373TimeTravelSnapshot before_failed_edit = capture_phase103_73_snapshot(binding);
    const bool failed_edit = !binding.apply_inspector_text_edit_command("phase103_73_rejected_edit");
    const Phase10373TimeTravelSnapshot after_failed_edit = capture_phase103_73_snapshot(binding);
    const bool undo_ok = binding.apply_undo_command();
    const Phase10373TimeTravelSnapshot after_undo = capture_phase103_73_snapshot(binding);

    binding.undo_redo_time_travel_integrity_diag.no_history_pollution_from_failed_operations =
      valid_edit_ok && filter_cleared_ok && root_state_ok && inspector_ok && preview_ok && failed_edit && undo_ok &&
      phase103_73_snapshots_equal_except_history(before_failed_edit, after_failed_edit) &&
      after_failed_edit.undo_size == history_before_failed_edit &&
      after_failed_edit.redo_size == redo_before_failed_edit &&
      phase103_73_snapshots_equal_except_history(after_undo, before_valid_edit);
    flow_ok = binding.undo_redo_time_travel_integrity_diag.no_history_pollution_from_failed_operations && flow_ok;
  }

  {
    flow_ok = establish_phase103_73_rich_state(binding) && flow_ok;
    bool invariant_ok = binding.apply_inspector_text_edit_command("phase103_73_invariant");
    for (int cycle = 0; cycle < 6 && invariant_ok; ++cycle) {
      invariant_ok = binding.apply_undo_command() && invariant_ok;
      std::string invariant_reason;
      invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;
      invariant_ok = binding.apply_redo_command() && invariant_ok;
      invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;
    }
    binding.undo_redo_time_travel_integrity_diag.global_invariant_preserved_during_undo_redo = invariant_ok;
    flow_ok = binding.undo_redo_time_travel_integrity_diag.global_invariant_preserved_during_undo_redo && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
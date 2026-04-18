#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct ViewportScrollPhase10374Binding {
  BuilderViewportScrollVisualStateIntegrityHardeningDiagnostics& viewport_scroll_visual_state_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
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
  std::string& builder_projection_filter_query;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  bool& builder_doc_dirty;
  std::size_t max_visual_tree_rows;
  std::size_t max_visual_preview_rows;
  std::function<bool()> visible_rows_reference_valid_nodes;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<std::string()> collect_visible_tree_row_ids;
  std::function<std::string()> collect_visible_preview_row_ids;
  std::function<std::string()> first_visible_tree_row_node_id;
  std::function<std::string()> first_visible_preview_row_node_id;
  std::function<int()> get_tree_scroll_offset_y;
  std::function<int()> get_preview_scroll_offset_y;
  std::function<int()> get_tree_max_scroll_y;
  std::function<int()> get_preview_max_scroll_y;
  std::function<bool(const std::string&)> tree_row_fully_visible_in_viewport;
  std::function<bool(const std::string&)> preview_row_fully_visible_in_viewport;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(std::string&)> validate_global_document_invariant;
  std::function<void(const std::string&)> set_builder_projection_filter_state;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<void()> update_add_child_target_display;
  std::function<void(int)> set_tree_scroll_offset_y;
  std::function<void(int)> set_preview_scroll_offset_y;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool(const std::string&, const std::string&)> restore_exact_selection_focus_anchor_state;
  std::function<void()> refresh_tree_surface_label;
  std::function<std::size_t(const std::string&)> find_visible_tree_row_index;
  std::function<std::size_t(const std::string&)> find_visible_preview_row_index;
  std::function<bool(std::size_t, int&, int&)> compute_tree_row_bounds;
  std::function<bool(std::size_t, int&, int&)> compute_preview_row_bounds;
  std::function<void()> reconcile_tree_viewport_to_current_state;
  std::function<void()> reconcile_preview_viewport_to_current_state;
  std::function<bool(const std::string&, const char*)> invoke_builder_action;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
  std::function<bool()> apply_save_document_command;
  std::function<bool(bool)> apply_load_document_command;
  std::function<bool(bool)> apply_new_document_command;
};

struct Phase10374ViewportSnapshot {
  bool ok = false;
  std::string signature{};
  std::string selected{};
  std::string focused{};
  std::string filter_query{};
  std::string tree_visible{};
  std::string preview_visible{};
  std::string tree_top_id{};
  std::string preview_top_id{};
  int tree_scroll = 0;
  int preview_scroll = 0;
  int tree_max_scroll = 0;
  int preview_max_scroll = 0;
  bool tree_selected_visible = false;
  bool tree_focused_visible = false;
  bool preview_selected_visible = false;
  bool cross_surface_ok = false;
  bool invariant_ok = false;
  bool dirty = false;
  std::size_t undo_size = 0;
  std::size_t redo_size = 0;
};

inline Phase10374ViewportSnapshot capture_phase103_74_viewport_snapshot(ViewportScrollPhase10374Binding& binding) {
  Phase10374ViewportSnapshot snapshot{};
  snapshot.ok = binding.visible_rows_reference_valid_nodes();
  snapshot.signature = binding.current_document_signature(binding.builder_doc);
  snapshot.selected = binding.selected_builder_node_id;
  snapshot.focused = binding.focused_builder_node_id;
  snapshot.filter_query = binding.builder_projection_filter_query;
  snapshot.tree_visible = binding.collect_visible_tree_row_ids();
  snapshot.preview_visible = binding.collect_visible_preview_row_ids();
  snapshot.tree_top_id = binding.first_visible_tree_row_node_id();
  snapshot.preview_top_id = binding.first_visible_preview_row_node_id();
  snapshot.tree_scroll = binding.get_tree_scroll_offset_y();
  snapshot.preview_scroll = binding.get_preview_scroll_offset_y();
  snapshot.tree_max_scroll = binding.get_tree_max_scroll_y();
  snapshot.preview_max_scroll = binding.get_preview_max_scroll_y();
  snapshot.tree_selected_visible = binding.tree_row_fully_visible_in_viewport(binding.selected_builder_node_id);
  snapshot.tree_focused_visible =
    binding.focused_builder_node_id.empty() || binding.tree_row_fully_visible_in_viewport(binding.focused_builder_node_id);
  snapshot.preview_selected_visible = binding.preview_row_fully_visible_in_viewport(binding.selected_builder_node_id);
  snapshot.cross_surface_ok = binding.check_cross_surface_sync();
  std::string invariant_reason;
  snapshot.invariant_ok = binding.validate_global_document_invariant(invariant_reason);
  snapshot.dirty = binding.builder_doc_dirty;
  snapshot.undo_size = binding.undo_history.size();
  snapshot.redo_size = binding.redo_stack.size();
  snapshot.ok = snapshot.ok && snapshot.cross_surface_ok && snapshot.invariant_ok;
  return snapshot;
}

inline bool phase103_74_snapshots_equal(
  const Phase10374ViewportSnapshot& lhs,
  const Phase10374ViewportSnapshot& rhs) {
  return lhs.signature == rhs.signature &&
         lhs.selected == rhs.selected &&
         lhs.focused == rhs.focused &&
         lhs.filter_query == rhs.filter_query &&
         lhs.tree_visible == rhs.tree_visible &&
         lhs.preview_visible == rhs.preview_visible &&
         lhs.tree_top_id == rhs.tree_top_id &&
         lhs.preview_top_id == rhs.preview_top_id &&
         lhs.tree_scroll == rhs.tree_scroll &&
         lhs.preview_scroll == rhs.preview_scroll &&
         lhs.tree_selected_visible == rhs.tree_selected_visible &&
         lhs.tree_focused_visible == rhs.tree_focused_visible &&
         lhs.preview_selected_visible == rhs.preview_selected_visible &&
         lhs.dirty == rhs.dirty &&
         lhs.undo_size == rhs.undo_size &&
         lhs.redo_size == rhs.redo_size;
}

inline ngk::ui::builder::BuilderDocument make_phase103_74_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_74_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;

  for (int index = 0; index < 18; ++index) {
    const std::string node_id = "phase103_74_label_" + std::to_string(index);
    root.child_ids.push_back(node_id);
  }
  root.child_ids.push_back("phase103_74_group");

  doc.root_node_id = root.node_id;
  doc.nodes.push_back(root);

  for (int index = 0; index < 18; ++index) {
    ngk::ui::builder::BuilderNode label{};
    label.node_id = "phase103_74_label_" + std::to_string(index);
    label.parent_id = doc.root_node_id;
    label.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
    label.text = "phase103_74_label_" + std::to_string(index);
    doc.nodes.push_back(label);
  }

  ngk::ui::builder::BuilderNode group{};
  group.node_id = "phase103_74_group";
  group.parent_id = doc.root_node_id;
  group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  group.child_ids = {"phase103_74_nested_a", "phase103_74_nested_b"};
  doc.nodes.push_back(group);

  ngk::ui::builder::BuilderNode nested_a{};
  nested_a.node_id = "phase103_74_nested_a";
  nested_a.parent_id = group.node_id;
  nested_a.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  nested_a.text = "phase103_74_nested_a";
  doc.nodes.push_back(nested_a);

  ngk::ui::builder::BuilderNode nested_b{};
  nested_b.node_id = "phase103_74_nested_b";
  nested_b.parent_id = group.node_id;
  nested_b.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  nested_b.text = "phase103_74_nested_b";
  doc.nodes.push_back(nested_b);

  return doc;
}

inline bool apply_phase103_74_projection_filter(
  ViewportScrollPhase10374Binding& binding,
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

inline bool load_phase103_74_document(
  ViewportScrollPhase10374Binding& binding,
  const ngk::ui::builder::BuilderDocument& doc,
  const std::string& selected_id) {
  binding.builder_doc = doc;
  binding.undo_history.clear();
  binding.redo_stack.clear();
  binding.selected_builder_node_id = selected_id;
  binding.multi_selected_node_ids = selected_id.empty() ? std::vector<std::string>{} : std::vector<std::string>{selected_id};
  binding.focused_builder_node_id.clear();
  binding.builder_selection_anchor_node_id.clear();
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
  binding.set_tree_scroll_offset_y(0);
  binding.set_preview_scroll_offset_y(0);

  const std::string signature = binding.current_document_signature(binding.builder_doc);
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = signature;
  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = signature;
  binding.builder_doc_dirty = false;
  return apply_phase103_74_projection_filter(binding, "");
}

inline bool select_phase103_74_node_and_sync(
  ViewportScrollPhase10374Binding& binding,
  const std::string& node_id) {
  if (node_id.empty() || !binding.node_exists(node_id)) {
    return false;
  }
  binding.selected_builder_node_id = node_id;
  binding.multi_selected_node_ids = {node_id};
  const bool focus_ok = binding.restore_exact_selection_focus_anchor_state(node_id, node_id);
  const bool inspector_ok = binding.refresh_inspector_or_fail();
  const bool preview_ok = binding.refresh_preview_or_fail();
  binding.update_add_child_target_display();
  const bool sync_ok = binding.check_cross_surface_sync();
  return focus_ok && inspector_ok && preview_ok && sync_ok;
}

inline bool set_phase103_74_viewport_margins_for_selected(
  ViewportScrollPhase10374Binding& binding,
  int margin) {
  binding.refresh_tree_surface_label();
  const bool prelayout_inspector_ok = binding.refresh_inspector_or_fail();
  const bool prelayout_preview_ok = binding.refresh_preview_or_fail();
  if (!prelayout_inspector_ok || !prelayout_preview_ok) {
    return false;
  }

  const std::size_t tree_index = binding.find_visible_tree_row_index(binding.selected_builder_node_id);
  const std::size_t preview_index = binding.find_visible_preview_row_index(binding.selected_builder_node_id);
  if (tree_index >= binding.max_visual_tree_rows || preview_index >= binding.max_visual_preview_rows) {
    return false;
  }

  int tree_top = 0;
  int tree_bottom = 0;
  int preview_top = 0;
  int preview_bottom = 0;
  if (!binding.compute_tree_row_bounds(tree_index, tree_top, tree_bottom) ||
      !binding.compute_preview_row_bounds(preview_index, preview_top, preview_bottom)) {
    return false;
  }

  binding.set_tree_scroll_offset_y(std::max(0, tree_top - margin));
  binding.set_preview_scroll_offset_y(std::max(0, preview_top - margin));

  binding.reconcile_tree_viewport_to_current_state();
  binding.reconcile_preview_viewport_to_current_state();
  binding.refresh_tree_surface_label();
  const bool inspector_ok = binding.refresh_inspector_or_fail();
  const bool preview_ok = binding.refresh_preview_or_fail();
  binding.update_add_child_target_display();
  const bool sync_ok = binding.check_cross_surface_sync();
  return inspector_ok && preview_ok && sync_ok;
}

inline Phase10374ViewportSnapshot execute_phase103_74_reference_sequence(ViewportScrollPhase10374Binding& binding) {
  Phase10374ViewportSnapshot snapshot{};
  bool ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
  ok = select_phase103_74_node_and_sync(binding, "phase103_74_label_15") && ok;
  ok = set_phase103_74_viewport_margins_for_selected(binding, 10) && ok;
  ok = apply_phase103_74_projection_filter(binding, "phase103_74_label_15") && ok;
  ok = apply_phase103_74_projection_filter(binding, "") && ok;
  ok = select_phase103_74_node_and_sync(binding, "phase103_74_nested_b") && ok;
  ok = set_phase103_74_viewport_margins_for_selected(binding, 6) && ok;
  snapshot = capture_phase103_74_viewport_snapshot(binding);
  snapshot.ok = snapshot.ok && ok;
  return snapshot;
}

inline bool run_phase103_74_viewport_scroll_phase(ViewportScrollPhase10374Binding& binding) {
  binding.viewport_scroll_visual_state_integrity_diag = {};
  bool flow_ok = true;

  {
    const bool load_ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
    const bool select_ok = load_ok && select_phase103_74_node_and_sync(binding, "phase103_74_label_15");
    const Phase10374ViewportSnapshot first = capture_phase103_74_viewport_snapshot(binding);

    const bool load_ok_repeat = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
    const bool select_ok_repeat = load_ok_repeat && select_phase103_74_node_and_sync(binding, "phase103_74_label_15");
    const Phase10374ViewportSnapshot second = capture_phase103_74_viewport_snapshot(binding);

    binding.viewport_scroll_visual_state_integrity_diag.selected_node_visible_or_scrolled_into_view_deterministically =
      select_ok && select_ok_repeat &&
      first.tree_selected_visible && first.preview_selected_visible &&
      second.tree_selected_visible && second.preview_selected_visible &&
      first.tree_scroll == second.tree_scroll &&
      first.preview_scroll == second.preview_scroll;
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.selected_node_visible_or_scrolled_into_view_deterministically && flow_ok;
  }

  {
    const Phase10374ViewportSnapshot first = execute_phase103_74_reference_sequence(binding);
    const Phase10374ViewportSnapshot second = execute_phase103_74_reference_sequence(binding);
    binding.viewport_scroll_visual_state_integrity_diag.scroll_position_deterministic_for_identical_sequences =
      first.ok && second.ok && phase103_74_snapshots_equal(first, second);
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.scroll_position_deterministic_for_identical_sequences && flow_ok;
  }

  {
    bool ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
    ok = select_phase103_74_node_and_sync(binding, "phase103_74_label_15") && ok;
    ok = set_phase103_74_viewport_margins_for_selected(binding, 8) && ok;
    const Phase10374ViewportSnapshot before_delete = capture_phase103_74_viewport_snapshot(binding);
    const bool delete_ok = binding.invoke_builder_action("ACTION_DELETE_CURRENT", "phase103_74");
    const Phase10374ViewportSnapshot after_delete = capture_phase103_74_viewport_snapshot(binding);
    const bool undo_ok = delete_ok && binding.apply_undo_command();
    const Phase10374ViewportSnapshot after_undo = capture_phase103_74_viewport_snapshot(binding);
    const bool redo_ok = undo_ok && binding.apply_redo_command();
    const Phase10374ViewportSnapshot after_redo = capture_phase103_74_viewport_snapshot(binding);

    binding.viewport_scroll_visual_state_integrity_diag.undo_redo_restores_viewport_with_state =
      ok && delete_ok && undo_ok && redo_ok &&
      after_undo.tree_scroll == before_delete.tree_scroll &&
      after_undo.preview_scroll == before_delete.preview_scroll &&
      after_redo.tree_scroll == after_delete.tree_scroll &&
      after_redo.preview_scroll == after_delete.preview_scroll &&
      after_undo.tree_selected_visible && after_undo.preview_selected_visible &&
      after_redo.tree_selected_visible && after_redo.preview_selected_visible;
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.undo_redo_restores_viewport_with_state && flow_ok;
  }

  {
    bool ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
    ok = select_phase103_74_node_and_sync(binding, "phase103_74_label_15") && ok;
    ok = set_phase103_74_viewport_margins_for_selected(binding, 8) && ok;
    const bool filter_ok_1 = apply_phase103_74_projection_filter(binding, "phase103_74_label_15");
    const Phase10374ViewportSnapshot filtered_once = capture_phase103_74_viewport_snapshot(binding);
    const bool clear_ok = apply_phase103_74_projection_filter(binding, "");
    const Phase10374ViewportSnapshot unfiltered = capture_phase103_74_viewport_snapshot(binding);
    const bool filter_ok_2 = apply_phase103_74_projection_filter(binding, "phase103_74_label_15");
    const Phase10374ViewportSnapshot filtered_twice = capture_phase103_74_viewport_snapshot(binding);

    binding.viewport_scroll_visual_state_integrity_diag.filtered_and_unfiltered_scroll_mapping_consistent =
      ok && filter_ok_1 && clear_ok && filter_ok_2 &&
      filtered_once.tree_selected_visible && filtered_once.preview_selected_visible &&
      unfiltered.tree_selected_visible && unfiltered.preview_selected_visible &&
      filtered_once.tree_scroll == filtered_twice.tree_scroll &&
      filtered_once.preview_scroll == filtered_twice.preview_scroll &&
      filtered_once.tree_top_id == filtered_twice.tree_top_id &&
      filtered_once.preview_top_id == filtered_twice.preview_top_id;
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.filtered_and_unfiltered_scroll_mapping_consistent && flow_ok;
  }

  {
    bool ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
    ok = select_phase103_74_node_and_sync(binding, "phase103_74_label_15") && ok;
    ok = set_phase103_74_viewport_margins_for_selected(binding, 8) && ok;
    const bool before_valid = binding.visible_rows_reference_valid_nodes();
    const bool delete_ok = binding.invoke_builder_action("ACTION_DELETE_CURRENT", "phase103_74_invalid_ref");
    const Phase10374ViewportSnapshot after_delete = capture_phase103_74_viewport_snapshot(binding);

    binding.viewport_scroll_visual_state_integrity_diag.viewport_never_references_invalid_or_deleted_rows =
      ok && before_valid && delete_ok && binding.visible_rows_reference_valid_nodes() &&
      after_delete.tree_scroll >= 0 && after_delete.preview_scroll >= 0 &&
      after_delete.tree_scroll <= after_delete.tree_max_scroll &&
      after_delete.preview_scroll <= after_delete.preview_max_scroll &&
      (after_delete.tree_top_id.empty() || binding.node_exists(after_delete.tree_top_id)) &&
      (after_delete.preview_top_id.empty() || binding.node_exists(after_delete.preview_top_id));
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.viewport_never_references_invalid_or_deleted_rows && flow_ok;
  }

  {
    bool ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
    ok = select_phase103_74_node_and_sync(binding, "phase103_74_label_15") && ok;
    ok = set_phase103_74_viewport_margins_for_selected(binding, 8) && ok;
    const Phase10374ViewportSnapshot before_save = capture_phase103_74_viewport_snapshot(binding);
    const bool save_ok = binding.apply_save_document_command();
    const Phase10374ViewportSnapshot after_save = capture_phase103_74_viewport_snapshot(binding);
    const bool load_ok = binding.apply_load_document_command(false);
    const Phase10374ViewportSnapshot after_load = capture_phase103_74_viewport_snapshot(binding);
    const bool new_ok = binding.apply_new_document_command(true);
    const Phase10374ViewportSnapshot after_new = capture_phase103_74_viewport_snapshot(binding);

    binding.viewport_scroll_visual_state_integrity_diag.load_save_initialize_or_preserve_viewport_deterministically =
      ok && save_ok && load_ok &&
      before_save.tree_scroll == after_save.tree_scroll &&
      before_save.preview_scroll == after_save.preview_scroll &&
      after_load.tree_scroll == 0 && after_load.preview_scroll == 0 &&
      after_new.tree_scroll == 0 && after_new.preview_scroll == 0 &&
      after_load.tree_selected_visible && after_load.preview_selected_visible &&
      after_new.tree_selected_visible && after_new.preview_selected_visible;
    (void)new_ok;
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.load_save_initialize_or_preserve_viewport_deterministically && flow_ok;
  }

  {
    bool ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_label_15");
    ok = select_phase103_74_node_and_sync(binding, "phase103_74_label_15") && ok;
    const std::string before_signature = binding.current_document_signature(binding.builder_doc);
    const std::size_t before_undo = binding.undo_history.size();
    const std::size_t before_redo = binding.redo_stack.size();
    const bool before_dirty = binding.builder_doc_dirty;
    ok = set_phase103_74_viewport_margins_for_selected(binding, 2) && ok;
    ok = set_phase103_74_viewport_margins_for_selected(binding, 12) && ok;
    const std::string after_signature = binding.current_document_signature(binding.builder_doc);

    binding.viewport_scroll_visual_state_integrity_diag.no_dirty_or_history_side_effects_from_viewport_changes =
      ok && before_signature == after_signature &&
      binding.undo_history.size() == before_undo &&
      binding.redo_stack.size() == before_redo &&
      binding.builder_doc_dirty == before_dirty;
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.no_dirty_or_history_side_effects_from_viewport_changes && flow_ok;
  }

  {
    bool ok = load_phase103_74_document(binding, make_phase103_74_document(), "phase103_74_nested_b");
    ok = select_phase103_74_node_and_sync(binding, "phase103_74_nested_b") && ok;
    ok = set_phase103_74_viewport_margins_for_selected(binding, 6) && ok;
    const Phase10374ViewportSnapshot snapshot = capture_phase103_74_viewport_snapshot(binding);

    binding.viewport_scroll_visual_state_integrity_diag.tree_and_preview_viewports_remain_coherent =
      ok && snapshot.ok && !snapshot.tree_top_id.empty() && !snapshot.preview_top_id.empty();
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.tree_and_preview_viewports_remain_coherent && flow_ok;
  }

  {
    bool ok = true;
    Phase10374ViewportSnapshot baseline{};
    for (int cycle = 0; cycle < 6 && ok; ++cycle) {
      const Phase10374ViewportSnapshot current = execute_phase103_74_reference_sequence(binding);
      ok = current.ok && ok;
      if (cycle == 0) {
        baseline = current;
      } else {
        ok = phase103_74_snapshots_equal(current, baseline) && ok;
      }
    }
    binding.viewport_scroll_visual_state_integrity_diag.no_scroll_drift_after_stress_sequences = ok;
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.no_scroll_drift_after_stress_sequences && flow_ok;
  }

  {
    bool invariant_ok = true;
    for (int cycle = 0; cycle < 5 && invariant_ok; ++cycle) {
      const Phase10374ViewportSnapshot snapshot = execute_phase103_74_reference_sequence(binding);
      invariant_ok = snapshot.ok && snapshot.invariant_ok && invariant_ok;
    }
    binding.viewport_scroll_visual_state_integrity_diag.global_invariant_preserved_during_viewport_updates = invariant_ok;
    flow_ok = binding.viewport_scroll_visual_state_integrity_diag.global_invariant_preserved_during_viewport_updates && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
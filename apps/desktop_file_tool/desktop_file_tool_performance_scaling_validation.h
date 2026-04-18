#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <iomanip>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct PerformanceScalingPhase10376Binding {
  BuilderPerformanceScalingIntegrityHardeningDiagnostics& performance_scaling_integrity_diag;
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
  std::string& model_filter;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  bool& builder_doc_dirty;
  int& global_invariant_checks_total;
  int& global_invariant_failures_total;
  std::size_t max_visual_tree_rows = 0;
  std::size_t max_visual_preview_rows = 0;
  std::function<void(int)> set_tree_scroll_offset_y;
  std::function<void(int)> set_preview_scroll_offset_y;
  std::function<int()> tree_scroll_offset_y;
  std::function<int()> preview_scroll_offset_y;
  std::function<bool()> visible_rows_reference_valid_nodes;
  std::function<bool()> refresh_surfaces;
  std::function<bool(const std::string&)> apply_projection_filter;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<bool(const std::string&)> node_exists;
  std::function<const ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&, const std::string&)> restore_exact_selection_focus_anchor_state;
  std::function<std::string()> tree_visible_signature;
  std::function<std::string()> preview_visible_signature;
  std::function<std::string()> first_visible_tree_row_node_id;
  std::function<std::string()> first_visible_preview_row_node_id;
  std::function<bool(const std::string&)> tree_row_fully_visible_in_viewport;
  std::function<bool(const std::string&)> preview_row_fully_visible_in_viewport;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(std::string&)> validate_global_document_invariant;
  std::function<bool()> prepare_viewport_layout;
  std::function<void()> refresh_tree_surface_label;
  std::function<std::size_t(const std::string&)> find_visible_tree_row_index;
  std::function<std::size_t(const std::string&)> find_visible_preview_row_index;
  std::function<bool(std::size_t, int&, int&)> compute_tree_row_bounds;
  std::function<bool(std::size_t, int&, int&)> compute_preview_row_bounds;
  std::function<void()> reconcile_tree_viewport_to_current_state;
  std::function<void()> reconcile_preview_viewport_to_current_state;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::vector<std::pair<std::string, std::string>>&, const std::string&)> apply_inspector_property_edits_command;
  std::function<bool(const std::vector<std::string>&, const std::string&)> apply_bulk_move_reparent_selected_nodes_command;
  std::function<bool(const std::string&, const std::string&, const std::string&, std::vector<std::string>*, std::string*)>
    import_external_builder_subtree_payload;
  std::function<bool(const std::string&)> begin_tree_drag;
  std::function<bool(const std::string&)> commit_tree_drag_reorder;
  std::function<bool()> apply_delete_command_for_current_selection;
  std::function<bool(const std::vector<CommandHistoryEntry>&)> validate_command_history_snapshot;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
};

struct ScalingSnapshot {
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
  bool tree_selected_visible = false;
  bool preview_selected_visible = false;
  std::size_t undo_size = 0;
  std::size_t redo_size = 0;
  bool dirty = false;
};

struct ScalingSequenceOutcome {
  bool ok = false;
  std::string signature{};
  std::string selected{};
  std::string focused{};
  std::size_t undo_size = 0;
  std::size_t redo_size = 0;
  bool dirty = false;
};

inline std::string format_phase103_76_int(int value, int width) {
  std::ostringstream oss;
  oss << std::setw(width) << std::setfill('0') << value;
  return oss.str();
}

inline std::string phase103_76_group_id(int group_index) {
  return std::string("phase103_76_group_") + format_phase103_76_int(group_index, 3);
}

inline std::string phase103_76_group_item_id(int group_index, int item_index) {
  return phase103_76_group_id(group_index) + std::string("_item_") + format_phase103_76_int(item_index, 2);
}

inline ngk::ui::builder::BuilderDocument make_phase103_76_large_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_76_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.layout.min_width = 1;

  doc.root_node_id = root.node_id;

  for (int group_index = 0; group_index < 180; ++group_index) {
    const std::string current_group_id = phase103_76_group_id(group_index);
    root.child_ids.push_back(current_group_id);

    ngk::ui::builder::BuilderNode group{};
    group.node_id = current_group_id;
    group.parent_id = root.node_id;
    group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    group.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    group.layout.min_width = 1;
    for (int item_index = 0; item_index < 8; ++item_index) {
      group.child_ids.push_back(phase103_76_group_item_id(group_index, item_index));
    }
    doc.nodes.push_back(group);

    for (int item_index = 0; item_index < 8; ++item_index) {
      ngk::ui::builder::BuilderNode item{};
      item.node_id = phase103_76_group_item_id(group_index, item_index);
      item.parent_id = current_group_id;
      item.widget_type = (item_index % 2 == 0)
        ? ngk::ui::builder::BuilderWidgetType::Label
        : ngk::ui::builder::BuilderWidgetType::Button;
      item.text = item.node_id;
      item.layout.min_width = 1;
      doc.nodes.push_back(item);
    }
  }

  root.child_ids.push_back("phase103_76_import_target");
  root.child_ids.push_back("phase103_76_deep_00");

  ngk::ui::builder::BuilderNode import_target{};
  import_target.node_id = "phase103_76_import_target";
  import_target.parent_id = root.node_id;
  import_target.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  import_target.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  import_target.layout.min_width = 1;
  doc.nodes.push_back(import_target);

  for (int depth = 0; depth < 24; ++depth) {
    ngk::ui::builder::BuilderNode node{};
    node.node_id = std::string("phase103_76_deep_") + format_phase103_76_int(depth, 2);
    node.parent_id = depth == 0
      ? root.node_id
      : std::string("phase103_76_deep_") + format_phase103_76_int(depth - 1, 2);
    node.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    node.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    node.layout.min_width = 1;
    node.child_ids = {
      depth == 23
        ? std::string("phase103_76_deep_leaf")
        : std::string("phase103_76_deep_") + format_phase103_76_int(depth + 1, 2)
    };
    doc.nodes.push_back(node);
  }

  ngk::ui::builder::BuilderNode deep_leaf{};
  deep_leaf.node_id = "phase103_76_deep_leaf";
  deep_leaf.parent_id = "phase103_76_deep_23";
  deep_leaf.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  deep_leaf.text = "phase103_76_deep_leaf";
  deep_leaf.layout.min_width = 1;
  doc.nodes.push_back(deep_leaf);

  doc.nodes.insert(doc.nodes.begin(), root);
  return doc;
}

inline ngk::ui::builder::BuilderDocument make_phase103_76_external_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_76_external_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  root.layout.min_width = 1;
  root.child_ids = {"phase103_76_external_label", "phase103_76_external_group"};

  ngk::ui::builder::BuilderNode label{};
  label.node_id = "phase103_76_external_label";
  label.parent_id = root.node_id;
  label.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  label.text = "phase103_76_external_label";

  ngk::ui::builder::BuilderNode group{};
  group.node_id = "phase103_76_external_group";
  group.parent_id = root.node_id;
  group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  group.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  group.layout.min_width = 1;
  group.child_ids = {"phase103_76_external_nested"};

  ngk::ui::builder::BuilderNode nested{};
  nested.node_id = "phase103_76_external_nested";
  nested.parent_id = group.node_id;
  nested.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  nested.text = "phase103_76_external_nested";

  doc.root_node_id = root.node_id;
  doc.nodes = {root, label, group, nested};
  return doc;
}

inline bool load_phase103_76_document(
  PerformanceScalingPhase10376Binding& binding,
  const ngk::ui::builder::BuilderDocument& doc,
  const std::string& selected_id) {
  binding.builder_doc = doc;
  binding.undo_history.clear();
  binding.redo_stack.clear();
  binding.selected_builder_node_id = selected_id;
  binding.multi_selected_node_ids = selected_id.empty()
    ? std::vector<std::string>{}
    : std::vector<std::string>{selected_id};
  binding.focused_builder_node_id = selected_id;
  binding.builder_selection_anchor_node_id = selected_id;
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
  binding.builder_projection_filter_query.clear();
  binding.model_filter.clear();
  binding.set_tree_scroll_offset_y(0);
  binding.set_preview_scroll_offset_y(0);

  const std::string signature = binding.current_document_signature(binding.builder_doc);
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = signature;
  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = signature;
  binding.builder_doc_dirty = false;
  return binding.apply_projection_filter("");
}

inline bool select_phase103_76_node_and_sync(
  PerformanceScalingPhase10376Binding& binding,
  const std::string& node_id) {
  if (node_id.empty() || !binding.node_exists(node_id)) {
    return false;
  }
  binding.selected_builder_node_id = node_id;
  binding.multi_selected_node_ids = {node_id};
  const bool focus_ok = binding.restore_exact_selection_focus_anchor_state(node_id, node_id);
  return focus_ok && binding.refresh_surfaces();
}

inline int phase103_76_depth_of_node(
  PerformanceScalingPhase10376Binding& binding,
  const std::string& node_id) {
  int depth = 0;
  std::string current = node_id;
  std::size_t guard = 0;
  while (!current.empty() && current != binding.builder_doc.root_node_id && guard < binding.builder_doc.nodes.size()) {
    const auto* node = binding.find_node_by_id(current);
    if (!node) {
      return -1;
    }
    current = node->parent_id;
    depth += 1;
    guard += 1;
  }
  return current == binding.builder_doc.root_node_id ? depth : -1;
}

inline ScalingSnapshot capture_phase103_76_snapshot(PerformanceScalingPhase10376Binding& binding) {
  ScalingSnapshot snapshot{};
  snapshot.signature = binding.current_document_signature(binding.builder_doc);
  snapshot.selected = binding.selected_builder_node_id;
  snapshot.focused = binding.focused_builder_node_id;
  snapshot.filter_query = binding.builder_projection_filter_query;
  snapshot.tree_visible = binding.tree_visible_signature();
  snapshot.preview_visible = binding.preview_visible_signature();
  snapshot.tree_top_id = binding.first_visible_tree_row_node_id();
  snapshot.preview_top_id = binding.first_visible_preview_row_node_id();
  snapshot.tree_scroll = binding.tree_scroll_offset_y();
  snapshot.preview_scroll = binding.preview_scroll_offset_y();
  snapshot.tree_selected_visible = binding.tree_row_fully_visible_in_viewport(binding.selected_builder_node_id);
  snapshot.preview_selected_visible = binding.preview_row_fully_visible_in_viewport(binding.selected_builder_node_id);
  snapshot.undo_size = binding.undo_history.size();
  snapshot.redo_size = binding.redo_stack.size();
  snapshot.dirty = binding.builder_doc_dirty;
  std::string invariant_reason;
  snapshot.ok = binding.visible_rows_reference_valid_nodes() &&
                binding.check_cross_surface_sync() &&
                binding.validate_global_document_invariant(invariant_reason);
  return snapshot;
}

inline bool phase103_76_snapshots_equal(const ScalingSnapshot& lhs, const ScalingSnapshot& rhs) {
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
         lhs.preview_selected_visible == rhs.preview_selected_visible &&
         lhs.undo_size == rhs.undo_size &&
         lhs.redo_size == rhs.redo_size &&
         lhs.dirty == rhs.dirty;
}

inline bool set_phase103_76_viewport_margins_for_selected(
  PerformanceScalingPhase10376Binding& binding,
  int margin) {
  if (!binding.prepare_viewport_layout()) {
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
  return binding.refresh_surfaces();
}

inline bool mutate_phase103_76_large_document_sequence(
  PerformanceScalingPhase10376Binding& binding,
  ngk::ui::builder::BuilderWidgetType label_widget_type) {
  bool ok = true;
  for (int cycle = 0; cycle < 12 && ok; ++cycle) {
    const std::string insert_id = std::string("phase103_76_seq_insert_") + format_phase103_76_int(cycle, 2);
    const std::string edit_text = std::string("phase103_76_seq_text_") + format_phase103_76_int(cycle, 2);
    const std::string insert_parent = phase103_76_group_id(20 + (cycle % 4));
    const std::string move_target = phase103_76_group_id(30 + (cycle % 4));
    ok = binding.apply_typed_palette_insert(label_widget_type, insert_parent, insert_id) && ok;
    ok = select_phase103_76_node_and_sync(binding, insert_id) && ok;
    ok = binding.apply_inspector_property_edits_command(
      {{"text", edit_text}},
      std::string("phase103_76_seq_edit_") + format_phase103_76_int(cycle, 2)) && ok;
    ok = binding.apply_bulk_move_reparent_selected_nodes_command({insert_id}, move_target) && ok;
    if ((cycle % 2) == 0) {
      ok = binding.apply_projection_filter(edit_text) && ok;
      ok = binding.apply_projection_filter("") && ok;
    }
    std::string invariant_reason;
    ok = binding.validate_global_document_invariant(invariant_reason) && ok;
    ok = binding.validate_command_history_snapshot(binding.undo_history) && ok;
    ok = binding.validate_command_history_snapshot(binding.redo_stack) && ok;
    ok = binding.check_cross_surface_sync() && ok;
  }
  return ok;
}

inline bool build_phase103_76_large_history_sequence(
  PerformanceScalingPhase10376Binding& binding,
  ngk::ui::builder::BuilderWidgetType label_widget_type) {
  bool ok = true;
  for (int cycle = 0; cycle < 24 && ok; ++cycle) {
    const std::string insert_id = std::string("phase103_76_history_insert_") + format_phase103_76_int(cycle, 2);
    ok = binding.apply_typed_palette_insert(label_widget_type, phase103_76_group_id(4 + (cycle % 4)), insert_id) && ok;
    if ((cycle % 4) == 0) {
      ok = select_phase103_76_node_and_sync(binding, insert_id) && ok;
      ok = binding.apply_inspector_property_edits_command(
        {{"text", std::string("phase103_76_history_text_") + format_phase103_76_int(cycle, 2)}},
        std::string("phase103_76_history_edit_") + format_phase103_76_int(cycle, 2)) && ok;
    }
    std::string invariant_reason;
    ok = binding.validate_global_document_invariant(invariant_reason) && ok;
  }
  return ok;
}

inline ScalingSequenceOutcome execute_phase103_76_large_sequence(
  PerformanceScalingPhase10376Binding& binding,
  const ngk::ui::builder::BuilderDocument& large_doc,
  ngk::ui::builder::BuilderWidgetType label_widget_type) {
  ScalingSequenceOutcome outcome{};
  outcome.ok = load_phase103_76_document(binding, large_doc, phase103_76_group_id(0));
  outcome.ok = outcome.ok && mutate_phase103_76_large_document_sequence(binding, label_widget_type);
  outcome.signature = binding.current_document_signature(binding.builder_doc);
  outcome.selected = binding.selected_builder_node_id;
  outcome.focused = binding.focused_builder_node_id;
  outcome.undo_size = binding.undo_history.size();
  outcome.redo_size = binding.redo_stack.size();
  outcome.dirty = binding.builder_doc_dirty;
  return outcome;
}

inline bool run_phase103_76_performance_scaling_phase(PerformanceScalingPhase10376Binding& binding) {
  binding.performance_scaling_integrity_diag = {};
  bool flow_ok = true;
  const auto label_widget_type = ngk::ui::builder::BuilderWidgetType::Label;

  const ngk::ui::builder::BuilderDocument large_doc = make_phase103_76_large_document();
  const std::string large_doc_signature =
    ngk::ui::builder::serialize_builder_document_deterministic(large_doc);
  const std::string external_payload =
    ngk::ui::builder::serialize_builder_document_deterministic(make_phase103_76_external_document());

  {
    const bool loaded = load_phase103_76_document(binding, large_doc, phase103_76_group_id(2));
    bool ok = loaded;
    ok = binding.begin_tree_drag(phase103_76_group_id(2)) && ok;
    ok = binding.commit_tree_drag_reorder(phase103_76_group_id(4)) && ok;

    const std::string insert_id = "phase103_76_large_insert";
    ok = binding.apply_typed_palette_insert(label_widget_type, phase103_76_group_id(20), insert_id) && ok;
    ok = select_phase103_76_node_and_sync(binding, insert_id) && ok;
    ok = binding.apply_inspector_property_edits_command(
      {{"text", "phase103_76_large_insert_text"}},
      "phase103_76_large_insert_edit") && ok;
    ok = binding.apply_bulk_move_reparent_selected_nodes_command({insert_id}, phase103_76_group_id(21)) && ok;

    std::vector<std::string> imported_roots{};
    ok = binding.import_external_builder_subtree_payload(
      external_payload,
      "phase103_76_import_target",
      "phase103_76_large_import",
      &imported_roots,
      nullptr) && ok;

    ok = select_phase103_76_node_and_sync(binding, insert_id) && ok;
    ok = binding.apply_delete_command_for_current_selection() && ok;
    ok = binding.apply_projection_filter(phase103_76_group_item_id(179, 7)) && ok;
    ok = select_phase103_76_node_and_sync(binding, phase103_76_group_item_id(179, 7)) && ok;
    ok = binding.apply_projection_filter("") && ok;

    std::string invariant_reason;
    const auto* import_target = binding.find_node_by_id("phase103_76_import_target");
    binding.performance_scaling_integrity_diag.large_document_operations_remain_correct =
      ok &&
      large_doc_signature == ngk::ui::builder::serialize_builder_document_deterministic(large_doc) &&
      !binding.node_exists(insert_id) &&
      import_target != nullptr && !imported_roots.empty() && binding.node_exists(imported_roots.front()) &&
      binding.node_exists(phase103_76_group_item_id(179, 7)) &&
      binding.validate_global_document_invariant(invariant_reason) &&
      binding.validate_command_history_snapshot(binding.undo_history) &&
      binding.validate_command_history_snapshot(binding.redo_stack) &&
      binding.check_cross_surface_sync();
    flow_ok = binding.performance_scaling_integrity_diag.large_document_operations_remain_correct && flow_ok;
  }

  {
    const bool loaded = load_phase103_76_document(binding, large_doc, "phase103_76_deep_leaf");
    bool ok = loaded;
    ok = binding.apply_projection_filter("phase103_76_deep_leaf") && ok;
    ok = select_phase103_76_node_and_sync(binding, "phase103_76_deep_leaf") && ok;
    ok = binding.apply_inspector_property_edits_command(
      {{"text", "phase103_76_deep_leaf_verified"}},
      "phase103_76_deep_edit") && ok;
    ok = binding.apply_projection_filter("") && ok;
    const int depth = phase103_76_depth_of_node(binding, "phase103_76_deep_leaf");
    std::string invariant_reason;
    binding.performance_scaling_integrity_diag.deep_hierarchy_handled_without_failure =
      ok && depth >= 25 && binding.validate_global_document_invariant(invariant_reason) && binding.check_cross_surface_sync();
    flow_ok = binding.performance_scaling_integrity_diag.deep_hierarchy_handled_without_failure && flow_ok;
  }

  {
    const ScalingSequenceOutcome outcome = execute_phase103_76_large_sequence(binding, large_doc, label_widget_type);
    std::string invariant_reason;
    binding.performance_scaling_integrity_diag.long_stress_sequence_preserves_invariant =
      outcome.ok && outcome.undo_size >= 24 && outcome.dirty && !outcome.signature.empty() &&
      binding.validate_global_document_invariant(invariant_reason) &&
      binding.validate_command_history_snapshot(binding.undo_history) &&
      binding.validate_command_history_snapshot(binding.redo_stack);
    flow_ok = binding.performance_scaling_integrity_diag.long_stress_sequence_preserves_invariant && flow_ok;
  }

  {
    const bool loaded = load_phase103_76_document(binding, large_doc, phase103_76_group_id(0));
    const std::string before_signature = loaded ? binding.current_document_signature(binding.builder_doc) : std::string{};
    bool ok = loaded && !before_signature.empty() && build_phase103_76_large_history_sequence(binding, label_widget_type);
    const std::size_t mutation_count = binding.undo_history.size();
    const std::string after_signature = binding.current_document_signature(binding.builder_doc);
    for (std::size_t index = 0; index < mutation_count && ok; ++index) {
      ok = binding.apply_undo_command() && ok;
    }
    const std::string after_undo_signature = binding.current_document_signature(binding.builder_doc);
    for (std::size_t index = 0; index < mutation_count && ok; ++index) {
      ok = binding.apply_redo_command() && ok;
    }
    const std::string after_redo_signature = binding.current_document_signature(binding.builder_doc);
    std::string invariant_reason;
    binding.performance_scaling_integrity_diag.undo_redo_stable_under_large_history =
      ok && mutation_count >= 24 &&
      after_undo_signature == before_signature &&
      after_redo_signature == after_signature &&
      binding.validate_global_document_invariant(invariant_reason) &&
      binding.validate_command_history_snapshot(binding.undo_history) &&
      binding.validate_command_history_snapshot(binding.redo_stack);
    flow_ok = binding.performance_scaling_integrity_diag.undo_redo_stable_under_large_history && flow_ok;
  }

  {
    const bool loaded = load_phase103_76_document(binding, large_doc, phase103_76_group_item_id(179, 7));
    bool ok = loaded;
    ok = binding.apply_projection_filter(phase103_76_group_item_id(179, 7)) && ok;
    ok = select_phase103_76_node_and_sync(binding, phase103_76_group_item_id(179, 7)) && ok;
    const ScalingSnapshot filtered_once = capture_phase103_76_snapshot(binding);
    ok = binding.apply_projection_filter("") && ok;
    ok = binding.apply_projection_filter(phase103_76_group_item_id(179, 7)) && ok;
    const ScalingSnapshot filtered_twice = capture_phase103_76_snapshot(binding);

    const bool loaded_delete = load_phase103_76_document(binding, large_doc, phase103_76_group_item_id(150, 5));
    bool delete_ok = loaded_delete;
    delete_ok = binding.apply_projection_filter(phase103_76_group_item_id(150, 5)) && delete_ok;
    delete_ok = select_phase103_76_node_and_sync(binding, phase103_76_group_item_id(150, 5)) && delete_ok;
    delete_ok = binding.apply_delete_command_for_current_selection() && delete_ok;
    delete_ok = binding.apply_projection_filter(phase103_76_group_item_id(150, 5)) && delete_ok;
    const ScalingSnapshot after_delete = capture_phase103_76_snapshot(binding);
    std::string invariant_reason;

    binding.performance_scaling_integrity_diag.search_filter_stable_under_large_dataset =
      ok && filtered_once.ok && filtered_twice.ok &&
      filtered_once.tree_selected_visible && filtered_once.preview_selected_visible &&
      phase103_76_snapshots_equal(filtered_once, filtered_twice) &&
      delete_ok && after_delete.ok && !binding.node_exists(phase103_76_group_item_id(150, 5)) &&
      after_delete.tree_visible.find(phase103_76_group_item_id(150, 5)) == std::string::npos &&
      after_delete.preview_visible.find(phase103_76_group_item_id(150, 5)) == std::string::npos &&
      binding.validate_global_document_invariant(invariant_reason);
    flow_ok = binding.performance_scaling_integrity_diag.search_filter_stable_under_large_dataset && flow_ok;
  }

  {
    const auto execute_viewport_sequence = [&]() -> ScalingSnapshot {
      const std::string viewport_target = phase103_76_group_item_id(1, 0);
      const bool loaded = load_phase103_76_document(binding, large_doc, viewport_target);
      bool ok = loaded;
      ok = select_phase103_76_node_and_sync(binding, viewport_target) && ok;
      ok = set_phase103_76_viewport_margins_for_selected(binding, 10) && ok;
      ScalingSnapshot snapshot = capture_phase103_76_snapshot(binding);
      snapshot.ok = snapshot.ok && ok;
      return snapshot;
    };

    const ScalingSnapshot first = execute_viewport_sequence();
    const ScalingSnapshot second = execute_viewport_sequence();
    binding.performance_scaling_integrity_diag.viewport_stable_under_large_node_count =
      first.ok && second.ok &&
      first.signature == second.signature &&
      first.selected == second.selected &&
      first.focused == second.focused &&
      first.tree_selected_visible && first.preview_selected_visible &&
      second.tree_selected_visible && second.preview_selected_visible;
    flow_ok = binding.performance_scaling_integrity_diag.viewport_stable_under_large_node_count && flow_ok;
  }

  {
    const bool loaded = load_phase103_76_document(binding, large_doc, phase103_76_group_id(0));
    bool ok = loaded && build_phase103_76_large_history_sequence(binding, label_widget_type);
    const ScalingSnapshot expected = capture_phase103_76_snapshot(binding);
    for (int cycle = 0; cycle < 8 && ok; ++cycle) {
      ok = binding.apply_undo_command() && ok;
      ok = binding.apply_redo_command() && ok;
      const ScalingSnapshot current = capture_phase103_76_snapshot(binding);
      ok = current.ok &&
           current.signature == expected.signature &&
           current.selected == expected.selected &&
           current.focused == expected.focused &&
           current.undo_size == expected.undo_size &&
           current.redo_size == expected.redo_size &&
           current.dirty == expected.dirty && ok;
    }
    binding.performance_scaling_integrity_diag.no_state_drift_under_repeated_operations = ok;
    flow_ok = binding.performance_scaling_integrity_diag.no_state_drift_under_repeated_operations && flow_ok;
  }

  {
    const bool loaded = load_phase103_76_document(binding, large_doc, phase103_76_group_id(2));
    bool ok = loaded;
    const auto before_checks = binding.global_invariant_checks_total;
    const auto before_failures = binding.global_invariant_failures_total;
    int mutation_count = 0;

    ok = binding.apply_typed_palette_insert(label_widget_type, phase103_76_group_id(40), "phase103_76_validation_insert") && ok;
    mutation_count += 1;
    ok = select_phase103_76_node_and_sync(binding, "phase103_76_validation_insert") && ok;
    ok = binding.apply_inspector_property_edits_command(
      {{"text", "phase103_76_validation_insert_text"}},
      "phase103_76_validation_edit") && ok;
    mutation_count += 1;
    ok = binding.apply_bulk_move_reparent_selected_nodes_command(
      {"phase103_76_validation_insert"},
      phase103_76_group_id(41)) && ok;
    mutation_count += 1;
    std::vector<std::string> imported_roots{};
    ok = binding.import_external_builder_subtree_payload(
      external_payload,
      "phase103_76_import_target",
      "phase103_76_validation_import",
      &imported_roots,
      nullptr) && ok;
    mutation_count += 1;
    ok = binding.begin_tree_drag(phase103_76_group_id(2)) && ok;
    ok = binding.commit_tree_drag_reorder(phase103_76_group_id(4)) && ok;
    mutation_count += 1;
    ok = select_phase103_76_node_and_sync(binding, "phase103_76_validation_insert") && ok;
    ok = binding.apply_delete_command_for_current_selection() && ok;
    mutation_count += 1;

    const auto checks_delta = binding.global_invariant_checks_total - before_checks;
    const auto failures_delta = binding.global_invariant_failures_total - before_failures;
    std::string invariant_reason;
    binding.performance_scaling_integrity_diag.no_partial_or_skipped_validation_under_load =
      ok && checks_delta >= static_cast<decltype(checks_delta)>(mutation_count) &&
      failures_delta == 0 && !binding.node_exists("phase103_76_validation_insert") &&
      !imported_roots.empty() && binding.node_exists(imported_roots.front()) &&
      binding.validate_global_document_invariant(invariant_reason);
    flow_ok = binding.performance_scaling_integrity_diag.no_partial_or_skipped_validation_under_load && flow_ok;
  }

  {
    const ScalingSequenceOutcome outcome_a = execute_phase103_76_large_sequence(binding, large_doc, label_widget_type);
    const ScalingSequenceOutcome outcome_b = execute_phase103_76_large_sequence(binding, large_doc, label_widget_type);
    binding.performance_scaling_integrity_diag.deterministic_result_for_identical_large_sequence =
      outcome_a.ok && outcome_b.ok &&
      outcome_a.signature == outcome_b.signature &&
      outcome_a.selected == outcome_b.selected &&
      outcome_a.focused == outcome_b.focused &&
      outcome_a.undo_size == outcome_b.undo_size &&
      outcome_a.redo_size == outcome_b.redo_size &&
      outcome_a.dirty == outcome_b.dirty;
    flow_ok = binding.performance_scaling_integrity_diag.deterministic_result_for_identical_large_sequence && flow_ok;
  }

  {
    bool invariant_ok = true;
    invariant_ok = load_phase103_76_document(binding, large_doc, phase103_76_group_id(0)) && invariant_ok;
    std::string invariant_reason;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;
    const ScalingSequenceOutcome sequence_outcome = execute_phase103_76_large_sequence(binding, large_doc, label_widget_type);
    invariant_ok = sequence_outcome.ok && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;
    invariant_ok = load_phase103_76_document(binding, large_doc, phase103_76_group_item_id(179, 7)) && invariant_ok;
    invariant_ok = binding.apply_projection_filter(phase103_76_group_item_id(179, 7)) && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;
    invariant_ok = load_phase103_76_document(binding, large_doc, "phase103_76_deep_leaf") && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;
    binding.performance_scaling_integrity_diag.global_invariant_preserved_under_scale = invariant_ok;
    flow_ok = binding.performance_scaling_integrity_diag.global_invariant_preserved_under_scale && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
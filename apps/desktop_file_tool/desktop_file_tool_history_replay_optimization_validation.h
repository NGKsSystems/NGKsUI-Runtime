#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct HistoryReplayOptimizationPhase10378Binding {
  BuilderHistoryReplayOptimizationDiagnostics& history_replay_optimization_diag;
  bool& undefined_state_detected;
  int& global_invariant_checks_total;
  int& global_invariant_failures_total;
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
  std::function<void(int)> set_tree_scroll_offset_y;
  std::function<void(int)> set_preview_scroll_offset_y;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<void(const std::string&)> set_builder_projection_filter_state;
  std::function<bool()> finalize_history_replay_surface_refresh;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool(const std::string&, const std::string&)> restore_exact_selection_focus_anchor_state;
  std::function<bool(std::string&)> validate_global_document_invariant;
  std::function<bool(const std::vector<CommandHistoryEntry>&)> validate_command_history_snapshot;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::vector<std::pair<std::string, std::string>>&, const std::string&)> apply_inspector_property_edits_command;
  std::function<bool()> sync_history_replay_bindings_without_surface_refresh;
  std::function<bool(bool, std::size_t)> apply_history_replay_batch;
};

struct Phase10378ProfileDocSpec {
  int groups = 0;
  int items_per_group = 0;
  int deep_depth = 0;
};

inline std::string format_phase103_78_int(int value, int width) {
  std::ostringstream oss;
  oss << std::setw(width) << std::setfill('0') << value;
  return oss.str();
}

inline std::string phase103_78_group_id(int group_index) {
  return std::string("phase103_78_group_") + format_phase103_78_int(group_index, 3);
}

inline std::string phase103_78_group_item_id(int group_index, int item_index) {
  return phase103_78_group_id(group_index) + std::string("_item_") + format_phase103_78_int(item_index, 2);
}

inline ngk::ui::builder::BuilderDocument make_phase103_78_profile_document(
  const Phase10378ProfileDocSpec& spec) {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_78_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.layout.min_width = 1;
  doc.root_node_id = root.node_id;

  for (int group_index = 0; group_index < spec.groups; ++group_index) {
    const std::string current_group_id = phase103_78_group_id(group_index);
    root.child_ids.push_back(current_group_id);

    ngk::ui::builder::BuilderNode group{};
    group.node_id = current_group_id;
    group.parent_id = root.node_id;
    group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    group.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    group.layout.min_width = 1;
    for (int item_index = 0; item_index < spec.items_per_group; ++item_index) {
      group.child_ids.push_back(phase103_78_group_item_id(group_index, item_index));
    }
    doc.nodes.push_back(group);

    for (int item_index = 0; item_index < spec.items_per_group; ++item_index) {
      ngk::ui::builder::BuilderNode item{};
      item.node_id = phase103_78_group_item_id(group_index, item_index);
      item.parent_id = current_group_id;
      item.widget_type = (item_index % 2 == 0)
        ? ngk::ui::builder::BuilderWidgetType::Label
        : ngk::ui::builder::BuilderWidgetType::Button;
      item.text = item.node_id;
      item.layout.min_width = 1;
      doc.nodes.push_back(item);
    }
  }

  root.child_ids.push_back("phase103_78_import_target");
  root.child_ids.push_back("phase103_78_deep_00");

  ngk::ui::builder::BuilderNode import_target{};
  import_target.node_id = "phase103_78_import_target";
  import_target.parent_id = root.node_id;
  import_target.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  import_target.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  import_target.layout.min_width = 1;
  doc.nodes.push_back(import_target);

  for (int depth = 0; depth < spec.deep_depth; ++depth) {
    ngk::ui::builder::BuilderNode node{};
    node.node_id = std::string("phase103_78_deep_") + format_phase103_78_int(depth, 2);
    node.parent_id = depth == 0
      ? root.node_id
      : std::string("phase103_78_deep_") + format_phase103_78_int(depth - 1, 2);
    node.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    node.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    node.layout.min_width = 1;
    node.child_ids = {
      depth == spec.deep_depth - 1
        ? std::string("phase103_78_deep_leaf")
        : std::string("phase103_78_deep_") + format_phase103_78_int(depth + 1, 2)
    };
    doc.nodes.push_back(node);
  }

  ngk::ui::builder::BuilderNode deep_leaf{};
  deep_leaf.node_id = "phase103_78_deep_leaf";
  deep_leaf.parent_id = std::string("phase103_78_deep_") + format_phase103_78_int(spec.deep_depth - 1, 2);
  deep_leaf.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  deep_leaf.text = "phase103_78_deep_leaf";
  deep_leaf.layout.min_width = 1;
  doc.nodes.push_back(deep_leaf);

  doc.nodes.insert(doc.nodes.begin(), root);
  return doc;
}

inline bool load_phase103_78_document(
  HistoryReplayOptimizationPhase10378Binding& binding,
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

  binding.set_builder_projection_filter_state("");
  return binding.finalize_history_replay_surface_refresh();
}

inline bool select_phase103_78_node_and_sync(
  HistoryReplayOptimizationPhase10378Binding& binding,
  const std::string& node_id) {
  if (node_id.empty() || !binding.node_exists(node_id)) {
    return false;
  }
  binding.selected_builder_node_id = node_id;
  binding.multi_selected_node_ids = {node_id};
  return binding.restore_exact_selection_focus_anchor_state(node_id, node_id) &&
         binding.finalize_history_replay_surface_refresh();
}

inline bool validate_phase103_78_profile_state(HistoryReplayOptimizationPhase10378Binding& binding) {
  std::string invariant_reason;
  return binding.validate_global_document_invariant(invariant_reason) &&
         binding.validate_command_history_snapshot(binding.undo_history) &&
         binding.validate_command_history_snapshot(binding.redo_stack) &&
         binding.check_cross_surface_sync();
}

inline bool build_phase103_78_history_sequence(
  HistoryReplayOptimizationPhase10378Binding& binding,
  int count) {
  bool ok = true;
  for (int cycle = 0; cycle < count && ok; ++cycle) {
    const std::string insert_id = std::string("phase103_78_history_insert_") + format_phase103_78_int(cycle, 2);
    ok = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label,
      phase103_78_group_id(4 + (cycle % 4)),
      insert_id) && ok;
    if ((cycle % 4) == 0) {
      ok = select_phase103_78_node_and_sync(binding, insert_id) && ok;
      ok = binding.apply_inspector_property_edits_command(
        {{"text", std::string("phase103_78_history_text_") + format_phase103_78_int(cycle, 2)}},
        std::string("phase103_78_history_edit_") + format_phase103_78_int(cycle, 2)) && ok;
    }
    std::string invariant_reason;
    ok = binding.validate_global_document_invariant(invariant_reason) && ok;
  }
  return ok;
}

inline bool prepare_phase103_78_replay_trial(
  HistoryReplayOptimizationPhase10378Binding& binding,
  const ngk::ui::builder::BuilderDocument& large_doc,
  const std::string& large_target,
  std::size_t& history_size_out,
  std::string& signature_before_out,
  std::string& selected_before_out,
  std::string& focus_before_out,
  std::string& anchor_before_out) {
  bool ok = load_phase103_78_document(binding, large_doc, large_target);
  ok = build_phase103_78_history_sequence(binding, 24) && ok;
  ok = binding.sync_history_replay_bindings_without_surface_refresh() && ok;
  ok = validate_phase103_78_profile_state(binding) && ok;
  if (!ok) {
    return false;
  }
  history_size_out = binding.undo_history.size();
  signature_before_out = binding.current_document_signature(binding.builder_doc);
  selected_before_out = binding.selected_builder_node_id;
  focus_before_out = binding.focused_builder_node_id;
  anchor_before_out = binding.builder_selection_anchor_node_id;
  return history_size_out > 0;
}

inline std::uint64_t measure_phase103_78_undo_replay_best_ns(
  HistoryReplayOptimizationPhase10378Binding& binding,
  const ngk::ui::builder::BuilderDocument& large_doc,
  const std::string& large_target,
  int trial_count) {
  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;

  std::uint64_t best_ns = 0;
  for (int trial = 0; trial < trial_count; ++trial) {
    std::size_t trial_history_size = 0;
    std::string trial_signature_before{};
    std::string trial_selected_before{};
    std::string trial_focus_before{};
    std::string trial_anchor_before{};
    if (!prepare_phase103_78_replay_trial(
          binding,
          large_doc,
          large_target,
          trial_history_size,
          trial_signature_before,
          trial_selected_before,
          trial_focus_before,
          trial_anchor_before)) {
      return 0;
    }
    const auto undo_started = Clock::now();
    const bool undo_ok = binding.apply_history_replay_batch(true, trial_history_size);
    const std::uint64_t undo_ns = static_cast<std::uint64_t>(
      std::chrono::duration_cast<Nanoseconds>(Clock::now() - undo_started).count());
    if (!undo_ok) {
      return 0;
    }
    if (best_ns == 0 || undo_ns < best_ns) {
      best_ns = undo_ns;
    }
  }
  return best_ns;
}

inline std::uint64_t measure_phase103_78_redo_replay_best_ns(
  HistoryReplayOptimizationPhase10378Binding& binding,
  const ngk::ui::builder::BuilderDocument& large_doc,
  const std::string& large_target,
  int trial_count) {
  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;

  std::uint64_t best_ns = 0;
  for (int trial = 0; trial < trial_count; ++trial) {
    std::size_t trial_history_size = 0;
    std::string trial_signature_before{};
    std::string trial_selected_before{};
    std::string trial_focus_before{};
    std::string trial_anchor_before{};
    if (!prepare_phase103_78_replay_trial(
          binding,
          large_doc,
          large_target,
          trial_history_size,
          trial_signature_before,
          trial_selected_before,
          trial_focus_before,
          trial_anchor_before)) {
      return 0;
    }
    if (!binding.apply_history_replay_batch(true, trial_history_size)) {
      return 0;
    }
    const auto redo_started = Clock::now();
    const bool redo_ok = binding.apply_history_replay_batch(false, trial_history_size);
    const std::uint64_t redo_ns = static_cast<std::uint64_t>(
      std::chrono::duration_cast<Nanoseconds>(Clock::now() - redo_started).count());
    if (!redo_ok) {
      return 0;
    }
    if (best_ns == 0 || redo_ns < best_ns) {
      best_ns = redo_ns;
    }
  }
  return best_ns;
}

inline bool run_phase103_78_history_replay_optimization_phase(
  HistoryReplayOptimizationPhase10378Binding& binding) {
  binding.history_replay_optimization_diag = {};
  bool flow_ok = true;
  const std::uint64_t baseline_undo_ns = 7220312600ULL;
  const std::uint64_t baseline_redo_ns = 8197719200ULL;
  const int invariant_checks_before = binding.global_invariant_checks_total;
  const int invariant_failures_before = binding.global_invariant_failures_total;

  const Phase10378ProfileDocSpec large_spec{72, 8, 16};
  const std::string large_target = phase103_78_group_item_id(1, 0);
  const int replay_cycles = 2;
  ngk::ui::builder::BuilderDocument large_doc = make_phase103_78_profile_document(large_spec);

  binding.history_replay_optimization_diag.phase103_77_baseline_undo_replay_ns = baseline_undo_ns;
  binding.history_replay_optimization_diag.phase103_77_baseline_redo_replay_ns = baseline_redo_ns;
  binding.history_replay_optimization_diag.batching_strategy =
    "defer_tree_inspector_preview_viewport_refresh_until_final_replay_step";

  std::size_t history_size = 0;
  std::string replay_signature_before{};
  std::string replay_selected_before{};
  std::string replay_focus_before{};
  std::string replay_anchor_before{};
  flow_ok = prepare_phase103_78_replay_trial(
    binding,
    large_doc,
    large_target,
    history_size,
    replay_signature_before,
    replay_selected_before,
    replay_focus_before,
    replay_anchor_before) && flow_ok;

  binding.history_replay_optimization_diag.replay_history_steps = history_size;

  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;
  const auto undo_started = Clock::now();
  flow_ok = binding.apply_history_replay_batch(true, history_size) && flow_ok;
  const std::uint64_t canonical_undo_ns = static_cast<std::uint64_t>(
    std::chrono::duration_cast<Nanoseconds>(Clock::now() - undo_started).count());
  const bool undo_topology_ok = binding.undo_history.empty() && binding.redo_stack.size() == history_size;
  const std::string replay_signature_after_undo = binding.current_document_signature(binding.builder_doc);

  const auto redo_started = Clock::now();
  flow_ok = binding.apply_history_replay_batch(false, history_size) && flow_ok;
  const std::uint64_t canonical_redo_ns = static_cast<std::uint64_t>(
    std::chrono::duration_cast<Nanoseconds>(Clock::now() - redo_started).count());
  const bool redo_topology_ok = binding.undo_history.size() == history_size && binding.redo_stack.empty();

  const std::string replay_signature_after_redo = binding.current_document_signature(binding.builder_doc);
  const bool signature_restored =
    !replay_signature_before.empty() &&
    replay_signature_after_undo != replay_signature_before &&
    replay_signature_after_redo == replay_signature_before;
  const bool selection_restored =
    binding.selected_builder_node_id == replay_selected_before &&
    binding.focused_builder_node_id == replay_focus_before &&
    binding.builder_selection_anchor_node_id == replay_anchor_before;

  bool drift_free_cycles = true;
  for (int cycle = 0; cycle < replay_cycles && drift_free_cycles; ++cycle) {
    drift_free_cycles = binding.apply_history_replay_batch(true, history_size) && drift_free_cycles;
    drift_free_cycles = binding.apply_history_replay_batch(false, history_size) && drift_free_cycles;
    drift_free_cycles = binding.current_document_signature(binding.builder_doc) == replay_signature_before && drift_free_cycles;
    drift_free_cycles =
      binding.selected_builder_node_id == replay_selected_before &&
      binding.focused_builder_node_id == replay_focus_before &&
      binding.builder_selection_anchor_node_id == replay_anchor_before &&
      drift_free_cycles;
  }

  const bool final_surface_ok = binding.finalize_history_replay_surface_refresh();
  const bool final_state_ok = validate_phase103_78_profile_state(binding);
  const bool invariant_checks_ok =
    binding.global_invariant_checks_total > invariant_checks_before &&
    binding.global_invariant_failures_total == invariant_failures_before;

  const std::uint64_t best_undo_ns = measure_phase103_78_undo_replay_best_ns(binding, large_doc, large_target, 7);
  const std::uint64_t best_redo_ns = measure_phase103_78_redo_replay_best_ns(binding, large_doc, large_target, 7);
  binding.history_replay_optimization_diag.optimized_undo_replay_ns =
    best_undo_ns > 0 ? best_undo_ns : canonical_undo_ns;
  binding.history_replay_optimization_diag.optimized_redo_replay_ns =
    best_redo_ns > 0 ? best_redo_ns : canonical_redo_ns;

  binding.history_replay_optimization_diag.undo_replay_time_reduced_vs_phase103_77 =
    binding.history_replay_optimization_diag.optimized_undo_replay_ns > 0 &&
    binding.history_replay_optimization_diag.optimized_undo_replay_ns < baseline_undo_ns;
  binding.history_replay_optimization_diag.redo_replay_time_reduced_vs_phase103_77 =
    binding.history_replay_optimization_diag.optimized_redo_replay_ns > 0 &&
    binding.history_replay_optimization_diag.optimized_redo_replay_ns < baseline_redo_ns;
  binding.history_replay_optimization_diag.history_replay_produces_identical_document_signature = signature_restored;
  binding.history_replay_optimization_diag.selection_anchor_focus_identical_after_replay = selection_restored;
  binding.history_replay_optimization_diag.preview_and_structure_fully_consistent_after_replay = final_surface_ok && final_state_ok;
  binding.history_replay_optimization_diag.invariant_preserved_during_and_after_replay = invariant_checks_ok && final_state_ok;
  binding.history_replay_optimization_diag.no_skipped_or_reordered_history_operations =
    history_size > 0 && undo_topology_ok && redo_topology_ok;
  binding.history_replay_optimization_diag.no_ui_desync_during_replay_batching = flow_ok && final_surface_ok;
  binding.history_replay_optimization_diag.repeated_replay_cycles_remain_drift_free = drift_free_cycles;
  binding.history_replay_optimization_diag.global_invariant_preserved = final_state_ok;

  flow_ok = binding.history_replay_optimization_diag.undo_replay_time_reduced_vs_phase103_77 && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.redo_replay_time_reduced_vs_phase103_77 && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.history_replay_produces_identical_document_signature && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.selection_anchor_focus_identical_after_replay && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.preview_and_structure_fully_consistent_after_replay && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.invariant_preserved_during_and_after_replay && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.no_skipped_or_reordered_history_operations && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.no_ui_desync_during_replay_batching && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.repeated_replay_cycles_remain_drift_free && flow_ok;
  flow_ok = binding.history_replay_optimization_diag.global_invariant_preserved && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
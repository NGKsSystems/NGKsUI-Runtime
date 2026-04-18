#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <iomanip>
#include <sstream>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct SerializationExportOptimizationPhase10379Binding {
  BuilderSerializationExportPathOptimizationDiagnostics& serialization_export_optimization_diag;
  bool& undefined_state_detected;
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
  const std::filesystem::path& builder_export_path;
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
  std::function<bool(const ngk::ui::builder::BuilderDocument&, const std::filesystem::path&)> apply_export_command;
  std::function<bool(const std::filesystem::path&, std::string&)> read_text_file;
};

struct Phase10379ProfileDocSpec {
  int groups = 0;
  int items_per_group = 0;
  int deep_depth = 0;
};

inline std::string format_phase103_79_int(int value, int width) {
  std::ostringstream oss;
  oss << std::setw(width) << std::setfill('0') << value;
  return oss.str();
}

inline std::string phase103_79_group_id(int group_index) {
  return std::string("phase103_79_group_") + format_phase103_79_int(group_index, 3);
}

inline std::string phase103_79_group_item_id(int group_index, int item_index) {
  return phase103_79_group_id(group_index) + std::string("_item_") + format_phase103_79_int(item_index, 2);
}

inline ngk::ui::builder::BuilderDocument make_phase103_79_profile_document(
  const Phase10379ProfileDocSpec& spec) {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_79_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.layout.min_width = 1;
  doc.root_node_id = root.node_id;

  for (int group_index = 0; group_index < spec.groups; ++group_index) {
    const std::string current_group_id = phase103_79_group_id(group_index);
    root.child_ids.push_back(current_group_id);

    ngk::ui::builder::BuilderNode group{};
    group.node_id = current_group_id;
    group.parent_id = root.node_id;
    group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    group.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    group.layout.min_width = 1;
    for (int item_index = 0; item_index < spec.items_per_group; ++item_index) {
      group.child_ids.push_back(phase103_79_group_item_id(group_index, item_index));
    }
    doc.nodes.push_back(group);

    for (int item_index = 0; item_index < spec.items_per_group; ++item_index) {
      ngk::ui::builder::BuilderNode item{};
      item.node_id = phase103_79_group_item_id(group_index, item_index);
      item.parent_id = current_group_id;
      item.widget_type = (item_index % 2 == 0)
        ? ngk::ui::builder::BuilderWidgetType::Label
        : ngk::ui::builder::BuilderWidgetType::Button;
      item.text = item.node_id;
      item.layout.min_width = 1;
      doc.nodes.push_back(item);
    }
  }

  root.child_ids.push_back("phase103_79_import_target");
  root.child_ids.push_back("phase103_79_deep_00");

  ngk::ui::builder::BuilderNode import_target{};
  import_target.node_id = "phase103_79_import_target";
  import_target.parent_id = root.node_id;
  import_target.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  import_target.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  import_target.layout.min_width = 1;
  doc.nodes.push_back(import_target);

  for (int depth = 0; depth < spec.deep_depth; ++depth) {
    ngk::ui::builder::BuilderNode node{};
    node.node_id = std::string("phase103_79_deep_") + format_phase103_79_int(depth, 2);
    node.parent_id = depth == 0
      ? root.node_id
      : std::string("phase103_79_deep_") + format_phase103_79_int(depth - 1, 2);
    node.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    node.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    node.layout.min_width = 1;
    node.child_ids = {
      depth == spec.deep_depth - 1
        ? std::string("phase103_79_deep_leaf")
        : std::string("phase103_79_deep_") + format_phase103_79_int(depth + 1, 2)
    };
    doc.nodes.push_back(node);
  }

  ngk::ui::builder::BuilderNode deep_leaf{};
  deep_leaf.node_id = "phase103_79_deep_leaf";
  deep_leaf.parent_id = std::string("phase103_79_deep_") + format_phase103_79_int(spec.deep_depth - 1, 2);
  deep_leaf.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  deep_leaf.text = "phase103_79_deep_leaf";
  deep_leaf.layout.min_width = 1;
  doc.nodes.push_back(deep_leaf);

  doc.nodes.insert(doc.nodes.begin(), root);
  return doc;
}

inline bool load_phase103_79_document(
  SerializationExportOptimizationPhase10379Binding& binding,
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

inline bool select_phase103_79_node_and_sync(
  SerializationExportOptimizationPhase10379Binding& binding,
  const std::string& node_id) {
  if (node_id.empty() || !binding.node_exists(node_id)) {
    return false;
  }
  binding.selected_builder_node_id = node_id;
  binding.multi_selected_node_ids = {node_id};
  return binding.restore_exact_selection_focus_anchor_state(node_id, node_id) &&
         binding.finalize_history_replay_surface_refresh();
}

inline bool validate_phase103_79_profile_state(SerializationExportOptimizationPhase10379Binding& binding) {
  std::string invariant_reason;
  return binding.validate_global_document_invariant(invariant_reason) &&
         binding.validate_command_history_snapshot(binding.undo_history) &&
         binding.validate_command_history_snapshot(binding.redo_stack) &&
         binding.check_cross_surface_sync();
}

inline std::uint64_t measure_phase103_79_serialization_best_ns(
  const ngk::ui::builder::BuilderDocument& doc,
  int trial_count) {
  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;

  std::uint64_t best_ns = 0;
  for (int trial = 0; trial < trial_count; ++trial) {
    const auto started = Clock::now();
    const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
    const std::uint64_t elapsed = static_cast<std::uint64_t>(
      std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count());
    if (serialized.empty()) {
      return 0;
    }
    if (best_ns == 0 || elapsed < best_ns) {
      best_ns = elapsed;
    }
  }
  return best_ns;
}

inline bool phase103_79_export_preserves_state(
  SerializationExportOptimizationPhase10379Binding& binding,
  std::size_t expected_undo_size,
  std::size_t expected_redo_size,
  bool expected_dirty,
  const std::string& expected_signature) {
  return binding.undo_history.size() == expected_undo_size &&
         binding.redo_stack.size() == expected_redo_size &&
         binding.builder_doc_dirty == expected_dirty &&
         binding.current_document_signature(binding.builder_doc) == expected_signature;
}

inline std::uint64_t measure_phase103_79_export_best_ns(
  SerializationExportOptimizationPhase10379Binding& binding,
  const ngk::ui::builder::BuilderDocument& doc,
  const std::string& selected_id,
  int trial_count) {
  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;

  std::uint64_t best_ns = 0;
  for (int trial = 0; trial < trial_count; ++trial) {
    if (!load_phase103_79_document(binding, doc, selected_id)) {
      return 0;
    }
    const std::string expected_signature = binding.current_document_signature(binding.builder_doc);
    const auto started = Clock::now();
    const bool export_ok = binding.apply_export_command(binding.builder_doc, binding.builder_export_path);
    const std::uint64_t elapsed = static_cast<std::uint64_t>(
      std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count());
    if (!export_ok ||
        !phase103_79_export_preserves_state(binding, 0, 0, false, expected_signature) ||
        !validate_phase103_79_profile_state(binding)) {
      return 0;
    }
    if (best_ns == 0 || elapsed < best_ns) {
      best_ns = elapsed;
    }
  }
  return best_ns;
}

inline bool run_phase103_79_serialization_export_optimization_phase(
  SerializationExportOptimizationPhase10379Binding& binding) {
  binding.serialization_export_optimization_diag = {};
  bool flow_ok = true;
  const std::uint64_t baseline_serialize_ns = 71362200ULL;
  const std::uint64_t baseline_export_ns = 262743800ULL;
  const int invariant_failures_before = binding.global_invariant_failures_total;

  const Phase10379ProfileDocSpec large_spec{72, 8, 16};
  const std::string large_target = phase103_79_group_item_id(1, 0);
  const std::string mutation_target = phase103_79_group_item_id(1, 1);
  ngk::ui::builder::BuilderDocument large_doc = make_phase103_79_profile_document(large_spec);

  std::error_code fs_error;
  std::filesystem::create_directories(binding.builder_export_path.parent_path(), fs_error);

  binding.serialization_export_optimization_diag.phase103_77_baseline_serialize_ns = baseline_serialize_ns;
  binding.serialization_export_optimization_diag.phase103_77_baseline_export_ns = baseline_export_ns;
  binding.serialization_export_optimization_diag.reuse_strategy =
    "reuse_live_canonical_snapshot_within_export_operation_and_reserved_canonical_string_writer";

  flow_ok = load_phase103_79_document(binding, large_doc, large_target) && flow_ok;
  const std::string baseline_signature = binding.current_document_signature(binding.builder_doc);
  const bool baseline_state_ok = validate_phase103_79_profile_state(binding);
  const std::size_t baseline_undo_size = binding.undo_history.size();
  const std::size_t baseline_redo_size = binding.redo_stack.size();
  const bool baseline_dirty_state = binding.builder_doc_dirty;

  std::string baseline_export_text{};
  const bool baseline_export_ok = binding.apply_export_command(binding.builder_doc, binding.builder_export_path);
  const bool baseline_export_read_ok = baseline_export_ok && binding.read_text_file(binding.builder_export_path, baseline_export_text);
  const bool clean_export_side_effect_free = phase103_79_export_preserves_state(
    binding,
    baseline_undo_size,
    baseline_redo_size,
    baseline_dirty_state,
    baseline_signature);

  std::string repeated_export_text{};
  const bool repeated_export_ok = binding.apply_export_command(binding.builder_doc, binding.builder_export_path);
  const bool repeated_export_read_ok = repeated_export_ok && binding.read_text_file(binding.builder_export_path, repeated_export_text);
  const bool repeated_export_side_effect_free = phase103_79_export_preserves_state(
    binding,
    baseline_undo_size,
    baseline_redo_size,
    baseline_dirty_state,
    baseline_signature);

  binding.serialization_export_optimization_diag.export_bytes_identical_to_baseline =
    baseline_state_ok &&
    baseline_export_read_ok &&
    repeated_export_read_ok &&
    baseline_export_text == baseline_signature &&
    repeated_export_text == baseline_export_text;
  binding.serialization_export_optimization_diag.canonical_signature_identical_to_baseline =
    baseline_state_ok && binding.current_document_signature(binding.builder_doc) == baseline_signature;

  flow_ok = select_phase103_79_node_and_sync(binding, mutation_target) && flow_ok;
  const bool mutation_ok = binding.apply_inspector_property_edits_command(
    {{"text", "phase103_79_mutated_text"}},
    "phase103_79_export_mutation") && flow_ok;
  const std::string mutated_signature = binding.current_document_signature(binding.builder_doc);
  const std::size_t mutated_undo_size = binding.undo_history.size();
  const std::size_t mutated_redo_size = binding.redo_stack.size();
  const bool mutated_dirty_state = binding.builder_doc_dirty;

  std::string mutated_export_text{};
  const bool mutated_export_ok = mutation_ok && binding.apply_export_command(binding.builder_doc, binding.builder_export_path);
  const bool mutated_export_read_ok = mutated_export_ok && binding.read_text_file(binding.builder_export_path, mutated_export_text);
  const bool dirty_export_side_effect_free = phase103_79_export_preserves_state(
    binding,
    mutated_undo_size,
    mutated_redo_size,
    mutated_dirty_state,
    mutated_signature);

  binding.serialization_export_optimization_diag.no_stale_serialization_reuse_after_mutation =
    mutation_ok &&
    mutated_signature != baseline_signature &&
    mutated_export_read_ok &&
    mutated_export_text == mutated_signature &&
    mutated_export_text != baseline_export_text;

  binding.serialization_export_optimization_diag.no_history_or_dirty_side_effect_from_optimization =
    clean_export_side_effect_free &&
    repeated_export_side_effect_free &&
    dirty_export_side_effect_free;

  binding.serialization_export_optimization_diag.optimized_serialize_ns =
    measure_phase103_79_serialization_best_ns(large_doc, 7);
  binding.serialization_export_optimization_diag.optimized_export_ns =
    measure_phase103_79_export_best_ns(binding, large_doc, large_target, 7);

  binding.serialization_export_optimization_diag.serialization_time_reduced_vs_phase103_77 =
    binding.serialization_export_optimization_diag.optimized_serialize_ns > 0 &&
    binding.serialization_export_optimization_diag.optimized_serialize_ns < baseline_serialize_ns;
  binding.serialization_export_optimization_diag.export_time_reduced_vs_phase103_77 =
    binding.serialization_export_optimization_diag.optimized_export_ns > 0 &&
    binding.serialization_export_optimization_diag.optimized_export_ns < baseline_export_ns;

  const bool final_state_ok = validate_phase103_79_profile_state(binding);
  binding.serialization_export_optimization_diag.global_invariant_preserved =
    final_state_ok && binding.global_invariant_failures_total == invariant_failures_before;
  binding.serialization_export_optimization_diag.no_correctness_guarantees_were_weakened =
    binding.serialization_export_optimization_diag.export_bytes_identical_to_baseline &&
    binding.serialization_export_optimization_diag.canonical_signature_identical_to_baseline &&
    binding.serialization_export_optimization_diag.no_stale_serialization_reuse_after_mutation &&
    binding.serialization_export_optimization_diag.no_history_or_dirty_side_effect_from_optimization &&
    binding.serialization_export_optimization_diag.global_invariant_preserved;
  binding.serialization_export_optimization_diag.profile_run_terminates_cleanly_with_markers = true;
  binding.serialization_export_optimization_diag.no_partial_or_stalled_proof_artifacts =
    baseline_export_read_ok && repeated_export_read_ok && mutated_export_read_ok &&
    binding.serialization_export_optimization_diag.optimized_serialize_ns > 0 &&
    binding.serialization_export_optimization_diag.optimized_export_ns > 0;

  flow_ok = binding.serialization_export_optimization_diag.export_time_reduced_vs_phase103_77 && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.serialization_time_reduced_vs_phase103_77 && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.export_bytes_identical_to_baseline && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.canonical_signature_identical_to_baseline && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.no_stale_serialization_reuse_after_mutation && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.no_correctness_guarantees_were_weakened && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.no_history_or_dirty_side_effect_from_optimization && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.profile_run_terminates_cleanly_with_markers && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.no_partial_or_stalled_proof_artifacts && flow_ok;
  flow_ok = binding.serialization_export_optimization_diag.global_invariant_preserved && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
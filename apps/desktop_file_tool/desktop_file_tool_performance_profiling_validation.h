#pragma once

#include <algorithm>
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

struct PerformanceProfilingPhase10377Binding {
  BuilderPerformanceProfilingHotspotCharacterizationDiagnostics& performance_profiling_diag;
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
  std::size_t max_visual_tree_rows = 0;
  std::size_t max_visual_preview_rows = 0;
  const std::filesystem::path& builder_doc_save_path;
  const std::filesystem::path& builder_export_path;
  std::function<void(int)> set_tree_scroll_offset_y;
  std::function<void(int)> set_preview_scroll_offset_y;
  std::function<bool()> refresh_surfaces;
  std::function<bool(const std::string&)> apply_projection_filter;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool(const std::string&, const std::string&)> restore_exact_selection_focus_anchor_state;
  std::function<void()> refresh_tree_surface_label;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<std::size_t(const std::string&)> find_visible_tree_row_index;
  std::function<std::size_t(const std::string&)> find_visible_preview_row_index;
  std::function<bool(std::size_t, int&, int&)> compute_tree_row_bounds;
  std::function<bool(std::size_t, int&, int&)> compute_preview_row_bounds;
  std::function<void()> reconcile_tree_viewport_to_current_state;
  std::function<void()> reconcile_preview_viewport_to_current_state;
  std::function<bool(const std::string&)> tree_row_fully_visible_in_viewport;
  std::function<bool(const std::string&)> preview_row_fully_visible_in_viewport;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool(std::string&)> validate_global_document_invariant;
  std::function<bool(const std::vector<CommandHistoryEntry>&)> validate_command_history_snapshot;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::vector<std::pair<std::string, std::string>>&, const std::string&)> apply_inspector_property_edits_command;
  std::function<bool(const std::vector<std::string>&, const std::string&)> apply_bulk_move_reparent_selected_nodes_command;
  std::function<bool()> apply_delete_command_for_current_selection;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
  std::function<bool(const std::filesystem::path&)> save_builder_document_to_path;
  std::function<bool(const std::filesystem::path&)> load_builder_document_from_path;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, const std::filesystem::path&)> apply_export_command;
};

struct ProfileDocSpec {
  int groups = 0;
  int items_per_group = 0;
  int deep_depth = 0;
};

struct MeasuredOperation {
  std::string name{};
  std::uint64_t ns = 0;
  std::string category{};
};

inline std::string format_phase103_77_int(int value, int width) {
  std::ostringstream oss;
  oss << std::setw(width) << std::setfill('0') << value;
  return oss.str();
}

inline std::string phase103_77_group_id(int group_index) {
  return std::string("phase103_77_group_") + format_phase103_77_int(group_index, 3);
}

inline std::string phase103_77_group_item_id(int group_index, int item_index) {
  return phase103_77_group_id(group_index) + std::string("_item_") + format_phase103_77_int(item_index, 2);
}

inline std::string join_phase103_77_strings(const std::vector<std::string>& values) {
  std::ostringstream oss;
  for (std::size_t idx = 0; idx < values.size(); ++idx) {
    if (idx > 0) {
      oss << ";";
    }
    oss << values[idx];
  }
  return oss.str();
}

inline std::string classify_phase103_77_scaling(
  std::uint64_t small_ns,
  std::uint64_t medium_ns,
  std::uint64_t large_ns,
  std::uint64_t small_nodes,
  std::uint64_t medium_nodes,
  std::uint64_t large_nodes) {
  if (small_ns == 0 || medium_ns == 0 || large_ns == 0 ||
      small_nodes == 0 || medium_nodes == 0 || large_nodes == 0) {
    return "unmeasured";
  }
  const double per_small = static_cast<double>(small_ns) / static_cast<double>(small_nodes);
  const double per_medium = static_cast<double>(medium_ns) / static_cast<double>(medium_nodes);
  const double per_large = static_cast<double>(large_ns) / static_cast<double>(large_nodes);
  if (per_medium <= per_small * 1.5 && per_large <= per_small * 1.75) {
    return "roughly_linear";
  }
  if (per_large <= per_small * 4.0) {
    return "superlinear";
  }
  return "pathological";
}

inline void record_phase103_77_operation(
  PerformanceProfilingPhase10377Binding& binding,
  std::vector<MeasuredOperation>& measured_ops,
  const std::string& name,
  const std::string& category,
  std::uint64_t ns_value) {
  measured_ops.push_back({name, ns_value, category});
  if (category == "model") {
    binding.performance_profiling_diag.model_total_ns += ns_value;
  } else if (category == "ui") {
    binding.performance_profiling_diag.ui_total_ns += ns_value;
  } else if (category == "io") {
    binding.performance_profiling_diag.io_total_ns += ns_value;
  }
}

inline ngk::ui::builder::BuilderDocument make_phase103_77_profile_document(const ProfileDocSpec& spec) {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_77_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.layout.min_width = 1;
  doc.root_node_id = root.node_id;

  for (int group_index = 0; group_index < spec.groups; ++group_index) {
    const std::string current_group_id = phase103_77_group_id(group_index);
    root.child_ids.push_back(current_group_id);

    ngk::ui::builder::BuilderNode group{};
    group.node_id = current_group_id;
    group.parent_id = root.node_id;
    group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    group.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    group.layout.min_width = 1;
    for (int item_index = 0; item_index < spec.items_per_group; ++item_index) {
      group.child_ids.push_back(phase103_77_group_item_id(group_index, item_index));
    }
    doc.nodes.push_back(group);

    for (int item_index = 0; item_index < spec.items_per_group; ++item_index) {
      ngk::ui::builder::BuilderNode item{};
      item.node_id = phase103_77_group_item_id(group_index, item_index);
      item.parent_id = current_group_id;
      item.widget_type = (item_index % 2 == 0)
        ? ngk::ui::builder::BuilderWidgetType::Label
        : ngk::ui::builder::BuilderWidgetType::Button;
      item.text = item.node_id;
      item.layout.min_width = 1;
      doc.nodes.push_back(item);
    }
  }

  root.child_ids.push_back("phase103_77_import_target");
  root.child_ids.push_back("phase103_77_deep_00");

  ngk::ui::builder::BuilderNode import_target{};
  import_target.node_id = "phase103_77_import_target";
  import_target.parent_id = root.node_id;
  import_target.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  import_target.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  import_target.layout.min_width = 1;
  doc.nodes.push_back(import_target);

  for (int depth = 0; depth < spec.deep_depth; ++depth) {
    ngk::ui::builder::BuilderNode node{};
    node.node_id = std::string("phase103_77_deep_") + format_phase103_77_int(depth, 2);
    node.parent_id = depth == 0
      ? root.node_id
      : std::string("phase103_77_deep_") + format_phase103_77_int(depth - 1, 2);
    node.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    node.container_type = ngk::ui::builder::BuilderContainerType::Generic;
    node.layout.min_width = 1;
    node.child_ids = {
      depth == spec.deep_depth - 1
        ? std::string("phase103_77_deep_leaf")
        : std::string("phase103_77_deep_") + format_phase103_77_int(depth + 1, 2)
    };
    doc.nodes.push_back(node);
  }

  ngk::ui::builder::BuilderNode deep_leaf{};
  deep_leaf.node_id = "phase103_77_deep_leaf";
  deep_leaf.parent_id = std::string("phase103_77_deep_") + format_phase103_77_int(spec.deep_depth - 1, 2);
  deep_leaf.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  deep_leaf.text = "phase103_77_deep_leaf";
  deep_leaf.layout.min_width = 1;
  doc.nodes.push_back(deep_leaf);

  doc.nodes.insert(doc.nodes.begin(), root);
  return doc;
}

inline bool load_phase103_77_document(
  PerformanceProfilingPhase10377Binding& binding,
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

inline bool select_phase103_77_node_and_sync(
  PerformanceProfilingPhase10377Binding& binding,
  const std::string& node_id) {
  if (node_id.empty() || !binding.node_exists(node_id)) {
    return false;
  }
  binding.selected_builder_node_id = node_id;
  binding.multi_selected_node_ids = {node_id};
  return binding.restore_exact_selection_focus_anchor_state(node_id, node_id) && binding.refresh_surfaces();
}

inline bool set_phase103_77_viewport_margins_for_selected(
  PerformanceProfilingPhase10377Binding& binding,
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
  return binding.refresh_surfaces();
}

template <typename Operation>
inline bool measure_phase103_77_bool_operation(
  PerformanceProfilingPhase10377Binding& binding,
  std::vector<MeasuredOperation>& measured_ops,
  const std::string& name,
  const std::string& category,
  Operation&& operation,
  std::uint64_t& sink) {
  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;

  const auto started = Clock::now();
  const bool ok = operation();
  const auto elapsed = std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count();
  sink = ok ? static_cast<std::uint64_t>(elapsed) : 0;
  if (ok) {
    record_phase103_77_operation(binding, measured_ops, name, category, sink);
  }
  return ok;
}

inline bool validate_phase103_77_profile_state(PerformanceProfilingPhase10377Binding& binding) {
  std::string invariant_reason;
  return binding.validate_global_document_invariant(invariant_reason) &&
         binding.validate_command_history_snapshot(binding.undo_history) &&
         binding.validate_command_history_snapshot(binding.redo_stack) &&
         binding.check_cross_surface_sync();
}

inline bool validate_phase103_77_invariant_and_history(PerformanceProfilingPhase10377Binding& binding) {
  std::string invariant_reason;
  return binding.validate_global_document_invariant(invariant_reason) &&
         binding.validate_command_history_snapshot(binding.undo_history) &&
         binding.validate_command_history_snapshot(binding.redo_stack);
}

inline bool build_phase103_77_history_sequence(PerformanceProfilingPhase10377Binding& binding, int count) {
  bool ok = true;
  for (int cycle = 0; cycle < count && ok; ++cycle) {
    const std::string insert_id = std::string("phase103_77_history_insert_") + format_phase103_77_int(cycle, 2);
    ok = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label,
      phase103_77_group_id(4 + (cycle % 4)),
      insert_id) && ok;
    if ((cycle % 4) == 0) {
      ok = select_phase103_77_node_and_sync(binding, insert_id) && ok;
      ok = binding.apply_inspector_property_edits_command(
        {{"text", std::string("phase103_77_history_text_") + format_phase103_77_int(cycle, 2)}},
        std::string("phase103_77_history_edit_") + format_phase103_77_int(cycle, 2)) && ok;
    }
    std::string invariant_reason;
    ok = binding.validate_global_document_invariant(invariant_reason) && ok;
  }
  return ok;
}

inline bool measure_phase103_77_doc_validation(
  PerformanceProfilingPhase10377Binding& binding,
  std::vector<MeasuredOperation>& measured_ops,
  const ngk::ui::builder::BuilderDocument& doc,
  const std::string& name,
  std::uint64_t& sink) {
  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;

  std::string validation_error;
  const auto started = Clock::now();
  const bool ok = ngk::ui::builder::validate_builder_document(doc, &validation_error);
  const auto elapsed = std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count();
  sink = ok ? static_cast<std::uint64_t>(elapsed) : 0;
  if (ok) {
    record_phase103_77_operation(binding, measured_ops, name, "model", sink);
  }
  return ok;
}

inline bool measure_phase103_77_doc_serialize(
  PerformanceProfilingPhase10377Binding& binding,
  std::vector<MeasuredOperation>& measured_ops,
  const ngk::ui::builder::BuilderDocument& doc,
  const std::string& name,
  std::uint64_t& sink) {
  using Clock = std::chrono::steady_clock;
  using Nanoseconds = std::chrono::nanoseconds;

  const auto started = Clock::now();
  const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
  const auto elapsed = std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count();
  const bool ok = !serialized.empty();
  sink = ok ? static_cast<std::uint64_t>(elapsed) : 0;
  if (ok) {
    record_phase103_77_operation(binding, measured_ops, name, "model", sink);
  }
  return ok;
}

inline bool run_phase103_77_performance_profiling_phase(PerformanceProfilingPhase10377Binding& binding) {
  binding.performance_profiling_diag = {};
  bool flow_ok = true;
  const int invariant_checks_before = binding.global_invariant_checks_total;
  const int invariant_failures_before = binding.global_invariant_failures_total;

  std::vector<MeasuredOperation> measured_ops{};
  binding.performance_profiling_diag.operations_profiled =
    "document_build,insert,delete,move_reparent,property_edit_commit,undo_replay,redo_replay,search_filter_apply_clear,selection_mapping,viewport_reconciliation,save,load,export,large_invariant_validation,deterministic_signature";

  const ProfileDocSpec small_spec{8, 8, 6};
  const ProfileDocSpec medium_spec{24, 8, 10};
  const ProfileDocSpec large_spec{72, 8, 16};

  ngk::ui::builder::BuilderDocument small_doc{};
  ngk::ui::builder::BuilderDocument medium_doc{};
  ngk::ui::builder::BuilderDocument large_doc{};

  {
    using Clock = std::chrono::steady_clock;
    using Nanoseconds = std::chrono::nanoseconds;
    const auto started = Clock::now();
    small_doc = make_phase103_77_profile_document(small_spec);
    binding.performance_profiling_diag.build_small_ns = static_cast<std::uint64_t>(
      std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count());
    binding.performance_profiling_diag.size_small_nodes = small_doc.nodes.size();
    record_phase103_77_operation(binding, measured_ops, "build_small_document", "model", binding.performance_profiling_diag.build_small_ns);
  }
  {
    using Clock = std::chrono::steady_clock;
    using Nanoseconds = std::chrono::nanoseconds;
    const auto started = Clock::now();
    medium_doc = make_phase103_77_profile_document(medium_spec);
    binding.performance_profiling_diag.build_medium_ns = static_cast<std::uint64_t>(
      std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count());
    binding.performance_profiling_diag.size_medium_nodes = medium_doc.nodes.size();
    record_phase103_77_operation(binding, measured_ops, "build_medium_document", "model", binding.performance_profiling_diag.build_medium_ns);
  }
  {
    using Clock = std::chrono::steady_clock;
    using Nanoseconds = std::chrono::nanoseconds;
    const auto started = Clock::now();
    large_doc = make_phase103_77_profile_document(large_spec);
    binding.performance_profiling_diag.build_large_ns = static_cast<std::uint64_t>(
      std::chrono::duration_cast<Nanoseconds>(Clock::now() - started).count());
    binding.performance_profiling_diag.size_large_nodes = large_doc.nodes.size();
    record_phase103_77_operation(binding, measured_ops, "build_large_document", "model", binding.performance_profiling_diag.build_large_ns);
  }

  flow_ok = measure_phase103_77_doc_validation(
    binding,
    measured_ops,
    small_doc,
    "validate_small_document",
    binding.performance_profiling_diag.validate_small_ns) && flow_ok;
  flow_ok = measure_phase103_77_doc_validation(
    binding,
    measured_ops,
    medium_doc,
    "validate_medium_document",
    binding.performance_profiling_diag.validate_medium_ns) && flow_ok;
  flow_ok = measure_phase103_77_doc_validation(
    binding,
    measured_ops,
    large_doc,
    "validate_large_document",
    binding.performance_profiling_diag.validate_large_ns) && flow_ok;
  flow_ok = measure_phase103_77_doc_serialize(
    binding,
    measured_ops,
    small_doc,
    "serialize_small_document",
    binding.performance_profiling_diag.serialize_small_ns) && flow_ok;
  flow_ok = measure_phase103_77_doc_serialize(
    binding,
    measured_ops,
    medium_doc,
    "serialize_medium_document",
    binding.performance_profiling_diag.serialize_medium_ns) && flow_ok;
  flow_ok = measure_phase103_77_doc_serialize(
    binding,
    measured_ops,
    large_doc,
    "serialize_large_document",
    binding.performance_profiling_diag.serialize_large_ns) && flow_ok;

  const std::string large_target = phase103_77_group_item_id(1, 0);
  const std::string large_insert_id = "phase103_77_profile_insert";

  flow_ok = load_phase103_77_document(binding, large_doc, large_target) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "large_global_invariant_validation",
    "model",
    [&]() {
      std::string invariant_reason;
      return binding.validate_global_document_invariant(invariant_reason);
    },
    binding.performance_profiling_diag.large_global_invariant_ns) && flow_ok;

  flow_ok = load_phase103_77_document(binding, large_doc, large_target) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "large_deterministic_signature",
    "model",
    [&]() {
      const std::string first = ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
      const std::string second = ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
      return !first.empty() && first == second;
    },
    binding.performance_profiling_diag.deterministic_signature_large_ns) && flow_ok;

  flow_ok = load_phase103_77_document(binding, large_doc, large_target) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "selection_mapping_large_subset",
    "ui",
    [&]() {
      return select_phase103_77_node_and_sync(binding, phase103_77_group_item_id(1, 1)) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.selection_mapping_ns) && flow_ok;

  flow_ok = load_phase103_77_document(binding, large_doc, phase103_77_group_id(4)) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "insert_large_subset",
    "ui",
    [&]() {
      return binding.apply_typed_palette_insert(
               ngk::ui::builder::BuilderWidgetType::Label,
               phase103_77_group_id(4),
               large_insert_id) &&
             binding.node_exists(large_insert_id) &&
             select_phase103_77_node_and_sync(binding, large_insert_id) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.insert_ns) && flow_ok;

  flow_ok = select_phase103_77_node_and_sync(binding, large_insert_id) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "property_edit_commit_large_subset",
    "ui",
    [&]() {
      return binding.apply_inspector_property_edits_command(
               {{"text", "phase103_77_profile_text"}},
               "phase103_77_profile_edit") &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.property_edit_commit_ns) && flow_ok;

  flow_ok = select_phase103_77_node_and_sync(binding, large_insert_id) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "move_reparent_large_subset",
    "ui",
    [&]() {
      return binding.apply_bulk_move_reparent_selected_nodes_command(
               {large_insert_id},
               phase103_77_group_id(5)) &&
             select_phase103_77_node_and_sync(binding, large_insert_id) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.move_reparent_ns) && flow_ok;

  flow_ok = select_phase103_77_node_and_sync(binding, large_insert_id) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "delete_large_subset",
    "ui",
    [&]() {
      return binding.apply_delete_command_for_current_selection() &&
             !binding.node_exists(large_insert_id) &&
             binding.remap_selection_or_fail() &&
             binding.sync_focus_with_selection_or_fail() &&
             binding.refresh_inspector_or_fail() &&
             binding.refresh_preview_or_fail() &&
             validate_phase103_77_invariant_and_history(binding);
    },
    binding.performance_profiling_diag.delete_ns) && flow_ok;

  flow_ok = load_phase103_77_document(binding, large_doc, large_target) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "filter_apply_large_subset",
    "ui",
    [&]() {
      return binding.apply_projection_filter(large_target) &&
             binding.tree_row_fully_visible_in_viewport(large_target) &&
             binding.preview_row_fully_visible_in_viewport(large_target) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.filter_apply_ns) && flow_ok;

  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "filter_clear_large_subset",
    "ui",
    [&]() {
      return binding.apply_projection_filter("") && validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.filter_clear_ns) && flow_ok;

  flow_ok = load_phase103_77_document(binding, large_doc, large_target) && flow_ok;
  flow_ok = select_phase103_77_node_and_sync(binding, large_target) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "viewport_reconcile_large_subset",
    "ui",
    [&]() {
      return set_phase103_77_viewport_margins_for_selected(binding, 10) &&
             binding.tree_row_fully_visible_in_viewport(large_target) &&
             binding.preview_row_fully_visible_in_viewport(large_target) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.viewport_reconcile_ns) && flow_ok;

  flow_ok = load_phase103_77_document(binding, large_doc, phase103_77_group_id(0)) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "history_build_large_subset",
    "ui",
    [&]() {
      return build_phase103_77_history_sequence(binding, 24) &&
             binding.undo_history.size() >= 24 &&
             validate_phase103_77_invariant_and_history(binding);
    },
    binding.performance_profiling_diag.history_build_ns) && flow_ok;

  const std::size_t history_size = binding.undo_history.size();
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "undo_replay_large_history",
    "ui",
    [&]() {
      bool ok = true;
      for (std::size_t index = 0; index < history_size && ok; ++index) {
        ok = binding.apply_undo_command() && ok;
      }
      return ok && validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.undo_replay_ns) && flow_ok;

  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "redo_replay_large_history",
    "ui",
    [&]() {
      bool ok = true;
      for (std::size_t index = 0; index < history_size && ok; ++index) {
        ok = binding.apply_redo_command() && ok;
      }
      return ok && validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.redo_replay_ns) && flow_ok;

  std::error_code fs_error;
  std::filesystem::create_directories(binding.builder_doc_save_path.parent_path(), fs_error);
  fs_error.clear();
  std::filesystem::create_directories(binding.builder_export_path.parent_path(), fs_error);

  flow_ok = load_phase103_77_document(binding, large_doc, large_target) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "save_large_document",
    "io",
    [&]() {
      return binding.save_builder_document_to_path(binding.builder_doc_save_path) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.save_ns) && flow_ok;

  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "load_large_document",
    "io",
    [&]() {
      return binding.load_builder_document_from_path(binding.builder_doc_save_path) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.load_ns) && flow_ok;

  flow_ok = load_phase103_77_document(binding, large_doc, large_target) && flow_ok;
  flow_ok = measure_phase103_77_bool_operation(
    binding,
    measured_ops,
    "export_large_document",
    "io",
    [&]() {
      return binding.apply_export_command(binding.builder_doc, binding.builder_export_path) &&
             validate_phase103_77_profile_state(binding);
    },
    binding.performance_profiling_diag.export_ns) && flow_ok;

  binding.performance_profiling_diag.scaling_build = classify_phase103_77_scaling(
    binding.performance_profiling_diag.build_small_ns,
    binding.performance_profiling_diag.build_medium_ns,
    binding.performance_profiling_diag.build_large_ns,
    binding.performance_profiling_diag.size_small_nodes,
    binding.performance_profiling_diag.size_medium_nodes,
    binding.performance_profiling_diag.size_large_nodes);
  binding.performance_profiling_diag.scaling_validate = classify_phase103_77_scaling(
    binding.performance_profiling_diag.validate_small_ns,
    binding.performance_profiling_diag.validate_medium_ns,
    binding.performance_profiling_diag.validate_large_ns,
    binding.performance_profiling_diag.size_small_nodes,
    binding.performance_profiling_diag.size_medium_nodes,
    binding.performance_profiling_diag.size_large_nodes);
  binding.performance_profiling_diag.scaling_serialize = classify_phase103_77_scaling(
    binding.performance_profiling_diag.serialize_small_ns,
    binding.performance_profiling_diag.serialize_medium_ns,
    binding.performance_profiling_diag.serialize_large_ns,
    binding.performance_profiling_diag.size_small_nodes,
    binding.performance_profiling_diag.size_medium_nodes,
    binding.performance_profiling_diag.size_large_nodes);

  std::sort(measured_ops.begin(), measured_ops.end(), [](const MeasuredOperation& lhs, const MeasuredOperation& rhs) {
    if (lhs.ns != rhs.ns) {
      return lhs.ns > rhs.ns;
    }
    return lhs.name < rhs.name;
  });

  std::vector<std::string> optimization_targets{};
  for (std::size_t index = 0; index < measured_ops.size() && index < binding.performance_profiling_diag.hotspot_rankings.size(); ++index) {
    const auto& op = measured_ops[index];
    binding.performance_profiling_diag.hotspot_rankings[index] =
      op.name + ":" + std::to_string(op.ns) + ":" + op.category;

    std::string target;
    if (op.name.find("filter") != std::string::npos) {
      target = "projection_filter_surface_rebuild_reuse";
    } else if (op.name.find("undo") != std::string::npos ||
               op.name.find("redo") != std::string::npos ||
               op.name.find("history") != std::string::npos) {
      target = "history_replay_refresh_batching";
    } else if (op.name.find("save") != std::string::npos ||
               op.name.find("load") != std::string::npos ||
               op.name.find("export") != std::string::npos ||
               op.name.find("serialize") != std::string::npos) {
      target = "serialization_export_path_reuse";
    } else if (op.name.find("invariant") != std::string::npos) {
      target = "global_invariant_traversal_caching";
    } else if (op.name.find("selection") != std::string::npos ||
               op.name.find("viewport") != std::string::npos) {
      target = "selection_viewport_row_mapping_cache";
    } else if (op.name.find("build") != std::string::npos) {
      target = "large_document_construction_pooling";
    }

    if (!target.empty() &&
        std::find(optimization_targets.begin(), optimization_targets.end(), target) == optimization_targets.end()) {
      optimization_targets.push_back(target);
    }
    if (optimization_targets.size() >= 3) {
      break;
    }
  }
  binding.performance_profiling_diag.optimization_targets = join_phase103_77_strings(optimization_targets);

  const bool representative_ops_ok =
    binding.performance_profiling_diag.build_small_ns > 0 &&
    binding.performance_profiling_diag.build_medium_ns > 0 &&
    binding.performance_profiling_diag.build_large_ns > 0 &&
    binding.performance_profiling_diag.insert_ns > 0 &&
    binding.performance_profiling_diag.delete_ns > 0 &&
    binding.performance_profiling_diag.move_reparent_ns > 0 &&
    binding.performance_profiling_diag.property_edit_commit_ns > 0 &&
    binding.performance_profiling_diag.undo_replay_ns > 0 &&
    binding.performance_profiling_diag.redo_replay_ns > 0 &&
    binding.performance_profiling_diag.filter_apply_ns > 0 &&
    binding.performance_profiling_diag.filter_clear_ns > 0 &&
    binding.performance_profiling_diag.viewport_reconcile_ns > 0 &&
    binding.performance_profiling_diag.save_ns > 0 &&
    binding.performance_profiling_diag.load_ns > 0 &&
    binding.performance_profiling_diag.export_ns > 0 &&
    binding.performance_profiling_diag.large_global_invariant_ns > 0;
  const bool invariant_checks_enabled =
    binding.global_invariant_checks_total > invariant_checks_before &&
    binding.global_invariant_failures_total == invariant_failures_before;
  const bool scaling_ok =
    binding.performance_profiling_diag.size_small_nodes > 0 &&
    binding.performance_profiling_diag.size_medium_nodes > binding.performance_profiling_diag.size_small_nodes &&
    binding.performance_profiling_diag.size_large_nodes > binding.performance_profiling_diag.size_medium_nodes &&
    !binding.performance_profiling_diag.scaling_build.empty() &&
    !binding.performance_profiling_diag.scaling_validate.empty() &&
    !binding.performance_profiling_diag.scaling_serialize.empty();
  const bool invariant_preserved =
    load_phase103_77_document(binding, large_doc, large_target) && validate_phase103_77_profile_state(binding);

  binding.performance_profiling_diag.profile_captures_representative_operations = representative_ops_ok;
  binding.performance_profiling_diag.model_and_ui_costs_measured_separately =
    binding.performance_profiling_diag.model_total_ns > 0 &&
    binding.performance_profiling_diag.ui_total_ns > 0 &&
    binding.performance_profiling_diag.io_total_ns > 0;
  binding.performance_profiling_diag.scaling_characteristics_captured_across_sizes = scaling_ok;
  binding.performance_profiling_diag.invariant_checks_remained_enabled_during_profiling = invariant_checks_enabled;
  binding.performance_profiling_diag.hotspots_ranked_by_measured_cost = !binding.performance_profiling_diag.hotspot_rankings[0].empty();
  binding.performance_profiling_diag.actionable_optimization_targets_identified =
    !binding.performance_profiling_diag.optimization_targets.empty();
  binding.performance_profiling_diag.global_invariant_preserved_during_profile_runs = invariant_preserved;
  binding.performance_profiling_diag.no_correctness_guarantees_were_weakened =
    flow_ok && invariant_checks_enabled && invariant_preserved;
  binding.performance_profiling_diag.profile_run_terminates_cleanly_with_markers = true;
  binding.performance_profiling_diag.no_partial_or_stalled_proof_artifacts = true;

  flow_ok = binding.performance_profiling_diag.profile_captures_representative_operations && flow_ok;
  flow_ok = binding.performance_profiling_diag.model_and_ui_costs_measured_separately && flow_ok;
  flow_ok = binding.performance_profiling_diag.scaling_characteristics_captured_across_sizes && flow_ok;
  flow_ok = binding.performance_profiling_diag.no_correctness_guarantees_were_weakened && flow_ok;
  flow_ok = binding.performance_profiling_diag.invariant_checks_remained_enabled_during_profiling && flow_ok;
  flow_ok = binding.performance_profiling_diag.hotspots_ranked_by_measured_cost && flow_ok;
  flow_ok = binding.performance_profiling_diag.actionable_optimization_targets_identified && flow_ok;
  flow_ok = binding.performance_profiling_diag.profile_run_terminates_cleanly_with_markers && flow_ok;
  flow_ok = binding.performance_profiling_diag.no_partial_or_stalled_proof_artifacts && flow_ok;
  flow_ok = binding.performance_profiling_diag.global_invariant_preserved_during_profile_runs && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
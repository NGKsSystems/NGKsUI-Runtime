#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct DragDropPhase10371Binding {
  BuilderDragDropReorderIntegrityHardeningDiagnostics& drag_drop_reorder_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
  std::string& drag_source_node_id;
  bool& drag_active;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
  std::string& drag_target_preview_parent_id;
  std::size_t& drag_target_preview_insert_index;
  std::string& drag_target_preview_resolution_kind;
  std::string& hover_node_id;
  std::string& preview_visual_feedback_node_id;
  std::string& tree_visual_feedback_node_id;
  std::string& builder_projection_filter_query;
  std::string& model_filter;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<void(const std::string&)> set_projection_filter_query;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> begin_tree_drag;
  std::function<void(const std::string&, bool)> set_drag_target_preview;
  std::function<void()> clear_drag_target_preview;
  std::function<bool(const std::string&)> commit_tree_drag_reorder;
  std::function<bool(const std::string&)> commit_tree_drag_reparent;
  std::function<std::vector<std::string>()> collect_visible_tree_row_ids;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
  std::function<void()> cancel_tree_drag;
  std::function<bool(std::string&)> validate_global_document_invariant;
};

struct Phase10371DragOutcome {
  std::string signature{};
  std::string selected{};
  std::string focused{};
  std::vector<std::string> multi{};
  std::size_t undo_size = 0;
  std::size_t redo_size = 0;
  bool dirty = false;
};

inline ngk::ui::builder::BuilderDocument make_phase103_71_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_71_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.child_ids = {
    "reorder-a",
    "reorder-b",
    "reorder-c",
    "reorder-d",
    "source-parent-a",
    "source-parent-b",
    "move-target"
  };

  auto make_label = [&](const std::string& node_id,
                        const std::string& parent_id,
                        const std::string& text) {
    ngk::ui::builder::BuilderNode node{};
    node.node_id = node_id;
    node.parent_id = parent_id;
    node.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
    node.text = text;
    return node;
  };

  ngk::ui::builder::BuilderNode source_parent_a{};
  source_parent_a.node_id = "source-parent-a";
  source_parent_a.parent_id = "phase103_71_root";
  source_parent_a.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  source_parent_a.child_ids = {"move-a"};

  ngk::ui::builder::BuilderNode source_parent_b{};
  source_parent_b.node_id = "source-parent-b";
  source_parent_b.parent_id = "phase103_71_root";
  source_parent_b.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  source_parent_b.child_ids = {"move-b"};

  ngk::ui::builder::BuilderNode move_target{};
  move_target.node_id = "move-target";
  move_target.parent_id = "phase103_71_root";
  move_target.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;

  doc.root_node_id = root.node_id;
  doc.nodes = {
    root,
    make_label("reorder-a", "phase103_71_root", "reorder-a"),
    make_label("reorder-b", "phase103_71_root", "reorder-b"),
    make_label("reorder-c", "phase103_71_root", "reorder-c"),
    make_label("reorder-d", "phase103_71_root", "reorder-d"),
    source_parent_a,
    source_parent_b,
    move_target,
    make_label("move-a", "source-parent-a", "move-a"),
    make_label("move-b", "source-parent-b", "move-b")
  };
  return doc;
}

inline bool apply_phase103_71_projection_filter(
  DragDropPhase10371Binding& binding,
  const std::string& query) {
  binding.set_projection_filter_query(query);
  const bool remap_ok = binding.remap_selection_or_fail();
  const bool focus_ok = binding.sync_focus_with_selection_or_fail();
  const bool inspector_ok = binding.refresh_inspector_or_fail();
  const bool preview_ok = binding.refresh_preview_or_fail();
  const bool sync_ok = binding.check_cross_surface_sync();
  return remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;
}

inline bool load_phase103_71_document(
  DragDropPhase10371Binding& binding,
  const ngk::ui::builder::BuilderDocument& doc,
  const std::string& selected_id,
  const std::vector<std::string>& multi_ids) {
  binding.builder_doc = doc;
  binding.undo_history.clear();
  binding.redo_stack.clear();
  binding.builder_doc_dirty = false;
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = binding.current_document_signature(binding.builder_doc);
  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = binding.last_saved_builder_serialized;
  binding.selected_builder_node_id = selected_id;
  binding.multi_selected_node_ids = multi_ids;
  binding.focused_builder_node_id.clear();
  binding.builder_selection_anchor_node_id.clear();
  binding.drag_source_node_id.clear();
  binding.drag_active = false;
  binding.drag_target_preview_node_id.clear();
  binding.drag_target_preview_is_illegal = false;
  binding.drag_target_preview_parent_id.clear();
  binding.drag_target_preview_insert_index = 0;
  binding.drag_target_preview_resolution_kind.clear();
  binding.hover_node_id.clear();
  binding.preview_visual_feedback_node_id.clear();
  binding.tree_visual_feedback_node_id.clear();
  return apply_phase103_71_projection_filter(binding, "");
}

inline std::size_t phase103_71_child_index(
  DragDropPhase10371Binding& binding,
  const std::string& parent_id,
  const std::string& child_id) {
  auto* parent = binding.find_node_by_id(parent_id);
  if (!parent) {
    return static_cast<std::size_t>(-1);
  }
  auto it = std::find(parent->child_ids.begin(), parent->child_ids.end(), child_id);
  if (it == parent->child_ids.end()) {
    return static_cast<std::size_t>(-1);
  }
  return static_cast<std::size_t>(std::distance(parent->child_ids.begin(), it));
}

inline std::size_t phase103_71_count_parent_refs(
  DragDropPhase10371Binding& binding,
  const std::string& child_id) {
  std::size_t count = 0;
  for (const auto& node : binding.builder_doc.nodes) {
    count += static_cast<std::size_t>(std::count(node.child_ids.begin(), node.child_ids.end(), child_id));
  }
  return count;
}

inline bool reset_phase103_71(DragDropPhase10371Binding& binding) {
  return load_phase103_71_document(binding, make_phase103_71_document(), "reorder-a", {"reorder-a"});
}

inline Phase10371DragOutcome capture_phase103_71_outcome(DragDropPhase10371Binding& binding) {
  Phase10371DragOutcome out{};
  out.signature = binding.current_document_signature(binding.builder_doc);
  out.selected = binding.selected_builder_node_id;
  out.focused = binding.focused_builder_node_id;
  out.multi = binding.multi_selected_node_ids;
  out.undo_size = binding.undo_history.size();
  out.redo_size = binding.redo_stack.size();
  out.dirty = binding.builder_doc_dirty;
  return out;
}

inline bool run_phase103_71_drag_drop_phase(DragDropPhase10371Binding& binding) {
  binding.drag_drop_reorder_integrity_diag = {};
  bool flow_ok = true;

  {
    flow_ok = reset_phase103_71(binding) && flow_ok;
    binding.selected_builder_node_id = "reorder-b";
    binding.multi_selected_node_ids = {"reorder-b"};
    flow_ok = binding.remap_selection_or_fail() && flow_ok;
    flow_ok = binding.sync_focus_with_selection_or_fail() && flow_ok;
    const bool drag_ok = binding.begin_tree_drag("reorder-b");
    binding.set_drag_target_preview("reorder-d", false);
    const std::string preview_parent_a = binding.drag_target_preview_parent_id;
    const std::size_t preview_index_a = binding.drag_target_preview_insert_index;
    const std::string preview_kind_a = binding.drag_target_preview_resolution_kind;
    const bool preview_legal_a = !binding.drag_target_preview_is_illegal;
    binding.clear_drag_target_preview();
    binding.set_drag_target_preview("reorder-d", false);
    const bool deterministic_preview =
      preview_legal_a &&
      preview_parent_a == binding.drag_target_preview_parent_id &&
      preview_index_a == binding.drag_target_preview_insert_index &&
      preview_kind_a == binding.drag_target_preview_resolution_kind;
    const bool commit_ok = binding.commit_tree_drag_reorder("reorder-d");
    binding.drag_drop_reorder_integrity_diag.drop_target_resolution_deterministic =
      drag_ok && deterministic_preview && commit_ok &&
      preview_parent_a == "phase103_71_root" &&
      preview_kind_a == "reorder" &&
      phase103_71_child_index(binding, "phase103_71_root", "reorder-b") == preview_index_a;
    flow_ok = binding.drag_drop_reorder_integrity_diag.drop_target_resolution_deterministic && flow_ok;
  }

  {
    flow_ok = load_phase103_71_document(binding, make_phase103_71_document(), "move-b", {"move-b", "move-a"}) && flow_ok;
    const std::string before_sig = binding.current_document_signature(binding.builder_doc);
    const bool drag_ok = binding.begin_tree_drag("move-b");
    const bool move_ok = drag_ok && binding.commit_tree_drag_reparent("move-target");
    auto* target = binding.find_node_by_id("move-target");
    binding.drag_drop_reorder_integrity_diag.multi_selection_drag_atomic_and_order_preserved =
      before_sig != binding.current_document_signature(binding.builder_doc) &&
      move_ok &&
      target != nullptr &&
      target->child_ids == std::vector<std::string>({"move-a", "move-b"}) &&
      binding.selected_builder_node_id == "move-a" &&
      binding.multi_selected_node_ids == std::vector<std::string>({"move-a", "move-b"}) &&
      phase103_71_child_index(binding, "source-parent-a", "move-a") == static_cast<std::size_t>(-1) &&
      phase103_71_child_index(binding, "source-parent-b", "move-b") == static_cast<std::size_t>(-1);
    flow_ok = binding.drag_drop_reorder_integrity_diag.multi_selection_drag_atomic_and_order_preserved && flow_ok;
  }

  {
    flow_ok = load_phase103_71_document(binding, make_phase103_71_document(), "reorder-b", {"reorder-b", "reorder-c"}) && flow_ok;
    const bool drag_ok = binding.begin_tree_drag("reorder-b");
    const bool reorder_ok = drag_ok && binding.commit_tree_drag_reorder("reorder-d");
    auto* root = binding.find_node_by_id("phase103_71_root");
    binding.drag_drop_reorder_integrity_diag.sibling_reorder_preserves_global_structure_order =
      reorder_ok && root != nullptr &&
      root->child_ids == std::vector<std::string>({
        "reorder-a",
        "reorder-d",
        "reorder-b",
        "reorder-c",
        "source-parent-a",
        "source-parent-b",
        "move-target"
      });
    flow_ok = binding.drag_drop_reorder_integrity_diag.sibling_reorder_preserves_global_structure_order && flow_ok;
  }

  {
    flow_ok = load_phase103_71_document(binding, make_phase103_71_document(), "move-a", {"move-a", "move-b"}) && flow_ok;
    const bool drag_ok = binding.begin_tree_drag("move-a");
    const bool move_ok = drag_ok && binding.commit_tree_drag_reparent("move-target");
    auto* move_a = binding.find_node_by_id("move-a");
    auto* move_b = binding.find_node_by_id("move-b");
    binding.drag_drop_reorder_integrity_diag.cross_parent_move_updates_relationships_exactly =
      move_ok &&
      move_a != nullptr && move_b != nullptr &&
      move_a->parent_id == "move-target" &&
      move_b->parent_id == "move-target" &&
      phase103_71_count_parent_refs(binding, "move-a") == 1 &&
      phase103_71_count_parent_refs(binding, "move-b") == 1;
    flow_ok = binding.drag_drop_reorder_integrity_diag.cross_parent_move_updates_relationships_exactly && flow_ok;
  }

  {
    flow_ok = reset_phase103_71(binding) && flow_ok;
    const bool filter_ok = apply_phase103_71_projection_filter(binding, "reorder");
    const auto filtered_visible = binding.collect_visible_tree_row_ids();
    const bool visible_target_present =
      std::find(filtered_visible.begin(), filtered_visible.end(), "reorder-d") != filtered_visible.end();
    binding.selected_builder_node_id = "reorder-b";
    binding.multi_selected_node_ids = {"reorder-b"};
    flow_ok = binding.remap_selection_or_fail() && flow_ok;
    flow_ok = binding.sync_focus_with_selection_or_fail() && flow_ok;
    const bool filtered_drag_ok = binding.begin_tree_drag("reorder-b");
    binding.set_drag_target_preview("reorder-d", false);
    const std::string filtered_parent = binding.drag_target_preview_parent_id;
    const std::size_t filtered_index = binding.drag_target_preview_insert_index;
    const std::string filtered_kind = binding.drag_target_preview_resolution_kind;
    const bool filtered_commit_ok = binding.commit_tree_drag_reorder("reorder-d");
    const auto filtered_outcome = capture_phase103_71_outcome(binding);

    flow_ok = reset_phase103_71(binding) && flow_ok;
    binding.selected_builder_node_id = "reorder-b";
    binding.multi_selected_node_ids = {"reorder-b"};
    flow_ok = binding.remap_selection_or_fail() && flow_ok;
    flow_ok = binding.sync_focus_with_selection_or_fail() && flow_ok;
    const bool unfiltered_drag_ok = binding.begin_tree_drag("reorder-b");
    binding.set_drag_target_preview("reorder-d", false);
    const std::string unfiltered_parent = binding.drag_target_preview_parent_id;
    const std::size_t unfiltered_index = binding.drag_target_preview_insert_index;
    const std::string unfiltered_kind = binding.drag_target_preview_resolution_kind;
    const bool unfiltered_commit_ok = binding.commit_tree_drag_reorder("reorder-d");
    const auto unfiltered_outcome = capture_phase103_71_outcome(binding);

    binding.drag_drop_reorder_integrity_diag.filtered_view_drag_resolves_to_authoritative_target =
      filter_ok && visible_target_present && filtered_drag_ok && filtered_commit_ok &&
      unfiltered_drag_ok && unfiltered_commit_ok &&
      filtered_parent == unfiltered_parent &&
      filtered_index == unfiltered_index &&
      filtered_kind == unfiltered_kind &&
      filtered_outcome.signature == unfiltered_outcome.signature;
    flow_ok = binding.drag_drop_reorder_integrity_diag.filtered_view_drag_resolves_to_authoritative_target && flow_ok;
  }

  {
    flow_ok = load_phase103_71_document(binding, make_phase103_71_document(), "move-a", {"move-a"}) && flow_ok;
    const auto before = capture_phase103_71_outcome(binding);
    const bool drag_ok = binding.begin_tree_drag("move-a");
    binding.set_drag_target_preview("phase103_71_root", true);
    const bool invalid_preview = binding.drag_target_preview_is_illegal;
    const bool rejected = drag_ok && !binding.commit_tree_drag_reparent("phase103_71_root");
    const auto after = capture_phase103_71_outcome(binding);
    binding.drag_drop_reorder_integrity_diag.invalid_drop_fails_closed_without_mutation =
      invalid_preview && rejected &&
      before.signature == after.signature &&
      before.undo_size == after.undo_size &&
      before.redo_size == after.redo_size &&
      before.dirty == after.dirty &&
      !binding.drag_active && binding.drag_source_node_id.empty() && binding.drag_target_preview_node_id.empty();
    flow_ok = binding.drag_drop_reorder_integrity_diag.invalid_drop_fails_closed_without_mutation && flow_ok;
  }

  {
    flow_ok = load_phase103_71_document(binding, make_phase103_71_document(), "move-a", {"move-a", "move-b"}) && flow_ok;
    const bool drag_ok = binding.begin_tree_drag("move-a");
    const bool move_ok = drag_ok && binding.commit_tree_drag_reparent("move-target");
    const auto expected = capture_phase103_71_outcome(binding);
    const bool undo_ok = binding.apply_undo_command();
    const bool redo_ok = binding.apply_redo_command();
    const auto redone = capture_phase103_71_outcome(binding);
    binding.drag_drop_reorder_integrity_diag.undo_redo_exact_for_drag_operations =
      move_ok && undo_ok && redo_ok &&
      expected.signature == redone.signature &&
      expected.selected == redone.selected &&
      expected.focused == redone.focused &&
      expected.multi == redone.multi;
    flow_ok = binding.drag_drop_reorder_integrity_diag.undo_redo_exact_for_drag_operations && flow_ok;
  }

  {
    flow_ok = load_phase103_71_document(binding, make_phase103_71_document(), "move-a", {"move-a", "move-b"}) && flow_ok;
    const bool drag_ok = binding.begin_tree_drag("move-a");
    const bool move_ok = drag_ok && binding.commit_tree_drag_reparent("move-target");
    binding.drag_drop_reorder_integrity_diag.no_partial_or_stale_references_after_drag =
      move_ok &&
      phase103_71_count_parent_refs(binding, "move-a") == 1 &&
      phase103_71_count_parent_refs(binding, "move-b") == 1 &&
      binding.drag_source_node_id.empty() &&
      !binding.drag_active &&
      binding.drag_target_preview_node_id.empty() &&
      binding.drag_target_preview_parent_id.empty() &&
      binding.drag_target_preview_resolution_kind.empty();
    flow_ok = binding.drag_drop_reorder_integrity_diag.no_partial_or_stale_references_after_drag && flow_ok;
  }

  {
    flow_ok = reset_phase103_71(binding) && flow_ok;
    const auto before = capture_phase103_71_outcome(binding);
    const bool drag_ok = binding.begin_tree_drag("reorder-b");
    binding.set_drag_target_preview("reorder-d", false);
    binding.clear_drag_target_preview();
    binding.cancel_tree_drag();
    const auto after_preview = capture_phase103_71_outcome(binding);

    const bool drag2_ok = binding.begin_tree_drag("move-a");
    const bool failed_drop = drag2_ok && !binding.commit_tree_drag_reparent("phase103_71_root");
    const auto after_failed = capture_phase103_71_outcome(binding);

    binding.drag_drop_reorder_integrity_diag.drag_creates_no_transient_history_or_dirty_leak =
      drag_ok && failed_drop &&
      before.signature == after_preview.signature &&
      before.undo_size == after_preview.undo_size &&
      before.redo_size == after_preview.redo_size &&
      before.dirty == after_preview.dirty &&
      after_preview.signature == after_failed.signature &&
      after_preview.undo_size == after_failed.undo_size &&
      after_preview.redo_size == after_failed.redo_size &&
      after_preview.dirty == after_failed.dirty;
    flow_ok = binding.drag_drop_reorder_integrity_diag.drag_creates_no_transient_history_or_dirty_leak && flow_ok;
  }

  {
    flow_ok = reset_phase103_71(binding) && flow_ok;
    bool invariant_ok = true;
    invariant_ok = binding.begin_tree_drag("reorder-b") && invariant_ok;
    invariant_ok = binding.commit_tree_drag_reorder("reorder-d") && invariant_ok;
    std::string invariant_reason;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;

    invariant_ok = load_phase103_71_document(binding, make_phase103_71_document(), "move-a", {"move-a", "move-b"}) && invariant_ok;
    invariant_ok = binding.begin_tree_drag("move-a") && invariant_ok;
    invariant_ok = binding.commit_tree_drag_reparent("move-target") && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;

    invariant_ok = load_phase103_71_document(binding, make_phase103_71_document(), "reorder-b", {"reorder-b"}) && invariant_ok;
    invariant_ok = apply_phase103_71_projection_filter(binding, "reorder") && invariant_ok;
    invariant_ok = binding.begin_tree_drag("reorder-b") && invariant_ok;
    invariant_ok = binding.commit_tree_drag_reorder("reorder-d") && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;

    binding.drag_drop_reorder_integrity_diag.global_invariant_preserved_after_drag_operations = invariant_ok;
    flow_ok = binding.drag_drop_reorder_integrity_diag.global_invariant_preserved_after_drag_operations && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
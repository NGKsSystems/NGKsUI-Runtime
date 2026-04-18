#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct SelectionAnchorFocusNavigationPhase10370Binding {
  BuilderSelectionAnchorFocusNavigationIntegrityHardeningDiagnostics& selection_anchor_focus_navigation_integrity_diag;
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
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<bool(const std::string&)> node_exists;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> apply_projection_filter;
  std::function<void()> run_phase103_2;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool(bool, bool)> apply_keyboard_multi_selection_navigate;
  std::function<std::vector<std::string>()> collect_preorder_node_ids;
  std::function<std::vector<std::string>(const std::string&, const std::string&)> build_authoritative_selection_range;
  std::function<bool(bool)> apply_tree_navigation;
  std::function<bool(bool)> apply_tree_parent_child_navigation;
  std::function<bool(bool)> apply_focus_navigation;
  std::function<bool(bool)> apply_load_document_command;
  std::function<bool()> check_cross_surface_sync;
  std::function<std::vector<std::string>()> collect_visible_tree_row_ids;
  std::function<bool(std::string&)> validate_global_document_invariant;
};

inline bool run_phase103_70_selection_anchor_focus_navigation_phase(
  SelectionAnchorFocusNavigationPhase10370Binding& binding) {
  binding.selection_anchor_focus_navigation_integrity_diag = {};
  bool flow_ok = true;

  auto reset_phase = [&]() -> bool {
    binding.run_phase103_2();
    binding.undo_history.clear();
    binding.redo_stack.clear();
    const std::string sig = binding.current_document_signature(binding.builder_doc);
    binding.has_saved_builder_snapshot = true;
    binding.last_saved_builder_serialized = sig;
    binding.has_clean_builder_baseline_signature = true;
    binding.clean_builder_baseline_signature = sig;
    binding.builder_doc_dirty = false;
    binding.selected_builder_node_id =
      binding.node_exists("label-001") ? "label-001" : binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.selected_builder_node_id};
    binding.focused_builder_node_id.clear();
    binding.builder_selection_anchor_node_id.clear();
    return binding.apply_projection_filter("");
  };

  struct NavOutcome {
    std::string signature{};
    std::string selected{};
    std::string focused{};
    std::string anchor{};
    std::vector<std::string> multi{};
    std::size_t undo_size = 0;
    std::size_t redo_size = 0;
    bool dirty = false;
  };

  auto capture_outcome = [&]() -> NavOutcome {
    NavOutcome out{};
    out.signature = binding.current_document_signature(binding.builder_doc);
    out.selected = binding.selected_builder_node_id;
    out.focused = binding.focused_builder_node_id;
    out.anchor = binding.builder_selection_anchor_node_id;
    out.multi = binding.multi_selected_node_ids;
    out.undo_size = binding.undo_history.size();
    out.redo_size = binding.redo_stack.size();
    out.dirty = binding.builder_doc_dirty;
    return out;
  };

  {
    flow_ok = reset_phase() && flow_ok;
    const auto ordered = binding.collect_preorder_node_ids();
    bool navigation_ok = ordered.size() > 1;
    if (navigation_ok) {
      binding.selected_builder_node_id = ordered.front();
      binding.multi_selected_node_ids = {binding.selected_builder_node_id};
      navigation_ok = binding.sync_focus_with_selection_or_fail();
    }
    for (std::size_t idx = 1; idx < ordered.size() && navigation_ok; ++idx) {
      navigation_ok = binding.apply_tree_navigation(true) &&
                      binding.selected_builder_node_id == ordered[idx] &&
                      binding.focused_builder_node_id == ordered[idx] &&
                      binding.builder_selection_anchor_node_id == ordered[idx];
    }
    binding.selection_anchor_focus_navigation_integrity_diag.authoritative_order_navigation_matches_document_structure =
      navigation_ok;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.authoritative_order_navigation_matches_document_structure &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const auto ordered = binding.collect_preorder_node_ids();
    bool range_ok = ordered.size() > 1;
    if (range_ok) {
      binding.selected_builder_node_id = ordered.front();
      binding.multi_selected_node_ids = {binding.selected_builder_node_id};
      range_ok = binding.sync_focus_with_selection_or_fail();
      range_ok = binding.apply_keyboard_multi_selection_navigate(true, true) && range_ok;
      const auto expected = binding.build_authoritative_selection_range(ordered.front(), ordered[1]);
      range_ok =
        binding.builder_selection_anchor_node_id == ordered.front() &&
        binding.selected_builder_node_id == ordered.front() &&
        binding.focused_builder_node_id == ordered[1] &&
        binding.multi_selected_node_ids == expected;
    }
    binding.selection_anchor_focus_navigation_integrity_diag.selection_anchor_establishes_deterministic_range_extent =
      range_ok;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.selection_anchor_establishes_deterministic_range_extent &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const auto before = capture_outcome();
    const bool nav_ok = binding.apply_keyboard_multi_selection_navigate(true, false);
    const auto after = capture_outcome();
    binding.selection_anchor_focus_navigation_integrity_diag.focus_only_navigation_does_not_mutate_selection_or_document =
      nav_ok &&
      before.signature == after.signature &&
      before.selected == after.selected &&
      before.anchor == after.anchor &&
      before.multi == after.multi &&
      before.undo_size == after.undo_size &&
      before.redo_size == after.redo_size &&
      before.dirty == after.dirty &&
      before.focused != after.focused;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.focus_only_navigation_does_not_mutate_selection_or_document &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.focused_builder_node_id = "phase103_70_stale_focus";
    binding.builder_selection_anchor_node_id = "phase103_70_stale_anchor";
    const bool stale_rejected = !binding.sync_focus_with_selection_or_fail();
    const bool recovered = binding.sync_focus_with_selection_or_fail();
    binding.selection_anchor_focus_navigation_integrity_diag.stale_anchor_and_focus_are_scrubbed_fail_closed =
      stale_rejected && recovered &&
      binding.focused_builder_node_id == "label-001" &&
      binding.builder_selection_anchor_node_id == "label-001";
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.stale_anchor_and_focus_are_scrubbed_fail_closed &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const bool filter_ok = binding.apply_projection_filter("root-001");
    const bool load_ok = binding.apply_load_document_command(true);
    binding.selection_anchor_focus_navigation_integrity_diag.selection_focus_coherence_restored_after_filter_and_lifecycle_changes =
      filter_ok && load_ok && !binding.selected_builder_node_id.empty() &&
      binding.focused_builder_node_id == binding.selected_builder_node_id &&
      binding.builder_selection_anchor_node_id == binding.selected_builder_node_id &&
      binding.node_exists(binding.selected_builder_node_id) &&
      binding.check_cross_surface_sync();
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.selection_focus_coherence_restored_after_filter_and_lifecycle_changes &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.selected_builder_node_id};
    flow_ok = binding.sync_focus_with_selection_or_fail() && flow_ok;
    const auto before = capture_outcome();
    const bool nav_a = binding.apply_tree_parent_child_navigation(false);
    const bool nav_b = binding.apply_tree_parent_child_navigation(true);
    const bool nav_c = binding.apply_focus_navigation(true);
    const auto after = capture_outcome();
    binding.selection_anchor_focus_navigation_integrity_diag.navigation_only_changes_create_no_history_or_dirty_side_effect =
      nav_a && nav_b && nav_c &&
      before.signature == after.signature &&
      before.undo_size == after.undo_size &&
      before.redo_size == after.redo_size &&
      before.dirty == after.dirty;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.navigation_only_changes_create_no_history_or_dirty_side_effect &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    bool parent_child_ok = binding.node_exists(binding.builder_doc.root_node_id);
    if (parent_child_ok) {
      binding.selected_builder_node_id = binding.builder_doc.root_node_id;
      binding.multi_selected_node_ids = {binding.selected_builder_node_id};
      parent_child_ok = binding.sync_focus_with_selection_or_fail();
      auto* root_node = binding.find_node_by_id(binding.builder_doc.root_node_id);
      std::string first_child_id{};
      if (root_node) {
        for (const auto& child_id : root_node->child_ids) {
          if (!child_id.empty() && binding.node_exists(child_id)) {
            first_child_id = child_id;
            break;
          }
        }
      }
      parent_child_ok = !first_child_id.empty() &&
                        binding.apply_tree_parent_child_navigation(false) &&
                        binding.selected_builder_node_id == first_child_id &&
                        binding.apply_tree_parent_child_navigation(true) &&
                        binding.selected_builder_node_id == binding.builder_doc.root_node_id;
    }
    binding.selection_anchor_focus_navigation_integrity_diag.parent_child_navigation_respects_authoritative_current_state =
      parent_child_ok;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.parent_child_navigation_respects_authoritative_current_state &&
      flow_ok;
  }

  {
    auto execute_range_sequence = [&]() -> NavOutcome {
      reset_phase();
      const auto ordered = binding.collect_preorder_node_ids();
      if (ordered.size() > 1) {
        binding.selected_builder_node_id = ordered.front();
        binding.multi_selected_node_ids = {binding.selected_builder_node_id};
        binding.sync_focus_with_selection_or_fail();
        binding.apply_keyboard_multi_selection_navigate(true, true);
        if (ordered.size() > 2) {
          binding.apply_keyboard_multi_selection_navigate(true, true);
        }
        binding.apply_keyboard_multi_selection_navigate(false, true);
      }
      return capture_outcome();
    };

    const auto outcome_a = execute_range_sequence();
    const auto outcome_b = execute_range_sequence();
    const auto ordered = binding.collect_preorder_node_ids();
    const bool expected_shape = ordered.size() > 1 &&
      outcome_a.anchor == ordered.front() &&
      outcome_a.selected == ordered.front() &&
      !outcome_a.focused.empty() &&
      outcome_a.multi == binding.build_authoritative_selection_range(outcome_a.anchor, outcome_a.focused);
    binding.selection_anchor_focus_navigation_integrity_diag.range_extension_shrinks_and_grows_deterministically_from_same_anchor =
      expected_shape &&
      outcome_a.signature == outcome_b.signature &&
      outcome_a.selected == outcome_b.selected &&
      outcome_a.focused == outcome_b.focused &&
      outcome_a.anchor == outcome_b.anchor &&
      outcome_a.multi == outcome_b.multi;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.range_extension_shrinks_and_grows_deterministically_from_same_anchor &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.selected_builder_node_id};
    flow_ok = binding.sync_focus_with_selection_or_fail() && flow_ok;
    const bool filtered_ok = binding.apply_projection_filter("root-001");
    const auto hidden_visible = binding.collect_visible_tree_row_ids();
    const bool hidden_target =
      std::find(hidden_visible.begin(), hidden_visible.end(), "label-001") == hidden_visible.end();
    const bool filtered_nav_ok = binding.apply_tree_navigation(true);
    const auto filtered_outcome = capture_outcome();

    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.selected_builder_node_id};
    flow_ok = binding.sync_focus_with_selection_or_fail() && flow_ok;
    const bool unfiltered_ok = binding.apply_projection_filter("");
    const bool unfiltered_nav_ok = binding.apply_tree_navigation(true);
    const auto unfiltered_outcome = capture_outcome();

    binding.selection_anchor_focus_navigation_integrity_diag.filtered_and_unfiltered_navigation_resolve_same_underlying_targets =
      filtered_ok && hidden_target && filtered_nav_ok && unfiltered_ok && unfiltered_nav_ok &&
      filtered_outcome.selected == unfiltered_outcome.selected &&
      filtered_outcome.focused == unfiltered_outcome.focused &&
      filtered_outcome.anchor == unfiltered_outcome.anchor &&
      filtered_outcome.signature == unfiltered_outcome.signature;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.filtered_and_unfiltered_navigation_resolve_same_underlying_targets &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    bool cycles_ok = true;
    cycles_ok = binding.apply_tree_navigation(true) && cycles_ok;
    cycles_ok = binding.apply_focus_navigation(true) && cycles_ok;
    cycles_ok = binding.apply_keyboard_multi_selection_navigate(true, true) && cycles_ok;
    cycles_ok = binding.apply_keyboard_multi_selection_navigate(false, true) && cycles_ok;
    cycles_ok = binding.apply_projection_filter("root-001") && cycles_ok;
    cycles_ok = binding.apply_projection_filter("") && cycles_ok;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.selected_builder_node_id};
    cycles_ok = binding.sync_focus_with_selection_or_fail() && cycles_ok;
    cycles_ok = binding.apply_tree_parent_child_navigation(false) && cycles_ok;
    cycles_ok = binding.apply_tree_parent_child_navigation(true) && cycles_ok;
    cycles_ok = binding.sync_focus_with_selection_or_fail() && cycles_ok;
    std::string invariant_reason;
    cycles_ok = binding.validate_global_document_invariant(invariant_reason) && cycles_ok;
    binding.selection_anchor_focus_navigation_integrity_diag.global_invariant_preserved_through_anchor_focus_navigation_cycles =
      cycles_ok;
    flow_ok =
      binding.selection_anchor_focus_navigation_integrity_diag.global_invariant_preserved_through_anchor_focus_navigation_cycles &&
      flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct SearchFilterPhase10369Binding {
  BuilderSearchFilterVisibilityIntegrityHardeningDiagnostics& search_filter_visibility_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  std::string& last_action_dispatch_resolved_id;
  bool& last_action_dispatch_success;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<bool(const std::string&)> node_exists;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const ngk::ui::builder::BuilderNode&, const std::string&)> builder_node_matches_projection_query;
  std::function<std::vector<std::string>()> collect_visible_tree_row_ids;
  std::function<std::vector<std::string>()> collect_visible_preview_row_ids;
  std::function<bool(const std::string&)> apply_projection_filter;
  std::function<void()> run_phase103_2;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool(const std::string&, const char*)> invoke_builder_action;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(std::string&)> validate_global_document_invariant;
};

inline bool run_phase103_69_search_filter_phase(SearchFilterPhase10369Binding& binding) {
  binding.search_filter_visibility_integrity_diag = {};
  bool flow_ok = true;

  auto build_expected_visible_ids = [&](const std::string& query) -> std::vector<std::string> {
    std::unordered_map<std::string, bool> memo{};
    std::function<bool(const std::string&)> visible = [&](const std::string& node_id) -> bool {
      auto it = memo.find(node_id);
      if (it != memo.end()) {
        return it->second;
      }
      auto* node = binding.find_node_by_id(node_id);
      if (!node) {
        memo[node_id] = false;
        return false;
      }
      bool is_visible = binding.builder_node_matches_projection_query(*node, query);
      if (!is_visible) {
        for (const auto& child_id : node->child_ids) {
          if (visible(child_id)) {
            is_visible = true;
            break;
          }
        }
      }
      memo[node_id] = is_visible;
      return is_visible;
    };

    std::vector<std::string> ordered_ids{};
    std::function<void(const std::string&)> append = [&](const std::string& node_id) {
      auto* node = binding.find_node_by_id(node_id);
      if (!node) {
        return;
      }
      if (!visible(node_id)) {
        return;
      }
      ordered_ids.push_back(node_id);
      for (const auto& child_id : node->child_ids) {
        append(child_id);
      }
    };
    if (!binding.builder_doc.root_node_id.empty() && binding.node_exists(binding.builder_doc.root_node_id)) {
      append(binding.builder_doc.root_node_id);
    }
    return ordered_ids;
  };

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
    binding.sync_multi_selection_with_primary();
    return binding.apply_projection_filter("");
  };

  struct ActionOutcome {
    bool handled = false;
    std::string signature{};
    std::string selected{};
    std::size_t undo_size = 0;
    bool dirty = false;
    std::string resolved_action{};
    bool dispatch_success = false;
  };

  auto capture_outcome = [&](bool handled) -> ActionOutcome {
    ActionOutcome out{};
    out.handled = handled;
    out.signature = binding.current_document_signature(binding.builder_doc);
    out.selected = binding.selected_builder_node_id;
    out.undo_size = binding.undo_history.size();
    out.dirty = binding.builder_doc_dirty;
    out.resolved_action = binding.last_action_dispatch_resolved_id;
    out.dispatch_success = binding.last_action_dispatch_success;
    return out;
  };

  {
    flow_ok = reset_phase() && flow_ok;
    const std::string before_sig = binding.current_document_signature(binding.builder_doc);
    const auto before_undo = binding.undo_history.size();
    const auto before_redo = binding.redo_stack.size();
    const bool before_dirty = binding.builder_doc_dirty;

    const bool q1_ok = binding.apply_projection_filter("label");
    const bool q2_ok = binding.apply_projection_filter("root");
    const bool q3_ok = binding.apply_projection_filter("");

    const bool unchanged =
      binding.current_document_signature(binding.builder_doc) == before_sig &&
      binding.undo_history.size() == before_undo &&
      binding.redo_stack.size() == before_redo &&
      binding.builder_doc_dirty == before_dirty;

    binding.search_filter_visibility_integrity_diag.search_filter_read_only_no_document_mutation =
      q1_ok && q2_ok && q3_ok && unchanged;
    binding.search_filter_visibility_integrity_diag.search_filter_creates_no_history_or_dirty_side_effect =
      binding.search_filter_visibility_integrity_diag.search_filter_read_only_no_document_mutation;
    flow_ok =
      binding.search_filter_visibility_integrity_diag.search_filter_read_only_no_document_mutation &&
      binding.search_filter_visibility_integrity_diag.search_filter_creates_no_history_or_dirty_side_effect &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const bool filter_ok = binding.apply_projection_filter("label");
    const auto expected = build_expected_visible_ids("label");
    const auto actual = binding.collect_visible_tree_row_ids();
    binding.search_filter_visibility_integrity_diag.filtered_order_matches_authoritative_structure_order =
      filter_ok && expected == actual;
    flow_ok = binding.search_filter_visibility_integrity_diag.filtered_order_matches_authoritative_structure_order && flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.sync_multi_selection_with_primary();
    const bool hide_ok = binding.apply_projection_filter("root-001");
    const auto hidden_visible_ids = binding.collect_visible_tree_row_ids();
    const bool selected_hidden_but_preserved =
      hide_ok && binding.selected_builder_node_id == "label-001" &&
      std::find(hidden_visible_ids.begin(), hidden_visible_ids.end(), "label-001") == hidden_visible_ids.end();

    const bool clear_ok = binding.apply_projection_filter("");
    const auto clear_ids = binding.collect_visible_tree_row_ids();
    const bool reapply_ok = binding.apply_projection_filter("root-001");
    const auto reapply_ids = binding.collect_visible_tree_row_ids();

    binding.search_filter_visibility_integrity_diag.selection_mapping_remains_deterministic_under_filter_changes =
      selected_hidden_but_preserved && clear_ok && reapply_ok && binding.selected_builder_node_id == "label-001";
    binding.search_filter_visibility_integrity_diag.clear_and_reapply_filter_restores_coherent_visible_state =
      clear_ok && reapply_ok && clear_ids == build_expected_visible_ids("") && reapply_ids == hidden_visible_ids;
    flow_ok =
      binding.search_filter_visibility_integrity_diag.selection_mapping_remains_deterministic_under_filter_changes &&
      binding.search_filter_visibility_integrity_diag.clear_and_reapply_filter_restores_coherent_visible_state &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const bool add_ok = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label,
      binding.builder_doc.root_node_id,
      "phase103_69_target");
    flow_ok = add_ok && flow_ok;
    if (auto* node = binding.find_node_by_id("phase103_69_target")) {
      node->text = "phase103_69_target";
    }
    const bool filter_ok = binding.apply_projection_filter("phase103_69_target");
    const auto before_delete = binding.collect_visible_tree_row_ids();
    binding.selected_builder_node_id = "phase103_69_target";
    binding.multi_selected_node_ids = {"phase103_69_target"};
    binding.sync_multi_selection_with_primary();
    const bool delete_ok = binding.invoke_builder_action("ACTION_DELETE_CURRENT", "phase103_69");
    const bool refresh_ok = binding.apply_projection_filter("phase103_69_target");
    const auto after_delete = binding.collect_visible_tree_row_ids();
    const bool present_before =
      std::find(before_delete.begin(), before_delete.end(), "phase103_69_target") != before_delete.end();
    const bool absent_after =
      std::find(after_delete.begin(), after_delete.end(), "phase103_69_target") == after_delete.end();
    binding.search_filter_visibility_integrity_diag.no_stale_deleted_or_moved_nodes_in_results =
      filter_ok && delete_ok && refresh_ok && present_before && absent_after;
    flow_ok = binding.search_filter_visibility_integrity_diag.no_stale_deleted_or_moved_nodes_in_results && flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const bool filter_ok = binding.apply_projection_filter("label-001");
    const auto visible_ids = binding.collect_visible_tree_row_ids();
    const bool has_target = std::find(visible_ids.begin(), visible_ids.end(), "label-001") != visible_ids.end();
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.sync_multi_selection_with_primary();
    const auto filtered_outcome = capture_outcome(binding.invoke_builder_action("ACTION_DELETE_CURRENT", "filtered_view"));
    const bool filtered_removed = !binding.node_exists("label-001");

    flow_ok = reset_phase() && flow_ok;
    const bool unfiltered_ok = binding.apply_projection_filter("");
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.sync_multi_selection_with_primary();
    const auto unfiltered_outcome = capture_outcome(binding.invoke_builder_action("ACTION_DELETE_CURRENT", "unfiltered_view"));

    binding.search_filter_visibility_integrity_diag.actions_from_filtered_view_resolve_against_authoritative_current_state =
      filter_ok && has_target && filtered_outcome.handled && filtered_outcome.dispatch_success &&
      filtered_outcome.resolved_action == "ACTION_DELETE_CURRENT" && filtered_removed;
    binding.search_filter_visibility_integrity_diag.filtered_and_unfiltered_action_results_match_for_same_underlying_state =
      unfiltered_ok &&
      filtered_outcome.handled == unfiltered_outcome.handled &&
      filtered_outcome.signature == unfiltered_outcome.signature &&
      filtered_outcome.undo_size == unfiltered_outcome.undo_size &&
      filtered_outcome.dirty == unfiltered_outcome.dirty;
    flow_ok =
      binding.search_filter_visibility_integrity_diag.actions_from_filtered_view_resolve_against_authoritative_current_state &&
      binding.search_filter_visibility_integrity_diag.filtered_and_unfiltered_action_results_match_for_same_underlying_state &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    const bool filter_ok = binding.apply_projection_filter("label");
    const auto tree_ids = binding.collect_visible_tree_row_ids();
    const auto preview_ids = binding.collect_visible_preview_row_ids();
    binding.search_filter_visibility_integrity_diag.preview_and_bindings_remain_coherent_under_filtered_view =
      filter_ok && binding.check_cross_surface_sync() && tree_ids == preview_ids &&
      (!binding.selected_builder_node_id.empty()) && binding.node_exists(binding.selected_builder_node_id);
    flow_ok = binding.search_filter_visibility_integrity_diag.preview_and_bindings_remain_coherent_under_filtered_view && flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    bool cycles_ok = true;
    const std::array<std::string, 6> queries = {
      "", "label", "root", "no_match_token", "label-001", ""
    };
    for (const auto& query : queries) {
      cycles_ok = binding.apply_projection_filter(query) && cycles_ok;
      std::string invariant_reason;
      cycles_ok = binding.validate_global_document_invariant(invariant_reason) && cycles_ok;
    }
    binding.search_filter_visibility_integrity_diag.global_invariant_preserved_through_search_filter_cycles = cycles_ok;
    flow_ok = binding.search_filter_visibility_integrity_diag.global_invariant_preserved_through_search_filter_cycles && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
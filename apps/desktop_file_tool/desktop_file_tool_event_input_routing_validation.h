#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct EventInputRoutingPhase10358Binding {
  BuilderEventInputRoutingIntegrityDiagnostics& event_input_routing_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& hover_node_id;
  std::string& drag_source_node_id;
  bool& drag_active;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
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
  std::function<bool(std::vector<PreviewExportParityEntry>&, std::string&)> build_preview_click_hit_entries;
  std::function<bool(const std::string&)> node_exists;
  std::function<void()> scrub_stale_lifecycle_references;
  std::function<bool()> apply_keyboard_multi_selection_add_focused;
  std::function<std::vector<std::string>()> collect_preorder_node_ids;
  std::function<bool(bool)> apply_tree_navigation;
  std::function<bool(bool)> apply_focus_navigation;
  std::function<void(std::vector<std::string>&, std::vector<int>&)> collect_visible_preview_rows;
};

inline bool run_phase103_58_event_input_routing_phase(EventInputRoutingPhase10358Binding& binding) {
  bool flow_ok = true;
  binding.event_input_routing_diag = BuilderEventInputRoutingIntegrityDiagnostics{};

  const std::string kStaleRoutingRef{"phase103-58-nonexistent-stale-target"};

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
    if (!binding.build_preview_export_parity_entries(binding.builder_doc, entries, reason, "phase103_58")) {
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
    binding.hover_node_id.clear();
    binding.drag_source_node_id.clear();
    binding.drag_active = false;
    binding.drag_target_preview_node_id.clear();
    binding.drag_target_preview_is_illegal = false;
    binding.sync_multi_selection_with_primary();
    return refresh_all_surfaces();
  };

  flow_ok = reset_phase() && flow_ok;

  {
    std::vector<PreviewExportParityEntry> hit_entries{};
    std::string hit_reason;
    const bool hit_map_ok = binding.build_preview_click_hit_entries(hit_entries, hit_reason);
    bool all_valid = hit_map_ok && !hit_entries.empty();
    bool no_duplicates = true;
    std::vector<std::string> seen_ids{};
    for (const auto& entry : hit_entries) {
      if (entry.node_id.empty() || !binding.node_exists(entry.node_id)) {
        all_valid = false;
        break;
      }
      if (std::find(seen_ids.begin(), seen_ids.end(), entry.node_id) != seen_ids.end()) {
        no_duplicates = false;
        break;
      }
      seen_ids.push_back(entry.node_id);
    }
    binding.event_input_routing_diag.hit_test_returns_single_correct_node =
      hit_map_ok && all_valid && no_duplicates;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    std::vector<PreviewExportParityEntry> hit_entries{};
    std::string hit_reason;
    const bool hit_map_ok = binding.build_preview_click_hit_entries(hit_entries, hit_reason);
    std::vector<std::string> row_ids{};
    std::vector<int> row_depths{};
    binding.collect_visible_preview_rows(row_ids, row_depths);
    bool mapping_consistent = hit_map_ok && (row_ids.size() == hit_entries.size());
    if (mapping_consistent) {
      for (std::size_t idx = 0; idx < hit_entries.size(); ++idx) {
        if (row_ids[idx] != hit_entries[idx].node_id) {
          mapping_consistent = false;
          break;
        }
      }
    }
    bool routing_consistent = mapping_consistent;
    if (mapping_consistent && !hit_entries.empty()) {
      const std::size_t test_idx = hit_entries.size() > 1 ? 1 : 0;
      const std::string& target_id = hit_entries[test_idx].node_id;
      binding.selected_builder_node_id = target_id;
      binding.sync_multi_selection_with_primary();
      const bool remap_ok = binding.remap_selection_or_fail();
      const bool focus_ok = binding.sync_focus_with_selection_or_fail();
      routing_consistent = remap_ok && focus_ok &&
        binding.selected_builder_node_id == target_id &&
        binding.focused_builder_node_id == target_id;
      binding.selected_builder_node_id = binding.builder_doc.root_node_id;
      binding.focused_builder_node_id = binding.builder_doc.root_node_id;
      binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
      binding.sync_multi_selection_with_primary();
    }
    binding.event_input_routing_diag.preview_click_matches_structure_selection =
      mapping_consistent && routing_consistent;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    binding.hover_node_id = kStaleRoutingRef;
    binding.scrub_stale_lifecycle_references();
    const bool hover_cleared = binding.hover_node_id.empty();
    binding.drag_source_node_id = kStaleRoutingRef;
    binding.drag_active = true;
    binding.scrub_stale_lifecycle_references();
    const bool drag_cleared = binding.drag_source_node_id.empty() && !binding.drag_active;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = kStaleRoutingRef;
    const bool stale_focus_rejected = !binding.sync_focus_with_selection_or_fail();
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = kStaleRoutingRef;
    const bool stale_kbfocus_rejected = !binding.apply_keyboard_multi_selection_add_focused();
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    binding.event_input_routing_diag.no_input_routed_to_stale_nodes =
      hover_cleared && drag_cleared && stale_focus_rejected && stale_kbfocus_rejected;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    const std::vector<std::string> order1 = binding.collect_preorder_node_ids();
    const std::vector<std::string> order2 = binding.collect_preorder_node_ids();
    const bool preorder_stable = order1.size() > 1 && order1 == order2;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    const bool nav_fwd = binding.apply_tree_navigation(true);
    const std::string after_fwd = binding.selected_builder_node_id;
    const bool nav_back = binding.apply_tree_navigation(false);
    const std::string after_back = binding.selected_builder_node_id;
    const bool round_trip_ok =
      nav_fwd && nav_back &&
      !after_fwd.empty() && binding.node_exists(after_fwd) &&
      after_back == binding.builder_doc.root_node_id;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    binding.event_input_routing_diag.event_order_deterministic = preorder_stable && round_trip_ok;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    const bool initial_clean = binding.hover_node_id.empty() && binding.drag_source_node_id.empty() && !binding.drag_active;
    binding.hover_node_id = binding.builder_doc.root_node_id;
    const bool valid_hover_sync = binding.check_cross_surface_sync();
    binding.hover_node_id.clear();
    binding.hover_node_id = kStaleRoutingRef;
    const bool stale_hover_present = !binding.node_exists(binding.hover_node_id);
    binding.scrub_stale_lifecycle_references();
    const bool stale_hover_cleared = binding.hover_node_id.empty();
    binding.drag_source_node_id = kStaleRoutingRef;
    binding.drag_active = true;
    const bool stale_drag_present = !binding.node_exists(binding.drag_source_node_id);
    binding.scrub_stale_lifecycle_references();
    const bool stale_drag_cleared = binding.drag_source_node_id.empty() && !binding.drag_active;
    const bool final_sync = binding.check_cross_surface_sync();
    binding.event_input_routing_diag.focus_hover_drag_states_valid =
      initial_clean &&
      valid_hover_sync &&
      stale_hover_present && stale_hover_cleared &&
      stale_drag_present && stale_drag_cleared &&
      final_sync;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = kStaleRoutingRef;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    const bool nav_ok = binding.apply_focus_navigation(true);
    const bool nav_resolved_valid =
      nav_ok &&
      binding.focused_builder_node_id != kStaleRoutingRef &&
      !binding.focused_builder_node_id.empty() &&
      binding.node_exists(binding.focused_builder_node_id);
    binding.focused_builder_node_id = kStaleRoutingRef;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    const bool stale_add_rejected = !binding.apply_keyboard_multi_selection_add_focused();
    const bool stale_not_in_multi =
      std::find(binding.multi_selected_node_ids.begin(), binding.multi_selected_node_ids.end(),
                kStaleRoutingRef) == binding.multi_selected_node_ids.end();
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    binding.event_input_routing_diag.keyboard_targets_current_selection_only =
      nav_resolved_valid && stale_add_rejected && stale_not_in_multi;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.hover_node_id.clear();
    binding.drag_source_node_id.clear();
    binding.sync_multi_selection_with_primary();
    bool rapid_stable = true;
    for (int iter = 0; iter < 10 && rapid_stable; ++iter) {
      const bool nav_ok = binding.apply_tree_navigation(true);
      binding.multi_selected_node_ids = {binding.selected_builder_node_id};
      rapid_stable = nav_ok && refresh_all_surfaces();
    }
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    binding.event_input_routing_diag.rapid_interaction_sequence_stable = rapid_stable;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    const std::string primary = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {primary, primary, kStaleRoutingRef, primary};
    binding.selected_builder_node_id = primary;
    binding.focused_builder_node_id = primary;
    binding.sync_multi_selection_with_primary();
    const bool no_dups = binding.multi_selected_node_ids.size() == 1;
    const bool stale_removed =
      std::find(binding.multi_selected_node_ids.begin(), binding.multi_selected_node_ids.end(),
                kStaleRoutingRef) == binding.multi_selected_node_ids.end();
    const bool primary_intact =
      !binding.multi_selected_node_ids.empty() && binding.multi_selected_node_ids.front() == primary;
    binding.multi_selected_node_ids = {primary};
    binding.sync_multi_selection_with_primary();
    binding.event_input_routing_diag.no_ghost_or_duplicate_event_targets =
      no_dups && stale_removed && primary_intact;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    std::vector<PreviewExportParityEntry> hit_entries{};
    std::string hit_reason;
    const bool hit_map_ok = binding.build_preview_click_hit_entries(hit_entries, hit_reason);
    const std::vector<std::string> preorder = binding.collect_preorder_node_ids();
    bool hierarchy_ok = hit_map_ok && !hit_entries.empty() && !preorder.empty();
    if (hierarchy_ok) {
      std::size_t search_from = 0;
      for (const auto& entry : hit_entries) {
        bool found = false;
        for (std::size_t pi = search_from; pi < preorder.size(); ++pi) {
          if (preorder[pi] == entry.node_id) {
            search_from = pi + 1;
            found = true;
            break;
          }
        }
        if (!found) {
          hierarchy_ok = false;
          break;
        }
      }
    }
    binding.event_input_routing_diag.event_routing_respects_render_hierarchy = hierarchy_ok;
  }
  flow_ok = refresh_all_surfaces() && flow_ok;

  binding.event_input_routing_diag.preview_matches_structure_after_input_sequences =
    preview_matches_structure() &&
    ngk::ui::builder::validate_builder_document(binding.builder_doc, nullptr) &&
    binding.check_cross_surface_sync();

  flow_ok = binding.event_input_routing_diag.hit_test_returns_single_correct_node && flow_ok;
  flow_ok = binding.event_input_routing_diag.preview_click_matches_structure_selection && flow_ok;
  flow_ok = binding.event_input_routing_diag.no_input_routed_to_stale_nodes && flow_ok;
  flow_ok = binding.event_input_routing_diag.event_order_deterministic && flow_ok;
  flow_ok = binding.event_input_routing_diag.focus_hover_drag_states_valid && flow_ok;
  flow_ok = binding.event_input_routing_diag.keyboard_targets_current_selection_only && flow_ok;
  flow_ok = binding.event_input_routing_diag.rapid_interaction_sequence_stable && flow_ok;
  flow_ok = binding.event_input_routing_diag.no_ghost_or_duplicate_event_targets && flow_ok;
  flow_ok = binding.event_input_routing_diag.event_routing_respects_render_hierarchy && flow_ok;
  flow_ok = binding.event_input_routing_diag.preview_matches_structure_after_input_sequences && flow_ok;

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
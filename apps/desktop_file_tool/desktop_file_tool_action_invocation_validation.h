#pragma once

#include <cstddef>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct ActionInvocationPhase10368Binding {
  BuilderActionInvocationIntegrityHardeningDiagnostics& action_invocation_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  std::string& last_action_dispatch_requested_id;
  std::string& last_action_dispatch_resolved_id;
  bool& last_action_dispatch_success;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<bool(int, bool, bool, bool, bool)> handle_builder_shortcut_key_with_modifiers;
  std::function<bool(const std::string&, const char*)> invoke_builder_action;
  std::function<void()> run_phase103_2;
  std::function<bool(const std::string&)> node_exists;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(const std::string&, std::string&)> evaluate_builder_action_eligibility;
  std::function<bool(std::string&)> validate_global_document_invariant;
};

inline bool run_phase103_68_action_invocation_phase(ActionInvocationPhase10368Binding& binding) {
  binding.action_invocation_integrity_diag = {};
  bool flow_ok = true;

  struct InvocationOutcome {
    bool handled = false;
    std::string signature{};
    std::string selected{};
    std::vector<std::string> multi{};
    std::size_t undo_size = 0;
    std::size_t redo_size = 0;
    bool dirty = false;
    std::string clean_baseline{};
    std::string resolved_id{};
    bool dispatch_success = false;
  };

  auto capture_outcome = [&](bool handled) -> InvocationOutcome {
    InvocationOutcome out{};
    out.handled = handled;
    out.signature = binding.current_document_signature(binding.builder_doc);
    out.selected = binding.selected_builder_node_id;
    out.multi = binding.multi_selected_node_ids;
    out.undo_size = binding.undo_history.size();
    out.redo_size = binding.redo_stack.size();
    out.dirty = binding.builder_doc_dirty;
    out.clean_baseline = binding.clean_builder_baseline_signature;
    out.resolved_id = binding.last_action_dispatch_resolved_id;
    out.dispatch_success = binding.last_action_dispatch_success;
    return out;
  };

  auto execute_via_shortcut = [&](const std::string& action_id) -> bool {
    if (action_id == "ACTION_DELETE_CURRENT") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x2E, true, false, false, false);
    }
    if (action_id == "ACTION_INSERT_CONTAINER") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x43, true, false, false, false);
    }
    if (action_id == "ACTION_INSERT_LEAF") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x4C, true, false, false, false);
    }
    if (action_id == "ACTION_UNDO") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x5A, true, false, true, false);
    }
    if (action_id == "ACTION_REDO") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x59, true, false, true, false);
    }
    if (action_id == "ACTION_SAVE") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x53, true, false, true, false);
    }
    if (action_id == "ACTION_LOAD") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x4F, true, false, true, false);
    }
    if (action_id == "ACTION_NEW") {
      return binding.handle_builder_shortcut_key_with_modifiers(0x4E, true, false, true, false);
    }
    return false;
  };

  auto execute_action_for_surface = [&](const std::string& action_id, const char* surface) -> InvocationOutcome {
    bool handled = false;
    const std::string src = surface ? surface : "palette";
    if (src == "shortcut") {
      handled = execute_via_shortcut(action_id);
    } else {
      handled = binding.invoke_builder_action(action_id, surface);
    }
    return capture_outcome(handled);
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
    if (binding.node_exists("label-001")) {
      binding.selected_builder_node_id = "label-001";
    } else {
      binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    }
    binding.multi_selected_node_ids = {binding.selected_builder_node_id};
    binding.sync_multi_selection_with_primary();
    const bool remap_ok = binding.remap_selection_or_fail();
    const bool focus_ok = binding.sync_focus_with_selection_or_fail();
    const bool inspector_ok = binding.refresh_inspector_or_fail();
    const bool preview_ok = binding.refresh_preview_or_fail();
    const bool sync_ok = binding.check_cross_surface_sync();
    return remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;
  };

  auto outcomes_identical = [&](const InvocationOutcome& a, const InvocationOutcome& b) -> bool {
    return a.handled == b.handled &&
           a.signature == b.signature &&
           a.selected == b.selected &&
           a.multi == b.multi &&
           a.undo_size == b.undo_size &&
           a.redo_size == b.redo_size &&
           a.dirty == b.dirty &&
           a.clean_baseline == b.clean_baseline;
  };

  {
    flow_ok = reset_phase() && flow_ok;
    auto palette_outcome = execute_action_for_surface("ACTION_DELETE_CURRENT", "palette");
    flow_ok = reset_phase() && flow_ok;
    auto button_outcome = execute_action_for_surface("ACTION_DELETE_CURRENT", "button");
    flow_ok = reset_phase() && flow_ok;
    auto shortcut_outcome = execute_action_for_surface("ACTION_DELETE_CURRENT", "shortcut");

    binding.action_invocation_integrity_diag.same_action_id_same_result_across_invocation_surfaces =
      outcomes_identical(palette_outcome, button_outcome) &&
      outcomes_identical(button_outcome, shortcut_outcome);
    binding.action_invocation_integrity_diag.cross_surface_invocation_produces_identical_history_and_selection =
      binding.action_invocation_integrity_diag.same_action_id_same_result_across_invocation_surfaces;
    flow_ok =
      binding.action_invocation_integrity_diag.same_action_id_same_result_across_invocation_surfaces &&
      binding.action_invocation_integrity_diag.cross_surface_invocation_produces_identical_history_and_selection &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    const std::string before_sig = binding.current_document_signature(binding.builder_doc);
    const std::string before_baseline = binding.clean_builder_baseline_signature;
    const auto before_undo = binding.undo_history.size();
    const auto before_redo = binding.redo_stack.size();
    const bool before_dirty = binding.builder_doc_dirty;

    const auto blocked_palette = execute_action_for_surface("ACTION_DELETE_CURRENT", "palette");
    const auto blocked_button = execute_action_for_surface("ACTION_DELETE_CURRENT", "button");
    const auto blocked_shortcut = execute_action_for_surface("ACTION_DELETE_CURRENT", "shortcut");
    const bool stable_after_block =
      binding.current_document_signature(binding.builder_doc) == before_sig &&
      binding.clean_builder_baseline_signature == before_baseline &&
      binding.undo_history.size() == before_undo &&
      binding.redo_stack.size() == before_redo &&
      binding.builder_doc_dirty == before_dirty;

    binding.action_invocation_integrity_diag.ineligible_actions_fail_closed_without_mutation =
      !blocked_palette.handled && !blocked_button.handled && !blocked_shortcut.handled && stable_after_block;
    binding.action_invocation_integrity_diag.failed_invocation_creates_no_history_or_dirty_side_effect =
      binding.action_invocation_integrity_diag.ineligible_actions_fail_closed_without_mutation;
    flow_ok =
      binding.action_invocation_integrity_diag.ineligible_actions_fail_closed_without_mutation &&
      binding.action_invocation_integrity_diag.failed_invocation_creates_no_history_or_dirty_side_effect &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    std::string reason_current{};
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.sync_multi_selection_with_primary();
    const bool eligible_valid = binding.evaluate_builder_action_eligibility("ACTION_DELETE_CURRENT", reason_current);

    std::string reason_root{};
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    const bool eligible_root = binding.evaluate_builder_action_eligibility("ACTION_DELETE_CURRENT", reason_root);

    const std::string before_sig = binding.current_document_signature(binding.builder_doc);
    binding.selected_builder_node_id = "stale-node-id";
    binding.multi_selected_node_ids = {"stale-node-id"};
    binding.sync_multi_selection_with_primary();
    const auto stale_attempt = execute_action_for_surface("ACTION_DELETE_CURRENT", "palette");
    const bool stale_safe = !stale_attempt.handled && binding.current_document_signature(binding.builder_doc) == before_sig;

    binding.action_invocation_integrity_diag.action_eligibility_checked_against_current_state =
      eligible_valid && !eligible_root && !reason_root.empty();
    binding.action_invocation_integrity_diag.no_stale_selection_or_target_context_used = stale_safe;
    flow_ok =
      binding.action_invocation_integrity_diag.action_eligibility_checked_against_current_state &&
      binding.action_invocation_integrity_diag.no_stale_selection_or_target_context_used &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.sync_multi_selection_with_primary();
    std::string reason_ok{};
    const bool metadata_ok = binding.evaluate_builder_action_eligibility("ACTION_DELETE_CURRENT", reason_ok);
    const auto executed_ok = execute_action_for_surface("ACTION_DELETE_CURRENT", "palette");
    const bool dispatch_ok = executed_ok.handled && executed_ok.dispatch_success &&
      (binding.last_action_dispatch_requested_id == "ACTION_DELETE_CURRENT") &&
      (executed_ok.resolved_id == "ACTION_DELETE_CURRENT");

    flow_ok = reset_phase() && flow_ok;
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    std::string reason_blocked{};
    const bool metadata_blocked = binding.evaluate_builder_action_eligibility("ACTION_DELETE_CURRENT", reason_blocked);
    const auto executed_blocked = execute_action_for_surface("ACTION_DELETE_CURRENT", "palette");
    const bool dispatch_blocked_ok =
      !metadata_blocked && !executed_blocked.handled &&
      !binding.last_action_dispatch_success &&
      binding.last_action_dispatch_requested_id == "ACTION_DELETE_CURRENT";

    binding.action_invocation_integrity_diag.action_metadata_matches_execution_eligibility =
      metadata_ok && executed_ok.handled && !metadata_blocked && !executed_blocked.handled;
    binding.action_invocation_integrity_diag.no_command_dispatch_mismatch_or_wrong_handler_resolution =
      dispatch_ok && dispatch_blocked_ok;
    flow_ok =
      binding.action_invocation_integrity_diag.action_metadata_matches_execution_eligibility &&
      binding.action_invocation_integrity_diag.no_command_dispatch_mismatch_or_wrong_handler_resolution &&
      flow_ok;
  }

  {
    flow_ok = reset_phase() && flow_ok;
    bool seq_ok = true;
    binding.selected_builder_node_id = "label-001";
    binding.multi_selected_node_ids = {"label-001"};
    binding.sync_multi_selection_with_primary();
    seq_ok = execute_action_for_surface("ACTION_DELETE_CURRENT", "palette").handled && seq_ok;
    {
      std::string invariant_reason;
      seq_ok = binding.validate_global_document_invariant(invariant_reason) && seq_ok;
    }
    seq_ok = execute_action_for_surface("ACTION_UNDO", "shortcut").handled && seq_ok;
    {
      std::string invariant_reason;
      seq_ok = binding.validate_global_document_invariant(invariant_reason) && seq_ok;
    }
    seq_ok = execute_action_for_surface("ACTION_REDO", "button").handled && seq_ok;
    {
      std::string invariant_reason;
      seq_ok = binding.validate_global_document_invariant(invariant_reason) && seq_ok;
    }
    seq_ok = execute_action_for_surface("ACTION_SAVE", "shortcut").handled && seq_ok;
    {
      std::string invariant_reason;
      seq_ok = binding.validate_global_document_invariant(invariant_reason) && seq_ok;
    }
    seq_ok = execute_action_for_surface("ACTION_NEW_FORCE_DISCARD", "palette").handled && seq_ok;
    {
      std::string invariant_reason;
      seq_ok = binding.validate_global_document_invariant(invariant_reason) && seq_ok;
    }

    binding.action_invocation_integrity_diag.global_invariant_preserved_through_all_action_invocations = seq_ok;
    flow_ok = binding.action_invocation_integrity_diag.global_invariant_preserved_through_all_action_invocations && flow_ok;
  }

  {
    auto run_det_sequence = [&]() -> InvocationOutcome {
      reset_phase();
      binding.selected_builder_node_id = "label-001";
      binding.multi_selected_node_ids = {"label-001"};
      binding.sync_multi_selection_with_primary();
      execute_action_for_surface("ACTION_INSERT_LEAF", "button");
      execute_action_for_surface("ACTION_SAVE", "shortcut");
      execute_action_for_surface("ACTION_NEW_FORCE_DISCARD", "palette");
      execute_action_for_surface("ACTION_INSERT_CONTAINER", "shortcut");
      execute_action_for_surface("ACTION_UNDO", "button");
      execute_action_for_surface("ACTION_REDO", "shortcut");
      execute_action_for_surface("ACTION_SAVE", "button");
      return capture_outcome(true);
    };

    const auto run_a = run_det_sequence();
    const auto run_b = run_det_sequence();
    binding.action_invocation_integrity_diag.deterministic_invocation_sequence_stable = outcomes_identical(run_a, run_b);
    flow_ok = binding.action_invocation_integrity_diag.deterministic_invocation_sequence_stable && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
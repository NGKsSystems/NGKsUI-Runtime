#include "desktop_file_tool_history_controller.h"

#include <algorithm>

namespace desktop_file_tool {
namespace {

void clear_transient_builder_restore_state(HistoryControllerBinding& binding) {
  binding.cp.inline_edit_active = false;
  binding.cp.inline_edit_node_id.clear();
  binding.cp.inline_edit_buffer.clear();
  binding.cp.inline_edit_original_text.clear();
  binding.cp.preview_inline_loaded_text.clear();
  binding.cp.focused_builder_node_id.clear();
  binding.cp.drag_source_node_id.clear();
  binding.cp.drag_active = false;
  binding.cp.hover_node_id.clear();
  binding.cp.drag_target_preview_node_id.clear();
  binding.cp.drag_target_preview_is_illegal = false;
  binding.cp.preview_visual_feedback_node_id.clear();
  binding.cp.tree_visual_feedback_node_id.clear();
  binding.preview_visual_feedback_message.clear();
}

std::string resolve_focus_id(const HistoryCheckpointBinding& checkpoint_binding,
                             const std::string& preferred_focus_id,
                             const std::string& selected_id) {
  if (!preferred_focus_id.empty() &&
      checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, preferred_focus_id)) {
    return preferred_focus_id;
  }
  if (!selected_id.empty() &&
      checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, selected_id)) {
    return selected_id;
  }
  if (!checkpoint_binding.builder_doc.root_node_id.empty() &&
      checkpoint_binding.node_exists_in_document(
        checkpoint_binding.builder_doc,
        checkpoint_binding.builder_doc.root_node_id)) {
    return checkpoint_binding.builder_doc.root_node_id;
  }
  return std::string{};
}

std::string resolve_anchor_id(const HistoryCheckpointBinding& checkpoint_binding,
                              const std::string& preferred_anchor_id,
                              const std::string& selected_id,
                              const std::vector<std::string>& multi_selected_ids) {
  if (!preferred_anchor_id.empty() &&
      checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, preferred_anchor_id) &&
      std::find(multi_selected_ids.begin(), multi_selected_ids.end(), preferred_anchor_id) != multi_selected_ids.end()) {
    return preferred_anchor_id;
  }
  if (!selected_id.empty() &&
      checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, selected_id) &&
      std::find(multi_selected_ids.begin(), multi_selected_ids.end(), selected_id) != multi_selected_ids.end()) {
    return selected_id;
  }
  return std::string{};
}

bool restore_history_state(HistoryControllerBinding& binding,
                           const CommandHistoryEntry& raw_entry,
                           bool restore_before,
                           bool defer_refresh) {
  CommandHistoryEntry entry = raw_entry;
  if (!binding.on_normalize_history_entry(entry)) {
    binding.undefined_state_detected = true;
    return false;
  }

  const std::string prior_focus_id = binding.cp.focused_builder_node_id;
  const std::string prior_anchor_id = binding.cp.builder_selection_anchor_node_id;
  clear_transient_builder_restore_state(binding);

  auto& checkpoint_binding = binding.cp;
  const auto& nodes = restore_before ? entry.before_nodes : entry.after_nodes;
  const auto& root_id = restore_before ? entry.before_root_node_id : entry.after_root_node_id;
  const auto& selected_id = restore_before ? entry.before_selected_id : entry.after_selected_id;
  const auto& multi_selected_ids = restore_before ? entry.before_multi_selected_ids : entry.after_multi_selected_ids;
  const auto& focus_id = restore_before ? entry.before_focused_id : entry.after_focused_id;
  const auto& anchor_id = restore_before ? entry.before_anchor_id : entry.after_anchor_id;
  const auto& filter_query = restore_before ? entry.before_filter_query : entry.after_filter_query;
  const int tree_scroll_offset = restore_before ? entry.before_tree_scroll_offset_y : entry.after_tree_scroll_offset_y;
  const int preview_scroll_offset = restore_before ? entry.before_preview_scroll_offset_y : entry.after_preview_scroll_offset_y;
  const std::string raw_focus_id = restore_before ? raw_entry.before_focused_id : raw_entry.after_focused_id;
  const std::string raw_anchor_id = restore_before ? raw_entry.before_anchor_id : raw_entry.after_anchor_id;
  const bool preserve_prior_focus_anchor = !restore_before && entry.command_type == "typed_insert";

  checkpoint_binding.builder_doc.nodes = nodes;
  checkpoint_binding.builder_doc.root_node_id = root_id;
  checkpoint_binding.selected_builder_node_id = selected_id;
  checkpoint_binding.multi_selected_node_ids = multi_selected_ids;
  checkpoint_binding.set_builder_projection_filter_state(filter_query);
  checkpoint_binding.set_tree_scroll_offset_y(tree_scroll_offset);
  checkpoint_binding.set_preview_scroll_offset_y(preview_scroll_offset);

  const std::string desired_focus_id =
    (!raw_focus_id.empty() && checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, raw_focus_id))
      ? raw_focus_id
      : focus_id;
  std::string desired_anchor_id =
    (!raw_anchor_id.empty() && checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, raw_anchor_id))
      ? raw_anchor_id
      : anchor_id;
  std::string resolved_focus_id = resolve_focus_id(
    checkpoint_binding,
    desired_focus_id,
    checkpoint_binding.selected_builder_node_id);
  if (preserve_prior_focus_anchor &&
      !prior_focus_id.empty() &&
      checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, prior_focus_id)) {
    resolved_focus_id = prior_focus_id;
  }
  if (preserve_prior_focus_anchor &&
      !prior_anchor_id.empty() &&
      checkpoint_binding.node_exists_in_document(checkpoint_binding.builder_doc, prior_anchor_id)) {
    desired_anchor_id = prior_anchor_id;
  }
  const std::string resolved_anchor_id = resolve_anchor_id(
    checkpoint_binding,
    desired_anchor_id,
    checkpoint_binding.selected_builder_node_id,
    checkpoint_binding.multi_selected_node_ids);
  checkpoint_binding.restore_exact_selection_focus_anchor_state(resolved_focus_id, resolved_anchor_id);

  if (defer_refresh) {
    checkpoint_binding.update_add_child_target_display();
    return binding.on_sync_history();
  }

  checkpoint_binding.refresh_inspector_or_fail();
  checkpoint_binding.refresh_preview_or_fail();
  checkpoint_binding.update_add_child_target_display();
  return true;
}

}  // namespace

void clear_history_coalesce_request(HistoryControllerBinding& binding) {
  binding.history_coalesce_request_active = false;
  binding.history_coalesce_request_key.clear();
  binding.history_coalesce_request_operation_class.clear();
}

void request_history_coalescing(HistoryControllerBinding& binding,
                                const std::string& operation_class,
                                const std::string& coalescing_key) {
  if (operation_class.empty() || coalescing_key.empty()) {
    clear_history_coalesce_request(binding);
    return;
  }

  binding.history_coalesce_request_active = true;
  binding.history_coalesce_request_operation_class = operation_class;
  binding.history_coalesce_request_key = coalescing_key;
}

void break_history_coalescing_boundary(HistoryControllerBinding& binding) {
  clear_history_coalesce_request(binding);
  binding.history_boundary_epoch += 1;
}

void push_to_history(HistoryControllerBinding& binding,
                     const std::string& command_type,
                     const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
                     const std::string& before_root,
                     const std::string& before_sel,
                     const std::vector<std::string>* before_multi,
                     const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
                     const std::string& after_root,
                     const std::string& after_sel,
                     const std::vector<std::string>* after_multi,
                     const BuilderMutationCheckpoint* before_cp_opt,
                     const BuilderMutationCheckpoint* after_cp_opt,
                     const std::string& operation_class,
                     const std::string& coalescing_key) {
  const BuilderMutationCheckpoint captured_after_state = binding.on_capture_checkpoint();
  const BuilderMutationCheckpoint& after_state = after_cp_opt != nullptr ? *after_cp_opt : captured_after_state;

  CommandHistoryEntry entry{};
  entry.command_type = command_type;
  entry.operation_class = binding.history_coalesce_request_active
    ? binding.history_coalesce_request_operation_class
    : (operation_class.empty() ? command_type : operation_class);
  entry.coalescing_key = binding.history_coalesce_request_active
    ? binding.history_coalesce_request_key
    : coalescing_key;
  entry.boundary_epoch = binding.history_boundary_epoch;
  entry.logical_action_span = 1;

  entry.before_nodes = before_nodes;
  entry.before_root_node_id = before_root;
  entry.before_selected_id = before_sel;
  entry.before_multi_selected_ids = before_multi != nullptr
    ? *before_multi
    : (before_sel.empty() ? std::vector<std::string>{} : std::vector<std::string>{before_sel});
  entry.before_focused_id = before_cp_opt != nullptr ? before_cp_opt->focused_id : before_sel;
  entry.before_anchor_id = before_cp_opt != nullptr ? before_cp_opt->anchor_id : before_sel;
  entry.before_filter_query = before_cp_opt != nullptr
    ? before_cp_opt->filter_query
    : binding.cp.builder_projection_filter_query;
  entry.before_tree_scroll_offset_y = before_cp_opt != nullptr
    ? before_cp_opt->tree_scroll_offset_y
    : binding.cp.get_tree_scroll_offset_y();
  entry.before_preview_scroll_offset_y = before_cp_opt != nullptr
    ? before_cp_opt->preview_scroll_offset_y
    : binding.cp.get_preview_scroll_offset_y();

  entry.after_nodes = after_nodes;
  entry.after_root_node_id = after_root;
  entry.after_selected_id = after_sel;
  entry.after_multi_selected_ids = after_multi != nullptr
    ? *after_multi
    : (after_sel.empty() ? std::vector<std::string>{} : std::vector<std::string>{after_sel});
  entry.after_focused_id = after_state.focused_id;
  entry.after_anchor_id = after_state.anchor_id;
  entry.after_filter_query = after_state.filter_query;
  entry.after_tree_scroll_offset_y = after_state.tree_scroll_offset_y;
  entry.after_preview_scroll_offset_y = after_state.preview_scroll_offset_y;

  if (!binding.on_normalize_history_entry(entry)) {
    binding.undefined_state_detected = true;
    clear_history_coalesce_request(binding);
    return;
  }

  bool coalesced = false;
  if (binding.history_coalesce_request_active && !binding.undo_history.empty()) {
    auto& previous = binding.undo_history.back();
    const bool can_coalesce = previous.command_type == entry.command_type &&
      previous.operation_class == entry.operation_class &&
      previous.coalescing_key == entry.coalescing_key &&
      previous.boundary_epoch == entry.boundary_epoch &&
      previous.after_selected_id == entry.before_selected_id &&
      previous.after_multi_selected_ids == entry.before_multi_selected_ids;
    if (can_coalesce) {
      previous.after_nodes = entry.after_nodes;
      previous.after_root_node_id = entry.after_root_node_id;
      previous.after_selected_id = entry.after_selected_id;
      previous.after_multi_selected_ids = entry.after_multi_selected_ids;
      previous.logical_action_span += 1;
      coalesced = true;
    }
  }

  if (!coalesced) {
    binding.undo_history.push_back(std::move(entry));
  }
  binding.redo_stack.clear();
  binding.undoredo_diag.command_history_present = !binding.undo_history.empty();
  clear_history_coalesce_request(binding);

  if (!binding.on_enforce_global_invariant(after_state, "push_to_history")) {
    binding.undefined_state_detected = true;
  }
}

bool apply_undo_command(HistoryControllerBinding& binding,
                        bool defer_surface_refresh,
                        bool finalize_surface_refresh) {
  const BuilderMutationCheckpoint checkpoint = binding.on_capture_checkpoint();
  break_history_coalescing_boundary(binding);

  if (binding.undo_history.empty()) {
    return false;
  }

  const CommandHistoryEntry entry = binding.undo_history.back();
  if (!restore_history_state(binding, entry, true, defer_surface_refresh)) {
    return false;
  }

  binding.redo_stack.push_back(entry);
  binding.undo_history.pop_back();

  const bool dirty_ok = binding.on_recompute_dirty(true);
  binding.cp.update_add_child_target_display();
  const bool sync_ok = defer_surface_refresh ? true : binding.on_sync_history();
  bool final_surface_ok = true;
  if (defer_surface_refresh && finalize_surface_refresh) {
    final_surface_ok = binding.on_finalize_history();
  }
  if (!(dirty_ok && sync_ok && final_surface_ok)) {
    return false;
  }

  return binding.on_enforce_global_invariant(checkpoint, "apply_undo_command");
}

bool apply_redo_command(HistoryControllerBinding& binding,
                        bool defer_surface_refresh,
                        bool finalize_surface_refresh) {
  const BuilderMutationCheckpoint checkpoint = binding.on_capture_checkpoint();
  break_history_coalescing_boundary(binding);

  if (binding.redo_stack.empty()) {
    return false;
  }

  const CommandHistoryEntry entry = binding.redo_stack.back();
  if (!restore_history_state(binding, entry, false, defer_surface_refresh)) {
    return false;
  }

  binding.undo_history.push_back(entry);
  binding.redo_stack.pop_back();

  const bool dirty_ok = binding.on_recompute_dirty(true);
  binding.cp.update_add_child_target_display();
  const bool sync_ok = defer_surface_refresh ? true : binding.on_sync_history();
  bool final_surface_ok = true;
  if (defer_surface_refresh && finalize_surface_refresh) {
    final_surface_ok = binding.on_finalize_history();
  }
  if (!(dirty_ok && sync_ok && final_surface_ok)) {
    return false;
  }

  return binding.on_enforce_global_invariant(checkpoint, "apply_redo_command");
}

bool apply_history_replay_batch(HistoryControllerBinding& binding, bool undo_direction, std::size_t count) {
  if (count == 0) {
    return true;
  }

  for (std::size_t index = 0; index < count; ++index) {
    const bool finalize_surface_refresh = (index + 1) == count;
    const bool ok = undo_direction
      ? apply_undo_command(binding, true, finalize_surface_refresh)
      : apply_redo_command(binding, true, finalize_surface_refresh);
    if (!ok) {
      if (!finalize_surface_refresh) {
        binding.on_finalize_history();
      }
      return false;
    }
  }

  return true;
}

}  // namespace desktop_file_tool

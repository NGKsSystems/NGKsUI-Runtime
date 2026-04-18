#include "desktop_file_tool_history_checkpoint.h"

#include <algorithm>

BuilderMutationCheckpoint capture_mutation_checkpoint(const HistoryCheckpointBinding& binding) {
  BuilderMutationCheckpoint checkpoint{};
  checkpoint.doc = binding.builder_doc;
  checkpoint.selected_id = binding.selected_builder_node_id;
  checkpoint.multi_selected_ids = binding.multi_selected_node_ids;
  checkpoint.focused_id = binding.focused_builder_node_id;
  checkpoint.anchor_id = binding.builder_selection_anchor_node_id;
  checkpoint.filter_query = binding.builder_projection_filter_query;
  checkpoint.inspector_binding_id = binding.inspector_binding_node_id;
  checkpoint.preview_binding_id = binding.preview_binding_node_id;
  checkpoint.hover_id = binding.hover_node_id;
  checkpoint.drag_source_id = binding.drag_source_node_id;
  checkpoint.drag_active = binding.drag_active;
  checkpoint.drag_target_preview_id = binding.drag_target_preview_node_id;
  checkpoint.drag_target_preview_illegal = binding.drag_target_preview_is_illegal;
  checkpoint.drag_target_preview_parent_id = binding.drag_target_preview_parent_id;
  checkpoint.drag_target_preview_insert_index = binding.drag_target_preview_insert_index;
  checkpoint.drag_target_preview_resolution_kind = binding.drag_target_preview_resolution_kind;
  checkpoint.preview_feedback_node_id = binding.preview_visual_feedback_node_id;
  checkpoint.tree_feedback_node_id = binding.tree_visual_feedback_node_id;
  checkpoint.inline_edit_active = binding.inline_edit_active;
  checkpoint.inline_edit_node_id = binding.inline_edit_node_id;
  checkpoint.inline_edit_buffer = binding.inline_edit_buffer;
  checkpoint.inline_edit_original_text = binding.inline_edit_original_text;
  checkpoint.preview_inline_loaded_text = binding.preview_inline_loaded_text;
  checkpoint.undo_history = binding.undo_history;
  checkpoint.redo_stack = binding.redo_stack;
  checkpoint.has_saved_builder_snapshot = binding.has_saved_builder_snapshot;
  checkpoint.last_saved_builder_serialized = binding.last_saved_builder_serialized;
  checkpoint.has_clean_builder_baseline_signature = binding.has_clean_builder_baseline_signature;
  checkpoint.clean_builder_baseline_signature = binding.clean_builder_baseline_signature;
  checkpoint.builder_doc_dirty = binding.builder_doc_dirty;
  checkpoint.tree_scroll_offset_y = binding.get_tree_scroll_offset_y();
  checkpoint.preview_scroll_offset_y = binding.get_preview_scroll_offset_y();
  return checkpoint;
}

void restore_mutation_checkpoint(HistoryCheckpointBinding& binding, const BuilderMutationCheckpoint& checkpoint) {
  binding.builder_doc = checkpoint.doc;
  binding.selected_builder_node_id = checkpoint.selected_id;
  binding.multi_selected_node_ids = checkpoint.multi_selected_ids;
  binding.set_builder_projection_filter_state(checkpoint.filter_query);
  binding.inspector_binding_node_id = checkpoint.inspector_binding_id;
  binding.preview_binding_node_id = checkpoint.preview_binding_id;
  binding.hover_node_id = checkpoint.hover_id;
  binding.drag_source_node_id = checkpoint.drag_source_id;
  binding.drag_active = checkpoint.drag_active;
  binding.drag_target_preview_node_id = checkpoint.drag_target_preview_id;
  binding.drag_target_preview_is_illegal = checkpoint.drag_target_preview_illegal;
  binding.drag_target_preview_parent_id = checkpoint.drag_target_preview_parent_id;
  binding.drag_target_preview_insert_index = checkpoint.drag_target_preview_insert_index;
  binding.drag_target_preview_resolution_kind = checkpoint.drag_target_preview_resolution_kind;
  binding.preview_visual_feedback_node_id = checkpoint.preview_feedback_node_id;
  binding.tree_visual_feedback_node_id = checkpoint.tree_feedback_node_id;
  binding.inline_edit_active = checkpoint.inline_edit_active;
  binding.inline_edit_node_id = checkpoint.inline_edit_node_id;
  binding.inline_edit_buffer = checkpoint.inline_edit_buffer;
  binding.inline_edit_original_text = checkpoint.inline_edit_original_text;
  binding.preview_inline_loaded_text = checkpoint.preview_inline_loaded_text;
  binding.undo_history = checkpoint.undo_history;
  binding.redo_stack = checkpoint.redo_stack;
  binding.has_saved_builder_snapshot = checkpoint.has_saved_builder_snapshot;
  binding.last_saved_builder_serialized = checkpoint.last_saved_builder_serialized;
  binding.has_clean_builder_baseline_signature = checkpoint.has_clean_builder_baseline_signature;
  binding.clean_builder_baseline_signature = checkpoint.clean_builder_baseline_signature;
  binding.builder_doc_dirty = checkpoint.builder_doc_dirty;
  binding.set_tree_scroll_offset_y(checkpoint.tree_scroll_offset_y);
  binding.set_preview_scroll_offset_y(checkpoint.preview_scroll_offset_y);
  binding.restore_exact_selection_focus_anchor_state(checkpoint.focused_id, checkpoint.anchor_id);
  binding.refresh_inspector_or_fail();
  binding.refresh_preview_or_fail();
  binding.update_add_child_target_display();
}

bool validate_command_history_snapshot(const HistoryCheckpointBinding& binding, const std::vector<CommandHistoryEntry>& history) {
  auto validate_selection_refs = [&](const ngk::ui::builder::BuilderDocument& doc,
                                     const std::string& selected_id,
                                     const std::vector<std::string>& multi_ids) -> bool {
    if (selected_id.empty() || !binding.node_exists_in_document(doc, selected_id)) {
      return false;
    }
    if (multi_ids.empty() || multi_ids.front() != selected_id) {
      return false;
    }

    std::vector<std::string> seen_ids{};
    for (const auto& node_id : multi_ids) {
      if (node_id.empty() ||
          !binding.node_exists_in_document(doc, node_id) ||
          std::find(seen_ids.begin(), seen_ids.end(), node_id) != seen_ids.end()) {
        return false;
      }
      seen_ids.push_back(node_id);
    }
    return true;
  };

  for (const auto& entry : history) {
    ngk::ui::builder::BuilderDocument before_doc{};
    before_doc.root_node_id = entry.before_root_node_id;
    before_doc.nodes = entry.before_nodes;

    ngk::ui::builder::BuilderDocument after_doc{};
    after_doc.root_node_id = entry.after_root_node_id;
    after_doc.nodes = entry.after_nodes;

    std::string before_error;
    std::string after_error;
    if (!ngk::ui::builder::validate_builder_document(before_doc, &before_error) ||
        !ngk::ui::builder::validate_builder_document(after_doc, &after_error)) {
      return false;
    }

    if (!validate_selection_refs(before_doc, entry.before_selected_id, entry.before_multi_selected_ids) ||
        !validate_selection_refs(after_doc, entry.after_selected_id, entry.after_multi_selected_ids)) {
      return false;
    }

    if ((!entry.before_focused_id.empty() &&
         !binding.node_exists_in_document(before_doc, entry.before_focused_id)) ||
        (!entry.after_focused_id.empty() &&
         !binding.node_exists_in_document(after_doc, entry.after_focused_id))) {
      return false;
    }

    const bool before_anchor_valid = entry.before_anchor_id.empty() ||
      (binding.node_exists_in_document(before_doc, entry.before_anchor_id) &&
       std::find(entry.before_multi_selected_ids.begin(),
                 entry.before_multi_selected_ids.end(),
                 entry.before_anchor_id) != entry.before_multi_selected_ids.end());
    const bool after_anchor_valid = entry.after_anchor_id.empty() ||
      (binding.node_exists_in_document(after_doc, entry.after_anchor_id) &&
       std::find(entry.after_multi_selected_ids.begin(),
                 entry.after_multi_selected_ids.end(),
                 entry.after_anchor_id) != entry.after_multi_selected_ids.end());
    if (!before_anchor_valid || !after_anchor_valid) {
      return false;
    }
  }

  return true;
}


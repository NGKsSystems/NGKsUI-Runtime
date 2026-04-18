#pragma once

#include "desktop_file_tool_history_checkpoint.h"

#include <cstddef>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace desktop_file_tool {

struct DocumentLifecycleBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  bool& builder_persistence_io_in_progress;
  bool& builder_doc_dirty;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;

  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
  std::vector<std::string>& multi_selected_node_ids;
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

  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;

  std::function<void(const std::string&, bool)> on_reset_runtime_state_after_document_replacement;
  std::function<bool()> on_commit_clean_document_baseline;
  std::function<void()> on_reset_scroll_offsets;
  std::function<BuilderMutationCheckpoint()> on_capture_checkpoint;
  std::function<void(const BuilderMutationCheckpoint&)> on_restore_checkpoint;
  std::function<bool(const std::string&)> on_node_exists;
  std::function<bool()> on_remap_selection;
  std::function<bool()> on_sync_focus;
  std::function<bool()> on_refresh_inspector;
  std::function<bool()> on_refresh_preview;
  std::function<bool()> on_check_cross_surface_sync;
  std::function<bool(const BuilderMutationCheckpoint&, const char*)> on_enforce_global_invariant;
  std::function<bool(ngk::ui::builder::BuilderDocument&, std::string&)> on_create_default_document;
  std::function<void()> on_update_labels;
};

bool load_builder_document_from_path(DocumentLifecycleBinding& binding, const std::filesystem::path& path);
bool save_builder_document_to_path(DocumentLifecycleBinding& binding, const std::filesystem::path& path);
bool apply_save_document_command(DocumentLifecycleBinding& binding, const std::filesystem::path& path);
bool apply_load_document_command(DocumentLifecycleBinding& binding, const std::filesystem::path& path, bool allow_discard_dirty = false);
bool apply_new_document_command(DocumentLifecycleBinding& binding, bool allow_discard_dirty = false);

} // namespace desktop_file_tool
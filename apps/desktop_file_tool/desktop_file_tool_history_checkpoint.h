#pragma once

#include <algorithm>
#include <functional>
#include <string>
#include <vector>
#include <engine/ui/builder/builder_document.h>
#include "desktop_file_tool_diagnostics.h"

struct BuilderMutationCheckpoint {
  ngk::ui::builder::BuilderDocument doc{};
  std::string selected_id{};
  std::vector<std::string> multi_selected_ids{};
  std::string focused_id{};
  std::string anchor_id{};
  std::string filter_query{};
  std::string inspector_binding_id{};
  std::string preview_binding_id{};
  std::string hover_id{};
  std::string drag_source_id{};
  bool drag_active = false;
  std::string drag_target_preview_id{};
  bool drag_target_preview_illegal = false;
  std::string drag_target_preview_parent_id{};
  std::size_t drag_target_preview_insert_index = 0;
  std::string drag_target_preview_resolution_kind{};
  std::string preview_feedback_node_id{};
  std::string tree_feedback_node_id{};
  bool inline_edit_active = false;
  std::string inline_edit_node_id{};
  std::string inline_edit_buffer{};
  std::string inline_edit_original_text{};
  std::string preview_inline_loaded_text{};
  std::vector<CommandHistoryEntry> undo_history{};
  std::vector<CommandHistoryEntry> redo_stack{};
  bool has_saved_builder_snapshot = false;
  std::string last_saved_builder_serialized{};
  bool has_clean_builder_baseline_signature = false;
  std::string clean_builder_baseline_signature{};
  bool builder_doc_dirty = false;
  int tree_scroll_offset_y = 0;
  int preview_scroll_offset_y = 0;
};

struct HistoryCheckpointBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
  std::string& builder_projection_filter_query;
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
  std::string& preview_visual_feedback_node_id;
  std::string& tree_visual_feedback_node_id;
  bool& inline_edit_active;
  std::string& inline_edit_node_id;
  std::string& inline_edit_buffer;
  std::string& inline_edit_original_text;
  std::string& preview_inline_loaded_text;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  bool& builder_doc_dirty;

  std::function<int()> get_tree_scroll_offset_y;
  std::function<int()> get_preview_scroll_offset_y;

  std::function<void(const std::string&)> set_builder_projection_filter_state;
  std::function<void(int)> set_tree_scroll_offset_y;
  std::function<void(int)> set_preview_scroll_offset_y;
  std::function<void(const std::string&, const std::string&)> restore_exact_selection_focus_anchor_state;
  std::function<void()> refresh_inspector_or_fail;
  std::function<void()> refresh_preview_or_fail;
  std::function<void()> update_add_child_target_display;

  std::function<bool(const ngk::ui::builder::BuilderDocument&, const std::string&)> node_exists_in_document;
};

BuilderMutationCheckpoint capture_mutation_checkpoint(const HistoryCheckpointBinding& binding);
void restore_mutation_checkpoint(HistoryCheckpointBinding& binding, const BuilderMutationCheckpoint& cp);
bool validate_command_history_snapshot(const HistoryCheckpointBinding& binding, const std::vector<CommandHistoryEntry>& history);

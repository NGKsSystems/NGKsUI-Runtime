#pragma once

#include "desktop_file_tool_history_checkpoint.h"

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace desktop_file_tool {

struct HistoryControllerBinding {
    HistoryCheckpointBinding& cp;
    bool& undefined_state_detected;

    bool& history_coalesce_request_active;
    std::string& history_coalesce_request_key;
    std::string& history_coalesce_request_operation_class;
    uint64_t& history_boundary_epoch;

    std::vector<CommandHistoryEntry>& undo_history;
    std::vector<CommandHistoryEntry>& redo_stack;
    BuilderUndoRedoDiagnostics& undoredo_diag;
    
    bool& builder_doc_dirty;
    int& last_inspector_edit_status_code;
    std::string& last_inspector_edit_reason;
    std::string& preview_visual_feedback_message;
    
    std::function<bool()> on_sync_history;
    std::function<bool()> on_finalize_history;
    std::function<bool(bool)> on_recompute_dirty;
    std::function<bool(CommandHistoryEntry&)> on_normalize_history_entry;
    std::function<BuilderMutationCheckpoint()> on_capture_checkpoint;
    std::function<bool(const BuilderMutationCheckpoint&, const char*)> on_enforce_global_invariant;
};

void clear_history_coalesce_request(HistoryControllerBinding& binding);
void request_history_coalescing(HistoryControllerBinding& binding, const std::string& operation_class, const std::string& coalescing_key);
void break_history_coalescing_boundary(HistoryControllerBinding& binding);

void push_to_history(
    HistoryControllerBinding& binding,
    const std::string& command_type,
    const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
    const std::string& before_root,
    const std::string& before_sel,
    const std::vector<std::string>* before_multi,
    const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
    const std::string& after_root,
    const std::string& after_sel,
    const std::vector<std::string>* after_multi,
    const BuilderMutationCheckpoint* before_cp_opt = nullptr,
    const BuilderMutationCheckpoint* after_cp_opt = nullptr,
    const std::string& operation_class = "",
    const std::string& coalescing_key = ""
);

bool apply_undo_command(HistoryControllerBinding& binding, bool defer_surface_refresh = false, bool finalize_surface_refresh = true);
bool apply_redo_command(HistoryControllerBinding& binding, bool defer_surface_refresh = false, bool finalize_surface_refresh = true);
bool apply_history_replay_batch(HistoryControllerBinding& binding, bool undo_direction = true, std::size_t count = 1);

} // namespace desktop_file_tool

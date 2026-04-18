#pragma once

#include <filesystem>
#include <string>

#define DESKTOP_FILE_TOOL_DOCUMENT_WORKFLOW_STATE_FIELDS(X, ctx) \
  X(ctx, bool, builder_doc_dirty, false) \
  X(ctx, bool, has_saved_builder_snapshot, false) \
  X(ctx, std::string, last_saved_builder_serialized, {}) \
  X(ctx, bool, has_clean_builder_baseline_signature, false) \
  X(ctx, std::string, clean_builder_baseline_signature, {}) \
  X(ctx, bool, builder_persistence_io_in_progress, false) \
  X(ctx, bool, builder_persistence_force_next_temp_write_truncation, false) \
  X(ctx, bool, builder_persistence_force_next_atomic_replace_failure, false) \
  X(ctx, std::string, builder_projection_filter_query, {}) \
  X(ctx, const std::filesystem::path, builder_doc_save_path, std::filesystem::current_path() / "_artifacts/runtime/phase103_12_builder_document.ngkbdoc") \
  X(ctx, const std::filesystem::path, builder_export_path, std::filesystem::current_path() / "_artifacts/runtime/phase103_20_builder_export.ngkbdoc") \
  X(ctx, std::string, last_export_status_code, "not_run") \
  X(ctx, std::string, last_export_reason, "none") \
  X(ctx, std::string, last_export_artifact_path, builder_export_path.string()) \
  X(ctx, std::string, last_export_snapshot, {}) \
  X(ctx, bool, has_last_export_snapshot, false) \
  X(ctx, bool, export_snapshot_matches_current_doc, false) \
  X(ctx, const char*, kExportRule, "overwrite_deterministic_single_target")

#define DESKTOP_FILE_TOOL_DOCUMENT_WORKFLOW_STATE_DECLARE_FIELD(ctx, type, name, init) type name = init;
#define DESKTOP_FILE_TOOL_DOCUMENT_WORKFLOW_STATE_BIND_FIELD(ctx, type, name, init) auto& name = (ctx).name;

namespace desktop_file_tool {

struct DesktopFileToolDocumentWorkflowState {
  DESKTOP_FILE_TOOL_DOCUMENT_WORKFLOW_STATE_FIELDS(DESKTOP_FILE_TOOL_DOCUMENT_WORKFLOW_STATE_DECLARE_FIELD, _)
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_DOCUMENT_WORKFLOW_STATE(state_object) \
  DESKTOP_FILE_TOOL_DOCUMENT_WORKFLOW_STATE_FIELDS(DESKTOP_FILE_TOOL_DOCUMENT_WORKFLOW_STATE_BIND_FIELD, state_object)
#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct ExportBuilderDocumentArtifactResult {
  bool ok = false;
  bool export_artifact_created = false;
  bool export_artifact_deterministic = false;
  bool exported_structure_matches_builder_doc = false;
  bool has_export_snapshot = false;
  bool export_snapshot_matches_current_doc = false;
  std::string export_snapshot{};
  std::string status_code = "fail";
  std::string reason = "unknown_export_error";
};

struct PreviewExportParityComparisonResult {
  bool ok = false;
  std::string reason = "unknown_preview_export_parity_error";
};

using BuildPreviewExportParityEntriesFn = std::function<bool(
  const ngk::ui::builder::BuilderDocument&,
  std::vector<PreviewExportParityEntry>&,
  std::string&,
  const char*)>;

struct PreviewExportParityValidationResult {
  bool ok = false;
  std::string status_code = "fail";
  std::string reason = "unknown_preview_export_parity_error";
};

ExportBuilderDocumentArtifactResult export_builder_document_artifact(
  const ngk::ui::builder::BuilderDocument& live_doc,
  const ngk::ui::builder::BuilderDocument& source_doc,
  const std::filesystem::path& export_file_path);

PreviewExportParityComparisonResult compare_preview_export_parity_entries(
  const std::string& live_root_node_id,
  const std::string& exported_root_node_id,
  const std::vector<PreviewExportParityEntry>& live_entries,
  const std::vector<PreviewExportParityEntry>& exported_entries);

PreviewExportParityValidationResult validate_exported_preview_parity(
  const ngk::ui::builder::BuilderDocument& live_doc,
  const std::filesystem::path& export_file_path,
  const BuildPreviewExportParityEntriesFn& build_preview_export_parity_entries);

} // namespace desktop_file_tool
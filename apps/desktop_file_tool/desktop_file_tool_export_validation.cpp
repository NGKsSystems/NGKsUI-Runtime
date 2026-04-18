#include "desktop_file_tool_export_validation.h"

#include "desktop_file_tool_document_io.h"

namespace desktop_file_tool {

ExportBuilderDocumentArtifactResult export_builder_document_artifact(
  const ngk::ui::builder::BuilderDocument& live_doc,
  const ngk::ui::builder::BuilderDocument& source_doc,
  const std::filesystem::path& export_file_path) {
  ExportBuilderDocumentArtifactResult result{};

  const std::string live_snapshot = ngk::ui::builder::serialize_builder_document_deterministic(live_doc);
  const bool source_is_live_document = &source_doc == &live_doc;
  std::string detached_source_snapshot{};
  const std::string* source_snapshot = &live_snapshot;
  if (!source_is_live_document) {
    detached_source_snapshot = ngk::ui::builder::serialize_builder_document_deterministic(source_doc);
    source_snapshot = &detached_source_snapshot;
  }
  if (live_snapshot.empty() || source_snapshot->empty()) {
    result.reason = "snapshot_serialize_failed";
    return result;
  }
  if (live_snapshot != *source_snapshot) {
    result.reason = "source_doc_not_live_state";
    return result;
  }

  if (source_doc.root_node_id.empty() || source_doc.nodes.empty()) {
    result.reason = "invalid_document_missing_root_or_nodes";
    return result;
  }

  std::string validation_error;
  if (!ngk::ui::builder::validate_builder_document(source_doc, &validation_error)) {
    result.reason = "document_validation_failed";
    return result;
  }

  const std::string& export_text = *source_snapshot;
  if (export_text.find("hover_node_id") != std::string::npos ||
      export_text.find("drag_source_node_id") != std::string::npos ||
      export_text.find("focused_builder_node_id") != std::string::npos ||
      export_text.find("preview_binding_node_id") != std::string::npos ||
      export_text.find("inspector_binding_node_id") != std::string::npos ||
      export_text.find("inline_edit_node_id") != std::string::npos) {
    result.reason = "runtime_state_leak_detected";
    return result;
  }

  ngk::ui::builder::InstantiatedBuilderDocument runtime_proof{};
  std::string instantiate_error;
  if (!ngk::ui::builder::instantiate_builder_document(source_doc, runtime_proof, &instantiate_error)) {
    result.reason = "runtime_instantiate_failed";
    return result;
  }

  if (!write_text_file(export_file_path, export_text)) {
    result.reason = "artifact_write_failed";
    return result;
  }

  std::string roundtrip_text;
  if (!read_text_file(export_file_path, roundtrip_text)) {
    result.reason = "artifact_readback_failed";
    return result;
  }
  if (roundtrip_text != export_text) {
    result.reason = "artifact_roundtrip_mismatch";
    return result;
  }

  ngk::ui::builder::BuilderDocument roundtrip_doc{};
  std::string deserialize_error;
  if (!ngk::ui::builder::deserialize_builder_document_deterministic(
        roundtrip_text, roundtrip_doc, &deserialize_error)) {
    result.reason = "artifact_deserialize_failed";
    return result;
  }

  const std::string canonical_roundtrip =
    ngk::ui::builder::serialize_builder_document_deterministic(roundtrip_doc);
  if (canonical_roundtrip != export_text) {
    result.reason = "artifact_canonical_roundtrip_mismatch";
    return result;
  }
  if (canonical_roundtrip != *source_snapshot) {
    result.reason = "artifact_not_equal_live_snapshot";
    return result;
  }

  result.ok = true;
  result.export_artifact_created = true;
  result.export_artifact_deterministic = true;
  result.exported_structure_matches_builder_doc = true;
  result.has_export_snapshot = true;
  result.export_snapshot = export_text;
  result.export_snapshot_matches_current_doc = true;
  result.status_code = "success";
  result.reason = "none";
  return result;
}

PreviewExportParityComparisonResult compare_preview_export_parity_entries(
  const std::string& live_root_node_id,
  const std::string& exported_root_node_id,
  const std::vector<PreviewExportParityEntry>& live_entries,
  const std::vector<PreviewExportParityEntry>& exported_entries) {
  PreviewExportParityComparisonResult result{};

  if (live_root_node_id != exported_root_node_id) {
    result.reason = "root_node_mismatch_live_" + live_root_node_id + "_export_" + exported_root_node_id;
    return result;
  }

  if (live_entries.size() != exported_entries.size()) {
    result.reason = "node_count_mismatch_live_" + std::to_string(live_entries.size()) +
      "_export_" + std::to_string(exported_entries.size());
    return result;
  }

  for (std::size_t index = 0; index < live_entries.size(); ++index) {
    const auto& live_entry = live_entries[index];
    const auto& exported_entry = exported_entries[index];

    if (live_entry.depth != exported_entry.depth) {
      result.reason = "hierarchy_depth_mismatch_node_" + live_entry.node_id;
      return result;
    }
    if (live_entry.node_id != exported_entry.node_id) {
      result.reason = "node_identity_mismatch_live_" + live_entry.node_id + "_export_" + exported_entry.node_id;
      return result;
    }
    if (live_entry.widget_type != exported_entry.widget_type) {
      result.reason = "component_type_mismatch_node_" + live_entry.node_id;
      return result;
    }
    if (live_entry.text != exported_entry.text) {
      result.reason = "identity_text_mismatch_node_" + live_entry.node_id;
      return result;
    }
    if (live_entry.child_ids.size() != exported_entry.child_ids.size()) {
      result.reason = "child_count_mismatch_node_" + live_entry.node_id;
      return result;
    }
    for (std::size_t child_index = 0; child_index < live_entry.child_ids.size(); ++child_index) {
      if (live_entry.child_ids[child_index] != exported_entry.child_ids[child_index]) {
        result.reason = "child_link_mismatch_parent_" + live_entry.node_id +
          "_offset_" + std::to_string(child_index);
        return result;
      }
    }
  }

  result.ok = true;
  result.reason = "none";
  return result;
}

PreviewExportParityValidationResult validate_exported_preview_parity(
  const ngk::ui::builder::BuilderDocument& live_doc,
  const std::filesystem::path& export_file_path,
  const BuildPreviewExportParityEntriesFn& build_preview_export_parity_entries) {
  PreviewExportParityValidationResult result{};

  std::string exported_text;
  if (!read_text_file(export_file_path, exported_text)) {
    result.reason = "export_artifact_read_failed";
    return result;
  }

  ngk::ui::builder::BuilderDocument exported_doc{};
  std::string deserialize_error;
  if (!ngk::ui::builder::deserialize_builder_document_deterministic(
        exported_text, exported_doc, &deserialize_error)) {
    result.reason = "export_artifact_deserialize_failed";
    return result;
  }

  std::vector<PreviewExportParityEntry> live_entries{};
  std::vector<PreviewExportParityEntry> exported_entries{};
  std::string live_reason;
  std::string exported_reason;
  if (!build_preview_export_parity_entries(live_doc, live_entries, live_reason, "live_preview_scope")) {
    result.reason = live_reason;
    return result;
  }
  if (!build_preview_export_parity_entries(exported_doc, exported_entries, exported_reason, "export_scope")) {
    result.reason = exported_reason;
    return result;
  }

  const auto comparison = compare_preview_export_parity_entries(
    live_doc.root_node_id,
    exported_doc.root_node_id,
    live_entries,
    exported_entries);
  if (!comparison.ok) {
    result.reason = comparison.reason;
    return result;
  }

  result.ok = true;
  result.status_code = "success";
  result.reason = "none";
  return result;
}

} // namespace desktop_file_tool
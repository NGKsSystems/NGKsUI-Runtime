#pragma once

#include <algorithm>
#include <cstddef>
#include <filesystem>
#include <functional>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct PersistenceFileIoPhase10372Binding {
  BuilderPersistenceFileIoIntegrityHardeningDiagnostics& persistence_file_io_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
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
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  bool& builder_doc_dirty;
  bool& builder_persistence_io_in_progress;
  bool& builder_persistence_force_next_temp_write_truncation;
  bool& builder_persistence_force_next_atomic_replace_failure;
  const std::filesystem::path& builder_doc_save_path;
  std::function<std::string(const ngk::ui::builder::BuilderDocument&)> current_document_signature;
  std::function<bool()> refresh_all_surfaces;
  std::function<void(const std::filesystem::path&)> cleanup_io_artifacts;
  std::function<std::filesystem::path(const std::filesystem::path&)> build_atomic_save_temp_path;
  std::function<std::filesystem::path(const std::filesystem::path&)> build_atomic_save_backup_path;
  std::function<bool(const std::string&, const std::string&)> set_node_text;
  std::function<bool(const std::filesystem::path&)> save_builder_document_to_path;
  std::function<bool(const std::filesystem::path&, std::string&)> read_text_file_exact;
  std::function<bool(const std::filesystem::path&, const std::string&)> write_text_file;
  std::function<bool(const std::filesystem::path&)> load_builder_document_from_path;
  std::function<bool()> apply_save_document_command;
  std::function<bool(bool)> apply_load_document_command;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(std::string&)> validate_global_document_invariant;
};

inline std::string phase103_72_join_ids(const std::vector<std::string>& ids) {
  std::ostringstream oss;
  for (std::size_t index = 0; index < ids.size(); ++index) {
    if (index > 0) {
      oss << ",";
    }
    oss << ids[index];
  }
  return oss.str();
}

inline std::string build_phase103_72_live_state_signature(
  PersistenceFileIoPhase10372Binding& binding,
  const char* context_name) {
  std::ostringstream oss;
  (void)context_name;
  oss << binding.current_document_signature(binding.builder_doc) << "\n";
  oss << "selected=" << binding.selected_builder_node_id << "\n";
  oss << "focused=" << binding.focused_builder_node_id << "\n";
  oss << "multi=" << phase103_72_join_ids(binding.multi_selected_node_ids) << "\n";
  oss << "inspector=" << binding.inspector_binding_node_id << "\n";
  oss << "preview=" << binding.preview_binding_node_id << "\n";
  oss << "dirty=" << (binding.builder_doc_dirty ? 1 : 0) << "\n";
  oss << "baseline=" << binding.clean_builder_baseline_signature << "\n";
  oss << "undo=" << binding.undo_history.size() << "\n";
  oss << "redo=" << binding.redo_stack.size() << "\n";
  oss << "io_busy=" << (binding.builder_persistence_io_in_progress ? 1 : 0) << "\n";
  return oss.str();
}

inline ngk::ui::builder::BuilderDocument make_phase103_72_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_72_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.child_ids = {"phase103_72_label_a", "phase103_72_group", "phase103_72_label_b"};

  ngk::ui::builder::BuilderNode label_a{};
  label_a.node_id = "phase103_72_label_a";
  label_a.parent_id = "phase103_72_root";
  label_a.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  label_a.text = "alpha";

  ngk::ui::builder::BuilderNode group{};
  group.node_id = "phase103_72_group";
  group.parent_id = "phase103_72_root";
  group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  group.child_ids = {"phase103_72_nested"};

  ngk::ui::builder::BuilderNode nested{};
  nested.node_id = "phase103_72_nested";
  nested.parent_id = "phase103_72_group";
  nested.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  nested.text = "nested";

  ngk::ui::builder::BuilderNode label_b{};
  label_b.node_id = "phase103_72_label_b";
  label_b.parent_id = "phase103_72_root";
  label_b.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  label_b.text = "beta";

  doc.root_node_id = root.node_id;
  doc.nodes = {root, label_a, group, nested, label_b};
  return doc;
}

inline bool load_phase103_72_document(
  PersistenceFileIoPhase10372Binding& binding,
  const ngk::ui::builder::BuilderDocument& doc) {
  binding.builder_doc = doc;
  binding.undo_history.clear();
  binding.redo_stack.clear();
  binding.selected_builder_node_id = binding.builder_doc.root_node_id;
  binding.focused_builder_node_id = binding.builder_doc.root_node_id;
  binding.builder_selection_anchor_node_id.clear();
  binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
  binding.inspector_binding_node_id.clear();
  binding.preview_binding_node_id.clear();
  binding.hover_node_id.clear();
  binding.drag_source_node_id.clear();
  binding.drag_active = false;
  binding.drag_target_preview_node_id.clear();
  binding.drag_target_preview_is_illegal = false;
  binding.drag_target_preview_parent_id.clear();
  binding.drag_target_preview_insert_index = 0;
  binding.drag_target_preview_resolution_kind.clear();
  binding.preview_visual_feedback_message.clear();
  binding.preview_visual_feedback_node_id.clear();
  binding.tree_visual_feedback_node_id.clear();
  binding.inline_edit_active = false;
  binding.inline_edit_node_id.clear();
  binding.inline_edit_buffer.clear();
  binding.inline_edit_original_text.clear();
  binding.preview_inline_loaded_text.clear();
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = binding.current_document_signature(binding.builder_doc);
  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = binding.last_saved_builder_serialized;
  binding.builder_doc_dirty = false;
  binding.builder_persistence_io_in_progress = false;
  binding.builder_persistence_force_next_temp_write_truncation = false;
  binding.builder_persistence_force_next_atomic_replace_failure = false;
  return binding.refresh_all_surfaces();
}

inline bool reset_phase103_72(PersistenceFileIoPhase10372Binding& binding) {
  return load_phase103_72_document(binding, make_phase103_72_document());
}

inline bool run_phase103_72_persistence_file_io_phase(PersistenceFileIoPhase10372Binding& binding) {
  binding.persistence_file_io_integrity_diag = {};
  bool flow_ok = true;

  const std::filesystem::path phase103_72_primary_path =
    std::filesystem::current_path() / "_artifacts/runtime/phase103_72_builder_document.ngkbdoc";
  const std::filesystem::path phase103_72_secondary_path =
    std::filesystem::current_path() / "_artifacts/runtime/phase103_72_builder_document_second.ngkbdoc";
  const std::filesystem::path phase103_72_invalid_path =
    std::filesystem::current_path() / "_artifacts/runtime/phase103_72_invalid.ngkbdoc";
  const std::filesystem::path phase103_72_truncated_path =
    std::filesystem::current_path() / "_artifacts/runtime/phase103_72_truncated.ngkbdoc";
  const std::filesystem::path phase103_72_atomic_fail_path =
    std::filesystem::current_path() / "_artifacts/runtime/phase103_72_atomic_fail.ngkbdoc";

  binding.cleanup_io_artifacts(phase103_72_primary_path);
  binding.cleanup_io_artifacts(phase103_72_secondary_path);
  binding.cleanup_io_artifacts(phase103_72_invalid_path);
  binding.cleanup_io_artifacts(phase103_72_truncated_path);
  binding.cleanup_io_artifacts(phase103_72_atomic_fail_path);
  binding.cleanup_io_artifacts(binding.builder_doc_save_path);

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    binding.builder_persistence_force_next_temp_write_truncation = true;
    const bool missing_target_failed = !binding.save_builder_document_to_path(phase103_72_atomic_fail_path);
    std::error_code ec_missing;
    const bool no_missing_target_file = !std::filesystem::exists(phase103_72_atomic_fail_path, ec_missing);
    const bool no_missing_target_temp =
      !std::filesystem::exists(binding.build_atomic_save_temp_path(phase103_72_atomic_fail_path), ec_missing) &&
      !std::filesystem::exists(binding.build_atomic_save_backup_path(phase103_72_atomic_fail_path), ec_missing);

    flow_ok = binding.set_node_text("phase103_72_label_a", "atomic_base") && flow_ok;
    const bool base_save_ok = binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string original_bytes{};
    const bool original_read_ok = binding.read_text_file_exact(phase103_72_primary_path, original_bytes);

    flow_ok = binding.set_node_text("phase103_72_label_a", "atomic_partial_fail") && flow_ok;
    binding.builder_persistence_force_next_temp_write_truncation = true;
    const bool existing_target_failed = !binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string after_failed_save_bytes{};
    const bool after_failed_read_ok = binding.read_text_file_exact(phase103_72_primary_path, after_failed_save_bytes);
    std::error_code ec_existing;
    const bool no_existing_target_temp =
      !std::filesystem::exists(binding.build_atomic_save_temp_path(phase103_72_primary_path), ec_existing) &&
      !std::filesystem::exists(binding.build_atomic_save_backup_path(phase103_72_primary_path), ec_existing);

    binding.persistence_file_io_integrity_diag.save_is_atomic_and_never_exposes_partial_file =
      missing_target_failed && no_missing_target_file && no_missing_target_temp &&
      base_save_ok && original_read_ok && existing_target_failed && after_failed_read_ok &&
      original_bytes == after_failed_save_bytes && no_existing_target_temp;
    flow_ok = binding.persistence_file_io_integrity_diag.save_is_atomic_and_never_exposes_partial_file && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    flow_ok = binding.set_node_text("phase103_72_label_a", "canonical_payload") && flow_ok;
    const std::string expected_signature = binding.current_document_signature(binding.builder_doc);
    const bool save_ok = binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string file_bytes{};
    const bool read_ok = binding.read_text_file_exact(phase103_72_primary_path, file_bytes);
    binding.persistence_file_io_integrity_diag.saved_file_matches_canonical_document_signature =
      save_ok && read_ok && file_bytes == expected_signature;
    flow_ok = binding.persistence_file_io_integrity_diag.saved_file_matches_canonical_document_signature && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    flow_ok = binding.set_node_text("phase103_72_label_a", "truncate_source") && flow_ok;
    const std::string canonical_payload = binding.current_document_signature(binding.builder_doc);
    const bool write_invalid = binding.write_text_file(phase103_72_invalid_path, "not-a-builder-document");
    const std::string truncated_payload = canonical_payload.substr(0, std::max<std::size_t>(1, canonical_payload.size() / 2));
    const bool write_truncated = binding.write_text_file(phase103_72_truncated_path, truncated_payload);
    const bool invalid_rejected = write_invalid && !binding.load_builder_document_from_path(phase103_72_invalid_path);
    const bool truncated_rejected = write_truncated && !binding.load_builder_document_from_path(phase103_72_truncated_path);
    binding.persistence_file_io_integrity_diag.load_rejects_invalid_or_truncated_files = invalid_rejected && truncated_rejected;
    flow_ok = binding.persistence_file_io_integrity_diag.load_rejects_invalid_or_truncated_files && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    flow_ok = binding.set_node_text("phase103_72_label_a", "replace_base") && flow_ok;
    const bool save_ok = binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string original_bytes{};
    const bool read_original_ok = binding.read_text_file_exact(phase103_72_primary_path, original_bytes);
    flow_ok = binding.set_node_text("phase103_72_label_a", "replace_failure_candidate") && flow_ok;
    binding.builder_persistence_force_next_atomic_replace_failure = true;
    const bool failed_save = !binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string after_failed_bytes{};
    const bool read_after_failed_ok = binding.read_text_file_exact(phase103_72_primary_path, after_failed_bytes);
    binding.persistence_file_io_integrity_diag.failed_save_does_not_overwrite_existing_file =
      save_ok && read_original_ok && failed_save && read_after_failed_ok && original_bytes == after_failed_bytes;
    flow_ok = binding.persistence_file_io_integrity_diag.failed_save_does_not_overwrite_existing_file && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    const std::string before_failed_load = build_phase103_72_live_state_signature(binding, "phase103_72_failed_load_state");
    const std::string baseline_before_failed_load = binding.clean_builder_baseline_signature;
    const bool dirty_before_failed_load = binding.builder_doc_dirty;
    const bool invalid_write_ok = binding.write_text_file(phase103_72_invalid_path, "broken-payload");
    const bool failed_load = invalid_write_ok && !binding.load_builder_document_from_path(phase103_72_invalid_path);
    const std::string after_failed_load = build_phase103_72_live_state_signature(binding, "phase103_72_failed_load_state");
    binding.persistence_file_io_integrity_diag.failed_load_does_not_mutate_current_state =
      failed_load &&
      before_failed_load == after_failed_load &&
      binding.clean_builder_baseline_signature == baseline_before_failed_load &&
      binding.builder_doc_dirty == dirty_before_failed_load;
    flow_ok = binding.persistence_file_io_integrity_diag.failed_load_does_not_mutate_current_state && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    flow_ok = binding.set_node_text("phase103_72_label_a", "ui_sync_seed") && flow_ok;
    const std::string before_save_live = build_phase103_72_live_state_signature(binding, "phase103_72_save_sync_state");
    const bool save_ok = binding.save_builder_document_to_path(phase103_72_primary_path);
    const std::string after_save_live = build_phase103_72_live_state_signature(binding, "phase103_72_save_sync_state");
    flow_ok = binding.set_node_text("phase103_72_label_a", "ui_sync_mutated_after_save") && flow_ok;
    const bool load_ok = binding.load_builder_document_from_path(phase103_72_primary_path);
    std::string post_load_invariant_reason;
    binding.persistence_file_io_integrity_diag.no_transient_ui_or_state_desync_during_io =
      save_ok &&
      before_save_live == after_save_live &&
      binding.persistence_file_io_integrity_diag.failed_load_does_not_mutate_current_state &&
      load_ok &&
      !binding.builder_persistence_io_in_progress &&
      binding.check_cross_surface_sync() &&
      binding.validate_global_document_invariant(post_load_invariant_reason);
    flow_ok = binding.persistence_file_io_integrity_diag.no_transient_ui_or_state_desync_during_io && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    flow_ok = binding.set_node_text("phase103_72_label_a", "deterministic_bytes") && flow_ok;
    const std::string sig1 = binding.current_document_signature(binding.builder_doc);
    const std::string sig2 = binding.current_document_signature(binding.builder_doc);
    const bool save1 = binding.save_builder_document_to_path(phase103_72_primary_path);
    const bool save2 = binding.save_builder_document_to_path(phase103_72_secondary_path);
    std::string bytes1{};
    std::string bytes2{};
    const bool read1 = binding.read_text_file_exact(phase103_72_primary_path, bytes1);
    const bool read2 = binding.read_text_file_exact(phase103_72_secondary_path, bytes2);
    binding.persistence_file_io_integrity_diag.serialization_deterministic_for_identical_document =
      sig1 == sig2 && save1 && save2 && read1 && read2 && bytes1 == bytes2 && bytes1 == sig1;
    flow_ok = binding.persistence_file_io_integrity_diag.serialization_deterministic_for_identical_document && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    flow_ok = binding.set_node_text("phase103_72_label_a", "repeat_stable") && flow_ok;
    const bool save1 = binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string bytes1{};
    const bool read1 = binding.read_text_file_exact(phase103_72_primary_path, bytes1);
    const bool save2 = binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string bytes2{};
    const bool read2 = binding.read_text_file_exact(phase103_72_primary_path, bytes2);
    const bool save3 = binding.save_builder_document_to_path(phase103_72_primary_path);
    std::string bytes3{};
    const bool read3 = binding.read_text_file_exact(phase103_72_primary_path, bytes3);
    binding.builder_persistence_io_in_progress = true;
    const bool blocked_while_busy = !binding.save_builder_document_to_path(phase103_72_primary_path);
    binding.builder_persistence_io_in_progress = false;
    std::string bytes_after_busy{};
    const bool read_after_busy = binding.read_text_file_exact(phase103_72_primary_path, bytes_after_busy);
    binding.persistence_file_io_integrity_diag.repeated_save_calls_produce_consistent_output =
      save1 && save2 && save3 && read1 && read2 && read3 && read_after_busy &&
      bytes1 == bytes2 && bytes2 == bytes3 && bytes3 == bytes_after_busy && blocked_while_busy;
    flow_ok = binding.persistence_file_io_integrity_diag.repeated_save_calls_produce_consistent_output && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    binding.cleanup_io_artifacts(binding.builder_doc_save_path);
    flow_ok = binding.set_node_text("phase103_72_label_a", "baseline_seed") && flow_ok;
    const bool initial_save = binding.apply_save_document_command();

    flow_ok = binding.set_node_text("phase103_72_label_a", "dirty_before_failed_save") && flow_ok;
    const std::string baseline_before_failed_save = binding.clean_builder_baseline_signature;
    const bool dirty_before_failed_save = binding.builder_doc_dirty;
    binding.builder_persistence_force_next_atomic_replace_failure = true;
    const bool failed_save = !binding.apply_save_document_command();
    const bool failed_save_preserves_tracking =
      failed_save &&
      binding.builder_doc_dirty == dirty_before_failed_save &&
      binding.clean_builder_baseline_signature == baseline_before_failed_save;

    const bool successful_save = binding.apply_save_document_command();
    const std::string signature_after_successful_save = binding.current_document_signature(binding.builder_doc);
    const bool successful_save_updates_tracking =
      successful_save &&
      !binding.builder_doc_dirty &&
      binding.clean_builder_baseline_signature == signature_after_successful_save &&
      binding.last_saved_builder_serialized == signature_after_successful_save;

    flow_ok = binding.set_node_text("phase103_72_label_a", "dirty_before_failed_load") && flow_ok;
    const std::string baseline_before_failed_load = binding.clean_builder_baseline_signature;
    const bool dirty_before_failed_load = binding.builder_doc_dirty;
    const bool invalid_payload_written = binding.write_text_file(phase103_72_invalid_path, "invalid-load");
    const bool failed_load = invalid_payload_written && !binding.load_builder_document_from_path(phase103_72_invalid_path);
    const bool failed_load_preserves_tracking =
      failed_load &&
      binding.builder_doc_dirty == dirty_before_failed_load &&
      binding.clean_builder_baseline_signature == baseline_before_failed_load;

    const bool successful_load = binding.apply_load_document_command(true);
    const std::string signature_after_successful_load = binding.current_document_signature(binding.builder_doc);
    const bool successful_load_updates_tracking =
      successful_load &&
      !binding.builder_doc_dirty &&
      binding.clean_builder_baseline_signature == signature_after_successful_load &&
      binding.last_saved_builder_serialized == signature_after_successful_load;

    binding.persistence_file_io_integrity_diag.dirty_baseline_updates_only_on_successful_save_load =
      initial_save &&
      failed_save_preserves_tracking &&
      successful_save_updates_tracking &&
      failed_load_preserves_tracking &&
      successful_load_updates_tracking;
    flow_ok = binding.persistence_file_io_integrity_diag.dirty_baseline_updates_only_on_successful_save_load && flow_ok;
  }

  {
    flow_ok = reset_phase103_72(binding) && flow_ok;
    bool invariant_ok = true;
    std::string invariant_reason;

    invariant_ok = binding.set_node_text("phase103_72_label_a", "invariant_seed") && invariant_ok;
    invariant_ok = binding.save_builder_document_to_path(phase103_72_primary_path) && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;

    invariant_ok = binding.set_node_text("phase103_72_label_a", "invariant_failed_save") && invariant_ok;
    binding.builder_persistence_force_next_atomic_replace_failure = true;
    invariant_ok = !binding.save_builder_document_to_path(phase103_72_primary_path) && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;

    invariant_ok = binding.write_text_file(phase103_72_invalid_path, "bad-invariant-load") && invariant_ok;
    invariant_ok = !binding.load_builder_document_from_path(phase103_72_invalid_path) && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;

    invariant_ok = binding.load_builder_document_from_path(phase103_72_primary_path) && invariant_ok;
    invariant_ok = binding.validate_global_document_invariant(invariant_reason) && invariant_ok;

    binding.persistence_file_io_integrity_diag.global_invariant_preserved_through_all_io_operations = invariant_ok;
    flow_ok = binding.persistence_file_io_integrity_diag.global_invariant_preserved_through_all_io_operations && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
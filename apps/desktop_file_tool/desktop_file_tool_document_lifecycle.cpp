#include "desktop_file_tool_document_lifecycle.h"

#include "desktop_file_tool_document_io.h"

namespace desktop_file_tool {

struct ScopedBusyFlag {
  bool& flag;

  explicit ScopedBusyFlag(bool& value) : flag(value) {
    flag = true;
  }

  ~ScopedBusyFlag() {
    flag = false;
  }
};

bool load_builder_document_from_path(DocumentLifecycleBinding& binding, const std::filesystem::path& path) {
  if (binding.builder_persistence_io_in_progress) {
    return false;
  }

  const BuilderMutationCheckpoint checkpoint = binding.on_capture_checkpoint();
  std::string serialized{};
  ngk::ui::builder::BuilderDocument loaded_doc{};
  {
    ScopedBusyFlag io_guard(binding.builder_persistence_io_in_progress);
    if (!read_text_file_exact(path, serialized)) {
      return false;
    }

    std::string instantiate_error;
    if (!validate_serialized_builder_document_payload(serialized, &loaded_doc, nullptr, &instantiate_error)) {
      return false;
    }
  }

  binding.builder_doc = std::move(loaded_doc);
  binding.on_reset_runtime_state_after_document_replacement(binding.builder_doc.root_node_id, true);

  const bool remap_ok = binding.on_remap_selection();
  const bool focus_ok = binding.on_sync_focus();
  const bool inspector_ok = binding.on_refresh_inspector();
  const bool preview_ok = binding.on_refresh_preview();
  const bool sync_ok = binding.on_check_cross_surface_sync();

  if (!(remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok)) {
    binding.on_restore_checkpoint(checkpoint);
    return false;
  }

  return binding.on_enforce_global_invariant(checkpoint, "load_builder_document_from_path");
}

bool save_builder_document_to_path(DocumentLifecycleBinding& binding, const std::filesystem::path& path) {
  return atomic_save_builder_document(path, binding.builder_doc, binding.builder_persistence_io_in_progress);
}

bool apply_save_document_command(DocumentLifecycleBinding& binding, const std::filesystem::path& path) {
  const bool saved = atomic_save_builder_document(path, binding.builder_doc, binding.builder_persistence_io_in_progress);
  if (!saved) {
    return false;
  }

  const std::string saved_snapshot = ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
  if (saved_snapshot.empty()) {
    return false;
  }

  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = saved_snapshot;
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = saved_snapshot;
  binding.builder_doc_dirty = false;
  binding.on_update_labels();
  return true;
}

bool apply_load_document_command(DocumentLifecycleBinding& binding, const std::filesystem::path& path, bool allow_discard_dirty) {
  if (binding.builder_doc_dirty && !allow_discard_dirty) {
    return false;
  }

  const bool loaded = load_builder_document_from_path(binding, path);
  if (!loaded) {
    return false;
  }

  const std::string loaded_snapshot = ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
  if (loaded_snapshot.empty()) {
    return false;
  }

  (void)loaded_snapshot;
  return binding.on_commit_clean_document_baseline();
}

bool apply_new_document_command(DocumentLifecycleBinding& binding, bool allow_discard_dirty) {
  if (binding.builder_doc_dirty && !allow_discard_dirty) {
    return false;
  }

  ngk::ui::builder::BuilderDocument new_doc{};
  std::string new_selected{};
  if (!binding.on_create_default_document(new_doc, new_selected)) {
    return false;
  }

  binding.builder_doc = std::move(new_doc);
  binding.selected_builder_node_id = new_selected;
  binding.undo_history.clear();
  binding.redo_stack.clear();

  const std::string new_snapshot = ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
  if (new_snapshot.empty()) {
    return false;
  }

  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = new_snapshot;
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = new_snapshot;
  binding.builder_doc_dirty = false;
  binding.on_reset_scroll_offsets();

  const bool remap_ok = binding.on_remap_selection();
  const bool focus_ok = binding.on_sync_focus();
  const bool inspector_ok = binding.on_refresh_inspector();
  const bool preview_ok = binding.on_refresh_preview();
  const bool sync_ok = binding.on_check_cross_surface_sync();
  binding.on_update_labels();

  return remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;
}

} // namespace desktop_file_tool
#pragma once

#include <any>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"
#include "desktop_file_tool_document_io.h"

namespace desktop_file_tool {

struct ExternalImportPreparationResult {
  bool success = false;
  std::string failure_reason{};
  ngk::ui::builder::BuilderDocument candidate_doc{};
  std::string imported_root_id{};
};

struct ExternalImportTransactionContext {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::function<void(const std::string&, bool)> reset_runtime_state_after_document_replacement;
  std::function<std::any()> capture_mutation_checkpoint;
  std::function<void(const std::any&)> restore_mutation_checkpoint;
  std::function<void()> scrub_stale_lifecycle_references;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<void(const std::string&,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>&,
                     const std::any&)> push_to_history;
  std::function<void(bool)> recompute_builder_dirty_state;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool(const std::any&, const std::string&)> enforce_global_invariant_or_rollback;
};

struct ExternalImportTransactionResult {
  bool success = false;
  std::string failure_reason{};
};

struct ExternalImportPhase10375Binding {
  BuilderClipboardExternalDataBoundaryIntegrityHardeningDiagnostics& external_data_boundary_integrity_diag;
  const BuilderClipboardDuplicateCopyPasteIntegrityHardeningDiagnostics& clipboard_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& focused_builder_node_id;
  std::string& builder_selection_anchor_node_id;
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
  std::string& builder_projection_filter_query;
  std::string& model_filter;
  bool& has_saved_builder_snapshot;
  std::string& last_saved_builder_serialized;
  bool& has_clean_builder_baseline_signature;
  std::string& clean_builder_baseline_signature;
  bool& builder_doc_dirty;
  std::function<void(int)> set_tree_scroll_offset_y;
  std::function<void(int)> set_preview_scroll_offset_y;
  std::function<bool()> refresh_phase103_75_surfaces;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&, const std::string&, const std::string&, std::vector<std::string>*, std::string*)>
    import_external_builder_subtree_payload;
  std::function<bool(std::string&)> validate_global_document_invariant;
  std::function<void()> run_phase103_65;
};

inline ngk::ui::builder::BuilderDocument make_phase103_75_base_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_75_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
  root.layout.min_width = 1;
  root.child_ids = {"phase103_75_target", "phase103_75_existing_label"};

  ngk::ui::builder::BuilderNode target{};
  target.node_id = "phase103_75_target";
  target.parent_id = root.node_id;
  target.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  target.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  target.layout.min_width = 1;

  ngk::ui::builder::BuilderNode label{};
  label.node_id = "phase103_75_existing_label";
  label.parent_id = root.node_id;
  label.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  label.text = "phase103_75_existing";

  doc.root_node_id = root.node_id;
  doc.nodes = {root, target, label};
  return doc;
}

inline ngk::ui::builder::BuilderDocument make_phase103_75_external_document() {
  ngk::ui::builder::BuilderDocument doc{};
  doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

  ngk::ui::builder::BuilderNode root{};
  root.node_id = "phase103_75_ext_root";
  root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  root.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  root.layout.min_width = 1;
  root.child_ids = {"phase103_75_ext_label", "phase103_75_ext_group"};

  ngk::ui::builder::BuilderNode label{};
  label.node_id = "phase103_75_ext_label";
  label.parent_id = root.node_id;
  label.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  label.text = "phase103_75_ext_label";

  ngk::ui::builder::BuilderNode group{};
  group.node_id = "phase103_75_ext_group";
  group.parent_id = root.node_id;
  group.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  group.container_type = ngk::ui::builder::BuilderContainerType::Generic;
  group.layout.min_width = 1;
  group.child_ids = {"phase103_75_ext_nested"};

  ngk::ui::builder::BuilderNode nested{};
  nested.node_id = "phase103_75_ext_nested";
  nested.parent_id = group.node_id;
  nested.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
  nested.text = "phase103_75_ext_nested";

  doc.root_node_id = root.node_id;
  doc.nodes = {root, label, group, nested};
  return doc;
}

inline bool load_phase103_75_document(
  ExternalImportPhase10375Binding& binding,
  const ngk::ui::builder::BuilderDocument& doc,
  const std::string& selected_id) {
  binding.builder_doc = doc;
  binding.undo_history.clear();
  binding.redo_stack.clear();
  binding.selected_builder_node_id = selected_id;
  binding.multi_selected_node_ids = selected_id.empty()
    ? std::vector<std::string>{}
    : std::vector<std::string>{selected_id};
  binding.focused_builder_node_id = selected_id;
  binding.builder_selection_anchor_node_id = selected_id;
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
  binding.builder_projection_filter_query.clear();
  binding.model_filter.clear();
  binding.set_tree_scroll_offset_y(0);
  binding.set_preview_scroll_offset_y(0);

  const std::string signature =
    ngk::ui::builder::serialize_builder_document_deterministic(binding.builder_doc);
  binding.has_saved_builder_snapshot = true;
  binding.last_saved_builder_serialized = signature;
  binding.has_clean_builder_baseline_signature = true;
  binding.clean_builder_baseline_signature = signature;
  binding.builder_doc_dirty = false;
  return binding.refresh_phase103_75_surfaces();
}

inline std::string build_phase103_75_signature(const ngk::ui::builder::BuilderDocument& doc) {
  return ngk::ui::builder::serialize_builder_document_deterministic(doc);
}

inline std::vector<std::string> collect_phase103_75_subtree_ids(
  const std::function<ngk::ui::builder::BuilderNode*(const std::string&)>& find_node_by_id,
  const std::string& root_id) {
  std::vector<std::string> ordered{};
  std::function<void(const std::string&)> walk = [&](const std::string& node_id) {
    auto* node = find_node_by_id(node_id);
    if (!node) {
      return;
    }
    ordered.push_back(node_id);
    for (const auto& child_id : node->child_ids) {
      walk(child_id);
    }
  };
  walk(root_id);
  return ordered;
}

inline std::string canonical_phase103_75_subtree_signature(
  const std::function<ngk::ui::builder::BuilderNode*(const std::string&)>& find_node_by_id,
  const std::string& root_id) {
  std::function<std::string(const std::string&)> sig = [&](const std::string& node_id) -> std::string {
    const auto* node = find_node_by_id(node_id);
    if (!node) {
      return std::string("missing:") + node_id;
    }
    std::ostringstream oss;
    oss << ngk::ui::builder::to_string(node->widget_type)
        << "#" << node->text
        << "#" << node->layout.min_width
        << "{";
    for (std::size_t idx = 0; idx < node->child_ids.size(); ++idx) {
      if (idx > 0) {
        oss << ",";
      }
      oss << sig(node->child_ids[idx]);
    }
    oss << "}";
    return oss.str();
  };
  return root_id.empty() ? std::string{} : sig(root_id);
}

inline std::string replace_once(
  const std::string& haystack,
  const std::string& needle,
  const std::string& replacement) {
  const std::size_t pos = haystack.find(needle);
  if (pos == std::string::npos) {
    return std::string{};
  }
  std::string replaced = haystack;
  replaced.replace(pos, needle.size(), replacement);
  return replaced;
}

inline bool run_phase103_75_external_import_phase(ExternalImportPhase10375Binding& binding) {
  binding.external_data_boundary_integrity_diag = {};
  bool flow_ok = true;

  const ngk::ui::builder::BuilderDocument external_doc = make_phase103_75_external_document();
  const std::string valid_payload = ngk::ui::builder::serialize_builder_document_deterministic(external_doc);
  const std::string malformed_payload = valid_payload.empty() || valid_payload.size() < 12
    ? std::string("not_a_builder_payload")
    : valid_payload.substr(0, valid_payload.size() - 7);
  const std::string broken_parent_payload = replace_once(
    valid_payload,
    "node.1.parent_id=phase103_75_ext_root",
    "node.1.parent_id=phase103_75_missing_parent");
  const std::string invalid_layout_payload = replace_once(
    valid_payload,
    "node.0.layout.min_width=1",
    "node.0.layout.min_width=-1");
  const std::string oversized_payload(262145, 'Z');

  {
    const bool loaded = load_phase103_75_document(binding, make_phase103_75_base_document(), "phase103_75_target");
    const std::string before_signature = build_phase103_75_signature(binding.builder_doc);
    const std::size_t before_history = binding.undo_history.size();
    const bool before_dirty = binding.builder_doc_dirty;
    std::string malformed_reason;
    const bool malformed_rejected = loaded &&
      !binding.import_external_builder_subtree_payload(
        malformed_payload,
        "phase103_75_target",
        "phase103_75_malformed",
        nullptr,
        &malformed_reason);
    std::string partial_reason;
    const bool partial_rejected = loaded &&
      !binding.import_external_builder_subtree_payload(
        broken_parent_payload,
        "phase103_75_target",
        "phase103_75_partial",
        nullptr,
        &partial_reason);
    binding.external_data_boundary_integrity_diag.external_paste_rejects_malformed_or_partial_data =
      loaded && malformed_rejected && partial_rejected &&
      !malformed_reason.empty() && !partial_reason.empty() &&
      build_phase103_75_signature(binding.builder_doc) == before_signature &&
      binding.undo_history.size() == before_history &&
      binding.builder_doc_dirty == before_dirty;
    flow_ok = binding.external_data_boundary_integrity_diag.external_paste_rejects_malformed_or_partial_data && flow_ok;
  }

  {
    const bool loaded = load_phase103_75_document(binding, make_phase103_75_base_document(), "phase103_75_target");
    const auto* target_before = binding.find_node_by_id("phase103_75_target");
    const std::size_t child_count_before = target_before ? target_before->child_ids.size() : 0;
    const std::size_t node_count_before = binding.builder_doc.nodes.size();
    std::vector<std::string> imported_roots{};
    const bool import_ok = loaded &&
      binding.import_external_builder_subtree_payload(
        valid_payload,
        "phase103_75_target",
        "phase103_75_external_import",
        &imported_roots,
        nullptr);
    const auto* target_after = binding.find_node_by_id("phase103_75_target");
    const auto imported_ids = import_ok && !imported_roots.empty()
      ? collect_phase103_75_subtree_ids(binding.find_node_by_id, imported_roots.front())
      : std::vector<std::string>{};
    binding.external_data_boundary_integrity_diag.external_data_parsed_and_applied_atomically =
      import_ok && imported_roots.size() == 1 &&
      target_after != nullptr &&
      target_after->child_ids.size() == child_count_before + 1 &&
      binding.builder_doc.nodes.size() == node_count_before + external_doc.nodes.size() &&
      imported_ids.size() == external_doc.nodes.size();
    flow_ok = binding.external_data_boundary_integrity_diag.external_data_parsed_and_applied_atomically && flow_ok;

    bool ids_valid = import_ok && !imported_roots.empty();
    if (ids_valid) {
      const std::vector<std::string> imported_ids_local =
        collect_phase103_75_subtree_ids(binding.find_node_by_id, imported_roots.front());
      for (const auto& imported_id : imported_ids_local) {
        if (!ngk::ui::builder::is_valid_node_id(imported_id) || imported_id.rfind("ext75-", 0) != 0) {
          ids_valid = false;
          break;
        }
        if (imported_id == "phase103_75_ext_root" ||
            imported_id == "phase103_75_ext_label" ||
            imported_id == "phase103_75_ext_group" ||
            imported_id == "phase103_75_ext_nested") {
          ids_valid = false;
          break;
        }
      }
      const auto* imported_root = binding.find_node_by_id(imported_roots.front());
      ids_valid = ids_valid && imported_root != nullptr && imported_root->parent_id == "phase103_75_target";
    }
    binding.external_data_boundary_integrity_diag.imported_nodes_have_valid_ids_and_relationships =
      ids_valid && ngk::ui::builder::validate_builder_document(binding.builder_doc, nullptr);
    flow_ok = binding.external_data_boundary_integrity_diag.imported_nodes_have_valid_ids_and_relationships && flow_ok;

    std::string invariant_reason;
    binding.external_data_boundary_integrity_diag.global_invariant_preserved_after_external_import =
      import_ok && binding.validate_global_document_invariant(invariant_reason);
    flow_ok = binding.external_data_boundary_integrity_diag.global_invariant_preserved_after_external_import && flow_ok;

    binding.external_data_boundary_integrity_diag.successful_external_paste_creates_single_atomic_history_entry =
      import_ok && binding.undo_history.size() == 1 && binding.redo_stack.empty() && binding.builder_doc_dirty;
    flow_ok = binding.external_data_boundary_integrity_diag.successful_external_paste_creates_single_atomic_history_entry && flow_ok;
  }

  {
    const bool loaded = load_phase103_75_document(binding, make_phase103_75_base_document(), "phase103_75_target");
    const std::string before_signature = build_phase103_75_signature(binding.builder_doc);
    const std::size_t before_history = binding.undo_history.size();
    const bool before_dirty = binding.builder_doc_dirty;
    std::string invalid_reason;
    const bool invalid_rejected = loaded &&
      !binding.import_external_builder_subtree_payload(
        invalid_layout_payload,
        "phase103_75_target",
        "phase103_75_invalid_layout",
        nullptr,
        &invalid_reason);
    std::string missing_target_reason;
    const bool missing_target_rejected = loaded &&
      !binding.import_external_builder_subtree_payload(
        valid_payload,
        "phase103_75_missing_target",
        "phase103_75_missing_target",
        nullptr,
        &missing_target_reason);
    binding.external_data_boundary_integrity_diag.external_input_cannot_bypass_global_invariant =
      loaded && invalid_rejected && missing_target_rejected &&
      !invalid_reason.empty() && !missing_target_reason.empty() &&
      build_phase103_75_signature(binding.builder_doc) == before_signature &&
      binding.undo_history.size() == before_history &&
      binding.builder_doc_dirty == before_dirty &&
      binding.validate_global_document_invariant(invalid_reason);
    flow_ok = binding.external_data_boundary_integrity_diag.external_input_cannot_bypass_global_invariant && flow_ok;

    binding.external_data_boundary_integrity_diag.failed_external_paste_creates_no_history_or_dirty_change =
      loaded && invalid_rejected &&
      build_phase103_75_signature(binding.builder_doc) == before_signature &&
      binding.undo_history.size() == before_history &&
      binding.builder_doc_dirty == before_dirty;
    flow_ok = binding.external_data_boundary_integrity_diag.failed_external_paste_creates_no_history_or_dirty_change && flow_ok;
  }

  {
    const bool loaded_a = load_phase103_75_document(binding, make_phase103_75_base_document(), "phase103_75_target");
    std::vector<std::string> imported_a{};
    const bool import_a = loaded_a &&
      binding.import_external_builder_subtree_payload(
        valid_payload,
        "phase103_75_target",
        "phase103_75_deterministic_a",
        &imported_a,
        nullptr);
    const std::string signature_a = build_phase103_75_signature(binding.builder_doc);
    const std::string subtree_a =
      (import_a && !imported_a.empty())
        ? canonical_phase103_75_subtree_signature(binding.find_node_by_id, imported_a.front())
        : std::string{};

    const bool loaded_b = load_phase103_75_document(binding, make_phase103_75_base_document(), "phase103_75_target");
    std::vector<std::string> imported_b{};
    const bool import_b = loaded_b &&
      binding.import_external_builder_subtree_payload(
        valid_payload,
        "phase103_75_target",
        "phase103_75_deterministic_b",
        &imported_b,
        nullptr);
    const std::string signature_b = build_phase103_75_signature(binding.builder_doc);
    const std::string subtree_b =
      (import_b && !imported_b.empty())
        ? canonical_phase103_75_subtree_signature(binding.find_node_by_id, imported_b.front())
        : std::string{};

    binding.external_data_boundary_integrity_diag.deterministic_result_for_identical_external_input =
      import_a && import_b && signature_a == signature_b && subtree_a == subtree_b && imported_a == imported_b;
    flow_ok = binding.external_data_boundary_integrity_diag.deterministic_result_for_identical_external_input && flow_ok;
  }

  {
    const bool loaded = load_phase103_75_document(binding, make_phase103_75_base_document(), "phase103_75_target");
    const std::string before_signature = build_phase103_75_signature(binding.builder_doc);
    const std::size_t before_history = binding.undo_history.size();
    const bool before_dirty = binding.builder_doc_dirty;
    std::string oversized_reason;
    const bool oversized_rejected = loaded &&
      !binding.import_external_builder_subtree_payload(
        oversized_payload,
        "phase103_75_target",
        "phase103_75_oversized",
        nullptr,
        &oversized_reason);
    binding.external_data_boundary_integrity_diag.large_or_invalid_payloads_fail_safely_without_crash =
      loaded && oversized_rejected &&
      oversized_reason == "payload_too_large" &&
      build_phase103_75_signature(binding.builder_doc) == before_signature &&
      binding.undo_history.size() == before_history &&
      binding.builder_doc_dirty == before_dirty;
    flow_ok = binding.external_data_boundary_integrity_diag.large_or_invalid_payloads_fail_safely_without_crash && flow_ok;
  }

  {
    binding.run_phase103_65();
    binding.external_data_boundary_integrity_diag.internal_clipboard_path_unchanged_and_isolated =
      binding.clipboard_integrity_diag.clipboard_payload_requires_valid_selection &&
      binding.clipboard_integrity_diag.duplicate_creates_fresh_unique_ids &&
      binding.clipboard_integrity_diag.paste_preserves_subtree_fidelity &&
      binding.clipboard_integrity_diag.paste_does_not_leak_runtime_state &&
      binding.clipboard_integrity_diag.paste_target_validation_fail_closed &&
      binding.clipboard_integrity_diag.cut_paste_roundtrip_preserves_structure &&
      binding.clipboard_integrity_diag.undo_redo_exact_for_clipboard_operations &&
      binding.clipboard_integrity_diag.deterministic_paste_order_and_parenting &&
      binding.clipboard_integrity_diag.nested_selection_deduplicated_on_copy &&
      binding.clipboard_integrity_diag.no_cross_node_corruption_after_clipboard_sequence;
    flow_ok = binding.external_data_boundary_integrity_diag.internal_clipboard_path_unchanged_and_isolated && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

inline ExternalImportPreparationResult prepare_external_import_candidate(
  const ngk::ui::builder::BuilderDocument& builder_doc,
  const std::string& serialized,
  const std::string& target_id) {
  ExternalImportPreparationResult result{};

  ngk::ui::builder::BuilderDocument external_doc{};
  std::string payload_reason;
  if (!::desktop_file_tool::validate_serialized_builder_document_payload(
        serialized,
        &external_doc,
        nullptr,
        &payload_reason)) {
    result.failure_reason = "payload_invalid_" + payload_reason;
    return result;
  }
  if (external_doc.nodes.empty() || external_doc.root_node_id.empty()) {
    result.failure_reason = "payload_missing_root_or_nodes";
    return result;
  }

  result.candidate_doc = builder_doc;
  std::vector<std::pair<std::string, std::string>> id_map_pairs{};
  id_map_pairs.reserve(external_doc.nodes.size());

  auto batch_contains_id = [&](const std::string& candidate_id) -> bool {
    for (const auto& pair : id_map_pairs) {
      if (pair.second == candidate_id) {
        return true;
      }
    }
    return false;
  };

  auto next_external_import_id = [&](const std::string& source_id) -> std::string {
    std::string base = std::string("ext75-") + source_id;
    std::string candidate = base;
    int suffix = 1;
    while (ngk::ui::builder::find_node_by_id(result.candidate_doc, candidate) != nullptr ||
           batch_contains_id(candidate)) {
      candidate = base + "-" + std::to_string(suffix++);
    }
    return candidate;
  };

  for (const auto& source_node : external_doc.nodes) {
    id_map_pairs.push_back({source_node.node_id, next_external_import_id(source_node.node_id)});
  }

  auto map_lookup = [&](const std::string& old_id) -> std::string {
    for (const auto& pair : id_map_pairs) {
      if (pair.first == old_id) {
        return pair.second;
      }
    }
    return std::string{};
  };

  result.imported_root_id = map_lookup(external_doc.root_node_id);
  if (result.imported_root_id.empty()) {
    result.failure_reason = "payload_root_mapping_failed";
    return result;
  }

  for (const auto& source_node : external_doc.nodes) {
    ngk::ui::builder::BuilderNode imported = source_node;
    imported.node_id = map_lookup(source_node.node_id);
    if (imported.node_id.empty()) {
      result.failure_reason = "mapped_node_id_missing";
      return result;
    }

    if (source_node.node_id == external_doc.root_node_id) {
      imported.parent_id = target_id;
    } else {
      imported.parent_id = map_lookup(source_node.parent_id);
      if (imported.parent_id.empty()) {
        result.failure_reason = "mapped_parent_id_missing";
        return result;
      }
    }

    for (auto& child_id : imported.child_ids) {
      child_id = map_lookup(child_id);
      if (child_id.empty()) {
        result.failure_reason = "mapped_child_id_missing";
        return result;
      }
    }

    result.candidate_doc.nodes.push_back(std::move(imported));
  }

  auto* candidate_target = ngk::ui::builder::find_node_by_id_mutable(result.candidate_doc, target_id);
  if (!candidate_target) {
    result.failure_reason = "target_missing_after_candidate_build";
    return result;
  }
  candidate_target->child_ids.push_back(result.imported_root_id);

  std::string candidate_validation_error;
  if (!ngk::ui::builder::validate_builder_document(result.candidate_doc, &candidate_validation_error)) {
    result.failure_reason = "candidate_invalid_" + candidate_validation_error;
    return result;
  }

  ngk::ui::builder::InstantiatedBuilderDocument runtime_candidate{};
  std::string instantiate_error;
  if (!ngk::ui::builder::instantiate_builder_document(
        result.candidate_doc,
        runtime_candidate,
        &instantiate_error)) {
    result.failure_reason = "candidate_instantiate_failed_" + instantiate_error;
    return result;
  }

  result.success = true;
  return result;
}

inline ExternalImportTransactionResult apply_external_import_transaction(
  ExternalImportTransactionContext& context,
  ngk::ui::builder::BuilderDocument candidate_doc,
  const std::string& imported_root_id,
  const std::string& history_tag,
  std::vector<std::string>* imported_root_ids_out) {
  ExternalImportTransactionResult result{};

  const std::any checkpoint = context.capture_mutation_checkpoint();
  const auto before_nodes = context.builder_doc.nodes;
  const std::string before_root = context.builder_doc.root_node_id;
  const std::string before_sel = context.selected_builder_node_id;
  const auto before_multi = context.multi_selected_node_ids;

  context.builder_doc = std::move(candidate_doc);
  context.selected_builder_node_id = imported_root_id;
  context.multi_selected_node_ids = {imported_root_id};
  context.scrub_stale_lifecycle_references();
  context.sync_multi_selection_with_primary();

  context.push_to_history(
    history_tag,
    before_nodes,
    before_root,
    before_sel,
    before_multi,
    checkpoint);
  context.recompute_builder_dirty_state(true);

  const bool remap_ok = context.remap_selection_or_fail();
  const bool focus_ok = context.sync_focus_with_selection_or_fail();
  const bool inspector_ok = context.refresh_inspector_or_fail();
  const bool preview_ok = context.refresh_preview_or_fail();
  const bool sync_ok = context.check_cross_surface_sync();
  if (!(remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok)) {
    context.restore_mutation_checkpoint(checkpoint);
    result.failure_reason = "surface_sync_failed";
    return result;
  }

  if (!context.enforce_global_invariant_or_rollback(
        checkpoint,
        "import_external_builder_subtree_payload")) {
    result.failure_reason = "global_invariant_failed";
    return result;
  }

  if (imported_root_ids_out != nullptr) {
    *imported_root_ids_out = {imported_root_id};
  }

  result.success = true;
  return result;
}

}  // namespace desktop_file_tool
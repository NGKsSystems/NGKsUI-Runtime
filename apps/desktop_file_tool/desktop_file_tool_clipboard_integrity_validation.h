#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct ClipboardIntegrityPhase10365Binding {
  BuilderClipboardDuplicateCopyPasteIntegrityHardeningDiagnostics& clipboard_integrity_diag;
  bool& undefined_state_detected;
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::vector<CommandHistoryEntry>& undo_history;
  std::vector<CommandHistoryEntry>& redo_stack;
  bool& builder_doc_dirty;
  std::string& hover_node_id;
  std::string& drag_source_node_id;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
  bool& drag_active;
  bool& inline_edit_active;
  std::string& inline_edit_node_id;
  std::string& inline_edit_buffer;
  std::string& inline_edit_original_text;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& preview_visual_feedback_node_id;
  std::string& tree_visual_feedback_node_id;
  std::function<void()> run_phase103_2;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<bool(const ngk::ui::builder::BuilderDocument&, std::vector<PreviewExportParityEntry>&, std::string&, const char*)>
    build_preview_export_parity_entries;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<std::vector<std::string>()> collect_preorder_node_ids;
  std::function<bool(const std::string&)> node_exists;
  std::function<void(const std::string&,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*,
                     const std::vector<ngk::ui::builder::BuilderNode>&,
                     const std::string&,
                     const std::string&,
                     const std::vector<std::string>*)> push_to_history;
  std::function<bool(bool)> recompute_builder_dirty_state;
  std::function<void()> scrub_stale_lifecycle_references;
  std::function<bool()> apply_delete_command_for_current_selection;
  std::function<bool(ngk::ui::builder::BuilderWidgetType, const std::string&, const std::string&)> apply_typed_palette_insert;
  std::function<bool()> document_has_unique_node_ids;
  std::function<bool()> apply_undo_command;
  std::function<bool()> apply_redo_command;
};

inline bool run_phase103_65_clipboard_integrity_phase(ClipboardIntegrityPhase10365Binding& binding) {
  bool flow_ok = true;
  binding.clipboard_integrity_diag = BuilderClipboardDuplicateCopyPasteIntegrityHardeningDiagnostics{};

  struct ClipboardPayload {
    std::vector<ngk::ui::builder::BuilderNode> nodes{};
    std::vector<std::string> root_ids{};
    int serial = 0;
  };

  ClipboardPayload clipboard{};
  int paste_serial = 0;

  auto is_container_type = [](ngk::ui::builder::BuilderWidgetType widget_type) {
    using WType = ngk::ui::builder::BuilderWidgetType;
    return widget_type == WType::VerticalLayout || widget_type == WType::HorizontalLayout ||
           widget_type == WType::ScrollContainer || widget_type == WType::ToolbarContainer ||
           widget_type == WType::SidebarContainer || widget_type == WType::ContentPanel ||
           widget_type == WType::StatusBarContainer;
  };

  auto refresh_all_surfaces = [&]() -> bool {
    bool ok = true;
    ok = binding.remap_selection_or_fail() && ok;
    ok = binding.sync_focus_with_selection_or_fail() && ok;
    ok = binding.refresh_inspector_or_fail() && ok;
    ok = binding.refresh_preview_or_fail() && ok;
    ok = binding.check_cross_surface_sync() && ok;
    return ok;
  };

  auto reset_phase = [&]() -> bool {
    binding.run_phase103_2();
    binding.undo_history.clear();
    binding.redo_stack.clear();
    binding.builder_doc_dirty = false;
    binding.hover_node_id.clear();
    binding.drag_source_node_id.clear();
    binding.drag_target_preview_node_id.clear();
    binding.drag_target_preview_is_illegal = false;
    binding.drag_active = false;
    binding.inline_edit_active = false;
    binding.inline_edit_node_id.clear();
    binding.inline_edit_buffer.clear();
    binding.inline_edit_original_text.clear();
    binding.selected_builder_node_id = binding.builder_doc.root_node_id;
    binding.focused_builder_node_id = binding.builder_doc.root_node_id;
    binding.multi_selected_node_ids = {binding.builder_doc.root_node_id};
    binding.sync_multi_selection_with_primary();
    clipboard = ClipboardPayload{};
    paste_serial = 0;
    return refresh_all_surfaces();
  };

  auto build_structure_signature = [&](const char* context_name) -> std::string {
    std::vector<PreviewExportParityEntry> entries{};
    std::string reason;
    if (!binding.build_preview_export_parity_entries(binding.builder_doc, entries, reason, context_name)) {
      return std::string("invalid:") + reason;
    }
    std::ostringstream oss;
    oss << "root=" << binding.builder_doc.root_node_id << "\n";
    for (const auto& entry : entries) {
      oss << entry.depth << "|" << entry.node_id << "|" << entry.widget_type << "|" << entry.text << "|";
      for (std::size_t idx = 0; idx < entry.child_ids.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << entry.child_ids[idx];
      }
      oss << "\n";
    }
    return oss.str();
  };

  auto collect_subtree_ids = [&](const std::string& root_id) {
    std::vector<std::string> ordered{};
    std::function<void(const std::string&)> dfs = [&](const std::string& node_id) {
      auto* node = binding.find_node_by_id(node_id);
      if (!node) {
        return;
      }
      ordered.push_back(node_id);
      for (const auto& child_id : node->child_ids) {
        dfs(child_id);
      }
    };
    dfs(root_id);
    return ordered;
  };

  auto canonical_subtree_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                         const std::string& root_id) -> std::string {
    std::function<std::string(const std::string&)> sig = [&](const std::string& node_id) -> std::string {
      const auto* node = ngk::ui::builder::find_node_by_id(doc, node_id);
      if (!node) {
        return std::string("missing:") + node_id;
      }
      std::ostringstream oss;
      oss << ngk::ui::builder::to_string(node->widget_type)
          << "#" << node->text
          << "#" << node->layout.min_width
          << "#" << node->layout.min_height
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
  };

  auto normalize_copy_roots = [&](const std::vector<std::string>& requested_ids) {
    std::vector<std::string> unique{};
    for (const auto& node_id : requested_ids) {
      if (node_id.empty() || !binding.node_exists(node_id)) {
        continue;
      }
      if (std::find(unique.begin(), unique.end(), node_id) == unique.end()) {
        unique.push_back(node_id);
      }
    }

    std::vector<std::string> roots{};
    for (const auto& node_id : unique) {
      bool has_selected_ancestor = false;
      auto* node = binding.find_node_by_id(node_id);
      std::string parent_id = node ? node->parent_id : std::string{};
      while (!parent_id.empty()) {
        if (std::find(unique.begin(), unique.end(), parent_id) != unique.end()) {
          has_selected_ancestor = true;
          break;
        }
        auto* parent = binding.find_node_by_id(parent_id);
        if (!parent) {
          break;
        }
        parent_id = parent->parent_id;
      }
      if (!has_selected_ancestor) {
        roots.push_back(node_id);
      }
    }

    const auto preorder = binding.collect_preorder_node_ids();
    std::vector<std::string> ordered_roots{};
    for (const auto& node_id : preorder) {
      if (std::find(roots.begin(), roots.end(), node_id) != roots.end()) {
        ordered_roots.push_back(node_id);
      }
    }
    return ordered_roots;
  };

  auto copy_selection_to_clipboard = [&](const std::vector<std::string>& requested_ids) -> bool {
    const auto roots = normalize_copy_roots(requested_ids);
    if (roots.empty()) {
      return false;
    }

    ClipboardPayload next{};
    next.serial = clipboard.serial + 1;
    next.root_ids = roots;
    for (const auto& root_id : roots) {
      const auto subtree_ids = collect_subtree_ids(root_id);
      if (subtree_ids.empty()) {
        return false;
      }
      for (const auto& subtree_id : subtree_ids) {
        auto* node = binding.find_node_by_id(subtree_id);
        if (!node) {
          return false;
        }
        next.nodes.push_back(*node);
      }
    }

    clipboard = std::move(next);
    return true;
  };

  auto next_unique_id = [&](const std::string& source_id,
                            std::vector<std::pair<std::string, std::string>>& map_pairs) -> std::string {
    std::string base = std::string("p65-") + std::to_string(paste_serial) + "-" + source_id;
    std::string candidate = base;
    int suffix = 1;

    auto mapped_exists = [&](const std::string& id) {
      for (const auto& pair : map_pairs) {
        if (pair.second == id) {
          return true;
        }
      }
      return false;
    };

    while (binding.node_exists(candidate) || mapped_exists(candidate)) {
      candidate = base + "-" + std::to_string(suffix++);
    }
    return candidate;
  };

  auto paste_clipboard_into_target = [&](const std::string& target_id,
                                         const std::string& history_tag,
                                         std::vector<std::string>* pasted_root_ids_out) -> bool {
    auto* target = binding.find_node_by_id(target_id);
    if (!target || !is_container_type(target->widget_type)) {
      return false;
    }
    if (clipboard.nodes.empty() || clipboard.root_ids.empty()) {
      return false;
    }

    const auto before_nodes = binding.builder_doc.nodes;
    const std::string before_root = binding.builder_doc.root_node_id;
    const std::string before_sel = binding.selected_builder_node_id;
    const auto before_multi = binding.multi_selected_node_ids;

    std::vector<std::pair<std::string, std::string>> id_map_pairs{};
    for (const auto& source_node : clipboard.nodes) {
      id_map_pairs.push_back({source_node.node_id, next_unique_id(source_node.node_id, id_map_pairs)});
    }

    auto map_lookup = [&](const std::string& old_id) -> std::string {
      for (const auto& pair : id_map_pairs) {
        if (pair.first == old_id) {
          return pair.second;
        }
      }
      return std::string{};
    };

    std::vector<std::string> pasted_roots{};
    for (const auto& root_source_id : clipboard.root_ids) {
      const std::string mapped = map_lookup(root_source_id);
      if (!mapped.empty()) {
        pasted_roots.push_back(mapped);
      }
    }
    if (pasted_roots.empty()) {
      return false;
    }

    for (const auto& source_node : clipboard.nodes) {
      ngk::ui::builder::BuilderNode pasted = source_node;
      pasted.node_id = map_lookup(source_node.node_id);
      if (pasted.node_id.empty()) {
        return false;
      }

      const bool is_root =
        std::find(clipboard.root_ids.begin(), clipboard.root_ids.end(), source_node.node_id) != clipboard.root_ids.end();
      if (is_root) {
        pasted.parent_id = target_id;
      } else {
        pasted.parent_id = map_lookup(source_node.parent_id);
        if (pasted.parent_id.empty()) {
          return false;
        }
      }

      for (auto& child_id : pasted.child_ids) {
        child_id = map_lookup(child_id);
        if (child_id.empty()) {
          return false;
        }
      }

      binding.builder_doc.nodes.push_back(std::move(pasted));
    }

    auto* refreshed_target = binding.find_node_by_id(target_id);
    if (!refreshed_target) {
      return false;
    }
    for (const auto& pasted_root : pasted_roots) {
      refreshed_target->child_ids.push_back(pasted_root);
    }

    binding.selected_builder_node_id = pasted_roots.front();
    binding.multi_selected_node_ids = pasted_roots;
    binding.sync_multi_selection_with_primary();
    binding.scrub_stale_lifecycle_references();

    binding.push_to_history(history_tag,
                            before_nodes,
                            before_root,
                            before_sel,
                            &before_multi,
                            binding.builder_doc.nodes,
                            binding.builder_doc.root_node_id,
                            binding.selected_builder_node_id,
                            &binding.multi_selected_node_ids);
    binding.recompute_builder_dirty_state(true);

    if (pasted_root_ids_out != nullptr) {
      *pasted_root_ids_out = pasted_roots;
    }
    paste_serial += 1;
    return true;
  };

  auto duplicate_selection_into_parent = [&](const std::vector<std::string>& requested_ids,
                                             const std::string& history_tag,
                                             std::vector<std::string>* duplicated_root_ids_out) -> bool {
    const auto roots = normalize_copy_roots(requested_ids);
    if (roots.empty()) {
      return false;
    }

    std::string shared_parent_id{};
    for (const auto& root_id : roots) {
      auto* root_node = binding.find_node_by_id(root_id);
      if (!root_node || root_node->parent_id.empty() || !binding.node_exists(root_node->parent_id)) {
        return false;
      }
      if (shared_parent_id.empty()) {
        shared_parent_id = root_node->parent_id;
      } else if (shared_parent_id != root_node->parent_id) {
        return false;
      }
    }

    if (!copy_selection_to_clipboard(roots)) {
      return false;
    }
    return paste_clipboard_into_target(shared_parent_id, history_tag, duplicated_root_ids_out);
  };

  auto cut_selection_to_clipboard = [&](const std::vector<std::string>& requested_ids,
                                        const std::string& history_tag,
                                        std::vector<std::string>* cut_root_ids_out) -> bool {
    const auto roots = normalize_copy_roots(requested_ids);
    if (roots.empty()) {
      return false;
    }
    if (!copy_selection_to_clipboard(roots)) {
      return false;
    }

    const auto before_nodes = binding.builder_doc.nodes;
    const std::string before_root = binding.builder_doc.root_node_id;
    const std::string before_sel = binding.selected_builder_node_id;
    const auto before_multi = binding.multi_selected_node_ids;

    binding.selected_builder_node_id = roots.front();
    binding.multi_selected_node_ids = roots;
    binding.sync_multi_selection_with_primary();

    const bool delete_ok = binding.apply_delete_command_for_current_selection();
    if (!delete_ok) {
      return false;
    }

    binding.push_to_history(history_tag,
                            before_nodes,
                            before_root,
                            before_sel,
                            &before_multi,
                            binding.builder_doc.nodes,
                            binding.builder_doc.root_node_id,
                            binding.selected_builder_node_id,
                            &binding.multi_selected_node_ids);
    binding.recompute_builder_dirty_state(true);

    if (cut_root_ids_out != nullptr) {
      *cut_root_ids_out = roots;
    }
    return true;
  };

  flow_ok = reset_phase() && flow_ok;

  const bool add65_container = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p65-src-container");
  const bool add65_child_a = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Label, "p65-src-container", "p65-src-child-a");
  const bool add65_child_b = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::Button, "p65-src-container", "p65-src-child-b");
  const bool add65_target = binding.apply_typed_palette_insert(
    ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p65-paste-target");
  flow_ok = add65_container && add65_child_a && add65_child_b && add65_target && flow_ok;
  flow_ok = refresh_all_surfaces() && flow_ok;

  {
    const int clipboard_serial_before = clipboard.serial;
    const bool copy_invalid_rejected = !copy_selection_to_clipboard({"p65-missing-a", "p65-missing-b"});
    binding.clipboard_integrity_diag.clipboard_payload_requires_valid_selection =
      copy_invalid_rejected && clipboard.serial == clipboard_serial_before && clipboard.nodes.empty();
    flow_ok = binding.clipboard_integrity_diag.clipboard_payload_requires_valid_selection && flow_ok;
  }

  {
    const bool copy_nested_ok = copy_selection_to_clipboard(
      {"p65-src-container", "p65-src-child-a", "p65-src-child-b"});
    binding.clipboard_integrity_diag.nested_selection_deduplicated_on_copy =
      copy_nested_ok && clipboard.root_ids.size() == 1 && clipboard.root_ids.front() == "p65-src-container";
    flow_ok = binding.clipboard_integrity_diag.nested_selection_deduplicated_on_copy && flow_ok;
  }

  std::vector<std::string> duplicated_roots{};
  {
    const bool duplicate_ok = duplicate_selection_into_parent(
      {"p65-src-container", "p65-src-child-a"},
      "phase103_65_duplicate",
      &duplicated_roots);
    flow_ok = duplicate_ok && flow_ok;

    bool fresh_ids = duplicate_ok && !duplicated_roots.empty() && duplicated_roots.front() != "p65-src-container";
    if (fresh_ids) {
      const auto dup_ids = collect_subtree_ids(duplicated_roots.front());
      fresh_ids = !dup_ids.empty();
      for (const auto& id : dup_ids) {
        if (id == "p65-src-container" || id == "p65-src-child-a" || id == "p65-src-child-b") {
          fresh_ids = false;
          break;
        }
      }
    }
    binding.clipboard_integrity_diag.duplicate_creates_fresh_unique_ids =
      fresh_ids && binding.document_has_unique_node_ids();
    flow_ok = binding.clipboard_integrity_diag.duplicate_creates_fresh_unique_ids && flow_ok;
  }

  std::vector<std::string> pasted_roots{};
  {
    binding.hover_node_id = "p65-src-child-a";
    binding.drag_source_node_id = "p65-src-child-a";
    binding.drag_target_preview_node_id = "p65-src-container";
    binding.drag_active = true;
    binding.inline_edit_active = true;
    binding.inline_edit_node_id = "p65-src-child-a";
    binding.inline_edit_buffer = "phase103_65_runtime_only";
    binding.inline_edit_original_text = "phase103_65_runtime_only";

    const bool copy_ok = copy_selection_to_clipboard({"p65-src-container"});
    const bool paste_ok = copy_ok && paste_clipboard_into_target("p65-paste-target", "phase103_65_paste", &pasted_roots);
    flow_ok = paste_ok && flow_ok;

    const std::string source_sig = canonical_subtree_signature(binding.builder_doc, "p65-src-container");
    const std::string pasted_sig =
      (!pasted_roots.empty() ? canonical_subtree_signature(binding.builder_doc, pasted_roots.front()) : std::string{});
    binding.clipboard_integrity_diag.paste_preserves_subtree_fidelity =
      paste_ok && !source_sig.empty() && source_sig == pasted_sig;
    flow_ok = binding.clipboard_integrity_diag.paste_preserves_subtree_fidelity && flow_ok;

    std::vector<std::string> pasted_ids{};
    if (!pasted_roots.empty()) {
      pasted_ids = collect_subtree_ids(pasted_roots.front());
    }
    auto none_runtime_refers_to_pasted = [&]() {
      for (const auto& id : pasted_ids) {
        if (id == binding.hover_node_id || id == binding.drag_source_node_id ||
            id == binding.drag_target_preview_node_id || id == binding.preview_visual_feedback_node_id ||
            id == binding.tree_visual_feedback_node_id || id == binding.inline_edit_node_id) {
          return false;
        }
      }
      return true;
    };
    binding.clipboard_integrity_diag.paste_does_not_leak_runtime_state = paste_ok && none_runtime_refers_to_pasted();
    flow_ok = binding.clipboard_integrity_diag.paste_does_not_leak_runtime_state && flow_ok;

    binding.drag_active = false;
    binding.hover_node_id.clear();
    binding.drag_source_node_id.clear();
    binding.drag_target_preview_node_id.clear();
    binding.inline_edit_active = false;
    binding.inline_edit_node_id.clear();
    binding.inline_edit_buffer.clear();
    binding.inline_edit_original_text.clear();
  }

  {
    const std::string sig_before = build_structure_signature("phase103_65_invalid_target_before");
    const std::size_t hist_before = binding.undo_history.size();
    const bool paste_rejected_leaf =
      !paste_clipboard_into_target("label-001", "phase103_65_invalid_target_leaf", nullptr);
    const bool paste_rejected_missing =
      !paste_clipboard_into_target("phase103_65_missing_target", "phase103_65_invalid_target_missing", nullptr);
    const std::string sig_after = build_structure_signature("phase103_65_invalid_target_after");
    binding.clipboard_integrity_diag.paste_target_validation_fail_closed =
      paste_rejected_leaf && paste_rejected_missing && sig_before == sig_after && binding.undo_history.size() == hist_before;
    flow_ok = binding.clipboard_integrity_diag.paste_target_validation_fail_closed && flow_ok;
  }

  {
    const bool add_cut_parent = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p65-cut-parent");
    const bool add_cut_child = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "p65-cut-parent", "p65-cut-child");
    flow_ok = add_cut_parent && add_cut_child && flow_ok;

    const std::string cut_before_sig = canonical_subtree_signature(binding.builder_doc, "p65-cut-parent");
    std::vector<std::string> cut_roots{};
    const bool cut_ok = cut_selection_to_clipboard({"p65-cut-parent"}, "phase103_65_cut", &cut_roots);
    const bool removed_after_cut = cut_ok && !binding.node_exists("p65-cut-parent") && !binding.node_exists("p65-cut-child");
    std::vector<std::string> cut_pasted_roots{};
    const bool paste_cut_ok = cut_ok && paste_clipboard_into_target("root-001", "phase103_65_paste_cut", &cut_pasted_roots);
    const std::string cut_after_sig =
      (!cut_pasted_roots.empty() ? canonical_subtree_signature(binding.builder_doc, cut_pasted_roots.front()) : std::string{});

    binding.clipboard_integrity_diag.cut_paste_roundtrip_preserves_structure =
      cut_ok && removed_after_cut && paste_cut_ok && !cut_before_sig.empty() && cut_before_sig == cut_after_sig;
    flow_ok = binding.clipboard_integrity_diag.cut_paste_roundtrip_preserves_structure && flow_ok;
  }

  {
    const std::string before_sig = build_structure_signature("phase103_65_undo_before");
    const std::string before_sel = binding.selected_builder_node_id;
    const auto before_multi = binding.multi_selected_node_ids;

    std::vector<std::string> undo_pasted_roots{};
    const bool copy_ok = copy_selection_to_clipboard({"p65-src-container"});
    const bool paste_ok = copy_ok && paste_clipboard_into_target("root-001", "phase103_65_undo_paste", &undo_pasted_roots);
    const std::string after_sig = build_structure_signature("phase103_65_undo_after");
    const std::string after_sel = binding.selected_builder_node_id;
    const auto after_multi = binding.multi_selected_node_ids;

    const bool undo_ok = paste_ok && binding.apply_undo_command();
    const bool undo_exact =
      undo_ok && build_structure_signature("phase103_65_undo_reverted") == before_sig &&
      binding.selected_builder_node_id == before_sel && binding.multi_selected_node_ids == before_multi;
    const bool redo_ok = undo_ok && binding.apply_redo_command();
    const bool redo_exact =
      redo_ok && build_structure_signature("phase103_65_redo_reapplied") == after_sig &&
      binding.selected_builder_node_id == after_sel && binding.multi_selected_node_ids == after_multi;

    binding.clipboard_integrity_diag.undo_redo_exact_for_clipboard_operations = undo_exact && redo_exact;
    flow_ok = binding.clipboard_integrity_diag.undo_redo_exact_for_clipboard_operations && flow_ok;
  }

  {
    auto run_order_case = [&]() -> std::string {
      binding.run_phase103_2();
      binding.undo_history.clear();
      binding.redo_stack.clear();
      clipboard = ClipboardPayload{};
      paste_serial = 0;
      const bool o1 = binding.apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p65-order-a");
      const bool o2 = binding.apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Button, "root-001", "p65-order-b");
      const bool o3 = binding.apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p65-order-c");
      const bool ot = binding.apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p65-order-target");
      if (!(o1 && o2 && o3 && ot)) {
        return std::string("invalid:setup");
      }
      if (!copy_selection_to_clipboard({"p65-order-b", "p65-order-a"})) {
        return std::string("invalid:copy");
      }
      std::vector<std::string> pasted{};
      if (!paste_clipboard_into_target("p65-order-target", "phase103_65_order_paste", &pasted)) {
        return std::string("invalid:paste");
      }
      auto* target = binding.find_node_by_id("p65-order-target");
      if (!target || pasted.empty()) {
        return std::string("invalid:target");
      }
      std::ostringstream oss;
      for (std::size_t idx = 0; idx < target->child_ids.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << target->child_ids[idx];
      }
      for (const auto& pasted_root : pasted) {
        const auto* node = binding.find_node_by_id(pasted_root);
        if (!node || node->parent_id != "p65-order-target") {
          return std::string("invalid:parenting");
        }
      }
      return oss.str();
    };

    const std::string order_sig1 = run_order_case();
    const std::string order_sig2 = run_order_case();
    binding.clipboard_integrity_diag.deterministic_paste_order_and_parenting =
      !order_sig1.empty() && !order_sig2.empty() && order_sig1 == order_sig2;
    flow_ok = binding.clipboard_integrity_diag.deterministic_paste_order_and_parenting && flow_ok;
  }

  {
    const bool reset_ok = reset_phase();
    auto* untouched_before = binding.find_node_by_id("label-001");
    const std::string untouched_text_before = untouched_before ? untouched_before->text : std::string{};
    const bool c1 = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p65-x-a");
    const bool c2 = binding.apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "p65-x-b");
    flow_ok = reset_ok && c1 && c2 && flow_ok;
    const bool copy_ok = copy_selection_to_clipboard({"p65-x-a", "p65-x-b"});
    const bool paste_ok = copy_ok && paste_clipboard_into_target("root-001", "phase103_65_cross_paste", nullptr);
    const bool delete_ok = paste_ok && binding.apply_delete_command_for_current_selection();
    const bool sync_ok = refresh_all_surfaces();
    const auto* untouched_after = binding.find_node_by_id("label-001");

    binding.clipboard_integrity_diag.no_cross_node_corruption_after_clipboard_sequence =
      reset_ok && copy_ok && paste_ok && delete_ok && sync_ok && untouched_after != nullptr &&
      untouched_after->text == untouched_text_before && binding.document_has_unique_node_ids();
    flow_ok = binding.clipboard_integrity_diag.no_cross_node_corruption_after_clipboard_sequence && flow_ok;
  }

  if (!flow_ok) {
    binding.undefined_state_detected = true;
  }
  return flow_ok;
}

}  // namespace desktop_file_tool
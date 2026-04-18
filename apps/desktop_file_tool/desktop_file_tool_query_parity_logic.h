#pragma once

#include <algorithm>
#include <functional>
#include <iterator>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "builder_document.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct BuilderQueryParityLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& hover_node_id;
  std::string& drag_target_preview_node_id;
  bool& drag_target_preview_is_illegal;
};

class BuilderQueryParityLogic {
 public:
  explicit BuilderQueryParityLogic(BuilderQueryParityLogicBinding& binding) : binding_(binding) {}

  ngk::ui::builder::BuilderNode* find_node_by_id(const std::string& node_id) const {
    for (auto& node : binding_.builder_doc.nodes) {
      if (node.node_id == node_id) {
        return &node;
      }
    }
    return nullptr;
  }

  bool node_exists(const std::string& node_id) const {
    return find_node_by_id(node_id) != nullptr;
  }

  std::string node_identity_text(const ngk::ui::builder::BuilderNode& node) const {
    const std::string node_text = node.text.empty() ? std::string("<no-text>") : node.text;
    return node.node_id + " " + ngk::ui::builder::to_string(node.widget_type) + " \"" + node_text + "\"";
  }

  const ngk::ui::builder::BuilderNode* find_node_by_id_in_document(
    const ngk::ui::builder::BuilderDocument& doc,
    const std::string& node_id) const {
    for (const auto& node : doc.nodes) {
      if (node.node_id == node_id) {
        return &node;
      }
    }
    return nullptr;
  }

  bool node_exists_in_document(const ngk::ui::builder::BuilderDocument& doc, const std::string& node_id) const {
    return find_node_by_id_in_document(doc, node_id) != nullptr;
  }

  std::string normalize_selected_id_for_snapshot(
    const ngk::ui::builder::BuilderDocument& target_doc,
    const std::string& preferred_selected_id,
    const std::vector<std::string>& preferred_multi_selected_ids,
    const ngk::ui::builder::BuilderDocument* counterpart_doc,
    const std::string& counterpart_selected_id) const {
    if (!preferred_selected_id.empty() && node_exists_in_document(target_doc, preferred_selected_id)) {
      return preferred_selected_id;
    }
    for (const auto& node_id : preferred_multi_selected_ids) {
      if (!node_id.empty() && node_exists_in_document(target_doc, node_id)) {
        return node_id;
      }
    }
    if (counterpart_doc != nullptr && !counterpart_selected_id.empty()) {
      const auto* counterpart_selected = find_node_by_id_in_document(*counterpart_doc, counterpart_selected_id);
      if (counterpart_selected != nullptr) {
        std::string fallback_parent_id = counterpart_selected->parent_id;
        while (!fallback_parent_id.empty()) {
          if (node_exists_in_document(target_doc, fallback_parent_id)) {
            return fallback_parent_id;
          }
          const auto* fallback_parent = find_node_by_id_in_document(*counterpart_doc, fallback_parent_id);
          if (fallback_parent == nullptr) {
            break;
          }
          fallback_parent_id = fallback_parent->parent_id;
        }
      }
    }
    if (!target_doc.root_node_id.empty() && node_exists_in_document(target_doc, target_doc.root_node_id)) {
      return target_doc.root_node_id;
    }
    return std::string{};
  }

  std::vector<std::string> normalize_multi_selection_for_snapshot(
    const ngk::ui::builder::BuilderDocument& target_doc,
    const std::string& selected_id,
    const std::vector<std::string>& preferred_multi_selected_ids) const {
    std::vector<std::string> stable{};
    stable.reserve(preferred_multi_selected_ids.size() + 1);
    auto append_unique_valid = [&](const std::string& node_id) {
      if (node_id.empty() || !node_exists_in_document(target_doc, node_id)) {
        return;
      }
      if (std::find(stable.begin(), stable.end(), node_id) == stable.end()) {
        stable.push_back(node_id);
      }
    };
    append_unique_valid(selected_id);
    for (const auto& node_id : preferred_multi_selected_ids) {
      append_unique_valid(node_id);
    }
    return stable;
  }

  std::string normalize_focus_id_for_snapshot(
    const ngk::ui::builder::BuilderDocument& target_doc,
    const std::string& selected_id,
    const std::string& preferred_focus_id) const {
    if (!preferred_focus_id.empty() && node_exists_in_document(target_doc, preferred_focus_id)) {
      return preferred_focus_id;
    }
    if (!selected_id.empty() && node_exists_in_document(target_doc, selected_id)) {
      return selected_id;
    }
    if (!target_doc.root_node_id.empty() && node_exists_in_document(target_doc, target_doc.root_node_id)) {
      return target_doc.root_node_id;
    }
    return std::string{};
  }

  std::string normalize_anchor_id_for_snapshot(
    const ngk::ui::builder::BuilderDocument& target_doc,
    const std::string& selected_id,
    const std::vector<std::string>& multi_selected_ids,
    const std::string& preferred_anchor_id) const {
    if (!preferred_anchor_id.empty() && node_exists_in_document(target_doc, preferred_anchor_id) &&
        std::find(multi_selected_ids.begin(), multi_selected_ids.end(), preferred_anchor_id) != multi_selected_ids.end()) {
      return preferred_anchor_id;
    }
    if (!selected_id.empty() && node_exists_in_document(target_doc, selected_id) &&
        std::find(multi_selected_ids.begin(), multi_selected_ids.end(), selected_id) != multi_selected_ids.end()) {
      return selected_id;
    }
    return std::string{};
  }

  bool normalize_history_entry(CommandHistoryEntry& entry) const {
    ngk::ui::builder::BuilderDocument before_doc{};
    before_doc.root_node_id = entry.before_root_node_id;
    before_doc.nodes = entry.before_nodes;

    ngk::ui::builder::BuilderDocument after_doc{};
    after_doc.root_node_id = entry.after_root_node_id;
    after_doc.nodes = entry.after_nodes;

    std::string before_error;
    std::string after_error;
    if (!ngk::ui::builder::validate_builder_document(before_doc, &before_error) ||
        !ngk::ui::builder::validate_builder_document(after_doc, &after_error)) {
      return false;
    }

    entry.before_selected_id = normalize_selected_id_for_snapshot(
      before_doc,
      entry.before_selected_id,
      entry.before_multi_selected_ids,
      &after_doc,
      entry.after_selected_id);
    entry.before_multi_selected_ids = normalize_multi_selection_for_snapshot(
      before_doc,
      entry.before_selected_id,
      entry.before_multi_selected_ids);
    entry.before_focused_id = normalize_focus_id_for_snapshot(
      before_doc,
      entry.before_selected_id,
      entry.before_focused_id);
    entry.before_anchor_id = normalize_anchor_id_for_snapshot(
      before_doc,
      entry.before_selected_id,
      entry.before_multi_selected_ids,
      entry.before_anchor_id);

    entry.after_selected_id = normalize_selected_id_for_snapshot(
      after_doc,
      entry.after_selected_id,
      entry.after_multi_selected_ids,
      &before_doc,
      entry.before_selected_id);
    entry.after_multi_selected_ids = normalize_multi_selection_for_snapshot(
      after_doc,
      entry.after_selected_id,
      entry.after_multi_selected_ids);
    entry.after_focused_id = normalize_focus_id_for_snapshot(
      after_doc,
      entry.after_selected_id,
      entry.after_focused_id);
    entry.after_anchor_id = normalize_anchor_id_for_snapshot(
      after_doc,
      entry.after_selected_id,
      entry.after_multi_selected_ids,
      entry.after_anchor_id);

    return !entry.before_selected_id.empty() && !entry.after_selected_id.empty();
  }

  bool build_preview_export_parity_entries(
    const ngk::ui::builder::BuilderDocument& doc,
    std::vector<PreviewExportParityEntry>& entries,
    std::string& reason_out,
    const char* context_name) const {
    entries.clear();

    std::string validation_error;
    if (!ngk::ui::builder::validate_builder_document(doc, &validation_error)) {
      reason_out = std::string(context_name == nullptr ? "document" : context_name) +
        "_validation_failed";
      return false;
    }

    if (doc.root_node_id.empty()) {
      reason_out = std::string(context_name == nullptr ? "document" : context_name) +
        "_missing_root_node";
      return false;
    }

    const auto* root_node = find_node_by_id_in_document(doc, doc.root_node_id);
    if (root_node == nullptr) {
      reason_out = std::string(context_name == nullptr ? "document" : context_name) +
        "_root_node_missing_from_table";
      return false;
    }

    std::vector<std::pair<std::string, int>> stack{};
    stack.push_back({doc.root_node_id, 0});
    while (!stack.empty()) {
      const auto current = stack.back();
      stack.pop_back();

      const auto* node = find_node_by_id_in_document(doc, current.first);
      if (node == nullptr) {
        reason_out = std::string(context_name == nullptr ? "document" : context_name) +
          "_node_missing_" + current.first;
        return false;
      }

      PreviewExportParityEntry entry{};
      entry.depth = current.second;
      entry.node_id = node->node_id;
      entry.widget_type = ngk::ui::builder::to_string(node->widget_type);
      entry.text = node->text.empty() ? std::string("<no-text>") : node->text;
      entry.child_ids = node->child_ids;
      entries.push_back(entry);

      for (auto child_it = node->child_ids.rbegin(); child_it != node->child_ids.rend(); ++child_it) {
        if (child_it->empty()) {
          reason_out = std::string(context_name == nullptr ? "document" : context_name) +
            "_empty_child_id_parent_" + node->node_id;
          return false;
        }
        if (find_node_by_id_in_document(doc, *child_it) == nullptr) {
          reason_out = std::string(context_name == nullptr ? "document" : context_name) +
            "_missing_child_" + *child_it + "_parent_" + node->node_id;
          return false;
        }
        stack.push_back({*child_it, current.second + 1});
      }
    }

    reason_out = "none";
    return true;
  }

  std::string preview_identity_role(const PreviewExportParityEntry& entry) const {
    if (entry.widget_type == "button") {
      return "BUTTON";
    }
    if (entry.widget_type == "label") {
      return "LABEL";
    }
    if (entry.widget_type == "input_box") {
      return "INPUT";
    }
    if (entry.widget_type == "list_view" || entry.widget_type == "table_view") {
      return "DATA";
    }
    if (entry.widget_type == "content_panel" ||
        entry.widget_type == "scroll_container" ||
        entry.widget_type == "toolbar_container" ||
        entry.widget_type == "sidebar_container" ||
        entry.widget_type == "status_bar_container" ||
        entry.widget_type == "section_header") {
      return "REGION";
    }
    if (!entry.child_ids.empty() ||
        entry.widget_type == "vertical_layout" ||
        entry.widget_type == "horizontal_layout") {
      return "CONTAINER";
    }
    return "NODE";
  }

  std::string build_preview_runtime_outline() const {
    std::vector<PreviewExportParityEntry> entries{};
    std::string reason;
    if (!build_preview_export_parity_entries(binding_.builder_doc, entries, reason, "preview_surface")) {
      return std::string("outline_unavailable reason=") + reason;
    }

    std::ostringstream oss;
    for (const auto& entry : entries) {
      const bool is_selected = (entry.node_id == binding_.selected_builder_node_id);
      const bool is_focused = (entry.node_id == binding_.focused_builder_node_id);
      const bool is_secondary =
        !is_selected &&
        std::find(binding_.multi_selected_node_ids.begin(), binding_.multi_selected_node_ids.end(), entry.node_id) !=
          binding_.multi_selected_node_ids.end();
      const bool is_hover = (entry.node_id == binding_.hover_node_id) && !is_selected;
      const bool is_drag_tgt = !binding_.drag_target_preview_node_id.empty() &&
        (entry.node_id == binding_.drag_target_preview_node_id);
      const std::string indent = entry.depth == 0
        ? std::string()
        : std::string(static_cast<std::size_t>(entry.depth - 1) * 2U, ' ');
      const std::string branch = entry.depth == 0 ? std::string("# ") : indent + "+- ";
      oss << branch
          << (is_selected ? ">> " : "   ")
          << "[" << preview_identity_role(entry) << "] "
          << entry.node_id
          << " type=" << entry.widget_type
          << " text=\"" << entry.text << "\""
          << " children=" << entry.child_ids.size();
      if (is_selected) {
        oss << " [SELECTED]";
      }
      if (is_secondary) {
        oss << " [MULTI_SECONDARY]";
      }
      if (is_focused) {
        oss << " [FOCUS]";
      }
      if (is_hover) {
        oss << " [HOVER]";
      }
      if (is_drag_tgt && !binding_.drag_target_preview_is_illegal) {
        oss << " [DRAG_TARGET]";
      }
      if (is_drag_tgt && binding_.drag_target_preview_is_illegal) {
        oss << " [ILLEGAL_DROP]";
      }
      oss << "\n";
    }
    return oss.str();
  }

  bool build_preview_click_hit_entries(
    std::vector<PreviewExportParityEntry>& entries_out,
    std::string& reason_out) const {
    return build_preview_export_parity_entries(
      binding_.builder_doc,
      entries_out,
      reason_out,
      "preview_click_hit_map");
  }

  bool is_text_editable_widget_type(ngk::ui::builder::BuilderWidgetType type) const {
    using WType = ngk::ui::builder::BuilderWidgetType;
    return type == WType::Label || type == WType::Button ||
           type == WType::InputBox || type == WType::SectionHeader;
  }

  bool is_container_widget_type(ngk::ui::builder::BuilderWidgetType type) const {
    using WType = ngk::ui::builder::BuilderWidgetType;
    return type == WType::VerticalLayout || type == WType::HorizontalLayout ||
           type == WType::ScrollContainer || type == WType::ToolbarContainer ||
           type == WType::SidebarContainer || type == WType::ContentPanel ||
           type == WType::StatusBarContainer;
  }

  std::vector<PreviewInlineActionAffordanceEntry> build_preview_inline_action_entries(
    const ngk::ui::builder::BuilderNode& selected) const {
    std::vector<PreviewInlineActionAffordanceEntry> entries{};

    auto add_entry = [&](const std::string& action_id,
                         bool available,
                         bool commit_capable,
                         const std::string& blocked_reason,
                         const std::string& command_path) {
      PreviewInlineActionAffordanceEntry entry{};
      entry.action_id = action_id;
      entry.available = available;
      entry.commit_capable = commit_capable;
      entry.blocked_reason = blocked_reason;
      entry.command_path = command_path;
      entries.push_back(std::move(entry));
    };

    const bool can_insert_under_selected = is_container_widget_type(selected.widget_type);
    add_entry(
      "INSERT_CONTAINER_UNDER_SELECTED",
      can_insert_under_selected,
      false,
      can_insert_under_selected ? std::string("none") : std::string("selected_not_container"),
      "not_in_preview_commit_scope");
    add_entry(
      "INSERT_LEAF_UNDER_SELECTED",
      can_insert_under_selected,
      can_insert_under_selected,
      can_insert_under_selected ? std::string("none") : std::string("selected_not_container"),
      "apply_typed_palette_insert");

    const bool can_edit_text = is_text_editable_widget_type(selected.widget_type);
    add_entry(
      "EDIT_TEXT_SELECTED",
      can_edit_text,
      can_edit_text,
      can_edit_text ? std::string("none") : std::string("selected_not_text_editable"),
      "apply_inspector_text_edit_command");

    bool can_delete = true;
    std::string delete_block_reason = "none";
    if (selected.node_id == binding_.builder_doc.root_node_id) {
      can_delete = false;
      delete_block_reason = "protected_root";
    } else if (selected.container_type == ngk::ui::builder::BuilderContainerType::Shell) {
      can_delete = false;
      delete_block_reason = "protected_shell";
    }
    add_entry(
      "DELETE_SELECTED",
      can_delete,
      can_delete,
      can_delete ? std::string("none") : delete_block_reason,
      "apply_delete_selected_node_command");

    bool can_move_up = false;
    bool can_move_down = false;
    std::string move_block_reason = "missing_parent_or_siblings";
    if (!selected.parent_id.empty()) {
      if (auto* parent = find_node_by_id(selected.parent_id)) {
        auto it = std::find(parent->child_ids.begin(), parent->child_ids.end(), selected.node_id);
        if (it != parent->child_ids.end()) {
          can_move_up = (it != parent->child_ids.begin());
          can_move_down = (std::next(it) != parent->child_ids.end());
          if (!can_move_up && !can_move_down) {
            move_block_reason = "single_child_order_fixed";
          }
        }
      }
    }
    add_entry(
      "MOVE_SELECTED_UP",
      can_move_up,
      false,
      can_move_up ? std::string("none") : move_block_reason,
      "not_in_preview_commit_scope");
    add_entry(
      "MOVE_SELECTED_DOWN",
      can_move_down,
      false,
      can_move_down ? std::string("none") : move_block_reason,
      "not_in_preview_commit_scope");

    return entries;
  }

  std::string build_preview_inline_action_affordance_text(
    const ngk::ui::builder::BuilderNode& selected) const {
    const auto entries = build_preview_inline_action_entries(selected);
    std::ostringstream affordance;
    affordance << "PREVIEW_INLINE_ACTIONS=COMMIT_WHEN_ACTION_COMMIT_VISIBLE\n";

    bool any_available = false;
    for (const auto& entry : entries) {
      if (!entry.available) {
        continue;
      }
      any_available = true;
      affordance << "ACTION_AVAILABLE: " << entry.action_id << "\n";
      if (entry.commit_capable) {
        affordance << "ACTION_COMMIT: " << entry.action_id << " [via=" << entry.command_path << "]\n";
      }
    }
    if (!any_available) {
      affordance << "ACTION_AVAILABLE: <none>\n";
    }

    for (const auto& entry : entries) {
      if (entry.available) {
        continue;
      }
      affordance << "ACTION_BLOCKED: " << entry.action_id << " [" << entry.blocked_reason << "]\n";
    }

    return affordance.str();
  }

 private:
  BuilderQueryParityLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_QUERY_PARITY_LOGIC(logic_object) \
  auto find_node_by_id = [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { \
    return (logic_object).find_node_by_id(node_id); \
  }; \
  auto node_exists = [&](const std::string& node_id) -> bool { \
    return (logic_object).node_exists(node_id); \
  }; \
  auto node_identity_text = [&](const ngk::ui::builder::BuilderNode& node) -> std::string { \
    return (logic_object).node_identity_text(node); \
  }; \
  auto find_node_by_id_in_document = [&](const ngk::ui::builder::BuilderDocument& doc, const std::string& node_id) \
    -> const ngk::ui::builder::BuilderNode* { \
    return (logic_object).find_node_by_id_in_document(doc, node_id); \
  }; \
  auto node_exists_in_document = [&](const ngk::ui::builder::BuilderDocument& doc, const std::string& node_id) -> bool { \
    return (logic_object).node_exists_in_document(doc, node_id); \
  }; \
  auto normalize_selected_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc, \
                                                const std::string& preferred_selected_id, \
                                                const std::vector<std::string>& preferred_multi_selected_ids, \
                                                const ngk::ui::builder::BuilderDocument* counterpart_doc, \
                                                const std::string& counterpart_selected_id) -> std::string { \
    return (logic_object).normalize_selected_id_for_snapshot( \
      target_doc, preferred_selected_id, preferred_multi_selected_ids, counterpart_doc, counterpart_selected_id); \
  }; \
  auto normalize_multi_selection_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc, \
                                                    const std::string& selected_id, \
                                                    const std::vector<std::string>& preferred_multi_selected_ids) { \
    return (logic_object).normalize_multi_selection_for_snapshot(target_doc, selected_id, preferred_multi_selected_ids); \
  }; \
  auto normalize_focus_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc, \
                                             const std::string& selected_id, \
                                             const std::string& preferred_focus_id) -> std::string { \
    return (logic_object).normalize_focus_id_for_snapshot(target_doc, selected_id, preferred_focus_id); \
  }; \
  auto normalize_anchor_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc, \
                                              const std::string& selected_id, \
                                              const std::vector<std::string>& multi_selected_ids, \
                                              const std::string& preferred_anchor_id) -> std::string { \
    return (logic_object).normalize_anchor_id_for_snapshot( \
      target_doc, selected_id, multi_selected_ids, preferred_anchor_id); \
  }; \
  auto normalize_history_entry = [&](CommandHistoryEntry& entry) -> bool { \
    return (logic_object).normalize_history_entry(entry); \
  }; \
  auto build_preview_export_parity_entries = [&](const ngk::ui::builder::BuilderDocument& doc, \
                                                 std::vector<PreviewExportParityEntry>& entries, \
                                                 std::string& reason_out, \
                                                 const char* context_name) -> bool { \
    return (logic_object).build_preview_export_parity_entries(doc, entries, reason_out, context_name); \
  }; \
  auto preview_identity_role = [&](const PreviewExportParityEntry& entry) -> std::string { \
    return (logic_object).preview_identity_role(entry); \
  }; \
  auto build_preview_runtime_outline = [&]() -> std::string { \
    return (logic_object).build_preview_runtime_outline(); \
  }; \
  auto build_preview_click_hit_entries = [&](std::vector<PreviewExportParityEntry>& entries_out, \
                                             std::string& reason_out) -> bool { \
    return (logic_object).build_preview_click_hit_entries(entries_out, reason_out); \
  }; \
  auto is_text_editable_widget_type = [&](ngk::ui::builder::BuilderWidgetType type) -> bool { \
    return (logic_object).is_text_editable_widget_type(type); \
  }; \
  auto is_container_widget_type = [&](ngk::ui::builder::BuilderWidgetType type) -> bool { \
    return (logic_object).is_container_widget_type(type); \
  }; \
  auto build_preview_inline_action_entries = [&](const ngk::ui::builder::BuilderNode& selected) { \
    return (logic_object).build_preview_inline_action_entries(selected); \
  }; \
  auto build_preview_inline_action_affordance_text = [&](const ngk::ui::builder::BuilderNode& selected) -> std::string { \
    return (logic_object).build_preview_inline_action_affordance_text(selected); \
  };
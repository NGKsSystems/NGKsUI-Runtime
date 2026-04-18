#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "builder_document.hpp"

namespace desktop_file_tool {

struct ActionShortcutRoutingLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  bool& builder_doc_dirty;
  std::string& last_action_dispatch_requested_id;
  std::string& last_action_dispatch_resolved_id;
  std::string& last_action_dispatch_source;
  bool& last_action_dispatch_success;
  bool& shortcut_scope_rules_defined;
  std::function<bool()> focused_text_input_active;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool()> undo_history_available;
  std::function<bool()> redo_stack_available;
  std::function<bool(bool, bool)> apply_keyboard_multi_selection_navigate;
  std::function<bool()> apply_keyboard_multi_selection_add_focused;
  std::function<bool()> apply_keyboard_multi_selection_remove_focused;
  std::function<bool()> apply_keyboard_multi_selection_clear;
  std::function<bool(bool)> apply_tree_navigation;
  std::function<bool(bool)> apply_tree_parent_child_navigation;
  std::function<bool()> perform_insert_container_action;
  std::function<bool()> perform_insert_leaf_action;
  std::function<bool()> perform_delete_current_action;
  std::function<bool()> perform_undo_action;
  std::function<bool()> perform_redo_action;
  std::function<bool()> perform_save_action;
  std::function<bool(bool)> perform_load_action;
  std::function<bool(bool)> perform_new_action;
  std::function<bool()> remap_selection_or_fail;
  std::function<bool()> sync_focus_with_selection_or_fail;
  std::function<bool()> refresh_inspector_or_fail;
  std::function<bool()> refresh_preview_or_fail;
  std::function<bool()> check_cross_surface_sync;
  std::function<bool()> ctrl_down_active;
  std::function<bool()> shift_down_active;
};

class ActionShortcutRoutingLogic {
 public:
  explicit ActionShortcutRoutingLogic(ActionShortcutRoutingLogicBinding& binding) : binding_(binding) {}

  bool evaluate_builder_action_eligibility(const std::string& action_id,
                                           std::string& blocked_reason_out) const {
    blocked_reason_out.clear();
    if (action_id == "ACTION_INSERT_CONTAINER" || action_id == "ACTION_INSERT_LEAF") {
      if (binding_.builder_doc.nodes.empty()) {
        blocked_reason_out = "document_unavailable";
        return false;
      }
      return true;
    }
    if (action_id == "ACTION_DELETE_CURRENT") {
      const bool has_selection =
        !binding_.selected_builder_node_id.empty() &&
        binding_.node_exists(binding_.selected_builder_node_id) &&
        binding_.selected_builder_node_id != binding_.builder_doc.root_node_id;
      const bool has_multi_target = [&]() {
        for (const auto& id : binding_.multi_selected_node_ids) {
          if (id != binding_.builder_doc.root_node_id && binding_.node_exists(id)) {
            return true;
          }
        }
        return false;
      }();
      if (!(has_selection || has_multi_target)) {
        blocked_reason_out = "no_deletable_selection";
        return false;
      }
      return true;
    }
    if (action_id == "ACTION_UNDO") {
      if (!binding_.undo_history_available()) {
        blocked_reason_out = "undo_empty";
        return false;
      }
      return true;
    }
    if (action_id == "ACTION_REDO") {
      if (!binding_.redo_stack_available()) {
        blocked_reason_out = "redo_empty";
        return false;
      }
      return true;
    }
    if (action_id == "ACTION_SAVE") {
      if (binding_.builder_doc.nodes.empty()) {
        blocked_reason_out = "document_unavailable";
        return false;
      }
      return true;
    }
    if (action_id == "ACTION_LOAD") {
      if (binding_.builder_doc_dirty) {
        blocked_reason_out = "dirty_document_requires_explicit_discard";
        return false;
      }
      return true;
    }
    if (action_id == "ACTION_LOAD_FORCE_DISCARD") {
      return true;
    }
    if (action_id == "ACTION_NEW") {
      if (binding_.builder_doc_dirty) {
        blocked_reason_out = "dirty_document_requires_explicit_discard";
        return false;
      }
      return true;
    }
    if (action_id == "ACTION_NEW_FORCE_DISCARD") {
      return true;
    }
    if (action_id == "ACTION_EXPORT") {
      if (binding_.builder_doc.nodes.empty()) {
        blocked_reason_out = "document_unavailable";
        return false;
      }
      return true;
    }
    blocked_reason_out = "unknown_action";
    return false;
  }

  bool invoke_builder_action(const std::string& action_id,
                             const char* invocation_source) const {
    binding_.last_action_dispatch_requested_id = action_id;
    binding_.last_action_dispatch_resolved_id.clear();
    binding_.last_action_dispatch_source = invocation_source ? invocation_source : "unknown";
    binding_.last_action_dispatch_success = false;

    std::string blocked_reason;
    if (!evaluate_builder_action_eligibility(action_id, blocked_reason)) {
      return false;
    }

    if (!perform_action(action_id)) {
      return false;
    }

    binding_.last_action_dispatch_resolved_id = action_id;
    binding_.last_action_dispatch_success = true;
    binding_.remap_selection_or_fail();
    binding_.sync_focus_with_selection_or_fail();
    binding_.refresh_inspector_or_fail();
    binding_.refresh_preview_or_fail();
    binding_.check_cross_surface_sync();
    return true;
  }

  bool handle_builder_shortcut_key_with_modifiers(std::uint32_t key,
                                                  bool down,
                                                  bool repeat,
                                                  bool ctrl_down,
                                                  bool shift_down) const {
    if (!down || repeat) {
      return false;
    }
    if (!is_builder_shortcut_scope_active()) {
      return false;
    }

    bool handled = false;
    if (ctrl_down) {
      switch (key) {
        case 0x26:
          handled = binding_.apply_keyboard_multi_selection_navigate(false, shift_down);
          break;
        case 0x28:
          handled = binding_.apply_keyboard_multi_selection_navigate(true, shift_down);
          break;
        case 0x41:
          handled = binding_.apply_keyboard_multi_selection_add_focused();
          break;
        case 0x52:
          handled = binding_.apply_keyboard_multi_selection_remove_focused();
          break;
        case 0x1B:
          handled = binding_.apply_keyboard_multi_selection_clear();
          break;
        case 0x5A:
          handled = invoke_builder_action("ACTION_UNDO", "shortcut");
          break;
        case 0x59:
          handled = invoke_builder_action("ACTION_REDO", "shortcut");
          break;
        case 0x53:
          handled = invoke_builder_action("ACTION_SAVE", "shortcut");
          break;
        case 0x4F:
          handled = invoke_builder_action("ACTION_LOAD", "shortcut");
          break;
        case 0x4E:
          handled = invoke_builder_action("ACTION_NEW", "shortcut");
          break;
        default:
          break;
      }
    } else {
      switch (key) {
        case 0x26:
          handled = binding_.apply_tree_navigation(false);
          break;
        case 0x28:
          handled = binding_.apply_tree_navigation(true);
          break;
        case 0x25:
          handled = binding_.apply_tree_parent_child_navigation(true);
          break;
        case 0x27:
          handled = binding_.apply_tree_parent_child_navigation(false);
          break;
        case 0x5A:
          handled = invoke_builder_action("ACTION_UNDO", "shortcut");
          break;
        case 0x59:
          handled = invoke_builder_action("ACTION_REDO", "shortcut");
          break;
        case 0x2E:
          handled = invoke_builder_action("ACTION_DELETE_CURRENT", "shortcut");
          break;
        case 0x43:
          handled = invoke_builder_action("ACTION_INSERT_CONTAINER", "shortcut");
          break;
        case 0x4C:
          handled = invoke_builder_action("ACTION_INSERT_LEAF", "shortcut");
          break;
        case 0x53:
          handled = invoke_builder_action("ACTION_SAVE", "shortcut");
          break;
        case 0x4F:
          handled = invoke_builder_action("ACTION_LOAD", "shortcut");
          break;
        case 0x4E:
          handled = invoke_builder_action("ACTION_NEW", "shortcut");
          break;
        default:
          break;
      }
    }

    if (!handled) {
      return false;
    }

    const bool keyboard_multi_selection_workflow_op =
      ctrl_down &&
      (key == 0x26 || key == 0x28 || key == 0x41 || key == 0x52 || key == 0x1B);
    if (!keyboard_multi_selection_workflow_op) {
      binding_.remap_selection_or_fail();
      binding_.sync_focus_with_selection_or_fail();
    }
    binding_.refresh_inspector_or_fail();
    binding_.refresh_preview_or_fail();
    binding_.check_cross_surface_sync();
    return true;
  }

  bool handle_builder_shortcut_key(std::uint32_t key, bool down, bool repeat) const {
    return handle_builder_shortcut_key_with_modifiers(
      key,
      down,
      repeat,
      binding_.ctrl_down_active(),
      binding_.shift_down_active());
  }

 private:
  bool is_builder_shortcut_scope_active() const {
    binding_.shortcut_scope_rules_defined = true;
    if (binding_.focused_text_input_active()) {
      return false;
    }
    return !binding_.builder_doc.nodes.empty() &&
      !binding_.selected_builder_node_id.empty() &&
      binding_.node_exists(binding_.selected_builder_node_id);
  }

  bool perform_action(const std::string& action_id) const {
    if (action_id == "ACTION_INSERT_CONTAINER") {
      return binding_.perform_insert_container_action();
    }
    if (action_id == "ACTION_INSERT_LEAF") {
      return binding_.perform_insert_leaf_action();
    }
    if (action_id == "ACTION_DELETE_CURRENT") {
      return binding_.perform_delete_current_action();
    }
    if (action_id == "ACTION_UNDO") {
      return binding_.perform_undo_action();
    }
    if (action_id == "ACTION_REDO") {
      return binding_.perform_redo_action();
    }
    if (action_id == "ACTION_SAVE") {
      return binding_.perform_save_action();
    }
    if (action_id == "ACTION_LOAD") {
      return binding_.perform_load_action(false);
    }
    if (action_id == "ACTION_LOAD_FORCE_DISCARD") {
      return binding_.perform_load_action(true);
    }
    if (action_id == "ACTION_NEW") {
      return binding_.perform_new_action(false);
    }
    if (action_id == "ACTION_NEW_FORCE_DISCARD") {
      return binding_.perform_new_action(true);
    }
    if (action_id == "ACTION_EXPORT") {
      return false;
    }
    return false;
  }

  ActionShortcutRoutingLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_ACTION_SHORTCUT_ROUTING_LOGIC(logic_object) \
  auto evaluate_builder_action_eligibility = [&](const std::string& action_id, std::string& blocked_reason_out) -> bool { \
    return (logic_object).evaluate_builder_action_eligibility(action_id, blocked_reason_out); \
  }; \
  auto invoke_builder_action = [&](const std::string& action_id, const char* invocation_source) -> bool { \
    return (logic_object).invoke_builder_action(action_id, invocation_source); \
  }; \
  auto handle_builder_shortcut_key_with_modifiers = [&](std::uint32_t key, bool down, bool repeat, bool ctrl_down, bool shift_down) -> bool { \
    return (logic_object).handle_builder_shortcut_key_with_modifiers(key, down, repeat, ctrl_down, shift_down); \
  }; \
  auto handle_builder_shortcut_key = [&](std::uint32_t key, bool down, bool repeat) -> bool { \
    return (logic_object).handle_builder_shortcut_key(key, down, repeat); \
  };
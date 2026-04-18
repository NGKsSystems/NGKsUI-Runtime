#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "builder_document.hpp"
#include "button.hpp"
#include "horizontal_layout.hpp"
#include "input_box.hpp"
#include "label.hpp"
#include "vertical_layout.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct StructureInspectorSurfaceLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::string& focused_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  std::string& builder_projection_filter_query;
  bool& builder_debug_mode;
  std::string& last_action_feedback;
  std::string& tree_visual_feedback_node_id;
  std::string& inspector_edit_binding_node_id;
  std::string& inspector_edit_loaded_text;
  std::string& inspector_edit_loaded_min_width;
  std::string& inspector_edit_loaded_min_height;
  std::string& last_preview_export_parity_status_code;
  std::string& last_preview_export_parity_reason;
  std::string& last_inspector_edit_status_code;
  std::string& last_inspector_edit_reason;
  std::string& last_bulk_delete_status_code;
  std::string& last_bulk_delete_reason;
  std::string& last_bulk_move_reparent_status_code;
  std::string& last_bulk_move_reparent_reason;
  std::string& last_bulk_property_edit_status_code;
  std::string& last_bulk_property_edit_reason;
  ngk::ui::VerticalLayout& builder_tree_visual_rows;
  ngk::ui::Label& builder_tree_surface_label;
  std::array<ngk::ui::Button, 128>& builder_tree_row_buttons;
  std::array<std::string, 128>& tree_visual_row_node_ids;
  ngk::ui::Label& builder_inspector_selection_label;
  ngk::ui::Label& builder_add_child_target_label;
  ngk::ui::Label& builder_inspector_edit_hint_label;
  ngk::ui::InputBox& builder_inspector_text_input;
  ngk::ui::Label& builder_inspector_layout_min_width_label;
  ngk::ui::InputBox& builder_inspector_layout_min_width_input;
  ngk::ui::Label& builder_inspector_layout_min_height_label;
  ngk::ui::InputBox& builder_inspector_layout_min_height_input;
  ngk::ui::Label& builder_inspector_structure_controls_label;
  ngk::ui::HorizontalLayout& builder_inspector_structure_controls_row;
  ngk::ui::Button& builder_inspector_add_child_button;
  ngk::ui::Button& builder_inspector_delete_button;
  ngk::ui::Button& builder_inspector_move_up_button;
  ngk::ui::Button& builder_inspector_move_down_button;
  ngk::ui::Button& builder_inspector_apply_button;
  ngk::ui::Label& builder_inspector_non_editable_label;
  ngk::ui::Label& builder_inspector_label;
  std::function<void(ngk::ui::Label&, int)> sync_label_preferred_height;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool(const std::string&)> is_node_in_multi_selection;
  std::function<bool(ngk::ui::builder::BuilderWidgetType)> is_container_widget_type;
  std::function<bool(const ngk::ui::builder::BuilderNode&, const std::string&)> builder_node_matches_projection_query;
  std::function<BulkTextSuffixSelectionCompatibility()> compute_bulk_text_suffix_selection_compatibility;
  std::function<void(std::ostringstream&)> append_compact_bulk_action_surface;
  std::function<void()> refresh_top_action_surface_from_builder_state;
  std::function<void()> refresh_action_button_visual_state_from_builder_truth;
  std::function<void()> reconcile_tree_viewport_to_current_state;
};

class StructureInspectorSurfaceLogic {
 public:
  explicit StructureInspectorSurfaceLogic(StructureInspectorSurfaceLogicBinding& binding) : binding_(binding) {}

  std::string humanize_widget_type(ngk::ui::builder::BuilderWidgetType widget_type) const {
    const std::string raw = std::string(ngk::ui::builder::to_string(widget_type));
    if (raw == "vertical_layout") {
      return "Vertical layout";
    }
    if (raw == "horizontal_layout") {
      return "Horizontal row";
    }
    if (raw == "content_panel") {
      return "Panel";
    }
    if (raw == "scroll_container") {
      return "Scrollable area";
    }
    if (raw == "toolbar_container") {
      return "Toolbar";
    }
    if (raw == "sidebar_container") {
      return "Sidebar";
    }
    if (raw == "status_bar_container") {
      return "Status bar";
    }
    if (raw == "section_header") {
      return "Section title";
    }
    if (raw == "input_box") {
      return "Input field";
    }
    if (raw == "button") {
      return "Button";
    }
    if (raw == "label") {
      return "Label";
    }
    return raw;
  }

  std::string build_tree_surface_text() const {
    binding_.sync_multi_selection_with_primary();

    std::ostringstream oss;
    oss << "TREE REGION (Hierarchy / Selection)\n";
    std::string selected_type_name = "none";
    if (!binding_.selected_builder_node_id.empty()) {
      if (auto* selected_node = binding_.find_node_by_id(binding_.selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }
    oss << "SELECTED_ID: " << (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id) << "\n";
    oss << "SELECTED_TYPE: " << selected_type_name << "\n";
    oss << "focus=" << (binding_.focused_builder_node_id.empty() ? std::string("none") : binding_.focused_builder_node_id) << "\n";
    oss << "MULTI_SELECTION_COUNT: " << binding_.multi_selected_node_ids.size() << "\n";
    oss << "PRIMARY_SELECTION_ID: "
        << (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id) << "\n";
    if (binding_.multi_selected_node_ids.size() > 1) {
      oss << "SECONDARY_SELECTION_ORDER: ";
      for (std::size_t idx = 1; idx < binding_.multi_selected_node_ids.size(); ++idx) {
        if (idx > 1) {
          oss << ",";
        }
        oss << binding_.multi_selected_node_ids[idx];
      }
      oss << "\n";
    }

    if (binding_.builder_doc.nodes.empty() || binding_.builder_doc.root_node_id.empty() || !binding_.node_exists(binding_.builder_doc.root_node_id)) {
      oss << "(empty document)";
      return oss.str();
    }

    std::function<void(const std::string&, int)> append_node = [&](const std::string& node_id, int depth) {
      auto* node = binding_.find_node_by_id(node_id);
      if (!node) {
        return;
      }

      const bool is_selected = (node_id == binding_.selected_builder_node_id);
      const bool is_focused = (node_id == binding_.focused_builder_node_id);
      const bool is_secondary = binding_.is_node_in_multi_selection(node_id) && !is_selected;
      oss << std::string(static_cast<std::size_t>(depth) * 2U, ' ')
          << (is_selected ? "[SELECTED] " : "- ")
          << ngk::ui::builder::to_string(node->widget_type)
          << " | " << node->node_id;
      if (!node->text.empty()) {
        oss << " | \"" << node->text << "\"";
      }
      if (is_selected) {
        oss << " [PRIMARY]";
      }
      if (is_secondary) {
        oss << " [MULTI_SECONDARY]";
      }
      if (is_focused) {
        oss << " [FOCUS]";
      }
      oss << "\n";

      for (const auto& child_id : node->child_ids) {
        append_node(child_id, depth + 1);
      }
    };

    append_node(binding_.builder_doc.root_node_id, 0);
    return oss.str();
  }

  void refresh_tree_surface_label() const {
    binding_.builder_tree_surface_label.set_visible(binding_.builder_debug_mode);
    binding_.builder_tree_visual_rows.set_visible(!binding_.builder_debug_mode);
    binding_.builder_tree_surface_label.set_text(build_tree_surface_text());
    binding_.sync_label_preferred_height(binding_.builder_tree_surface_label, 20);

    for (std::size_t idx = 0; idx < binding_.builder_tree_row_buttons.size(); ++idx) {
      binding_.tree_visual_row_node_ids[idx].clear();
      binding_.builder_tree_row_buttons[idx].set_visible(false);
      binding_.builder_tree_row_buttons[idx].set_default_action(false);
      binding_.builder_tree_row_buttons[idx].set_enabled(false);
    }

    std::unordered_map<std::string, bool> visible_projection_cache{};
    std::function<bool(const std::string&)> node_visible_under_projection =
      [&](const std::string& node_id) -> bool {
        auto it = visible_projection_cache.find(node_id);
        if (it != visible_projection_cache.end()) {
          return it->second;
        }
        auto* node = binding_.find_node_by_id(node_id);
        if (!node) {
          visible_projection_cache[node_id] = false;
          return false;
        }
        bool visible = binding_.builder_node_matches_projection_query(*node, binding_.builder_projection_filter_query);
        if (!visible) {
          for (const auto& child_id : node->child_ids) {
            if (node_visible_under_projection(child_id)) {
              visible = true;
              break;
            }
          }
        }
        visible_projection_cache[node_id] = visible;
        return visible;
      };

    std::size_t row_count = 0;
    std::function<void(const std::string&, int)> append_visual_tree = [&](const std::string& node_id, int depth) {
      if (row_count >= binding_.builder_tree_row_buttons.size()) {
        return;
      }

      auto* node = binding_.find_node_by_id(node_id);
      if (!node) {
        return;
      }
      if (!node_visible_under_projection(node_id)) {
        return;
      }

      auto& row = binding_.builder_tree_row_buttons[row_count];
      binding_.tree_visual_row_node_ids[row_count] = node_id;

      std::string indent(static_cast<std::size_t>(std::max(0, depth)) * 4U, ' ');
      const bool is_container = binding_.is_container_widget_type(node->widget_type);
      const bool is_selected = (node_id == binding_.selected_builder_node_id);
      const bool is_hovered = row.visual_state() == ngk::ui::ButtonVisualState::Hover;
      const bool is_feedback_target = !binding_.tree_visual_feedback_node_id.empty() && binding_.tree_visual_feedback_node_id == node_id;
      std::string row_text;
      if (is_container) {
        row_text = indent + "CONTAINER (" + std::to_string(node->child_ids.size()) +
          (node->child_ids.size() == 1 ? std::string(" item)") : std::string(" items)"));
      } else if (node->widget_type == ngk::ui::builder::BuilderWidgetType::Label) {
        row_text = indent + (node->text.empty() ? std::string("Text") : node->text);
      } else if (!node->text.empty()) {
        row_text = indent + node->text;
      } else {
        row_text = indent + humanize_widget_type(node->widget_type);
      }
      if (is_selected) {
        row_text += "  Selected";
      }

      row.set_text(row_text);
      row.set_enabled(true);
      row.set_visible(true);
      row.set_focused(is_selected);
      row.set_default_action(node_id == binding_.selected_builder_node_id);
      row.set_preferred_size(0, is_container ? 34 : 28);

      const float depth_tint = std::min(0.05f * static_cast<float>(std::max(0, depth)), 0.16f);
      if (is_selected) {
        row.set_background(0.18f + depth_tint, 0.37f + depth_tint, 0.62f + depth_tint, 1.0f);
      } else if (is_feedback_target) {
        row.set_background(0.36f + depth_tint, 0.31f + depth_tint, 0.18f + depth_tint, 1.0f);
      } else if (is_container) {
        row.set_background(0.13f + depth_tint, 0.18f + depth_tint, 0.24f + depth_tint, 1.0f);
      } else if (is_hovered) {
        row.set_background(0.22f + depth_tint, 0.25f + depth_tint, 0.31f + depth_tint, 1.0f);
      } else {
        row.set_background(0.16f + depth_tint, 0.19f + depth_tint, 0.23f + depth_tint, 1.0f);
      }
      row_count += 1;

      for (const auto& child_id : node->child_ids) {
        append_visual_tree(child_id, depth + 1);
      }
    };

    if (!binding_.builder_doc.root_node_id.empty() && binding_.node_exists(binding_.builder_doc.root_node_id)) {
      append_visual_tree(binding_.builder_doc.root_node_id, 0);
    }

    binding_.reconcile_tree_viewport_to_current_state();
  }

  void refresh_inspector_surface_label() const {
    binding_.sync_multi_selection_with_primary();
    binding_.builder_inspector_label.set_visible(binding_.builder_debug_mode);

    std::ostringstream oss;
    oss << "INSPECTOR REGION (Guided Editing Surface)\n";
    oss << "[DEBUG MODE: " << (binding_.builder_debug_mode ? "ON" : "OFF") << "]\n";
    oss << binding_.last_action_feedback << "\n";
    std::string selected_type_name = "none";
    if (!binding_.selected_builder_node_id.empty()) {
      if (auto* selected_node = binding_.find_node_by_id(binding_.selected_builder_node_id)) {
        selected_type_name = humanize_widget_type(selected_node->widget_type);
      }
    }
    binding_.builder_inspector_selection_label.set_text(
      binding_.selected_builder_node_id.empty()
        ? std::string("Editing: Nothing selected")
        : (std::string("Editing: ") + selected_type_name));
    binding_.sync_label_preferred_height(binding_.builder_inspector_selection_label, 20);
    oss << "Selected Node: "
        << (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id)
        << " (" << selected_type_name << ")\n";

    if (binding_.selected_builder_node_id.empty() || !binding_.node_exists(binding_.selected_builder_node_id)) {
      binding_.inspector_edit_binding_node_id.clear();
      binding_.inspector_edit_loaded_text.clear();
      binding_.inspector_edit_loaded_min_width.clear();
      binding_.inspector_edit_loaded_min_height.clear();
      binding_.builder_inspector_edit_hint_label.set_text(
        "Click NEW DOC to start, then select an item from Structure or Live Preview.");
      binding_.sync_label_preferred_height(binding_.builder_inspector_edit_hint_label, 20);
      binding_.builder_inspector_text_input.set_visible(false);
      binding_.builder_inspector_text_input.set_focusable(false);
      binding_.builder_inspector_layout_min_width_label.set_visible(false);
      binding_.builder_inspector_layout_min_width_input.set_visible(false);
      binding_.builder_inspector_layout_min_width_input.set_focusable(false);
      binding_.builder_inspector_layout_min_height_label.set_visible(false);
      binding_.builder_inspector_layout_min_height_input.set_visible(false);
      binding_.builder_inspector_layout_min_height_input.set_focusable(false);
      binding_.builder_inspector_structure_controls_label.set_visible(false);
      binding_.builder_inspector_structure_controls_row.set_visible(false);
      binding_.builder_inspector_apply_button.set_visible(false);
      binding_.builder_inspector_apply_button.set_enabled(false);
      binding_.builder_inspector_apply_button.set_default_action(false);
      binding_.builder_inspector_apply_button.set_text("Apply Changes");
      binding_.builder_inspector_non_editable_label.set_visible(false);
      oss << "Edit Target: none\n";
      oss << "Click NEW DOC to start.\n";
      oss << "Then add a container, then add items inside it.\n";
      oss << "Select a node in Tree or Preview to edit.";

      if (binding_.builder_debug_mode) {
        oss << "\n\n[SELECTION_SUMMARY]\n";
        oss << "SELECTED_ID: none\n";
        oss << "SELECTED_TYPE: none EDIT_TARGET_ID: none MULTI_SELECTION_MODE: "
            << (binding_.multi_selected_node_ids.size() > 1 ? "active" : "inactive")
            << " MULTI_SELECTION_COUNT: " << binding_.multi_selected_node_ids.size() << "\n";
        oss << "\n[ACTION_SURFACE]\n";
        binding_.append_compact_bulk_action_surface(oss);
        oss << "\n[PARITY]\n";
        oss << "PREVIEW_EXPORT_PARITY: " << binding_.last_preview_export_parity_status_code << "\n";
        oss << "\n[INTERNAL_FLAGS]\n";
        oss << "selected=none focused=" << (binding_.focused_builder_node_id.empty() ? std::string("none") : binding_.focused_builder_node_id) << "\n";
        oss << "binding=cleared\n";
      }
      binding_.builder_inspector_label.set_text(oss.str());
      binding_.sync_label_preferred_height(binding_.builder_inspector_label, 20);
      return;
    }

    auto* node = binding_.find_node_by_id(binding_.selected_builder_node_id);
    if (!node) {
      binding_.inspector_edit_binding_node_id.clear();
      binding_.inspector_edit_loaded_text.clear();
      binding_.inspector_edit_loaded_min_width.clear();
      binding_.inspector_edit_loaded_min_height.clear();
      binding_.builder_inspector_edit_hint_label.set_text(
        "Selection changed before the editor loaded. Select an item again.");
      binding_.sync_label_preferred_height(binding_.builder_inspector_edit_hint_label, 20);
      binding_.builder_inspector_text_input.set_visible(false);
      binding_.builder_inspector_text_input.set_focusable(false);
      binding_.builder_inspector_layout_min_width_label.set_visible(false);
      binding_.builder_inspector_layout_min_width_input.set_visible(false);
      binding_.builder_inspector_layout_min_width_input.set_focusable(false);
      binding_.builder_inspector_layout_min_height_label.set_visible(false);
      binding_.builder_inspector_layout_min_height_input.set_visible(false);
      binding_.builder_inspector_layout_min_height_input.set_focusable(false);
      binding_.builder_inspector_structure_controls_label.set_visible(false);
      binding_.builder_inspector_structure_controls_row.set_visible(false);
      binding_.builder_inspector_apply_button.set_visible(false);
      binding_.builder_inspector_apply_button.set_enabled(false);
      binding_.builder_inspector_apply_button.set_default_action(false);
      binding_.builder_inspector_non_editable_label.set_visible(false);
      oss << "Edit Target: stale\n";
      oss << "Hint: Selection was remapped.";
      binding_.builder_inspector_label.set_text(oss.str());
      binding_.sync_label_preferred_height(binding_.builder_inspector_label, 20);
      return;
    }

    const auto widget_type_name = humanize_widget_type(node->widget_type);
    const auto container_type_name = std::string(ngk::ui::builder::to_string(node->container_type));
    const bool text_editable =
      node->widget_type == ngk::ui::builder::BuilderWidgetType::Label ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::Button ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::InputBox ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::SectionHeader;
    const bool shows_layout_group =
      node->widget_type == ngk::ui::builder::BuilderWidgetType::VerticalLayout ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::HorizontalLayout ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::ScrollContainer ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::ToolbarContainer ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::SidebarContainer ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::ContentPanel ||
      node->widget_type == ngk::ui::builder::BuilderWidgetType::StatusBarContainer;
    const bool container_selected = ngk::ui::builder::widget_allows_children(node->widget_type);

    binding_.builder_inspector_structure_controls_label.set_visible(true);
    binding_.builder_inspector_structure_controls_row.set_visible(true);
    binding_.builder_inspector_add_child_button.set_enabled(container_selected);
    binding_.builder_inspector_add_child_button.set_background(
      container_selected ? 0.16f : 0.11f,
      container_selected ? 0.20f : 0.12f,
      container_selected ? 0.28f : 0.13f,
      1.0f);
    binding_.builder_inspector_structure_controls_label.set_text(
      container_selected
        ? "Structure Controls"
        : "Structure Controls - Only containers can have children");
    binding_.builder_inspector_delete_button.set_enabled(binding_.selected_builder_node_id != binding_.builder_doc.root_node_id);
    binding_.builder_inspector_move_up_button.set_enabled(binding_.selected_builder_node_id != binding_.builder_doc.root_node_id);
    binding_.builder_inspector_move_down_button.set_enabled(binding_.selected_builder_node_id != binding_.builder_doc.root_node_id);

    oss << "Edit Target: " << node->node_id << "\n";
    oss << "Item: " << widget_type_name << "\n";
    oss << "Structure Controls: "
        << (container_selected ? "Add Child" : "Add Child disabled")
        << ", Delete, Move Up, Move Down\n";

    const std::string current_min_width = std::to_string(node->layout.min_width);
    const std::string current_min_height = std::to_string(node->layout.min_height);
    if (binding_.inspector_edit_binding_node_id != node->node_id ||
        binding_.builder_inspector_layout_min_width_input.value() == binding_.inspector_edit_loaded_min_width ||
        !binding_.builder_inspector_layout_min_width_input.focused()) {
      binding_.builder_inspector_layout_min_width_input.set_value(current_min_width);
      binding_.inspector_edit_loaded_min_width = current_min_width;
    }
    if (binding_.inspector_edit_binding_node_id != node->node_id ||
        binding_.builder_inspector_layout_min_height_input.value() == binding_.inspector_edit_loaded_min_height ||
        !binding_.builder_inspector_layout_min_height_input.focused()) {
      binding_.builder_inspector_layout_min_height_input.set_value(current_min_height);
      binding_.inspector_edit_loaded_min_height = current_min_height;
    }
    binding_.builder_inspector_layout_min_width_label.set_visible(true);
    binding_.builder_inspector_layout_min_width_input.set_visible(true);
    binding_.builder_inspector_layout_min_width_input.set_focusable(true);
    binding_.builder_inspector_layout_min_height_label.set_visible(true);
    binding_.builder_inspector_layout_min_height_input.set_visible(true);
    binding_.builder_inspector_layout_min_height_input.set_focusable(true);
    binding_.sync_label_preferred_height(binding_.builder_inspector_layout_min_width_label, 18);
    binding_.sync_label_preferred_height(binding_.builder_inspector_layout_min_height_label, 18);

    if (text_editable) {
      if (binding_.inspector_edit_binding_node_id != node->node_id ||
          binding_.builder_inspector_text_input.value() == binding_.inspector_edit_loaded_text ||
          !binding_.builder_inspector_text_input.focused()) {
        binding_.builder_inspector_text_input.set_value(node->text);
        binding_.inspector_edit_loaded_text = node->text;
      }
      binding_.builder_inspector_edit_hint_label.set_text(
        "You can edit Text, Width, and Height here. Apply Filter at the top only filters files.");
      binding_.sync_label_preferred_height(binding_.builder_inspector_edit_hint_label, 20);
      binding_.builder_inspector_text_input.set_visible(true);
      binding_.builder_inspector_text_input.set_focusable(true);
      binding_.builder_inspector_apply_button.set_visible(true);
      binding_.builder_inspector_apply_button.set_enabled(true);
      binding_.builder_inspector_apply_button.set_default_action(true);
      binding_.builder_inspector_apply_button.set_text("Apply Changes");
      binding_.builder_inspector_non_editable_label.set_visible(false);
      oss << "Label: \"" << (node->text.empty() ? std::string("<no-text>") : node->text) << "\"\n";
      oss << "Text Property: editable\n";
    } else {
      binding_.inspector_edit_loaded_text.clear();
      binding_.builder_inspector_edit_hint_label.set_text(
        "You can edit Width and Height for this item. This item has no text.");
      binding_.sync_label_preferred_height(binding_.builder_inspector_edit_hint_label, 20);
      binding_.builder_inspector_text_input.set_visible(false);
      binding_.builder_inspector_text_input.set_focusable(false);
      binding_.builder_inspector_apply_button.set_visible(true);
      binding_.builder_inspector_apply_button.set_enabled(true);
      binding_.builder_inspector_apply_button.set_default_action(true);
      binding_.builder_inspector_apply_button.set_text("Apply Changes");
      binding_.builder_inspector_non_editable_label.set_text(
        "This item has no text.");
      binding_.builder_inspector_non_editable_label.set_visible(true);
      binding_.sync_label_preferred_height(binding_.builder_inspector_non_editable_label, 20);
      oss << "Text Property: not editable for this node type\n";
    }

    binding_.inspector_edit_binding_node_id = node->node_id;
    oss << "Width: " << node->layout.min_width << "\n";
    oss << "Height: " << node->layout.min_height << "\n";

    if (shows_layout_group) {
      oss << "Layout Children: " << node->child_ids.size() << "\n";
    }

    if (binding_.builder_debug_mode) {
      const auto bulk_text_state = binding_.compute_bulk_text_suffix_selection_compatibility();
      oss << "\n[SELECTION_SUMMARY]\n";
      oss << "SELECTED_ID: " << (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id) << "\n";
      oss << "SELECTED_TYPE: " << selected_type_name
          << " EDIT_TARGET_ID: " << (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id)
          << " MULTI_SELECTION_MODE: " << (binding_.multi_selected_node_ids.size() > 1 ? "active" : "inactive")
          << " MULTI_SELECTION_COUNT: " << binding_.multi_selected_node_ids.size() << "\n";

      oss << "\n[ACTION_SURFACE]\n";
      oss << "BULK_TEXT_SUFFIX_COMPATIBILITY: " << bulk_text_state.mode;
      if (!bulk_text_state.widget_type.empty()) {
        oss << " widget_type=" << bulk_text_state.widget_type;
      }
      if (!bulk_text_state.reason.empty() && bulk_text_state.reason != "none") {
        oss << " reason=" << bulk_text_state.reason;
      }
      oss << "\n";
      oss << "BULK_TEXT_SUFFIX_ELIGIBLE: " << (bulk_text_state.eligible ? "YES" : "NO") << "\n";
      binding_.append_compact_bulk_action_surface(oss);

      oss << "\n[PARITY]\n";
      oss << "PREVIEW_EXPORT_PARITY: " << binding_.last_preview_export_parity_status_code;
      if (!binding_.last_preview_export_parity_reason.empty() && binding_.last_preview_export_parity_reason != "none") {
        oss << " reason=" << binding_.last_preview_export_parity_reason;
      }
      oss << "\n";

      oss << "\n[RECENT_RESULTS]\n";
      oss << "EDIT_RESULT: " << binding_.last_inspector_edit_status_code;
      if (!binding_.last_inspector_edit_reason.empty() && binding_.last_inspector_edit_reason != "none") {
        oss << " [" << binding_.last_inspector_edit_reason << "]";
      }
      oss << " | BULK_DELETE_RESULT: " << binding_.last_bulk_delete_status_code;
      if (!binding_.last_bulk_delete_reason.empty() && binding_.last_bulk_delete_reason != "none") {
        oss << " [" << binding_.last_bulk_delete_reason << "]";
      }
      oss << "\n";
      oss << "BULK_MOVE_REPARENT_RESULT: " << binding_.last_bulk_move_reparent_status_code;
      if (!binding_.last_bulk_move_reparent_reason.empty() && binding_.last_bulk_move_reparent_reason != "none") {
        oss << " [" << binding_.last_bulk_move_reparent_reason << "]";
      }
      oss << " | BULK_PROPERTY_EDIT_RESULT: " << binding_.last_bulk_property_edit_status_code;
      if (!binding_.last_bulk_property_edit_reason.empty() && binding_.last_bulk_property_edit_reason != "none") {
        oss << " [" << binding_.last_bulk_property_edit_reason << "]";
      }
      oss << "\n";
      oss << "\n[INTERNAL_FLAGS]\n";
      oss << "  selected=" << ((binding_.selected_builder_node_id == node->node_id) ? "true" : "false")
          << " focused=" << ((binding_.focused_builder_node_id == node->node_id) ? "true" : "false")
          << " multi_selection_count=" << binding_.multi_selected_node_ids.size() << "\n";
      oss << "  binding=selection_bound\n";
      oss << "  container_type=" << container_type_name;
      if (shows_layout_group) {
        oss << " child_ids=";
        if (node->child_ids.empty()) {
          oss << "<none>";
        } else {
          for (std::size_t idx = 0; idx < node->child_ids.size(); ++idx) {
            if (idx > 0) {
              oss << ",";
            }
            oss << node->child_ids[idx];
          }
        }
      }
      oss << "\n";
    }

    binding_.builder_inspector_label.set_text(oss.str());
    binding_.sync_label_preferred_height(binding_.builder_inspector_label, 20);
    binding_.refresh_top_action_surface_from_builder_state();
    binding_.refresh_action_button_visual_state_from_builder_truth();
  }

  void update_add_child_target_display() const {
    if (binding_.selected_builder_node_id.empty()) {
      binding_.builder_add_child_target_label.set_text("Add Child Target: None");
      return;
    }

    auto* selected_node = binding_.find_node_by_id(binding_.selected_builder_node_id);
    if (!selected_node) {
      binding_.builder_add_child_target_label.set_text("Add Child Target: Stale");
      return;
    }

    const bool is_container = ngk::ui::builder::widget_allows_children(selected_node->widget_type);
    const std::string type_name = humanize_widget_type(selected_node->widget_type);
    const std::string label_text = selected_node->text.empty() ? "(no label)" : selected_node->text;

    std::string target_text = is_container
      ? ("Add Child Target: CONTAINER " + type_name + " \"" + label_text + "\"")
      : ("Add Child Target: LABEL " + type_name + " (cannot add children to this)");

    binding_.builder_add_child_target_label.set_text(target_text);
    binding_.sync_label_preferred_height(binding_.builder_add_child_target_label, 18);
  }

 private:
  StructureInspectorSurfaceLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_STRUCTURE_INSPECTOR_SURFACE_LOGIC(logic_object) \
  auto humanize_widget_type = [&](ngk::ui::builder::BuilderWidgetType widget_type) -> std::string { \
    return (logic_object).humanize_widget_type(widget_type); \
  }; \
  auto build_tree_surface_text = [&]() -> std::string { \
    return (logic_object).build_tree_surface_text(); \
  }; \
  auto refresh_tree_surface_label = [&]() { \
    (logic_object).refresh_tree_surface_label(); \
  }; \
  auto refresh_inspector_surface_label = [&]() { \
    (logic_object).refresh_inspector_surface_label(); \
  }; \
  auto update_add_child_target_display = [&]() { \
    (logic_object).update_add_child_target_display(); \
  };
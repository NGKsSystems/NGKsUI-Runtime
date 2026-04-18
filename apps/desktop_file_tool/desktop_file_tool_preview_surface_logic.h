#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <functional>
#include <sstream>
#include <string>
#include <unordered_map>

#include "builder_document.hpp"
#include "button.hpp"
#include "horizontal_layout.hpp"
#include "input_box.hpp"
#include "label.hpp"
#include "vertical_layout.hpp"
#include "desktop_file_tool_diagnostics.h"

namespace desktop_file_tool {

struct PreviewSurfaceLogicBinding {
  ngk::ui::builder::BuilderDocument& builder_doc;
  std::string& selected_builder_node_id;
  std::vector<std::string>& multi_selected_node_ids;
  bool& builder_debug_mode;
  std::string& last_action_feedback;
  std::string& preview_visual_feedback_message;
  std::string& preview_visual_feedback_node_id;
  std::string& preview_snapshot;
  bool& inline_edit_active;
  std::string& inline_edit_node_id;
  std::string& inline_edit_buffer;
  std::string& preview_inline_loaded_text;
  std::string& last_preview_export_parity_status_code;
  std::string& last_preview_export_parity_reason;
  std::string& last_preview_click_select_status_code;
  std::string& last_preview_click_select_reason;
  std::string& last_preview_inline_action_commit_status_code;
  std::string& last_preview_inline_action_commit_reason;
  std::string& last_bulk_delete_status_code;
  std::string& last_bulk_delete_reason;
  std::string& last_bulk_move_reparent_status_code;
  std::string& last_bulk_move_reparent_reason;
  std::string& last_bulk_property_edit_status_code;
  std::string& last_bulk_property_edit_reason;
  std::string& builder_projection_filter_query;
  const char* preview_export_parity_scope;
  ngk::ui::VerticalLayout& builder_preview_visual_rows;
  ngk::ui::Label& builder_preview_interaction_hint_label;
  ngk::ui::InputBox& builder_preview_inline_text_input;
  ngk::ui::HorizontalLayout& builder_preview_inline_actions_row;
  ngk::ui::Label& builder_preview_label;
  std::array<ngk::ui::Button, 128>& builder_preview_row_buttons;
  std::array<std::string, 128>& preview_visual_row_node_ids;
  std::array<int, 128>& preview_visual_row_depths;
  std::array<bool, 128>& preview_visual_row_is_container;
  std::function<void(ngk::ui::Label&, int)> sync_label_preferred_height;
  std::function<void()> sync_multi_selection_with_primary;
  std::function<ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  std::function<bool(const std::string&)> node_exists;
  std::function<bool(ngk::ui::builder::BuilderWidgetType)> is_container_widget_type;
  std::function<bool(const ngk::ui::builder::BuilderNode&, const std::string&)> builder_node_matches_projection_query;
  std::function<std::string(ngk::ui::builder::BuilderWidgetType)> humanize_widget_type;
  std::function<BulkTextSuffixSelectionCompatibility()> compute_bulk_text_suffix_selection_compatibility;
  std::function<void(std::ostringstream&)> append_compact_bulk_action_surface;
  std::function<std::string(const ngk::ui::builder::BuilderNode&)> build_preview_inline_action_affordance_text;
  std::function<std::string()> build_preview_runtime_outline;
  std::function<void()> reconcile_preview_viewport_to_current_state;
  std::function<void()> refresh_top_action_surface_from_builder_state;
  std::function<void()> refresh_action_button_visual_state_from_builder_truth;
};

class PreviewSurfaceLogic {
 public:
  explicit PreviewSurfaceLogic(PreviewSurfaceLogicBinding& binding) : binding_(binding) {}

  void refresh_preview_surface_label() const {
    binding_.sync_multi_selection_with_primary();

    binding_.builder_preview_label.set_visible(binding_.builder_debug_mode);
    binding_.builder_preview_visual_rows.set_visible(!binding_.builder_debug_mode);

    std::ostringstream oss;
    oss << "PREVIEW REGION (Readable Runtime)\n";
    oss << "[DEBUG MODE: " << (binding_.builder_debug_mode ? "ON" : "OFF") << "]\n";
    oss << binding_.last_action_feedback << "\n";
    std::string selected_type_name = "none";
    if (!binding_.selected_builder_node_id.empty()) {
      if (auto* selected_node = binding_.find_node_by_id(binding_.selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }
    oss << "Selection: " << (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id)
        << " (" << selected_type_name << ")\n";
    oss << "Layout\n";

    if (binding_.selected_builder_node_id.empty() || !binding_.node_exists(binding_.selected_builder_node_id)) {
      binding_.builder_preview_interaction_hint_label.set_text(
        "Click NEW DOC to start. Select an item in Tree or Preview to edit.");
      binding_.builder_preview_inline_text_input.set_visible(false);
      binding_.builder_preview_inline_text_input.set_focusable(false);
      binding_.builder_preview_inline_actions_row.set_visible(false);
      oss << "No active node selected.\n";
      oss << "Hint: Click a TREE row or PREVIEW runtime entry.";
      binding_.preview_snapshot = "preview:selected=none";
      binding_.builder_preview_label.set_text(oss.str());
      binding_.sync_label_preferred_height(binding_.builder_preview_label, 20);
      return;
    }

    auto* selected = binding_.find_node_by_id(binding_.selected_builder_node_id);
    if (!selected) {
      binding_.builder_preview_interaction_hint_label.set_text("Selection became stale. Select another item.");
      binding_.builder_preview_inline_text_input.set_visible(false);
      binding_.builder_preview_inline_text_input.set_focusable(false);
      binding_.builder_preview_inline_actions_row.set_visible(false);
      oss << "Selected node became stale.";
      binding_.preview_snapshot = "preview:selected=stale";
      binding_.builder_preview_label.set_text(oss.str());
      binding_.sync_label_preferred_height(binding_.builder_preview_label, 20);
      return;
    }

    oss << "Active item: " << selected->node_id << "\n";
    oss << "Item: " << binding_.humanize_widget_type(selected->widget_type) << "\n";
    if (selected->text.empty()) {
      oss << "Label: \"<no-text>\"\n";
    } else {
      oss << "Label: \"" << selected->text << "\"\n";
    }
    oss << "Children: " << selected->child_ids.size() << "\n";

    std::string preview_hint_message;
    const bool preview_text_editable =
      selected->widget_type == ngk::ui::builder::BuilderWidgetType::Label;
    if (preview_text_editable) {
      preview_hint_message = "Click to select, then edit label text below and press Enter or Apply.";
      if (binding_.inline_edit_active && binding_.inline_edit_node_id == selected->node_id) {
        if (binding_.builder_preview_inline_text_input.value() == binding_.preview_inline_loaded_text ||
            !binding_.builder_preview_inline_text_input.focused()) {
          binding_.builder_preview_inline_text_input.set_value(binding_.inline_edit_buffer);
          binding_.preview_inline_loaded_text = binding_.inline_edit_buffer;
        }
        binding_.builder_preview_inline_text_input.set_visible(true);
        binding_.builder_preview_inline_text_input.set_focusable(true);
        binding_.builder_preview_inline_actions_row.set_visible(true);
      } else {
        binding_.builder_preview_inline_text_input.set_visible(false);
        binding_.builder_preview_inline_text_input.set_focusable(false);
        binding_.builder_preview_inline_actions_row.set_visible(false);
      }
    } else {
      preview_hint_message = "Click to select. Inline text editing is available for labels.";
      binding_.builder_preview_inline_text_input.set_visible(false);
      binding_.builder_preview_inline_text_input.set_focusable(false);
      binding_.builder_preview_inline_actions_row.set_visible(false);
    }

    if (ngk::ui::builder::widget_allows_children(selected->widget_type)) {
      preview_hint_message = "Container selected: child will appear in the highlighted insertion area.";
    }
    if (!binding_.preview_visual_feedback_message.empty()) {
      preview_hint_message = binding_.preview_visual_feedback_message;
    }
    binding_.builder_preview_interaction_hint_label.set_text(preview_hint_message);
    binding_.sync_label_preferred_height(binding_.builder_preview_interaction_hint_label, 18);

    if (binding_.builder_debug_mode) {
      const auto bulk_text_state = binding_.compute_bulk_text_suffix_selection_compatibility();
      oss << "\n[SELECTION_SUMMARY]\n";
      oss << "SELECTED_ID: " << (binding_.selected_builder_node_id.empty() ? std::string("none") : binding_.selected_builder_node_id) << "\n";
      oss << "SELECTED_TYPE: " << selected_type_name
          << " SELECTED_TARGET=ACTIVE_EDIT_NODE"
          << " selection_mode=" << (binding_.multi_selected_node_ids.size() > 1 ? "multi" : "single")
          << " multi_selection_count=" << binding_.multi_selected_node_ids.size();
      if (binding_.multi_selected_node_ids.size() > 1) {
        oss << " multi_secondary_ids=";
        for (std::size_t idx = 1; idx < binding_.multi_selected_node_ids.size(); ++idx) {
          if (idx > 1) {
            oss << ",";
          }
          oss << binding_.multi_selected_node_ids[idx];
        }
      }
      oss << "\n";

      oss << "\n[PARITY]\n";
      oss << "parity_scope=" << binding_.preview_export_parity_scope << " parity=" << binding_.last_preview_export_parity_status_code;
      if (!binding_.last_preview_export_parity_reason.empty() && binding_.last_preview_export_parity_reason != "none") {
        oss << " reason=" << binding_.last_preview_export_parity_reason;
      }
      oss << "\n";

      oss << "\n[ACTION_SURFACE]\n";
      oss << "multi_selection_compatibility=" << bulk_text_state.mode;
      if (!bulk_text_state.widget_type.empty()) {
        oss << " widget_type=" << bulk_text_state.widget_type;
      }
      if (!bulk_text_state.reason.empty() && bulk_text_state.reason != "none") {
        oss << " reason=" << bulk_text_state.reason;
      }
      oss << "\n";
      oss << "bulk_text_suffix_eligible=" << (bulk_text_state.eligible ? "YES" : "NO") << "\n";
      binding_.append_compact_bulk_action_surface(oss);

      oss << "\n[RECENT_RESULTS]\n";
      oss << "click_select=" << binding_.last_preview_click_select_status_code;
      if (!binding_.last_preview_click_select_reason.empty() && binding_.last_preview_click_select_reason != "none") {
        oss << " reason=" << binding_.last_preview_click_select_reason;
      }
      oss << " | inline_action_commit=" << binding_.last_preview_inline_action_commit_status_code;
      if (!binding_.last_preview_inline_action_commit_reason.empty() && binding_.last_preview_inline_action_commit_reason != "none") {
        oss << " reason=" << binding_.last_preview_inline_action_commit_reason;
      }
      oss << "\n";
      oss << "bulk_delete=" << binding_.last_bulk_delete_status_code;
      if (!binding_.last_bulk_delete_reason.empty() && binding_.last_bulk_delete_reason != "none") {
        oss << " reason=" << binding_.last_bulk_delete_reason;
      }
      oss << " | bulk_move_reparent=" << binding_.last_bulk_move_reparent_status_code;
      if (!binding_.last_bulk_move_reparent_reason.empty() && binding_.last_bulk_move_reparent_reason != "none") {
        oss << " reason=" << binding_.last_bulk_move_reparent_reason;
      }
      oss << " | bulk_property_edit=" << binding_.last_bulk_property_edit_status_code;
      if (!binding_.last_bulk_property_edit_reason.empty() && binding_.last_bulk_property_edit_reason != "none") {
        oss << " reason=" << binding_.last_bulk_property_edit_reason;
      }
      oss << "\n";
      oss << "root=" << (binding_.builder_doc.root_node_id.empty() ? std::string("none") : binding_.builder_doc.root_node_id)
          << " nodes=" << binding_.builder_doc.nodes.size() << "\n";
    }

    oss << binding_.build_preview_inline_action_affordance_text(*selected);
    oss << "runtime_outline:\n" << binding_.build_preview_runtime_outline();
    binding_.preview_snapshot = "preview:selected=" + selected->node_id +
      " type=" + std::string(ngk::ui::builder::to_string(selected->widget_type)) +
      " parity=" + binding_.last_preview_export_parity_status_code;
    binding_.builder_preview_label.set_text(oss.str());
    binding_.sync_label_preferred_height(binding_.builder_preview_label, 20);

    for (std::size_t idx = 0; idx < binding_.builder_preview_row_buttons.size(); ++idx) {
      binding_.preview_visual_row_node_ids[idx].clear();
      binding_.preview_visual_row_depths[idx] = 0;
      binding_.preview_visual_row_is_container[idx] = false;
      binding_.builder_preview_row_buttons[idx].set_visible(false);
      binding_.builder_preview_row_buttons[idx].set_default_action(false);
      binding_.builder_preview_row_buttons[idx].set_enabled(false);
      binding_.builder_preview_row_buttons[idx].set_focused(false);
      binding_.builder_preview_row_buttons[idx].set_background(0.16f, 0.18f, 0.22f, 1.0f);
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
    std::function<void(const std::string&, int)> append_preview_visual = [&](const std::string& node_id, int depth) {
      if (row_count >= binding_.builder_preview_row_buttons.size()) {
        return;
      }

      auto* node = binding_.find_node_by_id(node_id);
      if (!node) {
        return;
      }
      if (!node_visible_under_projection(node_id)) {
        return;
      }

      auto& row = binding_.builder_preview_row_buttons[row_count];
      binding_.preview_visual_row_node_ids[row_count] = node_id;
      binding_.preview_visual_row_depths[row_count] = depth;
      binding_.preview_visual_row_is_container[row_count] = binding_.is_container_widget_type(node->widget_type);

      const int layout_height = std::max(0, node->layout.min_height);
      const int layout_width = std::max(0, node->layout.min_width);
      const int width_units = std::clamp(layout_width / 80, 0, 8);
      const std::string width_pad(static_cast<std::size_t>(width_units), ' ');
      const std::string depth_indent(static_cast<std::size_t>(std::max(0, depth)) * 4U, ' ');

      std::string row_text;
      if (binding_.is_container_widget_type(node->widget_type)) {
        row_text = depth_indent + "CONTAINER (" + std::to_string(node->child_ids.size()) +
          (node->child_ids.size() == 1 ? std::string(" item)") : std::string(" items)"));
      } else if (node->widget_type == ngk::ui::builder::BuilderWidgetType::Label) {
        row_text = depth_indent + width_pad + (node->text.empty() ? std::string("Text") : node->text) + width_pad;
      } else if (!node->text.empty()) {
        row_text = depth_indent + width_pad + node->text + width_pad;
      } else {
        row_text = depth_indent + width_pad + binding_.humanize_widget_type(node->widget_type) + width_pad;
      }

      const bool is_selected = (node_id == binding_.selected_builder_node_id);
      const bool is_hovered = row.visual_state() == ngk::ui::ButtonVisualState::Hover;
      const bool is_feedback_target = !binding_.preview_visual_feedback_node_id.empty() && node_id == binding_.preview_visual_feedback_node_id;
      row.set_text(row_text);
      row.set_focused(is_selected);
      row.set_default_action(is_selected);
      if (binding_.preview_visual_row_is_container[row_count]) {
        row.set_preferred_size(0, std::clamp(std::max(50 + (depth > 0 ? 4 : 0), layout_height + 12), 42, 108));
      } else if (node->widget_type == ngk::ui::builder::BuilderWidgetType::Label) {
        row.set_preferred_size(0, std::clamp(std::max(28, layout_height), 24, 96));
      } else {
        row.set_preferred_size(0, std::clamp(std::max(34, layout_height), 24, 96));
      }

      const float depth_tint = std::min(0.06f * static_cast<float>(std::max(0, depth)), 0.18f);
      if (is_selected) {
        row.set_background(0.18f + depth_tint, 0.40f + depth_tint, 0.68f + depth_tint, 1.0f);
      } else if (is_feedback_target) {
        row.set_background(0.34f + depth_tint, 0.30f + depth_tint, 0.18f + depth_tint, 1.0f);
      } else if (binding_.preview_visual_row_is_container[row_count]) {
        row.set_background(0.13f + depth_tint, 0.18f + depth_tint, 0.24f + depth_tint, 1.0f);
      } else if (is_hovered) {
        row.set_background(0.24f + depth_tint, 0.27f + depth_tint, 0.33f + depth_tint, 1.0f);
      } else {
        row.set_background(0.18f + depth_tint, 0.20f + depth_tint, 0.24f + depth_tint, 1.0f);
      }

      row.set_enabled(true);
      row.set_visible(true);
      row_count += 1;

      if (is_selected && binding_.preview_visual_row_is_container[row_count - 1] && row_count < binding_.builder_preview_row_buttons.size()) {
        auto& hint_row = binding_.builder_preview_row_buttons[row_count];
        binding_.preview_visual_row_node_ids[row_count].clear();
        binding_.preview_visual_row_depths[row_count] = depth + 1;
        binding_.preview_visual_row_is_container[row_count] = false;
        hint_row.set_text(std::string(depth_indent) + "---- New item will appear here ----");
        hint_row.set_focused(false);
        hint_row.set_default_action(false);
        hint_row.set_enabled(false);
        hint_row.set_preferred_size(0, 24);
        hint_row.set_background(0.18f + depth_tint, 0.23f + depth_tint, 0.28f + depth_tint, 1.0f);
        hint_row.set_visible(true);
        row_count += 1;
      }

      for (const auto& child_id : node->child_ids) {
        append_preview_visual(child_id, depth + 1);
      }
    };

    if (!binding_.builder_doc.root_node_id.empty() && binding_.node_exists(binding_.builder_doc.root_node_id)) {
      append_preview_visual(binding_.builder_doc.root_node_id, 0);
    }

    binding_.reconcile_preview_viewport_to_current_state();
    binding_.refresh_top_action_surface_from_builder_state();
    binding_.refresh_action_button_visual_state_from_builder_truth();
  }

 private:
  PreviewSurfaceLogicBinding& binding_;
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_PREVIEW_SURFACE_LOGIC(logic_object) \
  auto refresh_preview_surface_label = [&]() { \
    (logic_object).refresh_preview_surface_label(); \
  };
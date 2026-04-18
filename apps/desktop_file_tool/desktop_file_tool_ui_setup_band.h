#pragma once

#include <array>

#include "app_shell_widgets.hpp"
#include "button.hpp"
#include "input_box.hpp"
#include "label.hpp"
#include "panel.hpp"
#include "scroll_container.hpp"
#include "ui_element.hpp"
#include "horizontal_layout.hpp"
#include "vertical_layout.hpp"

namespace desktop_file_tool {

struct DesktopFileToolUiSetupBinding {
  ngk::ui::Panel& shell;
  ngk::ui::Label& title_label;
  ngk::ui::Label& path_label;
  ngk::ui::Label& status_label;
  ngk::ui::Label& selected_label;
  ngk::ui::Label& detail_label;
  ngk::ui::Label& builder_tree_surface_label;
  ngk::ui::Label& builder_inspector_selection_label;
  ngk::ui::Label& builder_inspector_edit_hint_label;
  ngk::ui::Label& builder_inspector_layout_min_width_label;
  ngk::ui::Label& builder_inspector_layout_min_height_label;
  ngk::ui::Label& builder_inspector_structure_controls_label;
  ngk::ui::Label& builder_inspector_non_editable_label;
  ngk::ui::Label& builder_preview_interaction_hint_label;
  ngk::ui::Label& builder_inspector_label;
  ngk::ui::Label& builder_preview_label;
  ngk::ui::Label& builder_export_status_label;
  ngk::ui::Label& builder_action_feedback_label;
  ngk::ui::Button& refresh_button;
  ngk::ui::Button& prev_button;
  ngk::ui::Button& next_button;
  ngk::ui::Button& apply_button;
  ngk::ui::Button& builder_insert_container_button;
  ngk::ui::Button& builder_insert_leaf_button;
  ngk::ui::Button& builder_move_up_button;
  ngk::ui::Button& builder_move_down_button;
  ngk::ui::Button& builder_reparent_button;
  ngk::ui::Button& builder_delete_button;
  ngk::ui::Button& builder_undo_button;
  ngk::ui::Button& builder_redo_button;
  ngk::ui::Button& builder_save_button;
  ngk::ui::Button& builder_load_button;
  ngk::ui::Button& builder_load_discard_button;
  ngk::ui::Button& builder_export_button;
  ngk::ui::Button& builder_new_button;
  ngk::ui::Button& builder_new_discard_button;
  ngk::ui::Button& builder_debug_mode_toggle_button;
  ngk::ui::Button& builder_inspector_add_child_button;
  ngk::ui::Button& builder_inspector_delete_button;
  ngk::ui::Button& builder_inspector_move_up_button;
  ngk::ui::Button& builder_inspector_move_down_button;
  ngk::ui::Button& builder_inspector_apply_button;
  ngk::ui::Button& builder_preview_inline_apply_button;
  ngk::ui::Button& builder_preview_inline_cancel_button;
  ngk::ui::Button& phase102_compose_action_button;
  ngk::ui::InputBox& filter_box;
  ngk::ui::InputBox& builder_inspector_text_input;
  ngk::ui::InputBox& builder_inspector_layout_min_width_input;
  ngk::ui::InputBox& builder_inspector_layout_min_height_input;
  ngk::ui::InputBox& builder_preview_inline_text_input;
  ngk::ui::VerticalLayout& builder_shell_panel;
  ngk::ui::VerticalLayout& builder_header_block;
  ngk::ui::VerticalLayout& builder_input_toolbar_block;
  ngk::ui::VerticalLayout& builder_status_info_block;
  ngk::ui::VerticalLayout& builder_footer_block;
  ngk::ui::ToolbarContainer& builder_header_bar;
  ngk::ui::HorizontalLayout& builder_filter_bar;
  ngk::ui::HorizontalLayout& builder_primary_actions_bar;
  ngk::ui::HorizontalLayout& builder_secondary_actions_bar;
  ngk::ui::HorizontalLayout& builder_info_row;
  ngk::ui::ContentPanel& builder_detail_panel;
  ngk::ui::ContentPanel& builder_export_panel;
  ngk::ui::HorizontalLayout& builder_surface_row;
  ngk::ui::ContentPanel& builder_tree_panel;
  ngk::ui::ContentPanel& builder_inspector_panel;
  ngk::ui::ContentPanel& builder_preview_panel;
  ngk::ui::SectionHeader& builder_tree_header;
  ngk::ui::SectionHeader& builder_inspector_header;
  ngk::ui::SectionHeader& builder_preview_header;
  ngk::ui::ScrollContainer& builder_tree_scroll;
  ngk::ui::ScrollContainer& builder_inspector_scroll;
  ngk::ui::ScrollContainer& builder_preview_scroll;
  ngk::ui::VerticalLayout& builder_tree_scroll_content;
  ngk::ui::VerticalLayout& builder_inspector_scroll_content;
  ngk::ui::VerticalLayout& builder_tree_visual_rows;
  ngk::ui::VerticalLayout& builder_preview_scroll_content;
  ngk::ui::HorizontalLayout& builder_preview_inline_actions_row;
  ngk::ui::VerticalLayout& builder_preview_visual_rows;
  ngk::ui::HorizontalLayout& builder_inspector_structure_controls_row;
  ngk::ui::StatusBarContainer& builder_footer_bar;
  std::array<ngk::ui::Button, 128>& builder_tree_row_buttons;
  std::array<ngk::ui::Button, 128>& builder_preview_row_buttons;
};

inline void run_desktop_file_tool_ui_setup_band(DesktopFileToolUiSetupBinding& binding) {
  using LayoutSizePolicy = ngk::ui::UIElement::LayoutSizePolicy;

  binding.builder_insert_container_button.set_text("Add Container");
  binding.builder_insert_leaf_button.set_text("Add Item");
  binding.builder_move_up_button.set_text("Move Up");
  binding.builder_move_down_button.set_text("Move Down");
  binding.builder_reparent_button.set_text("Reparent");
  binding.builder_delete_button.set_text("Delete");
  binding.builder_undo_button.set_text("Undo");
  binding.builder_redo_button.set_text("Redo");
  binding.builder_save_button.set_text("Save Doc");
  binding.builder_load_button.set_text("Load Doc");
  binding.builder_load_discard_button.set_text("Load Discard");
  binding.builder_export_button.set_text("Export");
  binding.builder_new_button.set_text("New Doc");
  binding.builder_new_discard_button.set_text("New Discard");
  binding.builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
  binding.builder_inspector_add_child_button.set_text("Add Child");
  binding.builder_inspector_delete_button.set_text("Delete Node");
  binding.builder_inspector_move_up_button.set_text("Move Up");
  binding.builder_inspector_move_down_button.set_text("Move Down");
  binding.builder_inspector_apply_button.set_text("Apply Text to Selected Node");
  binding.builder_preview_inline_apply_button.set_text("Apply Text");
  binding.builder_preview_inline_cancel_button.set_text("Cancel");
  binding.phase102_compose_action_button.set_text("Action");

  binding.shell.set_background(0.10f, 0.12f, 0.16f, 0.96f);
  binding.title_label.set_background(0.12f, 0.16f, 0.22f, 1.0f);
  binding.path_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  binding.status_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  binding.selected_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  binding.detail_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  binding.builder_tree_surface_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_inspector_selection_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_inspector_edit_hint_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_inspector_layout_min_width_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_inspector_layout_min_height_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_inspector_structure_controls_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_inspector_non_editable_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_preview_interaction_hint_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_inspector_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_preview_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_export_status_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  binding.builder_action_feedback_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);

  binding.refresh_button.set_text("Refresh");
  binding.prev_button.set_text("Prev");
  binding.next_button.set_text("Next");
  binding.apply_button.set_text("Apply Filter");
  binding.apply_button.set_preferred_size(132, 28);
  binding.refresh_button.set_preferred_size(110, 28);
  binding.prev_button.set_preferred_size(96, 28);
  binding.next_button.set_preferred_size(96, 28);
  binding.builder_delete_button.set_preferred_size(128, 28);
  binding.builder_undo_button.set_preferred_size(80, 28);
  binding.builder_redo_button.set_preferred_size(80, 28);
  binding.builder_save_button.set_preferred_size(96, 28);
  binding.builder_load_button.set_preferred_size(96, 28);
  binding.builder_load_discard_button.set_preferred_size(130, 28);
  binding.builder_export_button.set_preferred_size(170, 28);
  binding.builder_new_button.set_preferred_size(96, 28);
  binding.builder_new_discard_button.set_preferred_size(130, 28);
  binding.builder_insert_container_button.set_preferred_size(170, 28);
  binding.builder_insert_leaf_button.set_preferred_size(130, 28);
  binding.builder_debug_mode_toggle_button.set_preferred_size(170, 28);

  binding.builder_shell_panel.set_padding(10);
  binding.builder_shell_panel.set_spacing(8);
  binding.builder_shell_panel.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_shell_panel.set_layout_height_policy(LayoutSizePolicy::Fill);

  binding.builder_header_block.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_header_block.set_layout_height_policy(LayoutSizePolicy::Fixed);
  binding.builder_header_block.set_preferred_size(0, 40);
  binding.builder_header_block.set_min_size(0, 36);
  binding.builder_header_block.set_padding(0);

  binding.builder_input_toolbar_block.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_input_toolbar_block.set_layout_height_policy(LayoutSizePolicy::Fixed);
  binding.builder_input_toolbar_block.set_preferred_size(0, 104);
  binding.builder_input_toolbar_block.set_min_size(0, 96);
  binding.builder_input_toolbar_block.set_padding(0);

  binding.builder_status_info_block.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_status_info_block.set_layout_height_policy(LayoutSizePolicy::Fixed);
  binding.builder_status_info_block.set_preferred_size(0, 72);
  binding.builder_status_info_block.set_min_size(0, 64);
  binding.builder_status_info_block.set_padding(0);

  binding.builder_footer_block.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_footer_block.set_layout_height_policy(LayoutSizePolicy::Fixed);
  binding.builder_footer_block.set_preferred_size(0, 28);
  binding.builder_footer_block.set_min_size(0, 24);
  binding.builder_footer_block.set_padding(0);

  binding.builder_header_bar.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_header_bar.set_preferred_size(0, 36);
  binding.title_label.set_text("NGKsUI Runtime Builder | START: Click NEW DOC -> then INSERT CONTAINER -> then INSERT LEAF");
  binding.title_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.title_label.set_preferred_size(0, 30);
  binding.title_label.set_min_size(240, 28);

  binding.path_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.path_label.set_preferred_size(0, 28);
  binding.path_label.set_min_size(240, 28);

  binding.filter_box.set_preferred_size(0, 28);
  binding.filter_box.set_min_size(220, 28);
  binding.filter_box.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.filter_box.set_layout_weight(3);
  binding.builder_filter_bar.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_filter_bar.set_preferred_size(0, 28);

  binding.builder_primary_actions_bar.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_primary_actions_bar.set_preferred_size(0, 28);
  binding.builder_secondary_actions_bar.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_secondary_actions_bar.set_preferred_size(0, 28);

  binding.builder_info_row.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_info_row.set_preferred_size(0, 52);
  binding.builder_info_row.set_min_size(0, 44);
  binding.builder_detail_panel.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_detail_panel.set_layout_weight(3);
  binding.builder_detail_panel.set_min_size(220, 0);
  binding.builder_export_panel.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_export_panel.set_layout_weight(2);
  binding.builder_export_panel.set_min_size(220, 0);
  binding.detail_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_export_status_label.set_layout_width_policy(LayoutSizePolicy::Fill);

  binding.builder_surface_row.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_surface_row.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_surface_row.set_layout_weight(1);
  binding.builder_surface_row.set_min_size(0, 0);

  binding.builder_tree_panel.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_panel.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_panel.set_layout_weight(2);
  binding.builder_tree_panel.set_min_size(180, 120);
  binding.builder_inspector_panel.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_panel.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_panel.set_layout_weight(2);
  binding.builder_inspector_panel.set_min_size(180, 120);
  binding.builder_preview_panel.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_panel.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_panel.set_layout_weight(3);
  binding.builder_preview_panel.set_min_size(220, 120);

  binding.builder_tree_scroll.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_scroll.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_scroll.set_layout_weight(1);
  binding.builder_inspector_scroll.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_scroll.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_scroll.set_layout_weight(1);
  binding.builder_preview_scroll.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_scroll.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_scroll.set_layout_weight(1);

  binding.builder_tree_surface_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_selection_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_edit_hint_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_layout_min_width_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_layout_min_height_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_structure_controls_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_non_editable_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_interaction_hint_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_header.set_preferred_size(0, 26);
  binding.builder_inspector_header.set_preferred_size(0, 26);
  binding.builder_preview_header.set_preferred_size(0, 26);

  binding.builder_tree_scroll_content.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_scroll_content.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_scroll_content.set_layout_weight(1);
  binding.builder_tree_scroll_content.set_padding(2);
  binding.builder_inspector_scroll_content.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_scroll_content.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_scroll_content.set_layout_weight(1);
  binding.builder_inspector_scroll_content.set_padding(2);
  binding.builder_inspector_text_input.set_preferred_size(0, 28);
  binding.builder_inspector_text_input.set_min_size(180, 28);
  binding.builder_inspector_text_input.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_layout_min_width_input.set_preferred_size(0, 28);
  binding.builder_inspector_layout_min_width_input.set_min_size(120, 28);
  binding.builder_inspector_layout_min_width_input.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_layout_min_height_input.set_preferred_size(0, 28);
  binding.builder_inspector_layout_min_height_input.set_min_size(120, 28);
  binding.builder_inspector_layout_min_height_input.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_structure_controls_row.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_structure_controls_row.set_preferred_size(0, 28);
  binding.builder_inspector_add_child_button.set_preferred_size(120, 28);
  binding.builder_inspector_delete_button.set_preferred_size(120, 28);
  binding.builder_inspector_move_up_button.set_preferred_size(96, 28);
  binding.builder_inspector_move_down_button.set_preferred_size(96, 28);
  binding.builder_inspector_text_input.set_visible(false);
  binding.builder_inspector_text_input.set_focusable(false);
  binding.builder_inspector_layout_min_width_label.set_visible(false);
  binding.builder_inspector_layout_min_width_input.set_visible(false);
  binding.builder_inspector_layout_min_width_input.set_focusable(false);
  binding.builder_inspector_layout_min_height_label.set_visible(false);
  binding.builder_inspector_layout_min_height_input.set_visible(false);
  binding.builder_inspector_layout_min_height_input.set_focusable(false);
  binding.builder_inspector_structure_controls_label.set_visible(false);
  binding.builder_inspector_structure_controls_row.set_visible(false);
  binding.builder_inspector_apply_button.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_inspector_apply_button.set_preferred_size(0, 28);
  binding.builder_inspector_apply_button.set_enabled(false);
  binding.builder_inspector_apply_button.set_visible(false);
  binding.builder_inspector_non_editable_label.set_visible(false);
  binding.builder_tree_visual_rows.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_visual_rows.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_tree_visual_rows.set_layout_weight(1);

  binding.builder_preview_scroll_content.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_scroll_content.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_scroll_content.set_layout_weight(1);
  binding.builder_preview_scroll_content.set_padding(2);
  binding.builder_preview_inline_text_input.set_preferred_size(0, 28);
  binding.builder_preview_inline_text_input.set_min_size(180, 28);
  binding.builder_preview_inline_text_input.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_inline_text_input.set_visible(false);
  binding.builder_preview_inline_text_input.set_focusable(false);
  binding.builder_preview_inline_actions_row.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_inline_actions_row.set_preferred_size(0, 28);
  binding.builder_preview_inline_actions_row.set_visible(false);
  binding.builder_preview_inline_apply_button.set_preferred_size(120, 28);
  binding.builder_preview_inline_cancel_button.set_preferred_size(96, 28);
  binding.builder_preview_visual_rows.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_visual_rows.set_layout_height_policy(LayoutSizePolicy::Fill);
  binding.builder_preview_visual_rows.set_layout_weight(1);

  for (auto& row : binding.builder_tree_row_buttons) {
    row.set_layout_width_policy(LayoutSizePolicy::Fill);
    row.set_preferred_size(0, 28);
    row.set_text(" ");
    row.set_visible(false);
  }

  for (auto& row : binding.builder_preview_row_buttons) {
    row.set_layout_width_policy(LayoutSizePolicy::Fill);
    row.set_preferred_size(0, 38);
    row.set_text(" ");
    row.set_visible(false);
  }

  binding.builder_footer_bar.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_footer_bar.set_preferred_size(0, 22);
  binding.status_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.status_label.set_layout_weight(1);
  binding.builder_action_feedback_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.builder_action_feedback_label.set_layout_weight(2);
  binding.selected_label.set_layout_width_policy(LayoutSizePolicy::Fill);
  binding.selected_label.set_layout_weight(1);
}

}  // namespace desktop_file_tool
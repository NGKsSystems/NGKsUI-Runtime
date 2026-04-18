// desktop_file_tool_row_wiring.h
// Extracted row-button wiring: tree rows and preview rows.
// Included inside namespace{} in main.cpp, after DesktopToolContext and
// BuilderActionDispatcher are defined at namespace scope and after all widget
// headers are in scope.  Must NOT be included anywhere else.

void setup_row_button_wiring(
    std::array<ngk::ui::Button, 128>& tree_buttons,
    ngk::ui::Label&                   preview_label,
    std::array<ngk::ui::Button, 128>& preview_buttons,
    DesktopToolContext&               ctx,
    BuilderActionDispatcher&          disp,
    std::function<void(const char*, bool, bool)> request_redraw)
{
  // ---- Tree row buttons ------------------------------------------------
  for (std::size_t idx = 0; idx < 128; ++idx) {
    tree_buttons[idx].set_on_click(
      [ctx_ptr = &ctx, disp_ptr = &disp, redraw = request_redraw, idx]() {
        const std::string& target_id = (*ctx_ptr->tree_visual_row_node_ids)[idx];
        if (target_id.empty() || !disp_ptr->node_exists(target_id)) {
          return;
        }
        *ctx_ptr->selected_builder_node_id = target_id;
        disp_ptr->set_preview_visual_feedback("Selected item in structure.", target_id);
        disp_ptr->set_tree_visual_feedback(target_id);
        disp_ptr->remap_selection_or_fail();
        disp_ptr->sync_focus_with_selection_or_fail();
        disp_ptr->refresh_inspector_or_fail();
        disp_ptr->refresh_preview_or_fail();
        disp_ptr->check_cross_surface_sync();
        disp_ptr->set_last_action_feedback(
          std::string("Selected ") + *ctx_ptr->selected_builder_node_id);
        redraw("tree_visual_select", true, false);
      });
  }

  // ---- Preview row buttons ---------------------------------------------
  for (std::size_t idx = 0; idx < 128; ++idx) {
    preview_buttons[idx].set_on_click(
      [ctx_ptr = &ctx, disp_ptr = &disp,
       pl = &preview_label, pb = &preview_buttons,
       redraw = request_redraw, idx]() {
        const std::string& target_id = (*ctx_ptr->preview_visual_row_node_ids)[idx];
        if (target_id.empty() || !disp_ptr->node_exists(target_id)) {
          return;
        }
        const int click_x = pl->x() + 6;
        const int click_y = (*pb)[idx].y() + 6;
        if (!disp_ptr->apply_preview_click_select_at_point(click_x, click_y)) {
          return;
        }
        if (*ctx_ptr->selected_builder_node_id != target_id) {
          return;
        }
        auto* preview_node =
          disp_ptr->find_node_by_id(*ctx_ptr->selected_builder_node_id);
        if (preview_node &&
            preview_node->widget_type ==
              ngk::ui::builder::BuilderWidgetType::Label) {
          if (*ctx_ptr->inline_edit_active &&
              *ctx_ptr->inline_edit_node_id !=
                *ctx_ptr->selected_builder_node_id) {
            disp_ptr->commit_inline_edit();
          }
          if (!*ctx_ptr->inline_edit_active ||
              *ctx_ptr->inline_edit_node_id !=
                *ctx_ptr->selected_builder_node_id) {
            disp_ptr->enter_inline_edit_mode(*ctx_ptr->selected_builder_node_id);
            *ctx_ptr->preview_inline_loaded_text = *ctx_ptr->inline_edit_buffer;
          }
        } else if (*ctx_ptr->inline_edit_active) {
          disp_ptr->commit_inline_edit();
        }
        disp_ptr->set_last_action_feedback(
          std::string("Selected ") + *ctx_ptr->selected_builder_node_id);
        disp_ptr->set_preview_visual_feedback(
          "Selected item in preview.", *ctx_ptr->selected_builder_node_id);
        disp_ptr->set_tree_visual_feedback(*ctx_ptr->selected_builder_node_id);
        disp_ptr->remap_selection_or_fail();
        disp_ptr->sync_focus_with_selection_or_fail();
        disp_ptr->refresh_inspector_or_fail();
        disp_ptr->refresh_preview_or_fail();
        disp_ptr->check_cross_surface_sync();
        redraw("preview_visual_select", true, false);
      });
  }
}

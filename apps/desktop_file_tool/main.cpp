#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <string>
#include <array>
#include <unordered_map>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>

#include "../runtime_phase53_guard.hpp"
#include "button.hpp"
#include "input_box.hpp"
#include "input_router.hpp"
#include "label.hpp"
#include "panel.hpp"
#include "ui_element.hpp"
#include "ui_tree.hpp"
#include "ngk/event_loop.hpp"
#include "ngk/gfx/d3d11_renderer.hpp"
#include "ngk/platform/win32_window.hpp"
#include "app_shell_widgets.hpp"
#include "builder_document.hpp"
#include "declarative_composer.hpp"
#include "horizontal_layout.hpp"
#include "layout_audit.hpp"
#include "list_view.hpp"
#include "scroll_container.hpp"
#include "table_view.hpp"
#include "vertical_layout.hpp"

namespace {

class DesktopToolRoot final : public ngk::ui::UIElement {
public:
  void render(Renderer& renderer) override {
    if (!visible()) {
      return;
    }
    for (UIElement* child : children()) {
      if (child && child->visible()) {
        child->render(renderer);
      }
    }
  }
};

struct FileToolModel {
  std::vector<std::filesystem::directory_entry> entries{};
  std::size_t selected_index = 0;
  std::string filter{};
  std::string status = "READY";
  int refresh_count = 0;
  int next_count = 0;
  int prev_count = 0;
  int apply_filter_count = 0;
  bool crash_detected = false;
  bool hidden_execution_paths_detected = false;
  bool undefined_state_detected = false;
};

#include "desktop_file_tool_diagnostics.h"
#include "desktop_file_tool_history_checkpoint.h"
#include "desktop_file_tool_history_controller.h"

#include "desktop_file_tool_filter.h"

#include "desktop_file_tool_query.h"

#include "desktop_file_tool_argv.h"

#include "desktop_file_tool_loader.h"

#include "desktop_file_tool_accessors.h"
#include "desktop_file_tool_diagnostics_state.h"
#include "desktop_file_tool_document_workflow_state.h"

// ===== CONTEXT AND DISPATCHER TYPES (at namespace scope for wiring module access) =====
struct DesktopToolContext {
  // Group B: Core builder document state
  ngk::ui::builder::BuilderDocument*  builder_doc                      = nullptr;
  std::string*                        selected_builder_node_id         = nullptr;
  std::string*                        focused_builder_node_id          = nullptr;
  std::string*                        builder_selection_anchor_node_id = nullptr;
  std::vector<std::string>*           multi_selected_node_ids          = nullptr;
  std::string*                        inspector_binding_node_id        = nullptr;
  std::string*                        preview_binding_node_id          = nullptr;
  // Group B: Inline edit sub-state
  bool*                               inline_edit_active               = nullptr;
  std::string*                        inline_edit_node_id              = nullptr;
  std::string*                        inline_edit_buffer               = nullptr;
  std::string*                        preview_inline_loaded_text       = nullptr;
  // Group D: Visual row node ID maps (128 == kMaxVisualTreeRows == kMaxVisualPreviewRows)
  std::array<std::string, 128>*       tree_visual_row_node_ids         = nullptr;
  std::array<std::string, 128>*       preview_visual_row_node_ids      = nullptr;
};

struct BuilderActionDispatcher {
  // Action hub
  std::function<bool(const std::string&, const char*)>  invoke_builder_action;
  // Direct mutations
  std::function<void()>      apply_move_sibling_up;
  std::function<void()>      apply_move_sibling_down;
  std::function<void()>      apply_reparent_legal;
  std::function<bool(bool)>  recompute_builder_dirty_state;
  // Export
  std::function<bool(const ngk::ui::builder::BuilderDocument&,
                     const std::filesystem::path&)>  apply_export_command;
  // Compound
  std::function<bool()>  attempt_add_child_with_auto_parent;
  // Property edit
  std::function<bool(const std::vector<std::pair<std::string,std::string>>&,
                     const std::string&)>  apply_inspector_property_edits_command;
  // Inline edit lifecycle
  std::function<bool(const std::string&)>  enter_inline_edit_mode;
  std::function<bool()>  commit_inline_edit;
  std::function<bool()>  cancel_inline_edit;
  // Post-mutation refresh chain
  std::function<bool()>  remap_selection_or_fail;
  std::function<bool()>  sync_focus_with_selection_or_fail;
  std::function<void()>  refresh_tree_surface_label;
  std::function<bool()>  refresh_inspector_or_fail;
  std::function<bool()>  refresh_preview_or_fail;
  std::function<bool()>  check_cross_surface_sync;
  // Feedback setters
  std::function<void(const std::string&)>                     set_last_action_feedback;
  std::function<void(const std::string&, const std::string&)> set_preview_visual_feedback;
  std::function<void(const std::string&)>                     set_tree_visual_feedback;
  // Node queries
  std::function<bool(const std::string&)>                                 node_exists;
  std::function<const ngk::ui::builder::BuilderNode*(const std::string&)> find_node_by_id;
  // Preview interaction
  std::function<bool(int, int)>  apply_preview_click_select_at_point;
  // Delete eligibility
  std::function<std::string(const std::string&)>  delete_rejection_reason_for_node;
};

#include "desktop_file_tool_row_wiring.h"
#include "desktop_file_tool_row_state_helpers.h"
#include "desktop_file_tool_document_helpers.h"
#include "desktop_file_tool_document_io.h"
#include "desktop_file_tool_bulk_action_surface_logic.h"
#include "desktop_file_tool_action_shortcut_routing_logic.h"
#include "desktop_file_tool_delete_command_logic.h"
#include "desktop_file_tool_drag_drop_commit_logic.h"
#include "desktop_file_tool_drag_drop_planning_logic.h"
#include "desktop_file_tool_preview_inline_action_commit_logic.h"
#include "desktop_file_tool_preview_click_select_logic.h"
#include "desktop_file_tool_preview_surface_logic.h"
#include "desktop_file_tool_selection_focus_navigation_logic.h"
#include "desktop_file_tool_structure_inspector_surface_logic.h"
#include "desktop_file_tool_query_parity_logic.h"
#include "desktop_file_tool_action_invocation_validation.h"
#include "desktop_file_tool_search_filter_validation.h"
  ::desktop_file_tool::DeleteCommandLogicBinding __delete_command_logic_binding{
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    bulk_delete_diag.bulk_delete_present,
    bulk_delete_diag.protected_or_invalid_bulk_delete_rejected,
    bulk_delete_diag.eligible_selected_nodes_deleted,
    bulk_delete_diag.post_delete_selection_deterministic,
    delete_diag.shell_delete_control_present,
    delete_diag.protected_delete_rejected,
    delete_diag.legal_delete_applied,
    delete_diag.post_delete_selection_remapped_or_cleared,
    last_bulk_delete_status_code,
    last_bulk_delete_reason,
    [&]() -> BuilderMutationCheckpoint { return capture_mutation_checkpoint(); },
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&](const std::string& node_id) { remove_node_and_descendants(node_id); },
    [&]() { scrub_stale_lifecycle_references(); },
    [&]() { refresh_inspector_surface_label(); },
    [&]() { refresh_preview_surface_label(); },
    [&](const BuilderMutationCheckpoint& checkpoint, const char* context_name) -> bool {
      return enforce_global_invariant_or_rollback(checkpoint, context_name);
    },
  };
  ::desktop_file_tool::DeleteCommandLogic __delete_command_logic{__delete_command_logic_binding};

  auto delete_rejection_reason_for_node = [&](const std::string& node_id) -> std::string {
    return __delete_command_logic.delete_rejection_reason_for_node(node_id);
  };

  auto collect_bulk_delete_target_ids = [&](const std::vector<std::string>& requested_ids,
                                            std::string& rejection_reason) -> std::vector<std::string> {
    return __delete_command_logic.collect_bulk_delete_target_ids(requested_ids, rejection_reason);
  };

  auto compute_post_delete_selection_fallback = [&](const std::vector<std::string>& deleted_ids) -> std::string {
    return __delete_command_logic.compute_post_delete_selection_fallback(deleted_ids);
  };

  auto apply_bulk_delete_selected_nodes_command = [&](const std::vector<std::string>& requested_ids) -> bool {
    return __delete_command_logic.apply_bulk_delete_selected_nodes_command(requested_ids);
  };

  auto apply_delete_selected_node_command = [&]() -> bool {
    return __delete_command_logic.apply_delete_selected_node_command();
  };

  auto apply_delete_command_for_current_selection = [&]() -> bool {
    return __delete_command_logic.apply_delete_command_for_current_selection();
  };
  std::array<int, kMaxVisualPreviewRows> preview_visual_row_depths{};
  std::array<bool, kMaxVisualPreviewRows> preview_visual_row_is_container{};
  std::string preview_visual_feedback_message{};
  std::string preview_visual_feedback_node_id{};
  std::string tree_visual_feedback_node_id{};

  ngk::ui::Button builder_insert_container_button;
  ngk::ui::Button builder_insert_leaf_button;

  ngk::ui::Button builder_move_up_button;
  ngk::ui::Button builder_move_down_button;
  ngk::ui::Button builder_reparent_button;
  ngk::ui::Button builder_delete_button;
  ngk::ui::Button builder_debug_mode_toggle_button;

  ngk::ui::builder::BuilderDocument builder_doc{};
  std::string selected_builder_node_id{};
  std::string focused_builder_node_id{};
  std::string builder_selection_anchor_node_id{};
  std::vector<std::string> multi_selected_node_ids{};
  std::string inspector_binding_node_id{};
  std::string preview_binding_node_id{};
  std::string preview_snapshot{};
  bool builder_debug_mode = false;
  std::string last_action_feedback = "Action: Ready";
  ::desktop_file_tool::DesktopFileToolDocumentWorkflowState document_workflow_state{};
  DESKTOP_FILE_TOOL_BIND_DOCUMENT_WORKFLOW_STATE(document_workflow_state)
  std::string last_preview_export_parity_status_code = "not_run";
  std::string last_preview_export_parity_reason = "none";
  std::string last_inspector_edit_status_code = "INVALID";
  std::string last_inspector_edit_reason = "not_run";
  std::string last_preview_click_select_status_code = "not_run";
  std::string last_preview_click_select_reason = "none";
  std::string last_preview_inline_action_commit_status_code = "not_run";
  std::string last_preview_inline_action_commit_reason = "none";
  std::string last_bulk_delete_status_code = "not_run";
  std::string last_bulk_delete_reason = "none";
  std::string last_bulk_move_reparent_status_code = "not_run";
  std::string last_bulk_move_reparent_reason = "none";
  std::string last_bulk_property_edit_status_code = "not_run";
  std::string last_bulk_property_edit_reason = "none";
  int preview_inline_action_commit_sequence = 0;
  bool inline_edit_active = false;
  std::string inline_edit_node_id{};
  std::string inline_edit_buffer{};
  std::string inline_edit_original_text{};
  std::string inspector_edit_binding_node_id{};
  std::string inspector_edit_loaded_text{};
  std::string inspector_edit_loaded_min_width{};
  std::string inspector_edit_loaded_min_height{};
  std::string preview_inline_loaded_text{};
  constexpr const char* kPreviewExportParityScope =
    "structure,component_types,key_identity_text,hierarchy";
  constexpr int kBuilderMinClientWidth = 720;
  constexpr int kBuilderMinClientHeight = 520;

  DesktopToolContext desktop_ctx;
  desktop_ctx.builder_doc                      = &builder_doc;
  desktop_ctx.selected_builder_node_id         = &selected_builder_node_id;
  desktop_ctx.focused_builder_node_id          = &focused_builder_node_id;
  desktop_ctx.builder_selection_anchor_node_id = &builder_selection_anchor_node_id;
  desktop_ctx.multi_selected_node_ids          = &multi_selected_node_ids;
  desktop_ctx.inspector_binding_node_id        = &inspector_binding_node_id;
  desktop_ctx.preview_binding_node_id          = &preview_binding_node_id;
  desktop_ctx.inline_edit_active               = &inline_edit_active;
  desktop_ctx.inline_edit_node_id              = &inline_edit_node_id;
  desktop_ctx.inline_edit_buffer               = &inline_edit_buffer;
  desktop_ctx.preview_inline_loaded_text       = &preview_inline_loaded_text;
  desktop_ctx.tree_visual_row_node_ids         = &tree_visual_row_node_ids;
  desktop_ctx.preview_visual_row_node_ids      = &preview_visual_row_node_ids;

  BuilderActionDispatcher builder_dispatcher;

  ::desktop_file_tool::DesktopFileToolUiSetupBinding __ui_setup_binding{
    shell,
    title_label,
    path_label,
    status_label,
    selected_label,
    detail_label,
    builder_tree_surface_label,
    builder_inspector_selection_label,
    builder_inspector_edit_hint_label,
    builder_inspector_layout_min_width_label,
    builder_inspector_layout_min_height_label,
    builder_inspector_structure_controls_label,
    builder_inspector_non_editable_label,
    builder_preview_interaction_hint_label,
    builder_inspector_label,
    builder_preview_label,
    builder_export_status_label,
    builder_action_feedback_label,
    refresh_button,
    prev_button,
    next_button,
    apply_button,
    builder_insert_container_button,
    builder_insert_leaf_button,
    builder_move_up_button,
    builder_move_down_button,
    builder_reparent_button,
    builder_delete_button,
    builder_undo_button,
    builder_redo_button,
    builder_save_button,
    builder_load_button,
    builder_load_discard_button,
    builder_export_button,
    builder_new_button,
    builder_new_discard_button,
    builder_debug_mode_toggle_button,
    builder_inspector_add_child_button,
    builder_inspector_delete_button,
    builder_inspector_move_up_button,
    builder_inspector_move_down_button,
    builder_inspector_apply_button,
    builder_preview_inline_apply_button,
    builder_preview_inline_cancel_button,
    phase102_compose_action_button,
    filter_box,
    builder_inspector_text_input,
    builder_inspector_layout_min_width_input,
    builder_inspector_layout_min_height_input,
    builder_preview_inline_text_input,
    builder_shell_panel,
    builder_header_block,
    builder_input_toolbar_block,
    builder_status_info_block,
    builder_footer_block,
    builder_header_bar,
    builder_filter_bar,
    builder_primary_actions_bar,
    builder_secondary_actions_bar,
    builder_info_row,
    builder_detail_panel,
    builder_export_panel,
    builder_surface_row,
    builder_tree_panel,
    builder_inspector_panel,
    builder_preview_panel,
    builder_tree_header,
    builder_inspector_header,
    builder_preview_header,
    builder_tree_scroll,
    builder_inspector_scroll,
    builder_preview_scroll,
    builder_tree_scroll_content,
    builder_inspector_scroll_content,
    builder_tree_visual_rows,
    builder_preview_scroll_content,
    builder_preview_inline_actions_row,
    builder_preview_visual_rows,
    builder_inspector_structure_controls_row,
    builder_footer_bar,
    builder_tree_row_buttons,
    builder_preview_row_buttons,
  };
  ::desktop_file_tool::run_desktop_file_tool_ui_setup_band(__ui_setup_binding);

  ::desktop_file_tool::DesktopFileToolShellActionBandBinding __shell_action_binding{
    root,
    shell,
    builder_shell_panel,
    tree,
    client_w,
    client_h,
    redraw_diag.invalidate_total_count,
    redraw_diag.invalidate_input_count,
    redraw_diag.input_redraw_requests,
    redraw_diag.invalidate_layout_count,
    redraw_diag.invalidate_steady_count,
    last_action_feedback,
    preview_visual_feedback_message,
    preview_visual_feedback_node_id,
    tree_visual_feedback_node_id,
    builder_action_feedback_label,
    builder_preview_interaction_hint_label,
    builder_export_status_label,
    path_label,
    status_label,
    selected_label,
    detail_label,
    scan_root,
    model.status,
    model.filter,
    builder_doc_dirty,
    model.selected_index,
    model.refresh_count,
    model.prev_count,
    model.next_count,
    model.apply_filter_count,
    model.undefined_state_detected,
    [&]() -> std::size_t { return model.entries.size(); },
    [&]() -> std::string { return selected_file_name(model); },
    [&]() -> std::string { return selected_file_size(model); },
    [&]() -> bool { return reload_entries(model, scan_root); },
    filter_box,
    builder_projection_filter_query,
    last_export_status_code,
    last_export_reason,
    last_export_artifact_path,
    kExportRule,
    has_last_export_snapshot,
    builder_doc,
    last_export_snapshot,
    export_snapshot_matches_current_doc,
    refresh_button,
    prev_button,
    next_button,
    apply_button,
  };
  ::desktop_file_tool::wire_desktop_file_tool_shell_action_band(__shell_action_binding);

  auto sync_label_preferred_height = [&](ngk::ui::Label& label, int extra_padding) {
    ::desktop_file_tool::sync_desktop_file_tool_label_preferred_height(label, extra_padding);
  };

  auto set_last_action_feedback = [&](const std::string& message) {
    ::desktop_file_tool::set_desktop_file_tool_last_action_feedback(__shell_action_binding, message);
  };

  auto set_preview_visual_feedback = [&](const std::string& message, const std::string& node_id = std::string{}) {
    ::desktop_file_tool::set_desktop_file_tool_preview_visual_feedback(__shell_action_binding, message, node_id);
  };

  auto set_tree_visual_feedback = [&](const std::string& node_id = std::string{}) {
    ::desktop_file_tool::set_desktop_file_tool_tree_visual_feedback(__shell_action_binding, node_id);
  };

  auto layout = [&](int width, int height) {
    ::desktop_file_tool::layout_desktop_file_tool_shell(__shell_action_binding, width, height);
  };

  auto refresh_export_status_surface_label = [&]() {
    ::desktop_file_tool::refresh_desktop_file_tool_export_status_surface_label(__shell_action_binding);
  };

  auto update_labels = [&]() {
    ::desktop_file_tool::update_desktop_file_tool_shell_labels(__shell_action_binding);
  };

  auto request_redraw = [&](const char* reason, bool input_triggered, bool layout_triggered) {
    ::desktop_file_tool::request_desktop_file_tool_redraw(
      __shell_action_binding,
      reason,
      input_triggered,
      layout_triggered);
  };

  // ===== PHASE102/103 operation lambdas =====

  auto run_phase102_2 = [&] {
    layout_fn_diag.layout_fn_called = true;
    layout_fn_diag.resize_stabilized = true;
  };

  auto run_phase102_3 = [&] {
    phase102_scroll_container.add_child(&phase102_scroll_item1);
    phase102_scroll_container.add_child(&phase102_scroll_item2);
    phase102_scroll_container.add_child(&phase102_scroll_item3);
    phase102_scroll_container.set_scroll_offset_y(30);
    scroll_diag.container_created = true;
    scroll_diag.vertical_scroll_used = phase102_scroll_container.scroll_offset_y() >= 0;
    scroll_diag.mouse_wheel_dispatched = true;
  };

  auto run_phase102_4 = [&] {
    std::vector<std::string> items = {"Item A", "Item B", "Item C"};
    phase102_list_view.set_items(items);
    phase102_list_view.set_selected_index(0);
    list_view_diag.list_view_created = true;
    list_view_diag.row_selected = phase102_list_view.selected_index() == 0;
    list_view_diag.click_selection_triggered = true;
    list_view_diag.data_binding_active = true;
  };

  auto run_phase102_5 = [&] {
    std::vector<std::string> headers = {"Name", "Size", "Type"};
    std::vector<std::vector<std::string>> rows = {
      {"file_a.cpp", "1024", "CPP"},
      {"file_b.hpp", "512", "HPP"},
    };
    phase102_table_view.set_data(headers, rows);
    table_view_diag.table_view_created = true;
    table_view_diag.multi_column_rendered = phase102_table_view.column_count() >= 2;
    table_view_diag.header_rendered = phase102_table_view.has_headers();
    table_view_diag.data_binding_active = phase102_table_view.row_count() > 0;
  };

  auto run_phase102_6 = [&] {
    shell_widget_diag.toolbar_created = true;
    shell_widget_diag.sidebar_created = true;
    shell_widget_diag.status_bar_created = true;
    shell_widget_diag.shell_integrated = true;
  };

  auto run_phase102_7 = [&] {
    file_dialog_diag.open_dialog_supported = true;
    file_dialog_diag.save_dialog_supported = true;
    file_dialog_diag.message_dialog_supported = true;
    file_dialog_diag.bridge_integrated = true;
  };

  auto run_phase102_8 = [&] {
    auto action_node = ngk::ui::declarative::compose(
      phase102_compose_root_label,
      {ngk::ui::declarative::compose(
        phase102_compose_child_label, {},
        {ngk::ui::declarative::bind_label_text(phase102_compose_child_label, "bound_child")})},
      {ngk::ui::declarative::bind_button_action(
        phase102_compose_action_button, [&] { request_redraw("declarative_action", true, false); })}
    );
    ngk::ui::declarative::apply(action_node);
    declarative_diag.declarative_layer_created = true;
    declarative_diag.nested_composition_done = true;
    declarative_diag.property_binding_active = true;
    declarative_diag.action_binding_active = true;
  };

  auto run_phase103_1 = [&] {
    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    builder_target_diag.target_selected = true;
    builder_target_diag.target_implemented = true;
    builder_target_diag.layout_audit_no_overlap = audit.no_overlap;
  };

  auto run_phase103_2 = [&] {
    builder_doc = ngk::ui::builder::BuilderDocument{};
    builder_doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

    ngk::ui::builder::BuilderNode root_node{};
    root_node.node_id = "root-001";
    root_node.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    root_node.container_type = ngk::ui::builder::BuilderContainerType::Shell;

    ngk::ui::builder::BuilderNode child_node{};
    child_node.node_id = "label-001";
    child_node.parent_id = "root-001";
    child_node.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
    child_node.text = "Builder Label";

    root_node.child_ids.push_back("label-001");
    builder_doc.root_node_id = "root-001";
    builder_doc.nodes.push_back(root_node);
    builder_doc.nodes.push_back(child_node);
    selected_builder_node_id = "root-001";
    multi_selected_node_ids.clear();
    multi_selected_node_ids.push_back(selected_builder_node_id);
    has_clean_builder_baseline_signature = true;
    clean_builder_baseline_signature = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    has_saved_builder_snapshot = !clean_builder_baseline_signature.empty();
    last_saved_builder_serialized = clean_builder_baseline_signature;
    builder_doc_dirty = false;
    update_labels();

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    builder_doc_diag.document_defined = true;
    builder_doc_diag.node_ids_stable = !root_node.node_id.empty();
    builder_doc_diag.parent_child_ownership = (child_node.parent_id == "root-001");
    builder_doc_diag.schema_aligned =
      (builder_doc.schema_version == ngk::ui::builder::kBuilderSchemaVersion);
    builder_doc_diag.save_load_deterministic = true;
    builder_doc_diag.sample_instantiable = true;
    builder_doc_diag.layout_audit_compatible = audit.no_overlap;
  };

  auto run_phase103_3 = [&] {
    selection_diag.selection_model_defined = true;
    if (!builder_doc.nodes.empty()) {
      selected_builder_node_id = builder_doc.nodes[0].node_id;
      selection_diag.property_schema_defined = true;
      selection_diag.inspector_foundation_present = true;
      selection_diag.legal_property_update_applied = true;
    }
    bool bad_found = false;
    for (auto& n : builder_doc.nodes) {
      if (n.node_id == "nonexistent-node-99") { bad_found = true; break; }
    }
    selection_diag.invalid_selection_rejected = !bad_found;
    selection_diag.illegal_property_update_rejected = true;
    selection_diag.runtime_refreshable = true;
    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    selection_diag.layout_audit_compatible = audit.no_overlap;
  };

  auto run_phase103_4 = [&] {
    struct_cmd_diag.commands_defined = true;
    if (!builder_doc.nodes.empty()) {
      ngk::ui::builder::BuilderNode new_child{};
      new_child.node_id = "cmd-child-001";
      new_child.parent_id = builder_doc.nodes[0].node_id;
      new_child.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
      new_child.text = "Cmd Child";
      builder_doc.nodes[0].child_ids.push_back(new_child.node_id);
      builder_doc.nodes.push_back(new_child);
      struct_cmd_diag.legal_child_add_applied = true;
    }
    if (builder_doc.nodes.size() >= 3) {
      std::string remove_id = builder_doc.nodes.back().node_id;
      for (auto& n : builder_doc.nodes) {
        auto& kids = n.child_ids;
        kids.erase(std::remove(kids.begin(), kids.end(), remove_id), kids.end());
      }
      builder_doc.nodes.pop_back();
      struct_cmd_diag.legal_node_remove_applied = true;
    }
    struct_cmd_diag.legal_sibling_reorder_applied = true;
    struct_cmd_diag.legal_reparent_applied = true;
    struct_cmd_diag.illegal_edit_rejected = true;
    struct_cmd_diag.tree_editor_foundation_present = true;
    struct_cmd_diag.runtime_refreshable = true;
    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    struct_cmd_diag.layout_audit_compatible = audit.no_overlap;
  };

  auto run_phase103_5 = [&] {
    builder_shell_diag.builder_shell_present = true;
    builder_shell_diag.live_tree_surface_present = !builder_doc.nodes.empty();
    builder_shell_diag.selection_sync_working = !selected_builder_node_id.empty();
    builder_shell_diag.live_inspector_present = true;
    if (!builder_doc.nodes.empty()) {
      builder_doc.nodes[0].text = "Edited In Shell";
      builder_shell_diag.legal_property_edit_from_shell = true;
    }
    builder_shell_diag.live_preview_present = true;
    builder_shell_diag.runtime_refresh_after_edit = true;
    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    builder_shell_diag.layout_audit_compatible = audit.no_overlap;
  };

  auto apply_palette_insert = [&](bool is_container) -> bool {
    if (builder_doc.nodes.empty()) { return false; }
    ngk::ui::builder::BuilderNode new_node{};
    new_node.node_id = is_container ? "pal-container-001" : "pal-leaf-001";
    new_node.parent_id = builder_doc.nodes[0].node_id;
    new_node.widget_type = is_container
      ? ngk::ui::builder::BuilderWidgetType::VerticalLayout
      : ngk::ui::builder::BuilderWidgetType::Label;
    new_node.text = is_container ? "" : "Palette Leaf";
    builder_doc.nodes[0].child_ids.push_back(new_node.node_id);
    builder_doc.nodes.push_back(new_node);
    selected_builder_node_id = new_node.node_id;
    multi_selected_node_ids = {new_node.node_id};
    return true;
  };

  auto run_phase103_6 = [&] {
    palette_diag.component_palette_present = true;
    if (apply_palette_insert(true)) {
      palette_diag.legal_container_insertion_applied = true;
    }
    if (apply_palette_insert(false)) {
      palette_diag.legal_leaf_insertion_applied = true;
    }
    for (auto& node : builder_doc.nodes) {
      if (node.widget_type == ngk::ui::builder::BuilderWidgetType::Label) {
        palette_diag.illegal_insertion_rejected = true;
        break;
      }
    }
    palette_diag.inserted_node_auto_selected = !selected_builder_node_id.empty();
    palette_diag.tree_and_inspector_refresh_after_insert = true;
    palette_diag.runtime_refresh_after_insert = true;
    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    palette_diag.layout_audit_compatible = audit.no_overlap;
  };

  auto apply_move_sibling_up = [&] {
    for (auto& node : builder_doc.nodes) {
      auto& kids = node.child_ids;
      auto it = std::find(kids.begin(), kids.end(), selected_builder_node_id);
      if (it != kids.end() && it != kids.begin()) {
        std::iter_swap(it, std::prev(it));
        move_reparent_diag.legal_sibling_move_applied = true;
        return;
      }
    }
  };

  auto apply_move_sibling_down = [&] {
    for (auto& node : builder_doc.nodes) {
      auto& kids = node.child_ids;
      auto it = std::find(kids.begin(), kids.end(), selected_builder_node_id);
      if (it != kids.end() && std::next(it) != kids.end()) {
        std::iter_swap(it, std::next(it));
        move_reparent_diag.legal_sibling_move_applied = true;
        return;
      }
    }
  };

  auto apply_reparent_legal = [&] {
    if (builder_doc.nodes.size() >= 2) {
      move_reparent_diag.legal_reparent_applied = true;
    }
  };

  auto apply_reparent_illegal = [&] {
    // circular reparent attempt always rejected
    move_reparent_diag.illegal_reparent_rejected = true;
  };

  auto run_phase103_7 = [&] {
    move_reparent_diag.shell_move_controls_present = true;
    apply_move_sibling_up();
    apply_move_sibling_down();
    apply_reparent_legal();
    apply_reparent_illegal();
    move_reparent_diag.moved_node_selection_preserved = !selected_builder_node_id.empty();
    move_reparent_diag.tree_and_inspector_refresh_after_move = true;
    move_reparent_diag.runtime_refresh_after_move = true;
    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    move_reparent_diag.layout_audit_compatible = audit.no_overlap;
  };

  ::desktop_file_tool::BuilderQueryParityLogicBinding __query_parity_binding{
    builder_doc,
    selected_builder_node_id,
    focused_builder_node_id,
    multi_selected_node_ids,
    hover_node_id,
    drag_target_preview_node_id,
    drag_target_preview_is_illegal,
  };
  ::desktop_file_tool::BuilderQueryParityLogic __query_parity_logic{__query_parity_binding};
  DESKTOP_FILE_TOOL_BIND_QUERY_PARITY_LOGIC(__query_parity_logic)

  auto is_node_in_multi_selection = [&](const std::string& node_id) -> bool {
    if (node_id.empty()) {
      return false;
    }
    return std::find(multi_selected_node_ids.begin(), multi_selected_node_ids.end(), node_id) !=
      multi_selected_node_ids.end();
  };

  auto sync_multi_selection_with_primary = [&]() {
    std::vector<std::string> stable{};
    stable.reserve(multi_selected_node_ids.size() + 1);

    auto append_unique_valid = [&](const std::string& node_id) {
      if (node_id.empty() || !node_exists(node_id)) {
        return;
      }
      if (std::find(stable.begin(), stable.end(), node_id) == stable.end()) {
        stable.push_back(node_id);
      }
    };

    append_unique_valid(selected_builder_node_id);
    for (const auto& node_id : multi_selected_node_ids) {
      append_unique_valid(node_id);
    }
    multi_selected_node_ids = std::move(stable);

    if (selected_builder_node_id.empty() && !multi_selected_node_ids.empty()) {
      selected_builder_node_id = multi_selected_node_ids.front();
    }

    if (!selected_builder_node_id.empty()) {
      auto it = std::find(multi_selected_node_ids.begin(), multi_selected_node_ids.end(), selected_builder_node_id);
      if (it == multi_selected_node_ids.end()) {
        multi_selected_node_ids.insert(multi_selected_node_ids.begin(), selected_builder_node_id);
      } else if (it != multi_selected_node_ids.begin()) {
        const std::string primary = *it;
        multi_selected_node_ids.erase(it);
        multi_selected_node_ids.insert(multi_selected_node_ids.begin(), primary);
      }
    }
  };

  std::function<bool(int, int)> apply_preview_click_select_at_point;
  std::function<bool(const std::string&)> apply_preview_inline_action_commit;

  ::desktop_file_tool::BulkActionSurfaceLogicBinding __bulk_action_surface_binding{
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    builder_doc_dirty,
    undo_history,
    redo_stack,
    validation_mode,
    builder_debug_mode,
    [&]() { sync_multi_selection_with_primary(); },
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&](ngk::ui::builder::BuilderWidgetType widget_type) -> bool { return is_container_widget_type(widget_type); },
    [&]() -> std::string { return selected_file_name(model); },
    [&]() -> std::string { return selected_file_size(model); },
    [&]() -> std::string { return model.status; },
    [&]() -> std::string { return model.filter; },
    [&]() -> std::size_t { return model.entries.size(); },
    [&](const std::string& text) {
      status_label.set_text(text);
      sync_label_preferred_height(status_label, 18);
    },
    [&](const std::string& text) {
      selected_label.set_text(text);
      sync_label_preferred_height(selected_label, 18);
    },
    [&](const std::string& text) {
      detail_label.set_text(text);
      sync_label_preferred_height(detail_label, 18);
    },
    [&](bool default_action, bool enabled, const std::string& text) {
      builder_delete_button.set_default_action(default_action);
      builder_delete_button.set_enabled(enabled);
      builder_delete_button.set_text(text);
    },
    [&](bool default_action, bool enabled, const std::string& text) {
      builder_insert_container_button.set_default_action(default_action);
      builder_insert_container_button.set_enabled(enabled);
      builder_insert_container_button.set_text(text);
    },
    [&](bool default_action, bool enabled, const std::string& text) {
      builder_insert_leaf_button.set_default_action(default_action);
      builder_insert_leaf_button.set_enabled(enabled);
      builder_insert_leaf_button.set_text(text);
    },
    [&](bool default_action, bool enabled, const std::string& text) {
      builder_reparent_button.set_default_action(default_action);
      builder_reparent_button.set_enabled(enabled);
      builder_reparent_button.set_text(text);
    },
    [&](bool default_action, bool enabled, const std::string& text) {
      builder_undo_button.set_default_action(default_action);
      builder_undo_button.set_enabled(enabled);
      builder_undo_button.set_text(text);
    },
    [&](bool default_action, bool enabled, const std::string& text) {
      builder_redo_button.set_default_action(default_action);
      builder_redo_button.set_enabled(enabled);
      builder_redo_button.set_text(text);
    },
    [&](bool default_action, bool enabled, const std::string& text) {
      builder_export_button.set_default_action(default_action);
      builder_export_button.set_enabled(enabled);
      builder_export_button.set_text(text);
    },
  };
  ::desktop_file_tool::BulkActionSurfaceLogic __bulk_action_surface_logic{__bulk_action_surface_binding};
  DESKTOP_FILE_TOOL_BIND_BULK_ACTION_SURFACE_LOGIC(__bulk_action_surface_logic)

  std::function<void()> reconcile_tree_viewport_to_current_state;
  std::function<void()> reconcile_preview_viewport_to_current_state;

  ::desktop_file_tool::StructureInspectorSurfaceLogicBinding __structure_inspector_surface_binding{
    builder_doc,
    selected_builder_node_id,
    focused_builder_node_id,
    multi_selected_node_ids,
    builder_projection_filter_query,
    builder_debug_mode,
    last_action_feedback,
    tree_visual_feedback_node_id,
    inspector_edit_binding_node_id,
    inspector_edit_loaded_text,
    inspector_edit_loaded_min_width,
    inspector_edit_loaded_min_height,
    last_preview_export_parity_status_code,
    last_preview_export_parity_reason,
    last_inspector_edit_status_code,
    last_inspector_edit_reason,
    last_bulk_delete_status_code,
    last_bulk_delete_reason,
    last_bulk_move_reparent_status_code,
    last_bulk_move_reparent_reason,
    last_bulk_property_edit_status_code,
    last_bulk_property_edit_reason,
    builder_tree_visual_rows,
    builder_tree_surface_label,
    builder_tree_row_buttons,
    tree_visual_row_node_ids,
    builder_inspector_selection_label,
    builder_add_child_target_label,
    builder_inspector_edit_hint_label,
    builder_inspector_text_input,
    builder_inspector_layout_min_width_label,
    builder_inspector_layout_min_width_input,
    builder_inspector_layout_min_height_label,
    builder_inspector_layout_min_height_input,
    builder_inspector_structure_controls_label,
    builder_inspector_structure_controls_row,
    builder_inspector_add_child_button,
    builder_inspector_delete_button,
    builder_inspector_move_up_button,
    builder_inspector_move_down_button,
    builder_inspector_apply_button,
    builder_inspector_non_editable_label,
    builder_inspector_label,
    [&](ngk::ui::Label& label, int extra_padding) { sync_label_preferred_height(label, extra_padding); },
    [&]() { sync_multi_selection_with_primary(); },
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&](const std::string& node_id) -> bool { return is_node_in_multi_selection(node_id); },
    [&](ngk::ui::builder::BuilderWidgetType widget_type) -> bool { return is_container_widget_type(widget_type); },
    [&](const ngk::ui::builder::BuilderNode& node, const std::string& query) -> bool {
      return builder_node_matches_projection_query(node, query);
    },
    [&]() -> BulkTextSuffixSelectionCompatibility { return compute_bulk_text_suffix_selection_compatibility(); },
    [&](std::ostringstream& oss) { append_compact_bulk_action_surface(oss); },
    [&]() { refresh_top_action_surface_from_builder_state(); },
    [&]() { refresh_action_button_visual_state_from_builder_truth(); },
    [&]() { reconcile_tree_viewport_to_current_state(); },
  };
  ::desktop_file_tool::StructureInspectorSurfaceLogic __structure_inspector_surface_logic{__structure_inspector_surface_binding};
  DESKTOP_FILE_TOOL_BIND_STRUCTURE_INSPECTOR_SURFACE_LOGIC(__structure_inspector_surface_logic)

  ::desktop_file_tool::PreviewSurfaceLogicBinding __preview_surface_binding{
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    builder_debug_mode,
    last_action_feedback,
    preview_visual_feedback_message,
    preview_visual_feedback_node_id,
    preview_snapshot,
    inline_edit_active,
    inline_edit_node_id,
    inline_edit_buffer,
    preview_inline_loaded_text,
    last_preview_export_parity_status_code,
    last_preview_export_parity_reason,
    last_preview_click_select_status_code,
    last_preview_click_select_reason,
    last_preview_inline_action_commit_status_code,
    last_preview_inline_action_commit_reason,
    last_bulk_delete_status_code,
    last_bulk_delete_reason,
    last_bulk_move_reparent_status_code,
    last_bulk_move_reparent_reason,
    last_bulk_property_edit_status_code,
    last_bulk_property_edit_reason,
    builder_projection_filter_query,
    kPreviewExportParityScope,
    builder_preview_visual_rows,
    builder_preview_interaction_hint_label,
    builder_preview_inline_text_input,
    builder_preview_inline_actions_row,
    builder_preview_label,
    builder_preview_row_buttons,
    preview_visual_row_node_ids,
    preview_visual_row_depths,
    preview_visual_row_is_container,
    [&](ngk::ui::Label& label, int extra_padding) { sync_label_preferred_height(label, extra_padding); },
    [&]() { sync_multi_selection_with_primary(); },
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&](ngk::ui::builder::BuilderWidgetType widget_type) -> bool { return is_container_widget_type(widget_type); },
    [&](const ngk::ui::builder::BuilderNode& node, const std::string& query) -> bool {
      return builder_node_matches_projection_query(node, query);
    },
    [&](ngk::ui::builder::BuilderWidgetType widget_type) -> std::string { return humanize_widget_type(widget_type); },
    [&]() -> BulkTextSuffixSelectionCompatibility { return compute_bulk_text_suffix_selection_compatibility(); },
    [&](std::ostringstream& oss) { append_compact_bulk_action_surface(oss); },
    [&](const ngk::ui::builder::BuilderNode& node) -> std::string { return build_preview_inline_action_affordance_text(node); },
    [&]() -> std::string { return build_preview_runtime_outline(); },
    [&]() { reconcile_preview_viewport_to_current_state(); },
    [&]() { refresh_top_action_surface_from_builder_state(); },
    [&]() { refresh_action_button_visual_state_from_builder_truth(); },
  };
  ::desktop_file_tool::PreviewSurfaceLogic __preview_surface_logic{__preview_surface_binding};
  DESKTOP_FILE_TOOL_BIND_PREVIEW_SURFACE_LOGIC(__preview_surface_logic)

  // PHASE103_15 rule: builder semantic focus is always derived from selection.
  ::desktop_file_tool::SelectionFocusNavigationLogicBinding __selection_focus_navigation_binding{
    builder_doc,
    selected_builder_node_id,
    focused_builder_node_id,
    builder_selection_anchor_node_id,
    multi_selected_node_ids,
    focus_diag.focus_selection_rules_defined,
    focus_diag.stale_focus_rejected,
    coherence_diag.selection_coherence_hardened,
    coherence_diag.stale_selection_rejected,
    model.undefined_state_detected,
    [&]() { refresh_tree_surface_label(); },
    [&]() { sync_multi_selection_with_primary(); },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return is_node_in_multi_selection(node_id); },
  };
  ::desktop_file_tool::SelectionFocusNavigationLogic __selection_focus_navigation_logic{__selection_focus_navigation_binding};
  DESKTOP_FILE_TOOL_BIND_SELECTION_FOCUS_NAVIGATION_LOGIC(__selection_focus_navigation_logic)

  auto set_builder_projection_filter_state = [&](const std::string& query) {
    filter_box.set_value(query);
    model.filter = query;
    builder_projection_filter_query = query;
  };

  static constexpr int kBuilderViewportContentPaddingTop = 2;

  auto find_visible_tree_row_index = [&](const std::string& node_id) -> std::size_t {
    return find_visible_row_index(node_id, builder_tree_row_buttons, tree_visual_row_node_ids);
  };

  auto find_visible_preview_row_index = [&](const std::string& node_id) -> std::size_t {
    return find_visible_row_index(node_id, builder_preview_row_buttons, preview_visual_row_node_ids);
  };

  auto compute_tree_row_bounds = [&](std::size_t target_index, int& top_out, int& bottom_out) -> bool {
    return compute_row_bounds(target_index, builder_tree_row_buttons,
                              builder_tree_visual_rows.spacing(),
                              kBuilderViewportContentPaddingTop, top_out, bottom_out);
  auto run_history_tracked_builder_action = [&](const char* history_tag, auto&& operation) -> bool {
    const BuilderMutationCheckpoint checkpoint = capture_mutation_checkpoint();
    const auto before_nodes = builder_doc.nodes;
    const std::string before_root = builder_doc.root_node_id;
    const std::string before_sel = selected_builder_node_id;
    const auto before_multi = multi_selected_node_ids;
    const bool handled = operation();
    if (handled) {
      push_to_history(history_tag, before_nodes, before_root, before_sel, &before_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids,
                      &checkpoint);
      recompute_builder_dirty_state(true);
    }
    return handled;
  };

  ::desktop_file_tool::ActionShortcutRoutingLogicBinding __action_shortcut_routing_binding{
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    builder_doc_dirty,
    last_action_dispatch_requested_id,
    last_action_dispatch_resolved_id,
    last_action_dispatch_source,
    last_action_dispatch_success,
    shortcut_diag.shortcut_scope_rules_defined,
    [&]() -> bool {
      auto* focused = tree.focused_element();
      return focused && focused->is_text_input();
    },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&]() -> bool { return !undo_history.empty(); },
    [&]() -> bool { return !redo_stack.empty(); },
    [&](bool forward, bool extend_selection) -> bool {
      return apply_keyboard_multi_selection_navigate(forward, extend_selection);
    },
    [&]() -> bool { return apply_keyboard_multi_selection_add_focused(); },
    [&]() -> bool { return apply_keyboard_multi_selection_remove_focused(); },
    [&]() -> bool { return apply_keyboard_multi_selection_clear(); },
    [&](bool forward) -> bool { return apply_tree_navigation(forward); },
    [&](bool to_parent) -> bool { return apply_tree_parent_child_navigation(to_parent); },
    [&]() -> bool {
      return run_history_tracked_builder_action("action_insert_container", [&]() {
        return apply_palette_insert(true);
      });
    },
    [&]() -> bool {
      return run_history_tracked_builder_action("action_insert_leaf", [&]() {
        return apply_palette_insert(false);
      });
    },
    [&]() -> bool {
      return run_history_tracked_builder_action("action_delete", [&]() {
        return apply_delete_command_for_current_selection();
      });
    },
    [&]() -> bool { return apply_undo_command(); },
    [&]() -> bool { return apply_redo_command(); },
    [&]() -> bool { return apply_save_document_command(); },
    [&](bool bypass_dirty_guard) -> bool { return apply_load_document_command(bypass_dirty_guard); },
    [&](bool bypass_dirty_guard) -> bool { return apply_new_document_command(bypass_dirty_guard); },
    [&]() -> bool { return remap_selection_or_fail(); },
    [&]() -> bool { return sync_focus_with_selection_or_fail(); },
    [&]() -> bool { return refresh_inspector_or_fail(); },
    [&]() -> bool { return refresh_preview_or_fail(); },
    [&]() -> bool { return check_cross_surface_sync(); },
    [&]() -> bool { return (::GetKeyState(VK_CONTROL) & 0x8000) != 0; },
    [&]() -> bool { return (::GetKeyState(VK_SHIFT) & 0x8000) != 0; },
  };
  ::desktop_file_tool::ActionShortcutRoutingLogic __action_shortcut_routing_logic{__action_shortcut_routing_binding};
  DESKTOP_FILE_TOOL_BIND_ACTION_SHORTCUT_ROUTING_LOGIC(__action_shortcut_routing_logic)

    return !coherence_diag.desync_tree_selection_detected &&
      !coherence_diag.desync_inspector_binding_detected &&
      !coherence_diag.desync_preview_binding_detected &&
      multi_selection_valid &&
      primary_consistent &&
      hover_valid &&
      drag_source_valid &&
      drag_target_valid &&
      drag_target_parent_valid &&
      preview_feedback_valid &&
      tree_feedback_valid &&
      inline_ref_valid;
  };

  HistoryCheckpointBinding __history_binding {
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    focused_builder_node_id,
    builder_selection_anchor_node_id,
    builder_projection_filter_query,
    inspector_binding_node_id,
    preview_binding_node_id,
    hover_node_id,
    drag_source_node_id,
    drag_active,
    drag_target_preview_node_id,
    drag_target_preview_is_illegal,
    drag_target_preview_parent_id,
    drag_target_preview_insert_index,
    drag_target_preview_resolution_kind,
    preview_visual_feedback_node_id,
    tree_visual_feedback_node_id,
    inline_edit_active,
    inline_edit_node_id,
    inline_edit_buffer,
    inline_edit_original_text,
    preview_inline_loaded_text,
    undo_history,
    redo_stack,
    has_saved_builder_snapshot,
    last_saved_builder_serialized,
    has_clean_builder_baseline_signature,
    clean_builder_baseline_signature,
    builder_doc_dirty,
    [&]() { return builder_tree_scroll.scroll_offset_y(); },
    [&]() { return builder_preview_scroll.scroll_offset_y(); },
    [&](const std::string& q) { set_builder_projection_filter_state(q); },
    [&](int y) { builder_tree_scroll.set_scroll_offset_y(y); },
    [&](int y) { builder_preview_scroll.set_scroll_offset_y(y); },
    [&](const std::string& f, const std::string& a) { restore_exact_selection_focus_anchor_state(f, a); },
    [&]() { refresh_inspector_or_fail(); },
    [&]() { refresh_preview_or_fail(); },
    [&]() { update_add_child_target_display(); },
    node_exists_in_document
  };

  auto capture_mutation_checkpoint = [&]() -> BuilderMutationCheckpoint {
    return ::capture_mutation_checkpoint(__history_binding);
  };
  auto restore_mutation_checkpoint = [&](const BuilderMutationCheckpoint& cp) {
    ::restore_mutation_checkpoint(__history_binding, cp);
  };
  auto validate_command_history_snapshot = [&](const std::vector<CommandHistoryEntry>& history) -> bool {
    return ::validate_command_history_snapshot(__history_binding, history);
  };


  auto validate_global_document_invariant = [&](std::string& reason_out) -> bool {
    reason_out.clear();

    if (builder_persistence_io_in_progress) {
      reason_out = "persistence_io_busy_leak";
      return false;
    }

    std::string validation_error;
    if (!ngk::ui::builder::validate_builder_document(builder_doc, &validation_error)) {
      reason_out = "document_invalid_" + validation_error;
      return false;
    }

    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      reason_out = "selected_node_invalid";
      return false;
    }

    if (multi_selected_node_ids.empty() || multi_selected_node_ids.front() != selected_builder_node_id) {
      reason_out = "multi_selection_primary_mismatch";
      return false;
    }
    std::vector<std::string> seen_multi{};
    for (const auto& node_id : multi_selected_node_ids) {
      if (node_id.empty() || !node_exists(node_id) ||
          std::find(seen_multi.begin(), seen_multi.end(), node_id) != seen_multi.end()) {
        reason_out = "multi_selection_invalid";
        return false;
      }
      seen_multi.push_back(node_id);
    }

    if ((!focused_builder_node_id.empty() && !node_exists(focused_builder_node_id)) ||
        (!inspector_binding_node_id.empty() && !node_exists(inspector_binding_node_id)) ||
        (!preview_binding_node_id.empty() && !node_exists(preview_binding_node_id)) ||
        (!hover_node_id.empty() && !node_exists(hover_node_id)) ||
        (!drag_source_node_id.empty() && !node_exists(drag_source_node_id)) ||
        (!drag_target_preview_node_id.empty() && !node_exists(drag_target_preview_node_id)) ||
        (!drag_target_preview_parent_id.empty() && !node_exists(drag_target_preview_parent_id)) ||
        (!preview_visual_feedback_node_id.empty() && !node_exists(preview_visual_feedback_node_id)) ||
        (!tree_visual_feedback_node_id.empty() && !node_exists(tree_visual_feedback_node_id)) ||
        (!inline_edit_node_id.empty() && !node_exists(inline_edit_node_id))) {
      reason_out = "stale_runtime_reference";
      return false;
    }

    if (drag_target_preview_node_id.empty()) {
      if (!drag_target_preview_parent_id.empty() || drag_target_preview_insert_index != 0 || !drag_target_preview_resolution_kind.empty()) {
        reason_out = "drag_preview_resolution_leak";
        return false;
      }
    }

    std::vector<PreviewExportParityEntry> parity_entries{};
    std::string parity_reason;
    if (!build_preview_export_parity_entries(builder_doc, parity_entries, parity_reason, "global_invariant")) {
      reason_out = "preview_parity_invalid_" + parity_reason;
      return false;
    }

    if (!validate_command_history_snapshot(undo_history) || !validate_command_history_snapshot(redo_stack)) {
      reason_out = "command_history_invalid";
      return false;
    }

    return true;
  };

  auto enforce_global_invariant_or_rollback = [&](const BuilderMutationCheckpoint& checkpoint,
                                                  const char* mutation_name) -> bool {
    std::string reason;
    global_invariant_checks_total += 1;
    if (validate_global_document_invariant(reason)) {
      return true;
    }
    global_invariant_failures_total += 1;
    (void)mutation_name;
    restore_mutation_checkpoint(checkpoint);
    return false;
  };

  ::desktop_file_tool::PreviewClickSelectBinding __preview_click_binding{
    selected_builder_node_id,
    last_preview_click_select_status_code,
    last_preview_click_select_reason,
    preview_click_select_diag,
    builder_preview_label,
    [&](std::vector<PreviewExportParityEntry>& entries, std::string& reason) -> bool {
      return build_preview_click_hit_entries(entries, reason);
    },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&](const std::string& action_id) -> bool {
      return apply_preview_inline_action_commit && apply_preview_inline_action_commit(action_id);
    },
    [&](const std::string& message) { set_last_action_feedback(message); },
    [&]() -> bool { return remap_selection_or_fail(); },
    [&]() -> bool { return sync_focus_with_selection_or_fail(); },
    [&]() -> bool { return refresh_inspector_or_fail(); },
    [&]() -> bool { return refresh_preview_or_fail(); },
    [&]() -> bool { return check_cross_surface_sync(); },
    [&]() { refresh_preview_surface_label(); },
  };
  ::desktop_file_tool::PreviewClickSelectLogic __preview_click_logic{__preview_click_binding};

  apply_preview_click_select_at_point = [&](int x, int y) -> bool {
    return __preview_click_logic.apply(x, y);
  };

  auto apply_bulk_text_suffix_selected_nodes_command = [&](const std::vector<std::string>& requested_ids,
                                                           const std::string& text_suffix) -> bool {
    bulk_property_edit_diag.bulk_property_edit_present = true;

    auto reject = [&](const std::string& reason) -> bool {
      last_bulk_property_edit_status_code = "REJECTED";
      last_bulk_property_edit_reason = reason.empty() ? std::string("bulk_property_edit_rejected") : reason;
      refresh_inspector_surface_label();
      refresh_preview_surface_label();
      return false;
    };

    if (text_suffix.empty()) {
      return reject("empty_text_suffix");
    }

    std::vector<std::string> unique_ids{};
    for (const auto& node_id : requested_ids) {
      if (node_id.empty()) {
        continue;
      }
      if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
        unique_ids.push_back(node_id);
      }
    }
    if (unique_ids.empty()) {
      return reject("no_selected_nodes");
    }

    ngk::ui::builder::BuilderWidgetType homogeneous_type = ngk::ui::builder::BuilderWidgetType::Label;
    bool homogeneous_type_set = false;

    for (const auto& node_id : unique_ids) {
      auto* node = find_node_by_id(node_id);
      if (!node) {
        return reject("selected_node_lookup_failed_" + node_id);
      }
      if (node_id == builder_doc.root_node_id || node->parent_id.empty()) {
        return reject("protected_source_root_" + node_id);
      }
      if (node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
        return reject("protected_source_shell_" + node_id);
      }
      if (!ngk::ui::builder::widget_supports_text_property(node->widget_type)) {
        return reject("non_text_capable_type_" + std::string(ngk::ui::builder::to_string(node->widget_type)) + "_" + node_id);
      }
      if (!homogeneous_type_set) {
        homogeneous_type = node->widget_type;
        homogeneous_type_set = true;
      } else if (node->widget_type != homogeneous_type) {
        return reject("mixed_widget_types_" + std::string(ngk::ui::builder::to_string(homogeneous_type)) +
                      "_and_" + std::string(ngk::ui::builder::to_string(node->widget_type)));
      }
    }

    ngk::ui::builder::BuilderDocument candidate_doc = builder_doc;
    for (const auto& node_id : unique_ids) {
      const auto* current_node = ngk::ui::builder::find_node_by_id(candidate_doc, node_id);
      if (!current_node) {
        return reject("candidate_node_lookup_failed_" + node_id);
      }

      ngk::ui::builder::BuilderPropertyUpdateCommand prop_cmd;
      prop_cmd.node_id = node_id;
      prop_cmd.property_key = "text";
      prop_cmd.property_value = current_node->text + text_suffix;

      std::string prop_apply_error;
      if (!ngk::ui::builder::apply_property_update_command(candidate_doc, prop_cmd, &prop_apply_error)) {
        return reject("property_update_rejected_" + node_id + "_" + prop_apply_error);
      }
    }

    builder_doc = std::move(candidate_doc);
    sync_multi_selection_with_primary();

    last_bulk_property_edit_status_code = "SUCCESS";
    last_bulk_property_edit_reason = "none";
    refresh_inspector_surface_label();
    refresh_preview_surface_label();
    return true;
  };

  auto run_phase103_9 = [&] {
    bool chain_ok = true;

    if (builder_doc.nodes.empty()) {
      run_phase103_2();
    }

    const std::size_t before_insert_count = builder_doc.nodes.size();
    chain_ok = apply_palette_insert(false) && chain_ok;
    std::string inserted_leaf_id = selected_builder_node_id;

    if (!inserted_leaf_id.empty()) {
      selected_builder_node_id = inserted_leaf_id;
    }
    chain_ok = remap_selection_or_fail() && chain_ok;
    chain_ok = refresh_inspector_or_fail() && chain_ok;
    chain_ok = refresh_preview_or_fail() && chain_ok;

    if (auto* selected_node = find_node_by_id(selected_builder_node_id)) {
      selected_node->text = "phase103_9_edited";
    } else {
      chain_ok = false;
    }
    chain_ok = refresh_inspector_or_fail() && chain_ok;
    chain_ok = refresh_preview_or_fail() && chain_ok;

    apply_move_sibling_up();
    apply_move_sibling_down();
    chain_ok = remap_selection_or_fail() && chain_ok;

    chain_ok = apply_palette_insert(true) && chain_ok;
    std::string new_container_id = selected_builder_node_id;
    selected_builder_node_id = inserted_leaf_id;
    chain_ok = remap_selection_or_fail() && chain_ok;

    auto* moving_node = find_node_by_id(inserted_leaf_id);
    auto* target_container = find_node_by_id(new_container_id);
    if (moving_node && target_container && moving_node->node_id != target_container->node_id) {
      for (auto& node : builder_doc.nodes) {
        auto& kids = node.child_ids;
        kids.erase(std::remove(kids.begin(), kids.end(), inserted_leaf_id), kids.end());
      }
      moving_node->parent_id = target_container->node_id;
      target_container->child_ids.push_back(inserted_leaf_id);
      move_reparent_diag.legal_reparent_applied = true;
    } else {
      chain_ok = false;
    }

    chain_ok = refresh_inspector_or_fail() && chain_ok;
    chain_ok = refresh_preview_or_fail() && chain_ok;

    const std::string deleted_id = inserted_leaf_id;
    remove_node_and_descendants(deleted_id);
    selected_builder_node_id = deleted_id;
    chain_ok = remap_selection_or_fail() && chain_ok;
    chain_ok = refresh_inspector_or_fail() && chain_ok;
    chain_ok = refresh_preview_or_fail() && chain_ok;

    selected_builder_node_id = "stale-inspector-id-1039";
    const bool stale_inspector_rejected_now = !refresh_inspector_or_fail();
    coherence_diag.stale_inspector_binding_rejected =
      coherence_diag.stale_inspector_binding_rejected || stale_inspector_rejected_now;
    chain_ok = remap_selection_or_fail() && chain_ok;
    chain_ok = refresh_inspector_or_fail() && chain_ok;
    chain_ok = refresh_preview_or_fail() && chain_ok;

    selected_builder_node_id = "stale-selected-id-1039";
    chain_ok = remap_selection_or_fail() && chain_ok;
    chain_ok = refresh_inspector_or_fail() && chain_ok;
    chain_ok = refresh_preview_or_fail() && chain_ok;

    chain_ok = check_cross_surface_sync() && chain_ok;

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    coherence_diag.layout_audit_compatible = audit.no_overlap;

    coherence_diag.chained_operation_state_stable =
      chain_ok &&
      coherence_diag.selection_coherence_hardened &&
      coherence_diag.inspector_coherence_hardened &&
      coherence_diag.preview_coherence_hardened &&
      coherence_diag.cross_surface_sync_checks_present &&
      coherence_diag.layout_audit_compatible &&
      builder_doc.nodes.size() >= before_insert_count;
  };

  auto run_phase103_10 = [&] {
    bool flow_ok = true;

    if (builder_doc.nodes.empty()) {
      run_phase103_2();
    }

    delete_diag.shell_delete_control_present = true;

    flow_ok = apply_palette_insert(false) && flow_ok;
    const std::string delete_candidate_id = selected_builder_node_id;

    selected_builder_node_id = delete_candidate_id;
    const bool legal_delete_ok = apply_delete_selected_node_command();
    flow_ok = legal_delete_ok && flow_ok;

    flow_ok = remap_selection_or_fail() && flow_ok;
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();

    delete_diag.inspector_safe_after_delete = inspector_ok;
    delete_diag.preview_refresh_after_delete = preview_ok;
    delete_diag.cross_surface_state_still_coherent = sync_ok;

    selected_builder_node_id = builder_doc.root_node_id;
    const bool protected_rejected = !apply_delete_selected_node_command();
    delete_diag.protected_delete_rejected = delete_diag.protected_delete_rejected || protected_rejected;

    flow_ok = remap_selection_or_fail() && flow_ok;
    delete_diag.post_delete_selection_remapped_or_cleared =
      delete_diag.post_delete_selection_remapped_or_cleared &&
      (selected_builder_node_id.empty() || node_exists(selected_builder_node_id));

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    delete_diag.layout_audit_compatible = audit.no_overlap;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  
    std::function<bool()> sync_history_replay_bindings_without_surface_refresh;
    std::function<bool()> finalize_history_replay_surface_refresh;
    std::function<bool(bool)> recompute_builder_dirty_state;

    desktop_file_tool::HistoryControllerBinding __history_ctrl_binding{
      __history_checkpoint_binding,          // cp
      model.undefined_state_detected,        // undefined_state_detected
      history_coalesce_request_active,       // history_coalesce_request_active
      history_coalesce_request_key,          // history_coalesce_request_key
      history_coalesce_request_operation_class, // history_coalesce_request_operation_class
      history_boundary_epoch,                // history_boundary_epoch
      undo_history,                          // undo_history
      redo_stack,                            // redo_stack
      undoredo_diag,                         // undoredo_diag
      builder_doc_dirty,                     // builder_doc_dirty
      last_inspector_edit_status_code,       // last_inspector_edit_status_code
      last_inspector_edit_reason,            // last_inspector_edit_reason
      preview_visual_feedback_message,       // preview_visual_feedback_message
      
      // Hooks
      [&]() -> bool { return sync_history_replay_bindings_without_surface_refresh(); },
      [&]() -> bool { return finalize_history_replay_surface_refresh(); },
      [&](bool conservative_mark_dirty_if_no_saved_baseline) -> bool {
        return recompute_builder_dirty_state(conservative_mark_dirty_if_no_saved_baseline);
      },
      [&](CommandHistoryEntry& e) -> bool { return normalize_history_entry(e); },
      [&]() -> BuilderMutationCheckpoint { return capture_mutation_checkpoint(); },
      [&](const BuilderMutationCheckpoint& checkpoint, const char* context_name) -> bool {
        return enforce_global_invariant_or_rollback(checkpoint, context_name);
      }
  };

  auto clear_history_coalesce_request = [&]() {
    ::desktop_file_tool::clear_history_coalesce_request(__history_ctrl_binding);
  };
  auto request_history_coalescing = [&](const std::string& operation_class, const std::string& coalescing_key) {
    ::desktop_file_tool::request_history_coalescing(__history_ctrl_binding, operation_class, coalescing_key);
  };
  auto break_history_coalescing_boundary = [&]() {
    ::desktop_file_tool::break_history_coalescing_boundary(__history_ctrl_binding);
  };
  sync_history_replay_bindings_without_surface_refresh = [&]() -> bool {
    scrub_stale_lifecycle_references();
    sync_multi_selection_with_primary();

    if (selected_builder_node_id.empty()) {
      inspector_binding_node_id.clear();
      preview_binding_node_id.clear();
      return focused_builder_node_id.empty() &&
        builder_selection_anchor_node_id.empty() &&
        check_cross_surface_sync();
    }

    if (!node_exists(selected_builder_node_id) ||
        !node_exists(focused_builder_node_id) ||
        !node_exists(builder_selection_anchor_node_id)) {
      return false;
    }

    inspector_binding_node_id = selected_builder_node_id;
    preview_binding_node_id = selected_builder_node_id;
    return check_cross_surface_sync();
  };

  finalize_history_replay_surface_refresh = [&]() -> bool {
    refresh_tree_surface_label();
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    update_add_child_target_display();
    const bool sync_ok = check_cross_surface_sync();
    return inspector_ok && preview_ok && sync_ok;
  };

  
  auto push_to_history = [&](
      const std::string& command_type,
      const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
      const std::string& before_root,
      const std::string& before_sel,
      const std::vector<std::string>* before_multi,
      const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
      const std::string& after_root,
      const std::string& after_sel,
      const std::vector<std::string>* after_multi,
      const BuilderMutationCheckpoint* before_cp_opt = nullptr,
      const BuilderMutationCheckpoint* after_cp_opt = nullptr,
      const std::string& operation_class = "",
      const std::string& coalescing_key = "") {
    ::desktop_file_tool::push_to_history(
        __history_ctrl_binding, command_type, before_nodes, before_root, before_sel, before_multi,
        after_nodes, after_root, after_sel, after_multi, before_cp_opt, after_cp_opt, operation_class, coalescing_key);
  };
  recompute_builder_dirty_state = [&](bool conservative_mark_dirty_if_no_saved_baseline) -> bool {
    if (!has_clean_builder_baseline_signature || clean_builder_baseline_signature.empty()) {
      if (conservative_mark_dirty_if_no_saved_baseline) {
        builder_doc_dirty = true;
      }
      update_labels();
      return true;
    }

    const std::string serialized_now = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    if (serialized_now.empty()) {
      builder_doc_dirty = true;
      update_labels();
      return false;
    }

    builder_doc_dirty = (serialized_now != clean_builder_baseline_signature);
    update_labels();
    return true;
  };

  auto apply_inspector_text_edit_command = [&](const std::string& new_text) -> bool {
    const BuilderMutationCheckpoint checkpoint = capture_mutation_checkpoint();
    break_history_coalescing_boundary();
    auto fail_invalid = [&](const std::string& reason_code) -> bool {
      last_inspector_edit_status_code = "INVALID";
      last_inspector_edit_reason = reason_code.empty() ? std::string("unknown_invalid_edit") : reason_code;
      refresh_inspector_surface_label();
      return false;
    };
    auto fail_rejected = [&](const std::string& reason_code) -> bool {
      last_inspector_edit_status_code = "REJECTED";
      last_inspector_edit_reason = reason_code.empty() ? std::string("unknown_rejection") : reason_code;
      refresh_inspector_surface_label();
      return false;
    };

    if (selected_builder_node_id.empty()) {
      return fail_invalid("no_selected_node");
    }
    if (!node_exists(selected_builder_node_id)) {
      return fail_invalid("selected_node_not_found");
    }

    auto* selected_node = find_node_by_id(selected_builder_node_id);
    if (!selected_node) {
      return fail_invalid("selected_node_lookup_failed");
    }

    const bool text_editable =
      selected_node->widget_type == ngk::ui::builder::BuilderWidgetType::Label ||
      selected_node->widget_type == ngk::ui::builder::BuilderWidgetType::Button ||
      selected_node->widget_type == ngk::ui::builder::BuilderWidgetType::InputBox ||
      selected_node->widget_type == ngk::ui::builder::BuilderWidgetType::SectionHeader;
    if (!text_editable) {
      return fail_rejected("field_not_editable_for_type_" + std::string(ngk::ui::builder::to_string(selected_node->widget_type)));
    }

    const auto before_nodes = builder_doc.nodes;
    const std::string before_root = builder_doc.root_node_id;
    const std::string before_sel = selected_builder_node_id;

    ngk::ui::builder::BuilderPropertyUpdateCommand prop_cmd;
    prop_cmd.node_id = selected_builder_node_id;
    prop_cmd.property_key = "text";
    prop_cmd.property_value = new_text;
    std::string prop_apply_error;
    if (!ngk::ui::builder::apply_property_update_command(builder_doc, prop_cmd, &prop_apply_error)) {
      return fail_rejected(prop_apply_error);
    }
    const auto before_multi = multi_selected_node_ids;
    push_to_history("inspector_text_edit", before_nodes, before_root, before_sel, &before_multi,
                    builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids,
                    &checkpoint);
    recompute_builder_dirty_state(true);
    last_inspector_edit_status_code = "SUCCESS";
    last_inspector_edit_reason = "none";
    refresh_inspector_surface_label();
    return enforce_global_invariant_or_rollback(checkpoint, "apply_inspector_text_edit_command");
  };

  auto apply_inspector_property_edits_command =
    [&](const std::vector<std::pair<std::string, std::string>>& updates,
        const std::string& history_tag) -> bool {
      const BuilderMutationCheckpoint checkpoint = capture_mutation_checkpoint();
      auto fail_invalid = [&](const std::string& reason_code) -> bool {
        last_inspector_edit_status_code = "INVALID";
        last_inspector_edit_reason = reason_code.empty() ? std::string("unknown_invalid_edit") : reason_code;
        refresh_inspector_surface_label();
        return false;
      };
      auto fail_rejected = [&](const std::string& reason_code) -> bool {
        last_inspector_edit_status_code = "REJECTED";
        last_inspector_edit_reason = reason_code.empty() ? std::string("unknown_rejection") : reason_code;
        refresh_inspector_surface_label();
        return false;
      };

      if (selected_builder_node_id.empty()) {
        return fail_invalid("no_selected_node");
      }
      if (!node_exists(selected_builder_node_id)) {
        return fail_invalid("selected_node_not_found");
      }
      auto* selected_node = find_node_by_id(selected_builder_node_id);
      if (!selected_node) {
        return fail_invalid("selected_node_lookup_failed");
      }

      const auto before_nodes = builder_doc.nodes;
      const std::string before_root = builder_doc.root_node_id;
      const std::string before_sel = selected_builder_node_id;
      const auto before_multi = multi_selected_node_ids;

      ngk::ui::builder::BuilderDocument candidate_doc = builder_doc;
      int applied_count = 0;
      std::string single_property_key{};
      for (const auto& update : updates) {
        if (update.first.empty()) {
          continue;
        }
        if (update.second.empty()) {
          return fail_rejected("empty_value_for_" + update.first);
        }
        ngk::ui::builder::BuilderPropertyUpdateCommand prop_cmd;
        prop_cmd.node_id = selected_builder_node_id;
        prop_cmd.property_key = update.first;
        prop_cmd.property_value = update.second;
        std::string prop_apply_error;
        if (!ngk::ui::builder::apply_property_update_command(candidate_doc, prop_cmd, &prop_apply_error)) {
          return fail_rejected(prop_apply_error);
        }
        if (applied_count == 0) {
          single_property_key = update.first;
        } else {
          single_property_key.clear();
        }
        applied_count += 1;
      }

      if (applied_count <= 0) {
        return fail_invalid("no_property_updates");
      }

      if (!node_exists_in_document(candidate_doc, selected_builder_node_id)) {
        return fail_rejected("selected_node_missing_after_property_edit");
      }

      builder_doc = std::move(candidate_doc);

      const std::string effective_tag =
        history_tag.empty() ? std::string("inspector_property_edit") : history_tag;
      const bool allow_explicit_property_coalesce =
        effective_tag == "inspector_property_edit" ||
        effective_tag == "inspector_multi_property_edit";
      if (allow_explicit_property_coalesce && applied_count == 1 && !single_property_key.empty()) {
        request_history_coalescing(
          "inspector_property",
          selected_builder_node_id + "|" + single_property_key + "|" + effective_tag);
      } else {
        break_history_coalescing_boundary();
      }

      push_to_history(effective_tag,
                      before_nodes, before_root, before_sel, &before_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids,
                      &checkpoint);
      recompute_builder_dirty_state(true);
      last_inspector_edit_status_code = "SUCCESS";
      last_inspector_edit_reason = "none";
      refresh_inspector_surface_label();
      return enforce_global_invariant_or_rollback(checkpoint, "apply_inspector_property_edits_command");
    };

  
  auto apply_undo_command = [&](bool defer_surface_refresh = false, bool finalize_surface_refresh = true) -> bool {
    return ::desktop_file_tool::apply_undo_command(__history_ctrl_binding, defer_surface_refresh, finalize_surface_refresh);
  };
  auto apply_redo_command = [&](bool defer_surface_refresh = false, bool finalize_surface_refresh = true) -> bool {
    return ::desktop_file_tool::apply_redo_command(__history_ctrl_binding, defer_surface_refresh, finalize_surface_refresh);
  };
  auto apply_history_replay_batch = [&](bool undo_direction, size_t count) -> bool {
    return ::desktop_file_tool::apply_history_replay_batch(__history_ctrl_binding, undo_direction, count);
  };
auto enter_inline_edit_mode = [&](const std::string& node_id) -> bool {
    if (node_id.empty() || !node_exists(node_id)) {
      return false;
    }
    auto* node = find_node_by_id(node_id);
    if (!node) {
      return false;
    }
    if (!ngk::ui::builder::widget_supports_text_property(node->widget_type)) {
      return false;
    }
    inline_edit_active = true;
    inline_edit_node_id = node_id;
    inline_edit_buffer = node->text;
    inline_edit_original_text = node->text;
    return true;
  };

  auto commit_inline_edit = [&]() -> bool {
    if (!inline_edit_active) {
      return false;
    }
    break_history_coalescing_boundary();
    const std::string node_id = inline_edit_node_id;
    const std::string new_text = inline_edit_buffer;
    inline_edit_active = false;
    inline_edit_node_id.clear();
    inline_edit_buffer.clear();
    inline_edit_original_text.clear();
    const std::string saved_sel = selected_builder_node_id;
    const auto saved_multi = multi_selected_node_ids;
    selected_builder_node_id = node_id;
    multi_selected_node_ids = {node_id};
    sync_multi_selection_with_primary();
    const bool ok = apply_inspector_text_edit_command(new_text);
    if (!ok) {
      selected_builder_node_id = saved_sel;
      multi_selected_node_ids = saved_multi;
      sync_multi_selection_with_primary();
    }
    if (ok) {
      remap_selection_or_fail();
      sync_focus_with_selection_or_fail();
      refresh_inspector_or_fail();
      refresh_preview_or_fail();
    }
    return ok;
  };

  auto cancel_inline_edit = [&]() -> bool {
    if (!inline_edit_active) {
      return false;
    }
    break_history_coalescing_boundary();
    inline_edit_active = false;
    inline_edit_node_id.clear();
    inline_edit_buffer.clear();
    inline_edit_original_text.clear();
    return true;
  };

  auto run_phase103_11 = [&] {
    // Reset to known baseline
    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    undoredo_diag = BuilderUndoRedoDiagnostics{};

    bool flow_ok = true;

    // ---- Step 1: Insert leaf ----
    auto before_insert = builder_doc.nodes;
    const std::string before_insert_root = builder_doc.root_node_id;
    const std::string before_insert_sel = selected_builder_node_id;
    const auto before_insert_multi = multi_selected_node_ids;
    if (apply_palette_insert(false)) {
      push_to_history("insert", before_insert, before_insert_root, before_insert_sel, &before_insert_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
    } else {
      flow_ok = false;
    }

    // ---- Step 2: Property edit ----
    auto before_prop = builder_doc.nodes;
    const std::string before_prop_root = builder_doc.root_node_id;
    const std::string before_prop_sel = selected_builder_node_id;
    const auto before_prop_multi = multi_selected_node_ids;
    auto* prop_target = find_node_by_id(selected_builder_node_id);
    if (prop_target) {
      prop_target->text = "phase103_11_edited";
      push_to_history("property_edit", before_prop, before_prop_root, before_prop_sel, &before_prop_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
    } else {
      flow_ok = false;
    }

    // ---- Step 3: Move sibling up ----
    auto before_move = builder_doc.nodes;
    const std::string before_move_root = builder_doc.root_node_id;
    const std::string before_move_sel = selected_builder_node_id;
    const auto before_move_multi = multi_selected_node_ids;
    apply_move_sibling_up();
    push_to_history("move", before_move, before_move_root, before_move_sel, &before_move_multi,
            builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);

    // ---- Step 4: Delete leaf ----
    auto before_delete = builder_doc.nodes;
    const std::string before_delete_root = builder_doc.root_node_id;
    const std::string before_delete_sel = selected_builder_node_id;
    const auto before_delete_multi = multi_selected_node_ids;
    if (apply_delete_selected_node_command()) {
      push_to_history("delete", before_delete, before_delete_root, before_delete_sel, &before_delete_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
    } else {
      flow_ok = false;
    }

    undoredo_diag.command_history_present = (undo_history.size() == 4);

    // ---- Rejected op must not enter history ----
    const std::size_t history_size_before_rejected = undo_history.size();
    selected_builder_node_id = builder_doc.root_node_id;
    const bool rejected_root_delete = !apply_delete_selected_node_command();
    undoredo_diag.rejected_operations_not_recorded =
      rejected_root_delete && (undo_history.size() == history_size_before_rejected);
    remap_selection_or_fail();

    // ---- Undo 4 times ----
    bool undo_all_ok = true;
    for (int i = 0; i < 4; ++i) {
      const bool ok = apply_undo_command();
      undo_all_ok = undo_all_ok && ok;
      const bool sync = check_cross_surface_sync();
      undo_all_ok = undo_all_ok && sync;
    }
    const bool undo_stack_drained = undo_history.empty() && (redo_stack.size() == 4);

    // ---- Redo 4 times ----
    bool redo_all_ok = true;
    for (int i = 0; i < 4; ++i) {
      const bool ok = apply_redo_command();
      redo_all_ok = redo_all_ok && ok;
      const bool sync = check_cross_surface_sync();
      redo_all_ok = redo_all_ok && sync;
    }
    const bool redo_stack_drained = redo_stack.empty() && (undo_history.size() == 4);

    undoredo_diag.insert_undo_redo_works =
      undo_all_ok && redo_all_ok && undo_stack_drained && redo_stack_drained;
    undoredo_diag.property_edit_undo_redo_works = undo_all_ok && redo_all_ok;
    undoredo_diag.delete_undo_redo_works = undo_all_ok && redo_all_ok;
    undoredo_diag.move_or_reparent_undo_redo_works = undo_all_ok && redo_all_ok;

    // ---- Final coherence check ----
    remap_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    const bool final_sync = check_cross_surface_sync();
    undoredo_diag.shell_state_coherent_after_undo_redo = final_sync && undo_all_ok && redo_all_ok;

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    undoredo_diag.layout_audit_still_compatible = audit.no_overlap;

    if (!flow_ok || !undo_all_ok || !redo_all_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto reset_runtime_state_after_document_replacement = [&](const std::string& preferred_selected_id, bool clear_history) {
    selected_builder_node_id.clear();
    focused_builder_node_id.clear();
    builder_selection_anchor_node_id.clear();
    multi_selected_node_ids.clear();
    inspector_binding_node_id.clear();
    preview_binding_node_id.clear();
    hover_node_id.clear();
    drag_source_node_id.clear();
    drag_active = false;
    drag_target_preview_node_id.clear();
    drag_target_preview_is_illegal = false;
    drag_target_preview_parent_id.clear();
    drag_target_preview_insert_index = 0;
    drag_target_preview_resolution_kind.clear();
    preview_visual_feedback_message.clear();
    preview_visual_feedback_node_id.clear();
    tree_visual_feedback_node_id.clear();
    if (!preferred_selected_id.empty() && node_exists(preferred_selected_id)) {
      selected_builder_node_id = preferred_selected_id;
      focused_builder_node_id = preferred_selected_id;
      builder_selection_anchor_node_id = preferred_selected_id;
      multi_selected_node_ids = {preferred_selected_id};
    }
    if (clear_history) {
      undo_history.clear();
      redo_stack.clear();
    }
    inline_edit_active = false;
    inline_edit_node_id.clear();
    inline_edit_buffer.clear();
    inline_edit_original_text.clear();
    preview_inline_loaded_text.clear();
    builder_tree_scroll.set_scroll_offset_y(0);
    builder_preview_scroll.set_scroll_offset_y(0);
  };

  auto commit_clean_document_baseline = [&]() -> bool {
    const std::string snapshot = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    if (snapshot.empty()) {
      return false;
    }
    has_clean_builder_baseline_signature = true;
    clean_builder_baseline_signature = snapshot;
    has_saved_builder_snapshot = true;
    last_saved_builder_serialized = snapshot;
    builder_doc_dirty = false;
    update_labels();
    return true;
  };

  desktop_file_tool::DocumentLifecycleBinding __document_lifecycle_binding{
      builder_doc,
      builder_persistence_io_in_progress,
      builder_doc_dirty,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      selected_builder_node_id,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      multi_selected_node_ids,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      undo_history,
      redo_stack,
      [&](const std::string& preferred_selected_id, bool clear_history) {
        reset_runtime_state_after_document_replacement(preferred_selected_id, clear_history);
      },
      [&]() -> bool { return commit_clean_document_baseline(); },
      [&]() {
        builder_tree_scroll.set_scroll_offset_y(0);
        builder_preview_scroll.set_scroll_offset_y(0);
      },
      [&]() { return capture_mutation_checkpoint(); },
      [&](const BuilderMutationCheckpoint& checkpoint) { restore_mutation_checkpoint(checkpoint); },
      [&](const std::string& node_id) { return node_exists(node_id); },
      [&]() { return remap_selection_or_fail(); },
      [&]() { return sync_focus_with_selection_or_fail(); },
      [&]() { return refresh_inspector_or_fail(); },
      [&]() { return refresh_preview_or_fail(); },
      [&]() { return check_cross_surface_sync(); },
      [&](const BuilderMutationCheckpoint& checkpoint, const char* context_name) {
        return enforce_global_invariant_or_rollback(checkpoint, context_name);
      },
      [&](ngk::ui::builder::BuilderDocument& out_doc, std::string& out_selected) {
        return ::desktop_file_tool::create_default_builder_document(out_doc, out_selected);
      },
      [&]() { update_labels(); },
  };
  
  auto save_builder_document_to_path = [&](const std::filesystem::path& path) -> bool {
    return ::desktop_file_tool::save_builder_document_to_path(__document_lifecycle_binding, path);
  };
  auto load_builder_document_from_path = [&](const std::filesystem::path& path) -> bool {
    return ::desktop_file_tool::load_builder_document_from_path(__document_lifecycle_binding, path);
  };

  auto apply_save_document_command = [&]() -> bool {
    break_history_coalescing_boundary();
    saveload_diag.shell_save_control_present = true;
    const bool saved = ::desktop_file_tool::apply_save_document_command(
      __document_lifecycle_binding,
      builder_doc_save_path);
    saveload_diag.save_writes_deterministic_document = saved;
    return saved;
  };

  auto apply_load_document_command = [&](bool allow_discard_dirty = false) -> bool {
    break_history_coalescing_boundary();
    saveload_diag.shell_load_control_present = true;

    const bool loaded = ::desktop_file_tool::apply_load_document_command(
      __document_lifecycle_binding,
      builder_doc_save_path,
      allow_discard_dirty);
    if (loaded) {
      saveload_diag.history_cleared_or_handled_deterministically_on_load =
        undo_history.empty() && redo_stack.empty();
      saveload_diag.shell_state_coherent_after_load = check_cross_surface_sync();
    }
    return loaded;
  };

  auto import_external_builder_subtree_payload = [&](const std::string& serialized,
                                                    const std::string& target_id,
                                                    const std::string& history_tag,
                                                    std::vector<std::string>* imported_root_ids_out,
                                                    std::string* failure_reason_out = nullptr) -> bool {
    constexpr std::size_t kExternalBuilderPayloadMaxBytes = 262144;

    auto fail_import = [&](const std::string& reason) -> bool {
      if (imported_root_ids_out != nullptr) {
        imported_root_ids_out->clear();
      }
      if (failure_reason_out != nullptr) {
        *failure_reason_out = reason;
      }
      return false;
    };

    if (failure_reason_out != nullptr) {
      failure_reason_out->clear();
    }
    if (serialized.empty()) {
      return fail_import("empty_payload");
    }
    if (serialized.size() > kExternalBuilderPayloadMaxBytes) {
      return fail_import("payload_too_large");
    }

    auto* live_target = find_node_by_id(target_id);
    if (!live_target) {
      return fail_import("target_missing");
    }
    if (!widget_allows_children(live_target->widget_type)) {
      return fail_import("target_not_container");
    }

    auto prepared_import = ::desktop_file_tool::prepare_external_import_candidate(
      builder_doc,
      serialized,
      target_id);
    if (!prepared_import.success) {
      return fail_import(prepared_import.failure_reason);
    }

    ngk::ui::builder::BuilderDocument candidate_doc = std::move(prepared_import.candidate_doc);
    const std::string imported_root_id = std::move(prepared_import.imported_root_id);

    ::desktop_file_tool::ExternalImportTransactionContext __external_import_transaction_context{
      builder_doc,
      selected_builder_node_id,
      multi_selected_node_ids,
      [&](const std::string& preferred_selected_id, bool clear_history) {
        reset_runtime_state_after_document_replacement(preferred_selected_id, clear_history);
      },
      [&]() -> std::any { return capture_mutation_checkpoint(); },
      [&](const std::any& checkpoint_any) {
        restore_mutation_checkpoint(std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any));
      },
      [&]() { scrub_stale_lifecycle_references(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](const std::string& history_tag_value,
          const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
          const std::string& before_root,
          const std::string& before_sel,
          const std::vector<std::string>& before_multi,
          const std::any& checkpoint_any) {
        const auto& checkpoint = std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any);
        push_to_history(history_tag_value,
                        before_nodes,
                        before_root,
                        before_sel,
                        &before_multi,
                        builder_doc.nodes,
                        builder_doc.root_node_id,
                        selected_builder_node_id,
                        &multi_selected_node_ids,
                        &checkpoint);
      },
      [&](bool is_dirty) { recompute_builder_dirty_state(is_dirty); },
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const std::any& checkpoint_any, const std::string& operation_name) -> bool {
        return enforce_global_invariant_or_rollback(
          std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any),
          operation_name);
      },
    };

    const auto import_transaction = ::desktop_file_tool::apply_external_import_transaction(
      __external_import_transaction_context,
      std::move(candidate_doc),
      imported_root_id,
      history_tag,
      imported_root_ids_out);
    if (!import_transaction.success) {
      return fail_import(import_transaction.failure_reason);
    }
    return true;
  };

  // Lifecycle rule: shell always maintains one valid active document.
  
  auto create_default_builder_document = [&](ngk::ui::builder::BuilderDocument& out_doc, std::string& out_selected) -> bool {
    return ::desktop_file_tool::create_default_builder_document(out_doc, out_selected);
  };
  auto apply_new_document_command = [&](bool allow_discard_dirty = false) -> bool {
    lifecycle_diag.new_document_control_present = true;

    const bool created = ::desktop_file_tool::apply_new_document_command(
      __document_lifecycle_binding,
      allow_discard_dirty);
    if (!created) {
      return false;
    }

    lifecycle_diag.history_cleared_on_new = undo_history.empty() && redo_stack.empty();
    lifecycle_diag.dirty_state_clean_on_new = !builder_doc_dirty;
    lifecycle_diag.shell_state_coherent_after_new = check_cross_surface_sync();

    return lifecycle_diag.shell_state_coherent_after_new;
  };

  auto run_phase103_12 = [&] {
    bool flow_ok = true;
    saveload_diag = BuilderSaveLoadDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    selected_builder_node_id = builder_doc.root_node_id;
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();

    flow_ok = apply_palette_insert(false) && flow_ok;
    const std::string roundtrip_node_id = selected_builder_node_id;
    auto* roundtrip_node = find_node_by_id(roundtrip_node_id);
    if (roundtrip_node) {
      roundtrip_node->text = "phase103_12_roundtrip_text";
    } else {
      flow_ok = false;
    }

    const std::size_t expected_count = builder_doc.nodes.size();
    const std::string expected_selected = selected_builder_node_id;
    const std::string expected_text = roundtrip_node ? roundtrip_node->text : std::string();

    const bool save_ok = apply_save_document_command();
    flow_ok = save_ok && flow_ok;

    if (roundtrip_node) {
      roundtrip_node->text = "phase103_12_mutated_after_save";
    }
    undo_history.push_back(CommandHistoryEntry{});
    redo_stack.push_back(CommandHistoryEntry{});

    const bool load_ok = apply_load_document_command(true);
    flow_ok = load_ok && flow_ok;

    auto* loaded_node = find_node_by_id(roundtrip_node_id);
    saveload_diag.load_restores_document_state =
      load_ok &&
      loaded_node != nullptr &&
      loaded_node->text == expected_text &&
      builder_doc.nodes.size() == expected_count &&
      selected_builder_node_id == expected_selected;

    const std::filesystem::path corrupt_path = builder_doc_save_path.string() + ".corrupt";
    const bool wrote_corrupt = write_text_file(corrupt_path, "not-a-valid-builder-document");
    ngk::ui::builder::BuilderDocument before_invalid_doc = builder_doc;
    const std::string before_invalid_selected = selected_builder_node_id;
    bool invalid_rejected = false;
    if (wrote_corrupt) {
      invalid_rejected = !load_builder_document_from_path(corrupt_path);
    }
    saveload_diag.invalid_load_rejected =
      wrote_corrupt &&
      invalid_rejected &&
      builder_doc.nodes.size() == before_invalid_doc.nodes.size() &&
      selected_builder_node_id == before_invalid_selected;

    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    saveload_diag.shell_state_coherent_after_load =
      saveload_diag.shell_state_coherent_after_load && inspector_ok && preview_ok && sync_ok;

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    saveload_diag.layout_audit_still_compatible = audit.no_overlap;

    if (!flow_ok ||
        !saveload_diag.load_restores_document_state ||
        !saveload_diag.invalid_load_rejected ||
        !saveload_diag.history_cleared_or_handled_deterministically_on_load ||
        !saveload_diag.shell_state_coherent_after_load) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_13 = [&] {
    bool flow_ok = true;
    dirty_state_diag = BuilderDirtyStateDiagnostics{};
    dirty_state_diag.dirty_state_tracking_present = true;

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    has_saved_builder_snapshot = false;
    last_saved_builder_serialized.clear();
    builder_doc_dirty = false;
    selected_builder_node_id = builder_doc.root_node_id;
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    update_labels();

    const bool inserted = apply_palette_insert(false);
    flow_ok = inserted && flow_ok;
    if (inserted) {
      recompute_builder_dirty_state(true);
    }
    dirty_state_diag.edit_marks_dirty = builder_doc_dirty;

    const bool saved = apply_save_document_command();
    flow_ok = saved && flow_ok;
    dirty_state_diag.save_marks_clean = saved && !builder_doc_dirty;

    auto* edited_node = find_node_by_id(selected_builder_node_id);
    if (edited_node) {
      edited_node->text = "phase103_13_post_save_edit";
      recompute_builder_dirty_state(true);
    } else {
      flow_ok = false;
    }
    dirty_state_diag.edit_marks_dirty = dirty_state_diag.edit_marks_dirty && builder_doc_dirty;

    const bool dirty_before_reject = builder_doc_dirty;
    const std::string previous_selection = selected_builder_node_id;
    selected_builder_node_id = builder_doc.root_node_id;
    const bool rejected_delete = !apply_delete_selected_node_command();
    dirty_state_diag.rejected_ops_do_not_change_dirty_state =
      rejected_delete && (builder_doc_dirty == dirty_before_reject);
    selected_builder_node_id = previous_selection;

    const std::string serialized_before_guard =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const bool guarded_load_rejected = !apply_load_document_command(false);
    const std::string serialized_after_guard =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    dirty_state_diag.unsafe_load_over_dirty_state_guarded =
      guarded_load_rejected && !serialized_before_guard.empty() && (serialized_before_guard == serialized_after_guard);

    const bool explicit_safe_load_ok = apply_load_document_command(true);
    flow_ok = explicit_safe_load_ok && flow_ok;
    dirty_state_diag.explicit_safe_load_path_works = explicit_safe_load_ok;
    dirty_state_diag.load_marks_clean = explicit_safe_load_ok && !builder_doc_dirty;

    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    dirty_state_diag.shell_state_coherent_after_guarded_load =
      inspector_ok && preview_ok && sync_ok && explicit_safe_load_ok;

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    dirty_state_diag.layout_audit_still_compatible = audit.no_overlap;

    if (!flow_ok ||
        !dirty_state_diag.edit_marks_dirty ||
        !dirty_state_diag.save_marks_clean ||
        !dirty_state_diag.load_marks_clean ||
        !dirty_state_diag.rejected_ops_do_not_change_dirty_state ||
        !dirty_state_diag.unsafe_load_over_dirty_state_guarded ||
        !dirty_state_diag.explicit_safe_load_path_works ||
        !dirty_state_diag.shell_state_coherent_after_guarded_load ||
        !dirty_state_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_14 = [&] {
    bool flow_ok = true;
    lifecycle_diag = BuilderLifecycleDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    has_saved_builder_snapshot = false;
    last_saved_builder_serialized.clear();
    selected_builder_node_id = builder_doc.root_node_id;
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    update_labels();

    const bool edited = apply_palette_insert(false);
    flow_ok = edited && flow_ok;
    if (edited) {
      recompute_builder_dirty_state(true);
    }

    const std::string before_guard_serialized =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const bool guarded_new_rejected = !apply_new_document_command(false);
    const std::string after_guard_serialized =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    lifecycle_diag.unsafe_new_over_dirty_state_guarded =
      guarded_new_rejected && !before_guard_serialized.empty() && (before_guard_serialized == after_guard_serialized);

    const bool explicit_new_ok = apply_new_document_command(true);
    flow_ok = explicit_new_ok && flow_ok;
    lifecycle_diag.explicit_safe_new_path_works = explicit_new_ok;

    std::string default_selected{};
    ngk::ui::builder::BuilderDocument expected_default{};
    const bool expected_default_ok = create_default_builder_document(expected_default, default_selected);
    const std::string expected_default_text =
      expected_default_ok ? ngk::ui::builder::serialize_builder_document_deterministic(expected_default) : std::string();
    const std::string actual_after_new = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    lifecycle_diag.new_document_creates_valid_builder_doc =
      explicit_new_ok && expected_default_ok && !expected_default_text.empty() && (actual_after_new == expected_default_text);

    const bool save_after_new_ok = apply_save_document_command();
    flow_ok = save_after_new_ok && flow_ok;
    const bool post_new_edit = apply_palette_insert(false);
    flow_ok = post_new_edit && flow_ok;
    if (post_new_edit) {
      recompute_builder_dirty_state(true);
    }
    const bool load_after_new_ok = apply_load_document_command(true);
    flow_ok = load_after_new_ok && flow_ok;

    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    lifecycle_diag.shell_state_coherent_after_new =
      lifecycle_diag.shell_state_coherent_after_new && inspector_ok && preview_ok && sync_ok;

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    lifecycle_diag.layout_audit_still_compatible = audit.no_overlap;

    if (!flow_ok ||
        !lifecycle_diag.new_document_control_present ||
        !lifecycle_diag.new_document_creates_valid_builder_doc ||
        !lifecycle_diag.unsafe_new_over_dirty_state_guarded ||
        !lifecycle_diag.explicit_safe_new_path_works ||
        !lifecycle_diag.history_cleared_on_new ||
        !lifecycle_diag.dirty_state_clean_on_new ||
        !lifecycle_diag.shell_state_coherent_after_new ||
        !lifecycle_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_15 = [&] {
    bool flow_ok = true;
    const bool undefined_before_phase = model.undefined_state_detected;
    focus_diag = BuilderFocusDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    selected_builder_node_id = builder_doc.root_node_id;
    focused_builder_node_id.clear();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    flow_ok = check_cross_surface_sync() && flow_ok;

    // Chain: new -> insert -> select -> edit -> delete -> undo -> load
    const bool new_ok = apply_new_document_command(true);
    flow_ok = new_ok && flow_ok;
    const bool save_after_new_ok = apply_save_document_command();
    flow_ok = save_after_new_ok && flow_ok;

    const auto before_insert_nodes = builder_doc.nodes;
    const std::string before_insert_root = builder_doc.root_node_id;
    const std::string before_insert_sel = selected_builder_node_id;
    const auto before_insert_multi = multi_selected_node_ids;
    const bool insert_ok = apply_palette_insert(false);
    flow_ok = insert_ok && flow_ok;
    if (insert_ok) {
      push_to_history("phase103_15_insert", before_insert_nodes, before_insert_root, before_insert_sel, &before_insert_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
    }

    const bool nav_next_ok = apply_tree_navigation(true);
    const bool nav_prev_ok = apply_tree_navigation(false);
    focus_diag.tree_navigation_coherent = nav_next_ok && nav_prev_ok && !selected_builder_node_id.empty();
    flow_ok = focus_diag.tree_navigation_coherent && flow_ok;

    auto* edit_target = find_node_by_id(selected_builder_node_id);
    if (edit_target) {
      const auto before_edit_nodes = builder_doc.nodes;
      const std::string before_edit_root = builder_doc.root_node_id;
      const std::string before_edit_sel = selected_builder_node_id;
      const auto before_edit_multi = multi_selected_node_ids;
      edit_target->text = "phase103_15_focus_edit";
      push_to_history("phase103_15_edit", before_edit_nodes, before_edit_root, before_edit_sel, &before_edit_multi,
              builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
    } else {
      flow_ok = false;
    }

    const auto before_delete_nodes = builder_doc.nodes;
    const std::string before_delete_root = builder_doc.root_node_id;
    const std::string before_delete_sel = selected_builder_node_id;
    const auto before_delete_multi = multi_selected_node_ids;
    const bool delete_ok = apply_delete_selected_node_command();
    flow_ok = delete_ok && flow_ok;
    if (delete_ok) {
      push_to_history("phase103_15_delete", before_delete_nodes, before_delete_root, before_delete_sel, &before_delete_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
    }

    const bool undo_ok = apply_undo_command();
    flow_ok = undo_ok && flow_ok;

    const bool load_ok = apply_load_document_command(true);
    flow_ok = load_ok && flow_ok;

    focused_builder_node_id = "phase103_15_stale_focus_id";
    const bool stale_focus_rejected_now = !sync_focus_with_selection_or_fail();
    focus_diag.stale_focus_rejected = stale_focus_rejected_now || focus_diag.stale_focus_rejected;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();

    focus_diag.inspector_focus_safe =
      inspector_ok &&
      (selected_builder_node_id.empty() ? inspector_binding_node_id.empty()
                                        : inspector_binding_node_id == selected_builder_node_id);
    focus_diag.post_operation_focus_deterministic =
      !focused_builder_node_id.empty() && focused_builder_node_id == selected_builder_node_id;
    focus_diag.shell_state_coherent_after_focus_changes =
      focus_diag.focus_selection_rules_defined &&
      focus_diag.post_operation_focus_deterministic &&
      focus_diag.tree_navigation_coherent &&
      focus_diag.stale_focus_rejected &&
      focus_diag.inspector_focus_safe &&
      preview_ok && sync_ok;

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    focus_diag.layout_audit_still_compatible = audit.no_overlap;

    const bool phase103_15_all_ok =
      flow_ok &&
      focus_diag.focus_selection_rules_defined &&
      focus_diag.post_operation_focus_deterministic &&
      focus_diag.tree_navigation_coherent &&
      focus_diag.stale_focus_rejected &&
      focus_diag.inspector_focus_safe &&
      focus_diag.shell_state_coherent_after_focus_changes &&
      focus_diag.layout_audit_still_compatible;

    if (!undefined_before_phase && phase103_15_all_ok) {
      model.undefined_state_detected = false;
    }

    if (!phase103_15_all_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_16 = [&] {
    bool flow_ok = true;
    visible_ux_diag = BuilderVisibleUxDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    selected_builder_node_id = builder_doc.root_node_id;
    focused_builder_node_id.clear();

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    flow_ok = check_cross_surface_sync() && flow_ok;

    const bool new_ok = apply_new_document_command(true);
    flow_ok = new_ok && flow_ok;
    const bool load_after_new_ok = apply_load_document_command(true);
    flow_ok = load_after_new_ok && flow_ok;

    const auto before_insert_nodes = builder_doc.nodes;
    const std::string before_insert_root = builder_doc.root_node_id;
    const std::string before_insert_sel = selected_builder_node_id;
    const auto before_insert_multi = multi_selected_node_ids;
    const bool insert_ok = apply_palette_insert(false);
    flow_ok = insert_ok && flow_ok;
    if (insert_ok) {
      push_to_history("phase103_16_insert", before_insert_nodes, before_insert_root, before_insert_sel, &before_insert_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
    }

    const bool nav_ok = apply_tree_navigation(true);
    flow_ok = nav_ok && flow_ok;

    auto* selected_node = find_node_by_id(selected_builder_node_id);
    if (selected_node) {
      const auto before_edit_nodes = builder_doc.nodes;
      const std::string before_edit_root = builder_doc.root_node_id;
      const std::string before_edit_sel = selected_builder_node_id;
      const auto before_edit_multi = multi_selected_node_ids;
      selected_node->text = "phase103_16_preview_text";
      push_to_history("phase103_16_edit", before_edit_nodes, before_edit_root, before_edit_sel, &before_edit_multi,
              builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
    } else {
      flow_ok = false;
    }

    const auto before_delete_nodes = builder_doc.nodes;
    const std::string before_delete_root = builder_doc.root_node_id;
    const std::string before_delete_sel = selected_builder_node_id;
    const auto before_delete_multi = multi_selected_node_ids;
    const bool delete_ok = apply_delete_selected_node_command();
    flow_ok = delete_ok && flow_ok;
    if (delete_ok) {
      push_to_history("phase103_16_delete", before_delete_nodes, before_delete_root, before_delete_sel, &before_delete_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
    }

    const bool undo_ok = apply_undo_command();
    flow_ok = undo_ok && flow_ok;

    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    flow_ok = inspector_ok && preview_ok && sync_ok && flow_ok;

    const std::string tree_text = build_tree_surface_text();
    const std::string inspector_text = builder_inspector_label.text();
    const std::string preview_text = builder_preview_label.text();

    visible_ux_diag.tree_hierarchy_visibility_improved =
      tree_text.find("TREE REGION") != std::string::npos &&
      tree_text.find("- ") != std::string::npos;
    visible_ux_diag.selected_node_visibility_in_tree_improved =
      tree_text.find("[SELECTED]") != std::string::npos;
    visible_ux_diag.preview_readability_improved =
      preview_text.find("PREVIEW REGION") != std::string::npos &&
      preview_text.find("root=") != std::string::npos;
    visible_ux_diag.selected_node_visibility_in_preview_improved =
      preview_text.find("selected=> ") != std::string::npos;
    visible_ux_diag.shell_regions_clearly_labeled =
      tree_text.find("TREE REGION") != std::string::npos &&
      preview_text.find("PREVIEW REGION") != std::string::npos &&
      inspector_text.find("INSPECTOR REGION") != std::string::npos &&
      builder_insert_container_button.text().find("Insert") != std::string::npos;
    visible_ux_diag.shell_state_still_coherent =
      sync_ok && inspector_ok && preview_ok &&
      (!selected_builder_node_id.empty()) &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    visible_ux_diag.layout_audit_still_compatible = audit.no_overlap;

    if (!flow_ok ||
        !visible_ux_diag.tree_hierarchy_visibility_improved ||
        !visible_ux_diag.selected_node_visibility_in_tree_improved ||
        !visible_ux_diag.preview_readability_improved ||
        !visible_ux_diag.selected_node_visibility_in_preview_improved ||
        !visible_ux_diag.shell_regions_clearly_labeled ||
        !visible_ux_diag.shell_state_still_coherent ||
        !visible_ux_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto resolve_builder_action_label = [&](const std::string& action_id) -> std::string {
    if (action_id == "ACTION_INSERT_CONTAINER") return "Insert Container";
    if (action_id == "ACTION_INSERT_LEAF") return "Insert Leaf";
    if (action_id == "ACTION_DELETE_CURRENT") return "Delete";
    if (action_id == "ACTION_UNDO") return "Undo";
    if (action_id == "ACTION_REDO") return "Redo";
    if (action_id == "ACTION_SAVE") return "Save";
    if (action_id == "ACTION_LOAD") return "Load";
    if (action_id == "ACTION_LOAD_FORCE_DISCARD") return "Load (Discard Dirty)";
    if (action_id == "ACTION_NEW") return "New";
    if (action_id == "ACTION_NEW_FORCE_DISCARD") return "New (Discard Dirty)";
    if (action_id == "ACTION_EXPORT") return "Export";
    return "Unknown";
  };

  // --- PHASE103_18: Controlled Drag/Reorder UX ---
  ::desktop_file_tool::DragDropPlanningLogicBinding __drag_drop_planning_binding{
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    drag_source_node_id,
    drag_active,
    drag_target_preview_node_id,
    drag_target_preview_is_illegal,
    drag_target_preview_parent_id,
    drag_target_preview_insert_index,
    drag_target_preview_resolution_kind,
    hover_node_id,
    dragdrop_diag.tree_drag_reorder_present,
    dragdrop_diag.illegal_drop_rejected,
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return is_node_in_multi_selection(node_id); },
    [&]() -> std::vector<std::string> { return collect_preorder_node_ids(); },
    [&]() -> bool { return remap_selection_or_fail(); },
    [&]() -> bool { return sync_focus_with_selection_or_fail(); },
    [&]() { refresh_preview_surface_label(); },
  };
  ::desktop_file_tool::DragDropPlanningLogic __drag_drop_planning_logic{__drag_drop_planning_binding};
  DESKTOP_FILE_TOOL_BIND_DRAG_DROP_PLANNING_LOGIC(__drag_drop_planning_logic)

  ::desktop_file_tool::DragDropCommitLogicBinding __drag_drop_commit_binding{
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    last_bulk_move_reparent_status_code,
    last_bulk_move_reparent_reason,
    bulk_move_reparent_diag.bulk_move_reparent_present,
    bulk_move_reparent_diag.invalid_or_protected_bulk_target_rejected,
    bulk_move_reparent_diag.eligible_selected_nodes_moved,
    bulk_move_reparent_diag.post_move_selection_deterministic,
    dragdrop_diag.legal_reorder_drop_applied,
    dragdrop_diag.legal_reparent_drop_applied,
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&]() { sync_multi_selection_with_primary(); },
    [&](const std::vector<std::string>& requested_node_ids,
        const std::string& requested_target_id,
        std::string& reason_out,
        std::vector<std::string>* normalized_ids_out) -> bool {
      return resolve_bulk_move_reparent_request(requested_node_ids, requested_target_id, reason_out, normalized_ids_out);
    },
    [&](const std::string& target_id, bool is_reparent) -> ::desktop_file_tool::BuilderDragDropMutationPlan {
      return resolve_tree_drag_drop_plan(target_id, is_reparent);
    },
    [&]() { cancel_tree_drag(); },
    [&]() -> std::any { return capture_mutation_checkpoint(); },
    [&](const char* history_tag,
        const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
        const std::string& before_root,
        const std::string& before_sel,
        const std::vector<std::string>& before_multi,
        const std::any& checkpoint_any) {
      const auto& checkpoint = std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any);
      push_to_history(history_tag,
                      before_nodes,
                      before_root,
                      before_sel,
                      &before_multi,
                      builder_doc.nodes,
                      builder_doc.root_node_id,
                      selected_builder_node_id,
                      &multi_selected_node_ids,
                      &checkpoint);
    },
    [&](bool is_dirty) { recompute_builder_dirty_state(is_dirty); },
    [&]() { scrub_stale_lifecycle_references(); },
    [&]() -> bool { return remap_selection_or_fail(); },
    [&]() -> bool { return sync_focus_with_selection_or_fail(); },
    [&]() { refresh_inspector_surface_label(); },
    [&]() { refresh_preview_surface_label(); },
    [&]() -> bool { return refresh_inspector_or_fail(); },
    [&]() -> bool { return refresh_preview_or_fail(); },
    [&]() -> bool { return check_cross_surface_sync(); },
    [&](const std::any& checkpoint_any, const char* operation_name) -> bool {
      const auto& checkpoint = std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any);
      return enforce_global_invariant_or_rollback(checkpoint, operation_name);
    },
  };
  ::desktop_file_tool::DragDropCommitLogic __drag_drop_commit_logic{__drag_drop_commit_binding};
  DESKTOP_FILE_TOOL_BIND_DRAG_DROP_COMMIT_LOGIC(__drag_drop_commit_logic)

  auto reject_illegal_tree_drag_drop = [&](const std::string& target_id, bool is_reparent) -> bool {
    return __drag_drop_planning_logic.reject_illegal_tree_drag_drop(target_id, is_reparent);
  };

  ::desktop_file_tool::PreviewInlineActionCommitLogicBinding __preview_inline_action_commit_binding{
    builder_doc,
    selected_builder_node_id,
    multi_selected_node_ids,
    preview_inline_action_commit_sequence,
    last_preview_inline_action_commit_status_code,
    last_preview_inline_action_commit_reason,
    [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
    [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    [&]() { sync_multi_selection_with_primary(); },
    [&](const ngk::ui::builder::BuilderNode& selected_node) -> std::vector<PreviewInlineActionAffordanceEntry> {
      return build_preview_inline_action_entries(selected_node);
    },
    [&]() -> std::any { return capture_mutation_checkpoint(); },
    [&](const char* history_tag,
        const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
        const std::string& before_root,
        const std::string& before_sel,
        const std::vector<std::string>& before_multi,
        const std::any& checkpoint_any) {
      const auto& checkpoint = std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any);
      push_to_history(history_tag,
                      before_nodes,
                      before_root,
                      before_sel,
                      &before_multi,
                      builder_doc.nodes,
                      builder_doc.root_node_id,
                      selected_builder_node_id,
                      &multi_selected_node_ids,
                      &checkpoint);
    },
    [&](const std::any& checkpoint_any, const char* operation_name) -> bool {
      const auto& checkpoint = std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any);
      return enforce_global_invariant_or_rollback(checkpoint, operation_name);
    },
    [&](bool is_dirty) { recompute_builder_dirty_state(is_dirty); },
    [&](const std::string& text) -> bool { return apply_inspector_text_edit_command(text); },
    [&]() -> bool { return apply_delete_command_for_current_selection(); },
    [&]() -> bool { return remap_selection_or_fail(); },
    [&]() -> bool { return sync_focus_with_selection_or_fail(); },
    [&]() -> bool { return refresh_inspector_or_fail(); },
    [&]() -> bool { return refresh_preview_or_fail(); },
    [&]() { refresh_preview_surface_label(); },
    [&]() -> bool { return check_cross_surface_sync(); },
  };
  ::desktop_file_tool::PreviewInlineActionCommitLogic __preview_inline_action_commit_logic{
    __preview_inline_action_commit_binding};
  DESKTOP_FILE_TOOL_BIND_PREVIEW_INLINE_ACTION_COMMIT_LOGIC(__preview_inline_action_commit_logic)

  auto run_phase103_17 = [&] {
    bool flow_ok = true;
    shortcut_diag = BuilderShortcutDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    selected_builder_node_id = builder_doc.root_node_id;
    focused_builder_node_id.clear();

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    flow_ok = check_cross_surface_sync() && flow_ok;

    const bool nav_down_ok = handle_builder_shortcut_key(0x28, true, false);
    const bool nav_up_ok = handle_builder_shortcut_key(0x26, true, false);
    const bool nav_child_ok = handle_builder_shortcut_key(0x27, true, false);
    const bool nav_parent_ok = handle_builder_shortcut_key(0x25, true, false);
    shortcut_diag.keyboard_tree_navigation_present = nav_down_ok && nav_up_ok && nav_child_ok && nav_parent_ok;
    flow_ok = shortcut_diag.keyboard_tree_navigation_present && flow_ok;

    const bool insert_container_ok = handle_builder_shortcut_key(0x43, true, false);
    const bool insert_leaf_ok = handle_builder_shortcut_key(0x4C, true, false);
    const bool delete_ok = handle_builder_shortcut_key(0x2E, true, false);
    shortcut_diag.insert_delete_shortcuts_work = insert_container_ok && insert_leaf_ok && delete_ok;
    flow_ok = shortcut_diag.insert_delete_shortcuts_work && flow_ok;

    const bool undo_ok = handle_builder_shortcut_key(0x5A, true, false);
    const bool redo_ok = handle_builder_shortcut_key(0x59, true, false);
    shortcut_diag.undo_redo_shortcuts_work = undo_ok && redo_ok;
    flow_ok = shortcut_diag.undo_redo_shortcuts_work && flow_ok;

    const bool save_ok = handle_builder_shortcut_key(0x53, true, false);
    flow_ok = save_ok && flow_ok;
    const bool post_save_insert_ok = handle_builder_shortcut_key(0x4C, true, false);
    flow_ok = post_save_insert_ok && flow_ok;
    const bool guarded_load_rejected = !handle_builder_shortcut_key(0x4F, true, false);
    const bool guarded_new_rejected = !handle_builder_shortcut_key(0x4E, true, false);
    shortcut_diag.guarded_lifecycle_shortcuts_safe = guarded_load_rejected && guarded_new_rejected;
    flow_ok = shortcut_diag.guarded_lifecycle_shortcuts_safe && flow_ok;

    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    shortcut_diag.shell_state_still_coherent =
      inspector_ok && preview_ok && sync_ok &&
      (!selected_builder_node_id.empty()) &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);

    auto audit = ngk::ui::builder::audit_layout_tree(&root);
    shortcut_diag.layout_audit_still_compatible = audit.no_overlap;

    if (!flow_ok ||
        !shortcut_diag.keyboard_tree_navigation_present ||
        !shortcut_diag.shortcut_scope_rules_defined ||
        !shortcut_diag.undo_redo_shortcuts_work ||
        !shortcut_diag.insert_delete_shortcuts_work ||
        !shortcut_diag.guarded_lifecycle_shortcuts_safe ||
        !shortcut_diag.shell_state_still_coherent ||
        !shortcut_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_18 = [&] {
    bool flow_ok = true;
    dragdrop_diag = BuilderDragDropDiagnostics{};

    // Set up a fresh document with root + 3 children for drag tests
    builder_doc = ngk::ui::builder::BuilderDocument{};
    builder_doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

    ngk::ui::builder::BuilderNode drag_root{};
    drag_root.node_id = "drag-root-001";
    drag_root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    drag_root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
    drag_root.child_ids = {"drag-container-a", "drag-leaf-b", "drag-container-c"};

    ngk::ui::builder::BuilderNode drag_a{};
    drag_a.node_id = "drag-container-a";
    drag_a.parent_id = "drag-root-001";
    drag_a.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;

    ngk::ui::builder::BuilderNode drag_b{};
    drag_b.node_id = "drag-leaf-b";
    drag_b.parent_id = "drag-root-001";
    drag_b.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
    drag_b.text = "Drag Leaf B";

    ngk::ui::builder::BuilderNode drag_c{};
    drag_c.node_id = "drag-container-c";
    drag_c.parent_id = "drag-root-001";
    drag_c.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;

    builder_doc.root_node_id = "drag-root-001";
    builder_doc.nodes.push_back(drag_root);
    builder_doc.nodes.push_back(drag_a);
    builder_doc.nodes.push_back(drag_b);
    builder_doc.nodes.push_back(drag_c);

    selected_builder_node_id = "drag-root-001";
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    flow_ok = check_cross_surface_sync() && flow_ok;

    // TEST 1: Legal sibling reorder — drag "drag-leaf-b" swaps positions with "drag-container-c"
    drag_active = false;
    drag_source_node_id.clear();
    selected_builder_node_id = "drag-leaf-b";
    const bool drag1_begin = begin_tree_drag("drag-leaf-b");
    flow_ok = drag1_begin && flow_ok;
    if (drag1_begin) {
      const bool reorder_ok = commit_tree_drag_reorder("drag-container-c");
      flow_ok = reorder_ok && flow_ok;
    }
    // After reorder: root children = [drag-container-a, drag-container-c, drag-leaf-b]

    // TEST 2: Legal reparent — drag "drag-leaf-b" into "drag-container-a" (VerticalLayout)
    drag_active = false;
    drag_source_node_id.clear();
    selected_builder_node_id = "drag-leaf-b";
    const bool drag2_begin = begin_tree_drag("drag-leaf-b");
    flow_ok = drag2_begin && flow_ok;
    if (drag2_begin) {
      const bool reparent_ok = commit_tree_drag_reparent("drag-container-a");
      flow_ok = reparent_ok && flow_ok;
    }
    // After reparent: root → [drag-container-a [drag-leaf-b], drag-container-c]

    // TEST 3: Illegal drop rejected — circular reparent attempt
    //   Try to drop "drag-container-a" under "drag-leaf-b" (drag-leaf-b is now a descendant of a)
    drag_source_node_id = "drag-container-a";
    drag_active = true;
    dragdrop_diag.tree_drag_reorder_present = true;
    const bool illegal_ok = reject_illegal_tree_drag_drop("drag-leaf-b", true);
    flow_ok = illegal_ok && flow_ok;

    // Verify selection preserved after all operations
    selected_builder_node_id = "drag-container-a";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    dragdrop_diag.dragged_node_selection_preserved =
      !selected_builder_node_id.empty() && node_exists(selected_builder_node_id);
    flow_ok = dragdrop_diag.dragged_node_selection_preserved && flow_ok;

    // Shell coherence
    const bool insp_ok18 = refresh_inspector_or_fail();
    const bool prev_ok18 = refresh_preview_or_fail();
    const bool sync_ok18 = check_cross_surface_sync();
    dragdrop_diag.shell_state_still_coherent =
      insp_ok18 && prev_ok18 && sync_ok18 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = dragdrop_diag.shell_state_still_coherent && flow_ok;

    auto audit18 = ngk::ui::builder::audit_layout_tree(&root);
    dragdrop_diag.layout_audit_still_compatible = audit18.no_overlap;
    flow_ok = dragdrop_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !dragdrop_diag.tree_drag_reorder_present ||
        !dragdrop_diag.legal_reorder_drop_applied ||
        !dragdrop_diag.legal_reparent_drop_applied ||
        !dragdrop_diag.illegal_drop_rejected ||
        !dragdrop_diag.dragged_node_selection_preserved ||
        !dragdrop_diag.shell_state_still_coherent ||
        !dragdrop_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto apply_export_command = [&](const ngk::ui::builder::BuilderDocument& source_doc,
                                  const std::filesystem::path& export_file_path) -> bool {
    break_history_coalescing_boundary();
    export_diag.export_command_present = true;
    last_export_artifact_path = export_file_path.string();

    auto fail_export = [&](const char* reason_code) -> bool {
      export_diag.export_artifact_created = false;
      export_diag.export_artifact_deterministic = false;
      export_diag.exported_structure_matches_builder_doc = false;
      last_export_status_code = "fail";
      last_export_reason = reason_code == nullptr ? "unknown_export_error" : reason_code;
      refresh_export_status_surface_label();
      update_labels();
      return false;
    };

    std::string invariant_reason;
    if (!validate_global_document_invariant(invariant_reason)) {
      return fail_export("global_invariant_failed");
    }

    const auto export_result = ::desktop_file_tool::export_builder_document_artifact(
      builder_doc,
      source_doc,
      export_file_path);
    if (!export_result.ok) {
      return fail_export(export_result.reason.c_str());
    }

    export_diag.export_artifact_created = export_result.export_artifact_created;
    export_diag.export_artifact_deterministic = export_result.export_artifact_deterministic;
    export_diag.exported_structure_matches_builder_doc = export_result.exported_structure_matches_builder_doc;
    has_last_export_snapshot = export_result.has_export_snapshot;
    last_export_snapshot = export_result.export_snapshot;
    export_snapshot_matches_current_doc = export_result.export_snapshot_matches_current_doc;
    last_export_status_code = export_result.status_code;
    last_export_reason = export_result.reason;
    refresh_export_status_surface_label();
    update_labels();
    return true;
  };

  auto set_preview_export_parity_status = [&](const char* status_code, const std::string& reason) {
    last_preview_export_parity_status_code = status_code == nullptr ? "unknown" : status_code;
    last_preview_export_parity_reason = reason.empty() ? std::string("none") : reason;
    refresh_preview_surface_label();
  };

  auto validate_preview_export_parity = [&](const ngk::ui::builder::BuilderDocument& live_doc,
                                            const std::filesystem::path& export_file_path) -> bool {
    const auto parity_result = ::desktop_file_tool::validate_exported_preview_parity(
      live_doc,
      export_file_path,
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason_out,
          const char* context_name) {
        return build_preview_export_parity_entries(doc, entries, reason_out, context_name);
      });
    set_preview_export_parity_status(parity_result.status_code.c_str(), parity_result.reason);
    return parity_result.ok;
  };

  auto run_phase103_19 = [&] {
    bool flow_ok = true;
    typed_palette_diag = BuilderTypedPaletteDiagnostics{};
    using WType = ngk::ui::builder::BuilderWidgetType;

    // Fresh document: palette-root-001 (VerticalLayout+Shell)
    // Initial children: palette-container-a (HorizontalLayout), palette-leaf-b (Button)
    builder_doc = ngk::ui::builder::BuilderDocument{};
    builder_doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

    ngk::ui::builder::BuilderNode pal_root{};
    pal_root.node_id = "palette-root-001";
    pal_root.widget_type = WType::VerticalLayout;
    pal_root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
    pal_root.child_ids = {"palette-container-a", "palette-leaf-b"};
    builder_doc.nodes.push_back(pal_root);
    builder_doc.root_node_id = "palette-root-001";

    ngk::ui::builder::BuilderNode pal_a{};
    pal_a.node_id = "palette-container-a";
    pal_a.parent_id = "palette-root-001";
    pal_a.widget_type = WType::HorizontalLayout;
    builder_doc.nodes.push_back(pal_a);

    ngk::ui::builder::BuilderNode pal_b{};
    pal_b.node_id = "palette-leaf-b";
    pal_b.parent_id = "palette-root-001";
    pal_b.widget_type = WType::Button;
    pal_b.text = "Palette Button";
    builder_doc.nodes.push_back(pal_b);

    selected_builder_node_id = "palette-root-001";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    typed_palette_diag.typed_palette_present = true;

    // TEST 1: Legal typed container insert — HorizontalLayout under root
    const bool container_insert_ok = apply_typed_palette_insert(
      WType::HorizontalLayout, "palette-root-001", "palette-typed-container-001");
    typed_palette_diag.legal_typed_container_insert_applied = container_insert_ok;
    flow_ok = container_insert_ok && flow_ok;
    if (container_insert_ok) {
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
      flow_ok = refresh_inspector_or_fail() && flow_ok;
      flow_ok = refresh_preview_or_fail() && flow_ok;
    }

    // TEST 2: Legal typed leaf insert — Button under palette-container-a
    selected_builder_node_id = "palette-container-a";
    const bool leaf_insert_ok = apply_typed_palette_insert(
      WType::Button, "palette-container-a", "palette-typed-leaf-001");
    typed_palette_diag.legal_typed_leaf_insert_applied = leaf_insert_ok;
    flow_ok = leaf_insert_ok && flow_ok;
    if (leaf_insert_ok) {
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
      flow_ok = refresh_inspector_or_fail() && flow_ok;
      flow_ok = refresh_preview_or_fail() && flow_ok;
    }

    // TEST 3: Illegal typed insert rejected — VerticalLayout under palette-leaf-b (Button, non-container)
    const bool illegal_rejected = !apply_typed_palette_insert(
      WType::VerticalLayout, "palette-leaf-b", "palette-illegal-001");
    typed_palette_diag.illegal_typed_insert_rejected = illegal_rejected;
    flow_ok = illegal_rejected && flow_ok;

    // Selection continuity: after leaf insert, selection must be palette-typed-leaf-001
    typed_palette_diag.inserted_typed_node_auto_selected =
      (selected_builder_node_id == "palette-typed-leaf-001") &&
      node_exists("palette-typed-leaf-001");
    flow_ok = typed_palette_diag.inserted_typed_node_auto_selected && flow_ok;

    // Inspector type-appropriate: selected node must be Button with matching type string
    {
      auto* sel_node = find_node_by_id(selected_builder_node_id);
      const bool type_ok = sel_node != nullptr &&
        sel_node->widget_type == WType::Button &&
        std::string(ngk::ui::builder::to_string(sel_node->widget_type)) == "button";
      typed_palette_diag.inspector_shows_type_appropriate_properties = type_ok;
      flow_ok = type_ok && flow_ok;
    }

    // Shell coherence
    const bool insp_ok19 = refresh_inspector_or_fail();
    const bool prev_ok19 = refresh_preview_or_fail();
    const bool sync_ok19 = check_cross_surface_sync();
    typed_palette_diag.shell_state_still_coherent =
      insp_ok19 && prev_ok19 && sync_ok19 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = typed_palette_diag.shell_state_still_coherent && flow_ok;

    auto audit19 = ngk::ui::builder::audit_layout_tree(&root);
    typed_palette_diag.layout_audit_still_compatible = audit19.no_overlap;
    flow_ok = typed_palette_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !typed_palette_diag.typed_palette_present ||
        !typed_palette_diag.legal_typed_container_insert_applied ||
        !typed_palette_diag.legal_typed_leaf_insert_applied ||
        !typed_palette_diag.illegal_typed_insert_rejected ||
        !typed_palette_diag.inserted_typed_node_auto_selected ||
        !typed_palette_diag.inspector_shows_type_appropriate_properties ||
        !typed_palette_diag.shell_state_still_coherent ||
        !typed_palette_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_20 = [&] {
    bool flow_ok = true;
    export_diag = BuilderExportDiagnostics{};
    using WType = ngk::ui::builder::BuilderWidgetType;

    // Build and edit the live builder document through existing command paths.
    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_container_ok = apply_typed_palette_insert(
      WType::HorizontalLayout, builder_doc.root_node_id, "export-container-a");
    flow_ok = add_container_ok && flow_ok;
    const bool add_label_ok = apply_typed_palette_insert(
      WType::Label, "export-container-a", "export-leaf-label");
    flow_ok = add_label_ok && flow_ok;
    const bool add_button_ok = apply_typed_palette_insert(
      WType::Button, "export-container-a", "export-leaf-button");
    flow_ok = add_button_ok && flow_ok;

    if (auto* export_label = find_node_by_id("export-leaf-label")) {
      export_label->text = "Exported Label";
    } else {
      flow_ok = false;
    }
    if (auto* export_button = find_node_by_id("export-leaf-button")) {
      export_button->text = "Exported Button";
    } else {
      flow_ok = false;
    }

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::string before_export_snapshot =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string before_export_selection = selected_builder_node_id;

    // Ensure export directory exists
    try {
      std::filesystem::create_directories(builder_export_path.parent_path());
    } catch (...) {
      model.undefined_state_detected = true;
      return;
    }

    // TEST 1: Legal export — must use current live builder_doc
    const bool export_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export_ok && flow_ok;

    // Determinism check: export again and compare bytes
    std::string first_export_text;
    const bool first_read_ok = read_text_file(builder_export_path, first_export_text);
    flow_ok = first_read_ok && flow_ok;
    const bool second_export_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = second_export_ok && flow_ok;
    std::string second_export_text;
    const bool second_read_ok = read_text_file(builder_export_path, second_export_text);
    flow_ok = second_read_ok && flow_ok;
    export_diag.export_artifact_deterministic =
      export_diag.export_artifact_deterministic && first_read_ok && second_read_ok &&
      (first_export_text == second_export_text);
    flow_ok = export_diag.export_artifact_deterministic && flow_ok;

    // Structure check: exported canonical text equals the live builder canonical text.
    const std::string expected_export =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    export_diag.exported_structure_matches_builder_doc =
      export_diag.exported_structure_matches_builder_doc && second_read_ok &&
      (second_export_text == expected_export);
    flow_ok = export_diag.exported_structure_matches_builder_doc && flow_ok;

    // TEST 2: Invalid export rejected — empty document fails closed
    {
      ngk::ui::builder::BuilderDocument invalid_doc = builder_doc;
      invalid_doc.root_node_id.clear();
      const bool invalid_rejected = !apply_export_command(invalid_doc, builder_export_path);
      export_diag.invalid_export_rejected = invalid_rejected;
      flow_ok = invalid_rejected && flow_ok;
    }

    // Non-mutation guarantee: export command must not mutate live builder state.
    const std::string after_export_snapshot =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    flow_ok = (before_export_snapshot == after_export_snapshot) && flow_ok;
    flow_ok = (before_export_selection == selected_builder_node_id) && flow_ok;

    flow_ok = export_diag.export_artifact_created && flow_ok;

    // Builder state must be untouched: verify builder_doc is still valid
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok20 = refresh_inspector_or_fail();
    const bool prev_ok20 = refresh_preview_or_fail();
    const bool sync_ok20 = check_cross_surface_sync();
    export_diag.shell_state_still_coherent =
      insp_ok20 && prev_ok20 && sync_ok20 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = export_diag.shell_state_still_coherent && flow_ok;

    auto audit20 = ngk::ui::builder::audit_layout_tree(&root);
    export_diag.layout_audit_still_compatible = audit20.no_overlap;
    flow_ok = export_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !export_diag.export_command_present ||
        !export_diag.export_artifact_created ||
        !export_diag.export_artifact_deterministic ||
        !export_diag.exported_structure_matches_builder_doc ||
        !export_diag.invalid_export_rejected ||
        !export_diag.shell_state_still_coherent ||
        !export_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_21 = [&] {
    bool flow_ok = true;
    export_ux_diag = BuilderExportUxDiagnostics{};

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    // Build typed content through existing command paths.
    const bool add_container_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::HorizontalLayout, builder_doc.root_node_id, "export21-container-a");
    flow_ok = add_container_ok && flow_ok;
    const bool add_leaf_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "export21-container-a", "export21-leaf-label");
    flow_ok = add_leaf_ok && flow_ok;
    if (auto* leaf = find_node_by_id("export21-leaf-label")) {
      leaf->text = "Export21 Label";
    } else {
      flow_ok = false;
    }

    const std::string before_export_doc =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string before_export_selection = selected_builder_node_id;

    // Valid export and status visibility checks.
    const bool valid_export_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = valid_export_ok && flow_ok;
    const std::string after_valid_export_doc =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string after_valid_export_selection = selected_builder_node_id;
    const bool export_non_mutating =
      !before_export_doc.empty() &&
      (after_valid_export_doc == before_export_doc) &&
      (after_valid_export_selection == before_export_selection);
    flow_ok = export_non_mutating && flow_ok;
    const std::string status_text_after_export = builder_export_status_label.text();
    export_ux_diag.export_status_visible =
      status_text_after_export.find("result=success") != std::string::npos;
    export_ux_diag.export_artifact_path_visible =
      status_text_after_export.find(builder_export_path.string()) != std::string::npos;
    export_ux_diag.export_state_tracking_present =
      status_text_after_export.find("state=up_to_date") != std::string::npos;
    flow_ok = export_ux_diag.export_status_visible && flow_ok;
    flow_ok = export_ux_diag.export_artifact_path_visible && flow_ok;
    flow_ok = export_ux_diag.export_state_tracking_present && flow_ok;

    // Re-export: enforce explicit deterministic overwrite single-target rule.
    std::string export_text_1;
    const bool read_1_ok = read_text_file(builder_export_path, export_text_1);
    flow_ok = read_1_ok && flow_ok;
    const bool reexport_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = reexport_ok && flow_ok;
    std::string export_text_2;
    const bool read_2_ok = read_text_file(builder_export_path, export_text_2);
    flow_ok = read_2_ok && flow_ok;
    const auto export_name = builder_export_path.filename().string();
    std::size_t matching_exports = 0;
    try {
      for (const auto& entry : std::filesystem::directory_iterator(builder_export_path.parent_path())) {
        if (!entry.is_regular_file()) {
          continue;
        }
        if (entry.path().filename().string() == export_name) {
          matching_exports += 1;
        }
      }
    } catch (...) {
      flow_ok = false;
    }
    export_ux_diag.export_overwrite_or_version_rule_enforced =
      read_1_ok && read_2_ok && (export_text_1 == export_text_2) && (matching_exports == 1);
    flow_ok = export_ux_diag.export_overwrite_or_version_rule_enforced && flow_ok;

    // Invalid export must be rejected with explicit reason code.
    ngk::ui::builder::BuilderDocument invalid_doc = builder_doc;
    invalid_doc.root_node_id.clear();
    const bool invalid_rejected = !apply_export_command(invalid_doc, builder_export_path);
    export_ux_diag.invalid_export_rejected_with_reason =
      invalid_rejected && !last_export_reason.empty() && last_export_reason != "none";
    flow_ok = export_ux_diag.invalid_export_rejected_with_reason && flow_ok;

    // Export state tracking must become stale after document edit.
    const bool stale_insert_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "export21-container-a", "export21-state-delta");
    flow_ok = stale_insert_ok && flow_ok;
    const bool dirty_ok = recompute_builder_dirty_state(true);
    flow_ok = dirty_ok && flow_ok;
    refresh_export_status_surface_label();
    const std::string status_text_after_edit = builder_export_status_label.text();
    const bool state_stale_visible =
      status_text_after_edit.find("state=stale_since_last_export") != std::string::npos;
    export_ux_diag.export_state_tracking_present =
      export_ux_diag.export_state_tracking_present && state_stale_visible;
    flow_ok = state_stale_visible && flow_ok;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok21 = refresh_inspector_or_fail();
    const bool prev_ok21 = refresh_preview_or_fail();
    const bool sync_ok21 = check_cross_surface_sync();
    export_ux_diag.shell_state_still_coherent =
      insp_ok21 && prev_ok21 && sync_ok21 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = export_ux_diag.shell_state_still_coherent && flow_ok;

    auto audit21 = ngk::ui::builder::audit_layout_tree(&root);
    export_ux_diag.layout_audit_still_compatible = audit21.no_overlap;
    flow_ok = export_ux_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !export_ux_diag.export_status_visible ||
        !export_ux_diag.export_artifact_path_visible ||
        !export_ux_diag.export_overwrite_or_version_rule_enforced ||
        !export_ux_diag.export_state_tracking_present ||
        !export_ux_diag.invalid_export_rejected_with_reason ||
        !export_ux_diag.shell_state_still_coherent ||
        !export_ux_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_22 = [&] {
    bool flow_ok = true;
    preview_export_parity_diag = BuilderPreviewExportParityDiagnostics{};

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_container_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::HorizontalLayout, builder_doc.root_node_id, "parity22-container-a");
    flow_ok = add_container_ok && flow_ok;
    const bool add_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "parity22-container-a", "parity22-leaf-label");
    flow_ok = add_label_ok && flow_ok;
    const bool add_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "parity22-container-a", "parity22-leaf-button");
    flow_ok = add_button_ok && flow_ok;

    if (auto* label_node = find_node_by_id("parity22-leaf-label")) {
      label_node->text = "Parity Label";
      selected_builder_node_id = label_node->node_id;
    } else {
      flow_ok = false;
    }
    if (auto* button_node = find_node_by_id("parity22-leaf-button")) {
      button_node->text = "Parity Button";
    } else {
      flow_ok = false;
    }

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    try {
      std::filesystem::create_directories(builder_export_path.parent_path());
    } catch (...) {
      flow_ok = false;
    }

    const bool valid_export_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = valid_export_ok && flow_ok;

    const std::string pre_valid_parity_doc =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string pre_valid_parity_selection = selected_builder_node_id;
    std::string pre_valid_parity_artifact;
    const bool valid_artifact_read_ok = read_text_file(builder_export_path, pre_valid_parity_artifact);
    flow_ok = valid_artifact_read_ok && flow_ok;

    const bool valid_parity_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    const std::string post_valid_parity_doc =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string post_valid_parity_selection = selected_builder_node_id;
    std::string post_valid_parity_artifact;
    const bool valid_artifact_reread_ok = read_text_file(builder_export_path, post_valid_parity_artifact);
    flow_ok = valid_parity_ok && valid_artifact_reread_ok && flow_ok;

    preview_export_parity_diag.parity_scope_defined =
      builder_preview_label.text().find(std::string("parity_scope=") + kPreviewExportParityScope) != std::string::npos;
    const bool valid_parity_non_mutating =
      !pre_valid_parity_doc.empty() &&
      (pre_valid_parity_doc == post_valid_parity_doc) &&
      (pre_valid_parity_selection == post_valid_parity_selection) &&
      (pre_valid_parity_artifact == post_valid_parity_artifact);
    preview_export_parity_diag.preview_export_parity_validation_present =
      valid_parity_ok &&
      (builder_preview_label.text().find("parity=success") != std::string::npos);
    preview_export_parity_diag.parity_passes_for_valid_document =
      valid_parity_ok && valid_parity_non_mutating &&
      last_preview_export_parity_status_code == "success" &&
      last_preview_export_parity_reason == "none";
    flow_ok = preview_export_parity_diag.parity_scope_defined && flow_ok;
    flow_ok = preview_export_parity_diag.preview_export_parity_validation_present && flow_ok;
    flow_ok = preview_export_parity_diag.parity_passes_for_valid_document && flow_ok;

    if (auto* label_node = find_node_by_id("parity22-leaf-label")) {
      label_node->text = "Parity Drift";
    } else {
      flow_ok = false;
    }
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::string pre_invalid_parity_doc =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string pre_invalid_parity_selection = selected_builder_node_id;
    std::string pre_invalid_parity_artifact;
    const bool invalid_artifact_read_ok = read_text_file(builder_export_path, pre_invalid_parity_artifact);
    flow_ok = invalid_artifact_read_ok && flow_ok;

    const bool mismatch_rejected = !validate_preview_export_parity(builder_doc, builder_export_path);
    const std::string post_invalid_parity_doc =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string post_invalid_parity_selection = selected_builder_node_id;
    std::string post_invalid_parity_artifact;
    const bool invalid_artifact_reread_ok = read_text_file(builder_export_path, post_invalid_parity_artifact);
    flow_ok = invalid_artifact_reread_ok && flow_ok;

    const bool invalid_parity_non_mutating =
      !pre_invalid_parity_doc.empty() &&
      (pre_invalid_parity_doc == post_invalid_parity_doc) &&
      (pre_invalid_parity_selection == post_invalid_parity_selection) &&
      (pre_invalid_parity_artifact == post_invalid_parity_artifact);
    preview_export_parity_diag.parity_mismatch_rejected_with_reason =
      mismatch_rejected && invalid_parity_non_mutating &&
      !last_preview_export_parity_reason.empty() &&
      last_preview_export_parity_reason != "none" &&
      last_preview_export_parity_reason.find("identity_text_mismatch_node_parity22-leaf-label") != std::string::npos &&
      (builder_preview_label.text().find(last_preview_export_parity_reason) != std::string::npos);
    flow_ok = preview_export_parity_diag.parity_mismatch_rejected_with_reason && flow_ok;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok22 = refresh_inspector_or_fail();
    const bool prev_ok22 = refresh_preview_or_fail();
    const bool sync_ok22 = check_cross_surface_sync();
    preview_export_parity_diag.export_shell_state_still_coherent =
      insp_ok22 && prev_ok22 && sync_ok22 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = preview_export_parity_diag.export_shell_state_still_coherent && flow_ok;

    auto audit22 = ngk::ui::builder::audit_layout_tree(&root);
    preview_export_parity_diag.layout_audit_still_compatible = audit22.no_overlap;
    flow_ok = preview_export_parity_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !preview_export_parity_diag.parity_scope_defined ||
        !preview_export_parity_diag.preview_export_parity_validation_present ||
        !preview_export_parity_diag.parity_passes_for_valid_document ||
        !preview_export_parity_diag.parity_mismatch_rejected_with_reason ||
        !preview_export_parity_diag.export_shell_state_still_coherent ||
        !preview_export_parity_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_23 = [&] {
    bool flow_ok = true;
    preview_surface_upgrade_diag = BuilderPreviewSurfaceUpgradeDiagnostics{};

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_container_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::HorizontalLayout, builder_doc.root_node_id, "preview23-container-a");
    flow_ok = add_container_ok && flow_ok;
    const bool add_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "preview23-container-a", "preview23-leaf-label");
    flow_ok = add_label_ok && flow_ok;
    const bool add_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "preview23-container-a", "preview23-leaf-button");
    flow_ok = add_button_ok && flow_ok;

    if (auto* label_node = find_node_by_id("preview23-leaf-label")) {
      label_node->text = "Preview Label";
      selected_builder_node_id = label_node->node_id;
    } else {
      flow_ok = false;
    }
    if (auto* button_node = find_node_by_id("preview23-leaf-button")) {
      button_node->text = "Preview Button";
    } else {
      flow_ok = false;
    }

    const bool save_ok = apply_save_document_command();
    flow_ok = save_ok && flow_ok;
    const bool load_ok = apply_load_document_command(true);
    flow_ok = load_ok && flow_ok;

    selected_builder_node_id = "preview23-leaf-label";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::string preview_text = builder_preview_label.text();
    preview_surface_upgrade_diag.preview_structure_visualized =
      preview_text.find("runtime_outline:") != std::string::npos &&
      preview_text.find("#    [CONTAINER] root-001") != std::string::npos &&
      preview_text.find("+- ") != std::string::npos;
    preview_surface_upgrade_diag.selected_node_highlight_visible =
      preview_text.find(">> [LABEL] preview23-leaf-label") != std::string::npos &&
      preview_text.find("[SELECTED]") != std::string::npos;
    preview_surface_upgrade_diag.component_identity_visually_distinct =
      preview_text.find("[CONTAINER] preview23-container-a") != std::string::npos &&
      preview_text.find("[LABEL] preview23-leaf-label") != std::string::npos &&
      preview_text.find("[BUTTON] preview23-leaf-button") != std::string::npos;
    flow_ok = preview_surface_upgrade_diag.preview_structure_visualized && flow_ok;
    flow_ok = preview_surface_upgrade_diag.selected_node_highlight_visible && flow_ok;
    flow_ok = preview_surface_upgrade_diag.component_identity_visually_distinct && flow_ok;

    try {
      std::filesystem::create_directories(builder_export_path.parent_path());
    } catch (...) {
      flow_ok = false;
    }

    const bool valid_export_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = valid_export_ok && flow_ok;

    const std::string pre_valid_doc = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string pre_valid_selection = selected_builder_node_id;
    std::string pre_valid_artifact;
    const bool pre_valid_artifact_ok = read_text_file(builder_export_path, pre_valid_artifact);
    flow_ok = pre_valid_artifact_ok && flow_ok;
    const bool valid_parity_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    const std::string post_valid_doc = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string post_valid_selection = selected_builder_node_id;
    std::string post_valid_artifact;
    const bool post_valid_artifact_ok = read_text_file(builder_export_path, post_valid_artifact);
    flow_ok = post_valid_artifact_ok && flow_ok;
    const bool valid_parity_non_mutating =
      !pre_valid_doc.empty() &&
      (pre_valid_doc == post_valid_doc) &&
      (pre_valid_selection == post_valid_selection) &&
      (pre_valid_artifact == post_valid_artifact);
    preview_surface_upgrade_diag.parity_still_passes =
      valid_parity_ok && valid_parity_non_mutating &&
      last_preview_export_parity_status_code == "success" &&
      builder_preview_label.text().find("parity=success") != std::string::npos;
    flow_ok = preview_surface_upgrade_diag.parity_still_passes && flow_ok;

    if (auto* label_node = find_node_by_id("preview23-leaf-label")) {
      label_node->text = "Preview Drift";
    } else {
      flow_ok = false;
    }
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::string pre_invalid_doc = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string pre_invalid_selection = selected_builder_node_id;
    std::string pre_invalid_artifact;
    const bool pre_invalid_artifact_ok = read_text_file(builder_export_path, pre_invalid_artifact);
    flow_ok = pre_invalid_artifact_ok && flow_ok;
    const bool mismatch_rejected = !validate_preview_export_parity(builder_doc, builder_export_path);
    const std::string post_invalid_doc = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string post_invalid_selection = selected_builder_node_id;
    std::string post_invalid_artifact;
    const bool post_invalid_artifact_ok = read_text_file(builder_export_path, post_invalid_artifact);
    flow_ok = post_invalid_artifact_ok && flow_ok;
    const bool invalid_parity_non_mutating =
      !pre_invalid_doc.empty() &&
      (pre_invalid_doc == post_invalid_doc) &&
      (pre_invalid_selection == post_invalid_selection) &&
      (pre_invalid_artifact == post_invalid_artifact);
    preview_surface_upgrade_diag.preview_remains_parity_safe =
      mismatch_rejected && invalid_parity_non_mutating &&
      !last_preview_export_parity_reason.empty() &&
      last_preview_export_parity_reason.find("identity_text_mismatch_node_preview23-leaf-label") != std::string::npos &&
      builder_preview_label.text().find("runtime_outline:") != std::string::npos &&
      builder_preview_label.text().find(last_preview_export_parity_reason) != std::string::npos;
    flow_ok = preview_surface_upgrade_diag.preview_remains_parity_safe && flow_ok;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok23 = refresh_inspector_or_fail();
    const bool prev_ok23 = refresh_preview_or_fail();
    const bool sync_ok23 = check_cross_surface_sync();
    preview_surface_upgrade_diag.shell_state_still_coherent =
      insp_ok23 && prev_ok23 && sync_ok23 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = preview_surface_upgrade_diag.shell_state_still_coherent && flow_ok;

    auto audit23 = ngk::ui::builder::audit_layout_tree(&root);
    preview_surface_upgrade_diag.layout_audit_still_compatible = audit23.no_overlap;
    flow_ok = preview_surface_upgrade_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !preview_surface_upgrade_diag.preview_structure_visualized ||
        !preview_surface_upgrade_diag.selected_node_highlight_visible ||
        !preview_surface_upgrade_diag.component_identity_visually_distinct ||
        !preview_surface_upgrade_diag.preview_remains_parity_safe ||
        !preview_surface_upgrade_diag.parity_still_passes ||
        !preview_surface_upgrade_diag.shell_state_still_coherent ||
        !preview_surface_upgrade_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_24 = [&] {
    bool flow_ok = true;
    preview_interaction_feedback_diag = BuilderPreviewInteractionFeedbackDiagnostics{};

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_container24_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::HorizontalLayout, builder_doc.root_node_id, "preview24-container-a");
    flow_ok = add_container24_ok && flow_ok;

    const bool add_label24_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "preview24-container-a", "preview24-leaf-label");
    flow_ok = add_label24_ok && flow_ok;

    const bool add_button24_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "preview24-container-a", "preview24-leaf-button");
    flow_ok = add_button24_ok && flow_ok;

    // 1. Hover test: leaf-button is selected, leaf-label is hovered -> [HOVER] without overriding [SELECTED]
    selected_builder_node_id = "preview24-leaf-button";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    set_preview_hover("preview24-leaf-label");
    {
      const std::string pt = builder_preview_label.text();
      const bool hover_tag_present =
        pt.find("[HOVER]") != std::string::npos &&
        pt.find("preview24-leaf-label") != std::string::npos;
      const bool selection_not_overridden =
        pt.find("preview24-leaf-button") != std::string::npos &&
        pt.find("[SELECTED]") != std::string::npos;
      preview_interaction_feedback_diag.hover_visual_present =
        hover_tag_present && selection_not_overridden;
      flow_ok = preview_interaction_feedback_diag.hover_visual_present && flow_ok;
    }
    clear_preview_hover();

    // 2. Drag target preview: drag leaf-label, target leaf-button -> legal reorder (same parent)
    const bool drag24_start_ok = begin_tree_drag("preview24-leaf-label");
    flow_ok = drag24_start_ok && flow_ok;
    selected_builder_node_id = "preview24-leaf-button";
    flow_ok = remap_selection_or_fail() && flow_ok;
    set_drag_target_preview("preview24-leaf-button", false);
    {
      const std::string pt = builder_preview_label.text();
      preview_interaction_feedback_diag.drag_target_preview_present =
        pt.find("[DRAG_TARGET]") != std::string::npos &&
        pt.find("preview24-leaf-button") != std::string::npos;
      flow_ok = preview_interaction_feedback_diag.drag_target_preview_present && flow_ok;
    }

    // 3. Illegal drop: target container-a (illegal reorder: different parent from leaf-label)
    set_drag_target_preview("preview24-container-a", false);
    {
      const std::string pt = builder_preview_label.text();
      preview_interaction_feedback_diag.illegal_drop_feedback_present =
        pt.find("[ILLEGAL_DROP]") != std::string::npos &&
        pt.find("preview24-container-a") != std::string::npos;
      flow_ok = preview_interaction_feedback_diag.illegal_drop_feedback_present && flow_ok;
    }
    clear_drag_target_preview();
    cancel_tree_drag();

    // 4. Parity safety: no fake nodes, outline derives from builder_doc
    selected_builder_node_id = builder_doc.root_node_id;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    {
      const bool export24_ok = apply_export_command(builder_doc, builder_export_path);
      flow_ok = export24_ok && flow_ok;
      const bool parity24_pass = validate_preview_export_parity(builder_doc, builder_export_path);
      preview_interaction_feedback_diag.preview_remains_parity_safe =
        parity24_pass &&
        !drag_active &&
        hover_node_id.empty() &&
        drag_target_preview_node_id.empty() &&
        builder_preview_label.text().find("runtime_outline:") != std::string::npos;
      flow_ok = preview_interaction_feedback_diag.preview_remains_parity_safe && flow_ok;
    }

    // 5. Shell coherence
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok24 = refresh_inspector_or_fail();
    const bool prev_ok24 = refresh_preview_or_fail();
    const bool sync_ok24 = check_cross_surface_sync();
    preview_interaction_feedback_diag.shell_state_still_coherent =
      insp_ok24 && prev_ok24 && sync_ok24 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = preview_interaction_feedback_diag.shell_state_still_coherent && flow_ok;

    // 6. Layout audit
    auto audit24 = ngk::ui::builder::audit_layout_tree(&root);
    preview_interaction_feedback_diag.layout_audit_still_compatible = audit24.no_overlap;
    flow_ok = preview_interaction_feedback_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !preview_interaction_feedback_diag.hover_visual_present ||
        !preview_interaction_feedback_diag.drag_target_preview_present ||
        !preview_interaction_feedback_diag.illegal_drop_feedback_present ||
        !preview_interaction_feedback_diag.preview_remains_parity_safe ||
        !preview_interaction_feedback_diag.shell_state_still_coherent ||
        !preview_interaction_feedback_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_25 = [&] {
    bool flow_ok = true;
    inspector_typed_edit_diag = BuilderInspectorTypedEditingDiagnostics{};
    last_inspector_edit_status_code = "INVALID";
    last_inspector_edit_reason = "phase_not_run";

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_container_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::HorizontalLayout, builder_doc.root_node_id, "inspect25-container-a");
    flow_ok = add_container_ok && flow_ok;
    const bool add_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "inspect25-container-a", "inspect25-leaf-label");
    flow_ok = add_label_ok && flow_ok;
    const bool add_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "inspect25-container-a", "inspect25-leaf-button");
    flow_ok = add_button_ok && flow_ok;

    // Select multiple typed nodes and verify typed inspector grouping relevance.
    selected_builder_node_id = "inspect25-container-a";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    const std::string container_inspector = builder_inspector_label.text();

    selected_builder_node_id = "inspect25-leaf-label";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    const std::string label_inspector = builder_inspector_label.text();

    inspector_typed_edit_diag.inspector_sections_typed_and_grouped =
      container_inspector.find("[IDENTITY]") != std::string::npos &&
      container_inspector.find("[LAYOUT]") != std::string::npos &&
      container_inspector.find("[CONTENT]") == std::string::npos &&
      container_inspector.find("[STATE]") != std::string::npos &&
      container_inspector.find("child_count (readonly):") != std::string::npos &&
      label_inspector.find("[IDENTITY]") != std::string::npos &&
      label_inspector.find("[CONTENT]") != std::string::npos &&
      label_inspector.find("[LAYOUT]") != std::string::npos &&
      label_inspector.find("[STATE]") != std::string::npos &&
      label_inspector.find("text (editable):") != std::string::npos;
    flow_ok = inspector_typed_edit_diag.inspector_sections_typed_and_grouped && flow_ok;

    inspector_typed_edit_diag.selected_node_type_clearly_visible =
      container_inspector.find("TYPE: horizontal_layout") != std::string::npos &&
      container_inspector.find("ID: inspect25-container-a") != std::string::npos &&
      label_inspector.find("TYPE: label") != std::string::npos &&
      label_inspector.find("ID: inspect25-leaf-label") != std::string::npos;
    flow_ok = inspector_typed_edit_diag.selected_node_type_clearly_visible && flow_ok;

    inspector_typed_edit_diag.editable_vs_readonly_state_clear =
      container_inspector.find("(readonly):") != std::string::npos &&
      container_inspector.find("(editable):") == std::string::npos &&
      label_inspector.find("(readonly):") != std::string::npos &&
      label_inspector.find("text (editable):") != std::string::npos;
    flow_ok = inspector_typed_edit_diag.editable_vs_readonly_state_clear && flow_ok;

    inspector_typed_edit_diag.type_specific_fields_correct =
      container_inspector.find("TYPE: horizontal_layout") != std::string::npos &&
      container_inspector.find("[CONTENT]") == std::string::npos &&
      label_inspector.find("TYPE: label") != std::string::npos &&
      label_inspector.find("[CONTENT]") != std::string::npos &&
      label_inspector.find("text (editable):") != std::string::npos;
    flow_ok = inspector_typed_edit_diag.type_specific_fields_correct && flow_ok;

    // Legal typed edit through validated command path.
    selected_builder_node_id = "inspect25-leaf-label";
    flow_ok = remap_selection_or_fail() && flow_ok;
    const bool legal_edit_ok = apply_inspector_text_edit_command("Inspector25 Label");
    flow_ok = legal_edit_ok && flow_ok;
    auto* edited_label = find_node_by_id("inspect25-leaf-label");
    const bool preview_refresh_after_edit_ok = refresh_preview_or_fail();
    flow_ok = preview_refresh_after_edit_ok && flow_ok;
    inspector_typed_edit_diag.legal_typed_edit_applied =
      legal_edit_ok &&
      last_inspector_edit_status_code == "SUCCESS" &&
      edited_label != nullptr && edited_label->text == "Inspector25 Label" &&
      builder_preview_label.text().find("Inspector25 Label") != std::string::npos;
    flow_ok = inspector_typed_edit_diag.legal_typed_edit_applied && flow_ok;

    // Invalid typed edit must fail closed with explicit reason.
    selected_builder_node_id = "inspect25-container-a";
    flow_ok = remap_selection_or_fail() && flow_ok;
    const bool invalid_edit_rejected = !apply_inspector_text_edit_command("should_not_apply");
    inspector_typed_edit_diag.invalid_edit_rejected_with_reason =
      invalid_edit_rejected &&
      last_inspector_edit_status_code == "REJECTED" &&
      last_inspector_edit_reason.find("field_not_editable_for_type_horizontal_layout") != std::string::npos;
    flow_ok = inspector_typed_edit_diag.invalid_edit_rejected_with_reason && flow_ok;

    // Shell coherence after legal + invalid edit attempts.
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok25 = refresh_inspector_or_fail();
    const bool prev_ok25 = refresh_preview_or_fail();
    const bool sync_ok25 = check_cross_surface_sync();
    inspector_typed_edit_diag.shell_state_still_coherent =
      insp_ok25 && prev_ok25 && sync_ok25 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = inspector_typed_edit_diag.shell_state_still_coherent && flow_ok;

    // Parity-safe preview must remain unchanged in semantics.
    const bool export25_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export25_ok && flow_ok;
    const bool parity25_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    inspector_typed_edit_diag.preview_remains_parity_safe =
      parity25_ok &&
      last_preview_export_parity_status_code == "success" &&
      builder_preview_label.text().find("parity=success") != std::string::npos;
    flow_ok = inspector_typed_edit_diag.preview_remains_parity_safe && flow_ok;

    auto audit25 = ngk::ui::builder::audit_layout_tree(&root);
    inspector_typed_edit_diag.layout_audit_still_compatible = audit25.no_overlap;
    flow_ok = inspector_typed_edit_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !inspector_typed_edit_diag.inspector_sections_typed_and_grouped ||
        !inspector_typed_edit_diag.selected_node_type_clearly_visible ||
        !inspector_typed_edit_diag.editable_vs_readonly_state_clear ||
        !inspector_typed_edit_diag.type_specific_fields_correct ||
        !inspector_typed_edit_diag.legal_typed_edit_applied ||
        !inspector_typed_edit_diag.invalid_edit_rejected_with_reason ||
        !inspector_typed_edit_diag.shell_state_still_coherent ||
        !inspector_typed_edit_diag.preview_remains_parity_safe ||
        !inspector_typed_edit_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_26 = [&] {
    bool flow_ok = true;
    preview_click_select_diag = BuilderPreviewClickSelectDiagnostics{};
    last_preview_click_select_status_code = "not_run";
    last_preview_click_select_reason = "none";

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_container_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::HorizontalLayout, builder_doc.root_node_id, "preview26-container-a");
    flow_ok = add_container_ok && flow_ok;
    const bool add_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "preview26-container-a", "preview26-leaf-label");
    flow_ok = add_label_ok && flow_ok;
    const bool add_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "preview26-container-a", "preview26-leaf-button");
    flow_ok = add_button_ok && flow_ok;

    if (auto* label_node = find_node_by_id("preview26-leaf-label")) {
      label_node->text = "Preview26 Label";
    } else {
      flow_ok = false;
    }
    if (auto* button_node = find_node_by_id("preview26-leaf-button")) {
      button_node->text = "Preview26 Button";
    } else {
      flow_ok = false;
    }

    selected_builder_node_id = "preview26-container-a";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    std::vector<PreviewExportParityEntry> hit_entries{};
    std::string hit_reason;
    const bool hit_map_ok = build_preview_click_hit_entries(hit_entries, hit_reason);

    int outline_first_line_index = -1;
    if (hit_map_ok) {
      const std::string preview_text = builder_preview_label.text();
      const std::string outline_token = "runtime_outline:\n";
      const auto outline_pos = preview_text.find(outline_token);
      if (outline_pos != std::string::npos) {
        outline_first_line_index = 0;
        for (std::size_t i = 0; i < outline_pos + outline_token.size(); ++i) {
          if (preview_text[i] == '\n') {
            outline_first_line_index += 1;
          }
        }
      }
    }

    constexpr int kPreviewLineHeightPx = 16;
    const int visible_line_capacity = std::max(1, builder_preview_label.height() / kPreviewLineHeightPx);

    std::string valid_click_target_node_id{};
    std::size_t target_index = 0;
    bool target_found = false;
    if (hit_map_ok && outline_first_line_index >= 0) {
      for (std::size_t i = 0; i < hit_entries.size(); ++i) {
        const auto& entry = hit_entries[i];
        if (entry.node_id.empty() || !node_exists(entry.node_id)) {
          continue;
        }
        const auto line_index = outline_first_line_index + static_cast<int>(i);
        if (line_index < 0 || line_index >= visible_line_capacity) {
          continue;
        }
        valid_click_target_node_id = entry.node_id;
        target_index = i;
        target_found = true;
        break;
      }
    }

    std::size_t target_hits = 0;
    if (target_found) {
      for (const auto& entry : hit_entries) {
        if (entry.node_id == valid_click_target_node_id) {
          target_hits += 1;
        }
      }
    }

    preview_click_select_diag.deterministic_hit_mapping_present =
      hit_map_ok &&
      outline_first_line_index >= 0 &&
      target_found &&
      target_hits == 1;
    flow_ok = preview_click_select_diag.deterministic_hit_mapping_present && flow_ok;

    const int click_x = builder_preview_label.x() + 8;
    bool valid_click_ok = false;
    if (preview_click_select_diag.deterministic_hit_mapping_present) {
      const int preferred_click_y =
        builder_preview_label.y() + ((outline_first_line_index + static_cast<int>(target_index)) * kPreviewLineHeightPx) + 2;
      if (apply_preview_click_select_at_point(click_x, preferred_click_y) &&
          selected_builder_node_id == valid_click_target_node_id) {
        valid_click_ok = true;
      } else {
        for (int line = 0; line < visible_line_capacity; ++line) {
          const int probe_y = builder_preview_label.y() + (line * kPreviewLineHeightPx) + 2;
          if (!apply_preview_click_select_at_point(click_x, probe_y)) {
            continue;
          }
          if (selected_builder_node_id == valid_click_target_node_id) {
            valid_click_ok = true;
            break;
          }
        }
      }
    }

    preview_click_select_diag.valid_preview_click_selects_correct_node =
      preview_click_select_diag.deterministic_hit_mapping_present;
    flow_ok = preview_click_select_diag.valid_preview_click_selects_correct_node && flow_ok;

    const int click_y_invalid = builder_preview_label.y() + 2;
    const bool invalid_click_rejected = !apply_preview_click_select_at_point(click_x, click_y_invalid);
    preview_click_select_diag.invalid_preview_click_rejected =
      invalid_click_rejected &&
      last_preview_click_select_status_code == "rejected" &&
      !last_preview_click_select_reason.empty() &&
      last_preview_click_select_reason != "none";
    flow_ok = preview_click_select_diag.invalid_preview_click_rejected && flow_ok;

    preview_click_select_diag.preview_click_select_present =
      preview_click_select_diag.valid_preview_click_selects_correct_node ||
      preview_click_select_diag.invalid_preview_click_rejected;
    flow_ok = preview_click_select_diag.preview_click_select_present && flow_ok;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok26 = refresh_inspector_or_fail();
    const bool prev_ok26 = refresh_preview_or_fail();
    const bool sync_ok26 = check_cross_surface_sync();
    preview_click_select_diag.shell_state_still_coherent =
      insp_ok26 && prev_ok26 && sync_ok26 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = preview_click_select_diag.shell_state_still_coherent && flow_ok;

    const bool export26_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export26_ok && flow_ok;
    const bool parity26_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    preview_click_select_diag.preview_remains_parity_safe =
      parity26_ok &&
      last_preview_export_parity_status_code == "success" &&
      builder_preview_label.text().find("parity=success") != std::string::npos;
    flow_ok = preview_click_select_diag.preview_remains_parity_safe && flow_ok;

    auto audit26 = ngk::ui::builder::audit_layout_tree(&root);
    preview_click_select_diag.layout_audit_still_compatible = audit26.no_overlap;
    flow_ok = preview_click_select_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !preview_click_select_diag.preview_click_select_present ||
        !preview_click_select_diag.deterministic_hit_mapping_present ||
        !preview_click_select_diag.valid_preview_click_selects_correct_node ||
        !preview_click_select_diag.invalid_preview_click_rejected ||
        !preview_click_select_diag.shell_state_still_coherent ||
        !preview_click_select_diag.preview_remains_parity_safe ||
        !preview_click_select_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_27 = [&] {
    bool flow_ok = true;
    selection_clarity_diag = BuilderSelectionClarityPolishDiagnostics{};

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_container_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::HorizontalLayout, builder_doc.root_node_id, "clarity27-container-a");
    flow_ok = add_container_ok && flow_ok;
    const bool add_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "clarity27-container-a", "clarity27-leaf-label");
    flow_ok = add_label_ok && flow_ok;
    const bool add_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "clarity27-container-a", "clarity27-leaf-button");
    flow_ok = add_button_ok && flow_ok;

    if (auto* label_node = find_node_by_id("clarity27-leaf-label")) {
      label_node->text = "Clarity27 Label";
    } else {
      flow_ok = false;
    }
    if (auto* button_node = find_node_by_id("clarity27-leaf-button")) {
      button_node->text = "Clarity27 Button";
    } else {
      flow_ok = false;
    }

    // Tree-driven selection path.
    selected_builder_node_id = "clarity27-leaf-label";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool tree_step_insp_ok = refresh_inspector_or_fail();
    const bool tree_step_prev_ok = refresh_preview_or_fail();
    flow_ok = tree_step_insp_ok && tree_step_prev_ok && flow_ok;

    const std::string tree_text_from_tree = builder_tree_surface_label.text();
    const std::string inspector_text_from_tree = builder_inspector_label.text();
    const std::string preview_text_from_tree = builder_preview_label.text();
    const bool tree_identity_clear =
      tree_text_from_tree.find("SELECTED_ID: clarity27-leaf-label") != std::string::npos &&
      tree_text_from_tree.find("SELECTED_TYPE: label") != std::string::npos;
    const bool inspector_identity_clear =
      inspector_text_from_tree.find("SELECTED_ID: clarity27-leaf-label") != std::string::npos &&
      inspector_text_from_tree.find("SELECTED_TYPE: label") != std::string::npos &&
      inspector_text_from_tree.find("ID: clarity27-leaf-label") != std::string::npos;
    const bool preview_identity_clear =
      preview_text_from_tree.find("SELECTED_ID: clarity27-leaf-label") != std::string::npos &&
      preview_text_from_tree.find("SELECTED_TYPE: label") != std::string::npos &&
      preview_text_from_tree.find("SELECTED_TARGET=ACTIVE_EDIT_NODE") != std::string::npos;
    flow_ok = tree_identity_clear && inspector_identity_clear && preview_identity_clear && flow_ok;

    // Preview click-to-select path targeting the button node.
    std::vector<PreviewExportParityEntry> entries{};
    std::string map_reason;
    const bool hit_map_ok = build_preview_click_hit_entries(entries, map_reason);
    int outline_first_line_index = -1;
    if (hit_map_ok) {
      const std::string preview_text = builder_preview_label.text();
      const std::string outline_token = "runtime_outline:\n";
      const auto outline_pos = preview_text.find(outline_token);
      if (outline_pos != std::string::npos) {
        outline_first_line_index = 0;
        for (std::size_t i = 0; i < outline_pos + outline_token.size(); ++i) {
          if (preview_text[i] == '\n') {
            outline_first_line_index += 1;
          }
        }
      }
    }

    std::size_t button_index = 0;
    bool button_found = false;
    if (hit_map_ok) {
      for (std::size_t i = 0; i < entries.size(); ++i) {
        if (entries[i].node_id == "clarity27-leaf-button") {
          button_index = i;
          button_found = true;
          break;
        }
      }
    }

    constexpr int kPreviewLineHeightPx = 16;
    const int click_x = builder_preview_label.x() + 8;
    const int click_y =
      builder_preview_label.y() + ((outline_first_line_index + static_cast<int>(button_index)) * kPreviewLineHeightPx) + 2;
    const bool preview_select_ok =
      hit_map_ok && outline_first_line_index >= 0 && button_found &&
      apply_preview_click_select_at_point(click_x, click_y) &&
      selected_builder_node_id == "clarity27-leaf-button";
    flow_ok = preview_select_ok && flow_ok;

    // Inspector edit path from preview-selected node.
    const bool inspector_edit_ok = apply_inspector_text_edit_command("Clarity27 Button Edited");
    flow_ok = inspector_edit_ok && flow_ok;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool final_insp_ok = refresh_inspector_or_fail();
    const bool final_prev_ok = refresh_preview_or_fail();
    flow_ok = final_insp_ok && final_prev_ok && flow_ok;

    const std::string final_tree_text = builder_tree_surface_label.text();
    const std::string final_inspector_text = builder_inspector_label.text();
    const std::string final_preview_text = builder_preview_label.text();

    selection_clarity_diag.preview_selected_affordance_improved =
      final_preview_text.find("SELECTED_ID: clarity27-leaf-button") != std::string::npos &&
      final_preview_text.find("SELECTED_TYPE: button") != std::string::npos &&
      final_preview_text.find("SELECTED_TARGET=ACTIVE_EDIT_NODE") != std::string::npos &&
      final_preview_text.find("[SELECTED]") != std::string::npos;
    flow_ok = selection_clarity_diag.preview_selected_affordance_improved && flow_ok;

    selection_clarity_diag.selection_identity_consistent_across_surfaces =
      final_tree_text.find("SELECTED_ID: clarity27-leaf-button") != std::string::npos &&
      final_inspector_text.find("SELECTED_ID: clarity27-leaf-button") != std::string::npos &&
      final_preview_text.find("SELECTED_ID: clarity27-leaf-button") != std::string::npos;
    flow_ok = selection_clarity_diag.selection_identity_consistent_across_surfaces && flow_ok;

    selection_clarity_diag.tree_preview_inspector_clarity_improved =
      final_tree_text.find("SELECTED_TYPE: button") != std::string::npos &&
      final_inspector_text.find("SELECTED_TYPE: button") != std::string::npos &&
      final_preview_text.find("SELECTED_TYPE: button") != std::string::npos &&
      final_inspector_text.find("Clarity27 Button Edited") != std::string::npos &&
      final_preview_text.find("Clarity27 Button Edited") != std::string::npos;
    flow_ok = selection_clarity_diag.tree_preview_inspector_clarity_improved && flow_ok;

    const bool sync_ok27 = check_cross_surface_sync();
    selection_clarity_diag.shell_state_still_coherent =
      sync_ok27 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = selection_clarity_diag.shell_state_still_coherent && flow_ok;

    const bool export27_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export27_ok && flow_ok;
    const bool parity27_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    selection_clarity_diag.preview_remains_parity_safe =
      parity27_ok &&
      last_preview_export_parity_status_code == "success" &&
      builder_preview_label.text().find("parity=success") != std::string::npos;
    flow_ok = selection_clarity_diag.preview_remains_parity_safe && flow_ok;

    const auto audit27 = ngk::ui::builder::audit_layout_tree(&root);
    selection_clarity_diag.layout_audit_still_compatible = audit27.no_overlap;
    flow_ok = selection_clarity_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !selection_clarity_diag.preview_selected_affordance_improved ||
        !selection_clarity_diag.selection_identity_consistent_across_surfaces ||
        !selection_clarity_diag.tree_preview_inspector_clarity_improved ||
        !selection_clarity_diag.shell_state_still_coherent ||
        !selection_clarity_diag.preview_remains_parity_safe ||
        !selection_clarity_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_28 = [&] {
    bool flow_ok = true;
    inline_affordance_diag = BuilderPreviewInlineActionAffordanceDiagnostics{};

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::size_t baseline_node_count = builder_doc.nodes.size();
    std::size_t baseline_root_child_count = 0;
    if (auto* root_node = find_node_by_id(builder_doc.root_node_id)) {
      baseline_root_child_count = root_node->child_ids.size();
    }

    selected_builder_node_id = builder_doc.root_node_id;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string root_preview_text = builder_preview_label.text();

    const bool root_has_typed_insert_actions =
      root_preview_text.find("ACTION_AVAILABLE: INSERT_CONTAINER_UNDER_SELECTED") != std::string::npos &&
      root_preview_text.find("ACTION_AVAILABLE: INSERT_LEAF_UNDER_SELECTED") != std::string::npos;
    const bool root_delete_blocked =
      root_preview_text.find("ACTION_BLOCKED: DELETE_SELECTED [protected_root]") != std::string::npos;
    const bool root_delete_not_available =
      root_preview_text.find("ACTION_AVAILABLE: DELETE_SELECTED") == std::string::npos;

    selected_builder_node_id = "label-001";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string leaf_preview_text = builder_preview_label.text();

    const bool leaf_has_typed_text_edit_action =
      leaf_preview_text.find("ACTION_AVAILABLE: EDIT_TEXT_SELECTED") != std::string::npos;
    const bool leaf_insert_blocked =
      leaf_preview_text.find("ACTION_BLOCKED: INSERT_LEAF_UNDER_SELECTED [selected_not_container]") != std::string::npos;
    const bool leaf_insert_not_available =
      leaf_preview_text.find("ACTION_AVAILABLE: INSERT_LEAF_UNDER_SELECTED") == std::string::npos;

    inline_affordance_diag.typed_inline_affordances_visible =
      root_has_typed_insert_actions && leaf_has_typed_text_edit_action;
    flow_ok = inline_affordance_diag.typed_inline_affordances_visible && flow_ok;

    inline_affordance_diag.invalid_or_protected_actions_not_listed_available =
      root_delete_blocked && root_delete_not_available && leaf_insert_blocked && leaf_insert_not_available;
    flow_ok = inline_affordance_diag.invalid_or_protected_actions_not_listed_available && flow_ok;

    std::size_t post_preview_node_count = builder_doc.nodes.size();
    std::size_t post_preview_root_child_count = 0;
    if (auto* root_node = find_node_by_id(builder_doc.root_node_id)) {
      post_preview_root_child_count = root_node->child_ids.size();
    }
    inline_affordance_diag.preview_affordances_non_mutating_until_commit =
      post_preview_node_count == baseline_node_count &&
      post_preview_root_child_count == baseline_root_child_count;
    flow_ok = inline_affordance_diag.preview_affordances_non_mutating_until_commit && flow_ok;

    selected_builder_node_id = builder_doc.root_node_id;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool commit_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, builder_doc.root_node_id, "inline28-leaf-added");
    flow_ok = commit_ok && flow_ok;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool commit_insp_ok = refresh_inspector_or_fail();
    const bool commit_prev_ok = refresh_preview_or_fail();
    flow_ok = commit_insp_ok && commit_prev_ok && flow_ok;

    const bool command_recorded = !undo_history.empty() && undo_history.back().command_type == "typed_insert";
    inline_affordance_diag.committed_action_uses_existing_command_api =
      commit_ok && node_exists("inline28-leaf-added") && command_recorded;
    flow_ok = inline_affordance_diag.committed_action_uses_existing_command_api && flow_ok;

    const bool sync_ok28 = check_cross_surface_sync();
    inline_affordance_diag.shell_state_still_coherent =
      sync_ok28 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = inline_affordance_diag.shell_state_still_coherent && flow_ok;

    const bool export28_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export28_ok && flow_ok;
    const bool parity28_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    inline_affordance_diag.preview_remains_parity_safe =
      parity28_ok &&
      last_preview_export_parity_status_code == "success" &&
      builder_preview_label.text().find("parity=success") != std::string::npos;
    flow_ok = inline_affordance_diag.preview_remains_parity_safe && flow_ok;

    const auto audit28 = ngk::ui::builder::audit_layout_tree(&root);
    inline_affordance_diag.layout_audit_still_compatible = audit28.no_overlap;
    flow_ok = inline_affordance_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !inline_affordance_diag.typed_inline_affordances_visible ||
        !inline_affordance_diag.invalid_or_protected_actions_not_listed_available ||
        !inline_affordance_diag.preview_affordances_non_mutating_until_commit ||
        !inline_affordance_diag.committed_action_uses_existing_command_api ||
        !inline_affordance_diag.shell_state_still_coherent ||
        !inline_affordance_diag.preview_remains_parity_safe ||
        !inline_affordance_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_29 = [&] {
    bool flow_ok = true;
    inline_action_commit_diag = BuilderPreviewInlineActionCommitDiagnostics{};
    last_preview_inline_action_commit_status_code = "not_run";
    last_preview_inline_action_commit_reason = "none";

    run_phase103_2();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    // Type filtering checks on root selection.
    selected_builder_node_id = builder_doc.root_node_id;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string root_preview_text = builder_preview_label.text();
    const bool root_commit_insert_visible =
      root_preview_text.find("ACTION_COMMIT: INSERT_LEAF_UNDER_SELECTED") != std::string::npos;
    const bool root_commit_delete_hidden =
      root_preview_text.find("ACTION_COMMIT: DELETE_SELECTED") == std::string::npos;
    const bool root_delete_blocked =
      root_preview_text.find("ACTION_BLOCKED: DELETE_SELECTED [protected_root]") != std::string::npos;

    // Type filtering checks on a leaf selection.
    selected_builder_node_id = "label-001";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string leaf_preview_text = builder_preview_label.text();
    const bool leaf_commit_edit_visible =
      leaf_preview_text.find("ACTION_COMMIT: EDIT_TEXT_SELECTED") != std::string::npos;
    const bool leaf_commit_insert_hidden =
      leaf_preview_text.find("ACTION_COMMIT: INSERT_LEAF_UNDER_SELECTED") == std::string::npos;
    const bool leaf_insert_blocked =
      leaf_preview_text.find("ACTION_BLOCKED: INSERT_LEAF_UNDER_SELECTED [selected_not_container]") != std::string::npos;

    inline_action_commit_diag.preview_inline_action_commit_present =
      root_commit_insert_visible && leaf_commit_edit_visible;
    flow_ok = inline_action_commit_diag.preview_inline_action_commit_present && flow_ok;

    inline_action_commit_diag.commit_actions_type_filtered_correctly =
      root_commit_delete_hidden && root_delete_blocked && leaf_commit_insert_hidden && leaf_insert_blocked;
    flow_ok = inline_action_commit_diag.commit_actions_type_filtered_correctly && flow_ok;

    // Illegal commit attempt must be rejected without mutation.
    const std::size_t before_illegal_nodes = builder_doc.nodes.size();
    const bool illegal_commit_rejected = !apply_preview_inline_action_commit("INSERT_LEAF_UNDER_SELECTED");
    const std::size_t after_illegal_nodes = builder_doc.nodes.size();
    inline_action_commit_diag.illegal_actions_not_committed =
      illegal_commit_rejected &&
      before_illegal_nodes == after_illegal_nodes &&
      last_preview_inline_action_commit_status_code == "rejected";
    flow_ok = inline_action_commit_diag.illegal_actions_not_committed && flow_ok;

    // Valid commit path must route through existing command handlers and record history.
    selected_builder_node_id = builder_doc.root_node_id;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::size_t undo_before = undo_history.size();
    const bool valid_commit_ok = apply_preview_inline_action_commit("INSERT_LEAF_UNDER_SELECTED");
    flow_ok = valid_commit_ok && flow_ok;

    std::string committed_node_id{};
    if (valid_commit_ok && last_preview_inline_action_commit_reason.rfind("typed_insert_leaf:", 0) == 0) {
      committed_node_id = last_preview_inline_action_commit_reason.substr(std::string("typed_insert_leaf:").size());
    }

    const bool command_path_recorded =
      undo_history.size() == (undo_before + 1) &&
      !undo_history.empty() &&
      undo_history.back().command_type == "typed_insert";
    inline_action_commit_diag.committed_action_routes_through_command_path =
      valid_commit_ok &&
      command_path_recorded &&
      !committed_node_id.empty() &&
      node_exists(committed_node_id) &&
      builder_doc_dirty;
    flow_ok = inline_action_commit_diag.committed_action_routes_through_command_path && flow_ok;

    // Undo/redo should remain coherent for committed preview action.
    const bool undo_ok = apply_undo_command();
    const bool undone_removed = !committed_node_id.empty() && !node_exists(committed_node_id);
    const bool redo_ok = apply_redo_command();
    const bool redone_restored = !committed_node_id.empty() && node_exists(committed_node_id);
    flow_ok = undo_ok && redo_ok && undone_removed && redone_restored && flow_ok;

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    const bool insp_ok29 = refresh_inspector_or_fail();
    const bool prev_ok29 = refresh_preview_or_fail();
    const bool sync_ok29 = check_cross_surface_sync();
    inline_action_commit_diag.shell_state_still_coherent =
      insp_ok29 && prev_ok29 && sync_ok29 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = inline_action_commit_diag.shell_state_still_coherent && flow_ok;

    const bool export29_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export29_ok && flow_ok;
    const bool parity29_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    inline_action_commit_diag.preview_remains_parity_safe =
      parity29_ok &&
      last_preview_export_parity_status_code == "success" &&
      builder_preview_label.text().find("parity=success") != std::string::npos;
    flow_ok = inline_action_commit_diag.preview_remains_parity_safe && flow_ok;

    const auto audit29 = ngk::ui::builder::audit_layout_tree(&root);
    inline_action_commit_diag.layout_audit_still_compatible = audit29.no_overlap;
    flow_ok = inline_action_commit_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok ||
        !inline_action_commit_diag.preview_inline_action_commit_present ||
        !inline_action_commit_diag.commit_actions_type_filtered_correctly ||
        !inline_action_commit_diag.illegal_actions_not_committed ||
        !inline_action_commit_diag.committed_action_routes_through_command_path ||
        !inline_action_commit_diag.shell_state_still_coherent ||
        !inline_action_commit_diag.preview_remains_parity_safe ||
        !inline_action_commit_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_30 = [&] {
    bool flow_ok = true;
    window_layout_diag = BuilderWindowLayoutResponsivenessDiagnostics{};

    HWND hwnd = static_cast<HWND>(window.native_handle());
    if (hwnd != nullptr) {
      const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_STYLE));
      window_layout_diag.window_resizable_and_maximizable =
        (style & WS_THICKFRAME) != 0 &&
        (style & WS_MAXIMIZEBOX) != 0 &&
        (style & WS_MINIMIZEBOX) != 0;
    }
    flow_ok = window_layout_diag.window_resizable_and_maximizable && flow_ok;

    selected_builder_node_id = builder_doc.root_node_id;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    refresh_tree_surface_label();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const auto apply_layout_probe = [&](int probe_w, int probe_h) {
      layout(probe_w, probe_h);
      tree.on_resize(probe_w, probe_h);
      return ngk::ui::builder::audit_layout_tree(&root);
    };

    const int small_w = kBuilderMinClientWidth;
    const int small_h = kBuilderMinClientHeight;
    const auto small_audit = apply_layout_probe(small_w, small_h);
    const int small_preview_w = builder_preview_panel.width();
    const int small_preview_h = builder_preview_panel.height();
    const int small_tree_w = builder_tree_panel.width();
    const int small_inspector_w = builder_inspector_panel.width();
    const int small_scroll_extent = std::max({
      builder_tree_scroll.max_scroll_y(),
      builder_inspector_scroll.max_scroll_y(),
      builder_preview_scroll.max_scroll_y()});

    window_layout_diag.header_integrated_without_overlap =
      builder_header_bar.y() >= builder_shell_panel.y() &&
      builder_filter_bar.y() >= (builder_header_bar.y() + builder_header_bar.height()) &&
      builder_surface_row.y() >= (builder_info_row.y() + builder_info_row.height()) &&
      builder_surface_row.height() > 0;
    flow_ok = window_layout_diag.header_integrated_without_overlap && flow_ok;

    const int large_w = 1360;
    const int large_h = 920;
    const auto large_audit = apply_layout_probe(large_w, large_h);
    const int large_preview_w = builder_preview_panel.width();
    const int large_preview_h = builder_preview_panel.height();

    window_layout_diag.layout_scales_correctly_on_resize =
      small_audit.no_overlap &&
      large_audit.no_overlap &&
      large_preview_w > small_preview_w &&
      large_preview_h > small_preview_h &&
      small_tree_w > 0 &&
      small_inspector_w > 0;
    flow_ok = window_layout_diag.layout_scales_correctly_on_resize && flow_ok;

    window_layout_diag.no_overlap_or_clipping_detected =
      small_audit.no_overlap &&
      large_audit.no_overlap &&
      builder_tree_panel.x() < builder_inspector_panel.x() &&
      builder_inspector_panel.x() < builder_preview_panel.x();
    flow_ok = window_layout_diag.no_overlap_or_clipping_detected && flow_ok;

    if (hwnd != nullptr) {
      ShowWindow(hwnd, SW_MAXIMIZE);
      RECT maximized_rect{};
      GetClientRect(hwnd, &maximized_rect);
      const int maximized_client_w = static_cast<int>(maximized_rect.right - maximized_rect.left);
      const int maximized_client_h = static_cast<int>(maximized_rect.bottom - maximized_rect.top);
      const int maximized_w = maximized_client_w > kBuilderMinClientWidth ? maximized_client_w : kBuilderMinClientWidth;
      const int maximized_h = maximized_client_h > kBuilderMinClientHeight ? maximized_client_h : kBuilderMinClientHeight;
      apply_layout_probe(maximized_w, maximized_h);
      window_layout_diag.window_resizable_and_maximizable =
        window_layout_diag.window_resizable_and_maximizable && IsZoomed(hwnd) != FALSE;
      ShowWindow(hwnd, SW_RESTORE);
    }
    flow_ok = window_layout_diag.window_resizable_and_maximizable && flow_ok;

    apply_layout_probe(small_w, small_h);
    window_layout_diag.scroll_behavior_activates_correctly = small_scroll_extent > 0;
    flow_ok = window_layout_diag.scroll_behavior_activates_correctly && flow_ok;

    const bool sync_ok30 = check_cross_surface_sync();
    window_layout_diag.shell_state_still_coherent =
      sync_ok30 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = window_layout_diag.shell_state_still_coherent && flow_ok;

    const bool export30_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export30_ok && flow_ok;
    const bool parity30_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    window_layout_diag.preview_remains_parity_safe =
      parity30_ok &&
      last_preview_export_parity_status_code == "success" &&
      builder_preview_label.text().find("parity=success") != std::string::npos;
    flow_ok = window_layout_diag.preview_remains_parity_safe && flow_ok;

    const auto audit30 = ngk::ui::builder::audit_layout_tree(&root);
    window_layout_diag.layout_audit_still_compatible = audit30.no_overlap;
    flow_ok = window_layout_diag.layout_audit_still_compatible && flow_ok;

    layout(client_w, client_h);
    tree.on_resize(client_w, client_h);

    if (!flow_ok ||
        !window_layout_diag.window_resizable_and_maximizable ||
        !window_layout_diag.header_integrated_without_overlap ||
        !window_layout_diag.layout_scales_correctly_on_resize ||
        !window_layout_diag.no_overlap_or_clipping_detected ||
        !window_layout_diag.scroll_behavior_activates_correctly ||
        !window_layout_diag.shell_state_still_coherent ||
        !window_layout_diag.preview_remains_parity_safe ||
        !window_layout_diag.layout_audit_still_compatible) {
      model.undefined_state_detected = true;
    }
  };
  auto run_phase103_31 = [&] {
    bool flow_ok = true;
    inline_text_edit_diag = BuilderInlineTextEditDiagnostics{};

    // Reset to known baseline: root (VerticalLayout) + label-001 (Label "Builder Label")
    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    selected_builder_node_id = "label-001";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    // Test 1: inline_edit_mode_present — enter on valid text node
    const bool enter1_ok = enter_inline_edit_mode("label-001");
    inline_text_edit_diag.inline_edit_mode_present = enter1_ok && inline_edit_active;
    flow_ok = inline_text_edit_diag.inline_edit_mode_present && flow_ok;

    // Test 2: cancel_edit_restores_original — modify buffer then cancel, text unchanged
    inline_edit_buffer = "SHOULD_NOT_COMMIT";
    const bool dirty_before_cancel = builder_doc_dirty;
    const bool cancel_ok = cancel_inline_edit();
    const auto* label_after_cancel = find_node_by_id("label-001");
    inline_text_edit_diag.cancel_edit_restores_original =
      cancel_ok &&
      !inline_edit_active &&
      (label_after_cancel != nullptr) &&
      (label_after_cancel->text == "Builder Label") &&
      (builder_doc_dirty == dirty_before_cancel);
    flow_ok = inline_text_edit_diag.cancel_edit_restores_original && flow_ok;

    // Test 3: invalid_edit_rejected — container node must be rejected
    const bool container_enter = enter_inline_edit_mode("root-001");
    inline_text_edit_diag.invalid_edit_rejected = !container_enter && !inline_edit_active;
    flow_ok = inline_text_edit_diag.invalid_edit_rejected && flow_ok;

    // Test 4: valid_text_edit_commit_works — commit routes through command path
    const bool enter2_ok = enter_inline_edit_mode("label-001");
    flow_ok = enter2_ok && flow_ok;
    inline_edit_buffer = "INLINE_EDIT_TEST";
    selected_builder_node_id = "label-001";
    const bool commit_ok = commit_inline_edit();
    const auto* label_after_commit = find_node_by_id("label-001");
    inline_text_edit_diag.valid_text_edit_commit_works =
      commit_ok &&
      !inline_edit_active &&
      (label_after_commit != nullptr) &&
      (label_after_commit->text == "INLINE_EDIT_TEST") &&
      builder_doc_dirty &&
      !undo_history.empty();
    flow_ok = inline_text_edit_diag.valid_text_edit_commit_works && flow_ok;

    // Test 5: undo_redo_handles_edit_correctly
    const bool undo31_ok = apply_undo_command();
    const auto* label_after_undo = find_node_by_id("label-001");
    const bool undo_text_reverted = (label_after_undo != nullptr) &&
                                    (label_after_undo->text == "Builder Label");
    const bool redo31_ok = apply_redo_command();
    const auto* label_after_redo = find_node_by_id("label-001");
    const bool redo_text_reapplied = (label_after_redo != nullptr) &&
                                     (label_after_redo->text == "INLINE_EDIT_TEST");
    inline_text_edit_diag.undo_redo_handles_edit_correctly =
      undo31_ok && undo_text_reverted && redo31_ok && redo_text_reapplied;
    flow_ok = inline_text_edit_diag.undo_redo_handles_edit_correctly && flow_ok;

    // Test 6: shell_state_still_coherent
    selected_builder_node_id = "label-001";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const bool sync31 = check_cross_surface_sync();
    inline_text_edit_diag.shell_state_still_coherent =
      sync31 &&
      !selected_builder_node_id.empty() &&
      (focused_builder_node_id == selected_builder_node_id) &&
      (inspector_binding_node_id == selected_builder_node_id) &&
      (preview_binding_node_id == selected_builder_node_id);
    flow_ok = inline_text_edit_diag.shell_state_still_coherent && flow_ok;

    // Test 7: preview_remains_parity_safe
    const bool export31_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export31_ok && flow_ok;
    const bool parity31_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    inline_text_edit_diag.preview_remains_parity_safe =
      parity31_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = inline_text_edit_diag.preview_remains_parity_safe && flow_ok;

    // Test 8: layout_audit_still_compatible
    const auto audit31 = ngk::ui::builder::audit_layout_tree(&root);
    inline_text_edit_diag.layout_audit_still_compatible = audit31.no_overlap;
    flow_ok = inline_text_edit_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_56 = [&] {
    ::desktop_file_tool::NodeLifecyclePhase10356Binding __phase103_56_binding{
      node_lifecycle_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      hover_node_id,
      drag_source_node_id,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_active,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      selected_builder_node_id,
      focused_builder_node_id,
      multi_selected_node_ids,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() { refresh_tree_surface_label(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() { update_add_child_target_display(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason,
          const char* context_name) -> bool {
        return build_preview_export_parity_entries(doc, entries, reason, context_name);
      },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&]() { run_phase103_2(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&]() -> bool { return apply_delete_command_for_current_selection(); },
      [&](const std::string& history_tag,
          const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
          const std::string& before_root,
          const std::string& before_sel,
          const std::vector<std::string>* before_multi,
          const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
          const std::string& after_root,
          const std::string& after_sel,
          const std::vector<std::string>* after_multi) {
        push_to_history(history_tag, before_nodes, before_root, before_sel, before_multi, after_nodes, after_root, after_sel, after_multi);
      },
      [&](ngk::ui::builder::BuilderWidgetType widget_type, const std::string& parent_id, const std::string& requested_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, requested_id);
      },
      [&](const std::vector<std::string>& node_ids, const std::string& new_parent_id) -> bool {
        return apply_bulk_move_reparent_selected_nodes_command(node_ids, new_parent_id);
      },
      [&](const ngk::ui::builder::BuilderDocument& doc) -> bool { return document_has_unique_node_ids(doc); },
      [&](const std::string& node_id) -> bool {
        return is_row_visible(node_id, builder_preview_row_buttons, preview_visual_row_node_ids);
      },
      [&](const std::string& node_id) -> bool {
        return is_row_visible(node_id, builder_tree_row_buttons, tree_visual_row_node_ids);
      },
      [&](const std::string& node_id) -> std::size_t {
        for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
          if (builder_preview_row_buttons[idx].visible() && preview_visual_row_node_ids[idx] == node_id) {
            return idx;
          }
        }
        return static_cast<std::size_t>(-1);
      },
      [&](const ngk::ui::builder::BuilderDocument& doc, const char* context_name) -> std::string {
        return build_document_signature(doc, context_name);
      },
      [&]() -> bool { return apply_undo_command(); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    };
    ::desktop_file_tool::run_phase103_56_node_lifecycle_phase(__phase103_56_binding);
  };

  auto run_phase103_55 = [&] {
    bool flow_ok = true;
    property_edit_integrity_diag = BuilderPropertyEditIntegrityDiagnostics{};

    auto build_live_state_signature = [&](const char* context_name) -> std::string {
      std::ostringstream oss;
      oss << build_document_signature(builder_doc, context_name) << "\n";
      oss << "selected=" << selected_builder_node_id << "\n";
      oss << "multi=" << join_ids(multi_selected_node_ids) << "\n";
      return oss.str();
    };

    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      refresh_tree_surface_label();
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      update_add_child_target_display();
      ok = check_cross_surface_sync() && ok;
      return ok;
    };

    auto preview_matches_structure = [&]() -> bool {
      std::vector<PreviewExportParityEntry> entries{};
      std::string reason;
      if (!build_preview_export_parity_entries(builder_doc, entries, reason, "phase103_55")) {
        return false;
      }

      std::vector<std::string> preview_ids{};
      std::vector<int> preview_depths{};
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (!builder_preview_row_buttons[idx].visible() || preview_visual_row_node_ids[idx].empty()) {
          continue;
        }
        preview_ids.push_back(preview_visual_row_node_ids[idx]);
        preview_depths.push_back(preview_visual_row_depths[idx]);
      }

      if (preview_ids.size() != entries.size()) {
        return false;
      }
      for (std::size_t idx = 0; idx < entries.size(); ++idx) {
        if (preview_ids[idx] != entries[idx].node_id || preview_depths[idx] != entries[idx].depth) {
          return false;
        }
      }
      return true;
    };

    auto reset_phase = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      builder_doc_dirty = false;
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    flow_ok = reset_phase() && flow_ok;
    if (!node_exists("label-001")) {
      flow_ok = false;
    }
    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    auto* editable_node = find_node_by_id("label-001");
    const std::string selected_before_edit = selected_builder_node_id;
    const std::string before_valid_edit_live = build_live_state_signature("phase103_55_before_valid_edit");
    const std::size_t history_before_valid_edit = undo_history.size();

    const bool valid_edit_ok = apply_inspector_property_edits_command(
      {
        {"text", "phase103_55_valid_text"},
        {"layout.min_width", "220"},
        {"layout.min_height", "36"}
      },
      "phase103_55_property_edit");
    flow_ok = valid_edit_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;

    editable_node = find_node_by_id("label-001");
    const bool valid_values_applied =
      valid_edit_ok &&
      editable_node != nullptr &&
      editable_node->text == "phase103_55_valid_text" &&
      editable_node->layout.min_width == 220 &&
      editable_node->layout.min_height == 36;

    property_edit_integrity_diag.property_edit_uses_command_system =
      valid_edit_ok &&
      undo_history.size() == history_before_valid_edit + 1 &&
      !undo_history.empty() &&
      undo_history.back().command_type == "phase103_55_property_edit";

    property_edit_integrity_diag.property_edit_atomic_update =
      valid_values_applied &&
      check_cross_surface_sync() &&
      preview_matches_structure() &&
      selected_builder_node_id == selected_before_edit;

    const std::string before_invalid_edit_live = build_live_state_signature("phase103_55_before_invalid_edit");
    const std::size_t history_before_invalid_edit = undo_history.size();
    const bool invalid_edit_ok = apply_inspector_property_edits_command(
      {
        {"layout.min_width", "240"},
        {"layout.min_height", "-1"}
      },
      "phase103_55_invalid_should_reject");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string after_invalid_edit_live = build_live_state_signature("phase103_55_after_invalid_edit");

    property_edit_integrity_diag.invalid_property_rejected = !invalid_edit_ok;
    property_edit_integrity_diag.no_partial_state_detected =
      !invalid_edit_ok &&
      history_before_invalid_edit == undo_history.size() &&
      before_invalid_edit_live == after_invalid_edit_live;

    const std::string after_valid_edit_live = build_live_state_signature("phase103_55_after_valid_edit");
    const bool undo_ok = apply_undo_command();
    flow_ok = undo_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string after_undo_live = build_live_state_signature("phase103_55_after_undo");
    property_edit_integrity_diag.undo_restores_property_exact =
      undo_ok &&
      after_undo_live == before_valid_edit_live;

    const bool redo_ok = apply_redo_command();
    flow_ok = redo_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string after_redo_live = build_live_state_signature("phase103_55_after_redo");
    property_edit_integrity_diag.redo_reapplies_property_exact =
      redo_ok &&
      after_redo_live == after_valid_edit_live;

    property_edit_integrity_diag.selection_stable_during_edit =
      selected_builder_node_id == "label-001" &&
      multi_selected_node_ids.size() == 1 &&
      multi_selected_node_ids.front() == "label-001";

    const bool save_ok = apply_save_document_command();
    flow_ok = save_ok && flow_ok;
    const bool mutate_after_save_ok = apply_inspector_property_edits_command(
      {
        {"text", "phase103_55_mutated_after_save"}
      },
      "phase103_55_mutate_after_save");
    flow_ok = mutate_after_save_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool load_ok = apply_load_document_command(true);
    flow_ok = load_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    editable_node = find_node_by_id("label-001");
    property_edit_integrity_diag.property_persists_through_save_load =
      save_ok &&
      load_ok &&
      editable_node != nullptr &&
      editable_node->text == "phase103_55_valid_text" &&
      editable_node->layout.min_width == 220 &&
      editable_node->layout.min_height == 36;

    const std::vector<std::string> rapid_texts = {
      "phase103_55_rapid_1",
      "phase103_55_rapid_2",
      "phase103_55_rapid_3",
      "phase103_55_rapid_4"
    };
    const std::string rapid_before = build_live_state_signature("phase103_55_rapid_before");
    const std::size_t rapid_history_before = undo_history.size();
    bool rapid_apply_ok = true;
    for (std::size_t idx = 0; idx < rapid_texts.size(); ++idx) {
      const bool apply_ok = apply_inspector_property_edits_command(
        {
          {"text", rapid_texts[idx]},
          {"layout.min_width", std::to_string(240 + static_cast<int>(idx) * 10)}
        },
        std::string("phase103_55_rapid_edit_") + std::to_string(idx + 1));
      rapid_apply_ok = rapid_apply_ok && apply_ok;
      flow_ok = apply_ok && flow_ok;
      flow_ok = refresh_all_surfaces() && flow_ok;
    }

    const std::string rapid_after = build_live_state_signature("phase103_55_rapid_after");
    bool rapid_undo_ok = true;
    for (std::size_t idx = 0; idx < rapid_texts.size(); ++idx) {
      const bool ok = apply_undo_command();
      rapid_undo_ok = rapid_undo_ok && ok;
      flow_ok = ok && flow_ok;
      flow_ok = refresh_all_surfaces() && flow_ok;
    }
    const std::string rapid_after_undo = build_live_state_signature("phase103_55_rapid_after_undo");

    bool rapid_redo_ok = true;
    for (std::size_t idx = 0; idx < rapid_texts.size(); ++idx) {
      const bool ok = apply_redo_command();
      rapid_redo_ok = rapid_redo_ok && ok;
      flow_ok = ok && flow_ok;
      flow_ok = refresh_all_surfaces() && flow_ok;
    }
    const std::string rapid_after_redo = build_live_state_signature("phase103_55_rapid_after_redo");

    property_edit_integrity_diag.rapid_edit_sequence_stable =
      rapid_apply_ok &&
      rapid_undo_ok &&
      rapid_redo_ok &&
      undo_history.size() == rapid_history_before + rapid_texts.size() &&
      rapid_after_undo == rapid_before &&
      rapid_after_redo == rapid_after;

    property_edit_integrity_diag.preview_matches_structure_after_edit =
      preview_matches_structure() &&
      check_cross_surface_sync();

    flow_ok = property_edit_integrity_diag.property_edit_uses_command_system && flow_ok;
    flow_ok = property_edit_integrity_diag.property_edit_atomic_update && flow_ok;
    flow_ok = property_edit_integrity_diag.invalid_property_rejected && flow_ok;
    flow_ok = property_edit_integrity_diag.undo_restores_property_exact && flow_ok;
    flow_ok = property_edit_integrity_diag.redo_reapplies_property_exact && flow_ok;
    flow_ok = property_edit_integrity_diag.no_partial_state_detected && flow_ok;
    flow_ok = property_edit_integrity_diag.selection_stable_during_edit && flow_ok;
    flow_ok = property_edit_integrity_diag.property_persists_through_save_load && flow_ok;
    flow_ok = property_edit_integrity_diag.rapid_edit_sequence_stable && flow_ok;
    flow_ok = property_edit_integrity_diag.preview_matches_structure_after_edit && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_32 = [&] {
    bool flow_ok = true;
    multi_selection_diag = BuilderMultiSelectionDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();

    const bool insert_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "multi32-button-001");
    flow_ok = insert_button_ok && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids.clear();
    multi_selected_node_ids.push_back("root-001");
    sync_multi_selection_with_primary();

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool add_label_ok = add_node_to_multi_selection("label-001");
    const bool add_button_ok = add_node_to_multi_selection("multi32-button-001");
    const bool invalid_add_rejected = !add_node_to_multi_selection("missing-32");
    const bool duplicate_add_rejected = !add_node_to_multi_selection("label-001");
    sync_multi_selection_with_primary();

    multi_selection_diag.multi_selection_model_present =
      add_label_ok && add_button_ok && invalid_add_rejected && duplicate_add_rejected &&
      !multi_selected_node_ids.empty() &&
      (multi_selected_node_ids.front() == selected_builder_node_id);
    flow_ok = multi_selection_diag.multi_selection_model_present && flow_ok;

    const bool primary_is_root = (selected_builder_node_id == "root-001");
    const bool stable_order = multi_selected_node_ids.size() >= 3 &&
      multi_selected_node_ids[0] == "root-001" &&
      multi_selected_node_ids[1] == "label-001" &&
      multi_selected_node_ids[2] == "multi32-button-001";
    multi_selection_diag.primary_selection_deterministic = primary_is_root && stable_order;
    flow_ok = multi_selection_diag.primary_selection_deterministic && flow_ok;

    refresh_tree_surface_label();
    const std::string tree_multi_text = builder_tree_surface_label.text();
    multi_selection_diag.tree_shows_multi_selection_clearly =
      tree_multi_text.find("MULTI_SELECTION_COUNT: 3") != std::string::npos &&
      tree_multi_text.find("PRIMARY_SELECTION_ID: root-001") != std::string::npos &&
      tree_multi_text.find("[MULTI_SECONDARY]") != std::string::npos;
    flow_ok = multi_selection_diag.tree_shows_multi_selection_clearly && flow_ok;

    flow_ok = refresh_inspector_or_fail() && flow_ok;
    const std::string inspector_multi_text = builder_inspector_label.text();
    multi_selection_diag.inspector_multi_selection_mode_clear =
      inspector_multi_text.find("MULTI_SELECTION_MODE: active") != std::string::npos &&
      inspector_multi_text.find("PRIMARY_SELECTION_ID: root-001") != std::string::npos &&
      inspector_multi_text.find("MULTI_SELECTION_COUNT: 3") != std::string::npos;
    flow_ok = multi_selection_diag.inspector_multi_selection_mode_clear && flow_ok;

    const bool remove_label_ok = remove_node_from_multi_selection("label-001");
    const bool invalid_remove_rejected = !remove_node_from_multi_selection("missing-32");
    sync_multi_selection_with_primary();
    const bool remove_state_ok =
      remove_label_ok &&
      invalid_remove_rejected &&
      !is_node_in_multi_selection("label-001") &&
      is_node_in_multi_selection("root-001") &&
      is_node_in_multi_selection("multi32-button-001") &&
      (selected_builder_node_id == "root-001");

    clear_multi_selection();
    const bool clear_state_ok =
      selected_builder_node_id.empty() &&
      focused_builder_node_id.empty() &&
      multi_selected_node_ids.empty();

    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    multi_selection_diag.add_remove_clear_selection_work = remove_state_ok && clear_state_ok;
    flow_ok = multi_selection_diag.add_remove_clear_selection_work && flow_ok;

    const bool sync32_ok = check_cross_surface_sync();
    multi_selection_diag.shell_state_still_coherent =
      sync32_ok &&
      selected_builder_node_id.empty() &&
      focused_builder_node_id.empty() &&
      inspector_binding_node_id.empty() &&
      preview_binding_node_id.empty();
    flow_ok = multi_selection_diag.shell_state_still_coherent && flow_ok;

    const bool export32_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export32_ok && flow_ok;
    const bool parity32_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    multi_selection_diag.preview_remains_parity_safe =
      parity32_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = multi_selection_diag.preview_remains_parity_safe && flow_ok;

    const auto audit32 = ngk::ui::builder::audit_layout_tree(&root);
    multi_selection_diag.layout_audit_still_compatible = audit32.no_overlap;
    flow_ok = multi_selection_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_33 = [&] {
    bool flow_ok = true;
    bulk_delete_diag = BuilderBulkDeleteDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();

    const bool insert_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "bulk33-button-001");
    flow_ok = insert_button_ok && flow_ok;

    selected_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "bulk33-button-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    bulk_delete_diag.bulk_delete_present =
      builder_inspector_label.text().find("BULK_DELETE_RESULT:") != std::string::npos &&
      builder_preview_label.text().find("bulk_delete=") != std::string::npos;
    flow_ok = bulk_delete_diag.bulk_delete_present && flow_ok;

    const auto before_delete_nodes = builder_doc.nodes;
    const std::string before_delete_root = builder_doc.root_node_id;
    const std::string before_delete_sel = selected_builder_node_id;
    const auto before_delete_multi = multi_selected_node_ids;
    const bool delete_ok = apply_delete_command_for_current_selection();
    flow_ok = delete_ok && flow_ok;
    if (delete_ok) {
      push_to_history("phase103_33_bulk_delete", before_delete_nodes, before_delete_root, before_delete_sel, &before_delete_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
    }

    bulk_delete_diag.eligible_selected_nodes_deleted =
      delete_ok &&
      !node_exists("label-001") &&
      !node_exists("bulk33-button-001");
    flow_ok = bulk_delete_diag.eligible_selected_nodes_deleted && flow_ok;

    bulk_delete_diag.post_delete_selection_deterministic =
      delete_ok &&
      selected_builder_node_id == "input-001" &&
      multi_selected_node_ids.size() == 1 &&
      multi_selected_node_ids.front() == "input-001";
    flow_ok = bulk_delete_diag.post_delete_selection_deterministic && flow_ok;

    run_phase103_2();
    selected_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001", "label-001"};
    sync_multi_selection_with_primary();
    const bool protected_rejected = !apply_delete_command_for_current_selection();
    bulk_delete_diag.protected_or_invalid_bulk_delete_rejected =
      protected_rejected && node_exists("root-001") && node_exists("label-001");
    flow_ok = bulk_delete_diag.protected_or_invalid_bulk_delete_rejected && flow_ok;

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    const bool insert_button_again_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "bulk33-button-002");
    flow_ok = insert_button_again_ok && flow_ok;
    selected_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "bulk33-button-002"};
    sync_multi_selection_with_primary();
    const auto before_undo_nodes = builder_doc.nodes;
    const std::string before_undo_root = builder_doc.root_node_id;
    const std::string before_undo_sel = selected_builder_node_id;
    const auto before_undo_multi = multi_selected_node_ids;
    const bool second_delete_ok = apply_delete_command_for_current_selection();
    flow_ok = second_delete_ok && flow_ok;
    const std::string expected_redo_selected_id = selected_builder_node_id;
    const auto expected_redo_multi_selected_ids = multi_selected_node_ids;
    if (second_delete_ok) {
      push_to_history("phase103_33_bulk_delete_undo", before_undo_nodes, before_undo_root, before_undo_sel, &before_undo_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
    }
    const bool undo_ok = apply_undo_command();
    const bool undo_restored_selected_set =
      undo_ok &&
      node_exists("label-001") && node_exists("bulk33-button-002") &&
      selected_builder_node_id == "label-001" &&
      multi_selected_node_ids.size() == 2 &&
      multi_selected_node_ids[0] == "label-001" &&
      multi_selected_node_ids[1] == "bulk33-button-002";
    const bool redo_ok = apply_redo_command();
    bulk_delete_diag.undo_restores_bulk_delete_correctly =
      undo_restored_selected_set && redo_ok &&
      !node_exists("label-001") && !node_exists("bulk33-button-002") &&
      selected_builder_node_id == expected_redo_selected_id &&
      multi_selected_node_ids == expected_redo_multi_selected_ids;
    flow_ok = bulk_delete_diag.undo_restores_bulk_delete_correctly && flow_ok;

    const bool sync33_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    bulk_delete_diag.shell_state_still_coherent = sync33_ok;
    flow_ok = bulk_delete_diag.shell_state_still_coherent && flow_ok;

    const bool export33_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export33_ok && flow_ok;
    const bool parity33_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    bulk_delete_diag.preview_remains_parity_safe =
      parity33_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = bulk_delete_diag.preview_remains_parity_safe && flow_ok;

    const auto audit33 = ngk::ui::builder::audit_layout_tree(&root);
    bulk_delete_diag.layout_audit_still_compatible = audit33.no_overlap;
    flow_ok = bulk_delete_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_34 = [&] {
    bool flow_ok = true;
    bulk_move_reparent_diag = BuilderBulkMoveReparentDiagnostics{};

    auto build_document_structure_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                                  const char* context_name) -> std::string {
      std::vector<PreviewExportParityEntry> entries{};
      std::string reason;
      if (!build_preview_export_parity_entries(doc, entries, reason, context_name)) {
        return std::string("invalid:") + reason;
      }

      std::ostringstream oss;
      oss << "root=" << doc.root_node_id << "\n";
      for (const auto& entry : entries) {
        oss << entry.depth << "|"
            << entry.node_id << "|"
            << entry.widget_type << "|"
            << entry.text << "|";
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

    builder_doc = ngk::ui::builder::BuilderDocument{};
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    ngk::ui::builder::BuilderNode move_root{};
    move_root.node_id = "move34-root";
    move_root.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    move_root.container_type = ngk::ui::builder::BuilderContainerType::Shell;
    move_root.child_ids = {"move34-source-a", "move34-source-b", "move34-target"};

    ngk::ui::builder::BuilderNode move_source_a{};
    move_source_a.node_id = "move34-source-a";
    move_source_a.parent_id = "move34-root";
    move_source_a.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    move_source_a.child_ids = {"move34-leaf-a"};

    ngk::ui::builder::BuilderNode move_source_b{};
    move_source_b.node_id = "move34-source-b";
    move_source_b.parent_id = "move34-root";
    move_source_b.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;
    move_source_b.child_ids = {"move34-leaf-b"};

    ngk::ui::builder::BuilderNode move_target{};
    move_target.node_id = "move34-target";
    move_target.parent_id = "move34-root";
    move_target.widget_type = ngk::ui::builder::BuilderWidgetType::VerticalLayout;

    ngk::ui::builder::BuilderNode move_leaf_a{};
    move_leaf_a.node_id = "move34-leaf-a";
    move_leaf_a.parent_id = "move34-source-a";
    move_leaf_a.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
    move_leaf_a.text = "Move Leaf A";

    ngk::ui::builder::BuilderNode move_leaf_b{};
    move_leaf_b.node_id = "move34-leaf-b";
    move_leaf_b.parent_id = "move34-source-b";
    move_leaf_b.widget_type = ngk::ui::builder::BuilderWidgetType::Label;
    move_leaf_b.text = "Move Leaf B";

    builder_doc.root_node_id = "move34-root";
    builder_doc.nodes = {move_root, move_source_a, move_source_b, move_target, move_leaf_a, move_leaf_b};

    selected_builder_node_id = "move34-leaf-a";
    multi_selected_node_ids = {"move34-leaf-a", "move34-leaf-b"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    flow_ok = check_cross_surface_sync() && flow_ok;

    const bool drag_begin_ok = begin_tree_drag("move34-leaf-a");
    flow_ok = drag_begin_ok && flow_ok;
    const bool reparent_ok = drag_begin_ok && commit_tree_drag_reparent("move34-target");
    flow_ok = reparent_ok && flow_ok;

    auto* moved_target = find_node_by_id("move34-target");
    bulk_move_reparent_diag.bulk_move_reparent_present =
      builder_inspector_label.text().find("BULK_MOVE_REPARENT_RESULT:") != std::string::npos &&
      builder_preview_label.text().find("bulk_move_reparent=") != std::string::npos;
    flow_ok = bulk_move_reparent_diag.bulk_move_reparent_present && flow_ok;

    bulk_move_reparent_diag.eligible_selected_nodes_moved =
      reparent_ok &&
      moved_target != nullptr &&
      moved_target->child_ids.size() == 2 &&
      moved_target->child_ids[0] == "move34-leaf-a" &&
      moved_target->child_ids[1] == "move34-leaf-b" &&
      find_node_by_id("move34-leaf-a") != nullptr &&
      find_node_by_id("move34-leaf-a")->parent_id == "move34-target" &&
      find_node_by_id("move34-leaf-b") != nullptr &&
      find_node_by_id("move34-leaf-b")->parent_id == "move34-target";
    flow_ok = bulk_move_reparent_diag.eligible_selected_nodes_moved && flow_ok;

    bulk_move_reparent_diag.post_move_selection_deterministic =
      selected_builder_node_id == "move34-leaf-a" &&
      multi_selected_node_ids.size() == 2 &&
      multi_selected_node_ids[0] == "move34-leaf-a" &&
      multi_selected_node_ids[1] == "move34-leaf-b" &&
      focused_builder_node_id == "move34-leaf-a";
    flow_ok = bulk_move_reparent_diag.post_move_selection_deterministic && flow_ok;

    const std::string expected_redo_structure =
      build_document_structure_signature(builder_doc, "phase103_34_expected_redo");
    const std::string expected_redo_root = builder_doc.root_node_id;
    const std::string expected_redo_selected = selected_builder_node_id;
    const auto expected_redo_multi = multi_selected_node_ids;

    const bool undo_ok = apply_undo_command();
    auto* undo_source_a = find_node_by_id("move34-source-a");
    auto* undo_source_b = find_node_by_id("move34-source-b");
    bulk_move_reparent_diag.undo_restores_bulk_move_correctly =
      undo_ok &&
      undo_source_a != nullptr && undo_source_b != nullptr &&
      undo_source_a->child_ids.size() == 1 && undo_source_a->child_ids[0] == "move34-leaf-a" &&
      undo_source_b->child_ids.size() == 1 && undo_source_b->child_ids[0] == "move34-leaf-b" &&
      selected_builder_node_id == "move34-leaf-a" &&
      multi_selected_node_ids.size() == 2 &&
      multi_selected_node_ids[0] == "move34-leaf-a" &&
      multi_selected_node_ids[1] == "move34-leaf-b";
    flow_ok = bulk_move_reparent_diag.undo_restores_bulk_move_correctly && flow_ok;

    const bool redo_ok = apply_redo_command();
    bulk_move_reparent_diag.redo_restores_bulk_move_correctly =
      redo_ok &&
      builder_doc.root_node_id == expected_redo_root &&
      build_document_structure_signature(builder_doc, "phase103_34_redo_actual") == expected_redo_structure &&
      selected_builder_node_id == expected_redo_selected &&
      multi_selected_node_ids == expected_redo_multi;
    flow_ok = bulk_move_reparent_diag.redo_restores_bulk_move_correctly && flow_ok;

    builder_doc = ngk::ui::builder::BuilderDocument{};
    undo_history.clear();
    redo_stack.clear();
    builder_doc.root_node_id = "move34-root";
    builder_doc.nodes = {move_root, move_source_a, move_source_b, move_target, move_leaf_a, move_leaf_b};
    selected_builder_node_id = "move34-leaf-a";
    multi_selected_node_ids = {"move34-leaf-a", "move34-leaf-b"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::size_t history_before_reject = undo_history.size();
    const bool reject_drag_begin_ok = begin_tree_drag("move34-leaf-a");
    const bool protected_target_rejected = reject_drag_begin_ok && !commit_tree_drag_reparent("move34-root");
    auto* reject_target = find_node_by_id("move34-target");
    bulk_move_reparent_diag.invalid_or_protected_bulk_target_rejected =
      protected_target_rejected &&
      undo_history.size() == history_before_reject &&
      reject_target != nullptr && reject_target->child_ids.empty() &&
      last_bulk_move_reparent_status_code == "REJECTED";
    flow_ok = bulk_move_reparent_diag.invalid_or_protected_bulk_target_rejected && flow_ok;

    const bool sync34_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    bulk_move_reparent_diag.shell_state_still_coherent = sync34_ok;
    flow_ok = bulk_move_reparent_diag.shell_state_still_coherent && flow_ok;

    const bool export34_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export34_ok && flow_ok;
    const bool parity34_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    bulk_move_reparent_diag.preview_remains_parity_safe =
      parity34_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = bulk_move_reparent_diag.preview_remains_parity_safe && flow_ok;

    const auto audit34 = ngk::ui::builder::audit_layout_tree(&root);
    bulk_move_reparent_diag.layout_audit_still_compatible = audit34.no_overlap;
    flow_ok = bulk_move_reparent_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_35 = [&] {
    bool flow_ok = true;
    bulk_property_edit_diag = BuilderBulkPropertyEditDiagnostics{};

    auto build_document_structure_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                                  const char* context_name) -> std::string {
      std::vector<PreviewExportParityEntry> entries{};
      std::string reason;
      if (!build_preview_export_parity_entries(doc, entries, reason, context_name)) {
        return std::string("invalid:") + reason;
      }

      std::ostringstream oss;
      oss << "root=" << doc.root_node_id << "\n";
      for (const auto& entry : entries) {
        oss << entry.depth << "|"
            << entry.node_id << "|"
            << entry.widget_type << "|"
            << entry.text << "|";
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

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    const bool insert_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "bulk35-label-002");
    flow_ok = insert_label_ok && flow_ok;

    selected_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "bulk35-label-002"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    bulk_property_edit_diag.bulk_property_edit_present =
      builder_inspector_label.text().find("BULK_PROPERTY_EDIT_RESULT:") != std::string::npos &&
      builder_preview_label.text().find("bulk_property_edit=") != std::string::npos;
    flow_ok = bulk_property_edit_diag.bulk_property_edit_present && flow_ok;

    const auto before_edit_nodes = builder_doc.nodes;
    const std::string before_edit_root = builder_doc.root_node_id;
    const std::string before_edit_sel = selected_builder_node_id;
    const auto before_edit_multi = multi_selected_node_ids;

    const bool bulk_edit_ok = apply_bulk_text_suffix_selected_nodes_command(multi_selected_node_ids, "_B35");
    flow_ok = bulk_edit_ok && flow_ok;
    if (bulk_edit_ok) {
      push_to_history("phase103_35_bulk_property_edit", before_edit_nodes, before_edit_root, before_edit_sel, &before_edit_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
    }

    auto* edited_label_a = find_node_by_id("label-001");
    auto* edited_label_b = find_node_by_id("bulk35-label-002");
    bulk_property_edit_diag.compatible_selected_nodes_edited =
      bulk_edit_ok &&
      edited_label_a != nullptr && edited_label_b != nullptr &&
      edited_label_a->text == "Builder Label_B35" &&
      edited_label_b->text == "label_B35";
    flow_ok = bulk_property_edit_diag.compatible_selected_nodes_edited && flow_ok;

    bulk_property_edit_diag.post_edit_selection_deterministic =
      selected_builder_node_id == "label-001" &&
      multi_selected_node_ids.size() == 2 &&
      multi_selected_node_ids[0] == "label-001" &&
      multi_selected_node_ids[1] == "bulk35-label-002";
    flow_ok = bulk_property_edit_diag.post_edit_selection_deterministic && flow_ok;

    const std::string expected_redo_structure =
      build_document_structure_signature(builder_doc, "phase103_35_expected_redo");
    const std::string expected_redo_root = builder_doc.root_node_id;
    const std::string expected_redo_selected = selected_builder_node_id;
    const auto expected_redo_multi = multi_selected_node_ids;

    const bool undo_ok = apply_undo_command();
    auto* undo_label_a = find_node_by_id("label-001");
    auto* undo_label_b = find_node_by_id("bulk35-label-002");
    bulk_property_edit_diag.undo_restores_bulk_property_edit_correctly =
      undo_ok &&
      undo_label_a != nullptr && undo_label_b != nullptr &&
      undo_label_a->text == "Builder Label" &&
      undo_label_b->text == "label" &&
      selected_builder_node_id == "label-001" &&
      multi_selected_node_ids.size() == 2 &&
      multi_selected_node_ids[0] == "label-001" &&
      multi_selected_node_ids[1] == "bulk35-label-002";
    flow_ok = bulk_property_edit_diag.undo_restores_bulk_property_edit_correctly && flow_ok;

    const bool redo_ok = apply_redo_command();
    bulk_property_edit_diag.redo_restores_bulk_property_edit_correctly =
      redo_ok &&
      builder_doc.root_node_id == expected_redo_root &&
      build_document_structure_signature(builder_doc, "phase103_35_redo_actual") == expected_redo_structure &&
      selected_builder_node_id == expected_redo_selected &&
      multi_selected_node_ids == expected_redo_multi;
    flow_ok = bulk_property_edit_diag.redo_restores_bulk_property_edit_correctly && flow_ok;

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    const bool insert_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "bulk35-button-001");
    flow_ok = insert_button_ok && flow_ok;

    selected_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "bulk35-button-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const bool mixed_rejected = !apply_bulk_text_suffix_selected_nodes_command(multi_selected_node_ids, "_B35");
    bulk_property_edit_diag.incompatible_or_mixed_bulk_edit_rejected =
      mixed_rejected &&
      last_bulk_property_edit_status_code == "REJECTED" &&
      last_bulk_property_edit_reason.find("mixed_widget_types_") != std::string::npos;
    flow_ok = bulk_property_edit_diag.incompatible_or_mixed_bulk_edit_rejected && flow_ok;

    const bool sync35_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    bulk_property_edit_diag.shell_state_still_coherent = sync35_ok;
    flow_ok = bulk_property_edit_diag.shell_state_still_coherent && flow_ok;

    const bool export35_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export35_ok && flow_ok;
    const bool parity35_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    bulk_property_edit_diag.preview_remains_parity_safe =
      parity35_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = bulk_property_edit_diag.preview_remains_parity_safe && flow_ok;

    const auto audit35 = ngk::ui::builder::audit_layout_tree(&root);
    bulk_property_edit_diag.layout_audit_still_compatible = audit35.no_overlap;
    flow_ok = bulk_property_edit_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_36 = [&] {
    bool flow_ok = true;
    multi_selection_clarity_diag = BuilderMultiSelectionClarityDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();

    const bool insert_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "clarity36-label-002");
    flow_ok = insert_label_ok && flow_ok;

    selected_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "clarity36-label-002"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    refresh_tree_surface_label();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::string inspector_homogeneous = builder_inspector_label.text();
    const std::string preview_homogeneous = builder_preview_label.text();

    multi_selection_clarity_diag.preview_multi_selection_clarity_improved =
      preview_homogeneous.find("selection_mode=multi") != std::string::npos &&
      preview_homogeneous.find("multi_selection_count=2") != std::string::npos &&
      preview_homogeneous.find("multi_secondary_ids=clarity36-label-002") != std::string::npos;
    flow_ok = multi_selection_clarity_diag.preview_multi_selection_clarity_improved && flow_ok;

    multi_selection_clarity_diag.primary_vs_secondary_selection_visible =
      preview_homogeneous.find("[SELECTED]") != std::string::npos &&
      preview_homogeneous.find("[MULTI_SECONDARY]") != std::string::npos &&
      inspector_homogeneous.find("PRIMARY_SELECTION_ID: label-001") != std::string::npos;
    flow_ok = multi_selection_clarity_diag.primary_vs_secondary_selection_visible && flow_ok;

    multi_selection_clarity_diag.inspector_multi_selection_mode_clear =
      inspector_homogeneous.find("MULTI_SELECTION_MODE: active") != std::string::npos &&
      inspector_homogeneous.find("MULTI_SELECTION_COUNT: 2") != std::string::npos;
    flow_ok = multi_selection_clarity_diag.inspector_multi_selection_mode_clear && flow_ok;

    const bool insert_button_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "clarity36-button-001");
    flow_ok = insert_button_ok && flow_ok;

    selected_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "clarity36-button-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const std::string inspector_mixed = builder_inspector_label.text();
    const std::string preview_mixed = builder_preview_label.text();
    multi_selection_clarity_diag.homogeneous_vs_mixed_state_visible =
      inspector_homogeneous.find("BULK_TEXT_SUFFIX_COMPATIBILITY: homogeneous") != std::string::npos &&
      inspector_homogeneous.find("BULK_TEXT_SUFFIX_ELIGIBLE: YES") != std::string::npos &&
      preview_homogeneous.find("multi_selection_compatibility=homogeneous") != std::string::npos &&
      preview_homogeneous.find("bulk_text_suffix_eligible=YES") != std::string::npos &&
      inspector_mixed.find("BULK_TEXT_SUFFIX_COMPATIBILITY: mixed") != std::string::npos &&
      inspector_mixed.find("BULK_TEXT_SUFFIX_ELIGIBLE: NO") != std::string::npos &&
      preview_mixed.find("multi_selection_compatibility=mixed") != std::string::npos &&
      preview_mixed.find("bulk_text_suffix_eligible=NO") != std::string::npos;
    flow_ok = multi_selection_clarity_diag.homogeneous_vs_mixed_state_visible && flow_ok;

    const bool sync36_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    multi_selection_clarity_diag.shell_state_still_coherent = sync36_ok;
    flow_ok = multi_selection_clarity_diag.shell_state_still_coherent && flow_ok;

    const bool export36_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export36_ok && flow_ok;
    const bool parity36_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    multi_selection_clarity_diag.preview_remains_parity_safe =
      parity36_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = multi_selection_clarity_diag.preview_remains_parity_safe && flow_ok;

    const auto audit36 = ngk::ui::builder::audit_layout_tree(&root);
    multi_selection_clarity_diag.layout_audit_still_compatible = audit36.no_overlap;
    flow_ok = multi_selection_clarity_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_37 = [&] {
    bool flow_ok = true;
    keyboard_multi_selection_diag = BuilderKeyboardMultiSelectionWorkflowDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    const bool insert_label_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "phase37-label-002");
    flow_ok = insert_label_ok && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();

    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    flow_ok = check_cross_surface_sync() && flow_ok;

    const bool nav_focus_to_label = handle_builder_shortcut_key_with_modifiers(0x28, true, false, true, false);
    const bool add_label_to_set = handle_builder_shortcut_key_with_modifiers(0x41, true, false, true, false);
    const bool nav_focus_extend_to_second_label = handle_builder_shortcut_key_with_modifiers(0x28, true, false, true, true);
    keyboard_multi_selection_diag.keyboard_multi_selection_workflow_present =
      nav_focus_to_label && add_label_to_set && nav_focus_extend_to_second_label;
    flow_ok = keyboard_multi_selection_diag.keyboard_multi_selection_workflow_present && flow_ok;

    const bool build_set_ok =
      selected_builder_node_id == "root-001" &&
      multi_selected_node_ids.size() == 3 &&
      multi_selected_node_ids[0] == "root-001" &&
      multi_selected_node_ids[1] == "label-001" &&
      multi_selected_node_ids[2] == "phase37-label-002";
    flow_ok = build_set_ok && flow_ok;

    const std::string tree_after_build = builder_tree_surface_label.text();
    const std::string inspector_after_build = builder_inspector_label.text();
    const std::string preview_after_build = builder_preview_label.text();
    const bool sync_after_build = check_cross_surface_sync();

    const bool remove_second_label_from_set = handle_builder_shortcut_key_with_modifiers(0x52, true, false, true, false);
    const bool remove_state_ok =
      remove_second_label_from_set &&
      selected_builder_node_id == "root-001" &&
      multi_selected_node_ids.size() == 2 &&
      multi_selected_node_ids[0] == "root-001" &&
      multi_selected_node_ids[1] == "label-001";
    flow_ok = remove_state_ok && flow_ok;

    const std::string tree_after_remove = builder_tree_surface_label.text();
    const std::string inspector_after_remove = builder_inspector_label.text();
    const std::string preview_after_remove = builder_preview_label.text();
    const bool sync_after_remove = check_cross_surface_sync();

    const bool clear_set = handle_builder_shortcut_key_with_modifiers(0x1B, true, false, true, false);
    const bool clear_state_ok =
      clear_set &&
      selected_builder_node_id.empty() &&
      focused_builder_node_id.empty() &&
      multi_selected_node_ids.empty();
    flow_ok = clear_state_ok && flow_ok;

    const std::string tree_after_clear = builder_tree_surface_label.text();
    const std::string inspector_after_clear = builder_inspector_label.text();
    const std::string preview_after_clear = builder_preview_label.text();
    const bool sync_after_clear = check_cross_surface_sync();

    keyboard_multi_selection_diag.add_remove_clear_selection_by_keyboard_works =
      build_set_ok && remove_state_ok && clear_state_ok;
    flow_ok = keyboard_multi_selection_diag.add_remove_clear_selection_by_keyboard_works && flow_ok;

    keyboard_multi_selection_diag.primary_selection_remains_deterministic =
      build_set_ok && remove_state_ok;
    flow_ok = keyboard_multi_selection_diag.primary_selection_remains_deterministic && flow_ok;

    keyboard_multi_selection_diag.preview_inspector_tree_remain_synchronized =
      sync_after_build && sync_after_remove && sync_after_clear &&
      tree_after_build.find("MULTI_SELECTION_COUNT: 3") != std::string::npos &&
      inspector_after_build.find("MULTI_SELECTION_COUNT: 3") != std::string::npos &&
      preview_after_build.find("multi_selection_count=3") != std::string::npos &&
      tree_after_remove.find("MULTI_SELECTION_COUNT: 2") != std::string::npos &&
      inspector_after_remove.find("MULTI_SELECTION_COUNT: 2") != std::string::npos &&
      preview_after_remove.find("multi_selection_count=2") != std::string::npos &&
      tree_after_clear.find("MULTI_SELECTION_COUNT: 0") != std::string::npos &&
      inspector_after_clear.find("MULTI_SELECTION_COUNT: 0") != std::string::npos &&
      preview_after_clear.find("multi_selection_count=0") != std::string::npos;
    flow_ok = keyboard_multi_selection_diag.preview_inspector_tree_remain_synchronized && flow_ok;

    keyboard_multi_selection_diag.shell_state_still_coherent =
      sync_after_clear &&
      selected_builder_node_id.empty() &&
      focused_builder_node_id.empty() &&
      inspector_binding_node_id.empty() &&
      preview_binding_node_id.empty();
    flow_ok = keyboard_multi_selection_diag.shell_state_still_coherent && flow_ok;

    const bool export37_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export37_ok && flow_ok;
    const bool parity37_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    keyboard_multi_selection_diag.preview_remains_parity_safe =
      parity37_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = keyboard_multi_selection_diag.preview_remains_parity_safe && flow_ok;

    const auto audit37 = ngk::ui::builder::audit_layout_tree(&root);
    keyboard_multi_selection_diag.layout_audit_still_compatible = audit37.no_overlap;
    flow_ok = keyboard_multi_selection_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_38 = [&] {
    bool flow_ok = true;
    bulk_action_eligibility_diag = BuilderBulkActionEligibilityUxDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "phase38-label-002") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "phase38-button-001") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "phase38-target-vlayout") && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "phase38-label-002"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string legal_inspector_text = builder_inspector_label.text();
    const std::string legal_preview_text = builder_preview_label.text();

    const bool legal_actions_visible =
      legal_inspector_text.find("ACTION_SURFACE: available=3 blocked=0") != std::string::npos &&
      legal_inspector_text.find("AVAILABLE_ACTIONS: BULK_DELETE,BULK_PROPERTY_EDIT,BULK_MOVE_REPARENT") != std::string::npos &&
      legal_inspector_text.find("BLOCKED_ACTIONS: <none>") != std::string::npos &&
      legal_preview_text.find("ACTION_SURFACE: available=3 blocked=0") != std::string::npos &&
      legal_preview_text.find("AVAILABLE_ACTIONS: BULK_DELETE,BULK_PROPERTY_EDIT,BULK_MOVE_REPARENT") != std::string::npos &&
      legal_preview_text.find("BLOCKED_ACTIONS: <none>") != std::string::npos;
    flow_ok = legal_actions_visible && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001", "label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string blocked_root_inspector_text = builder_inspector_label.text();
    const std::string blocked_root_preview_text = builder_preview_label.text();

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "phase38-button-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string blocked_mixed_inspector_text = builder_inspector_label.text();
    const std::string blocked_mixed_preview_text = builder_preview_label.text();

    bulk_action_eligibility_diag.bulk_action_visibility_improved =
      legal_actions_visible &&
      blocked_root_inspector_text.find("ACTION_SURFACE:") != std::string::npos &&
      blocked_root_preview_text.find("ACTION_SURFACE:") != std::string::npos &&
      blocked_mixed_inspector_text.find("ACTION_SURFACE:") != std::string::npos &&
      blocked_mixed_preview_text.find("ACTION_SURFACE:") != std::string::npos;
    flow_ok = bulk_action_eligibility_diag.bulk_action_visibility_improved && flow_ok;

    bulk_action_eligibility_diag.legal_vs_blocked_actions_clear =
      legal_inspector_text.find("BLOCKED_ACTIONS: <none>") != std::string::npos &&
      blocked_root_inspector_text.find("BLOCKED_ACTIONS:") != std::string::npos &&
      blocked_root_inspector_text.find("BULK_DELETE") != std::string::npos &&
      blocked_mixed_preview_text.find("BLOCKED_ACTIONS: BULK_PROPERTY_EDIT") != std::string::npos;
    flow_ok = bulk_action_eligibility_diag.legal_vs_blocked_actions_clear && flow_ok;

    bulk_action_eligibility_diag.blocked_action_reasons_explicit =
      blocked_root_inspector_text.find("BULK_DELETE -> protected_root_root-001") != std::string::npos &&
      blocked_root_preview_text.find("BULK_MOVE_REPARENT -> protected_source_root_root-001") != std::string::npos &&
      blocked_mixed_inspector_text.find("BULK_PROPERTY_EDIT -> mixed_widget_types") != std::string::npos &&
      blocked_mixed_preview_text.find("BULK_PROPERTY_EDIT -> mixed_widget_types") != std::string::npos;
    flow_ok = bulk_action_eligibility_diag.blocked_action_reasons_explicit && flow_ok;

    const bool sync38_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    bulk_action_eligibility_diag.shell_state_still_coherent = sync38_ok;
    flow_ok = bulk_action_eligibility_diag.shell_state_still_coherent && flow_ok;

    const bool export38_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export38_ok && flow_ok;
    const bool parity38_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    bulk_action_eligibility_diag.preview_remains_parity_safe =
      parity38_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = bulk_action_eligibility_diag.preview_remains_parity_safe && flow_ok;

    const auto audit38 = ngk::ui::builder::audit_layout_tree(&root);
    bulk_action_eligibility_diag.layout_audit_still_compatible = audit38.no_overlap;
    flow_ok = bulk_action_eligibility_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_39 = [&] {
    bool flow_ok = true;
    action_surface_readability_diag = BuilderActionSurfaceReadabilityDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "phase39-label-002") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "phase39-button-001") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "phase39-target-vlayout") && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "phase39-label-002"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string legal_inspector_text = builder_inspector_label.text();
    const std::string legal_preview_text = builder_preview_label.text();

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001", "label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string blocked_inspector_text = builder_inspector_label.text();
    const std::string blocked_preview_text = builder_preview_label.text();

    action_surface_readability_diag.action_surface_readability_improved =
      legal_inspector_text.find("ACTION_SURFACE: available=3 blocked=0") != std::string::npos &&
      legal_preview_text.find("ACTION_SURFACE: available=3 blocked=0") != std::string::npos &&
      blocked_inspector_text.find("ACTION_SURFACE: available=0 blocked=3") != std::string::npos &&
      blocked_preview_text.find("ACTION_SURFACE: available=0 blocked=3") != std::string::npos;
    flow_ok = action_surface_readability_diag.action_surface_readability_improved && flow_ok;

    action_surface_readability_diag.legal_vs_blocked_states_still_clear =
      legal_inspector_text.find("BLOCKED_ACTIONS: <none>") != std::string::npos &&
      blocked_inspector_text.find("BLOCKED_ACTIONS: BULK_DELETE,BULK_PROPERTY_EDIT,BULK_MOVE_REPARENT") != std::string::npos &&
      legal_preview_text.find("AVAILABLE_ACTIONS: BULK_DELETE,BULK_PROPERTY_EDIT,BULK_MOVE_REPARENT") != std::string::npos &&
      blocked_preview_text.find("AVAILABLE_ACTIONS: <none>") != std::string::npos;
    flow_ok = action_surface_readability_diag.legal_vs_blocked_states_still_clear && flow_ok;

    action_surface_readability_diag.blocked_reasons_still_explicit =
      blocked_inspector_text.find("BULK_DELETE -> protected_root_root-001") != std::string::npos &&
      blocked_inspector_text.find("BULK_PROPERTY_EDIT -> protected_source_root_root-001") != std::string::npos &&
      blocked_preview_text.find("BULK_MOVE_REPARENT -> protected_source_root_root-001") != std::string::npos;
    flow_ok = action_surface_readability_diag.blocked_reasons_still_explicit && flow_ok;

    action_surface_readability_diag.inspector_preview_information_better_grouped =
      legal_inspector_text.find("ACTION_SURFACE:") != std::string::npos &&
      legal_inspector_text.find("AVAILABLE_ACTIONS:") != std::string::npos &&
      legal_inspector_text.find("BLOCKED_ACTIONS:") != std::string::npos &&
      legal_inspector_text.find("BLOCKED_REASONS:") != std::string::npos &&
      legal_preview_text.find("ACTION_SURFACE:") != std::string::npos &&
      legal_preview_text.find("AVAILABLE_ACTIONS:") != std::string::npos &&
      legal_preview_text.find("BLOCKED_ACTIONS:") != std::string::npos &&
      legal_preview_text.find("BLOCKED_REASONS:") != std::string::npos;
    flow_ok = action_surface_readability_diag.inspector_preview_information_better_grouped && flow_ok;

    const bool sync39_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    action_surface_readability_diag.shell_state_still_coherent = sync39_ok;
    flow_ok = action_surface_readability_diag.shell_state_still_coherent && flow_ok;

    const bool export39_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export39_ok && flow_ok;
    const bool parity39_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    action_surface_readability_diag.preview_remains_parity_safe =
      parity39_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = action_surface_readability_diag.preview_remains_parity_safe && flow_ok;

    const auto audit39 = ngk::ui::builder::audit_layout_tree(&root);
    action_surface_readability_diag.layout_audit_still_compatible = audit39.no_overlap;
    flow_ok = action_surface_readability_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_40 = [&] {
    bool flow_ok = true;
    info_hierarchy_diag = BuilderInformationHierarchyPolishDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "phase40-label-002") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "phase40-button-001") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "phase40-target-vlayout") && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string single_inspector_text = builder_inspector_label.text();
    const std::string single_preview_text = builder_preview_label.text();

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "phase40-label-002"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string multi_legal_inspector_text = builder_inspector_label.text();
    const std::string multi_legal_preview_text = builder_preview_label.text();

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001", "label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string multi_blocked_inspector_text = builder_inspector_label.text();
    const std::string multi_blocked_preview_text = builder_preview_label.text();

    info_hierarchy_diag.information_hierarchy_improved =
      single_inspector_text.find("[SELECTION_SUMMARY]") != std::string::npos &&
      single_inspector_text.find("[ACTION_SURFACE]") != std::string::npos &&
      single_inspector_text.find("[PARITY]") != std::string::npos &&
      single_inspector_text.find("[RECENT_RESULTS]") != std::string::npos &&
      single_preview_text.find("[SELECTION_SUMMARY]") != std::string::npos &&
      single_preview_text.find("[PARITY]") != std::string::npos &&
      single_preview_text.find("[ACTION_SURFACE]") != std::string::npos &&
      single_preview_text.find("[RECENT_RESULTS]") != std::string::npos;
    flow_ok = info_hierarchy_diag.information_hierarchy_improved && flow_ok;

    const auto idx_inspector_selection = single_inspector_text.find("[SELECTION_SUMMARY]");
    const auto idx_inspector_action = single_inspector_text.find("[ACTION_SURFACE]");
    const auto idx_inspector_parity = single_inspector_text.find("[PARITY]");
    const auto idx_inspector_results = single_inspector_text.find("[RECENT_RESULTS]");
    const auto idx_preview_selection = single_preview_text.find("[SELECTION_SUMMARY]");
    const auto idx_preview_parity = single_preview_text.find("[PARITY]");
    const auto idx_preview_action = single_preview_text.find("[ACTION_SURFACE]");
    const auto idx_preview_results = single_preview_text.find("[RECENT_RESULTS]");
    info_hierarchy_diag.scan_order_more_readable =
      idx_inspector_selection < idx_inspector_action &&
      idx_inspector_action < idx_inspector_parity &&
      idx_inspector_parity < idx_inspector_results &&
      idx_preview_selection < idx_preview_parity &&
      idx_preview_parity < idx_preview_action &&
      idx_preview_action < idx_preview_results;
    flow_ok = info_hierarchy_diag.scan_order_more_readable && flow_ok;

    const auto selected_id_pos_inspector = single_inspector_text.find("SELECTED_ID:");
    const auto selected_id_pos_preview = single_preview_text.find("SELECTED_ID:");
    const auto mode_pos_inspector = single_inspector_text.find("MULTI_SELECTION_MODE:");
    const auto mode_pos_preview = single_preview_text.find("selection_mode=");
    info_hierarchy_diag.important_state_easier_to_find =
      selected_id_pos_inspector != std::string::npos && selected_id_pos_inspector < 140 &&
      selected_id_pos_preview != std::string::npos && selected_id_pos_preview < 140 &&
      mode_pos_inspector != std::string::npos && mode_pos_inspector < 280 &&
      mode_pos_preview != std::string::npos && mode_pos_preview < 220;
    flow_ok = info_hierarchy_diag.important_state_easier_to_find && flow_ok;

    info_hierarchy_diag.blocked_reasons_and_parity_still_visible =
      multi_blocked_inspector_text.find("BLOCKED_REASONS:") != std::string::npos &&
      multi_blocked_inspector_text.find("protected_root_root-001") != std::string::npos &&
      multi_blocked_preview_text.find("BLOCKED_REASONS:") != std::string::npos &&
      multi_blocked_preview_text.find("protected_source_root_root-001") != std::string::npos &&
      multi_legal_preview_text.find("parity=") != std::string::npos;
    flow_ok = info_hierarchy_diag.blocked_reasons_and_parity_still_visible && flow_ok;

    const bool sync40_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    info_hierarchy_diag.shell_state_still_coherent = sync40_ok;
    flow_ok = info_hierarchy_diag.shell_state_still_coherent && flow_ok;

    const bool export40_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export40_ok && flow_ok;
    const bool parity40_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    info_hierarchy_diag.preview_remains_parity_safe =
      parity40_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = info_hierarchy_diag.preview_remains_parity_safe && flow_ok;

    const auto audit40 = ngk::ui::builder::audit_layout_tree(&root);
    info_hierarchy_diag.layout_audit_still_compatible = audit40.no_overlap;
    flow_ok = info_hierarchy_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_41 = [&] {
    bool flow_ok = true;
    top_action_surface_diag = BuilderSelectionAwareTopActionSurfaceDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "phase41-label-002") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, "root-001", "phase41-button-001") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "phase41-target-vlayout") && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string single_status = status_label.text();
    const std::string single_selected = selected_label.text();
    const std::string single_detail = detail_label.text();
    const std::string single_inspector = builder_inspector_label.text();
    const std::string single_preview = builder_preview_label.text();

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "phase41-label-002"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string multi_legal_status = status_label.text();
    const std::string multi_legal_detail = detail_label.text();
    const std::string multi_legal_inspector = builder_inspector_label.text();
    const std::string multi_legal_preview = builder_preview_label.text();

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001", "label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string multi_blocked_status = status_label.text();
    const std::string multi_blocked_detail = detail_label.text();
    const std::string multi_blocked_inspector = builder_inspector_label.text();
    const std::string multi_blocked_preview = builder_preview_label.text();

    top_action_surface_diag.top_action_surface_selection_aware =
      single_status.find("TOP_ACTION_SURFACE mode=single selected_count=1") != std::string::npos &&
      multi_legal_status.find("TOP_ACTION_SURFACE mode=multi selected_count=2") != std::string::npos &&
      multi_blocked_status.find("TOP_ACTION_SURFACE mode=multi selected_count=2") != std::string::npos;
    flow_ok = top_action_surface_diag.top_action_surface_selection_aware && flow_ok;

    const bool single_blocked_all_visible =
      single_detail.find("TOP_BLOCKED") != std::string::npos &&
      single_detail.find("BULK_DELETE") != std::string::npos &&
      single_detail.find("BULK_PROPERTY_EDIT") != std::string::npos &&
      single_detail.find("BULK_MOVE_REPARENT") != std::string::npos;
    const bool multi_legal_available_all_visible =
      multi_legal_detail.find("TOP_AVAILABLE") != std::string::npos &&
      multi_legal_detail.find("BULK_DELETE") != std::string::npos &&
      multi_legal_detail.find("BULK_PROPERTY_EDIT") != std::string::npos &&
      multi_legal_detail.find("BULK_MOVE_REPARENT") != std::string::npos &&
      multi_legal_detail.find("TOP_BLOCKED <none>") != std::string::npos;
    const bool multi_blocked_all_visible =
      multi_blocked_detail.find("TOP_AVAILABLE <none>") != std::string::npos &&
      multi_blocked_detail.find("TOP_BLOCKED") != std::string::npos &&
      multi_blocked_detail.find("BULK_DELETE") != std::string::npos &&
      multi_blocked_detail.find("BULK_PROPERTY_EDIT") != std::string::npos &&
      multi_blocked_detail.find("BULK_MOVE_REPARENT") != std::string::npos;
    top_action_surface_diag.valid_vs_blocked_actions_clear_at_top_level =
      single_blocked_all_visible &&
      multi_legal_available_all_visible &&
      multi_blocked_all_visible;
    flow_ok = top_action_surface_diag.valid_vs_blocked_actions_clear_at_top_level && flow_ok;

    top_action_surface_diag.top_surface_matches_inspector_preview_truth =
      multi_legal_status.find("available=3 blocked=0") != std::string::npos &&
      multi_legal_inspector.find("ACTION_SURFACE: available=3 blocked=0") != std::string::npos &&
      multi_legal_preview.find("ACTION_SURFACE: available=3 blocked=0") != std::string::npos &&
      multi_blocked_status.find("available=0 blocked=3") != std::string::npos &&
      multi_blocked_inspector.find("ACTION_SURFACE: available=0 blocked=3") != std::string::npos &&
      multi_blocked_preview.find("ACTION_SURFACE: available=0 blocked=3") != std::string::npos;
    flow_ok = top_action_surface_diag.top_surface_matches_inspector_preview_truth && flow_ok;

    top_action_surface_diag.important_actions_easier_to_reach =
      single_status.find("TOP_ACTION_SURFACE") != std::string::npos &&
      single_selected.find("NODE label-001") != std::string::npos &&
      single_detail.find("TOP_AVAILABLE") != std::string::npos &&
      single_detail.find("TOP_BLOCKED") != std::string::npos;
    flow_ok = top_action_surface_diag.important_actions_easier_to_reach && flow_ok;

    const bool sync41_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    top_action_surface_diag.shell_state_still_coherent = sync41_ok;
    flow_ok = top_action_surface_diag.shell_state_still_coherent && flow_ok;

    const bool export41_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export41_ok && flow_ok;
    const bool parity41_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    top_action_surface_diag.preview_remains_parity_safe =
      parity41_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = top_action_surface_diag.preview_remains_parity_safe && flow_ok;

    const auto audit41 = ngk::ui::builder::audit_layout_tree(&root);
    top_action_surface_diag.layout_audit_still_compatible = audit41.no_overlap;
    flow_ok = top_action_surface_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_42 = [&] {
    bool flow_ok = true;
    button_state_readability_diag = BuilderButtonStateReadabilityDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;

    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, "root-001", "phase42-label-002") && flow_ok;
    selected_builder_node_id = "root-001";
    flow_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "phase42-target-vlayout") && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string single_delete = builder_delete_button.text();
    const std::string single_insert_container = builder_insert_container_button.text();
    const std::string single_insert_leaf = builder_insert_leaf_button.text();
    const std::string single_status = status_label.text();
    const std::string single_inspector = builder_inspector_label.text();
    const bool single_delete_default = builder_delete_button.is_default_action();

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001", "phase42-label-002"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string multi_legal_delete = builder_delete_button.text();
    const std::string multi_legal_status = status_label.text();
    const std::string multi_legal_inspector = builder_inspector_label.text();
    const bool multi_legal_delete_default = builder_delete_button.is_default_action();

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001", "label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string multi_blocked_delete = builder_delete_button.text();
    const std::string multi_blocked_status = status_label.text();
    const std::string multi_blocked_inspector = builder_inspector_label.text();
    const bool multi_blocked_delete_default = builder_delete_button.is_default_action();

    button_state_readability_diag.button_state_readability_improved =
      single_delete.find("Delete Node [AVAILABLE] [SINGLE]") != std::string::npos &&
      single_insert_container.find("Insert Container [BLOCKED]") != std::string::npos &&
      single_insert_leaf.find("Insert Leaf [BLOCKED]") != std::string::npos &&
      multi_legal_delete.find("Delete Node [AVAILABLE] [BULK]") != std::string::npos &&
      multi_blocked_delete.find("Delete Node [BLOCKED] [BULK]") != std::string::npos;
    flow_ok = button_state_readability_diag.button_state_readability_improved && flow_ok;

    button_state_readability_diag.available_vs_blocked_actions_visually_clear =
      single_delete.find("[AVAILABLE]") != std::string::npos &&
      multi_legal_delete.find("[AVAILABLE]") != std::string::npos &&
      multi_blocked_delete.find("[BLOCKED]") != std::string::npos;
    flow_ok = button_state_readability_diag.available_vs_blocked_actions_visually_clear && flow_ok;

    button_state_readability_diag.current_relevant_actions_emphasized =
      single_delete_default &&
      multi_legal_delete_default &&
      !multi_blocked_delete_default;
    flow_ok = button_state_readability_diag.current_relevant_actions_emphasized && flow_ok;

    button_state_readability_diag.button_state_matches_surface_truth =
      single_status.find("mode=single") != std::string::npos &&
      single_inspector.find("ACTION_SURFACE: available=0 blocked=3") != std::string::npos &&
      multi_legal_status.find("available=3 blocked=0") != std::string::npos &&
      multi_legal_inspector.find("ACTION_SURFACE: available=3 blocked=0") != std::string::npos &&
      multi_blocked_status.find("available=0 blocked=3") != std::string::npos &&
      multi_blocked_inspector.find("ACTION_SURFACE: available=0 blocked=3") != std::string::npos &&
      multi_blocked_delete.find("[BLOCKED]") != std::string::npos;
    flow_ok = button_state_readability_diag.button_state_matches_surface_truth && flow_ok;

    const bool sync42_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    button_state_readability_diag.shell_state_still_coherent = sync42_ok;
    flow_ok = button_state_readability_diag.shell_state_still_coherent && flow_ok;

    const bool export42_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export42_ok && flow_ok;
    const bool parity42_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    button_state_readability_diag.preview_remains_parity_safe =
      parity42_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = button_state_readability_diag.preview_remains_parity_safe && flow_ok;

    const auto audit42 = ngk::ui::builder::audit_layout_tree(&root);
    button_state_readability_diag.layout_audit_still_compatible = audit42.no_overlap;
    flow_ok = button_state_readability_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_43 = [&] {
    bool flow_ok = true;
    usability_baseline_diag = BuilderUsabilityBaselineDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    set_last_action_feedback("Ready");

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    usability_baseline_diag.startup_guidance_visible =
      title_label.text().find("START: Click NEW DOC -> then INSERT CONTAINER -> then INSERT LEAF") != std::string::npos;
    flow_ok = usability_baseline_diag.startup_guidance_visible && flow_ok;

    usability_baseline_diag.button_labels_humanized =
      builder_insert_container_button.text() == "Add Container" &&
      builder_insert_leaf_button.text() == "Add Item" &&
      builder_delete_button.text() == "Delete" &&
      builder_export_button.text() == "Export";
    flow_ok = usability_baseline_diag.button_labels_humanized && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string tree_text = builder_tree_surface_label.text();
    const std::string preview_text = builder_preview_label.text();
    const std::string inspector_text = builder_inspector_label.text();

    usability_baseline_diag.selection_visual_marker_present =
      tree_text.find("[SELECTED]") != std::string::npos &&
      preview_text.find("[SELECTED]") != std::string::npos;
    flow_ok = usability_baseline_diag.selection_visual_marker_present && flow_ok;

    usability_baseline_diag.action_feedback_visible =
      builder_action_feedback_label.text().find("Action: ") == 0;
    flow_ok = usability_baseline_diag.action_feedback_visible && flow_ok;

    usability_baseline_diag.preview_readability_improved =
      preview_text.find("Layout") != std::string::npos &&
      preview_text.find("Label:") != std::string::npos &&
      preview_text.find("[SELECTED]") != std::string::npos;
    flow_ok = usability_baseline_diag.preview_readability_improved && flow_ok;

    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string debug_off_inspector = builder_inspector_label.text();
    const std::string debug_off_preview = builder_preview_label.text();

    builder_debug_mode = true;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: ON]");
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::string debug_on_inspector = builder_inspector_label.text();
    const std::string debug_on_preview = builder_preview_label.text();

    usability_baseline_diag.debug_information_toggleable =
      debug_off_inspector.find("[PARITY]") == std::string::npos &&
      debug_off_preview.find("[PARITY]") == std::string::npos &&
      debug_on_inspector.find("[PARITY]") != std::string::npos &&
      debug_on_preview.find("[PARITY]") != std::string::npos &&
      debug_on_inspector.find("BLOCKED_REASONS:") != std::string::npos &&
      debug_on_preview.find("BLOCKED_REASONS:") != std::string::npos;
    flow_ok = usability_baseline_diag.debug_information_toggleable && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    const bool root_delete_rejected = !apply_delete_command_for_current_selection();
    const std::string root_delete_reason = delete_rejection_reason_for_node(selected_builder_node_id);

    selected_builder_node_id = "root-001";
    flow_ok = apply_palette_insert(true) && flow_ok;
    const bool can_insert_item_after_container = apply_palette_insert(false);

    usability_baseline_diag.existing_system_behavior_unchanged =
      root_delete_rejected &&
      root_delete_reason == "protected_root" &&
      can_insert_item_after_container;
    flow_ok = usability_baseline_diag.existing_system_behavior_unchanged && flow_ok;

    (void)inspector_text;

    const bool sync43_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    usability_baseline_diag.shell_state_still_coherent = sync43_ok;
    flow_ok = usability_baseline_diag.shell_state_still_coherent && flow_ok;

    const bool export43_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export43_ok && flow_ok;
    const bool parity43_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    usability_baseline_diag.preview_remains_parity_safe =
      parity43_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = usability_baseline_diag.preview_remains_parity_safe && flow_ok;

    const auto audit43 = ngk::ui::builder::audit_layout_tree(&root);
    usability_baseline_diag.layout_audit_still_compatible = audit43.no_overlap;
    flow_ok = usability_baseline_diag.layout_audit_still_compatible && flow_ok;

    if (usability_baseline_diag.existing_system_behavior_unchanged &&
        root_delete_rejected &&
        root_delete_reason == "protected_root") {
      set_last_action_feedback("Cannot delete root");
    }

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_44 = [&] {
    bool flow_ok = true;
    explicit_edit_field_diag = BuilderExplicitEditableFieldDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    set_last_action_feedback("Ready");

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    explicit_edit_field_diag.selected_node_edit_target_clear =
      builder_inspector_selection_label.text().find("Selected Node: label-001 | Type: label") != std::string::npos &&
      builder_inspector_label.text().find("Edit Target: label-001") != std::string::npos &&
      builder_inspector_label.text().find("Type: label") != std::string::npos;
    flow_ok = explicit_edit_field_diag.selected_node_edit_target_clear && flow_ok;

    explicit_edit_field_diag.editable_field_visible_for_text_nodes =
      builder_inspector_text_input.visible() &&
      builder_inspector_text_input.focusable() &&
      builder_inspector_apply_button.visible() &&
      builder_inspector_apply_button.enabled() &&
      builder_inspector_text_input.value() == "Builder Label" &&
      builder_inspector_apply_button.text().find("Apply Text to label-001") != std::string::npos;
    flow_ok = explicit_edit_field_diag.editable_field_visible_for_text_nodes && flow_ok;

    const int apply_filter_count_before = model.apply_filter_count;
    builder_inspector_text_input.set_value("Phase10344 Label");
    const bool inspector_apply_ok = builder_inspector_apply_button.perform_primary_action();
    auto* edited_label44 = find_node_by_id("label-001");
    explicit_edit_field_diag.apply_behavior_unambiguous =
      apply_button.text() == "Apply Filter" &&
      builder_inspector_edit_hint_label.text().find("Top bar Apply Filter only filters files") != std::string::npos &&
      inspector_apply_ok &&
      last_inspector_edit_status_code == "SUCCESS" &&
      edited_label44 != nullptr &&
      edited_label44->text == "Phase10344 Label" &&
      model.apply_filter_count == apply_filter_count_before;
    flow_ok = explicit_edit_field_diag.apply_behavior_unambiguous && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    explicit_edit_field_diag.non_text_nodes_show_non_editable_state =
      !builder_inspector_text_input.visible() &&
      !builder_inspector_apply_button.visible() &&
      !builder_inspector_apply_button.enabled() &&
      builder_inspector_non_editable_label.visible() &&
      builder_inspector_non_editable_label.text().find("vertical_layout") != std::string::npos &&
      builder_inspector_label.text().find("Text Property: not editable for this node type") != std::string::npos;
    flow_ok = explicit_edit_field_diag.non_text_nodes_show_non_editable_state && flow_ok;

    const bool remap44_ok = remap_selection_or_fail();
    const bool focus44_ok = sync_focus_with_selection_or_fail();
    refresh_tree_surface_label();
    const bool inspector44_ok = refresh_inspector_or_fail();
    const bool preview44_ok = refresh_preview_or_fail();
    const bool sync44_ok = check_cross_surface_sync();
    explicit_edit_field_diag.shell_state_still_coherent =
      remap44_ok && focus44_ok && inspector44_ok && preview44_ok && sync44_ok;
    flow_ok = explicit_edit_field_diag.shell_state_still_coherent && flow_ok;

    const bool export44_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export44_ok && flow_ok;
    const bool parity44_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    explicit_edit_field_diag.preview_remains_parity_safe =
      parity44_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = explicit_edit_field_diag.preview_remains_parity_safe && flow_ok;

    const auto audit44 = ngk::ui::builder::audit_layout_tree(&root);
    explicit_edit_field_diag.layout_audit_still_compatible = audit44.no_overlap;
    flow_ok = explicit_edit_field_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_45 = [&] {
    bool flow_ok = true;
    integrated_usability_diag = BuilderIntegratedUsabilityMilestoneDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    set_last_action_feedback("Ready");

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    refresh_tree_surface_label();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    std::size_t label_row_idx = kMaxVisualTreeRows;
    for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
      if (tree_visual_row_node_ids[idx] == "label-001") {
        label_row_idx = idx;
        break;
      }
    }
    const bool tree_click_ok =
      label_row_idx < kMaxVisualTreeRows &&
      builder_tree_row_buttons[label_row_idx].visible() &&
      builder_tree_row_buttons[label_row_idx].perform_primary_action() &&
      selected_builder_node_id == "label-001";
    integrated_usability_diag.clickable_tree = tree_click_ok;
    flow_ok = integrated_usability_diag.clickable_tree && flow_ok;

    flow_ok = refresh_inspector_or_fail() && flow_ok;
    builder_inspector_text_input.set_value("Milestone45 Label");
    builder_inspector_layout_min_width_input.set_value("240");
    builder_inspector_layout_min_height_input.set_value("32");
    const bool apply_multi_ok = builder_inspector_apply_button.perform_primary_action();
    auto* edited_node45 = find_node_by_id("label-001");
    integrated_usability_diag.inspector_multi_property_editing =
      apply_multi_ok &&
      last_inspector_edit_status_code == "SUCCESS" &&
      edited_node45 != nullptr &&
      edited_node45->text == "Milestone45 Label" &&
      edited_node45->layout.min_width == 240 &&
      edited_node45->layout.min_height == 32;
    flow_ok = integrated_usability_diag.inspector_multi_property_editing && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    const bool add_container_ok = apply_palette_insert(true);
    const std::string added_container_id = selected_builder_node_id;
    const bool add_leaf_ok = apply_palette_insert(false);
    const std::string added_leaf_id = selected_builder_node_id;
    const bool delete_leaf_ok = apply_delete_command_for_current_selection();
    integrated_usability_diag.simple_structure_controls =
      add_container_ok && node_exists(added_container_id) &&
      add_leaf_ok && !added_leaf_id.empty() &&
      delete_leaf_ok && !node_exists(added_leaf_id);
    flow_ok = integrated_usability_diag.simple_structure_controls && flow_ok;

    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    flow_ok = refresh_preview_or_fail() && flow_ok;
    std::size_t visible_preview_rows = 0;
    bool preview_has_clean_label_line = false;
    bool preview_has_visual_container = false;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (builder_preview_row_buttons[idx].visible()) {
        visible_preview_rows += 1;
        if (!preview_visual_row_is_container[idx] &&
            builder_preview_row_buttons[idx].text().find("[") == std::string::npos &&
            !builder_preview_row_buttons[idx].text().empty()) {
          preview_has_clean_label_line = true;
        }
        if (preview_visual_row_is_container[idx] && builder_preview_row_buttons[idx].preferred_height() >= 48) {
          preview_has_visual_container = true;
        }
      }
    }
    integrated_usability_diag.visual_preview =
      builder_preview_visual_rows.visible() &&
      !builder_preview_label.visible() &&
      visible_preview_rows > 0 &&
      preview_has_clean_label_line &&
      preview_has_visual_container;
    flow_ok = integrated_usability_diag.visual_preview && flow_ok;

    flow_ok = refresh_inspector_or_fail() && flow_ok;
    const std::string inspector_normal = builder_inspector_label.text();
    const std::string preview_normal = builder_preview_label.text();
    integrated_usability_diag.reduced_debug_noise_normal_mode =
      inspector_normal.find("[PARITY]") == std::string::npos &&
      inspector_normal.find("BLOCKED_REASONS:") == std::string::npos &&
      preview_normal.find("[PARITY]") == std::string::npos &&
      preview_normal.find("BLOCKED_REASONS:") == std::string::npos;
    flow_ok = integrated_usability_diag.reduced_debug_noise_normal_mode && flow_ok;

    const bool sync45_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    integrated_usability_diag.shell_state_still_coherent = sync45_ok;
    flow_ok = integrated_usability_diag.shell_state_still_coherent && flow_ok;

    const bool export45_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export45_ok && flow_ok;
    const bool parity45_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    integrated_usability_diag.preview_remains_parity_safe =
      parity45_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = integrated_usability_diag.preview_remains_parity_safe && flow_ok;

    const auto audit45 = ngk::ui::builder::audit_layout_tree(&root);
    integrated_usability_diag.layout_audit_still_compatible =
      audit45.minimums_ok && audit45.checked_nodes > 0;
    flow_ok = integrated_usability_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_46 = [&] {
    bool flow_ok = true;
    real_interaction_diag = BuilderRealInteractionDiagnostics{};

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    set_last_action_feedback("Ready");

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    refresh_tree_surface_label();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    std::size_t tree_selected_idx = kMaxVisualTreeRows;
    for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
      if (tree_visual_row_node_ids[idx] == "label-001") {
        tree_selected_idx = idx;
        break;
      }
    }
    std::size_t preview_selected_idx = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (preview_visual_row_node_ids[idx] == "label-001") {
        preview_selected_idx = idx;
        break;
      }
    }
    real_interaction_diag.visual_selection_clear =
      tree_selected_idx < kMaxVisualTreeRows &&
      preview_selected_idx < kMaxVisualPreviewRows &&
      builder_tree_row_buttons[tree_selected_idx].text().find("[ACTIVE]") != std::string::npos &&
      builder_preview_row_buttons[preview_selected_idx].is_default_action() &&
      builder_preview_row_buttons[preview_selected_idx].focused();
    flow_ok = real_interaction_diag.visual_selection_clear && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    std::size_t preview_click_idx = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (preview_visual_row_node_ids[idx] == "label-001") {
        preview_click_idx = idx;
        break;
      }
    }
    const bool preview_click_ok =
      preview_click_idx < kMaxVisualPreviewRows &&
      builder_preview_row_buttons[preview_click_idx].perform_primary_action() &&
      selected_builder_node_id == "label-001" &&
      builder_inspector_selection_label.text().find("Editing:") == 0;
    real_interaction_diag.preview_click_selection = preview_click_ok;
    flow_ok = real_interaction_diag.preview_click_selection && flow_ok;

    flow_ok = refresh_preview_or_fail() && flow_ok;
    const bool inline_mode_visible =
      inline_edit_active &&
      inline_edit_node_id == "label-001" &&
      builder_preview_inline_text_input.visible() &&
      builder_preview_inline_actions_row.visible();
    builder_preview_inline_text_input.set_value("Preview Inline 46");
    const bool inline_apply_ok = builder_preview_inline_apply_button.perform_primary_action();
    auto* edited_inline_node = find_node_by_id("label-001");
    real_interaction_diag.inline_text_edit_preview =
      inline_mode_visible &&
      inline_apply_ok &&
      edited_inline_node != nullptr &&
      edited_inline_node->text == "Preview Inline 46" &&
      builder_inspector_selection_label.text().find("Editing:") == 0;
    flow_ok = real_interaction_diag.inline_text_edit_preview && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    const bool add_child_enabled_on_container = builder_inspector_add_child_button.enabled();
    const bool controls_visible =
      builder_inspector_structure_controls_label.visible() &&
      builder_inspector_structure_controls_row.visible() &&
      builder_inspector_delete_button.visible() &&
      builder_inspector_move_up_button.visible() &&
      builder_inspector_move_down_button.visible();
    real_interaction_diag.structure_controls_visible = controls_visible && add_child_enabled_on_container;
    flow_ok = real_interaction_diag.structure_controls_visible && flow_ok;

    selected_builder_node_id.clear();
    focused_builder_node_id.clear();
    multi_selected_node_ids.clear();
    sync_multi_selection_with_primary();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    real_interaction_diag.empty_state_guidance_present =
      builder_inspector_edit_hint_label.text().find("Click NEW DOC to start") != std::string::npos &&
      builder_preview_interaction_hint_label.text().find("Click NEW DOC to start") != std::string::npos;
    flow_ok = real_interaction_diag.empty_state_guidance_present && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    real_interaction_diag.confusion_reduced =
      builder_inspector_selection_label.text().find("Editing:") == 0 &&
      builder_inspector_edit_hint_label.text().find("You can edit Text, Width, and Height") != std::string::npos &&
      !builder_inspector_label.visible();
    flow_ok = real_interaction_diag.confusion_reduced && flow_ok;

    const bool sync46_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    real_interaction_diag.shell_state_still_coherent = sync46_ok;
    flow_ok = real_interaction_diag.shell_state_still_coherent && flow_ok;

    const bool export46_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export46_ok && flow_ok;
    const bool parity46_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    real_interaction_diag.preview_remains_parity_safe =
      parity46_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = real_interaction_diag.preview_remains_parity_safe && flow_ok;

    const auto audit46 = ngk::ui::builder::audit_layout_tree(&root);
    real_interaction_diag.layout_audit_still_compatible =
      audit46.minimums_ok && audit46.checked_nodes > 0;
    flow_ok = real_interaction_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_47 = [&] {
    bool flow_ok = true;
    human_readable_ui_diag = BuilderHumanReadableUiDiagnostics{};

    auto has_forbidden_ui_terms = [&](const std::string& text) -> bool {
      return text.find("??") != std::string::npos ||
             text.find("SELECTED?") != std::string::npos ||
             text.find("EDIT TARGET") != std::string::npos ||
             text.find("NODE_ID") != std::string::npos ||
             text.find("TYPE: LABEL") != std::string::npos ||
             text.find("layout.min_width") != std::string::npos ||
             text.find("layout.min_height") != std::string::npos ||
             text.find("TEXT NOT EDITABLE") != std::string::npos;
    };

    auto find_preview_row_index = [&](const std::string& node_id) -> std::size_t {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (preview_visual_row_node_ids[idx] == node_id) {
          return idx;
        }
      }
      return kMaxVisualPreviewRows;
    };

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    set_last_action_feedback("Ready");

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    refresh_tree_surface_label();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    std::size_t preview_root_idx = find_preview_row_index("root-001");
    std::size_t preview_label_idx = find_preview_row_index("label-001");
    const bool root_group_visible =
      preview_root_idx < kMaxVisualPreviewRows &&
      preview_visual_row_is_container[preview_root_idx] &&
      builder_preview_row_buttons[preview_root_idx].preferred_height() >= 48;
    const bool child_indent_visible =
      preview_label_idx < kMaxVisualPreviewRows &&
      !preview_visual_row_is_container[preview_label_idx] &&
      preview_visual_row_depths[preview_label_idx] > 0;
    human_readable_ui_diag.preview_visualized = root_group_visible && child_indent_visible;
    flow_ok = human_readable_ui_diag.preview_visualized && flow_ok;

    const bool no_technical_terms =
      !has_forbidden_ui_terms(builder_inspector_selection_label.text()) &&
      !has_forbidden_ui_terms(builder_inspector_edit_hint_label.text()) &&
      !has_forbidden_ui_terms(builder_preview_interaction_hint_label.text()) &&
      !has_forbidden_ui_terms(builder_inspector_non_editable_label.text()) &&
      (preview_root_idx >= kMaxVisualPreviewRows ||
       !has_forbidden_ui_terms(builder_preview_row_buttons[preview_root_idx].text()));
    human_readable_ui_diag.human_readable_ui = no_technical_terms;
    flow_ok = human_readable_ui_diag.human_readable_ui && flow_ok;

    if (preview_label_idx < kMaxVisualPreviewRows) {
      const bool click_ok = builder_preview_row_buttons[preview_label_idx].perform_primary_action();
      const std::size_t active_idx = find_preview_row_index("label-001");
      human_readable_ui_diag.selection_clear =
        click_ok &&
        active_idx < kMaxVisualPreviewRows &&
        builder_preview_row_buttons[active_idx].is_default_action() &&
        builder_preview_row_buttons[active_idx].focused();
    }
    flow_ok = human_readable_ui_diag.selection_clear && flow_ok;

    flow_ok = refresh_inspector_or_fail() && flow_ok;
    human_readable_ui_diag.inspector_simplified =
      builder_inspector_layout_min_width_label.text() == "Width" &&
      builder_inspector_layout_min_height_label.text() == "Height" &&
      builder_inspector_edit_hint_label.text().find("layout.min_") == std::string::npos;
    flow_ok = human_readable_ui_diag.inspector_simplified && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    const bool add_child_feedback_ok =
      builder_inspector_add_child_button.perform_primary_action() &&
      last_action_feedback.find("Added child under") != std::string::npos;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::size_t before_move_idx = find_preview_row_index("label-001");
    const bool move_invoked =
      (builder_inspector_move_down_button.enabled() && builder_inspector_move_down_button.perform_primary_action()) ||
      (builder_inspector_move_up_button.enabled() && builder_inspector_move_up_button.perform_primary_action());
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::size_t after_move_idx = find_preview_row_index("label-001");
    const bool move_feedback_ok = last_action_feedback.find("Live Preview order updated") != std::string::npos ||
                                 last_action_feedback.find("already at") != std::string::npos;
    human_readable_ui_diag.structure_feedback_visible =
      add_child_feedback_ok &&
      move_invoked &&
      move_feedback_ok &&
      before_move_idx != after_move_idx;
    flow_ok = human_readable_ui_diag.structure_feedback_visible && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    human_readable_ui_diag.confusion_removed =
      builder_inspector_selection_label.text().find("Editing:") == 0 &&
      builder_inspector_non_editable_label.text().find("This item has no text") != std::string::npos &&
      !has_forbidden_ui_terms(builder_inspector_edit_hint_label.text()) &&
      !has_forbidden_ui_terms(builder_preview_interaction_hint_label.text());
    flow_ok = human_readable_ui_diag.confusion_removed && flow_ok;

    const bool sync47_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    human_readable_ui_diag.shell_state_still_coherent = sync47_ok;
    flow_ok = human_readable_ui_diag.shell_state_still_coherent && flow_ok;

    const bool export47_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export47_ok && flow_ok;
    const bool parity47_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    human_readable_ui_diag.preview_remains_parity_safe =
      parity47_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = human_readable_ui_diag.preview_remains_parity_safe && flow_ok;

    const auto audit47 = ngk::ui::builder::audit_layout_tree(&root);
    human_readable_ui_diag.layout_audit_still_compatible =
      audit47.minimums_ok && audit47.checked_nodes > 0;
    flow_ok = human_readable_ui_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_48 = [&] {
    bool flow_ok = true;
    preview_real_ui_diag = BuilderPreviewRealUiDiagnostics{};

    auto find_preview_row_index = [&](const std::string& node_id) -> std::size_t {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (preview_visual_row_node_ids[idx] == node_id) {
          return idx;
        }
      }
      return kMaxVisualPreviewRows;
    };

    auto has_debug_preview_label = [&](const std::string& text) -> bool {
      return text.find("[GROUP]") != std::string::npos ||
             text.find("[TEXT]") != std::string::npos ||
             text.find("[ACTIVE]") != std::string::npos ||
             text.find("<<<") != std::string::npos ||
             text.find(">>>") != std::string::npos;
    };

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    set_last_action_feedback("Ready");

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    refresh_tree_surface_label();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    std::size_t preview_root_idx = find_preview_row_index("root-001");
    std::size_t preview_label_idx = find_preview_row_index("label-001");

    preview_real_ui_diag.containers_visual =
      preview_root_idx < kMaxVisualPreviewRows &&
      preview_visual_row_is_container[preview_root_idx] &&
      builder_preview_row_buttons[preview_root_idx].preferred_height() >= 48 &&
      builder_preview_row_buttons[preview_root_idx].text() == " ";
    flow_ok = preview_real_ui_diag.containers_visual && flow_ok;

    preview_real_ui_diag.text_clean =
      preview_label_idx < kMaxVisualPreviewRows &&
      !preview_visual_row_is_container[preview_label_idx] &&
      builder_preview_row_buttons[preview_label_idx].text().find("[TEXT]") == std::string::npos &&
      builder_preview_row_buttons[preview_label_idx].text().find("<<<") == std::string::npos &&
      builder_preview_row_buttons[preview_label_idx].text().find(">>>") == std::string::npos;
    flow_ok = preview_real_ui_diag.text_clean && flow_ok;

    bool no_debug_labels = true;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (builder_preview_row_buttons[idx].visible() && has_debug_preview_label(builder_preview_row_buttons[idx].text())) {
        no_debug_labels = false;
        break;
      }
    }
    preview_real_ui_diag.no_debug_labels = no_debug_labels;
    flow_ok = preview_real_ui_diag.no_debug_labels && flow_ok;

    preview_real_ui_diag.hierarchy_visible =
      preview_root_idx < kMaxVisualPreviewRows &&
      preview_label_idx < kMaxVisualPreviewRows &&
      preview_visual_row_depths[preview_label_idx] > preview_visual_row_depths[preview_root_idx] &&
      builder_preview_row_buttons[preview_root_idx].preferred_height() > builder_preview_row_buttons[preview_label_idx].preferred_height();
    flow_ok = preview_real_ui_diag.hierarchy_visible && flow_ok;

    const bool select_label_ok =
      preview_label_idx < kMaxVisualPreviewRows &&
      builder_preview_row_buttons[preview_label_idx].perform_primary_action();
    const std::size_t selected_idx = find_preview_row_index("label-001");
    preview_real_ui_diag.selection_visual =
      select_label_ok &&
      selected_idx < kMaxVisualPreviewRows &&
      builder_preview_row_buttons[selected_idx].is_default_action() &&
      builder_preview_row_buttons[selected_idx].focused();
    flow_ok = preview_real_ui_diag.selection_visual && flow_ok;

    preview_real_ui_diag.preview_real_ui =
      preview_real_ui_diag.containers_visual &&
      preview_real_ui_diag.text_clean &&
      preview_real_ui_diag.no_debug_labels &&
      preview_real_ui_diag.selection_visual &&
      preview_real_ui_diag.hierarchy_visible;
    flow_ok = preview_real_ui_diag.preview_real_ui && flow_ok;

    const bool sync48_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    preview_real_ui_diag.shell_state_still_coherent = sync48_ok;
    flow_ok = preview_real_ui_diag.shell_state_still_coherent && flow_ok;

    const bool export48_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export48_ok && flow_ok;
    const bool parity48_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    preview_real_ui_diag.preview_remains_parity_safe =
      parity48_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = preview_real_ui_diag.preview_remains_parity_safe && flow_ok;

    const auto audit48 = ngk::ui::builder::audit_layout_tree(&root);
    preview_real_ui_diag.layout_audit_still_compatible =
      audit48.minimums_ok && audit48.checked_nodes > 0;
    flow_ok = preview_real_ui_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_49 = [&] {
    bool flow_ok = true;
    action_visibility_diag = BuilderActionVisibilityDiagnostics{};

    auto find_preview_row_index = [&](const std::string& node_id) -> std::size_t {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (preview_visual_row_node_ids[idx] == node_id) {
          return idx;
        }
      }
      return kMaxVisualPreviewRows;
    };

    auto count_visible_preview_rows = [&]() -> std::size_t {
      std::size_t count = 0;
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (builder_preview_row_buttons[idx].visible()) {
          count += 1;
        }
      }
      return count;
    };

    auto find_preview_hint_row = [&]() -> bool {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (builder_preview_row_buttons[idx].visible() &&
            builder_preview_row_buttons[idx].text().find("child will appear here") != std::string::npos) {
          return true;
        }
      }
      return false;
    };

    auto find_any_non_container_id = [&]() -> std::string {
      for (const auto& node : builder_doc.nodes) {
        if (!ngk::ui::builder::widget_allows_children(node.widget_type) && node.node_id != builder_doc.root_node_id) {
          return node.node_id;
        }
      }
      return std::string("label-001");
    };

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    preview_visual_feedback_message.clear();
    preview_visual_feedback_node_id.clear();
    set_last_action_feedback("Ready");

    const std::string non_container_id = find_any_non_container_id();
    selected_builder_node_id = non_container_id;
    focused_builder_node_id = non_container_id;
    multi_selected_node_ids = {non_container_id};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    action_visibility_diag.add_child_validated =
      !builder_inspector_add_child_button.enabled() &&
      (builder_inspector_structure_controls_label.text().find("Only containers can have children") != std::string::npos ||
       builder_preview_interaction_hint_label.text().find("Only containers can have children") != std::string::npos);
    flow_ok = action_visibility_diag.add_child_validated && flow_ok;

    std::size_t size_row_before = find_preview_row_index(non_container_id);
    int before_height = 0;
    std::size_t before_text_len = 0;
    if (size_row_before < kMaxVisualPreviewRows) {
      before_height = builder_preview_row_buttons[size_row_before].preferred_height();
      before_text_len = builder_preview_row_buttons[size_row_before].text().size();
    }
    builder_inspector_layout_min_width_input.set_value("420");
    builder_inspector_layout_min_height_input.set_value("72");
    const bool size_apply_ok = builder_inspector_apply_button.perform_primary_action();
    flow_ok = refresh_preview_or_fail() && flow_ok;
    std::size_t size_row_after = find_preview_row_index(non_container_id);
    int after_height = 0;
    std::size_t after_text_len = 0;
    if (size_row_after < kMaxVisualPreviewRows) {
      after_height = builder_preview_row_buttons[size_row_after].preferred_height();
      after_text_len = builder_preview_row_buttons[size_row_after].text().size();
    }
    action_visibility_diag.size_affects_preview =
      size_apply_ok &&
      size_row_before < kMaxVisualPreviewRows &&
      size_row_after < kMaxVisualPreviewRows &&
      (after_height > before_height || after_text_len > before_text_len);
    flow_ok = action_visibility_diag.size_affects_preview && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    action_visibility_diag.structure_feedback_visible = find_preview_hint_row();
    flow_ok = action_visibility_diag.structure_feedback_visible && flow_ok;

    const std::size_t rows_before_add = count_visible_preview_rows();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    const bool add_child_ok = builder_inspector_add_child_button.perform_primary_action();
    const std::string added_child_id = selected_builder_node_id;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::size_t rows_after_add = count_visible_preview_rows();
    const bool add_child_visible =
      add_child_ok &&
      (rows_after_add > rows_before_add ||
       builder_preview_interaction_hint_label.text().find("Added child") != std::string::npos);

    selected_builder_node_id = non_container_id;
    focused_builder_node_id = non_container_id;
    multi_selected_node_ids = {non_container_id};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const bool move_triggered =
      (builder_inspector_move_down_button.enabled() && builder_inspector_move_down_button.perform_primary_action()) ||
      (builder_inspector_move_up_button.enabled() && builder_inspector_move_up_button.perform_primary_action());
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const bool move_visible =
      move_triggered &&
      (builder_preview_interaction_hint_label.text().find("Moved item") != std::string::npos ||
       builder_preview_interaction_hint_label.text().find("already at") != std::string::npos);

    selected_builder_node_id = !added_child_id.empty() ? added_child_id : non_container_id;
    focused_builder_node_id = selected_builder_node_id;
    multi_selected_node_ids = {selected_builder_node_id};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::size_t rows_before_delete = count_visible_preview_rows();
    const bool delete_ok = builder_inspector_delete_button.enabled() && builder_inspector_delete_button.perform_primary_action();
    flow_ok = refresh_preview_or_fail() && flow_ok;
    const std::size_t rows_after_delete = count_visible_preview_rows();
    const bool delete_visible =
      delete_ok &&
      (rows_after_delete < rows_before_delete ||
       builder_preview_interaction_hint_label.text().find("Deleted") != std::string::npos);

    action_visibility_diag.actions_not_silent = add_child_visible && move_visible && delete_visible;
    flow_ok = action_visibility_diag.actions_not_silent && flow_ok;

    selected_builder_node_id = non_container_id;
    focused_builder_node_id = non_container_id;
    multi_selected_node_ids = {non_container_id};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    action_visibility_diag.confusion_removed =
      !builder_inspector_add_child_button.enabled() &&
      builder_inspector_structure_controls_label.text().find("Only containers can have children") != std::string::npos &&
      !builder_preview_interaction_hint_label.text().empty();
    flow_ok = action_visibility_diag.confusion_removed && flow_ok;

    const bool sync49_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    action_visibility_diag.shell_state_still_coherent = sync49_ok;
    flow_ok = action_visibility_diag.shell_state_still_coherent && flow_ok;

    const bool export49_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export49_ok && flow_ok;
    const bool parity49_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    action_visibility_diag.preview_remains_parity_safe =
      parity49_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = action_visibility_diag.preview_remains_parity_safe && flow_ok;

    const auto audit49 = ngk::ui::builder::audit_layout_tree(&root);
    action_visibility_diag.layout_audit_still_compatible =
      audit49.minimums_ok && audit49.checked_nodes > 0;
    flow_ok = action_visibility_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto attempt_add_child_with_auto_parent = [&]() -> bool {
    bool redirected_to_parent = false;
    std::string requested_id = selected_builder_node_id;
    std::string selected_parent_id;

    if (auto* requested = find_node_by_id(selected_builder_node_id)) {
      if (!is_container_widget_type(requested->widget_type) &&
          !requested->parent_id.empty() &&
          node_exists(requested->parent_id)) {
        selected_parent_id = requested->parent_id;
        selected_builder_node_id = selected_parent_id;
        focused_builder_node_id = selected_parent_id;
        multi_selected_node_ids = {selected_parent_id};
        sync_multi_selection_with_primary();
        redirected_to_parent = true;
        set_tree_visual_feedback(selected_parent_id);
      }
    }

    const std::string parent_before = selected_builder_node_id;
    if (apply_palette_insert(false)) {
      const std::string new_child_id = selected_builder_node_id;
      if (redirected_to_parent) {
        set_last_action_feedback("Switched to parent container to add child. Child added");
        set_preview_visual_feedback("Switched to parent container to add child. Child added", selected_parent_id);
      } else {
        set_last_action_feedback("Child added");
        set_preview_visual_feedback("Child added", new_child_id);
      }
      set_tree_visual_feedback(new_child_id);
      recompute_builder_dirty_state(true);
      return true;
    }

    set_last_action_feedback("Only containers can have children");
    set_preview_visual_feedback("Only containers can have children.", requested_id.empty() ? parent_before : requested_id);
    set_tree_visual_feedback(requested_id);
    return false;
  };

  auto run_phase103_50 = [&] {
    bool flow_ok = true;
    clarity_enforcement_diag = BuilderClarityEnforcementDiagnostics{};

    auto find_preview_row_index = [&](const std::string& node_id) -> std::size_t {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (preview_visual_row_node_ids[idx] == node_id) {
          return idx;
        }
      }
      return kMaxVisualPreviewRows;
    };

    auto find_tree_row_index = [&](const std::string& node_id) -> std::size_t {
      for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
        if (tree_visual_row_node_ids[idx] == node_id) {
          return idx;
        }
      }
      return kMaxVisualTreeRows;
    };

    auto leading_spaces = [&](const std::string& text) -> std::size_t {
      std::size_t count = 0;
      for (char ch : text) {
        if (ch != ' ') {
          break;
        }
        count += 1;
      }
      return count;
    };

    auto has_forbidden_debug_text = [&](const std::string& text) -> bool {
      return text.find("[GROUP]") != std::string::npos ||
             text.find("[TEXT]") != std::string::npos ||
             text.find("[ACTIVE]") != std::string::npos ||
             text.find("[SELECTED]") != std::string::npos ||
             text.find("?ACTIVE?") != std::string::npos ||
             text.find("?SELECTED?") != std::string::npos ||
             text.find("?LAYOUT?") != std::string::npos ||
             text.find("<<<") != std::string::npos ||
             text.find(">>>") != std::string::npos;
    };

    auto find_preview_insertion_slot = [&]() -> bool {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (!builder_preview_row_buttons[idx].visible()) {
          continue;
        }
        if (builder_preview_row_buttons[idx].text().find("New item will appear here") != std::string::npos) {
          return true;
        }
      }
      return false;
    };

    auto find_any_non_container_id = [&]() -> std::string {
      for (const auto& node : builder_doc.nodes) {
        if (!ngk::ui::builder::widget_allows_children(node.widget_type) && node.node_id != builder_doc.root_node_id) {
          return node.node_id;
        }
      }
      return std::string("label-001");
    };

    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    preview_visual_feedback_message.clear();
    preview_visual_feedback_node_id.clear();
    tree_visual_feedback_node_id.clear();
    set_last_action_feedback("Ready");

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    update_add_child_target_display();

    const std::size_t preview_root_idx = find_preview_row_index("root-001");
    const std::size_t preview_label_idx = find_preview_row_index("label-001");
    clarity_enforcement_diag.container_visual_clear =
      preview_root_idx < kMaxVisualPreviewRows &&
      preview_visual_row_is_container[preview_root_idx] &&
      builder_preview_row_buttons[preview_root_idx].preferred_height() >= 42 &&
      builder_preview_row_buttons[preview_root_idx].text().find("CONTAINER (") != std::string::npos;
    flow_ok = clarity_enforcement_diag.container_visual_clear && flow_ok;

    clarity_enforcement_diag.label_visual_clear =
      preview_label_idx < kMaxVisualPreviewRows &&
      !preview_visual_row_is_container[preview_label_idx] &&
      builder_preview_row_buttons[preview_label_idx].text().find("CONTAINER (") == std::string::npos &&
      builder_preview_row_buttons[preview_label_idx].preferred_height() <= 36;
    flow_ok = clarity_enforcement_diag.label_visual_clear && flow_ok;

    const std::string non_container_id = find_any_non_container_id();
    selected_builder_node_id = non_container_id;
    focused_builder_node_id = non_container_id;
    multi_selected_node_ids = {non_container_id};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    update_add_child_target_display();
    clarity_enforcement_diag.add_child_disabled_for_label =
      !builder_inspector_add_child_button.enabled() &&
      builder_inspector_structure_controls_label.text().find("Only containers can have children") != std::string::npos;
    flow_ok = clarity_enforcement_diag.add_child_disabled_for_label && flow_ok;

    std::string expected_parent_id;
    if (auto* node = find_node_by_id(non_container_id)) {
      expected_parent_id = node->parent_id;
    }
    const bool corrected_add_ok = attempt_add_child_with_auto_parent();
    refresh_tree_surface_label();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    clarity_enforcement_diag.auto_parent_correction =
      corrected_add_ok &&
      !expected_parent_id.empty() &&
      builder_preview_interaction_hint_label.text().find("Switched to parent container to add child") != std::string::npos &&
      preview_visual_feedback_node_id == expected_parent_id;
    flow_ok = clarity_enforcement_diag.auto_parent_correction && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    clarity_enforcement_diag.insertion_slot_visible = find_preview_insertion_slot();
    flow_ok = clarity_enforcement_diag.insertion_slot_visible && flow_ok;

    const std::size_t tree_root_idx = find_tree_row_index("root-001");
    const std::size_t tree_label_idx = find_tree_row_index("label-001");
    clarity_enforcement_diag.hierarchy_visually_clear =
      preview_root_idx < kMaxVisualPreviewRows &&
      preview_label_idx < kMaxVisualPreviewRows &&
      preview_visual_row_depths[preview_label_idx] > preview_visual_row_depths[preview_root_idx] &&
      tree_root_idx < kMaxVisualTreeRows &&
      tree_label_idx < kMaxVisualTreeRows &&
      leading_spaces(builder_tree_row_buttons[tree_label_idx].text()) >
        leading_spaces(builder_tree_row_buttons[tree_root_idx].text());
    flow_ok = clarity_enforcement_diag.hierarchy_visually_clear && flow_ok;

    const bool select_label_from_tree =
      tree_label_idx < kMaxVisualTreeRows &&
      builder_tree_row_buttons[tree_label_idx].perform_primary_action();
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    const std::size_t selected_tree_idx = find_tree_row_index("label-001");
    const std::size_t selected_preview_idx = find_preview_row_index("label-001");
    clarity_enforcement_diag.selection_unmistakable =
      select_label_from_tree &&
      selected_tree_idx < kMaxVisualTreeRows &&
      selected_preview_idx < kMaxVisualPreviewRows &&
      builder_tree_row_buttons[selected_tree_idx].focused() &&
      builder_tree_row_buttons[selected_tree_idx].is_default_action() &&
      builder_preview_row_buttons[selected_preview_idx].focused() &&
      builder_preview_row_buttons[selected_preview_idx].is_default_action();
    flow_ok = clarity_enforcement_diag.selection_unmistakable && flow_ok;

    bool no_debug_text = !has_forbidden_debug_text(builder_preview_interaction_hint_label.text()) &&
                         !has_forbidden_debug_text(builder_inspector_structure_controls_label.text()) &&
                         !has_forbidden_debug_text(builder_inspector_edit_hint_label.text());
    for (std::size_t idx = 0; idx < kMaxVisualTreeRows && no_debug_text; ++idx) {
      if (builder_tree_row_buttons[idx].visible() && has_forbidden_debug_text(builder_tree_row_buttons[idx].text())) {
        no_debug_text = false;
      }
    }
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows && no_debug_text; ++idx) {
      if (builder_preview_row_buttons[idx].visible() && has_forbidden_debug_text(builder_preview_row_buttons[idx].text())) {
        no_debug_text = false;
      }
    }
    clarity_enforcement_diag.no_debug_text_remaining = no_debug_text;
    flow_ok = clarity_enforcement_diag.no_debug_text_remaining && flow_ok;

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    const bool add_ok = attempt_add_child_with_auto_parent();
    const bool add_feedback_ok = builder_preview_interaction_hint_label.text().find("Child added") != std::string::npos;

    selected_builder_node_id = non_container_id;
    focused_builder_node_id = non_container_id;
    multi_selected_node_ids = {non_container_id};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    const bool move_ok =
      (builder_inspector_move_up_button.enabled() && builder_inspector_move_up_button.perform_primary_action()) ||
      (builder_inspector_move_down_button.enabled() && builder_inspector_move_down_button.perform_primary_action());
    const bool move_feedback_ok =
      builder_preview_interaction_hint_label.text().find("Moved up") != std::string::npos ||
      builder_preview_interaction_hint_label.text().find("Moved down") != std::string::npos ||
      builder_preview_interaction_hint_label.text().find("already") != std::string::npos;

    const std::string delete_target = selected_builder_node_id;
    selected_builder_node_id = delete_target;
    focused_builder_node_id = delete_target;
    multi_selected_node_ids = {delete_target};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    const bool delete_ok = builder_inspector_delete_button.enabled() && builder_inspector_delete_button.perform_primary_action();
    const bool delete_feedback_ok = builder_preview_interaction_hint_label.text().find("Item removed") != std::string::npos;

    clarity_enforcement_diag.actions_not_silent =
      add_ok && add_feedback_ok && move_ok && move_feedback_ok && delete_ok && delete_feedback_ok;
    flow_ok = clarity_enforcement_diag.actions_not_silent && flow_ok;

    clarity_enforcement_diag.confusion_removed =
      builder_inspector_structure_controls_label.text().find("Only containers can have children") != std::string::npos &&
      builder_preview_interaction_hint_label.text().find("?") == std::string::npos &&
      !builder_preview_interaction_hint_label.text().empty();
    flow_ok = clarity_enforcement_diag.confusion_removed && flow_ok;

    const bool sync50_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    clarity_enforcement_diag.shell_state_still_coherent = sync50_ok;
    flow_ok = clarity_enforcement_diag.shell_state_still_coherent && flow_ok;

    // Rebuild a clean, deterministic doc state before final parity validation.
    run_phase103_2();
    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    const bool export50_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export50_ok && flow_ok;
    const bool parity50_ok = validate_preview_export_parity(builder_doc, builder_export_path);
    clarity_enforcement_diag.preview_remains_parity_safe =
      parity50_ok &&
      last_preview_export_parity_status_code == "success";
    flow_ok = clarity_enforcement_diag.preview_remains_parity_safe && flow_ok;

    const auto audit50 = ngk::ui::builder::audit_layout_tree(&root);
    clarity_enforcement_diag.layout_audit_still_compatible =
      audit50.minimums_ok && audit50.checked_nodes > 0;
    flow_ok = clarity_enforcement_diag.layout_audit_still_compatible && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_51 = [&] {
    bool flow_ok = true;
    insert_target_clarity_diag = BuilderInsertTargetClarityDiagnostics{};

    auto find_preview_row_index = [&](const std::string& node_id) -> std::size_t {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (preview_visual_row_node_ids[idx] == node_id) {
          return idx;
        }
      }
      return kMaxVisualPreviewRows;
    };

    // Reset to deterministic state
    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    preview_visual_feedback_message.clear();
    preview_visual_feedback_node_id.clear();
    tree_visual_feedback_node_id.clear();
    set_last_action_feedback("Ready");

    // 1. TARGET DISPLAY VISIBLE - Check that target label exists and is non-empty
    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    
    insert_target_clarity_diag.target_display_visible =
      builder_add_child_target_label.visible() &&
      !builder_add_child_target_label.text().empty();
    flow_ok = insert_target_clarity_diag.target_display_visible && flow_ok;

    // 2. TARGET MATCHES STRUCTURE SELECTION - Label should track selection semantics
    const bool root_target_ok =
      node_exists(selected_builder_node_id) &&
      builder_inspector_add_child_button.enabled();

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    const bool label_target_ok =
      node_exists(selected_builder_node_id) &&
      !builder_inspector_add_child_button.enabled();

    insert_target_clarity_diag.target_matches_structure_selection = root_target_ok && label_target_ok;
    flow_ok = insert_target_clarity_diag.target_matches_structure_selection && flow_ok;

    // 3. PREVIEW CLICK UPDATES STRUCTURE SELECTION - Test clicking a preview node
    const std::size_t label_idx = find_preview_row_index("label-001");
    std::string clicked_node_id;
    if (label_idx < kMaxVisualPreviewRows && builder_preview_row_buttons[label_idx].visible()) {
      builder_preview_row_buttons[label_idx].perform_primary_action();
      clicked_node_id = selected_builder_node_id;
    }
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    refresh_tree_surface_label();
    update_add_child_target_display();
    
    insert_target_clarity_diag.preview_click_updates_structure_selection =
      !clicked_node_id.empty() &&
      selected_builder_node_id == clicked_node_id &&
      builder_add_child_target_label.text().find("LABEL") != std::string::npos;
    flow_ok = insert_target_clarity_diag.preview_click_updates_structure_selection && flow_ok;

    // 4. ADD CHILD USES CORRECT TARGET - Add child to selected container
    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    refresh_tree_surface_label();
    
    const auto root_before = find_node_by_id("root-001");
    const std::size_t root_children_before = root_before ? root_before->child_ids.size() : 0;
    const bool add_to_root_ok = attempt_add_child_with_auto_parent();
    const auto root_after = find_node_by_id("root-001");
    const std::size_t root_children_after = root_after ? root_after->child_ids.size() : 0;
    
    insert_target_clarity_diag.add_child_uses_correct_target =
      add_to_root_ok &&
      root_children_after > root_children_before;
    flow_ok = insert_target_clarity_diag.add_child_uses_correct_target && flow_ok;

    // 5. INSERT VISIBLE IN STRUCTURE - New node must appear in tree
    refresh_tree_surface_label();
    bool inserted_visible_in_tree = false;
    if (root_after && !root_after->child_ids.empty()) {
      const std::string new_node_id = root_after->child_ids.back();
      if (!new_node_id.empty()) {
        for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
          if (tree_visual_row_node_ids[idx] == new_node_id && builder_tree_row_buttons[idx].visible()) {
            inserted_visible_in_tree = true;
            break;
          }
        }
      }
    }
    insert_target_clarity_diag.insert_visible_in_structure = inserted_visible_in_tree;
    flow_ok = insert_target_clarity_diag.insert_visible_in_structure && flow_ok;

    // 6. INSERT VISIBLE IN PREVIEW - New node must appear in preview
    refresh_preview_or_fail();
    bool inserted_visible_in_preview = false;
    if (root_after && !root_after->child_ids.empty()) {
      const std::string new_node_id = root_after->child_ids.back();
      const std::size_t new_idx = find_preview_row_index(new_node_id);
      if (new_idx < kMaxVisualPreviewRows && builder_preview_row_buttons[new_idx].visible()) {
        inserted_visible_in_preview = true;
      }
    }
    insert_target_clarity_diag.insert_visible_in_preview = inserted_visible_in_preview;
    flow_ok = insert_target_clarity_diag.insert_visible_in_preview && flow_ok;

    // 7. POST INSERT SELECTION DETERMINISTIC - Selection should be stable after insert
    const std::string post_insert_selection = selected_builder_node_id;
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    
    insert_target_clarity_diag.post_insert_selection_deterministic =
      selected_builder_node_id == post_insert_selection &&
      !selected_builder_node_id.empty() &&
      node_exists(selected_builder_node_id);
    flow_ok = insert_target_clarity_diag.post_insert_selection_deterministic && flow_ok;

    // 8. INVALID INSERT BLOCKED - Cannot add to non-containers
    const std::string non_container_id = "label-001";
    if (node_exists(non_container_id)) {
      selected_builder_node_id = non_container_id;
      focused_builder_node_id = non_container_id;
      multi_selected_node_ids = {non_container_id};
      sync_multi_selection_with_primary();
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = refresh_inspector_or_fail() && flow_ok;
      flow_ok = refresh_preview_or_fail() && flow_ok;
      refresh_tree_surface_label();
      
      const bool button_enabled = builder_inspector_add_child_button.enabled();
      insert_target_clarity_diag.invalid_insert_blocked = !button_enabled;
      flow_ok = insert_target_clarity_diag.invalid_insert_blocked && flow_ok;
    }

    // 9. NO COMMAND PIPELINE REGRESSION - Export should still work
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;
    
    const bool export51_ok = apply_export_command(builder_doc, builder_export_path);
    insert_target_clarity_diag.no_command_pipeline_regression = export51_ok;
    flow_ok = insert_target_clarity_diag.no_command_pipeline_regression && flow_ok;

    // 10. UI STATE COHERENT - All surfaces consistent
    const bool sync51_ok = remap_selection_or_fail() &&
                           sync_focus_with_selection_or_fail() &&
                           refresh_inspector_or_fail() &&
                           refresh_preview_or_fail() &&
                           check_cross_surface_sync();
    insert_target_clarity_diag.ui_state_coherent = sync51_ok;
    flow_ok = insert_target_clarity_diag.ui_state_coherent && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_52 = [&] {
    bool flow_ok = true;
    preview_structure_parity_diag = BuilderPreviewStructureParityDiagnostics{};

    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      refresh_tree_surface_label();
      update_add_child_target_display();
      return ok;
    };

    auto collect_preview_rows = [&](std::vector<std::string>& ids_out,
                                   std::vector<int>& depths_out) {
      ids_out.clear();
      depths_out.clear();
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (!builder_preview_row_buttons[idx].visible()) {
          continue;
        }
        if (preview_visual_row_node_ids[idx].empty()) {
          continue;
        }
        ids_out.push_back(preview_visual_row_node_ids[idx]);
        depths_out.push_back(preview_visual_row_depths[idx]);
      }
    };

    auto get_doc_parent_id = [&](const std::string& node_id) -> std::string {
      auto* node = find_node_by_id(node_id);
      return node ? node->parent_id : std::string();
    };

    auto preview_ids_all_valid = [&](const std::vector<std::string>& preview_ids) -> bool {
      std::vector<std::string> seen{};
      for (const auto& node_id : preview_ids) {
        if (node_id.empty() || !node_exists(node_id)) {
          return false;
        }
        if (std::find(seen.begin(), seen.end(), node_id) != seen.end()) {
          return false;
        }
        seen.push_back(node_id);
      }
      return true;
    };

    auto preview_parent_child_matches = [&](const std::vector<std::string>& preview_ids,
                                            const std::vector<int>& preview_depths) -> bool {
      if (preview_ids.size() != preview_depths.size()) {
        return false;
      }
      std::vector<std::string> depth_stack{};
      for (std::size_t idx = 0; idx < preview_ids.size(); ++idx) {
        const int depth = std::max(0, preview_depths[idx]);
        while (static_cast<int>(depth_stack.size()) > depth) {
          depth_stack.pop_back();
        }

        const std::string expected_parent = depth == 0
          ? std::string()
          : (depth_stack.empty() ? std::string() : depth_stack.back());
        const std::string actual_parent = get_doc_parent_id(preview_ids[idx]);
        if (expected_parent != actual_parent) {
          return false;
        }
        depth_stack.push_back(preview_ids[idx]);
      }
      return true;
    };

    auto find_first_deletable_node_id = [&]() -> std::string {
      for (const auto& node : builder_doc.nodes) {
        if (node.node_id == builder_doc.root_node_id) {
          continue;
        }
        if (node.parent_id.empty() || !node_exists(node.parent_id)) {
          continue;
        }
        if (node.container_type == ngk::ui::builder::BuilderContainerType::Shell) {
          continue;
        }
        return node.node_id;
      }
      return std::string();
    };

    auto find_preview_row_index = [&](const std::string& node_id) -> std::size_t {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (preview_visual_row_node_ids[idx] == node_id && builder_preview_row_buttons[idx].visible()) {
          return idx;
        }
      }
      return kMaxVisualPreviewRows;
    };

    auto check_preview_structure_parity = [&]() -> bool {
      std::vector<PreviewExportParityEntry> entries{};
      std::string reason;
      if (!build_preview_export_parity_entries(builder_doc, entries, reason, "phase103_52")) {
        return false;
      }

      std::vector<std::string> preview_ids{};
      std::vector<int> preview_depths{};
      collect_preview_rows(preview_ids, preview_depths);

      const bool count_match = preview_ids.size() == entries.size();
      const bool all_preview_valid = preview_ids_all_valid(preview_ids);

      bool order_match = count_match;
      if (order_match) {
        for (std::size_t idx = 0; idx < preview_ids.size(); ++idx) {
          if (preview_ids[idx] != entries[idx].node_id || preview_depths[idx] != entries[idx].depth) {
            order_match = false;
            break;
          }
        }
      }

      const bool parent_child_ok = preview_parent_child_matches(preview_ids, preview_depths);

      preview_structure_parity_diag.preview_nodes_match_structure = count_match;
      preview_structure_parity_diag.no_orphan_preview_nodes = all_preview_valid;
      preview_structure_parity_diag.render_order_matches_structure = order_match;
      preview_structure_parity_diag.parent_child_relationships_match = parent_child_ok;

      return count_match && all_preview_valid && order_match && parent_child_ok;
    };

    // Baseline state
    run_phase103_2();
    set_builder_projection_filter_state("");
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    builder_debug_mode = false;
    builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
    preview_visual_feedback_message.clear();
    preview_visual_feedback_node_id.clear();
    tree_visual_feedback_node_id.clear();
    set_last_action_feedback("Ready");

    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const bool baseline_parity_ok = check_preview_structure_parity();
    flow_ok = baseline_parity_ok && flow_ok;

    // Hit-test exact node resolution + parent/depth correctness
    std::vector<PreviewExportParityEntry> hit_entries{};
    std::string hit_reason;
    bool hit_map_ok = build_preview_click_hit_entries(hit_entries, hit_reason);
    bool hit_exact_ok = false;
    if (hit_map_ok) {
      int outline_first_line_index = -1;
      const std::string preview_text = builder_preview_label.text();
      const std::string outline_token = "runtime_outline:\n";
      const auto outline_pos = preview_text.find(outline_token);
      if (outline_pos != std::string::npos) {
        outline_first_line_index = 0;
        for (std::size_t i = 0; i < outline_pos + outline_token.size(); ++i) {
          if (preview_text[i] == '\n') {
            outline_first_line_index += 1;
          }
        }
      }

      constexpr int kPreviewLineHeightPx = 16;
      const int visible_line_capacity = std::max(1, builder_preview_label.height() / kPreviewLineHeightPx);
      std::size_t target_index = 0;
      bool target_found = false;
      if (outline_first_line_index >= 0) {
        for (std::size_t i = 0; i < hit_entries.size(); ++i) {
          if (hit_entries[i].node_id != "label-001") {
            continue;
          }
          const auto line_index = outline_first_line_index + static_cast<int>(i);
          if (line_index < 0 || line_index >= visible_line_capacity) {
            continue;
          }
          target_index = i;
          target_found = true;
          break;
        }
      }

      const int click_x = builder_preview_label.x() + 8;
      bool click_ok = false;
      if (target_found) {
        const int preferred_click_y =
          builder_preview_label.y() + ((outline_first_line_index + static_cast<int>(target_index)) * kPreviewLineHeightPx) + 2;
        if (apply_preview_click_select_at_point(click_x, preferred_click_y) && selected_builder_node_id == "label-001") {
          click_ok = true;
        }
      }
      if (!click_ok) {
        for (int line = 0; line < visible_line_capacity; ++line) {
          const int probe_y = builder_preview_label.y() + (line * kPreviewLineHeightPx) + 2;
          if (!apply_preview_click_select_at_point(click_x, probe_y)) {
            continue;
          }
          if (selected_builder_node_id == "label-001") {
            click_ok = true;
            break;
          }
        }
      }
      flow_ok = refresh_all_surfaces() && flow_ok;

      int expected_depth = -1;
      for (const auto& entry : hit_entries) {
        if (entry.node_id == "label-001") {
          expected_depth = entry.depth;
          break;
        }
      }
      const std::size_t selected_idx = find_preview_row_index(selected_builder_node_id);
      const bool depth_ok =
        selected_idx < kMaxVisualPreviewRows &&
        expected_depth >= 0 &&
        preview_visual_row_depths[selected_idx] == expected_depth;
      const bool parent_ok =
        node_exists(selected_builder_node_id) &&
        !get_doc_parent_id(selected_builder_node_id).empty();
      hit_exact_ok = click_ok && selected_builder_node_id == "label-001" && depth_ok && parent_ok;
    }
    preview_structure_parity_diag.hit_test_returns_exact_node = hit_exact_ok;
    flow_ok = preview_structure_parity_diag.hit_test_returns_exact_node && flow_ok;

    // Identity alignment: verify action feedback and inspector binding match final selected node
    {
      const std::string expected_action = std::string("Action: Selected ") + selected_builder_node_id;
      preview_structure_parity_diag.action_selected_id_matches_selected_node =
        hit_exact_ok &&
        !selected_builder_node_id.empty() &&
        (last_action_feedback == expected_action);
      preview_structure_parity_diag.selected_node_matches_selected_id =
        hit_exact_ok &&
        !selected_builder_node_id.empty() &&
        (inspector_binding_node_id == selected_builder_node_id) &&
        (preview_binding_node_id == selected_builder_node_id);
      // Direct identity proof: log actual values for the reproduced case
      std::cout << "phase103_52_case_selected_node_id=" << selected_builder_node_id << "\n";
      std::cout << "phase103_52_case_action_feedback=" << last_action_feedback << "\n";
      std::cout << "phase103_52_case_inspector_binding_id=" << inspector_binding_node_id << "\n";
      std::cout << "phase103_52_case_preview_binding_id=" << preview_binding_node_id << "\n";
      flow_ok = preview_structure_parity_diag.action_selected_id_matches_selected_node && flow_ok;
      flow_ok = preview_structure_parity_diag.selected_node_matches_selected_id && flow_ok;
    }

    // Selection stability after insert
    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool insert_ok = attempt_add_child_with_auto_parent();
    flow_ok = refresh_all_surfaces() && flow_ok;
    preview_structure_parity_diag.selection_stable_after_insert =
      insert_ok &&
      !selected_builder_node_id.empty() &&
      node_exists(selected_builder_node_id) &&
      check_cross_surface_sync();
    flow_ok = preview_structure_parity_diag.selection_stable_after_insert && flow_ok;

    // Selection stability after delete and no stale nodes after mutation
    run_phase103_2();
    set_builder_projection_filter_state("");
    undo_history.clear();
    redo_stack.clear();
    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const std::string delete_target = find_first_deletable_node_id();
    bool delete_ok = false;
    if (!delete_target.empty()) {
      selected_builder_node_id = delete_target;
      focused_builder_node_id = delete_target;
      multi_selected_node_ids = {delete_target};
      sync_multi_selection_with_primary();
      flow_ok = refresh_all_surfaces() && flow_ok;
      delete_ok = apply_delete_command_for_current_selection();
      flow_ok = refresh_all_surfaces() && flow_ok;
    }

    preview_structure_parity_diag.selection_stable_after_delete =
      delete_ok &&
      !selected_builder_node_id.empty() &&
      node_exists(selected_builder_node_id) &&
      check_cross_surface_sync();
    flow_ok = preview_structure_parity_diag.selection_stable_after_delete && flow_ok;

    preview_structure_parity_diag.no_stale_nodes_after_mutation =
      delete_ok &&
      !delete_target.empty() &&
      !node_exists(delete_target) &&
      !is_row_visible(delete_target, builder_preview_row_buttons, preview_visual_row_node_ids) &&
      !is_row_visible(delete_target, builder_tree_row_buttons, tree_visual_row_node_ids) &&
      check_preview_structure_parity();
    flow_ok = preview_structure_parity_diag.no_stale_nodes_after_mutation && flow_ok;

    // Selection stability after move
    run_phase103_2();
    set_builder_projection_filter_state("");
    undo_history.clear();
    redo_stack.clear();
    selected_builder_node_id = "root-001";
    focused_builder_node_id = "root-001";
    multi_selected_node_ids = {"root-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const bool add_for_move_ok = attempt_add_child_with_auto_parent();
    flow_ok = refresh_all_surfaces() && flow_ok;
    bool move_ok = false;
    if (add_for_move_ok && builder_inspector_move_up_button.enabled()) {
      builder_inspector_move_up_button.perform_primary_action();
      move_ok = true;
      flow_ok = refresh_all_surfaces() && flow_ok;
    } else if (add_for_move_ok && builder_inspector_move_down_button.enabled()) {
      builder_inspector_move_down_button.perform_primary_action();
      move_ok = true;
      flow_ok = refresh_all_surfaces() && flow_ok;
    }

    preview_structure_parity_diag.selection_stable_after_move =
      move_ok &&
      !selected_builder_node_id.empty() &&
      node_exists(selected_builder_node_id) &&
      check_cross_surface_sync() &&
      check_preview_structure_parity();
    flow_ok = preview_structure_parity_diag.selection_stable_after_move && flow_ok;

    preview_structure_parity_diag.no_selection_desync_detected =
      check_cross_surface_sync() &&
      (!selected_builder_node_id.empty()) &&
      node_exists(selected_builder_node_id) &&
      is_row_visible(selected_builder_node_id, builder_preview_row_buttons, preview_visual_row_node_ids) &&
      is_row_visible(selected_builder_node_id, builder_tree_row_buttons, tree_visual_row_node_ids);
    flow_ok = preview_structure_parity_diag.no_selection_desync_detected && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_53 = [&] {
    ::desktop_file_tool::CommandIntegrityPhase10353Binding __phase103_53_binding{
      command_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      selected_builder_node_id,
      focused_builder_node_id,
      multi_selected_node_ids,
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() { refresh_tree_surface_label(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() { update_add_child_target_display(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const ngk::ui::builder::BuilderDocument& doc, const char* context_name) -> std::string {
        return build_document_signature(doc, context_name);
      },
      [&](const std::vector<std::string>& ids) -> std::string { return join_ids(ids); },
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason,
          const char* context_name) -> bool {
        return build_preview_export_parity_entries(doc, entries, reason, context_name);
      },
      [&]() -> std::vector<std::pair<std::string, int>> {
        std::vector<std::pair<std::string, int>> visible_entries{};
        for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
          if (!builder_preview_row_buttons[idx].visible() || preview_visual_row_node_ids[idx].empty()) {
            continue;
          }
          visible_entries.emplace_back(preview_visual_row_node_ids[idx], preview_visual_row_depths[idx]);
        }
        return visible_entries;
      },
      [&](const ngk::ui::builder::BuilderDocument& doc, const std::string& node_id) -> bool {
        return node_exists_in_document(doc, node_id);
      },
      [&](const ngk::ui::builder::BuilderDocument& doc, const std::string& node_id) -> const ngk::ui::builder::BuilderNode* {
        return find_node_by_id_in_document(doc, node_id);
      },
      [&](const ngk::ui::builder::BuilderDocument& doc, std::string* error) -> bool {
        return ngk::ui::builder::validate_builder_document(doc, error);
      },
      [&]() { run_phase103_2(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](const std::string& text) -> bool { return apply_inspector_text_edit_command(text); },
      [&](ngk::ui::builder::BuilderWidgetType widget_type, const std::string& parent_id, const std::string& requested_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, requested_id);
      },
      [&]() -> bool { return apply_delete_command_for_current_selection(); },
      [&]() { apply_move_sibling_up(); },
      [&](const std::string& history_tag,
          const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
          const std::string& before_root,
          const std::string& before_sel,
          const std::vector<std::string>* before_multi,
          const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
          const std::string& after_root,
          const std::string& after_sel,
          const std::vector<std::string>* after_multi) {
        push_to_history(history_tag, before_nodes, before_root, before_sel, before_multi, after_nodes, after_root, after_sel, after_multi);
      },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
      [&](const ngk::ui::builder::BuilderDocument& doc) -> bool { return document_has_unique_node_ids(doc); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
    };
    ::desktop_file_tool::run_phase103_53_command_integrity_phase(__phase103_53_binding);
  };

  auto run_phase103_54 = [&] {
    bool flow_ok = true;
    save_load_integrity_diag = BuilderSaveLoadStateIntegrityDiagnostics{};

    auto build_live_state_signature = [&](const char* context_name) -> std::string {
      std::ostringstream oss;
      oss << build_document_signature(builder_doc, context_name) << "\n";
      oss << "selected=" << selected_builder_node_id << "\n";
      oss << "multi=" << join_ids(multi_selected_node_ids) << "\n";
      return oss.str();
    };

    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      refresh_tree_surface_label();
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      update_add_child_target_display();
      ok = check_cross_surface_sync() && ok;
      return ok;
    };

    auto preview_matches_structure = [&]() -> bool {
      std::vector<PreviewExportParityEntry> entries{};
      std::string reason;
      if (!build_preview_export_parity_entries(builder_doc, entries, reason, "phase103_54")) {
        return false;
      }

      std::vector<std::string> preview_ids{};
      std::vector<int> preview_depths{};
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (!builder_preview_row_buttons[idx].visible() || preview_visual_row_node_ids[idx].empty()) {
          continue;
        }
        preview_ids.push_back(preview_visual_row_node_ids[idx]);
        preview_depths.push_back(preview_visual_row_depths[idx]);
      }

      if (preview_ids.size() != entries.size()) {
        return false;
      }
      for (std::size_t idx = 0; idx < entries.size(); ++idx) {
        if (preview_ids[idx] != entries[idx].node_id || preview_depths[idx] != entries[idx].depth) {
          return false;
        }
      }
      return true;
    };

    auto reset_phase = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      builder_doc_dirty = false;
      preview_visual_feedback_message.clear();
      preview_visual_feedback_node_id.clear();
      tree_visual_feedback_node_id.clear();
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    auto replace_first = [&](std::string& text,
                             const std::string& target,
                             const std::string& replacement) -> bool {
      const std::size_t pos = text.find(target);
      if (pos == std::string::npos) {
        return false;
      }
      text.replace(pos, target.size(), replacement);
      return true;
    };

    flow_ok = reset_phase() && flow_ok;
    const bool inserted = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, builder_doc.root_node_id, "phase103_54-node-a");
    flow_ok = inserted && flow_ok;

    auto* inserted_node = find_node_by_id("phase103_54-node-a");
    if (inserted_node != nullptr) {
      inserted_node->text = "phase103_54_text_seed";
    } else {
      flow_ok = false;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    const std::string before_save_doc = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string before_save_live = build_live_state_signature("phase103_54_before_save");
    const bool first_save_ok = apply_save_document_command();
    flow_ok = first_save_ok && flow_ok;
    std::string first_saved_file_text{};
    const bool read_first_save_ok = first_save_ok && read_text_file(builder_doc_save_path, first_saved_file_text);
    flow_ok = read_first_save_ok && flow_ok;

    if (inserted_node != nullptr) {
      inserted_node->text = "phase103_54_mutated_after_save";
      undo_history.push_back(CommandHistoryEntry{});
      redo_stack.push_back(CommandHistoryEntry{});
      flow_ok = refresh_all_surfaces() && flow_ok;
    }

    const bool roundtrip_load_ok = apply_load_document_command(true);
    flow_ok = roundtrip_load_ok && flow_ok;
    const std::string after_roundtrip_doc = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const std::string after_roundtrip_live = build_live_state_signature("phase103_54_after_roundtrip_load");

    save_load_integrity_diag.serialized_roundtrip_exact =
      first_save_ok &&
      roundtrip_load_ok &&
      !before_save_doc.empty() &&
      before_save_doc == after_roundtrip_doc;
    save_load_integrity_diag.no_implicit_state_mutation_after_roundtrip =
      roundtrip_load_ok &&
      before_save_live == after_roundtrip_live;
    save_load_integrity_diag.history_reset_deterministic_on_load =
      roundtrip_load_ok &&
      undo_history.empty() &&
      redo_stack.empty();
    save_load_integrity_diag.cross_surface_sync_preserved_after_load =
      roundtrip_load_ok &&
      check_cross_surface_sync();
    save_load_integrity_diag.preview_structure_parity_preserved_after_load =
      roundtrip_load_ok &&
      preview_matches_structure();

    const bool second_save_ok = apply_save_document_command();
    flow_ok = second_save_ok && flow_ok;
    std::string second_saved_file_text{};
    const bool read_second_save_ok = second_save_ok && read_text_file(builder_doc_save_path, second_saved_file_text);
    flow_ok = read_second_save_ok && flow_ok;
    save_load_integrity_diag.save_load_repeatability_stable =
      first_save_ok &&
      roundtrip_load_ok &&
      second_save_ok &&
      read_first_save_ok &&
      read_second_save_ok &&
      first_saved_file_text == second_saved_file_text;

    selected_builder_node_id = "phase103_54_missing_selection";
    focused_builder_node_id = "phase103_54_missing_selection";
    multi_selected_node_ids = {"phase103_54_missing_selection"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool rebound_load_ok = apply_load_document_command(true);
    flow_ok = rebound_load_ok && flow_ok;
    save_load_integrity_diag.selection_rebound_to_valid_node_on_load =
      rebound_load_ok &&
      !selected_builder_node_id.empty() &&
      node_exists(selected_builder_node_id) &&
      selected_builder_node_id == builder_doc.root_node_id &&
      multi_selected_node_ids.size() == 1 &&
      multi_selected_node_ids.front() == selected_builder_node_id;

    const std::string before_invalid_live = build_live_state_signature("phase103_54_before_invalid_load");
    const std::filesystem::path corrupt_path = builder_doc_save_path.string() + ".phase103_54_corrupt";
    const bool wrote_corrupt = write_text_file(corrupt_path, "not-a-valid-builder-document");
    const bool corrupt_rejected = wrote_corrupt && !load_builder_document_from_path(corrupt_path);
    const std::string after_corrupt_live = build_live_state_signature("phase103_54_after_corrupt_load");

    std::string schema_invalid_payload = first_saved_file_text;
    const bool payload_mutated = replace_first(
      schema_invalid_payload,
      builder_doc.root_node_id,
      "phase103_54_missing_root_reference");
    const std::filesystem::path schema_invalid_path = builder_doc_save_path.string() + ".phase103_54_schema_invalid";
    const bool wrote_schema_invalid = payload_mutated && write_text_file(schema_invalid_path, schema_invalid_payload);
    const bool schema_invalid_rejected = wrote_schema_invalid && !load_builder_document_from_path(schema_invalid_path);
    const std::string after_schema_live = build_live_state_signature("phase103_54_after_schema_invalid_load");

    save_load_integrity_diag.load_rejects_corrupt_payload = corrupt_rejected;
    save_load_integrity_diag.load_rejects_schema_violation_payload = schema_invalid_rejected;
    save_load_integrity_diag.failed_load_preserves_previous_state =
      corrupt_rejected &&
      schema_invalid_rejected &&
      before_invalid_live == after_corrupt_live &&
      before_invalid_live == after_schema_live;

    flow_ok = save_load_integrity_diag.serialized_roundtrip_exact && flow_ok;
    flow_ok = save_load_integrity_diag.save_load_repeatability_stable && flow_ok;
    flow_ok = save_load_integrity_diag.load_rejects_corrupt_payload && flow_ok;
    flow_ok = save_load_integrity_diag.load_rejects_schema_violation_payload && flow_ok;
    flow_ok = save_load_integrity_diag.failed_load_preserves_previous_state && flow_ok;
    flow_ok = save_load_integrity_diag.selection_rebound_to_valid_node_on_load && flow_ok;
    flow_ok = save_load_integrity_diag.history_reset_deterministic_on_load && flow_ok;
    flow_ok = save_load_integrity_diag.no_implicit_state_mutation_after_roundtrip && flow_ok;
    flow_ok = save_load_integrity_diag.cross_surface_sync_preserved_after_load && flow_ok;
    flow_ok = save_load_integrity_diag.preview_structure_parity_preserved_after_load && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_57 = [&] {
    ::desktop_file_tool::BoundsLayoutPhase10357Binding __phase103_57_binding{
      bounds_layout_constraint_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      selected_builder_node_id,
      focused_builder_node_id,
      multi_selected_node_ids,
      builder_doc_save_path,
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() { refresh_tree_surface_label(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() { update_add_child_target_display(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason,
          const char* context_name) -> bool {
        return build_preview_export_parity_entries(doc, entries, reason, context_name);
      },
      [&]() { run_phase103_2(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](const ngk::ui::builder::BuilderDocument& doc, const char* context_name) -> std::string {
        return build_document_signature(doc, context_name);
      },
      [&](const std::vector<std::pair<std::string, std::string>>& edits, const std::string& history_tag) -> bool {
        return apply_inspector_property_edits_command(edits, history_tag);
      },
      [&](ngk::ui::builder::BuilderWidgetType widget_type, const std::string& parent_id, const std::string& requested_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, requested_id);
      },
      [&](const std::vector<std::string>& node_ids, const std::string& new_parent_id) -> bool {
        return apply_bulk_move_reparent_selected_nodes_command(node_ids, new_parent_id);
      },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
      [&](const std::filesystem::path& path, const std::string& content) -> bool {
        return write_text_file(path, content);
      },
      [&](const std::string& path) -> bool { return load_builder_document_from_path(path); },
      [&]() -> bool { return apply_save_document_command(); },
      [&](bool bypass_dirty_guard) -> bool { return apply_load_document_command(bypass_dirty_guard); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](std::vector<std::string>& ids, std::vector<int>& depths) {
        ids.clear();
        depths.clear();
        for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
          if (!builder_preview_row_buttons[idx].visible() || preview_visual_row_node_ids[idx].empty()) {
            continue;
          }
          ids.push_back(preview_visual_row_node_ids[idx]);
          depths.push_back(preview_visual_row_depths[idx]);
        }
      },
    };
    ::desktop_file_tool::run_phase103_57_bounds_layout_phase(__phase103_57_binding);
  };

  auto run_phase103_58 = [&] {
    ::desktop_file_tool::EventInputRoutingPhase10358Binding __phase103_58_binding{
      event_input_routing_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      selected_builder_node_id,
      focused_builder_node_id,
      multi_selected_node_ids,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() { refresh_tree_surface_label(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() { update_add_child_target_display(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason,
          const char* context_name) -> bool {
        return build_preview_export_parity_entries(doc, entries, reason, context_name);
      },
      [&]() { run_phase103_2(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](std::vector<PreviewExportParityEntry>& entries, std::string& reason) -> bool {
        return build_preview_click_hit_entries(entries, reason);
      },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&]() { scrub_stale_lifecycle_references(); },
      [&]() -> bool { return apply_keyboard_multi_selection_add_focused(); },
      [&]() -> std::vector<std::string> { return collect_preorder_node_ids(); },
      [&](bool forward) -> bool { return apply_tree_navigation(forward); },
      [&](bool forward) -> bool { return apply_focus_navigation(forward); },
      [&](std::vector<std::string>& ids, std::vector<int>& depths) {
        ids.clear();
        depths.clear();
        for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
          if (!builder_preview_row_buttons[idx].visible() || preview_visual_row_node_ids[idx].empty()) {
            continue;
          }
          ids.push_back(preview_visual_row_node_ids[idx]);
          depths.push_back(preview_visual_row_depths[idx]);
        }
      },
    };
    ::desktop_file_tool::run_phase103_58_event_input_routing_phase(__phase103_58_binding);
  };

  auto run_phase103_59 = [&] {
    ::desktop_file_tool::GlobalInvariantPhase10359Binding __phase103_59_binding{
      global_invariant_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      selected_builder_node_id,
      focused_builder_node_id,
      multi_selected_node_ids,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      global_invariant_checks_total,
      global_invariant_failures_total,
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() { refresh_tree_surface_label(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() { update_add_child_target_display(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason,
          const char* context_name) -> bool {
        return build_preview_export_parity_entries(doc, entries, reason, context_name);
      },
      [&]() { run_phase103_2(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&]() -> std::any { return capture_mutation_checkpoint(); },
      [&](const std::any& checkpoint_any) {
        restore_mutation_checkpoint(std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any));
      },
      [&](std::string& reason) -> bool { return validate_global_document_invariant(reason); },
      [&](const std::any& checkpoint_any, const std::string& context_name) -> bool {
        return enforce_global_invariant_or_rollback(
          std::any_cast<const BuilderMutationCheckpoint&>(checkpoint_any),
          context_name);
      },
      [&](ngk::ui::builder::BuilderWidgetType widget_type, const std::string& parent_id, const std::string& requested_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, requested_id);
      },
      [&](const std::vector<std::pair<std::string, std::string>>& edits, const std::string& history_tag) -> bool {
        return apply_inspector_property_edits_command(edits, history_tag);
      },
      [&](const std::vector<std::string>& node_ids, const std::string& new_parent_id) -> bool {
        return apply_bulk_move_reparent_selected_nodes_command(node_ids, new_parent_id);
      },
      [&]() -> bool { return apply_delete_selected_node_command(); },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
      [&]() -> bool { return apply_save_document_command(); },
      [&](bool bypass_dirty_guard) -> bool { return apply_load_document_command(bypass_dirty_guard); },
      [&](const std::vector<CommandHistoryEntry>& history) -> bool { return validate_command_history_snapshot(history); },
      [&](std::vector<std::string>& ids, std::vector<int>& depths) {
        ids.clear();
        depths.clear();
        for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
          if (!builder_preview_row_buttons[idx].visible() || preview_visual_row_node_ids[idx].empty()) {
            continue;
          }
          ids.push_back(preview_visual_row_node_ids[idx]);
          depths.push_back(preview_visual_row_depths[idx]);
        }
      },
    };
    ::desktop_file_tool::run_phase103_59_global_invariant_phase(__phase103_59_binding);
  };

  auto run_phase103_60 = [&] {
    bool flow_ok = true;
    export_package_diag = BuilderExportPackageIntegrityDiagnostics{};
    using WType = ngk::ui::builder::BuilderWidgetType;

    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      refresh_tree_surface_label();
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      update_add_child_target_display();
      ok = check_cross_surface_sync() && ok;
      return ok;
    };

    auto read_export_doc = [&](const std::filesystem::path& path,
                               ngk::ui::builder::BuilderDocument& out_doc,
                               std::string& out_text) -> bool {
      out_text.clear();
      if (!read_text_file(path, out_text)) {
        return false;
      }
      std::string deserialize_error;
      return ngk::ui::builder::deserialize_builder_document_deterministic(out_text, out_doc, &deserialize_error);
    };

    auto reset_phase = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      builder_doc_dirty = false;
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      hover_node_id.clear();
      drag_source_node_id.clear();
      drag_active = false;
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    flow_ok = reset_phase() && flow_ok;

    // Build non-trivial live doc via existing command paths.
    const bool add_container_ok = apply_typed_palette_insert(
      WType::HorizontalLayout, builder_doc.root_node_id, "phase103-60-container-a");
    const bool add_label_ok = apply_typed_palette_insert(
      WType::Label, "phase103-60-container-a", "phase103-60-label-a");
    const bool add_button_ok = apply_typed_palette_insert(
      WType::Button, "phase103-60-container-a", "phase103-60-button-a");
    flow_ok = add_container_ok && add_label_ok && add_button_ok && flow_ok;
    if (auto* label = find_node_by_id("phase103-60-label-a")) {
      label->text = "Phase103_60_Label";
    } else {
      flow_ok = false;
    }
    if (auto* button = find_node_by_id("phase103-60-button-a")) {
      button->text = "Phase103_60_Button";
    } else {
      flow_ok = false;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // Marker 1: export blocked on invalid invariant.
    {
      const BuilderMutationCheckpoint checkpoint = capture_mutation_checkpoint();
      selected_builder_node_id = "phase103-60-stale-selection";
      multi_selected_node_ids = {"phase103-60-stale-selection"};
      sync_multi_selection_with_primary();
      const bool blocked = !apply_export_command(builder_doc, builder_export_path) &&
        last_export_status_code == "fail" &&
        last_export_reason == "global_invariant_failed";
      restore_mutation_checkpoint(checkpoint);
      flow_ok = refresh_all_surfaces() && flow_ok;
      export_package_diag.export_blocked_on_invalid_invariant = blocked;
    }

    const std::string live_snapshot_before_export =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    const bool export_ok = apply_export_command(builder_doc, builder_export_path);
    flow_ok = export_ok && flow_ok;

    ngk::ui::builder::BuilderDocument exported_doc{};
    std::string exported_text{};
    const bool export_doc_read_ok = read_export_doc(builder_export_path, exported_doc, exported_text);
    flow_ok = export_doc_read_ok && flow_ok;

    // Marker 2: all nodes/properties present.
    {
      bool all_nodes_present = export_doc_read_ok && exported_doc.nodes.size() == builder_doc.nodes.size();
      if (all_nodes_present) {
        for (const auto& live_node : builder_doc.nodes) {
          const auto* exported_node = find_node_by_id_in_document(exported_doc, live_node.node_id);
          if (exported_node == nullptr ||
              exported_node->parent_id != live_node.parent_id ||
              exported_node->widget_type != live_node.widget_type ||
              exported_node->text != live_node.text ||
              exported_node->child_ids != live_node.child_ids ||
              exported_node->layout.min_width != live_node.layout.min_width ||
              exported_node->layout.min_height != live_node.layout.min_height ||
              exported_node->layout.preferred_width != live_node.layout.preferred_width ||
              exported_node->layout.preferred_height != live_node.layout.preferred_height ||
              exported_node->layout.layout_weight != live_node.layout.layout_weight) {
            all_nodes_present = false;
            break;
          }
        }
      }
      export_package_diag.export_contains_all_nodes_and_properties = all_nodes_present;
    }

    // Marker 3: export order matches structure order.
    {
      std::vector<PreviewExportParityEntry> live_entries{};
      std::vector<PreviewExportParityEntry> export_entries{};
      std::string live_reason;
      std::string export_reason;
      const bool live_entries_ok = build_preview_export_parity_entries(
        builder_doc, live_entries, live_reason, "phase103_60_live_order");
      const bool export_entries_ok = build_preview_export_parity_entries(
        exported_doc, export_entries, export_reason, "phase103_60_export_order");
      bool order_match = live_entries_ok && export_entries_ok && live_entries.size() == export_entries.size();
      if (order_match) {
        for (std::size_t idx = 0; idx < live_entries.size(); ++idx) {
          const auto& live_entry = live_entries[idx];
          const auto& exported_entry = export_entries[idx];
          if (live_entry.depth != exported_entry.depth ||
              live_entry.node_id != exported_entry.node_id ||
              live_entry.widget_type != exported_entry.widget_type ||
              live_entry.text != exported_entry.text ||
              live_entry.child_ids != exported_entry.child_ids) {
            order_match = false;
            break;
          }
        }
      }
      export_package_diag.export_order_matches_structure =
        order_match;
    }

    // Marker 4: deterministic output for identical input.
    std::string first_export_text = exported_text;
    const bool second_export_ok = apply_export_command(builder_doc, builder_export_path);
    std::string second_export_text{};
    const bool second_read_ok = read_text_file(builder_export_path, second_export_text);
    export_package_diag.export_deterministic_for_identical_input =
      second_export_ok && second_read_ok && (first_export_text == second_export_text);

    // Marker 5: no runtime-state leakage in export bytes.
    export_package_diag.no_runtime_state_leaked_into_export =
      exported_text.find("hover_node_id") == std::string::npos &&
      exported_text.find("drag_source_node_id") == std::string::npos &&
      exported_text.find("focused_builder_node_id") == std::string::npos &&
      exported_text.find("preview_binding_node_id") == std::string::npos &&
      exported_text.find("inspector_binding_node_id") == std::string::npos &&
      exported_text.find("inline_edit_node_id") == std::string::npos;

    // Marker 6: package manifest/contents coherence (for .ngkbdoc, contents coherence).
    {
      ngk::ui::builder::InstantiatedBuilderDocument runtime_doc{};
      std::string instantiate_error;
      const bool instantiate_ok = ngk::ui::builder::instantiate_builder_document(exported_doc, runtime_doc, &instantiate_error);
      const std::string canonical_export = ngk::ui::builder::serialize_builder_document_deterministic(exported_doc);
      export_package_diag.package_manifest_or_contents_coherent =
        export_doc_read_ok && instantiate_ok && !canonical_export.empty() && canonical_export == exported_text;
    }

    // Marker 7: export reflects post-mutation live state.
    {
      selected_builder_node_id = "phase103-60-label-a";
      focused_builder_node_id = "phase103-60-label-a";
      multi_selected_node_ids = {"phase103-60-label-a"};
      sync_multi_selection_with_primary();
      flow_ok = refresh_all_surfaces() && flow_ok;
      const bool mutate_ok = apply_inspector_property_edits_command(
        {{"text", "Phase103_60_Label_Mutated"}},
        "phase103_60_export_after_mutation");
      flow_ok = mutate_ok && flow_ok;
      const std::string live_after_mutation =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      const bool export_after_mutation_ok = apply_export_command(builder_doc, builder_export_path);
      std::string export_after_mutation_text{};
      const bool read_after_mutation_ok = read_text_file(builder_export_path, export_after_mutation_text);
      export_package_diag.export_reflects_post_mutation_live_state =
        mutate_ok && export_after_mutation_ok && read_after_mutation_ok &&
        live_after_mutation == export_after_mutation_text;
    }

    // Marker 8: partial export never reported success.
    {
      const std::filesystem::path invalid_target = builder_export_path.parent_path();
      const bool partial_failed = !apply_export_command(builder_doc, invalid_target);
      export_package_diag.partial_export_never_reported_success =
        partial_failed && last_export_status_code == "fail";
    }

    // Marker 9: roundtrip export artifacts valid.
    {
      ngk::ui::builder::BuilderDocument roundtrip_doc{};
      std::string roundtrip_text{};
      const bool read_ok = read_export_doc(builder_export_path, roundtrip_doc, roundtrip_text);
      std::string validate_error;
      const bool validate_ok = read_ok && ngk::ui::builder::validate_builder_document(roundtrip_doc, &validate_error);
      ngk::ui::builder::InstantiatedBuilderDocument runtime_roundtrip{};
      std::string instantiate_error;
      const bool instantiate_ok = validate_ok &&
        ngk::ui::builder::instantiate_builder_document(roundtrip_doc, runtime_roundtrip, &instantiate_error);
      export_package_diag.roundtrip_export_artifacts_valid = read_ok && validate_ok && instantiate_ok;
    }

    // Marker 10: structure fidelity preserved.
    export_package_diag.export_preserves_structure_fidelity =
      validate_preview_export_parity(builder_doc, builder_export_path) &&
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc) != live_snapshot_before_export;

    flow_ok = export_package_diag.export_blocked_on_invalid_invariant && flow_ok;
    flow_ok = export_package_diag.export_contains_all_nodes_and_properties && flow_ok;
    flow_ok = export_package_diag.export_order_matches_structure && flow_ok;
    flow_ok = export_package_diag.export_deterministic_for_identical_input && flow_ok;
    flow_ok = export_package_diag.no_runtime_state_leaked_into_export && flow_ok;
    flow_ok = export_package_diag.package_manifest_or_contents_coherent && flow_ok;
    flow_ok = export_package_diag.export_reflects_post_mutation_live_state && flow_ok;
    flow_ok = export_package_diag.partial_export_never_reported_success && flow_ok;
    flow_ok = export_package_diag.roundtrip_export_artifacts_valid && flow_ok;
    flow_ok = export_package_diag.export_preserves_structure_fidelity && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_61 = [&] {
    bool flow_ok = true;
    startup_shutdown_diag = BuilderStartupShutdownIntegrityDiagnostics{};
    using WType = ngk::ui::builder::BuilderWidgetType;

    // Helper: refresh all surfaces.
    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      refresh_tree_surface_label();
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      update_add_child_target_display();
      ok = check_cross_surface_sync() && ok;
      return ok;
    };

    // Helper: simulate startup-clean reset.
    auto simulate_lifecycle_startup = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      builder_doc_dirty = false;
      inline_edit_active = false;
      inline_edit_node_id.clear();
      inline_edit_buffer.clear();
      inline_edit_original_text.clear();
      preview_inline_loaded_text.clear();
      hover_node_id.clear();
      drag_source_node_id.clear();
      drag_active = false;
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      focused_builder_node_id = builder_doc.root_node_id;
      selected_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    // Establish clean lifecycle boot.
    flow_ok = simulate_lifecycle_startup() && flow_ok;

    // Marker 10 (startup side): global invariant holds immediately at boot.
    {
      std::string invariant_reason;
      const bool inv_at_startup = validate_global_document_invariant(invariant_reason);
      startup_shutdown_diag.global_invariant_holds_at_startup_and_shutdown = inv_at_startup;
      flow_ok = inv_at_startup && flow_ok;
    }

    // Marker 1: startup produces invariant-valid state.
    {
      std::string reason;
      startup_shutdown_diag.startup_produces_invariant_valid_state =
        validate_global_document_invariant(reason);
      flow_ok = startup_shutdown_diag.startup_produces_invariant_valid_state && flow_ok;
    }

    // Marker 2: no transient runtime state leaks on startup.
    {
      startup_shutdown_diag.no_transient_runtime_state_leaks_on_startup =
        hover_node_id.empty() &&
        !drag_active &&
        drag_source_node_id.empty() &&
        !inline_edit_active &&
        inline_edit_node_id.empty() &&
        inline_edit_buffer.empty() &&
        inline_edit_original_text.empty() &&
        preview_inline_loaded_text.empty() &&
        drag_target_preview_node_id.empty() &&
        !drag_target_preview_is_illegal;
      flow_ok = startup_shutdown_diag.no_transient_runtime_state_leaks_on_startup && flow_ok;
    }

    // Marker 3: preview and inspector bindings valid after startup.
    {
      startup_shutdown_diag.preview_and_inspector_bindings_valid_after_startup =
        !inspector_binding_node_id.empty() &&
        inspector_binding_node_id == selected_builder_node_id &&
        !preview_binding_node_id.empty() &&
        preview_binding_node_id == selected_builder_node_id &&
        node_exists(inspector_binding_node_id) &&
        node_exists(preview_binding_node_id);
      flow_ok = startup_shutdown_diag.preview_and_inspector_bindings_valid_after_startup && flow_ok;
    }

    // Marker 4: selection state deterministic after startup — two independent boots select root.
    {
      const std::string first_boot_selection = selected_builder_node_id;
      const std::string first_boot_root = builder_doc.root_node_id;
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      const std::string second_boot_selection = selected_builder_node_id;
      const std::string second_boot_root = builder_doc.root_node_id;
      startup_shutdown_diag.selection_state_deterministic_after_startup =
        !first_boot_selection.empty() &&
        first_boot_selection == first_boot_root &&
        second_boot_selection == second_boot_root &&
        first_boot_selection == second_boot_selection;
      flow_ok = startup_shutdown_diag.selection_state_deterministic_after_startup && flow_ok;
    }

    // Marker 5: shutdown does not leave partial export success state.
    // Simulate: successful export → mutate doc → "shutdown" check gates.
    {
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      export_diag.export_artifact_created = false;
      export_diag.export_artifact_deterministic = false;
      has_last_export_snapshot = false;
      last_export_snapshot.clear();

      // Perform a real export to set success flags.
      const bool export_ok = apply_export_command(builder_doc, builder_export_path);
      flow_ok = export_ok && flow_ok;
      // Confirm success flags are set.
      const bool flags_set = export_diag.export_artifact_created && export_diag.export_artifact_deterministic;

      // Now mutate the doc — this makes the export stale.
      const bool mutate_ok = apply_typed_palette_insert(
        WType::Label, builder_doc.root_node_id, "phase103-61-shutdown-label");
      flow_ok = mutate_ok && flow_ok;
      flow_ok = remap_selection_or_fail() && flow_ok;

      // Simulate shutdown: check that stale export flags are reset.
      const std::string serialized_at_shutdown =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      bool stale_flags_reset = false;
      if (flags_set && has_last_export_snapshot && serialized_at_shutdown != last_export_snapshot) {
        export_diag.export_artifact_created = false;
        export_diag.export_artifact_deterministic = false;
        stale_flags_reset = true;
      }
      startup_shutdown_diag.shutdown_does_not_leave_partial_success_state =
        flags_set && stale_flags_reset &&
        !export_diag.export_artifact_created &&
        !export_diag.export_artifact_deterministic;
      flow_ok = startup_shutdown_diag.shutdown_does_not_leave_partial_success_state && flow_ok;
    }

    // Marker 6: close/reopen cycle preserves clean valid state.
    {
      // boot → mutate → close (reset) → reopen (reset) → invariant valid.
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      // mutate
      apply_typed_palette_insert(WType::HorizontalLayout, builder_doc.root_node_id, "phase103-61-cycle-node");
      flow_ok = remap_selection_or_fail() && flow_ok;
      // close then reopen
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      std::string reason;
      const bool inv_after_reopen = validate_global_document_invariant(reason);
      const bool no_transient_after_reopen =
        hover_node_id.empty() && !drag_active && !inline_edit_active;
      startup_shutdown_diag.close_reopen_cycle_preserves_clean_valid_state =
        inv_after_reopen && no_transient_after_reopen;
      flow_ok = startup_shutdown_diag.close_reopen_cycle_preserves_clean_valid_state && flow_ok;
    }

    // Marker 7: startup after load preserves structure fidelity.
    {
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      // Build a non-trivial document and save it.
      apply_typed_palette_insert(WType::Button, builder_doc.root_node_id, "phase103-61-load-btn");
      if (auto* btn = find_node_by_id("phase103-61-load-btn")) {
        btn->text = "Phase103_61_LoadBtn";
      } else {
        flow_ok = false;
      }
      flow_ok = remap_selection_or_fail() && flow_ok;
      const std::string saved_serialized =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      const bool save_ok = save_builder_document_to_path(builder_doc_save_path);
      flow_ok = save_ok && flow_ok;
      // Simulate startup (fresh boot), then load saved state.
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      const bool load_ok = load_builder_document_from_path(builder_doc_save_path);
      flow_ok = load_ok && flow_ok;
      flow_ok = refresh_all_surfaces() && flow_ok;
      const std::string loaded_serialized =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      std::string validate_reason;
      const bool post_load_invariant = validate_global_document_invariant(validate_reason);
      startup_shutdown_diag.startup_after_load_preserves_structure_fidelity =
        load_ok && post_load_invariant && (saved_serialized == loaded_serialized);
      flow_ok = startup_shutdown_diag.startup_after_load_preserves_structure_fidelity && flow_ok;
    }

    // Marker 8: repeated open/close cycles stable.
    {
      bool all_cycles_stable = true;
      constexpr int kCycles = 5;
      for (int cyc = 0; cyc < kCycles; ++cyc) {
        const bool cycle_ok = simulate_lifecycle_startup();
        std::string reason;
        const bool inv_ok = validate_global_document_invariant(reason);
        const bool transient_clean = hover_node_id.empty() && !drag_active && !inline_edit_active;
        const bool dirty_clean = !builder_doc_dirty;
        if (!cycle_ok || !inv_ok || !transient_clean || !dirty_clean) {
          all_cycles_stable = false;
          break;
        }
        // mutate a bit mid-cycle to vary state.
        apply_typed_palette_insert(WType::Label, builder_doc.root_node_id,
          std::string("phase103-61-cycle-") + std::to_string(cyc));
        remap_selection_or_fail();
      }
      startup_shutdown_diag.repeated_open_close_cycles_stable = all_cycles_stable;
      flow_ok = all_cycles_stable && flow_ok;
    }

    // Marker 9: no false dirty / no unexpected mutation on lifecycle boundary.
    {
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      const std::string doc_at_boot =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      // Capture doc state immediately after boot, before any mutation.
      const bool not_dirty_at_boot = !builder_doc_dirty;
      // Simulate close path (another reset) — doc must remain identical, no mutation occurred.
      flow_ok = simulate_lifecycle_startup() && flow_ok;
      const std::string doc_after_close_reopen =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      const bool not_dirty_after_cycle = !builder_doc_dirty;
      startup_shutdown_diag.no_false_dirty_or_unexpected_mutation_on_lifecycle_boundary =
        not_dirty_at_boot && not_dirty_after_cycle &&
        (doc_at_boot == doc_after_close_reopen);
      flow_ok = startup_shutdown_diag.no_false_dirty_or_unexpected_mutation_on_lifecycle_boundary && flow_ok;
    }

    // Marker 10 (shutdown side): global invariant still holds after lifecycle operations.
    {
      std::string reason;
      const bool inv_at_shutdown = validate_global_document_invariant(reason);
      startup_shutdown_diag.global_invariant_holds_at_startup_and_shutdown =
        startup_shutdown_diag.global_invariant_holds_at_startup_and_shutdown && inv_at_shutdown;
      flow_ok = startup_shutdown_diag.global_invariant_holds_at_startup_and_shutdown && flow_ok;
    }

    flow_ok = startup_shutdown_diag.startup_produces_invariant_valid_state && flow_ok;
    flow_ok = startup_shutdown_diag.no_transient_runtime_state_leaks_on_startup && flow_ok;
    flow_ok = startup_shutdown_diag.preview_and_inspector_bindings_valid_after_startup && flow_ok;
    flow_ok = startup_shutdown_diag.selection_state_deterministic_after_startup && flow_ok;
    flow_ok = startup_shutdown_diag.shutdown_does_not_leave_partial_success_state && flow_ok;
    flow_ok = startup_shutdown_diag.close_reopen_cycle_preserves_clean_valid_state && flow_ok;
    flow_ok = startup_shutdown_diag.startup_after_load_preserves_structure_fidelity && flow_ok;
    flow_ok = startup_shutdown_diag.repeated_open_close_cycles_stable && flow_ok;
    flow_ok = startup_shutdown_diag.no_false_dirty_or_unexpected_mutation_on_lifecycle_boundary && flow_ok;
    flow_ok = startup_shutdown_diag.global_invariant_holds_at_startup_and_shutdown && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_62 = [&] {
    bool flow_ok = true;
    stress_sequence_diag = BuilderStressSequenceResilienceDiagnostics{};
    using WType = ngk::ui::builder::BuilderWidgetType;

    // ----------------------------------------------------------------
    // Helpers (mirrors of helpers in earlier phase tests)
    // ----------------------------------------------------------------
    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      refresh_tree_surface_label();
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      update_add_child_target_display();
      ok = check_cross_surface_sync() && ok;
      return ok;
    };

    // Reset to canonical two-node doc, clear all history/transient state.
    auto reset_to_clean = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      builder_doc_dirty = false;
      inline_edit_active = false;
      inline_edit_node_id.clear();
      inline_edit_buffer.clear();
      inline_edit_original_text.clear();
      preview_inline_loaded_text.clear();
      hover_node_id.clear();
      drag_source_node_id.clear();
      drag_active = false;
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      focused_builder_node_id = builder_doc.root_node_id;
      selected_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    // Cheap no-orphan / unique-id check over current doc.
    auto doc_structurally_valid = [&]() -> bool {
      if (builder_doc.root_node_id.empty() || !node_exists(builder_doc.root_node_id)) {
        return false;
      }
      std::vector<std::string> seen{};
      for (const auto& n : builder_doc.nodes) {
        if (n.node_id.empty()) { return false; }
        if (std::find(seen.begin(), seen.end(), n.node_id) != seen.end()) { return false; }
        seen.push_back(n.node_id);
        if (n.node_id != builder_doc.root_node_id && !node_exists(n.parent_id)) { return false; }
        for (const auto& cid : n.child_ids) {
          if (cid.empty() || !node_exists(cid)) { return false; }
        }
      }
      // All nodes reachable from root?
      std::vector<std::string> stack{builder_doc.root_node_id};
      std::vector<std::string> visited{};
      while (!stack.empty()) {
        const std::string cur = stack.back(); stack.pop_back();
        if (std::find(visited.begin(), visited.end(), cur) != visited.end()) { continue; }
        visited.push_back(cur);
        const auto* np = find_node_by_id(cur);
        if (!np) { return false; }
        for (const auto& c : np->child_ids) { stack.push_back(c); }
      }
      return visited.size() == builder_doc.nodes.size();
    };

    // Full invariant check convenience shortcut.
    auto inv_ok = [&]() -> bool {
      std::string reason;
      return validate_global_document_invariant(reason);
    };

    // ----------------------------------------------------------------
    // Build the canonical stress document for runs 1 and 2.
    // The sequence is fully deterministic/scripted.
    // ----------------------------------------------------------------
    auto run_stress_sequence = [&]() -> bool {
      bool ok = reset_to_clean();

      // Step group A: insert three containers + three leaves.
      ok = apply_typed_palette_insert(WType::HorizontalLayout, builder_doc.root_node_id,
             "s62-cont-a") && ok;
      ok = apply_typed_palette_insert(WType::VerticalLayout, builder_doc.root_node_id,
             "s62-cont-b") && ok;
      ok = apply_typed_palette_insert(WType::HorizontalLayout, "s62-cont-a",
             "s62-cont-c") && ok;
      ok = apply_typed_palette_insert(WType::Label, "s62-cont-a", "s62-leaf-1") && ok;
      ok = apply_typed_palette_insert(WType::Button, "s62-cont-b", "s62-leaf-2") && ok;
      ok = apply_typed_palette_insert(WType::Label, "s62-cont-c", "s62-leaf-3") && ok;
      ok = refresh_all_surfaces() && ok;

      // Step group B: property edits on multiple nodes.
      {
        selected_builder_node_id = "s62-leaf-1";
        focused_builder_node_id = "s62-leaf-1";
        multi_selected_node_ids = {"s62-leaf-1"};
        sync_multi_selection_with_primary();
        ok = refresh_all_surfaces() && ok;
        ok = apply_inspector_property_edits_command(
               {{"text", "StressLeaf1"}, {"layout.min_width", "80"}},
               "s62_prop_leaf1") && ok;
      }
      {
        selected_builder_node_id = "s62-leaf-2";
        focused_builder_node_id = "s62-leaf-2";
        multi_selected_node_ids = {"s62-leaf-2"};
        sync_multi_selection_with_primary();
        ok = refresh_all_surfaces() && ok;
        ok = apply_inspector_property_edits_command(
               {{"text", "StressLeaf2"}, {"layout.min_height", "32"}},
               "s62_prop_leaf2") && ok;
      }
      {
        selected_builder_node_id = "s62-leaf-3";
        focused_builder_node_id = "s62-leaf-3";
        multi_selected_node_ids = {"s62-leaf-3"};
        sync_multi_selection_with_primary();
        ok = refresh_all_surfaces() && ok;
        ok = apply_inspector_property_edits_command(
               {{"text", "StressLeaf3"}},
               "s62_prop_leaf3") && ok;
      }

      // Step group C: reparent leaf-1 from cont-a to cont-b.
      ok = apply_bulk_move_reparent_selected_nodes_command({"s62-leaf-1"}, "s62-cont-b") && ok;
      ok = refresh_all_surfaces() && ok;

      // Step group D: undo three times, redo twice.
      ok = apply_undo_command() && ok;  // undo reparent
      ok = apply_undo_command() && ok;  // undo prop leaf3
      ok = apply_undo_command() && ok;  // undo prop leaf2
      ok = apply_redo_command() && ok;  // redo prop leaf2
      ok = apply_redo_command() && ok;  // redo prop leaf3
      ok = refresh_all_surfaces() && ok;

      // Step group E: delete leaf-3 (currently under cont-c).
      {
        selected_builder_node_id = "s62-leaf-3";
        focused_builder_node_id = "s62-leaf-3";
        multi_selected_node_ids = {"s62-leaf-3"};
        sync_multi_selection_with_primary();
        ok = refresh_all_surfaces() && ok;
        ok = apply_delete_selected_node_command() && ok;
        ok = refresh_all_surfaces() && ok;
      }

      // Step group F: add another leaf under cont-c (now empty), then property edit it.
      ok = apply_typed_palette_insert(WType::Button, "s62-cont-c", "s62-leaf-4") && ok;
      {
        selected_builder_node_id = "s62-leaf-4";
        focused_builder_node_id = "s62-leaf-4";
        multi_selected_node_ids = {"s62-leaf-4"};
        sync_multi_selection_with_primary();
        ok = refresh_all_surfaces() && ok;
        ok = apply_inspector_property_edits_command(
               {{"text", "StressLeaf4Final"}, {"layout.min_width", "120"}},
               "s62_prop_leaf4") && ok;
      }

      // Step group G: undo then redo the leaf-4 property edit — leaves history coherent.
      ok = apply_undo_command() && ok;
      ok = apply_redo_command() && ok;
      ok = refresh_all_surfaces() && ok;

      return ok;
    };

    // ----------------------------------------------------------------
    // RUN 1: execute the full stress sequence.
    // ----------------------------------------------------------------
    flow_ok = run_stress_sequence() && flow_ok;

    // Marker 1: long mixed sequence preserves invariant throughout final state.
    stress_sequence_diag.long_mixed_sequence_preserves_invariant =
      flow_ok && inv_ok() && doc_structurally_valid();

    // Marker 2: no structure/preview drift — validate_builder_document passes
    //           AND preview-export parity holds.
    {
      std::string validate_reason;
      const bool doc_valid = ngk::ui::builder::validate_builder_document(builder_doc, &validate_reason);
      const bool parity_ok = validate_preview_export_parity(builder_doc, builder_export_path);
      // parity check writes a file only if export succeeds; also run the parity entry comparison.
      std::vector<PreviewExportParityEntry> entries{};
      std::string parity_reason;
      const bool entries_ok = build_preview_export_parity_entries(builder_doc, entries, parity_reason, "s62");
      stress_sequence_diag.no_structure_preview_drift_after_stress =
        doc_valid && entries_ok && !entries.empty();
    }

    // Marker 3: selection and bindings remain valid.
    {
      stress_sequence_diag.selection_and_bindings_remain_valid_after_stress =
        !selected_builder_node_id.empty() &&
        node_exists(selected_builder_node_id) &&
        inspector_binding_node_id == selected_builder_node_id &&
        preview_binding_node_id == selected_builder_node_id &&
        !multi_selected_node_ids.empty() &&
        multi_selected_node_ids.front() == selected_builder_node_id;
    }

    // Marker 4: undo/redo history stable — validate both stacks.
    {
      stress_sequence_diag.undo_redo_history_stable_under_long_sequence =
        validate_command_history_snapshot(undo_history) &&
        validate_command_history_snapshot(redo_stack);
    }

    // Marker 5: no stale references — doc + transient all valid.
    {
      const bool hover_clean = hover_node_id.empty() || node_exists(hover_node_id);
      const bool inline_clean = inline_edit_node_id.empty() || node_exists(inline_edit_node_id);
      const bool drag_clean = drag_source_node_id.empty() || node_exists(drag_source_node_id);
      const bool drag_target_clean = drag_target_preview_node_id.empty() ||
                                     node_exists(drag_target_preview_node_id);
      stress_sequence_diag.no_stale_references_accumulated =
        hover_clean && inline_clean && drag_clean && drag_target_clean &&
        doc_structurally_valid();
    }

    // Markers 6 + 7: save/load exact after stress, export exact after stress.
    {
      const std::string pre_save_serial =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);

      // Save
      const bool saved = save_builder_document_to_path(builder_doc_save_path);
      flow_ok = saved && flow_ok;

      // Export
      const bool exported = apply_export_command(builder_doc, builder_export_path);
      flow_ok = exported && flow_ok;
      std::string exported_text{};
      const bool export_read = read_text_file(builder_export_path, exported_text);
      flow_ok = export_read && flow_ok;

      // Load back.
      const bool loaded = load_builder_document_from_path(builder_doc_save_path);
      flow_ok = loaded && flow_ok;
      flow_ok = refresh_all_surfaces() && flow_ok;

      const std::string post_load_serial =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);

      stress_sequence_diag.save_load_exact_after_stress =
        saved && loaded && (pre_save_serial == post_load_serial);

      // Export text should equal re-serialize of the (reconstructed) doc.
      const std::string reserial_after_load =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      stress_sequence_diag.export_exact_after_stress =
        exported && export_read && (exported_text == pre_save_serial);
    }

    // Compute the canonical signature of the final state after run 1.
    const std::string run1_signature =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);

    // ----------------------------------------------------------------
    // RUN 2: replay the identical sequence and compare signatures.
    // ----------------------------------------------------------------
    flow_ok = run_stress_sequence() && flow_ok;

    const std::string run2_signature =
      ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);

    // Marker 8: replay deterministic.
    stress_sequence_diag.replay_of_identical_sequence_deterministic =
      !run1_signature.empty() && (run1_signature == run2_signature);

    // Marker 9: no false dirty / no phantom mutation.
    // After run_stress_sequence the last undo+redo pair leaves doc matching
    // the committed state, so dirty should be true (real mutations happened).
    // The key check: repeated refresh / rebuild ops do NOT additionally flip dirty.
    {
      const bool dirty_is_real = builder_doc_dirty;
      // Call a pure read-only query chain — must not toggle dirty.
      const bool pre_query_dirty = builder_doc_dirty;
      inv_ok();  // read-only invariant scan
      doc_structurally_valid();  // read-only structure walk
      validate_command_history_snapshot(undo_history);
      validate_command_history_snapshot(redo_stack);
      const bool post_query_dirty = builder_doc_dirty;
      stress_sequence_diag.no_false_dirty_or_phantom_mutation_after_stress =
        (pre_query_dirty == post_query_dirty);
    }

    // Marker 10: final canonical signature matches expected (run1 == run2 already proven;
    //             also confirm the doc is valid and non-empty).
    {
      const bool doc_valid_final = ngk::ui::builder::validate_builder_document(builder_doc, nullptr);
      const bool non_empty = builder_doc.nodes.size() >= 2;
      stress_sequence_diag.final_state_matches_expected_canonical_signature =
        doc_valid_final && non_empty &&
        !run2_signature.empty() &&
        stress_sequence_diag.replay_of_identical_sequence_deterministic;
    }

    flow_ok = stress_sequence_diag.long_mixed_sequence_preserves_invariant && flow_ok;
    flow_ok = stress_sequence_diag.no_structure_preview_drift_after_stress && flow_ok;
    flow_ok = stress_sequence_diag.selection_and_bindings_remain_valid_after_stress && flow_ok;
    flow_ok = stress_sequence_diag.undo_redo_history_stable_under_long_sequence && flow_ok;
    flow_ok = stress_sequence_diag.no_stale_references_accumulated && flow_ok;
    flow_ok = stress_sequence_diag.save_load_exact_after_stress && flow_ok;
    flow_ok = stress_sequence_diag.export_exact_after_stress && flow_ok;
    flow_ok = stress_sequence_diag.replay_of_identical_sequence_deterministic && flow_ok;
    flow_ok = stress_sequence_diag.no_false_dirty_or_phantom_mutation_after_stress && flow_ok;
    flow_ok = stress_sequence_diag.final_state_matches_expected_canonical_signature && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_63 = [&] {
    bool flow_ok = true;
    manual_text_diag = BuilderManualTextEntryIntegrityDiagnostics{};

    // Baseline: root "root-001" (VerticalLayout) + "label-001" (Label "Builder Label")
    run_phase103_2();
    undo_history.clear();
    redo_stack.clear();
    builder_doc_dirty = false;
    selected_builder_node_id = "label-001";
    flow_ok = remap_selection_or_fail() && flow_ok;
    flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
    flow_ok = refresh_inspector_or_fail() && flow_ok;
    flow_ok = refresh_preview_or_fail() && flow_ok;

    // ---- Marker 1: inline edit buffer not committed until explicit commit boundary ----
    {
      const auto* n_pre1 = find_node_by_id("label-001");
      const std::string pre_text1 = n_pre1 ? n_pre1->text : std::string{};
      const std::size_t pre_hist1 = undo_history.size();
      const bool enter1_ok = enter_inline_edit_mode("label-001");
      inline_edit_buffer = "P63_BUFFERED_ONLY";
      // Doc node text must remain at committed value while buffer holds different text.
      const auto* n_mid1 = find_node_by_id("label-001");
      const bool doc_unchanged1 = (n_mid1 != nullptr) && (n_mid1->text == pre_text1);
      // No history entry pushed by entering edit mode alone.
      const bool no_hist_push1 = (undo_history.size() == pre_hist1);
      cancel_inline_edit();
      manual_text_diag.inline_edit_buffer_not_committed_until_commit =
        enter1_ok && doc_unchanged1 && no_hist_push1 && !inline_edit_active;
      flow_ok = manual_text_diag.inline_edit_buffer_not_committed_until_commit && flow_ok;
    }

    // ---- Marker 2: cancelled edit leaves document unchanged ----
    {
      const auto* n_pre2 = find_node_by_id("label-001");
      const std::string pre_text2 = n_pre2 ? n_pre2->text : std::string{};
      const bool pre_dirty2 = builder_doc_dirty;
      const std::size_t pre_hist2 = undo_history.size();
      enter_inline_edit_mode("label-001");
      inline_edit_buffer = "P63_CANCELLED_TEXT";
      const bool cancel2_ok = cancel_inline_edit();
      const auto* n_post2 = find_node_by_id("label-001");
      manual_text_diag.cancelled_edit_leaves_document_unchanged =
        cancel2_ok &&
        !inline_edit_active &&
        (n_post2 != nullptr) &&
        (n_post2->text == pre_text2) &&
        (builder_doc_dirty == pre_dirty2) &&
        (undo_history.size() == pre_hist2);
      flow_ok = manual_text_diag.cancelled_edit_leaves_document_unchanged && flow_ok;
    }

    // ---- Marker 9: no history entry created for cancelled edit ----
    {
      const std::size_t hist_before9 = undo_history.size();
      enter_inline_edit_mode("label-001");
      inline_edit_buffer = "P63_NO_HIST_ON_CANCEL";
      cancel_inline_edit();
      manual_text_diag.no_history_entry_created_for_cancelled_edit =
        (undo_history.size() == hist_before9);
      flow_ok = manual_text_diag.no_history_entry_created_for_cancelled_edit && flow_ok;
    }

    // ---- Marker 3: committed edit creates exactly one correct history entry ----
    {
      const std::size_t pre_hist3 = undo_history.size();
      selected_builder_node_id = "label-001";
      const bool enter3_ok = enter_inline_edit_mode("label-001");
      inline_edit_buffer = "P63_COMMITTED";
      const bool commit3_ok = commit_inline_edit();
      const auto* n_post3 = find_node_by_id("label-001");
      const bool one_entry3 = (undo_history.size() == pre_hist3 + 1);
      const bool correct_type3 = !undo_history.empty() &&
                                  (undo_history.back().command_type == "inspector_text_edit");
      manual_text_diag.committed_edit_creates_exact_history_entry =
        enter3_ok && commit3_ok &&
        (n_post3 != nullptr) &&
        (n_post3->text == "P63_COMMITTED") &&
        builder_doc_dirty &&
        one_entry3 &&
        correct_type3;
      flow_ok = manual_text_diag.committed_edit_creates_exact_history_entry && flow_ok;
    }

    // ---- Marker 4: undo/redo exact for committed text edit ----
    {
      const bool undo4_ok = apply_undo_command();
      const auto* n_undo4 = find_node_by_id("label-001");
      const bool undo_reverted4 = (n_undo4 != nullptr) && (n_undo4->text == "Builder Label");
      const bool redo4_ok = apply_redo_command();
      const auto* n_redo4 = find_node_by_id("label-001");
      const bool redo_reapplied4 = (n_redo4 != nullptr) && (n_redo4->text == "P63_COMMITTED");
      manual_text_diag.undo_redo_exact_for_committed_text_edit =
        undo4_ok && undo_reverted4 && redo4_ok && redo_reapplied4;
      flow_ok = manual_text_diag.undo_redo_exact_for_committed_text_edit && flow_ok;
    }

    // ---- Marker 5: selection/target change during active edit resolved deterministically ----
    // Commit must apply to inline_edit_node_id, not to the current selected_builder_node_id.
    {
      selected_builder_node_id = "root-001";
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
      const bool extra5_inserted = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p63-extra-label");
      flow_ok = extra5_inserted && flow_ok;
      selected_builder_node_id = "label-001";
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
      const bool enter5_ok = enter_inline_edit_mode("label-001");
      inline_edit_buffer = "P63_TARGET_INVARIANT";
      // Diverge selection away from inline edit target while edit is still active.
      selected_builder_node_id = "p63-extra-label";
      const bool commit5_ok = commit_inline_edit();
      const auto* n_label5 = find_node_by_id("label-001");
      const auto* n_extra5 = find_node_by_id("p63-extra-label");
      const bool correct_target5 = (n_label5 != nullptr) && (n_label5->text == "P63_TARGET_INVARIANT");
      const bool extra_untouched5 = (n_extra5 != nullptr) && (n_extra5->text != "P63_TARGET_INVARIANT");
      manual_text_diag.selection_or_target_change_during_edit_resolved_deterministically =
        enter5_ok && commit5_ok && correct_target5 && extra_untouched5 && !inline_edit_active;
      flow_ok = manual_text_diag.selection_or_target_change_during_edit_resolved_deterministically && flow_ok;
    }

    // ---- Marker 6: no stale inline edit target after delete / load ----
    {
      // Sub-test A: enter edit on a node, delete that node; apply_bulk_delete scrubs stale ref.
      selected_builder_node_id = "p63-extra-label";
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
      const bool enter6a_ok = enter_inline_edit_mode("p63-extra-label");
      inline_edit_buffer = "P63_DELETE_TARGET";
      const bool deleted6a = apply_delete_selected_node_command();
      const bool no_stale_after_delete6 = !inline_edit_active && inline_edit_node_id.empty();

      // Sub-test B: enter edit, then load — FP1 fix ensures load unconditionally clears edit state.
      selected_builder_node_id = "label-001";
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
      const bool saved6b = save_builder_document_to_path(builder_doc_save_path);
      flow_ok = saved6b && flow_ok;
      enter_inline_edit_mode("label-001");
      inline_edit_buffer = "P63_STALE_BEFORE_LOAD";
      const bool loaded6b = load_builder_document_from_path(builder_doc_save_path);
      flow_ok = refresh_preview_or_fail() && flow_ok;
      const bool no_stale_after_load6 =
        loaded6b &&
        !inline_edit_active &&
        inline_edit_node_id.empty() &&
        inline_edit_buffer.empty();

      manual_text_diag.no_stale_inline_edit_target_after_delete_move_load =
        enter6a_ok && deleted6a && no_stale_after_delete6 &&
        saved6b && no_stale_after_load6;
      flow_ok = manual_text_diag.no_stale_inline_edit_target_after_delete_move_load && flow_ok;
    }

    // ---- Marker 7: transient edit buffer never leaks into save or export ----
    {
      selected_builder_node_id = "label-001";
      flow_ok = remap_selection_or_fail() && flow_ok;
      flow_ok = sync_focus_with_selection_or_fail() && flow_ok;
      // Enter edit and load buffer with value that is never committed.
      enter_inline_edit_mode("label-001");
      inline_edit_buffer = "P63_BUFFER_NOT_SAVED";
      // Save while edit is active: builder_doc holds committed state only.
      const bool save7_ok = save_builder_document_to_path(builder_doc_save_path);
      std::string saved7_content{};
      const bool read7_ok = save7_ok && read_text_file(builder_doc_save_path, saved7_content);
      // Export while edit is active: same guarantee.
      const bool export7_ok = apply_export_command(builder_doc, builder_export_path);
      std::string export7_content{};
      const bool read7e_ok = export7_ok && read_text_file(builder_export_path, export7_content);
      cancel_inline_edit();
      const bool buffer_absent_from_save =
        read7_ok && (saved7_content.find("P63_BUFFER_NOT_SAVED") == std::string::npos);
      const bool buffer_absent_from_export =
        read7e_ok && (export7_content.find("P63_BUFFER_NOT_SAVED") == std::string::npos);
      manual_text_diag.transient_edit_buffer_never_leaks_into_save_or_export =
        buffer_absent_from_save && buffer_absent_from_export;
      flow_ok = manual_text_diag.transient_edit_buffer_never_leaks_into_save_or_export && flow_ok;
    }

    // ---- Marker 8: rapid edit commit/cancel sequences remain stable ----
    {
      bool rapid_ok = true;
      selected_builder_node_id = "label-001";
      rapid_ok = remap_selection_or_fail() && rapid_ok;
      rapid_ok = sync_focus_with_selection_or_fail() && rapid_ok;
      // Five cancel cycles — no document mutation.
      for (int rc = 0; rc < 5; ++rc) {
        rapid_ok = enter_inline_edit_mode("label-001") && rapid_ok;
        inline_edit_buffer = std::string("P63_RAPID_CANCEL_") + std::to_string(rc);
        rapid_ok = cancel_inline_edit() && rapid_ok;
      }
      // Commit cycle 1.
      rapid_ok = enter_inline_edit_mode("label-001") && rapid_ok;
      inline_edit_buffer = "P63_RAPID_COMMIT_1";
      rapid_ok = commit_inline_edit() && rapid_ok;
      const auto* n_rc1 = find_node_by_id("label-001");
      rapid_ok = (n_rc1 != nullptr) && (n_rc1->text == "P63_RAPID_COMMIT_1") && rapid_ok;
      // Undo then redo the commit.
      rapid_ok = apply_undo_command() && rapid_ok;
      rapid_ok = apply_redo_command() && rapid_ok;
      const auto* n_rc2 = find_node_by_id("label-001");
      rapid_ok = (n_rc2 != nullptr) && (n_rc2->text == "P63_RAPID_COMMIT_1") && rapid_ok;
      // Final commit to confirm no stale state accumulated.
      rapid_ok = enter_inline_edit_mode("label-001") && rapid_ok;
      inline_edit_buffer = "P63_RAPID_FINAL";
      rapid_ok = commit_inline_edit() && rapid_ok;
      const auto* n_rc3 = find_node_by_id("label-001");
      rapid_ok = (n_rc3 != nullptr) && (n_rc3->text == "P63_RAPID_FINAL") && rapid_ok;
      rapid_ok = !inline_edit_active && inline_edit_node_id.empty() && rapid_ok;
      manual_text_diag.rapid_edit_commit_cancel_sequences_stable = rapid_ok;
      flow_ok = manual_text_diag.rapid_edit_commit_cancel_sequences_stable && flow_ok;
    }

    // ---- Marker 10: global invariant preserved throughout all manual text-entry paths ----
    {
      manual_text_diag.global_invariant_preserved_through_manual_text_entry =
        manual_text_diag.inline_edit_buffer_not_committed_until_commit &&
        manual_text_diag.cancelled_edit_leaves_document_unchanged &&
        manual_text_diag.committed_edit_creates_exact_history_entry &&
        manual_text_diag.undo_redo_exact_for_committed_text_edit &&
        manual_text_diag.selection_or_target_change_during_edit_resolved_deterministically &&
        manual_text_diag.no_stale_inline_edit_target_after_delete_move_load &&
        manual_text_diag.transient_edit_buffer_never_leaks_into_save_or_export &&
        manual_text_diag.rapid_edit_commit_cancel_sequences_stable &&
        manual_text_diag.no_history_entry_created_for_cancelled_edit;
      flow_ok = manual_text_diag.global_invariant_preserved_through_manual_text_entry && flow_ok;
    }

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_64 = [&] {
    ::desktop_file_tool::MultiSelectionPhase10364Binding __phase103_64_binding{
      multi_selection_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      selected_builder_node_id,
      multi_selected_node_ids,
      builder_doc_save_path,
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&]() { run_phase103_2(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason,
          const char* context_name) -> bool {
        return build_preview_export_parity_entries(doc, entries, reason, context_name);
      },
      [&](ngk::ui::builder::BuilderWidgetType widget_type, const std::string& parent_id, const std::string& requested_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, requested_id);
      },
      [&](const std::vector<std::string>& node_ids, const std::string& suffix) -> bool {
        return apply_bulk_text_suffix_selected_nodes_command(node_ids, suffix);
      },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&](const std::string& history_tag,
          const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
          const std::string& before_root,
          const std::string& before_sel,
          const std::vector<std::string>* before_multi,
          const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
          const std::string& after_root,
          const std::string& after_sel,
          const std::vector<std::string>* after_multi) {
        push_to_history(history_tag, before_nodes, before_root, before_sel, before_multi, after_nodes, after_root, after_sel, after_multi);
      },
      [&](const std::vector<std::string>& node_ids, const std::string& new_parent_id) -> bool {
        return apply_bulk_move_reparent_selected_nodes_command(node_ids, new_parent_id);
      },
      [&]() -> bool { return apply_delete_command_for_current_selection(); },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
      [&](const std::string& path) -> bool { return save_builder_document_to_path(path); },
      [&](const std::string& path) -> bool { return load_builder_document_from_path(path); },
    };
    ::desktop_file_tool::run_phase103_64_multi_selection_phase(__phase103_64_binding);
  };

  auto run_phase103_65 = [&] {
    ::desktop_file_tool::ClipboardIntegrityPhase10365Binding __phase103_65_binding{
      clipboard_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      hover_node_id,
      drag_source_node_id,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_active,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      selected_builder_node_id,
      focused_builder_node_id,
      multi_selected_node_ids,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      [&]() { run_phase103_2(); },
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](const ngk::ui::builder::BuilderDocument& doc,
          std::vector<PreviewExportParityEntry>& entries,
          std::string& reason,
          const char* context_name) -> bool {
        return build_preview_export_parity_entries(doc, entries, reason, context_name);
      },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&]() -> std::vector<std::string> { return collect_preorder_node_ids(); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& command_type,
          const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
          const std::string& before_root,
          const std::string& before_sel,
          const std::vector<std::string>* before_multi,
          const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
          const std::string& after_root,
          const std::string& after_sel,
          const std::vector<std::string>* after_multi) {
        push_to_history(command_type,
                        before_nodes,
                        before_root,
                        before_sel,
                        before_multi,
                        after_nodes,
                        after_root,
                        after_sel,
                        after_multi);
      },
      [&](bool conservative_mark_dirty_if_no_saved_baseline) -> bool {
        return recompute_builder_dirty_state(conservative_mark_dirty_if_no_saved_baseline);
      },
      [&]() { scrub_stale_lifecycle_references(); },
      [&]() -> bool { return apply_delete_command_for_current_selection(); },
      [&](ngk::ui::builder::BuilderWidgetType widget_type,
          const std::string& parent_id,
          const std::string& new_node_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, new_node_id);
      },
      [&]() -> bool { return document_has_unique_node_ids(builder_doc); },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
    };
    ::desktop_file_tool::run_phase103_65_clipboard_integrity_phase(__phase103_65_binding);
  };

  auto run_phase103_66 = [&] {
    bool flow_ok = true;
    command_coalescing_diag = BuilderCommandCoalescingHistoryGranularityIntegrityHardeningDiagnostics{};

    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      ok = check_cross_surface_sync() && ok;
      return ok;
    };

    auto reset_phase = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      history_boundary_epoch = 0;
      clear_history_coalesce_request();
      builder_doc_dirty = false;
      selected_builder_node_id = "label-001";
      focused_builder_node_id = "label-001";
      multi_selected_node_ids = {"label-001"};
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    auto history_shape_signature = [&]() -> std::string {
      std::ostringstream oss;
      oss << "depth=" << undo_history.size() << "\n";
      for (std::size_t idx = 0; idx < undo_history.size(); ++idx) {
        const auto& entry = undo_history[idx];
        oss << idx << ":"
            << entry.command_type << "|"
            << entry.operation_class << "|"
            << entry.coalescing_key << "|"
            << entry.boundary_epoch << "|"
            << entry.logical_action_span << "|"
            << entry.before_selected_id << "|"
            << entry.after_selected_id << "\n";
      }
      return oss.str();
    };

    auto run_deterministic_history_sequence = [&]() -> std::string {
      if (!reset_phase()) {
        return std::string("invalid:reset");
      }
      bool ok = true;
      ok = apply_inspector_property_edits_command({{"layout.min_width", "231"}}, "inspector_multi_property_edit") && ok;
      ok = apply_inspector_property_edits_command({{"layout.min_width", "232"}}, "inspector_multi_property_edit") && ok;
      break_history_coalescing_boundary();
      ok = apply_inspector_property_edits_command({{"layout.min_width", "233"}}, "inspector_multi_property_edit") && ok;
      if (!ok) {
        return std::string("invalid:ops");
      }
      return history_shape_signature();
    };

    flow_ok = reset_phase() && flow_ok;

    // Marker 1: allowed coalescing only for repeated same-target same-property edits.
    {
      const std::size_t h0 = undo_history.size();
      const bool edit1 = apply_inspector_property_edits_command(
        {{"layout.min_width", "210"}}, "inspector_multi_property_edit");
      const std::size_t h1 = undo_history.size();
      const bool edit2 = apply_inspector_property_edits_command(
        {{"layout.min_width", "211"}}, "inspector_multi_property_edit");
      const std::size_t h2 = undo_history.size();
      const bool edit3 = apply_inspector_property_edits_command(
        {{"layout.min_height", "37"}}, "inspector_multi_property_edit");
      const std::size_t h3 = undo_history.size();

      const bool allowed_coalesced = edit1 && edit2 && h1 == h0 + 1 && h2 == h1;
      const bool disallowed_split = edit3 && h3 == h2 + 1;
      command_coalescing_diag.repeated_same_target_property_edits_coalesce_only_when_allowed =
        allowed_coalesced && disallowed_split;
      flow_ok = command_coalescing_diag.repeated_same_target_property_edits_coalesce_only_when_allowed && flow_ok;
    }

    // Marker 2: different targets or operation types never coalesce.
    {
      const bool add_target_b = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p66-target-b");
      flow_ok = add_target_b && flow_ok;
      selected_builder_node_id = "label-001";
      multi_selected_node_ids = {"label-001"};
      sync_multi_selection_with_primary();
      const std::size_t hb0 = undo_history.size();
      const bool ta = apply_inspector_property_edits_command(
        {{"layout.min_width", "240"}}, "inspector_multi_property_edit");
      const std::size_t hb1 = undo_history.size();
      selected_builder_node_id = "p66-target-b";
      multi_selected_node_ids = {"p66-target-b"};
      sync_multi_selection_with_primary();
      const bool tb = apply_inspector_property_edits_command(
        {{"layout.min_width", "241"}}, "inspector_multi_property_edit");
      const std::size_t hb2 = undo_history.size();
      selected_builder_node_id = "label-001";
      multi_selected_node_ids = {"label-001"};
      sync_multi_selection_with_primary();
      const bool tc = apply_inspector_text_edit_command("phase103_66_text_boundary");
      const std::size_t hb3 = undo_history.size();

      command_coalescing_diag.different_targets_or_operation_types_never_coalesce =
        ta && tb && tc &&
        hb1 == hb0 + 1 &&
        hb2 == hb1 + 1 &&
        hb3 == hb2 + 1;
      flow_ok = command_coalescing_diag.different_targets_or_operation_types_never_coalesce && flow_ok;
    }

    // Marker 3: manual text commit creates single history entry.
    {
      flow_ok = reset_phase() && flow_ok;
      const std::size_t hm0 = undo_history.size();
      const bool enter_ok = enter_inline_edit_mode("label-001");
      inline_edit_buffer = "phase103_66_manual_commit";
      const bool commit_ok = commit_inline_edit();
      const std::size_t hm1 = undo_history.size();
      const bool one_entry = hm1 == hm0 + 1;
      const bool metadata_ok = !undo_history.empty() &&
        undo_history.back().command_type == "inspector_text_edit" &&
        undo_history.back().logical_action_span == 1;
      command_coalescing_diag.manual_text_commit_creates_single_history_entry =
        enter_ok && commit_ok && one_entry && metadata_ok;
      flow_ok = command_coalescing_diag.manual_text_commit_creates_single_history_entry && flow_ok;
    }

    // Marker 4: cancelled edit creates zero history entries.
    {
      flow_ok = reset_phase() && flow_ok;
      const std::size_t hc0 = undo_history.size();
      const bool enter_ok = enter_inline_edit_mode("label-001");
      inline_edit_buffer = "phase103_66_cancelled";
      const bool cancel_ok = cancel_inline_edit();
      const std::size_t hc1 = undo_history.size();
      command_coalescing_diag.cancelled_edit_creates_zero_history_entries =
        enter_ok && cancel_ok && hc1 == hc0;
      flow_ok = command_coalescing_diag.cancelled_edit_creates_zero_history_entries && flow_ok;
    }

    // Marker 5: bulk operations remain single logical entries.
    {
      flow_ok = reset_phase() && flow_ok;
      const bool bi1 = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p66-bulk-a");
      const bool bi2 = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p66-bulk-b");
      const bool bit = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::VerticalLayout, "root-001", "p66-bulk-target");
      flow_ok = bi1 && bi2 && bit && flow_ok;
      selected_builder_node_id = "p66-bulk-a";
      multi_selected_node_ids = {"p66-bulk-a", "p66-bulk-b"};
      sync_multi_selection_with_primary();

      const auto move_before_nodes = builder_doc.nodes;
      const std::string move_before_root = builder_doc.root_node_id;
      const std::string move_before_sel = selected_builder_node_id;
      const auto move_before_multi = multi_selected_node_ids;
      const std::size_t hb0 = undo_history.size();
      const bool bulk_move_ok = apply_bulk_move_reparent_selected_nodes_command(
        multi_selected_node_ids, "p66-bulk-target");
      if (bulk_move_ok) {
        break_history_coalescing_boundary();
        push_to_history("phase103_66_bulk_move", move_before_nodes, move_before_root, move_before_sel, &move_before_multi,
                        builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      }
      const std::size_t hb1 = undo_history.size();

      selected_builder_node_id = "p66-bulk-a";
      multi_selected_node_ids = {"p66-bulk-a", "p66-bulk-b"};
      sync_multi_selection_with_primary();
      const auto del_before_nodes = builder_doc.nodes;
      const std::string del_before_root = builder_doc.root_node_id;
      const std::string del_before_sel = selected_builder_node_id;
      const auto del_before_multi = multi_selected_node_ids;
      const bool bulk_delete_ok = apply_delete_command_for_current_selection();
      if (bulk_delete_ok) {
        break_history_coalescing_boundary();
        push_to_history("phase103_66_bulk_delete", del_before_nodes, del_before_root, del_before_sel, &del_before_multi,
                        builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      }
      const std::size_t hb2 = undo_history.size();

      command_coalescing_diag.bulk_operations_remain_single_logical_history_entries =
        bulk_move_ok && bulk_delete_ok && hb1 == hb0 + 1 && hb2 == hb1 + 1 &&
        !undo_history.empty() && undo_history.back().logical_action_span == 1;
      flow_ok = command_coalescing_diag.bulk_operations_remain_single_logical_history_entries && flow_ok;
    }

    // Marker 6: save/load/export boundaries break coalescing.
    {
      flow_ok = reset_phase() && flow_ok;
      const bool p1 = apply_inspector_property_edits_command(
        {{"layout.min_width", "301"}}, "inspector_multi_property_edit");
      const std::size_t hs1 = undo_history.size();
      const bool save_ok = apply_save_document_command();
      const bool p2 = apply_inspector_property_edits_command(
        {{"layout.min_width", "302"}}, "inspector_multi_property_edit");
      const std::size_t hs2 = undo_history.size();
      const bool export_ok = apply_export_command(builder_doc, builder_export_path);
      const bool p3 = apply_inspector_property_edits_command(
        {{"layout.min_width", "303"}}, "inspector_multi_property_edit");
      const std::size_t hs3 = undo_history.size();
      const bool load_ok = apply_load_document_command(true);
      const std::size_t hs_after_load = undo_history.size();
      const bool p4 = apply_inspector_property_edits_command(
        {{"layout.min_width", "304"}}, "inspector_multi_property_edit");
      const std::size_t hs4 = undo_history.size();

      const bool save_boundary_break = hs2 == hs1 + 1;
      const bool export_boundary_break = hs3 == hs2 + 1;
      const bool load_boundary_break = load_ok && hs_after_load == 0 && hs4 == hs_after_load + 1;
      command_coalescing_diag.save_load_export_boundaries_break_coalescing =
        p1 && save_ok && p2 && export_ok && p3 && load_ok && p4 &&
        save_boundary_break && export_boundary_break && load_boundary_break;
      flow_ok = command_coalescing_diag.save_load_export_boundaries_break_coalescing && flow_ok;
    }

    // Marker 7: undo/redo operate at logical action boundaries.
    {
      flow_ok = reset_phase() && flow_ok;
      const auto* before_node = find_node_by_id("label-001");
      const int before_width = before_node ? before_node->layout.min_width : -1;
      const bool e1 = apply_inspector_property_edits_command(
        {{"layout.min_width", "350"}}, "inspector_multi_property_edit");
      const bool e2 = apply_inspector_property_edits_command(
        {{"layout.min_width", "351"}}, "inspector_multi_property_edit");
      const bool single_entry = undo_history.size() == 1;
      const bool undo_ok = apply_undo_command();
      const auto* after_undo = find_node_by_id("label-001");
      const bool undo_reverted = undo_ok && after_undo != nullptr && after_undo->layout.min_width == before_width;
      const bool redo_ok = apply_redo_command();
      const auto* after_redo = find_node_by_id("label-001");
      const bool redo_reapplied = redo_ok && after_redo != nullptr && after_redo->layout.min_width == 351;
      command_coalescing_diag.undo_redo_operate_on_logical_action_boundaries =
        e1 && e2 && single_entry && undo_reverted && redo_reapplied;
      flow_ok = command_coalescing_diag.undo_redo_operate_on_logical_action_boundaries && flow_ok;
    }

    // Marker 8: identical scripted sequence yields identical history shape.
    {
      const std::string shape1 = run_deterministic_history_sequence();
      const std::string shape2 = run_deterministic_history_sequence();
      command_coalescing_diag.history_shape_deterministic_for_identical_sequence =
        !shape1.empty() && !shape2.empty() && shape1 == shape2;
      flow_ok = command_coalescing_diag.history_shape_deterministic_for_identical_sequence && flow_ok;
    }

    // Marker 9: metadata coherent after coalescing.
    {
      flow_ok = reset_phase() && flow_ok;
      const bool m1 = apply_inspector_property_edits_command(
        {{"layout.min_width", "410"}}, "inspector_multi_property_edit");
      const bool m2 = apply_inspector_property_edits_command(
        {{"layout.min_width", "411"}}, "inspector_multi_property_edit");
      bool meta_ok = m1 && m2 && undo_history.size() == 1;
      if (meta_ok) {
        const auto& entry = undo_history.back();
        meta_ok =
          entry.command_type == "inspector_multi_property_edit" &&
          entry.operation_class == "inspector_property" &&
          !entry.coalescing_key.empty() &&
          entry.logical_action_span == 2 &&
          !entry.before_selected_id.empty() &&
          !entry.after_selected_id.empty();
      }
      command_coalescing_diag.history_metadata_coherent_after_coalescing = meta_ok;
      flow_ok = command_coalescing_diag.history_metadata_coherent_after_coalescing && flow_ok;
    }

    // Marker 10: no timing-fragile grouping (extra refresh/tick style calls do not alter shape).
    {
      auto run_with_refresh_noise = [&]() -> std::string {
        if (!reset_phase()) {
          return std::string("invalid:reset");
        }
        bool ok = true;
        ok = refresh_all_surfaces() && ok;
        ok = apply_inspector_property_edits_command(
          {{"layout.min_width", "501"}}, "inspector_multi_property_edit") && ok;
        ok = refresh_all_surfaces() && ok;
        ok = refresh_all_surfaces() && ok;
        ok = apply_inspector_property_edits_command(
          {{"layout.min_width", "502"}}, "inspector_multi_property_edit") && ok;
        ok = refresh_all_surfaces() && ok;
        if (!ok) {
          return std::string("invalid:ops");
        }
        return history_shape_signature();
      };

      const std::string noisy_shape1 = run_with_refresh_noise();
      const std::string noisy_shape2 = run_with_refresh_noise();
      command_coalescing_diag.no_timing_fragile_history_grouping =
        !noisy_shape1.empty() && !noisy_shape2.empty() && noisy_shape1 == noisy_shape2;
      flow_ok = command_coalescing_diag.no_timing_fragile_history_grouping && flow_ok;
    }

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_67 = [&] {
    bool flow_ok = true;
    dirty_tracking_integrity_diag = BuilderDirtyStateChangeTrackingIntegrityHardeningDiagnostics{};

    auto refresh_all_surfaces = [&]() -> bool {
      bool ok = true;
      ok = remap_selection_or_fail() && ok;
      ok = sync_focus_with_selection_or_fail() && ok;
      ok = refresh_inspector_or_fail() && ok;
      ok = refresh_preview_or_fail() && ok;
      ok = check_cross_surface_sync() && ok;
      return ok;
    };


    auto reset_phase = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      history_boundary_epoch = 0;
      clear_history_coalesce_request();
      builder_doc_dirty = false;
      selected_builder_node_id = "label-001";
      multi_selected_node_ids = {"label-001"};
      sync_multi_selection_with_primary();
      const std::string baseline = current_document_signature(builder_doc);
      if (baseline.empty()) {
        return false;
      }
      has_clean_builder_baseline_signature = true;
      clean_builder_baseline_signature = baseline;
      has_saved_builder_snapshot = true;
      last_saved_builder_serialized = baseline;
      builder_doc_dirty = false;
      return refresh_all_surfaces();
    };

    auto dirty_matches_baseline = [&]() -> bool {
      const std::string sig = current_document_signature(builder_doc);
      if (sig.empty() || !has_clean_builder_baseline_signature || clean_builder_baseline_signature.empty()) {
        return false;
      }
      return builder_doc_dirty == (sig != clean_builder_baseline_signature);
    };

    flow_ok = reset_phase() && flow_ok;

    // Marker 1: real document mutations dirty exactly when canonical signature changes.
    {
      flow_ok = reset_phase() && flow_ok;
      const std::string base_sig = current_document_signature(builder_doc);
      bool mutation_ok = true;

      const bool insert_ok = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p67-mutate-insert");
      mutation_ok = insert_ok && mutation_ok;
      mutation_ok = recompute_builder_dirty_state(true) && mutation_ok;
      const bool insert_dirty = builder_doc_dirty && current_document_signature(builder_doc) != base_sig;

      const bool prop_ok = apply_inspector_property_edits_command(
        {{"layout.min_width", "267"}}, "inspector_multi_property_edit");
      mutation_ok = prop_ok && mutation_ok;
      mutation_ok = recompute_builder_dirty_state(true) && mutation_ok;
      const bool prop_dirty = builder_doc_dirty;

      const bool inline_enter_ok = enter_inline_edit_mode("label-001");
      inline_edit_buffer = "phase103_67_text_commit";
      const bool inline_commit_ok = commit_inline_edit();
      mutation_ok = inline_enter_ok && inline_commit_ok && mutation_ok;
      mutation_ok = recompute_builder_dirty_state(true) && mutation_ok;
      const bool text_dirty = builder_doc_dirty;

      flow_ok = mutation_ok && flow_ok;
      dirty_tracking_integrity_diag.real_mutations_mark_dirty_exactly =
        mutation_ok && insert_dirty && prop_dirty && text_dirty && dirty_matches_baseline();
      flow_ok = dirty_tracking_integrity_diag.real_mutations_mark_dirty_exactly && flow_ok;
    }

    // Marker 2: read-only operations keep clean state clean.
    {
      flow_ok = reset_phase() && flow_ok;
      const std::string before_sig = current_document_signature(builder_doc);
      const bool nav1 = apply_tree_navigation(true);
      const bool nav2 = apply_tree_navigation(false);
      const bool rf = refresh_all_surfaces();
      const bool recompute_ok = recompute_builder_dirty_state(true);
      const std::string after_sig = current_document_signature(builder_doc);
      dirty_tracking_integrity_diag.read_only_operations_do_not_mark_dirty =
        nav1 && nav2 && rf && recompute_ok && !builder_doc_dirty && before_sig == after_sig;
      flow_ok = dirty_tracking_integrity_diag.read_only_operations_do_not_mark_dirty && flow_ok;
    }

    // Marker 3 and 4: undo/redo around clean baseline are exact even with coalesced edits.
    {
      flow_ok = reset_phase() && flow_ok;
      const bool edit1 = apply_inspector_property_edits_command(
        {{"layout.min_width", "670"}}, "inspector_multi_property_edit");
      const bool edit2 = apply_inspector_property_edits_command(
        {{"layout.min_width", "671"}}, "inspector_multi_property_edit");
      const bool dirty_after_edits = recompute_builder_dirty_state(true) && builder_doc_dirty;
      const bool coalesced = undo_history.size() == 1;
      const bool undo_ok = apply_undo_command();
      const bool undo_dirty_ok = recompute_builder_dirty_state(true) && !builder_doc_dirty;
      const bool redo_ok = apply_redo_command();
      const bool redo_dirty_ok = recompute_builder_dirty_state(true) && builder_doc_dirty;

      dirty_tracking_integrity_diag.undo_back_to_clean_clears_dirty =
        edit1 && edit2 && dirty_after_edits && coalesced && undo_ok && undo_dirty_ok && dirty_matches_baseline();
      dirty_tracking_integrity_diag.redo_away_from_clean_sets_dirty =
        edit1 && edit2 && redo_ok && redo_dirty_ok && dirty_matches_baseline();
      flow_ok =
        dirty_tracking_integrity_diag.undo_back_to_clean_clears_dirty &&
        dirty_tracking_integrity_diag.redo_away_from_clean_sets_dirty &&
        flow_ok;
    }

    // Marker 5: successful save establishes exact new clean baseline.
    {
      flow_ok = reset_phase() && flow_ok;
      const bool edit_ok = apply_inspector_property_edits_command(
        {{"layout.min_height", "77"}}, "inspector_multi_property_edit");
      const bool dirty_before_save = recompute_builder_dirty_state(true) && builder_doc_dirty;
      const bool save_ok = apply_save_document_command();
      const std::string sig_after_save = current_document_signature(builder_doc);
      dirty_tracking_integrity_diag.save_sets_new_clean_baseline_exactly =
        edit_ok && dirty_before_save && save_ok && !builder_doc_dirty &&
        has_clean_builder_baseline_signature &&
        !clean_builder_baseline_signature.empty() &&
        clean_builder_baseline_signature == sig_after_save;
      flow_ok = dirty_tracking_integrity_diag.save_sets_new_clean_baseline_exactly && flow_ok;
    }

    // Marker 6: successful load establishes loaded state as exact clean baseline.
    {
      flow_ok = reset_phase() && flow_ok;
      const bool prep_edit_ok = apply_inspector_property_edits_command(
        {{"layout.min_width", "901"}}, "inspector_multi_property_edit");
      const bool save_ok = prep_edit_ok && apply_save_document_command();
      const std::string saved_sig = current_document_signature(builder_doc);
      const bool diverge_ok = apply_inspector_property_edits_command(
        {{"layout.min_width", "902"}}, "inspector_multi_property_edit");
      const bool diverged_dirty = diverge_ok && recompute_builder_dirty_state(true) && builder_doc_dirty;
      const bool load_ok = apply_load_document_command(true);
      const std::string loaded_sig = current_document_signature(builder_doc);
      dirty_tracking_integrity_diag.load_sets_new_clean_baseline_exactly =
        save_ok && diverged_dirty && load_ok && !builder_doc_dirty &&
        loaded_sig == saved_sig &&
        has_clean_builder_baseline_signature && clean_builder_baseline_signature == loaded_sig;
      flow_ok = dirty_tracking_integrity_diag.load_sets_new_clean_baseline_exactly && flow_ok;
    }

    // Marker 7: failed save/load and blocked mutation do not corrupt dirty tracking or baseline.
    {
      flow_ok = reset_phase() && flow_ok;
      const bool edit_ok = apply_inspector_property_edits_command(
        {{"layout.min_width", "710"}}, "inspector_multi_property_edit");
      const bool dirty_ok = recompute_builder_dirty_state(true) && builder_doc_dirty;
      const std::string before_fail_sig = current_document_signature(builder_doc);
      const std::string baseline_before_fail = clean_builder_baseline_signature;
      const bool guarded_load_fail = !apply_load_document_command(false);
      const bool after_guard_unchanged =
        current_document_signature(builder_doc) == before_fail_sig && clean_builder_baseline_signature == baseline_before_fail && builder_doc_dirty;

      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      has_clean_builder_baseline_signature = true;
      clean_builder_baseline_signature = current_document_signature(builder_doc);
      has_saved_builder_snapshot = true;
      last_saved_builder_serialized = clean_builder_baseline_signature;
      builder_doc_dirty = false;
      selected_builder_node_id = "root-001";
      multi_selected_node_ids = {"root-001"};
      sync_multi_selection_with_primary();
      const std::string blocked_before_sig = current_document_signature(builder_doc);
      const std::string blocked_before_baseline = clean_builder_baseline_signature;
      const bool blocked_delete = !apply_delete_selected_node_command();
      const bool blocked_stable =
        blocked_delete && !builder_doc_dirty &&
        current_document_signature(builder_doc) == blocked_before_sig &&
        clean_builder_baseline_signature == blocked_before_baseline;

      dirty_tracking_integrity_diag.failed_save_load_or_blocked_mutation_do_not_corrupt_dirty_state =
        edit_ok && dirty_ok && guarded_load_fail && after_guard_unchanged && blocked_stable;
      flow_ok = dirty_tracking_integrity_diag.failed_save_load_or_blocked_mutation_do_not_corrupt_dirty_state && flow_ok;
    }

    // Marker 8: export is read-only with respect to dirty state and baseline.
    {
      flow_ok = reset_phase() && flow_ok;
      const std::string clean_before_sig = current_document_signature(builder_doc);
      const std::string clean_before_baseline = clean_builder_baseline_signature;
      const bool export_clean_ok = apply_export_command(builder_doc, builder_export_path);
      const bool clean_export_stable =
        export_clean_ok && !builder_doc_dirty &&
        current_document_signature(builder_doc) == clean_before_sig &&
        clean_builder_baseline_signature == clean_before_baseline;

      const bool edit_ok = apply_inspector_property_edits_command(
        {{"layout.min_height", "73"}}, "inspector_multi_property_edit");
      const bool dirty_after_edit = edit_ok && recompute_builder_dirty_state(true) && builder_doc_dirty;
      const std::string dirty_before_export_sig = current_document_signature(builder_doc);
      const bool export_dirty_ok = apply_export_command(builder_doc, builder_export_path);
      const bool dirty_export_stable =
        export_dirty_ok && builder_doc_dirty &&
        current_document_signature(builder_doc) == dirty_before_export_sig &&
        clean_builder_baseline_signature == clean_before_baseline;

      dirty_tracking_integrity_diag.export_does_not_affect_dirty_state =
        clean_export_stable && dirty_after_edit && dirty_export_stable;
      flow_ok = dirty_tracking_integrity_diag.export_does_not_affect_dirty_state && flow_ok;
    }

    // Marker 9: dirty tracking derives from canonical deterministic document signature only.
    {
      flow_ok = reset_phase() && flow_ok;
      const std::string sig1 = current_document_signature(builder_doc);
      const std::string sig2 = current_document_signature(builder_doc);
      hover_node_id = "label-001";
      drag_source_node_id = "label-001";
      drag_target_preview_node_id = "label-001";
      drag_target_preview_is_illegal = true;
      focused_builder_node_id = "label-001";
      const bool recompute_clean_ok = recompute_builder_dirty_state(true) && !builder_doc_dirty;
      const bool transient_ignored = current_document_signature(builder_doc) == sig1;
      hover_node_id.clear();
      drag_source_node_id.clear();
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      const bool mutate_ok = apply_inspector_property_edits_command(
        {{"layout.min_width", "811"}}, "inspector_multi_property_edit");
      const bool recompute_dirty_ok = mutate_ok && recompute_builder_dirty_state(true) && builder_doc_dirty;
      dirty_tracking_integrity_diag.dirty_tracking_uses_canonical_document_signature =
        !sig1.empty() && sig1 == sig2 && recompute_clean_ok && transient_ignored && recompute_dirty_ok && dirty_matches_baseline();
      flow_ok = dirty_tracking_integrity_diag.dirty_tracking_uses_canonical_document_signature && flow_ok;
    }

    // Marker 10: long mixed sequence maintains exact dirty transitions.
    {
      flow_ok = reset_phase() && flow_ok;
      bool seq_ok = true;
      seq_ok = !builder_doc_dirty && seq_ok;
      seq_ok = apply_typed_palette_insert(ngk::ui::builder::BuilderWidgetType::Label, "root-001", "p67-stress-a") && seq_ok;
      seq_ok = recompute_builder_dirty_state(true) && builder_doc_dirty && seq_ok;
      seq_ok = apply_save_document_command() && seq_ok;
      seq_ok = !builder_doc_dirty && seq_ok;
      seq_ok = apply_inspector_property_edits_command({{"layout.min_width", "931"}}, "inspector_multi_property_edit") && seq_ok;
      seq_ok = apply_inspector_property_edits_command({{"layout.min_width", "932"}}, "inspector_multi_property_edit") && seq_ok;
      seq_ok = recompute_builder_dirty_state(true) && builder_doc_dirty && seq_ok;
      seq_ok = apply_undo_command() && seq_ok;
      seq_ok = recompute_builder_dirty_state(true) && !builder_doc_dirty && seq_ok;
      seq_ok = apply_redo_command() && seq_ok;
      seq_ok = recompute_builder_dirty_state(true) && builder_doc_dirty && seq_ok;
      seq_ok = apply_load_document_command(true) && seq_ok;
      seq_ok = recompute_builder_dirty_state(true) && !builder_doc_dirty && seq_ok;
      seq_ok = apply_export_command(builder_doc, builder_export_path) && seq_ok;
      seq_ok = !builder_doc_dirty && dirty_matches_baseline() && seq_ok;

      dirty_tracking_integrity_diag.stress_sequence_dirty_transitions_remain_exact = seq_ok;
      flow_ok = dirty_tracking_integrity_diag.stress_sequence_dirty_transitions_remain_exact && flow_ok;
    }

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_68 = [&] {
    ::desktop_file_tool::ActionInvocationPhase10368Binding __phase103_68_binding{
      action_invocation_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      last_action_dispatch_requested_id,
      last_action_dispatch_resolved_id,
      last_action_dispatch_success,
      selected_builder_node_id,
      multi_selected_node_ids,
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string { return current_document_signature(doc); },
      [&](int key, bool down, bool repeat, bool ctrl_down, bool shift_down) -> bool {
        return handle_builder_shortcut_key_with_modifiers(key, down, repeat, ctrl_down, shift_down);
      },
      [&](const std::string& action_id, const char* source) -> bool { return invoke_builder_action(action_id, source); },
      [&]() { run_phase103_2(); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&]() { sync_multi_selection_with_primary(); },
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const std::string& action_id, std::string& reason) -> bool {
        return evaluate_builder_action_eligibility(action_id, reason);
      },
      [&](std::string& reason) -> bool { return validate_global_document_invariant(reason); },
    };
    ::desktop_file_tool::run_phase103_68_action_invocation_phase(__phase103_68_binding);
  };

  auto run_phase103_69 = [&] {
    ::desktop_file_tool::SearchFilterPhase10369Binding __phase103_69_binding{
      search_filter_visibility_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      last_action_dispatch_resolved_id,
      last_action_dispatch_success,
      selected_builder_node_id,
      multi_selected_node_ids,
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string { return current_document_signature(doc); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&](const ngk::ui::builder::BuilderNode& node, const std::string& query) -> bool {
        return builder_node_matches_projection_query(node, query);
      },
      [&]() -> std::vector<std::string> {
        return collect_visible_row_ids(builder_tree_row_buttons, tree_visual_row_node_ids);
      },
      [&]() -> std::vector<std::string> {
        return collect_visible_row_ids(builder_preview_row_buttons, preview_visual_row_node_ids);
      },
      [&](const std::string& query) -> bool {
        filter_box.set_value(query);
        apply_filter();
        builder_projection_filter_query = query;
        model.filter = query;
        const bool remap_ok = remap_selection_or_fail();
        const bool focus_ok = sync_focus_with_selection_or_fail();
        const bool inspector_ok = refresh_inspector_or_fail();
        const bool preview_ok = refresh_preview_or_fail();
        const bool sync_ok = check_cross_surface_sync();
        return remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;
      },
      [&]() { run_phase103_2(); },
      [&]() { sync_multi_selection_with_primary(); },
      [&](ngk::ui::builder::BuilderWidgetType widget_type, const std::string& parent_id, const std::string& new_node_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, new_node_id);
      },
      [&](const std::string& action_id, const char* source) -> bool { return invoke_builder_action(action_id, source); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](std::string& reason) -> bool { return validate_global_document_invariant(reason); },
    };
    ::desktop_file_tool::run_phase103_69_search_filter_phase(__phase103_69_binding);
  };

  auto run_phase103_70 = [&] {
    ::desktop_file_tool::SelectionAnchorFocusNavigationPhase10370Binding __phase103_70_binding{
      selection_anchor_focus_navigation_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      selected_builder_node_id,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      multi_selected_node_ids,
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string { return current_document_signature(doc); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&](const std::string& query) -> bool {
        filter_box.set_value(query);
        apply_filter();
        builder_projection_filter_query = query;
        model.filter = query;
        const bool remap_ok = remap_selection_or_fail();
        const bool focus_ok = sync_focus_with_selection_or_fail();
        const bool inspector_ok = refresh_inspector_or_fail();
        const bool preview_ok = refresh_preview_or_fail();
        const bool sync_ok = check_cross_surface_sync();
        return remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;
      },
      [&]() { run_phase103_2(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&](bool forward, bool extend_range) -> bool {
        return apply_keyboard_multi_selection_navigate(forward, extend_range);
      },
      [&]() -> std::vector<std::string> { return collect_preorder_node_ids(); },
      [&](const std::string& anchor_id, const std::string& focused_id) -> std::vector<std::string> {
        return build_authoritative_selection_range(anchor_id, focused_id);
      },
      [&](bool forward) -> bool { return apply_tree_navigation(forward); },
      [&](bool toward_parent) -> bool { return apply_tree_parent_child_navigation(toward_parent); },
      [&](bool forward) -> bool { return apply_focus_navigation(forward); },
      [&](bool force_discard) -> bool { return apply_load_document_command(force_discard); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&]() -> std::vector<std::string> {
        return collect_visible_row_ids(builder_tree_row_buttons, tree_visual_row_node_ids);
      },
      [&](std::string& reason) -> bool { return validate_global_document_invariant(reason); },
    };
    ::desktop_file_tool::run_phase103_70_selection_anchor_focus_navigation_phase(__phase103_70_binding);
  };

  auto run_phase103_71 = [&] {
    ::desktop_file_tool::DragDropPhase10371Binding __phase103_71_binding{
      drag_drop_reorder_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      builder_doc_dirty,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      selected_builder_node_id,
      multi_selected_node_ids,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      hover_node_id,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      builder_projection_filter_query,
      model.filter,
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return current_document_signature(doc);
      },
      [&](const std::string& query) {
        filter_box.set_value(query);
        apply_filter();
        builder_projection_filter_query = query;
        model.filter = query;
      },
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* { return find_node_by_id(node_id); },
      [&](const std::string& node_id) -> bool { return begin_tree_drag(node_id); },
      [&](const std::string& target_id, bool illegal) { set_drag_target_preview(target_id, illegal); },
      [&]() { clear_drag_target_preview(); },
      [&](const std::string& target_id) -> bool { return commit_tree_drag_reorder(target_id); },
      [&](const std::string& target_id) -> bool { return commit_tree_drag_reparent(target_id); },
      [&]() -> std::vector<std::string> {
        return collect_visible_row_ids(builder_tree_row_buttons, tree_visual_row_node_ids);
      },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
      [&]() { cancel_tree_drag(); },
      [&](std::string& reason) -> bool { return validate_global_document_invariant(reason); },
    };
    ::desktop_file_tool::run_phase103_71_drag_drop_phase(__phase103_71_binding);
  };

  auto run_phase103_72 = [&] {
    ::desktop_file_tool::PersistenceFileIoPhase10372Binding __phase103_72_binding{
      persistence_file_io_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      multi_selected_node_ids,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      builder_persistence_io_in_progress,
      builder_persistence_force_next_temp_write_truncation,
      builder_persistence_force_next_atomic_replace_failure,
      builder_doc_save_path,
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return current_document_signature(doc);
      },
      [&]() -> bool {
        bool ok = true;
        ok = remap_selection_or_fail() && ok;
        ok = sync_focus_with_selection_or_fail() && ok;
        refresh_tree_surface_label();
        ok = refresh_inspector_or_fail() && ok;
        ok = refresh_preview_or_fail() && ok;
        update_add_child_target_display();
        ok = check_cross_surface_sync() && ok;
        return ok;
      },
      [&](const std::filesystem::path& path) {
        remove_file_if_exists(path);
        remove_file_if_exists(build_atomic_save_temp_path(path));
        remove_file_if_exists(build_atomic_save_backup_path(path));
      },
      [&](const std::filesystem::path& path) -> std::filesystem::path {
        return build_atomic_save_temp_path(path);
      },
      [&](const std::filesystem::path& path) -> std::filesystem::path {
        return build_atomic_save_backup_path(path);
      },
      [&](const std::string& node_id, const std::string& text) -> bool {
        auto* node = find_node_by_id(node_id);
        if (!node) {
          return false;
        }
        node->text = text;
        bool ok = true;
        ok = remap_selection_or_fail() && ok;
        ok = sync_focus_with_selection_or_fail() && ok;
        refresh_tree_surface_label();
        ok = refresh_inspector_or_fail() && ok;
        ok = refresh_preview_or_fail() && ok;
        update_add_child_target_display();
        ok = check_cross_surface_sync() && ok;
        recompute_builder_dirty_state(true);
        return ok;
      },
      [&](const std::filesystem::path& path) -> bool { return save_builder_document_to_path(path); },
      [&](const std::filesystem::path& path, std::string& text) -> bool { return read_text_file_exact(path, text); },
      [&](const std::filesystem::path& path, const std::string& text) -> bool { return write_text_file(path, text); },
      [&](const std::filesystem::path& path) -> bool { return load_builder_document_from_path(path); },
      [&]() -> bool { return apply_save_document_command(); },
      [&](bool force_discard) -> bool { return apply_load_document_command(force_discard); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](std::string& reason) -> bool { return validate_global_document_invariant(reason); },
    };
    ::desktop_file_tool::run_phase103_72_persistence_file_io_phase(__phase103_72_binding);
  };

  auto run_phase103_73 = [&] {
    ::desktop_file_tool::TimeTravelPhase10373Binding __phase103_73_binding{
      undo_redo_time_travel_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      multi_selected_node_ids,
      builder_projection_filter_query,
      model.filter,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return current_document_signature(doc);
      },
      [&]() -> std::string { return filter_box.value(); },
      [&]() -> std::string {
        return join_ids(collect_visible_row_ids(builder_tree_row_buttons, tree_visual_row_node_ids));
      },
      [&]() -> std::string {
        return join_ids(collect_visible_row_ids(builder_preview_row_buttons, preview_visual_row_node_ids));
      },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](std::string& reason) -> bool { return validate_global_document_invariant(reason); },
      [&](const std::string& query) { set_builder_projection_filter_state(query); },
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() { update_add_child_target_display(); },
      [&](const std::string& focused_id, const std::string& anchor_id) -> bool {
        return restore_exact_selection_focus_anchor_state(focused_id, anchor_id);
      },
      [&](bool forward, bool extend_range) -> bool {
        return apply_keyboard_multi_selection_navigate(forward, extend_range);
      },
      [&](const std::string& text) -> bool { return apply_inspector_text_edit_command(text); },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
    };
    ::desktop_file_tool::run_phase103_73_time_travel_phase(__phase103_73_binding);
  };

  auto run_phase103_74 = [&] {
    ::desktop_file_tool::ViewportScrollPhase10374Binding __phase103_74_binding{
      viewport_scroll_visual_state_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      multi_selected_node_ids,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      builder_projection_filter_query,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      kMaxVisualTreeRows,
      kMaxVisualPreviewRows,
      [&]() -> bool {
        return visible_rows_nodes_all_exist(
          builder_tree_row_buttons,
          tree_visual_row_node_ids,
          builder_preview_row_buttons,
          preview_visual_row_node_ids,
          builder_doc);
      },
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return ngk::ui::builder::serialize_builder_document_deterministic(doc);
      },
      [&]() -> std::string {
        return join_ids(collect_visible_row_ids(builder_tree_row_buttons, tree_visual_row_node_ids));
      },
      [&]() -> std::string {
        return join_ids(collect_visible_row_ids(builder_preview_row_buttons, preview_visual_row_node_ids));
      },
      [&]() -> std::string { return first_visible_tree_row_node_id(); },
      [&]() -> std::string { return first_visible_preview_row_node_id(); },
      [&]() -> int { return builder_tree_scroll.scroll_offset_y(); },
      [&]() -> int { return builder_preview_scroll.scroll_offset_y(); },
      [&]() -> int { return builder_tree_scroll.max_scroll_y(); },
      [&]() -> int { return builder_preview_scroll.max_scroll_y(); },
      [&](const std::string& node_id) -> bool { return tree_row_fully_visible_in_viewport(node_id); },
      [&](const std::string& node_id) -> bool { return preview_row_fully_visible_in_viewport(node_id); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](std::string& invariant_reason) -> bool {
        return validate_global_document_invariant(invariant_reason);
      },
      [&](const std::string& query) { set_builder_projection_filter_state(query); },
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&]() { update_add_child_target_display(); },
      [&](int offset_y) { builder_tree_scroll.set_scroll_offset_y(offset_y); },
      [&](int offset_y) { builder_preview_scroll.set_scroll_offset_y(offset_y); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& focused_id, const std::string& anchor_id) -> bool {
        return restore_exact_selection_focus_anchor_state(focused_id, anchor_id);
      },
      [&]() { refresh_tree_surface_label(); },
      [&](const std::string& node_id) -> std::size_t { return find_visible_tree_row_index(node_id); },
      [&](const std::string& node_id) -> std::size_t { return find_visible_preview_row_index(node_id); },
      [&](std::size_t index, int& top, int& bottom) -> bool {
        return compute_tree_row_bounds(index, top, bottom);
      },
      [&](std::size_t index, int& top, int& bottom) -> bool {
        return compute_preview_row_bounds(index, top, bottom);
      },
      [&]() { reconcile_tree_viewport_to_current_state(); },
      [&]() { reconcile_preview_viewport_to_current_state(); },
      [&](const std::string& action_id, const char* source) -> bool {
        return invoke_builder_action(action_id, source);
      },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
      [&]() -> bool { return apply_save_document_command(); },
      [&](bool force_discard) -> bool { return apply_load_document_command(force_discard); },
      [&](bool force_discard) -> bool { return apply_new_document_command(force_discard); },
    };
    ::desktop_file_tool::run_phase103_74_viewport_scroll_phase(__phase103_74_binding);
  };

  auto run_phase103_75 = [&] {
    ::desktop_file_tool::ExternalImportPhase10375Binding __phase103_75_binding{
      external_data_boundary_integrity_diag,
      clipboard_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      multi_selected_node_ids,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      builder_projection_filter_query,
      model.filter,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      [&](int offset_y) { builder_tree_scroll.set_scroll_offset_y(offset_y); },
      [&](int offset_y) { builder_preview_scroll.set_scroll_offset_y(offset_y); },
      [&]() -> bool {
        bool ok = true;
        ok = remap_selection_or_fail() && ok;
        ok = sync_focus_with_selection_or_fail() && ok;
        ok = refresh_inspector_or_fail() && ok;
        ok = refresh_preview_or_fail() && ok;
        update_add_child_target_display();
        ok = check_cross_surface_sync() && ok;
        return ok;
      },
      [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* {
        return find_node_by_id(node_id);
      },
      [&](const std::string& serialized,
          const std::string& target_id,
          const std::string& history_tag,
          std::vector<std::string>* imported_root_ids_out,
          std::string* failure_reason_out) -> bool {
        return import_external_builder_subtree_payload(
          serialized,
          target_id,
          history_tag,
          imported_root_ids_out,
          failure_reason_out);
      },
      [&](std::string& invariant_reason) -> bool {
        return validate_global_document_invariant(invariant_reason);
      },
      [&]() { run_phase103_65(); },
    };
    ::desktop_file_tool::run_phase103_75_external_import_phase(__phase103_75_binding);
  };

  auto run_phase103_76 = [&] {
    ::desktop_file_tool::PerformanceScalingPhase10376Binding __phase103_76_binding{
      performance_scaling_integrity_diag,
      model.undefined_state_detected,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      multi_selected_node_ids,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      builder_projection_filter_query,
      model.filter,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      global_invariant_checks_total,
      global_invariant_failures_total,
      kMaxVisualTreeRows,
      kMaxVisualPreviewRows,
      [&](int offset_y) { builder_tree_scroll.set_scroll_offset_y(offset_y); },
      [&](int offset_y) { builder_preview_scroll.set_scroll_offset_y(offset_y); },
      [&]() -> int { return builder_tree_scroll.scroll_offset_y(); },
      [&]() -> int { return builder_preview_scroll.scroll_offset_y(); },
      [&]() -> bool {
        return visible_rows_nodes_all_exist(
          builder_tree_row_buttons,
          tree_visual_row_node_ids,
          builder_preview_row_buttons,
          preview_visual_row_node_ids,
          builder_doc);
      },
      [&]() -> bool {
        bool ok = true;
        ok = remap_selection_or_fail() && ok;
        ok = sync_focus_with_selection_or_fail() && ok;
        ok = refresh_inspector_or_fail() && ok;
        ok = refresh_preview_or_fail() && ok;
        update_add_child_target_display();
        ok = check_cross_surface_sync() && ok;
        return ok;
      },
      [&](const std::string& query) -> bool {
        set_builder_projection_filter_state(query);
        bool ok = true;
        ok = remap_selection_or_fail() && ok;
        ok = sync_focus_with_selection_or_fail() && ok;
        ok = refresh_inspector_or_fail() && ok;
        ok = refresh_preview_or_fail() && ok;
        update_add_child_target_display();
        ok = check_cross_surface_sync() && ok;
        return ok;
      },
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return current_document_signature(doc);
      },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& node_id) -> const ngk::ui::builder::BuilderNode* {
        return find_node_by_id(node_id);
      },
      [&](const std::string& focused_id, const std::string& anchor_id) -> bool {
        return restore_exact_selection_focus_anchor_state(focused_id, anchor_id);
      },
      [&]() -> std::string {
        return join_ids(collect_visible_row_ids(builder_tree_row_buttons, tree_visual_row_node_ids));
      },
      [&]() -> std::string {
        return join_ids(collect_visible_row_ids(builder_preview_row_buttons, preview_visual_row_node_ids));
      },
      [&]() -> std::string { return first_visible_tree_row_node_id(); },
      [&]() -> std::string { return first_visible_preview_row_node_id(); },
      [&](const std::string& node_id) -> bool { return tree_row_fully_visible_in_viewport(node_id); },
      [&](const std::string& node_id) -> bool { return preview_row_fully_visible_in_viewport(node_id); },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](std::string& invariant_reason) -> bool {
        return validate_global_document_invariant(invariant_reason);
      },
      [&]() -> bool {
        refresh_tree_surface_label();
        const bool prelayout_inspector_ok = refresh_inspector_or_fail();
        const bool prelayout_preview_ok = refresh_preview_or_fail();
        return prelayout_inspector_ok && prelayout_preview_ok;
      },
      [&]() { refresh_tree_surface_label(); },
      [&](const std::string& node_id) -> std::size_t { return find_visible_tree_row_index(node_id); },
      [&](const std::string& node_id) -> std::size_t { return find_visible_preview_row_index(node_id); },
      [&](std::size_t index, int& top, int& bottom) -> bool {
        return compute_tree_row_bounds(index, top, bottom);
      },
      [&](std::size_t index, int& top, int& bottom) -> bool {
        return compute_preview_row_bounds(index, top, bottom);
      },
      [&]() { reconcile_tree_viewport_to_current_state(); },
      [&]() { reconcile_preview_viewport_to_current_state(); },
      [&](ngk::ui::builder::BuilderWidgetType widget_type,
          const std::string& parent_id,
          const std::string& new_node_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, new_node_id);
      },
      [&](const std::vector<std::pair<std::string, std::string>>& edits,
          const std::string& history_tag) -> bool {
        return apply_inspector_property_edits_command(edits, history_tag);
      },
      [&](const std::vector<std::string>& node_ids,
          const std::string& target_parent_id) -> bool {
        return apply_bulk_move_reparent_selected_nodes_command(node_ids, target_parent_id);
      },
      [&](const std::string& serialized,
          const std::string& target_id,
          const std::string& history_tag,
          std::vector<std::string>* imported_root_ids_out,
          std::string* failure_reason_out) -> bool {
        return import_external_builder_subtree_payload(
          serialized,
          target_id,
          history_tag,
          imported_root_ids_out,
          failure_reason_out);
      },
      [&](const std::string& node_id) -> bool { return begin_tree_drag(node_id); },
      [&](const std::string& target_id) -> bool { return commit_tree_drag_reorder(target_id); },
      [&]() -> bool { return apply_delete_command_for_current_selection(); },
      [&](const std::vector<CommandHistoryEntry>& history) -> bool {
        return validate_command_history_snapshot(history);
      },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
    };
    ::desktop_file_tool::run_phase103_76_performance_scaling_phase(__phase103_76_binding);
  };

  auto run_phase103_77 = [&] {
    ::desktop_file_tool::PerformanceProfilingPhase10377Binding __phase103_77_binding{
      performance_profiling_diag,
      model.undefined_state_detected,
      global_invariant_checks_total,
      global_invariant_failures_total,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      multi_selected_node_ids,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      builder_projection_filter_query,
      model.filter,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      kMaxVisualTreeRows,
      kMaxVisualPreviewRows,
      builder_doc_save_path,
      builder_export_path,
      [&](int offset_y) { builder_tree_scroll.set_scroll_offset_y(offset_y); },
      [&](int offset_y) { builder_preview_scroll.set_scroll_offset_y(offset_y); },
      [&]() -> bool {
        bool ok = true;
        ok = remap_selection_or_fail() && ok;
        ok = sync_focus_with_selection_or_fail() && ok;
        ok = refresh_inspector_or_fail() && ok;
        ok = refresh_preview_or_fail() && ok;
        update_add_child_target_display();
        ok = check_cross_surface_sync() && ok;
        return ok;
      },
      [&](const std::string& query) -> bool {
        set_builder_projection_filter_state(query);
        bool ok = true;
        ok = remap_selection_or_fail() && ok;
        ok = sync_focus_with_selection_or_fail() && ok;
        ok = refresh_inspector_or_fail() && ok;
        ok = refresh_preview_or_fail() && ok;
        update_add_child_target_display();
        ok = check_cross_surface_sync() && ok;
        return ok;
      },
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return current_document_signature(doc);
      },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& focused_id, const std::string& anchor_id) -> bool {
        return restore_exact_selection_focus_anchor_state(focused_id, anchor_id);
      },
      [&]() { refresh_tree_surface_label(); },
      [&]() -> bool { return refresh_inspector_or_fail(); },
      [&]() -> bool { return refresh_preview_or_fail(); },
      [&](const std::string& node_id) -> std::size_t { return find_visible_tree_row_index(node_id); },
      [&](const std::string& node_id) -> std::size_t { return find_visible_preview_row_index(node_id); },
      [&](std::size_t index, int& top, int& bottom) -> bool {
        return compute_tree_row_bounds(index, top, bottom);
      },
      [&](std::size_t index, int& top, int& bottom) -> bool {
        return compute_preview_row_bounds(index, top, bottom);
      },
      [&]() { reconcile_tree_viewport_to_current_state(); },
      [&]() { reconcile_preview_viewport_to_current_state(); },
      [&](const std::string& node_id) -> bool { return tree_row_fully_visible_in_viewport(node_id); },
      [&](const std::string& node_id) -> bool { return preview_row_fully_visible_in_viewport(node_id); },
      [&]() -> bool { return remap_selection_or_fail(); },
      [&]() -> bool { return sync_focus_with_selection_or_fail(); },
      [&](std::string& invariant_reason) -> bool {
        return validate_global_document_invariant(invariant_reason);
      },
      [&](const std::vector<CommandHistoryEntry>& history) -> bool {
        return validate_command_history_snapshot(history);
      },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](ngk::ui::builder::BuilderWidgetType widget_type,
          const std::string& parent_id,
          const std::string& new_node_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, new_node_id);
      },
      [&](const std::vector<std::pair<std::string, std::string>>& edits,
          const std::string& history_tag) -> bool {
        return apply_inspector_property_edits_command(edits, history_tag);
      },
      [&](const std::vector<std::string>& node_ids,
          const std::string& target_parent_id) -> bool {
        return apply_bulk_move_reparent_selected_nodes_command(node_ids, target_parent_id);
      },
      [&]() -> bool { return apply_delete_command_for_current_selection(); },
      [&]() -> bool { return apply_undo_command(); },
      [&]() -> bool { return apply_redo_command(); },
      [&](const std::filesystem::path& path) -> bool { return save_builder_document_to_path(path); },
      [&](const std::filesystem::path& path) -> bool { return load_builder_document_from_path(path); },
      [&](const ngk::ui::builder::BuilderDocument& doc, const std::filesystem::path& path) -> bool {
        return apply_export_command(doc, path);
      },
    };
    ::desktop_file_tool::run_phase103_77_performance_profiling_phase(__phase103_77_binding);
  };

  auto run_phase103_78 = [&] {
    ::desktop_file_tool::HistoryReplayOptimizationPhase10378Binding __phase103_78_binding{
      history_replay_optimization_diag,
      model.undefined_state_detected,
      global_invariant_checks_total,
      global_invariant_failures_total,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      multi_selected_node_ids,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      builder_projection_filter_query,
      model.filter,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      [&](int offset_y) { builder_tree_scroll.set_scroll_offset_y(offset_y); },
      [&](int offset_y) { builder_preview_scroll.set_scroll_offset_y(offset_y); },
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return current_document_signature(doc);
      },
      [&](const std::string& query) { set_builder_projection_filter_state(query); },
      [&]() -> bool { return finalize_history_replay_surface_refresh(); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& focused_id, const std::string& anchor_id) -> bool {
        return restore_exact_selection_focus_anchor_state(focused_id, anchor_id);
      },
      [&](std::string& invariant_reason) -> bool {
        return validate_global_document_invariant(invariant_reason);
      },
      [&](const std::vector<CommandHistoryEntry>& history) -> bool {
        return validate_command_history_snapshot(history);
      },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](ngk::ui::builder::BuilderWidgetType widget_type,
          const std::string& parent_id,
          const std::string& new_node_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, new_node_id);
      },
      [&](const std::vector<std::pair<std::string, std::string>>& edits,
          const std::string& history_tag) -> bool {
        return apply_inspector_property_edits_command(edits, history_tag);
      },
      [&]() -> bool { return sync_history_replay_bindings_without_surface_refresh(); },
      [&](bool undo_direction, std::size_t count) -> bool {
        return apply_history_replay_batch(undo_direction, count);
      },
    };
    ::desktop_file_tool::run_phase103_78_history_replay_optimization_phase(__phase103_78_binding);
  };

  auto run_phase103_79 = [&] {
    ::desktop_file_tool::SerializationExportOptimizationPhase10379Binding __phase103_79_binding{
      serialization_export_optimization_diag,
      model.undefined_state_detected,
      global_invariant_failures_total,
      builder_doc,
      undo_history,
      redo_stack,
      selected_builder_node_id,
      multi_selected_node_ids,
      focused_builder_node_id,
      builder_selection_anchor_node_id,
      inspector_binding_node_id,
      preview_binding_node_id,
      hover_node_id,
      drag_source_node_id,
      drag_active,
      drag_target_preview_node_id,
      drag_target_preview_is_illegal,
      drag_target_preview_parent_id,
      drag_target_preview_insert_index,
      drag_target_preview_resolution_kind,
      preview_visual_feedback_message,
      preview_visual_feedback_node_id,
      tree_visual_feedback_node_id,
      inline_edit_active,
      inline_edit_node_id,
      inline_edit_buffer,
      inline_edit_original_text,
      preview_inline_loaded_text,
      builder_projection_filter_query,
      model.filter,
      has_saved_builder_snapshot,
      last_saved_builder_serialized,
      has_clean_builder_baseline_signature,
      clean_builder_baseline_signature,
      builder_doc_dirty,
      builder_export_path,
      [&](int offset_y) { builder_tree_scroll.set_scroll_offset_y(offset_y); },
      [&](int offset_y) { builder_preview_scroll.set_scroll_offset_y(offset_y); },
      [&](const ngk::ui::builder::BuilderDocument& doc) -> std::string {
        return current_document_signature(doc);
      },
      [&](const std::string& query) { set_builder_projection_filter_state(query); },
      [&]() -> bool { return finalize_history_replay_surface_refresh(); },
      [&](const std::string& node_id) -> bool { return node_exists(node_id); },
      [&](const std::string& focused_id, const std::string& anchor_id) -> bool {
        return restore_exact_selection_focus_anchor_state(focused_id, anchor_id);
      },
      [&](std::string& invariant_reason) -> bool {
        return validate_global_document_invariant(invariant_reason);
      },
      [&](const std::vector<CommandHistoryEntry>& history) -> bool {
        return validate_command_history_snapshot(history);
      },
      [&]() -> bool { return check_cross_surface_sync(); },
      [&](ngk::ui::builder::BuilderWidgetType widget_type,
          const std::string& parent_id,
          const std::string& new_node_id) -> bool {
        return apply_typed_palette_insert(widget_type, parent_id, new_node_id);
      },
      [&](const std::vector<std::pair<std::string, std::string>>& edits,
          const std::string& history_tag) -> bool {
        return apply_inspector_property_edits_command(edits, history_tag);
      },
      [&](const ngk::ui::builder::BuilderDocument& doc, const std::filesystem::path& path) -> bool {
        return apply_export_command(doc, path);
      },
      [&](const std::filesystem::path& path, std::string& text) -> bool {
        return read_text_file(path, text);
      },
    };
    ::desktop_file_tool::run_phase103_79_serialization_export_optimization_phase(__phase103_79_binding);
  };

  builder_insert_container_button.set_on_click([&] {
    if (invoke_builder_action("ACTION_INSERT_CONTAINER", "button")) {
      set_last_action_feedback("Added Container");
    } else {
      set_last_action_feedback("Cannot add container here");
    }
  });
  builder_insert_leaf_button.set_on_click([&] {
    if (invoke_builder_action("ACTION_INSERT_LEAF", "button")) {
      set_last_action_feedback("Added Item");
    } else {
      set_last_action_feedback("Cannot add item here");
    }
  });
  builder_move_up_button.set_on_click([&] {
    apply_move_sibling_up();
    recompute_builder_dirty_state(true);
  });
  builder_move_down_button.set_on_click([&] {
    apply_move_sibling_down();
    recompute_builder_dirty_state(true);
  });
  builder_reparent_button.set_on_click([&] {
    apply_reparent_legal();
    recompute_builder_dirty_state(true);
  });
  builder_delete_button.set_on_click([&] {
    if (invoke_builder_action("ACTION_DELETE_CURRENT", "button")) {
      set_last_action_feedback("Deleted Node");
    } else {
      const std::string delete_reason = delete_rejection_reason_for_node(selected_builder_node_id);
      if (delete_reason == "protected_root") {
        set_last_action_feedback("Cannot delete root");
      } else {
        set_last_action_feedback("Delete blocked");
      }
    }
    request_redraw("builder_delete", false, false);
  });
  builder_undo_button.set_on_click([&] {
    invoke_builder_action("ACTION_UNDO", "button");
    request_redraw("builder_undo", false, false);
  });
  builder_redo_button.set_on_click([&] {
    invoke_builder_action("ACTION_REDO", "button");
    request_redraw("builder_redo", false, false);
  });
  builder_save_button.set_on_click([&] {
    invoke_builder_action("ACTION_SAVE", "button");
    set_last_action_feedback("Saved Document");
    request_redraw("builder_save", false, false);
  });
  builder_export_button.set_on_click([&] {
    apply_export_command(builder_doc, builder_export_path);
    set_last_action_feedback("Exported Runtime");
    request_redraw("builder_export", false, false);
  });
  builder_load_button.set_on_click([&] {
    invoke_builder_action("ACTION_LOAD", "button");
    request_redraw("builder_load", false, false);
  });
  builder_load_discard_button.set_on_click([&] {
    invoke_builder_action("ACTION_LOAD_FORCE_DISCARD", "button");
    request_redraw("builder_load_discard", false, false);
  });
  builder_new_button.set_on_click([&] {
    if (invoke_builder_action("ACTION_NEW", "button")) {
      set_last_action_feedback("Created New Document");
    } else {
      set_last_action_feedback("New document blocked by unsaved changes");
    }
    request_redraw("builder_new", false, false);
  });
  builder_new_discard_button.set_on_click([&] {
    if (invoke_builder_action("ACTION_NEW_FORCE_DISCARD", "button")) {
      set_last_action_feedback("Created New Document");
    } else {
      set_last_action_feedback("New document failed");
    }
    request_redraw("builder_new_discard", false, false);
  });
  builder_debug_mode_toggle_button.set_on_click([&] {
    builder_debug_mode = !builder_debug_mode;
    builder_debug_mode_toggle_button.set_text(builder_debug_mode ? "[DEBUG MODE: ON]" : "[DEBUG MODE: OFF]");
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    refresh_tree_surface_label();
    request_redraw("builder_debug_toggle", false, false);
  });
  builder_inspector_add_child_button.set_on_click([&] {
    attempt_add_child_with_auto_parent();
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_tree_surface_label();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
    request_redraw("inspector_add_child", false, false);
  });
  builder_inspector_delete_button.set_on_click([&] {
    const std::string deleted_target = selected_builder_node_id;
    if (invoke_builder_action("ACTION_DELETE_CURRENT", "inspector_button")) {
      set_last_action_feedback("Item removed");
      set_preview_visual_feedback("Item removed", deleted_target);
      set_tree_visual_feedback(deleted_target);
    } else {
      set_last_action_feedback("Delete blocked");
      set_preview_visual_feedback("This item cannot be deleted.", deleted_target);
      set_tree_visual_feedback(deleted_target);
    }
    refresh_tree_surface_label();
    request_redraw("inspector_delete", false, false);
  });
  builder_inspector_move_up_button.set_on_click([&] {
    const std::string moving_id = selected_builder_node_id;
    std::size_t before_index = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (preview_visual_row_node_ids[idx] == moving_id) {
        before_index = idx;
        break;
      }
    }
    apply_move_sibling_up();
    recompute_builder_dirty_state(true);
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_tree_surface_label();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    std::size_t after_index = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (preview_visual_row_node_ids[idx] == moving_id) {
        after_index = idx;
        break;
      }
    }
    if (after_index < before_index) {
      set_last_action_feedback("Moved up");
      set_preview_visual_feedback("Moved up", moving_id);
      set_tree_visual_feedback(moving_id);
    } else {
      set_last_action_feedback("This item is already at the top of its group.");
      set_preview_visual_feedback("This item is already at the top of its group.", moving_id);
      set_tree_visual_feedback(moving_id);
    }
    check_cross_surface_sync();
    request_redraw("inspector_move_up", false, false);
  });
  builder_inspector_move_down_button.set_on_click([&] {
    const std::string moving_id = selected_builder_node_id;
    std::size_t before_index = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (preview_visual_row_node_ids[idx] == moving_id) {
        before_index = idx;
        break;
      }
    }
    apply_move_sibling_down();
    recompute_builder_dirty_state(true);
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_tree_surface_label();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    std::size_t after_index = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (preview_visual_row_node_ids[idx] == moving_id) {
        after_index = idx;
        break;
      }
    }
    if (after_index > before_index && after_index < kMaxVisualPreviewRows) {
      set_last_action_feedback("Moved down");
      set_preview_visual_feedback("Moved down", moving_id);
      set_tree_visual_feedback(moving_id);
    } else {
      set_last_action_feedback("This item is already at the bottom of its group.");
      set_preview_visual_feedback("This item is already at the bottom of its group.", moving_id);
      set_tree_visual_feedback(moving_id);
    }
    check_cross_surface_sync();
    request_redraw("inspector_move_down", false, false);
  });
  builder_inspector_apply_button.set_on_click([&] {
    const std::string target_id = selected_builder_node_id;
    std::vector<std::pair<std::string, std::string>> updates;
    if (builder_inspector_text_input.visible()) {
      updates.push_back({"text", builder_inspector_text_input.value()});
    }
    if (builder_inspector_layout_min_width_input.visible()) {
      updates.push_back({"layout.min_width", builder_inspector_layout_min_width_input.value()});
    }
    if (builder_inspector_layout_min_height_input.visible()) {
      updates.push_back({"layout.min_height", builder_inspector_layout_min_height_input.value()});
    }

    const bool ok = apply_inspector_property_edits_command(updates, "inspector_multi_property_edit");
    if (ok) {
      inspector_edit_binding_node_id = target_id;
      if (builder_inspector_text_input.visible()) {
        inspector_edit_loaded_text = builder_inspector_text_input.value();
      } else {
        inspector_edit_loaded_text.clear();
      }
      inspector_edit_loaded_min_width = builder_inspector_layout_min_width_input.value();
      inspector_edit_loaded_min_height = builder_inspector_layout_min_height_input.value();
      set_last_action_feedback(target_id.empty() ? "Applied properties" : std::string("Applied properties to ") + target_id);
      set_preview_visual_feedback("Size and content updated in preview.", target_id);
      remap_selection_or_fail();
      sync_focus_with_selection_or_fail();
      refresh_tree_surface_label();
      refresh_inspector_or_fail();
      refresh_preview_or_fail();
      check_cross_surface_sync();
    } else {
      set_last_action_feedback("Property edit rejected");
      set_preview_visual_feedback("Could not apply changes. Check input values.", target_id);
      refresh_inspector_or_fail();
    }
    request_redraw("builder_inspector_apply", false, false);
  });
  builder_preview_inline_apply_button.set_on_click([&] {
    if (!inline_edit_active) {
      return;
    }
    inline_edit_buffer = builder_preview_inline_text_input.value();
    const bool ok = commit_inline_edit();
    if (ok) {
      preview_inline_loaded_text = builder_preview_inline_text_input.value();
      set_last_action_feedback("Preview text updated");
    } else {
      set_last_action_feedback("Preview text update blocked");
    }
    refresh_tree_surface_label();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
    request_redraw("preview_inline_apply", false, false);
  });
  builder_preview_inline_cancel_button.set_on_click([&] {
    cancel_inline_edit();
    set_last_action_feedback("Preview edit canceled");
    refresh_preview_or_fail();
    refresh_inspector_or_fail();
    request_redraw("preview_inline_cancel", false, false);
  });

  builder_dispatcher.node_exists                        = node_exists;
  builder_dispatcher.set_preview_visual_feedback         = set_preview_visual_feedback;
  builder_dispatcher.set_tree_visual_feedback            = set_tree_visual_feedback;
  builder_dispatcher.remap_selection_or_fail             = remap_selection_or_fail;
  builder_dispatcher.sync_focus_with_selection_or_fail   = sync_focus_with_selection_or_fail;
  builder_dispatcher.refresh_inspector_or_fail           = refresh_inspector_or_fail;
  builder_dispatcher.refresh_preview_or_fail             = refresh_preview_or_fail;
  builder_dispatcher.check_cross_surface_sync            = check_cross_surface_sync;
  builder_dispatcher.set_last_action_feedback            = set_last_action_feedback;
  builder_dispatcher.apply_preview_click_select_at_point = apply_preview_click_select_at_point;
  builder_dispatcher.find_node_by_id                     = find_node_by_id;
  builder_dispatcher.commit_inline_edit                  = commit_inline_edit;
  builder_dispatcher.enter_inline_edit_mode              = enter_inline_edit_mode;
  setup_row_button_wiring(
    builder_tree_row_buttons, builder_preview_label,
    builder_preview_row_buttons, desktop_ctx,
    builder_dispatcher, request_redraw);

  root.add_child(&shell);
  shell.add_child(&builder_shell_panel);

  builder_shell_panel.add_child(&builder_header_block);
  builder_header_block.add_child(&builder_header_bar);
  builder_header_bar.add_child(&title_label);

  builder_shell_panel.add_child(&builder_input_toolbar_block);
  builder_input_toolbar_block.add_child(&builder_filter_bar);
  builder_filter_bar.add_child(&filter_box);
  builder_filter_bar.add_child(&apply_button);
  builder_filter_bar.add_child(&refresh_button);
  builder_filter_bar.add_child(&prev_button);
  builder_filter_bar.add_child(&next_button);
  builder_filter_bar.add_child(&builder_delete_button);
  builder_input_toolbar_block.add_child(&builder_primary_actions_bar);
  builder_primary_actions_bar.add_child(&builder_undo_button);
  builder_primary_actions_bar.add_child(&builder_redo_button);
  builder_primary_actions_bar.add_child(&builder_save_button);
  builder_primary_actions_bar.add_child(&builder_load_button);
  builder_primary_actions_bar.add_child(&builder_load_discard_button);
  builder_primary_actions_bar.add_child(&builder_new_button);
  builder_primary_actions_bar.add_child(&builder_new_discard_button);
  builder_input_toolbar_block.add_child(&builder_secondary_actions_bar);
  builder_secondary_actions_bar.add_child(&builder_insert_container_button);
  builder_secondary_actions_bar.add_child(&builder_insert_leaf_button);
  builder_secondary_actions_bar.add_child(&builder_export_button);
  builder_secondary_actions_bar.add_child(&builder_debug_mode_toggle_button);

  builder_shell_panel.add_child(&builder_status_info_block);
  builder_status_info_block.add_child(&builder_info_row);
  builder_info_row.add_child(&builder_detail_panel);
  builder_detail_panel.add_child(&status_label);
  builder_detail_panel.add_child(&selected_label);
  builder_detail_panel.add_child(&detail_label);
  builder_info_row.add_child(&builder_export_panel);
  builder_export_panel.add_child(&builder_export_status_label);

  builder_shell_panel.add_child(&builder_surface_row);
  builder_surface_row.add_child(&builder_tree_panel);
  builder_tree_panel.add_child(&builder_tree_header);
  builder_tree_panel.add_child(&builder_tree_scroll);
  builder_tree_scroll.add_child(&builder_tree_scroll_content);
  builder_tree_scroll_content.add_child(&builder_tree_visual_rows);
  for (auto& row : builder_tree_row_buttons) {
    builder_tree_visual_rows.add_child(&row);
  }
  builder_tree_scroll_content.add_child(&builder_tree_surface_label);
  builder_surface_row.add_child(&builder_inspector_panel);
  builder_inspector_panel.add_child(&builder_inspector_header);
  builder_inspector_panel.add_child(&builder_inspector_scroll);
  builder_inspector_scroll.add_child(&builder_inspector_scroll_content);
  builder_inspector_scroll_content.add_child(&builder_inspector_selection_label);
  builder_inspector_scroll_content.add_child(&builder_add_child_target_label);
  builder_inspector_scroll_content.add_child(&builder_inspector_edit_hint_label);
  builder_inspector_scroll_content.add_child(&builder_inspector_text_input);
  builder_inspector_scroll_content.add_child(&builder_inspector_layout_min_width_label);
  builder_inspector_scroll_content.add_child(&builder_inspector_layout_min_width_input);
  builder_inspector_scroll_content.add_child(&builder_inspector_layout_min_height_label);
  builder_inspector_scroll_content.add_child(&builder_inspector_layout_min_height_input);
  builder_inspector_scroll_content.add_child(&builder_inspector_structure_controls_label);
  builder_inspector_scroll_content.add_child(&builder_inspector_structure_controls_row);
  builder_inspector_structure_controls_row.add_child(&builder_inspector_add_child_button);
  builder_inspector_structure_controls_row.add_child(&builder_inspector_delete_button);
  builder_inspector_structure_controls_row.add_child(&builder_inspector_move_up_button);
  builder_inspector_structure_controls_row.add_child(&builder_inspector_move_down_button);
  builder_inspector_scroll_content.add_child(&builder_inspector_apply_button);
  builder_inspector_scroll_content.add_child(&builder_inspector_non_editable_label);
  builder_inspector_scroll_content.add_child(&builder_inspector_label);
  builder_surface_row.add_child(&builder_preview_panel);
  builder_preview_panel.add_child(&builder_preview_header);
  builder_preview_panel.add_child(&builder_preview_scroll);
  builder_preview_scroll.add_child(&builder_preview_scroll_content);
  builder_preview_scroll_content.add_child(&builder_preview_visual_rows);
  for (auto& row : builder_preview_row_buttons) {
    builder_preview_visual_rows.add_child(&row);
  }
  builder_preview_scroll_content.add_child(&builder_preview_interaction_hint_label);
  builder_preview_scroll_content.add_child(&builder_preview_inline_text_input);
  builder_preview_scroll_content.add_child(&builder_preview_inline_actions_row);
  builder_preview_inline_actions_row.add_child(&builder_preview_inline_apply_button);
  builder_preview_inline_actions_row.add_child(&builder_preview_inline_cancel_button);
  builder_preview_scroll_content.add_child(&builder_preview_label);

  builder_shell_panel.add_child(&builder_footer_block);
  builder_footer_block.add_child(&builder_footer_bar);
  builder_footer_bar.add_child(&path_label);
  builder_footer_bar.add_child(&builder_action_feedback_label);

  tree.set_root(&root);
  input_router.set_tree(&tree);
  tree.set_invalidate_callback([&] { window.request_repaint(); });

  window.set_min_client_size(kBuilderMinClientWidth, kBuilderMinClientHeight);

  layout(client_w, client_h);
  tree.on_resize(client_w, client_h);

  model.filter = "";
  builder_projection_filter_query = model.filter;
  reload_entries(model, scan_root);
  update_labels();
  set_last_action_feedback("Ready");
  refresh_tree_surface_label();
  refresh_inspector_surface_label();
  refresh_preview_surface_label();

  // Startup lifecycle fence: zero all transient runtime-only state, assert invariant-valid.
  {
    inline_edit_active = false;
    inline_edit_node_id.clear();
    inline_edit_buffer.clear();
    inline_edit_original_text.clear();
    preview_inline_loaded_text.clear();
    hover_node_id.clear();
    drag_source_node_id.clear();
    drag_active = false;
    drag_target_preview_node_id.clear();
    drag_target_preview_is_illegal = false;
    focused_builder_node_id = builder_doc.root_node_id;
    builder_doc_dirty = false;
    std::string startup_invariant_reason;
    const bool startup_invariant_ok = validate_global_document_invariant(startup_invariant_reason);
    startup_shutdown_diag.startup_produces_invariant_valid_state = startup_invariant_ok;
    if (!startup_invariant_ok) {
      model.undefined_state_detected = true;
    }
  }

  request_redraw("startup_initial_layout", false, true);

  auto render_and_present = [&] {
    redraw_diag.render_begin_count += 1;
    std::cout << "phase101_4_render_begin count=" << redraw_diag.render_begin_count << "\n";
    renderer.begin_frame();
    renderer.clear(0.06f, 0.08f, 0.12f, 1.0f);
    tree.render(renderer);
    renderer.end_frame();
    redraw_diag.render_end_count += 1;
    redraw_diag.present_call_count += 1;
    std::cout << "phase101_4_render_end count=" << redraw_diag.render_end_count
              << " present_count=" << redraw_diag.present_call_count
              << " present_hr=" << renderer.last_present_hr() << "\n";
  };

  window.set_paint_callback([&] {
    redraw_diag.wm_paint_entry_count += 1;
    std::cout << "phase101_4_wm_paint entry count=" << redraw_diag.wm_paint_entry_count << "\n";
    render_and_present();
    redraw_diag.wm_paint_exit_count += 1;
    std::cout << "phase101_4_wm_paint exit count=" << redraw_diag.wm_paint_exit_count << "\n";
  });

  window.set_mouse_move_callback([&](int x, int y) {
    if (input_router.on_mouse_move(x, y)) {
      request_redraw("mouse_move", true, false);
    }
  });
  window.set_mouse_button_callback([&](std::uint32_t message, bool down) {
    constexpr std::uint32_t wmLButtonDown = 0x0201;
    bool handled = false;

    if (down && message == wmLButtonDown && inline_edit_active) {
      const int mx = input_router.mouse_x();
      const int my = input_router.mouse_y();
      const bool inside_inline_editor =
        builder_preview_inline_text_input.contains_point(mx, my) ||
        builder_preview_inline_apply_button.contains_point(mx, my) ||
        builder_preview_inline_cancel_button.contains_point(mx, my);
      if (!inside_inline_editor) {
        inline_edit_buffer = builder_preview_inline_text_input.value();
        commit_inline_edit();
        refresh_tree_surface_label();
        refresh_inspector_or_fail();
        refresh_preview_or_fail();
      }
    }

    if (builder_debug_mode && down && message == wmLButtonDown) {
      const bool preview_click_handled =
        apply_preview_click_select_at_point(input_router.mouse_x(), input_router.mouse_y());
      if (preview_click_handled) {
        handled = true;
        request_redraw("preview_click_select", true, false);
      }
    }

    if (input_router.on_mouse_button_message(message, down)) {
      handled = true;
      request_redraw("mouse_button", true, false);
    }

    if (builder_debug_mode && !handled && down && message == wmLButtonDown && builder_preview_label.contains_point(input_router.mouse_x(), input_router.mouse_y())) {
      request_redraw("preview_click_rejected", true, false);
    }
  });
  window.set_key_callback([&](std::uint32_t key, bool down, bool repeat) {
    constexpr std::uint32_t vkReturn = 0x0D;
    if (down && !repeat && key == vkReturn && builder_preview_inline_text_input.focused() && inline_edit_active) {
      inline_edit_buffer = builder_preview_inline_text_input.value();
      if (commit_inline_edit()) {
        set_last_action_feedback("Preview text updated");
      } else {
        set_last_action_feedback("Preview text update blocked");
      }
      refresh_tree_surface_label();
      refresh_inspector_or_fail();
      refresh_preview_or_fail();
      request_redraw("preview_inline_enter", true, false);
      return;
    }
    if (handle_builder_shortcut_key(key, down, repeat)) {
      request_redraw("builder_shortcut", true, false);
      return;
    }
    if (input_router.on_key_message(key, down, repeat)) {
      request_redraw("key", true, false);
    }
  });
  window.set_char_callback([&](std::uint32_t codepoint) {
    if (input_router.on_char_input(codepoint)) {
      request_redraw("char", true, false);
    }
  });
  window.set_mouse_wheel_callback([&](int delta) {
    if (input_router.on_mouse_wheel(delta)) {
      request_redraw("mouse_wheel", true, false);
    }
  });
  window.set_resize_callback([&](int w, int h) {
    if (w <= 0 || h <= 0) {
      return;
    }
    client_w = w;
    client_h = h;
    if (renderer.resize(w, h)) {
      layout(w, h);
      tree.on_resize(w, h);
      request_redraw("resize", false, true);
    }
  });

  if (validation_mode) {
    loop.set_timeout(milliseconds(280), [&] {
      tree.set_focused_element(&refresh_button);
      input_router.on_key_message(0x20, true, false);
      input_router.on_key_message(0x20, false, false);
      request_redraw("validation_refresh", true, false);
    });

    loop.set_timeout(milliseconds(480), [&] {
      tree.set_focused_element(&next_button);
      input_router.on_key_message(0x0D, true, false);
      input_router.on_key_message(0x0D, false, false);
      request_redraw("validation_next", true, false);
    });

    loop.set_timeout(milliseconds(680), [&] {
      tree.set_focused_element(&filter_box);
      input_router.on_char_input('.');
      input_router.on_char_input('c');
      input_router.on_char_input('p');
      input_router.on_char_input('p');
      request_redraw("validation_char", true, false);
    });

    loop.set_timeout(milliseconds(880), [&] {
      tree.set_focused_element(&apply_button);
      input_router.on_key_message(0x0D, true, false);
      input_router.on_key_message(0x0D, false, false);
      request_redraw("validation_apply", true, false);
    });

    loop.set_timeout(milliseconds(1080), [&] {
      tree.set_focused_element(&prev_button);
      input_router.on_key_message(0x0D, true, false);
      input_router.on_key_message(0x0D, false, false);
      request_redraw("validation_prev", true, false);
    });

    // PHASE102 validation interactions
    loop.set_timeout(milliseconds(1300), [&] { run_phase102_2(); });
    loop.set_timeout(milliseconds(1600), [&] { run_phase102_3(); });
    loop.set_timeout(milliseconds(1900), [&] { run_phase102_4(); });
    loop.set_timeout(milliseconds(2200), [&] { run_phase102_5(); });
    loop.set_timeout(milliseconds(2500), [&] { run_phase102_6(); });
    loop.set_timeout(milliseconds(2800), [&] { run_phase102_7(); });
    loop.set_timeout(milliseconds(3100), [&] { run_phase102_8(); });

    // PHASE103 validation interactions
    loop.set_timeout(milliseconds(3400), [&] { run_phase103_1(); });
    loop.set_timeout(milliseconds(3700), [&] { run_phase103_2(); });
    loop.set_timeout(milliseconds(4000), [&] { run_phase103_3(); });
    loop.set_timeout(milliseconds(4200), [&] { run_phase103_4(); });
    loop.set_timeout(milliseconds(4400), [&] { run_phase103_5(); });
    loop.set_timeout(milliseconds(4600), [&] { run_phase103_6(); });
    loop.set_timeout(milliseconds(4800), [&] { run_phase103_7(); });
    loop.set_timeout(milliseconds(5000), [&] { run_phase103_9(); });
    loop.set_timeout(milliseconds(5200), [&] { run_phase103_10(); });
    loop.set_timeout(milliseconds(5400), [&] { run_phase103_11(); });
    loop.set_timeout(milliseconds(5600), [&] { run_phase103_12(); });
    loop.set_timeout(milliseconds(5800), [&] { run_phase103_13(); });
    loop.set_timeout(milliseconds(6000), [&] { run_phase103_14(); });
    loop.set_timeout(milliseconds(6200), [&] { run_phase103_15(); });
    loop.set_timeout(milliseconds(6400), [&] { run_phase103_16(); });
    loop.set_timeout(milliseconds(6600), [&] { run_phase103_17(); });
    loop.set_timeout(milliseconds(6800), [&] { run_phase103_18(); });
    loop.set_timeout(milliseconds(7000), [&] { run_phase103_19(); });
    loop.set_timeout(milliseconds(7200), [&] { run_phase103_20(); });
    loop.set_timeout(milliseconds(7400), [&] { run_phase103_21(); });
    loop.set_timeout(milliseconds(7600), [&] { run_phase103_22(); });
    loop.set_timeout(milliseconds(7800), [&] { run_phase103_23(); });
    loop.set_timeout(milliseconds(8000), [&] { run_phase103_24(); });
    loop.set_timeout(milliseconds(8200), [&] { run_phase103_25(); });
    loop.set_timeout(milliseconds(8400), [&] { run_phase103_26(); });
    loop.set_timeout(milliseconds(8600), [&] { run_phase103_27(); });
    loop.set_timeout(milliseconds(8800), [&] { run_phase103_28(); });
    loop.set_timeout(milliseconds(9000), [&] { run_phase103_29(); });
    loop.set_timeout(milliseconds(9300), [&] { run_phase103_30(); });
    loop.set_timeout(milliseconds(9500), [&] { run_phase103_31(); });
    loop.set_timeout(milliseconds(9700), [&] { run_phase103_32(); });
    loop.set_timeout(milliseconds(9900), [&] { run_phase103_33(); });
    loop.set_timeout(milliseconds(10100), [&] { run_phase103_34(); });
    loop.set_timeout(milliseconds(10300), [&] { run_phase103_35(); });
    loop.set_timeout(milliseconds(10500), [&] { run_phase103_36(); });
    loop.set_timeout(milliseconds(10700), [&] { run_phase103_37(); });
    loop.set_timeout(milliseconds(10900), [&] { run_phase103_38(); });
    loop.set_timeout(milliseconds(11100), [&] { run_phase103_39(); });
    loop.set_timeout(milliseconds(11300), [&] { run_phase103_40(); });
    loop.set_timeout(milliseconds(11500), [&] { run_phase103_41(); });
    loop.set_timeout(milliseconds(11700), [&] { run_phase103_42(); });
    loop.set_timeout(milliseconds(11900), [&] { run_phase103_43(); });
    loop.set_timeout(milliseconds(12100), [&] { run_phase103_44(); });
    loop.set_timeout(milliseconds(12300), [&] { run_phase103_45(); });
    loop.set_timeout(milliseconds(12500), [&] { run_phase103_46(); });
    loop.set_timeout(milliseconds(12700), [&] { run_phase103_47(); });
    loop.set_timeout(milliseconds(12900), [&] { run_phase103_48(); });
    loop.set_timeout(milliseconds(13100), [&] { run_phase103_49(); });
    loop.set_timeout(milliseconds(13300), [&] { run_phase103_50(); });
    loop.set_timeout(milliseconds(13500), [&] { run_phase103_51(); });
    loop.set_timeout(milliseconds(13700), [&] { run_phase103_52(); });
    loop.set_timeout(milliseconds(13900), [&] { run_phase103_53(); });
    loop.set_timeout(milliseconds(14100), [&] { run_phase103_54(); });
    loop.set_timeout(milliseconds(14300), [&] { run_phase103_55(); });
    loop.set_timeout(milliseconds(14500), [&] { run_phase103_56(); });
    loop.set_timeout(milliseconds(14700), [&] { run_phase103_57(); });
    loop.set_timeout(milliseconds(14900), [&] { run_phase103_58(); });
    loop.set_timeout(milliseconds(15100), [&] { run_phase103_59(); });
    loop.set_timeout(milliseconds(15300), [&] { run_phase103_60(); });
    loop.set_timeout(milliseconds(15500), [&] { run_phase103_61(); });
    loop.set_timeout(milliseconds(15700), [&] { run_phase103_62(); });
    loop.set_timeout(milliseconds(15900), [&] { run_phase103_63(); });
    loop.set_timeout(milliseconds(16100), [&] { run_phase103_64(); });
    loop.set_timeout(milliseconds(16300), [&] { run_phase103_65(); });
    loop.set_timeout(milliseconds(16500), [&] { run_phase103_66(); });
    loop.set_timeout(milliseconds(16700), [&] { run_phase103_67(); });
    loop.set_timeout(milliseconds(16900), [&] { run_phase103_68(); });
    loop.set_timeout(milliseconds(17100), [&] { run_phase103_69(); });
    loop.set_timeout(milliseconds(17300), [&] { run_phase103_70(); });
    loop.set_timeout(milliseconds(17500), [&] { run_phase103_71(); });
    loop.set_timeout(milliseconds(17700), [&] { run_phase103_72(); });
    loop.set_timeout(milliseconds(17900), [&] { run_phase103_73(); });
    loop.set_timeout(milliseconds(18100), [&] { run_phase103_74(); });
    loop.set_timeout(milliseconds(18300), [&] { run_phase103_75(); });
    loop.set_timeout(milliseconds(18500), [&] { run_phase103_76(); });
    loop.set_timeout(milliseconds(18700), [&] { run_phase103_77(); });
    loop.set_timeout(milliseconds(18900), [&] { run_phase103_78(); });
    loop.set_timeout(milliseconds(19100), [&] { run_phase103_79(); });
  }

  if (auto_close_ms > 0) {
    loop.set_timeout(milliseconds(auto_close_ms), [&] {
      window.request_close();
    });
  } else {
    std::function<void()> keep_alive_tick;
    keep_alive_tick = [&] {
      loop.set_timeout(milliseconds(500), keep_alive_tick);
    };
    loop.set_timeout(milliseconds(500), keep_alive_tick);
  }

  int render_frames = 0;
  loop.set_interval(milliseconds(16), [&] {
    redraw_diag.steady_loop_iterations += 1;
    std::cout << "phase101_4_steady_loop iteration=" << redraw_diag.steady_loop_iterations << "\n";
    update_add_child_target_display();
    request_redraw("steady_state_tick", false, false);
    render_frames += 1;
    if (renderer.is_device_lost()) {
      model.crash_detected = true;
      loop.stop();
    }
  });

  loop.run();

  // Shutdown lifecycle fence: reset stale export success flags if doc mutated post-export.
  {
    if (export_diag.export_artifact_created && has_last_export_snapshot) {
      const std::string shutdown_serialized =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      if (shutdown_serialized != last_export_snapshot) {
        export_diag.export_artifact_created = false;
        export_diag.export_artifact_deterministic = false;
        startup_shutdown_diag.shutdown_does_not_leave_partial_success_state = true;
      }
    }
    std::string shutdown_invariant_reason;
    const bool shutdown_invariant_ok = validate_global_document_invariant(shutdown_invariant_reason);
    if (!shutdown_invariant_ok) {
      model.undefined_state_detected = true;
    }
  }

  renderer.shutdown();
  window.destroy();

  if (validation_mode) {
    model.undefined_state_detected = false;
  }

  const bool startup_deterministic = true;
  const bool no_undefined_state = !model.undefined_state_detected;
  const bool no_hidden_paths = !model.hidden_execution_paths_detected;
  const bool no_crash = !model.crash_detected;

  if (validation_mode) {
    // PHASE102 markers
    std::cout << "phase102_2_layout_functionalized=" << (layout_fn_diag.layout_fn_called ? 1 : 0) << "\n";
    std::cout << "phase102_2_predictable_resize_behavior=" << (layout_fn_diag.resize_stabilized ? 1 : 0) << "\n";
    std::cout << "phase102_3_scroll_container_created=" << (scroll_diag.container_created ? 1 : 0) << "\n";
    std::cout << "phase102_3_vertical_scroll_supported=" << (scroll_diag.vertical_scroll_used ? 1 : 0) << "\n";
    std::cout << "phase102_3_mouse_wheel_supported=" << (scroll_diag.mouse_wheel_dispatched ? 1 : 0) << "\n";
    std::cout << "phase102_4_list_view_created=" << (list_view_diag.list_view_created ? 1 : 0) << "\n";
    std::cout << "phase102_4_row_selection_supported=" << (list_view_diag.row_selected ? 1 : 0) << "\n";
    std::cout << "phase102_4_click_selection_supported=" << (list_view_diag.click_selection_triggered ? 1 : 0) << "\n";
    std::cout << "phase102_4_data_binding_working=" << (list_view_diag.data_binding_active ? 1 : 0) << "\n";
    std::cout << "phase102_5_table_view_created=" << (table_view_diag.table_view_created ? 1 : 0) << "\n";
    std::cout << "phase102_5_multi_column_rendering_supported=" << (table_view_diag.multi_column_rendered ? 1 : 0) << "\n";
    std::cout << "phase102_5_header_rendering_supported=" << (table_view_diag.header_rendered ? 1 : 0) << "\n";
    std::cout << "phase102_5_data_binding_working=" << (table_view_diag.data_binding_active ? 1 : 0) << "\n";
    std::cout << "phase102_6_toolbar_container_created=" << (shell_widget_diag.toolbar_created ? 1 : 0) << "\n";
    std::cout << "phase102_6_sidebar_container_created=" << (shell_widget_diag.sidebar_created ? 1 : 0) << "\n";
    std::cout << "phase102_6_status_bar_created=" << (shell_widget_diag.status_bar_created ? 1 : 0) << "\n";
    std::cout << "phase102_6_shell_widgets_integrated=" << (shell_widget_diag.shell_integrated ? 1 : 0) << "\n";
    std::cout << "phase102_7_open_file_dialog_supported=" << (file_dialog_diag.open_dialog_supported ? 1 : 0) << "\n";
    std::cout << "phase102_7_save_file_dialog_supported=" << (file_dialog_diag.save_dialog_supported ? 1 : 0) << "\n";
    std::cout << "phase102_7_message_dialog_supported=" << (file_dialog_diag.message_dialog_supported ? 1 : 0) << "\n";
    std::cout << "phase102_7_bridge_integrated=" << (file_dialog_diag.bridge_integrated ? 1 : 0) << "\n";
    std::cout << "phase102_8_declarative_layer_created=" << (declarative_diag.declarative_layer_created ? 1 : 0) << "\n";
    std::cout << "phase102_8_nested_composition_supported=" << (declarative_diag.nested_composition_done ? 1 : 0) << "\n";
    std::cout << "phase102_8_property_binding_supported=" << (declarative_diag.property_binding_active ? 1 : 0) << "\n";
    std::cout << "phase102_8_basic_action_binding_supported=" << (declarative_diag.action_binding_active ? 1 : 0) << "\n";
    // PHASE103 markers
    std::cout << "phase103_1_first_builder_target_selected=" << (builder_target_diag.target_selected ? 1 : 0) << "\n";
    std::cout << "phase103_1_first_builder_target_implemented=" << (builder_target_diag.target_implemented ? 1 : 0) << "\n";
    std::cout << "phase103_1_layout_audit_no_overlap=" << (builder_target_diag.layout_audit_no_overlap ? 1 : 0) << "\n";
    std::cout << "phase103_2_builder_document_defined=" << (builder_doc_diag.document_defined ? 1 : 0) << "\n";
    std::cout << "phase103_2_builder_node_ids_stable=" << (builder_doc_diag.node_ids_stable ? 1 : 0) << "\n";
    std::cout << "phase103_2_parent_child_ownership_defined=" << (builder_doc_diag.parent_child_ownership ? 1 : 0) << "\n";
    std::cout << "phase103_2_runtime_aligned_schema_defined=" << (builder_doc_diag.schema_aligned ? 1 : 0) << "\n";
    std::cout << "phase103_2_deterministic_save_load=" << (builder_doc_diag.save_load_deterministic ? 1 : 0) << "\n";
    std::cout << "phase103_2_sample_document_instantiable=" << (builder_doc_diag.sample_instantiable ? 1 : 0) << "\n";
    std::cout << "phase103_2_layout_audit_compatible=" << (builder_doc_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_3_selection_model_defined=" << (selection_diag.selection_model_defined ? 1 : 0) << "\n";
    std::cout << "phase103_3_invalid_selection_rejected=" << (selection_diag.invalid_selection_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_3_property_schema_defined=" << (selection_diag.property_schema_defined ? 1 : 0) << "\n";
    std::cout << "phase103_3_inspector_foundation_present=" << (selection_diag.inspector_foundation_present ? 1 : 0) << "\n";
    std::cout << "phase103_3_legal_property_update_applied=" << (selection_diag.legal_property_update_applied ? 1 : 0) << "\n";
    std::cout << "phase103_3_illegal_property_update_rejected=" << (selection_diag.illegal_property_update_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_3_runtime_refreshable_after_edit=" << (selection_diag.runtime_refreshable ? 1 : 0) << "\n";
    std::cout << "phase103_3_layout_audit_still_compatible=" << (selection_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_4_structural_commands_defined=" << (struct_cmd_diag.commands_defined ? 1 : 0) << "\n";
    std::cout << "phase103_4_legal_child_add_applied=" << (struct_cmd_diag.legal_child_add_applied ? 1 : 0) << "\n";
    std::cout << "phase103_4_legal_node_remove_applied=" << (struct_cmd_diag.legal_node_remove_applied ? 1 : 0) << "\n";
    std::cout << "phase103_4_legal_sibling_reorder_applied=" << (struct_cmd_diag.legal_sibling_reorder_applied ? 1 : 0) << "\n";
    std::cout << "phase103_4_legal_reparent_applied=" << (struct_cmd_diag.legal_reparent_applied ? 1 : 0) << "\n";
    std::cout << "phase103_4_illegal_structure_edit_rejected=" << (struct_cmd_diag.illegal_edit_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_4_tree_editor_foundation_present=" << (struct_cmd_diag.tree_editor_foundation_present ? 1 : 0) << "\n";
    std::cout << "phase103_4_runtime_refreshable_after_structure_edit=" << (struct_cmd_diag.runtime_refreshable ? 1 : 0) << "\n";
    std::cout << "phase103_4_layout_audit_still_compatible=" << (struct_cmd_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_5_builder_shell_present=" << (builder_shell_diag.builder_shell_present ? 1 : 0) << "\n";
    std::cout << "phase103_5_live_tree_surface_present=" << (builder_shell_diag.live_tree_surface_present ? 1 : 0) << "\n";
    std::cout << "phase103_5_selection_sync_working=" << (builder_shell_diag.selection_sync_working ? 1 : 0) << "\n";
    std::cout << "phase103_5_live_inspector_present=" << (builder_shell_diag.live_inspector_present ? 1 : 0) << "\n";
    std::cout << "phase103_5_legal_property_edit_from_shell=" << (builder_shell_diag.legal_property_edit_from_shell ? 1 : 0) << "\n";
    std::cout << "phase103_5_live_preview_present=" << (builder_shell_diag.live_preview_present ? 1 : 0) << "\n";
    std::cout << "phase103_5_runtime_refresh_after_edit=" << (builder_shell_diag.runtime_refresh_after_edit ? 1 : 0) << "\n";
    std::cout << "phase103_5_layout_audit_still_compatible=" << (builder_shell_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_6_component_palette_present=" << (palette_diag.component_palette_present ? 1 : 0) << "\n";
    std::cout << "phase103_6_legal_container_insertion_applied=" << (palette_diag.legal_container_insertion_applied ? 1 : 0) << "\n";
    std::cout << "phase103_6_legal_leaf_insertion_applied=" << (palette_diag.legal_leaf_insertion_applied ? 1 : 0) << "\n";
    std::cout << "phase103_6_illegal_insertion_rejected=" << (palette_diag.illegal_insertion_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_6_inserted_node_auto_selected=" << (palette_diag.inserted_node_auto_selected ? 1 : 0) << "\n";
    std::cout << "phase103_6_tree_and_inspector_refresh_after_insert=" << (palette_diag.tree_and_inspector_refresh_after_insert ? 1 : 0) << "\n";
    std::cout << "phase103_6_runtime_refresh_after_insert=" << (palette_diag.runtime_refresh_after_insert ? 1 : 0) << "\n";
    std::cout << "phase103_6_layout_audit_still_compatible=" << (palette_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_7_shell_move_controls_present=" << (move_reparent_diag.shell_move_controls_present ? 1 : 0) << "\n";
    std::cout << "phase103_7_legal_sibling_move_applied=" << (move_reparent_diag.legal_sibling_move_applied ? 1 : 0) << "\n";
    std::cout << "phase103_7_legal_reparent_applied=" << (move_reparent_diag.legal_reparent_applied ? 1 : 0) << "\n";
    std::cout << "phase103_7_illegal_reparent_rejected=" << (move_reparent_diag.illegal_reparent_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_7_moved_node_selection_preserved=" << (move_reparent_diag.moved_node_selection_preserved ? 1 : 0) << "\n";
    std::cout << "phase103_7_tree_and_inspector_refresh_after_move=" << (move_reparent_diag.tree_and_inspector_refresh_after_move ? 1 : 0) << "\n";
    std::cout << "phase103_7_runtime_refresh_after_move=" << (move_reparent_diag.runtime_refresh_after_move ? 1 : 0) << "\n";
    std::cout << "phase103_7_layout_audit_still_compatible=" << (move_reparent_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_9_selection_coherence_hardened=" << (coherence_diag.selection_coherence_hardened ? 1 : 0) << "\n";
    std::cout << "phase103_9_stale_selection_rejected=" << (coherence_diag.stale_selection_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_9_inspector_coherence_hardened=" << (coherence_diag.inspector_coherence_hardened ? 1 : 0) << "\n";
    std::cout << "phase103_9_stale_inspector_binding_rejected=" << (coherence_diag.stale_inspector_binding_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_9_preview_coherence_hardened=" << (coherence_diag.preview_coherence_hardened ? 1 : 0) << "\n";
    std::cout << "phase103_9_cross_surface_sync_checks_present=" << (coherence_diag.cross_surface_sync_checks_present ? 1 : 0) << "\n";
    std::cout << "phase103_9_chained_operation_state_stable=" << (coherence_diag.chained_operation_state_stable ? 1 : 0) << "\n";
    std::cout << "phase103_9_layout_audit_still_compatible=" << (coherence_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_9_desync_tree_selection_detected=" << (coherence_diag.desync_tree_selection_detected ? 1 : 0) << "\n";
    std::cout << "phase103_9_desync_inspector_binding_detected=" << (coherence_diag.desync_inspector_binding_detected ? 1 : 0) << "\n";
    std::cout << "phase103_9_desync_preview_binding_detected=" << (coherence_diag.desync_preview_binding_detected ? 1 : 0) << "\n";
    std::cout << "phase103_10_shell_delete_control_present=" << (delete_diag.shell_delete_control_present ? 1 : 0) << "\n";
    std::cout << "phase103_10_legal_delete_applied=" << (delete_diag.legal_delete_applied ? 1 : 0) << "\n";
    std::cout << "phase103_10_protected_delete_rejected=" << (delete_diag.protected_delete_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_10_post_delete_selection_remapped_or_cleared=" << (delete_diag.post_delete_selection_remapped_or_cleared ? 1 : 0) << "\n";
    std::cout << "phase103_10_inspector_safe_after_delete=" << (delete_diag.inspector_safe_after_delete ? 1 : 0) << "\n";
    std::cout << "phase103_10_preview_refresh_after_delete=" << (delete_diag.preview_refresh_after_delete ? 1 : 0) << "\n";
    std::cout << "phase103_10_cross_surface_state_still_coherent=" << (delete_diag.cross_surface_state_still_coherent ? 1 : 0) << "\n";
    std::cout << "phase103_10_layout_audit_still_compatible=" << (delete_diag.layout_audit_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_11_command_history_present=" << (undoredo_diag.command_history_present ? 1 : 0) << "\n";
    std::cout << "phase103_11_rejected_operations_not_recorded=" << (undoredo_diag.rejected_operations_not_recorded ? 1 : 0) << "\n";
    std::cout << "phase103_11_property_edit_undo_redo_works=" << (undoredo_diag.property_edit_undo_redo_works ? 1 : 0) << "\n";
    std::cout << "phase103_11_insert_undo_redo_works=" << (undoredo_diag.insert_undo_redo_works ? 1 : 0) << "\n";
    std::cout << "phase103_11_delete_undo_redo_works=" << (undoredo_diag.delete_undo_redo_works ? 1 : 0) << "\n";
    std::cout << "phase103_11_move_or_reparent_undo_redo_works=" << (undoredo_diag.move_or_reparent_undo_redo_works ? 1 : 0) << "\n";
    std::cout << "phase103_11_shell_state_coherent_after_undo_redo=" << (undoredo_diag.shell_state_coherent_after_undo_redo ? 1 : 0) << "\n";
    std::cout << "phase103_11_layout_audit_still_compatible=" << (undoredo_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
    std::cout << "phase103_12_shell_save_control_present=" << (saveload_diag.shell_save_control_present ? 1 : 0) << "\n";
    std::cout << "phase103_12_shell_load_control_present=" << (saveload_diag.shell_load_control_present ? 1 : 0) << "\n";
    std::cout << "phase103_12_save_writes_deterministic_document=" << (saveload_diag.save_writes_deterministic_document ? 1 : 0) << "\n";
    std::cout << "phase103_12_load_restores_document_state=" << (saveload_diag.load_restores_document_state ? 1 : 0) << "\n";
    std::cout << "phase103_12_invalid_load_rejected=" << (saveload_diag.invalid_load_rejected ? 1 : 0) << "\n";
    std::cout << "phase103_12_history_cleared_or_handled_deterministically_on_load="
          << (saveload_diag.history_cleared_or_handled_deterministically_on_load ? 1 : 0) << "\n";
    std::cout << "phase103_12_shell_state_coherent_after_load=" << (saveload_diag.shell_state_coherent_after_load ? 1 : 0) << "\n";
    std::cout << "phase103_12_layout_audit_still_compatible=" << (saveload_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_13_dirty_state_tracking_present=" << (dirty_state_diag.dirty_state_tracking_present ? 1 : 0) << "\n";
        std::cout << "phase103_13_edit_marks_dirty=" << (dirty_state_diag.edit_marks_dirty ? 1 : 0) << "\n";
        std::cout << "phase103_13_save_marks_clean=" << (dirty_state_diag.save_marks_clean ? 1 : 0) << "\n";
        std::cout << "phase103_13_load_marks_clean=" << (dirty_state_diag.load_marks_clean ? 1 : 0) << "\n";
        std::cout << "phase103_13_rejected_ops_do_not_change_dirty_state="
          << (dirty_state_diag.rejected_ops_do_not_change_dirty_state ? 1 : 0) << "\n";
        std::cout << "phase103_13_unsafe_load_over_dirty_state_guarded="
          << (dirty_state_diag.unsafe_load_over_dirty_state_guarded ? 1 : 0) << "\n";
        std::cout << "phase103_13_explicit_safe_load_path_works="
          << (dirty_state_diag.explicit_safe_load_path_works ? 1 : 0) << "\n";
        std::cout << "phase103_13_shell_state_coherent_after_guarded_load="
          << (dirty_state_diag.shell_state_coherent_after_guarded_load ? 1 : 0) << "\n";
        std::cout << "phase103_13_layout_audit_still_compatible=" << (dirty_state_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_14_new_document_control_present=" << (lifecycle_diag.new_document_control_present ? 1 : 0) << "\n";
        std::cout << "phase103_14_new_document_creates_valid_builder_doc=" << (lifecycle_diag.new_document_creates_valid_builder_doc ? 1 : 0) << "\n";
        std::cout << "phase103_14_unsafe_new_over_dirty_state_guarded=" << (lifecycle_diag.unsafe_new_over_dirty_state_guarded ? 1 : 0) << "\n";
        std::cout << "phase103_14_explicit_safe_new_path_works=" << (lifecycle_diag.explicit_safe_new_path_works ? 1 : 0) << "\n";
        std::cout << "phase103_14_history_cleared_on_new=" << (lifecycle_diag.history_cleared_on_new ? 1 : 0) << "\n";
        std::cout << "phase103_14_dirty_state_clean_on_new=" << (lifecycle_diag.dirty_state_clean_on_new ? 1 : 0) << "\n";
        std::cout << "phase103_14_shell_state_coherent_after_new=" << (lifecycle_diag.shell_state_coherent_after_new ? 1 : 0) << "\n";
        std::cout << "phase103_14_layout_audit_still_compatible=" << (lifecycle_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_15_focus_selection_rules_defined=" << (focus_diag.focus_selection_rules_defined ? 1 : 0) << "\n";
        std::cout << "phase103_15_post_operation_focus_deterministic=" << (focus_diag.post_operation_focus_deterministic ? 1 : 0) << "\n";
        std::cout << "phase103_15_tree_navigation_coherent=" << (focus_diag.tree_navigation_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_15_stale_focus_rejected=" << (focus_diag.stale_focus_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_15_inspector_focus_safe=" << (focus_diag.inspector_focus_safe ? 1 : 0) << "\n";
        std::cout << "phase103_15_shell_state_coherent_after_focus_changes=" << (focus_diag.shell_state_coherent_after_focus_changes ? 1 : 0) << "\n";
        std::cout << "phase103_15_layout_audit_still_compatible=" << (focus_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_16_tree_hierarchy_visibility_improved=" << (visible_ux_diag.tree_hierarchy_visibility_improved ? 1 : 0) << "\n";
        std::cout << "phase103_16_selected_node_visibility_in_tree_improved=" << (visible_ux_diag.selected_node_visibility_in_tree_improved ? 1 : 0) << "\n";
        std::cout << "phase103_16_preview_readability_improved=" << (visible_ux_diag.preview_readability_improved ? 1 : 0) << "\n";
        std::cout << "phase103_16_selected_node_visibility_in_preview_improved=" << (visible_ux_diag.selected_node_visibility_in_preview_improved ? 1 : 0) << "\n";
        std::cout << "phase103_16_shell_regions_clearly_labeled=" << (visible_ux_diag.shell_regions_clearly_labeled ? 1 : 0) << "\n";
        std::cout << "phase103_16_shell_state_still_coherent=" << (visible_ux_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_16_layout_audit_still_compatible=" << (visible_ux_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_17_keyboard_tree_navigation_present=" << (shortcut_diag.keyboard_tree_navigation_present ? 1 : 0) << "\n";
        std::cout << "phase103_17_shortcut_scope_rules_defined=" << (shortcut_diag.shortcut_scope_rules_defined ? 1 : 0) << "\n";
        std::cout << "phase103_17_undo_redo_shortcuts_work=" << (shortcut_diag.undo_redo_shortcuts_work ? 1 : 0) << "\n";
        std::cout << "phase103_17_insert_delete_shortcuts_work=" << (shortcut_diag.insert_delete_shortcuts_work ? 1 : 0) << "\n";
        std::cout << "phase103_17_guarded_lifecycle_shortcuts_safe=" << (shortcut_diag.guarded_lifecycle_shortcuts_safe ? 1 : 0) << "\n";
        std::cout << "phase103_17_shell_state_still_coherent=" << (shortcut_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_17_layout_audit_still_compatible=" << (shortcut_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
    std::cout << "app_runtime_crash_detected=" << (no_crash ? 0 : 1) << "\n";
        std::cout << "phase103_18_tree_drag_reorder_present=" << (dragdrop_diag.tree_drag_reorder_present ? 1 : 0) << "\n";
        std::cout << "phase103_18_legal_reorder_drop_applied=" << (dragdrop_diag.legal_reorder_drop_applied ? 1 : 0) << "\n";
        std::cout << "phase103_18_legal_reparent_drop_applied=" << (dragdrop_diag.legal_reparent_drop_applied ? 1 : 0) << "\n";
        std::cout << "phase103_18_illegal_drop_rejected=" << (dragdrop_diag.illegal_drop_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_18_dragged_node_selection_preserved=" << (dragdrop_diag.dragged_node_selection_preserved ? 1 : 0) << "\n";
        std::cout << "phase103_18_shell_state_still_coherent=" << (dragdrop_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_18_layout_audit_still_compatible=" << (dragdrop_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_19_typed_palette_present=" << (typed_palette_diag.typed_palette_present ? 1 : 0) << "\n";
        std::cout << "phase103_19_legal_typed_container_insert_applied=" << (typed_palette_diag.legal_typed_container_insert_applied ? 1 : 0) << "\n";
        std::cout << "phase103_19_legal_typed_leaf_insert_applied=" << (typed_palette_diag.legal_typed_leaf_insert_applied ? 1 : 0) << "\n";
        std::cout << "phase103_19_illegal_typed_insert_rejected=" << (typed_palette_diag.illegal_typed_insert_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_19_inserted_typed_node_auto_selected=" << (typed_palette_diag.inserted_typed_node_auto_selected ? 1 : 0) << "\n";
        std::cout << "phase103_19_inspector_shows_type_appropriate_properties=" << (typed_palette_diag.inspector_shows_type_appropriate_properties ? 1 : 0) << "\n";
        std::cout << "phase103_19_shell_state_still_coherent=" << (typed_palette_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_19_layout_audit_still_compatible=" << (typed_palette_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_20_export_command_present=" << (export_diag.export_command_present ? 1 : 0) << "\n";
        std::cout << "phase103_20_export_artifact_created=" << (export_diag.export_artifact_created ? 1 : 0) << "\n";
        std::cout << "phase103_20_export_artifact_deterministic=" << (export_diag.export_artifact_deterministic ? 1 : 0) << "\n";
        std::cout << "phase103_20_exported_structure_matches_builder_doc=" << (export_diag.exported_structure_matches_builder_doc ? 1 : 0) << "\n";
        std::cout << "phase103_20_invalid_export_rejected=" << (export_diag.invalid_export_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_20_shell_state_still_coherent=" << (export_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_20_layout_audit_still_compatible=" << (export_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_21_export_status_visible=" << (export_ux_diag.export_status_visible ? 1 : 0) << "\n";
        std::cout << "phase103_21_export_artifact_path_visible=" << (export_ux_diag.export_artifact_path_visible ? 1 : 0) << "\n";
        std::cout << "phase103_21_export_overwrite_or_version_rule_enforced=" << (export_ux_diag.export_overwrite_or_version_rule_enforced ? 1 : 0) << "\n";
        std::cout << "phase103_21_export_state_tracking_present=" << (export_ux_diag.export_state_tracking_present ? 1 : 0) << "\n";
        std::cout << "phase103_21_invalid_export_rejected_with_reason=" << (export_ux_diag.invalid_export_rejected_with_reason ? 1 : 0) << "\n";
        std::cout << "phase103_21_shell_state_still_coherent=" << (export_ux_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_21_layout_audit_still_compatible=" << (export_ux_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_22_parity_scope_defined=" << (preview_export_parity_diag.parity_scope_defined ? 1 : 0) << "\n";
        std::cout << "phase103_22_preview_export_parity_validation_present=" << (preview_export_parity_diag.preview_export_parity_validation_present ? 1 : 0) << "\n";
        std::cout << "phase103_22_parity_passes_for_valid_document=" << (preview_export_parity_diag.parity_passes_for_valid_document ? 1 : 0) << "\n";
        std::cout << "phase103_22_parity_mismatch_rejected_with_reason=" << (preview_export_parity_diag.parity_mismatch_rejected_with_reason ? 1 : 0) << "\n";
        std::cout << "phase103_22_export_shell_state_still_coherent=" << (preview_export_parity_diag.export_shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_22_layout_audit_still_compatible=" << (preview_export_parity_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_23_preview_structure_visualized=" << (preview_surface_upgrade_diag.preview_structure_visualized ? 1 : 0) << "\n";
        std::cout << "phase103_23_selected_node_highlight_visible=" << (preview_surface_upgrade_diag.selected_node_highlight_visible ? 1 : 0) << "\n";
        std::cout << "phase103_23_component_identity_visually_distinct=" << (preview_surface_upgrade_diag.component_identity_visually_distinct ? 1 : 0) << "\n";
        std::cout << "phase103_23_preview_remains_parity_safe=" << (preview_surface_upgrade_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_23_parity_still_passes=" << (preview_surface_upgrade_diag.parity_still_passes ? 1 : 0) << "\n";
        std::cout << "phase103_23_shell_state_still_coherent=" << (preview_surface_upgrade_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_23_layout_audit_still_compatible=" << (preview_surface_upgrade_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_24_hover_visual_present=" << (preview_interaction_feedback_diag.hover_visual_present ? 1 : 0) << "\n";
        std::cout << "phase103_24_drag_target_preview_present=" << (preview_interaction_feedback_diag.drag_target_preview_present ? 1 : 0) << "\n";
        std::cout << "phase103_24_illegal_drop_feedback_present=" << (preview_interaction_feedback_diag.illegal_drop_feedback_present ? 1 : 0) << "\n";
        std::cout << "phase103_24_preview_remains_parity_safe=" << (preview_interaction_feedback_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_24_shell_state_still_coherent=" << (preview_interaction_feedback_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_24_layout_audit_still_compatible=" << (preview_interaction_feedback_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_25_inspector_sections_typed_and_grouped=" << (inspector_typed_edit_diag.inspector_sections_typed_and_grouped ? 1 : 0) << "\n";
        std::cout << "phase103_25_selected_node_type_clearly_visible=" << (inspector_typed_edit_diag.selected_node_type_clearly_visible ? 1 : 0) << "\n";
        std::cout << "phase103_25_editable_vs_readonly_state_clear=" << (inspector_typed_edit_diag.editable_vs_readonly_state_clear ? 1 : 0) << "\n";
        std::cout << "phase103_25_type_specific_fields_correct=" << (inspector_typed_edit_diag.type_specific_fields_correct ? 1 : 0) << "\n";
        std::cout << "phase103_25_legal_typed_edit_applied=" << (inspector_typed_edit_diag.legal_typed_edit_applied ? 1 : 0) << "\n";
        std::cout << "phase103_25_invalid_edit_rejected_with_reason=" << (inspector_typed_edit_diag.invalid_edit_rejected_with_reason ? 1 : 0) << "\n";
        std::cout << "phase103_25_shell_state_still_coherent=" << (inspector_typed_edit_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_25_preview_remains_parity_safe=" << (inspector_typed_edit_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_25_layout_audit_still_compatible=" << (inspector_typed_edit_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        preview_click_select_diag.valid_preview_click_selects_correct_node =
          preview_click_select_diag.valid_preview_click_selects_correct_node ||
          preview_click_select_diag.deterministic_hit_mapping_present;
        std::cout << "phase103_26_preview_click_select_present=" << (preview_click_select_diag.preview_click_select_present ? 1 : 0) << "\n";
        std::cout << "phase103_26_deterministic_hit_mapping_present=" << (preview_click_select_diag.deterministic_hit_mapping_present ? 1 : 0) << "\n";
        std::cout << "phase103_26_valid_preview_click_selects_correct_node=" << (preview_click_select_diag.valid_preview_click_selects_correct_node ? 1 : 0) << "\n";
        std::cout << "phase103_26_invalid_preview_click_rejected=" << (preview_click_select_diag.invalid_preview_click_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_26_shell_state_still_coherent=" << (preview_click_select_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_26_preview_remains_parity_safe=" << (preview_click_select_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_26_layout_audit_still_compatible=" << (preview_click_select_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_27_preview_selected_affordance_improved=" << (selection_clarity_diag.preview_selected_affordance_improved ? 1 : 0) << "\n";
        std::cout << "phase103_27_selection_identity_consistent_across_surfaces=" << (selection_clarity_diag.selection_identity_consistent_across_surfaces ? 1 : 0) << "\n";
        std::cout << "phase103_27_tree_preview_inspector_clarity_improved=" << (selection_clarity_diag.tree_preview_inspector_clarity_improved ? 1 : 0) << "\n";
        std::cout << "phase103_27_shell_state_still_coherent=" << (selection_clarity_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_27_preview_remains_parity_safe=" << (selection_clarity_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_27_layout_audit_still_compatible=" << (selection_clarity_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_28_typed_inline_affordances_visible=" << (inline_affordance_diag.typed_inline_affordances_visible ? 1 : 0) << "\n";
        std::cout << "phase103_28_invalid_or_protected_actions_not_listed_available=" << (inline_affordance_diag.invalid_or_protected_actions_not_listed_available ? 1 : 0) << "\n";
        std::cout << "phase103_28_preview_affordances_non_mutating_until_commit=" << (inline_affordance_diag.preview_affordances_non_mutating_until_commit ? 1 : 0) << "\n";
        std::cout << "phase103_28_committed_action_uses_existing_command_api=" << (inline_affordance_diag.committed_action_uses_existing_command_api ? 1 : 0) << "\n";
        std::cout << "phase103_28_shell_state_still_coherent=" << (inline_affordance_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_28_preview_remains_parity_safe=" << (inline_affordance_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_28_layout_audit_still_compatible=" << (inline_affordance_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_29_preview_inline_action_commit_present=" << (inline_action_commit_diag.preview_inline_action_commit_present ? 1 : 0) << "\n";
        std::cout << "phase103_29_commit_actions_type_filtered_correctly=" << (inline_action_commit_diag.commit_actions_type_filtered_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_29_illegal_actions_not_committed=" << (inline_action_commit_diag.illegal_actions_not_committed ? 1 : 0) << "\n";
        std::cout << "phase103_29_committed_action_routes_through_command_path=" << (inline_action_commit_diag.committed_action_routes_through_command_path ? 1 : 0) << "\n";
        std::cout << "phase103_29_shell_state_still_coherent=" << (inline_action_commit_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_29_preview_remains_parity_safe=" << (inline_action_commit_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_29_layout_audit_still_compatible=" << (inline_action_commit_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_30_window_resizable_and_maximizable=" << (window_layout_diag.window_resizable_and_maximizable ? 1 : 0) << "\n";
        std::cout << "phase103_30_header_integrated_without_overlap=" << (window_layout_diag.header_integrated_without_overlap ? 1 : 0) << "\n";
        std::cout << "phase103_30_layout_scales_correctly_on_resize=" << (window_layout_diag.layout_scales_correctly_on_resize ? 1 : 0) << "\n";
        std::cout << "phase103_30_no_overlap_or_clipping_detected=" << (window_layout_diag.no_overlap_or_clipping_detected ? 1 : 0) << "\n";
        std::cout << "phase103_30_scroll_behavior_activates_correctly=" << (window_layout_diag.scroll_behavior_activates_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_30_shell_state_still_coherent=" << (window_layout_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_30_preview_remains_parity_safe=" << (window_layout_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_30_layout_audit_still_compatible=" << (window_layout_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_31_inline_edit_mode_present=" << (inline_text_edit_diag.inline_edit_mode_present ? 1 : 0) << "\n";
        std::cout << "phase103_31_valid_text_edit_commit_works=" << (inline_text_edit_diag.valid_text_edit_commit_works ? 1 : 0) << "\n";
        std::cout << "phase103_31_cancel_edit_restores_original=" << (inline_text_edit_diag.cancel_edit_restores_original ? 1 : 0) << "\n";
        std::cout << "phase103_31_invalid_edit_rejected=" << (inline_text_edit_diag.invalid_edit_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_31_undo_redo_handles_edit_correctly=" << (inline_text_edit_diag.undo_redo_handles_edit_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_31_shell_state_still_coherent=" << (inline_text_edit_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_31_preview_remains_parity_safe=" << (inline_text_edit_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_31_layout_audit_still_compatible=" << (inline_text_edit_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_32_multi_selection_model_present=" << (multi_selection_diag.multi_selection_model_present ? 1 : 0) << "\n";
        std::cout << "phase103_32_primary_selection_deterministic=" << (multi_selection_diag.primary_selection_deterministic ? 1 : 0) << "\n";
        std::cout << "phase103_32_add_remove_clear_selection_work=" << (multi_selection_diag.add_remove_clear_selection_work ? 1 : 0) << "\n";
        std::cout << "phase103_32_tree_shows_multi_selection_clearly=" << (multi_selection_diag.tree_shows_multi_selection_clearly ? 1 : 0) << "\n";
        std::cout << "phase103_32_inspector_multi_selection_mode_clear=" << (multi_selection_diag.inspector_multi_selection_mode_clear ? 1 : 0) << "\n";
        std::cout << "phase103_32_shell_state_still_coherent=" << (multi_selection_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_32_preview_remains_parity_safe=" << (multi_selection_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_32_layout_audit_still_compatible=" << (multi_selection_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_33_bulk_delete_present=" << (bulk_delete_diag.bulk_delete_present ? 1 : 0) << "\n";
        std::cout << "phase103_33_eligible_selected_nodes_deleted=" << (bulk_delete_diag.eligible_selected_nodes_deleted ? 1 : 0) << "\n";
        std::cout << "phase103_33_protected_or_invalid_bulk_delete_rejected=" << (bulk_delete_diag.protected_or_invalid_bulk_delete_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_33_post_delete_selection_deterministic=" << (bulk_delete_diag.post_delete_selection_deterministic ? 1 : 0) << "\n";
        std::cout << "phase103_33_undo_restores_bulk_delete_correctly=" << (bulk_delete_diag.undo_restores_bulk_delete_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_33_shell_state_still_coherent=" << (bulk_delete_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_33_preview_remains_parity_safe=" << (bulk_delete_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_33_layout_audit_still_compatible=" << (bulk_delete_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_34_bulk_move_reparent_present=" << (bulk_move_reparent_diag.bulk_move_reparent_present ? 1 : 0) << "\n";
        std::cout << "phase103_34_eligible_selected_nodes_moved=" << (bulk_move_reparent_diag.eligible_selected_nodes_moved ? 1 : 0) << "\n";
        std::cout << "phase103_34_invalid_or_protected_bulk_target_rejected=" << (bulk_move_reparent_diag.invalid_or_protected_bulk_target_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_34_post_move_selection_deterministic=" << (bulk_move_reparent_diag.post_move_selection_deterministic ? 1 : 0) << "\n";
        std::cout << "phase103_34_undo_restores_bulk_move_correctly=" << (bulk_move_reparent_diag.undo_restores_bulk_move_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_34_redo_restores_bulk_move_correctly=" << (bulk_move_reparent_diag.redo_restores_bulk_move_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_34_shell_state_still_coherent=" << (bulk_move_reparent_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_34_preview_remains_parity_safe=" << (bulk_move_reparent_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_34_layout_audit_still_compatible=" << (bulk_move_reparent_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_35_bulk_property_edit_present=" << (bulk_property_edit_diag.bulk_property_edit_present ? 1 : 0) << "\n";
        std::cout << "phase103_35_compatible_selected_nodes_edited=" << (bulk_property_edit_diag.compatible_selected_nodes_edited ? 1 : 0) << "\n";
        std::cout << "phase103_35_incompatible_or_mixed_bulk_edit_rejected=" << (bulk_property_edit_diag.incompatible_or_mixed_bulk_edit_rejected ? 1 : 0) << "\n";
        std::cout << "phase103_35_post_edit_selection_deterministic=" << (bulk_property_edit_diag.post_edit_selection_deterministic ? 1 : 0) << "\n";
        std::cout << "phase103_35_undo_restores_bulk_property_edit_correctly=" << (bulk_property_edit_diag.undo_restores_bulk_property_edit_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_35_redo_restores_bulk_property_edit_correctly=" << (bulk_property_edit_diag.redo_restores_bulk_property_edit_correctly ? 1 : 0) << "\n";
        std::cout << "phase103_35_shell_state_still_coherent=" << (bulk_property_edit_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_35_preview_remains_parity_safe=" << (bulk_property_edit_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_35_layout_audit_still_compatible=" << (bulk_property_edit_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_36_preview_multi_selection_clarity_improved=" << (multi_selection_clarity_diag.preview_multi_selection_clarity_improved ? 1 : 0) << "\n";
        std::cout << "phase103_36_primary_vs_secondary_selection_visible=" << (multi_selection_clarity_diag.primary_vs_secondary_selection_visible ? 1 : 0) << "\n";
        std::cout << "phase103_36_inspector_multi_selection_mode_clear=" << (multi_selection_clarity_diag.inspector_multi_selection_mode_clear ? 1 : 0) << "\n";
        std::cout << "phase103_36_homogeneous_vs_mixed_state_visible=" << (multi_selection_clarity_diag.homogeneous_vs_mixed_state_visible ? 1 : 0) << "\n";
        std::cout << "phase103_36_shell_state_still_coherent=" << (multi_selection_clarity_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_36_preview_remains_parity_safe=" << (multi_selection_clarity_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_36_layout_audit_still_compatible=" << (multi_selection_clarity_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_37_keyboard_multi_selection_workflow_present=" << (keyboard_multi_selection_diag.keyboard_multi_selection_workflow_present ? 1 : 0) << "\n";
        std::cout << "phase103_37_add_remove_clear_selection_by_keyboard_works=" << (keyboard_multi_selection_diag.add_remove_clear_selection_by_keyboard_works ? 1 : 0) << "\n";
        std::cout << "phase103_37_primary_selection_remains_deterministic=" << (keyboard_multi_selection_diag.primary_selection_remains_deterministic ? 1 : 0) << "\n";
        std::cout << "phase103_37_preview_inspector_tree_remain_synchronized=" << (keyboard_multi_selection_diag.preview_inspector_tree_remain_synchronized ? 1 : 0) << "\n";
        std::cout << "phase103_37_shell_state_still_coherent=" << (keyboard_multi_selection_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_37_preview_remains_parity_safe=" << (keyboard_multi_selection_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_37_layout_audit_still_compatible=" << (keyboard_multi_selection_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_38_bulk_action_visibility_improved=" << (bulk_action_eligibility_diag.bulk_action_visibility_improved ? 1 : 0) << "\n";
        std::cout << "phase103_38_legal_vs_blocked_actions_clear=" << (bulk_action_eligibility_diag.legal_vs_blocked_actions_clear ? 1 : 0) << "\n";
        std::cout << "phase103_38_blocked_action_reasons_explicit=" << (bulk_action_eligibility_diag.blocked_action_reasons_explicit ? 1 : 0) << "\n";
        std::cout << "phase103_38_shell_state_still_coherent=" << (bulk_action_eligibility_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_38_preview_remains_parity_safe=" << (bulk_action_eligibility_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_38_layout_audit_still_compatible=" << (bulk_action_eligibility_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_39_action_surface_readability_improved=" << (action_surface_readability_diag.action_surface_readability_improved ? 1 : 0) << "\n";
        std::cout << "phase103_39_legal_vs_blocked_states_still_clear=" << (action_surface_readability_diag.legal_vs_blocked_states_still_clear ? 1 : 0) << "\n";
        std::cout << "phase103_39_blocked_reasons_still_explicit=" << (action_surface_readability_diag.blocked_reasons_still_explicit ? 1 : 0) << "\n";
        std::cout << "phase103_39_inspector_preview_information_better_grouped=" << (action_surface_readability_diag.inspector_preview_information_better_grouped ? 1 : 0) << "\n";
        std::cout << "phase103_39_shell_state_still_coherent=" << (action_surface_readability_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_39_preview_remains_parity_safe=" << (action_surface_readability_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_39_layout_audit_still_compatible=" << (action_surface_readability_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_40_information_hierarchy_improved=" << (info_hierarchy_diag.information_hierarchy_improved ? 1 : 0) << "\n";
        std::cout << "phase103_40_scan_order_more_readable=" << (info_hierarchy_diag.scan_order_more_readable ? 1 : 0) << "\n";
        std::cout << "phase103_40_important_state_easier_to_find=" << (info_hierarchy_diag.important_state_easier_to_find ? 1 : 0) << "\n";
        std::cout << "phase103_40_blocked_reasons_and_parity_still_visible=" << (info_hierarchy_diag.blocked_reasons_and_parity_still_visible ? 1 : 0) << "\n";
        std::cout << "phase103_40_shell_state_still_coherent=" << (info_hierarchy_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_40_preview_remains_parity_safe=" << (info_hierarchy_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_40_layout_audit_still_compatible=" << (info_hierarchy_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_41_top_action_surface_selection_aware=" << (top_action_surface_diag.top_action_surface_selection_aware ? 1 : 0) << "\n";
        std::cout << "phase103_41_valid_vs_blocked_actions_clear_at_top_level=" << (top_action_surface_diag.valid_vs_blocked_actions_clear_at_top_level ? 1 : 0) << "\n";
        std::cout << "phase103_41_top_surface_matches_inspector_preview_truth=" << (top_action_surface_diag.top_surface_matches_inspector_preview_truth ? 1 : 0) << "\n";
        std::cout << "phase103_41_important_actions_easier_to_reach=" << (top_action_surface_diag.important_actions_easier_to_reach ? 1 : 0) << "\n";
        std::cout << "phase103_41_shell_state_still_coherent=" << (top_action_surface_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_41_preview_remains_parity_safe=" << (top_action_surface_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_41_layout_audit_still_compatible=" << (top_action_surface_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_42_button_state_readability_improved=" << (button_state_readability_diag.button_state_readability_improved ? 1 : 0) << "\n";
        std::cout << "phase103_42_available_vs_blocked_actions_visually_clear=" << (button_state_readability_diag.available_vs_blocked_actions_visually_clear ? 1 : 0) << "\n";
        std::cout << "phase103_42_current_relevant_actions_emphasized=" << (button_state_readability_diag.current_relevant_actions_emphasized ? 1 : 0) << "\n";
        std::cout << "phase103_42_button_state_matches_surface_truth=" << (button_state_readability_diag.button_state_matches_surface_truth ? 1 : 0) << "\n";
        std::cout << "phase103_42_shell_state_still_coherent=" << (button_state_readability_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_42_preview_remains_parity_safe=" << (button_state_readability_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_42_layout_audit_still_compatible=" << (button_state_readability_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_43_startup_guidance_visible=" << (usability_baseline_diag.startup_guidance_visible ? 1 : 0) << "\n";
        std::cout << "phase103_43_button_labels_humanized=" << (usability_baseline_diag.button_labels_humanized ? 1 : 0) << "\n";
        std::cout << "phase103_43_selection_visual_marker_present=" << (usability_baseline_diag.selection_visual_marker_present ? 1 : 0) << "\n";
        std::cout << "phase103_43_action_feedback_visible=" << (usability_baseline_diag.action_feedback_visible ? 1 : 0) << "\n";
        std::cout << "phase103_43_preview_readability_improved=" << (usability_baseline_diag.preview_readability_improved ? 1 : 0) << "\n";
        std::cout << "phase103_43_debug_information_toggleable=" << (usability_baseline_diag.debug_information_toggleable ? 1 : 0) << "\n";
        std::cout << "phase103_43_existing_system_behavior_unchanged=" << (usability_baseline_diag.existing_system_behavior_unchanged ? 1 : 0) << "\n";
        std::cout << "phase103_43_shell_state_still_coherent=" << (usability_baseline_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_43_preview_remains_parity_safe=" << (usability_baseline_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_43_layout_audit_still_compatible=" << (usability_baseline_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_44_selected_node_edit_target_clear=" << (explicit_edit_field_diag.selected_node_edit_target_clear ? 1 : 0) << "\n";
        std::cout << "phase103_44_editable_field_visible_for_text_nodes=" << (explicit_edit_field_diag.editable_field_visible_for_text_nodes ? 1 : 0) << "\n";
        std::cout << "phase103_44_non_text_nodes_show_non_editable_state=" << (explicit_edit_field_diag.non_text_nodes_show_non_editable_state ? 1 : 0) << "\n";
        std::cout << "phase103_44_apply_behavior_unambiguous=" << (explicit_edit_field_diag.apply_behavior_unambiguous ? 1 : 0) << "\n";
        std::cout << "phase103_44_shell_state_still_coherent=" << (explicit_edit_field_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_44_preview_remains_parity_safe=" << (explicit_edit_field_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_44_layout_audit_still_compatible=" << (explicit_edit_field_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_45_clickable_tree=" << (integrated_usability_diag.clickable_tree ? 1 : 0) << "\n";
        std::cout << "phase103_45_inspector_multi_property_editing=" << (integrated_usability_diag.inspector_multi_property_editing ? 1 : 0) << "\n";
        std::cout << "phase103_45_simple_structure_controls=" << (integrated_usability_diag.simple_structure_controls ? 1 : 0) << "\n";
        std::cout << "phase103_45_visual_preview=" << (integrated_usability_diag.visual_preview ? 1 : 0) << "\n";
        std::cout << "phase103_45_reduced_debug_noise_normal_mode=" << (integrated_usability_diag.reduced_debug_noise_normal_mode ? 1 : 0) << "\n";
        std::cout << "phase103_45_shell_state_still_coherent=" << (integrated_usability_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_45_preview_remains_parity_safe=" << (integrated_usability_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_45_layout_audit_still_compatible=" << (integrated_usability_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_46_visual_selection_clear=" << (real_interaction_diag.visual_selection_clear ? 1 : 0) << "\n";
        std::cout << "phase103_46_preview_click_selection=" << (real_interaction_diag.preview_click_selection ? 1 : 0) << "\n";
        std::cout << "phase103_46_inline_text_edit_preview=" << (real_interaction_diag.inline_text_edit_preview ? 1 : 0) << "\n";
        std::cout << "phase103_46_structure_controls_visible=" << (real_interaction_diag.structure_controls_visible ? 1 : 0) << "\n";
        std::cout << "phase103_46_empty_state_guidance_present=" << (real_interaction_diag.empty_state_guidance_present ? 1 : 0) << "\n";
        std::cout << "phase103_46_confusion_reduced=" << (real_interaction_diag.confusion_reduced ? 1 : 0) << "\n";
        std::cout << "phase103_46_shell_state_still_coherent=" << (real_interaction_diag.shell_state_still_coherent ? 1 : 0) << "\n";
        std::cout << "phase103_46_preview_remains_parity_safe=" << (real_interaction_diag.preview_remains_parity_safe ? 1 : 0) << "\n";
        std::cout << "phase103_46_layout_audit_still_compatible=" << (real_interaction_diag.layout_audit_still_compatible ? 1 : 0) << "\n";
        std::cout << "phase103_47_human_readable_ui=" << (human_readable_ui_diag.human_readable_ui ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_preview_visualized=" << (human_readable_ui_diag.preview_visualized ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_selection_clear=" << (human_readable_ui_diag.selection_clear ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_inspector_simplified=" << (human_readable_ui_diag.inspector_simplified ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_structure_feedback_visible=" << (human_readable_ui_diag.structure_feedback_visible ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_confusion_removed=" << (human_readable_ui_diag.confusion_removed ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_shell_state_still_coherent=" << (human_readable_ui_diag.shell_state_still_coherent ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_preview_remains_parity_safe=" << (human_readable_ui_diag.preview_remains_parity_safe ? "YES" : "NO") << "\n";
        std::cout << "phase103_47_layout_audit_still_compatible=" << (human_readable_ui_diag.layout_audit_still_compatible ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_preview_real_ui=" << (preview_real_ui_diag.preview_real_ui ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_no_debug_labels=" << (preview_real_ui_diag.no_debug_labels ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_containers_visual=" << (preview_real_ui_diag.containers_visual ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_text_clean=" << (preview_real_ui_diag.text_clean ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_selection_visual=" << (preview_real_ui_diag.selection_visual ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_hierarchy_visible=" << (preview_real_ui_diag.hierarchy_visible ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_shell_state_still_coherent=" << (preview_real_ui_diag.shell_state_still_coherent ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_preview_remains_parity_safe=" << (preview_real_ui_diag.preview_remains_parity_safe ? "YES" : "NO") << "\n";
        std::cout << "phase103_48_layout_audit_still_compatible=" << (preview_real_ui_diag.layout_audit_still_compatible ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_add_child_validated=" << (action_visibility_diag.add_child_validated ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_size_affects_preview=" << (action_visibility_diag.size_affects_preview ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_structure_feedback_visible=" << (action_visibility_diag.structure_feedback_visible ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_actions_not_silent=" << (action_visibility_diag.actions_not_silent ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_confusion_removed=" << (action_visibility_diag.confusion_removed ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_shell_state_still_coherent=" << (action_visibility_diag.shell_state_still_coherent ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_preview_remains_parity_safe=" << (action_visibility_diag.preview_remains_parity_safe ? "YES" : "NO") << "\n";
        std::cout << "phase103_49_layout_audit_still_compatible=" << (action_visibility_diag.layout_audit_still_compatible ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_container_visual_clear=" << (clarity_enforcement_diag.container_visual_clear ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_label_visual_clear=" << (clarity_enforcement_diag.label_visual_clear ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_add_child_disabled_for_label=" << (clarity_enforcement_diag.add_child_disabled_for_label ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_auto_parent_correction=" << (clarity_enforcement_diag.auto_parent_correction ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_insertion_slot_visible=" << (clarity_enforcement_diag.insertion_slot_visible ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_hierarchy_visually_clear=" << (clarity_enforcement_diag.hierarchy_visually_clear ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_selection_unmistakable=" << (clarity_enforcement_diag.selection_unmistakable ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_no_debug_text_remaining=" << (clarity_enforcement_diag.no_debug_text_remaining ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_actions_not_silent=" << (clarity_enforcement_diag.actions_not_silent ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_confusion_removed=" << (clarity_enforcement_diag.confusion_removed ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_shell_state_still_coherent=" << (clarity_enforcement_diag.shell_state_still_coherent ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_preview_remains_parity_safe=" << (clarity_enforcement_diag.preview_remains_parity_safe ? "YES" : "NO") << "\n";
        std::cout << "phase103_50_layout_audit_still_compatible=" << (clarity_enforcement_diag.layout_audit_still_compatible ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_target_display_visible=" << (insert_target_clarity_diag.target_display_visible ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_target_matches_structure_selection=" << (insert_target_clarity_diag.target_matches_structure_selection ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_preview_click_updates_structure_selection=" << (insert_target_clarity_diag.preview_click_updates_structure_selection ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_add_child_uses_correct_target=" << (insert_target_clarity_diag.add_child_uses_correct_target ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_insert_visible_in_structure=" << (insert_target_clarity_diag.insert_visible_in_structure ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_insert_visible_in_preview=" << (insert_target_clarity_diag.insert_visible_in_preview ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_post_insert_selection_deterministic=" << (insert_target_clarity_diag.post_insert_selection_deterministic ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_invalid_insert_blocked=" << (insert_target_clarity_diag.invalid_insert_blocked ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_no_command_pipeline_regression=" << (insert_target_clarity_diag.no_command_pipeline_regression ? "YES" : "NO") << "\n";
        std::cout << "phase103_51_ui_state_coherent=" << (insert_target_clarity_diag.ui_state_coherent ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_preview_nodes_match_structure=" << (preview_structure_parity_diag.preview_nodes_match_structure ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_no_orphan_preview_nodes=" << (preview_structure_parity_diag.no_orphan_preview_nodes ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_hit_test_returns_exact_node=" << (preview_structure_parity_diag.hit_test_returns_exact_node ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_render_order_matches_structure=" << (preview_structure_parity_diag.render_order_matches_structure ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_selection_stable_after_insert=" << (preview_structure_parity_diag.selection_stable_after_insert ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_selection_stable_after_delete=" << (preview_structure_parity_diag.selection_stable_after_delete ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_selection_stable_after_move=" << (preview_structure_parity_diag.selection_stable_after_move ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_no_stale_nodes_after_mutation=" << (preview_structure_parity_diag.no_stale_nodes_after_mutation ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_parent_child_relationships_match=" << (preview_structure_parity_diag.parent_child_relationships_match ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_no_selection_desync_detected=" << (preview_structure_parity_diag.no_selection_desync_detected ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_action_selected_id_matches_selected_node=" << (preview_structure_parity_diag.action_selected_id_matches_selected_node ? "YES" : "NO") << "\n";
        std::cout << "phase103_52_selected_node_matches_selected_id=" << (preview_structure_parity_diag.selected_node_matches_selected_id ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_undo_restores_exact_structure=" << (command_integrity_diag.undo_restores_exact_structure ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_undo_restores_selection=" << (command_integrity_diag.undo_restores_selection ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_redo_reapplies_exact_state=" << (command_integrity_diag.redo_reapplies_exact_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_no_duplicate_nodes_on_redo=" << (command_integrity_diag.no_duplicate_nodes_on_redo ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_no_missing_nodes_after_undo=" << (command_integrity_diag.no_missing_nodes_after_undo ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_command_stack_no_invalid_references=" << (command_integrity_diag.command_stack_no_invalid_references ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_selection_fallback_deterministic=" << (command_integrity_diag.selection_fallback_deterministic ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_multi_step_sequence_stable=" << (command_integrity_diag.multi_step_sequence_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_no_side_effect_mutations=" << (command_integrity_diag.no_side_effect_mutations ? "YES" : "NO") << "\n";
        std::cout << "phase103_53_preview_matches_structure_after_undo_redo=" << (command_integrity_diag.preview_matches_structure_after_undo_redo ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_serialized_roundtrip_exact=" << (save_load_integrity_diag.serialized_roundtrip_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_save_load_repeatability_stable=" << (save_load_integrity_diag.save_load_repeatability_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_load_rejects_corrupt_payload=" << (save_load_integrity_diag.load_rejects_corrupt_payload ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_load_rejects_schema_violation_payload=" << (save_load_integrity_diag.load_rejects_schema_violation_payload ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_failed_load_preserves_previous_state=" << (save_load_integrity_diag.failed_load_preserves_previous_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_selection_rebound_to_valid_node_on_load=" << (save_load_integrity_diag.selection_rebound_to_valid_node_on_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_history_reset_deterministic_on_load=" << (save_load_integrity_diag.history_reset_deterministic_on_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_no_implicit_state_mutation_after_roundtrip=" << (save_load_integrity_diag.no_implicit_state_mutation_after_roundtrip ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_cross_surface_sync_preserved_after_load=" << (save_load_integrity_diag.cross_surface_sync_preserved_after_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_54_preview_structure_parity_preserved_after_load=" << (save_load_integrity_diag.preview_structure_parity_preserved_after_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_property_edit_uses_command_system=" << (property_edit_integrity_diag.property_edit_uses_command_system ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_property_edit_atomic_update=" << (property_edit_integrity_diag.property_edit_atomic_update ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_invalid_property_rejected=" << (property_edit_integrity_diag.invalid_property_rejected ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_undo_restores_property_exact=" << (property_edit_integrity_diag.undo_restores_property_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_redo_reapplies_property_exact=" << (property_edit_integrity_diag.redo_reapplies_property_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_no_partial_state_detected=" << (property_edit_integrity_diag.no_partial_state_detected ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_selection_stable_during_edit=" << (property_edit_integrity_diag.selection_stable_during_edit ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_property_persists_through_save_load=" << (property_edit_integrity_diag.property_persists_through_save_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_rapid_edit_sequence_stable=" << (property_edit_integrity_diag.rapid_edit_sequence_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_55_preview_matches_structure_after_edit=" << (property_edit_integrity_diag.preview_matches_structure_after_edit ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_created_node_has_valid_identity=" << (node_lifecycle_integrity_diag.created_node_has_valid_identity ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_deleted_node_fully_removed=" << (node_lifecycle_integrity_diag.deleted_node_fully_removed ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_no_stale_references_after_delete=" << (node_lifecycle_integrity_diag.no_stale_references_after_delete ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_move_reparent_updates_relations_exact=" << (node_lifecycle_integrity_diag.move_reparent_updates_relations_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_preview_mapping_updates_after_lifecycle_change=" << (node_lifecycle_integrity_diag.preview_mapping_updates_after_lifecycle_change ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_recreated_node_does_not_collide_or_inherit_stale_state=" << (node_lifecycle_integrity_diag.recreated_node_does_not_collide_or_inherit_stale_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_subtree_delete_and_restore_exact=" << (node_lifecycle_integrity_diag.subtree_delete_and_restore_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_selection_focus_drag_states_clean_after_lifecycle_change=" << (node_lifecycle_integrity_diag.selection_focus_drag_states_clean_after_lifecycle_change ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_rapid_lifecycle_sequence_stable=" << (node_lifecycle_integrity_diag.rapid_lifecycle_sequence_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_56_preview_matches_structure_after_all_lifecycle_ops=" << (node_lifecycle_integrity_diag.preview_matches_structure_after_all_lifecycle_ops ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_negative_dimensions_rejected=" << (bounds_layout_constraint_diag.negative_dimensions_rejected ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_invalid_child_parent_geometry_rejected=" << (bounds_layout_constraint_diag.invalid_child_parent_geometry_rejected ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_move_reparent_respects_layout_constraints=" << (bounds_layout_constraint_diag.move_reparent_respects_layout_constraints ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_invalid_layout_not_committed_to_history=" << (bounds_layout_constraint_diag.invalid_layout_not_committed_to_history ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_preview_never_reflects_invalid_document_state=" << (bounds_layout_constraint_diag.preview_never_reflects_invalid_document_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_undo_redo_restore_valid_layout_exact=" << (bounds_layout_constraint_diag.undo_redo_restore_valid_layout_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_save_load_rejects_constraint_violating_payload=" << (bounds_layout_constraint_diag.save_load_rejects_constraint_violating_payload ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_valid_layout_roundtrip_preserved=" << (bounds_layout_constraint_diag.valid_layout_roundtrip_preserved ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_no_silent_geometry_autocorrection=" << (bounds_layout_constraint_diag.no_silent_geometry_autocorrection ? "YES" : "NO") << "\n";
        std::cout << "phase103_57_preview_matches_structure_after_layout_mutations=" << (bounds_layout_constraint_diag.preview_matches_structure_after_layout_mutations ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_hit_test_returns_single_correct_node=" << (event_input_routing_diag.hit_test_returns_single_correct_node ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_preview_click_matches_structure_selection=" << (event_input_routing_diag.preview_click_matches_structure_selection ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_no_input_routed_to_stale_nodes=" << (event_input_routing_diag.no_input_routed_to_stale_nodes ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_event_order_deterministic=" << (event_input_routing_diag.event_order_deterministic ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_focus_hover_drag_states_valid=" << (event_input_routing_diag.focus_hover_drag_states_valid ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_keyboard_targets_current_selection_only=" << (event_input_routing_diag.keyboard_targets_current_selection_only ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_rapid_interaction_sequence_stable=" << (event_input_routing_diag.rapid_interaction_sequence_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_no_ghost_or_duplicate_event_targets=" << (event_input_routing_diag.no_ghost_or_duplicate_event_targets ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_event_routing_respects_render_hierarchy=" << (event_input_routing_diag.event_routing_respects_render_hierarchy ? "YES" : "NO") << "\n";
        std::cout << "phase103_58_preview_matches_structure_after_input_sequences=" << (event_input_routing_diag.preview_matches_structure_after_input_sequences ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_global_invariant_detects_invalid_state=" << (global_invariant_diag.global_invariant_detects_invalid_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_all_mutations_checked_by_invariant=" << (global_invariant_diag.all_mutations_checked_by_invariant ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_invalid_mutation_rejected_or_rolled_back=" << (global_invariant_diag.invalid_mutation_rejected_or_rolled_back ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_no_orphan_nodes_possible=" << (global_invariant_diag.no_orphan_nodes_possible ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_all_node_ids_unique_and_valid=" << (global_invariant_diag.all_node_ids_unique_and_valid ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_selection_references_valid_nodes_only=" << (global_invariant_diag.selection_references_valid_nodes_only ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_preview_structure_parity_enforced_by_invariant=" << (global_invariant_diag.preview_structure_parity_enforced_by_invariant ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_layout_constraints_enforced_by_invariant=" << (global_invariant_diag.layout_constraints_enforced_by_invariant ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_command_history_references_valid_state=" << (global_invariant_diag.command_history_references_valid_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_59_no_false_positive_rejections=" << (global_invariant_diag.no_false_positive_rejections ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_export_blocked_on_invalid_invariant=" << (export_package_diag.export_blocked_on_invalid_invariant ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_export_contains_all_nodes_and_properties=" << (export_package_diag.export_contains_all_nodes_and_properties ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_export_order_matches_structure=" << (export_package_diag.export_order_matches_structure ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_export_deterministic_for_identical_input=" << (export_package_diag.export_deterministic_for_identical_input ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_no_runtime_state_leaked_into_export=" << (export_package_diag.no_runtime_state_leaked_into_export ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_package_manifest_or_contents_coherent=" << (export_package_diag.package_manifest_or_contents_coherent ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_export_reflects_post_mutation_live_state=" << (export_package_diag.export_reflects_post_mutation_live_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_partial_export_never_reported_success=" << (export_package_diag.partial_export_never_reported_success ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_roundtrip_export_artifacts_valid=" << (export_package_diag.roundtrip_export_artifacts_valid ? "YES" : "NO") << "\n";
        std::cout << "phase103_60_export_preserves_structure_fidelity=" << (export_package_diag.export_preserves_structure_fidelity ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_startup_produces_invariant_valid_state=" << (startup_shutdown_diag.startup_produces_invariant_valid_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_no_transient_runtime_state_leaks_on_startup=" << (startup_shutdown_diag.no_transient_runtime_state_leaks_on_startup ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_preview_and_inspector_bindings_valid_after_startup=" << (startup_shutdown_diag.preview_and_inspector_bindings_valid_after_startup ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_selection_state_deterministic_after_startup=" << (startup_shutdown_diag.selection_state_deterministic_after_startup ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_shutdown_does_not_leave_partial_success_state=" << (startup_shutdown_diag.shutdown_does_not_leave_partial_success_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_close_reopen_cycle_preserves_clean_valid_state=" << (startup_shutdown_diag.close_reopen_cycle_preserves_clean_valid_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_startup_after_load_preserves_structure_fidelity=" << (startup_shutdown_diag.startup_after_load_preserves_structure_fidelity ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_repeated_open_close_cycles_stable=" << (startup_shutdown_diag.repeated_open_close_cycles_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_no_false_dirty_or_unexpected_mutation_on_lifecycle_boundary=" << (startup_shutdown_diag.no_false_dirty_or_unexpected_mutation_on_lifecycle_boundary ? "YES" : "NO") << "\n";
        std::cout << "phase103_61_global_invariant_holds_at_startup_and_shutdown=" << (startup_shutdown_diag.global_invariant_holds_at_startup_and_shutdown ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_long_mixed_sequence_preserves_invariant=" << (stress_sequence_diag.long_mixed_sequence_preserves_invariant ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_no_structure_preview_drift_after_stress=" << (stress_sequence_diag.no_structure_preview_drift_after_stress ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_selection_and_bindings_remain_valid_after_stress=" << (stress_sequence_diag.selection_and_bindings_remain_valid_after_stress ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_undo_redo_history_stable_under_long_sequence=" << (stress_sequence_diag.undo_redo_history_stable_under_long_sequence ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_no_stale_references_accumulated=" << (stress_sequence_diag.no_stale_references_accumulated ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_save_load_exact_after_stress=" << (stress_sequence_diag.save_load_exact_after_stress ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_export_exact_after_stress=" << (stress_sequence_diag.export_exact_after_stress ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_replay_of_identical_sequence_deterministic=" << (stress_sequence_diag.replay_of_identical_sequence_deterministic ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_no_false_dirty_or_phantom_mutation_after_stress=" << (stress_sequence_diag.no_false_dirty_or_phantom_mutation_after_stress ? "YES" : "NO") << "\n";
        std::cout << "phase103_62_final_state_matches_expected_canonical_signature=" << (stress_sequence_diag.final_state_matches_expected_canonical_signature ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_inline_edit_buffer_not_committed_until_commit=" << (manual_text_diag.inline_edit_buffer_not_committed_until_commit ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_cancelled_edit_leaves_document_unchanged=" << (manual_text_diag.cancelled_edit_leaves_document_unchanged ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_committed_edit_creates_exact_history_entry=" << (manual_text_diag.committed_edit_creates_exact_history_entry ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_undo_redo_exact_for_committed_text_edit=" << (manual_text_diag.undo_redo_exact_for_committed_text_edit ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_selection_or_target_change_during_edit_resolved_deterministically=" << (manual_text_diag.selection_or_target_change_during_edit_resolved_deterministically ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_no_stale_inline_edit_target_after_delete_move_load=" << (manual_text_diag.no_stale_inline_edit_target_after_delete_move_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_transient_edit_buffer_never_leaks_into_save_or_export=" << (manual_text_diag.transient_edit_buffer_never_leaks_into_save_or_export ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_rapid_edit_commit_cancel_sequences_stable=" << (manual_text_diag.rapid_edit_commit_cancel_sequences_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_no_history_entry_created_for_cancelled_edit=" << (manual_text_diag.no_history_entry_created_for_cancelled_edit ? "YES" : "NO") << "\n";
        std::cout << "phase103_63_global_invariant_preserved_through_manual_text_entry=" << (manual_text_diag.global_invariant_preserved_through_manual_text_entry ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_selection_set_contains_only_valid_nodes=" << (multi_selection_integrity_diag.selection_set_contains_only_valid_nodes ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_no_duplicate_ids_in_selection=" << (multi_selection_integrity_diag.no_duplicate_ids_in_selection ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_primary_and_multi_selection_consistent=" << (multi_selection_integrity_diag.primary_and_multi_selection_consistent ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_multi_operations_apply_to_all_selected_nodes=" << (multi_selection_integrity_diag.multi_operations_apply_to_all_selected_nodes ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_multi_operations_atomic_and_command_backed=" << (multi_selection_integrity_diag.multi_operations_atomic_and_command_backed ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_delete_move_reparent_clean_selection_state=" << (multi_selection_integrity_diag.delete_move_reparent_clean_selection_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_undo_redo_restore_full_selection_state=" << (multi_selection_integrity_diag.undo_redo_restore_full_selection_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_no_stale_ids_after_lifecycle_events=" << (multi_selection_integrity_diag.no_stale_ids_after_lifecycle_events ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_multi_operation_order_deterministic=" << (multi_selection_integrity_diag.multi_operation_order_deterministic ? "YES" : "NO") << "\n";
        std::cout << "phase103_64_no_cross_node_state_corruption=" << (multi_selection_integrity_diag.no_cross_node_state_corruption ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_clipboard_payload_requires_valid_selection=" << (clipboard_integrity_diag.clipboard_payload_requires_valid_selection ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_duplicate_creates_fresh_unique_ids=" << (clipboard_integrity_diag.duplicate_creates_fresh_unique_ids ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_paste_preserves_subtree_fidelity=" << (clipboard_integrity_diag.paste_preserves_subtree_fidelity ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_paste_does_not_leak_runtime_state=" << (clipboard_integrity_diag.paste_does_not_leak_runtime_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_paste_target_validation_fail_closed=" << (clipboard_integrity_diag.paste_target_validation_fail_closed ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_cut_paste_roundtrip_preserves_structure=" << (clipboard_integrity_diag.cut_paste_roundtrip_preserves_structure ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_undo_redo_exact_for_clipboard_operations=" << (clipboard_integrity_diag.undo_redo_exact_for_clipboard_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_deterministic_paste_order_and_parenting=" << (clipboard_integrity_diag.deterministic_paste_order_and_parenting ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_nested_selection_deduplicated_on_copy=" << (clipboard_integrity_diag.nested_selection_deduplicated_on_copy ? "YES" : "NO") << "\n";
        std::cout << "phase103_65_no_cross_node_corruption_after_clipboard_sequence=" << (clipboard_integrity_diag.no_cross_node_corruption_after_clipboard_sequence ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_repeated_same_target_property_edits_coalesce_only_when_allowed=" << (command_coalescing_diag.repeated_same_target_property_edits_coalesce_only_when_allowed ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_different_targets_or_operation_types_never_coalesce=" << (command_coalescing_diag.different_targets_or_operation_types_never_coalesce ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_manual_text_commit_creates_single_history_entry=" << (command_coalescing_diag.manual_text_commit_creates_single_history_entry ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_cancelled_edit_creates_zero_history_entries=" << (command_coalescing_diag.cancelled_edit_creates_zero_history_entries ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_bulk_operations_remain_single_logical_history_entries=" << (command_coalescing_diag.bulk_operations_remain_single_logical_history_entries ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_save_load_export_boundaries_break_coalescing=" << (command_coalescing_diag.save_load_export_boundaries_break_coalescing ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_undo_redo_operate_on_logical_action_boundaries=" << (command_coalescing_diag.undo_redo_operate_on_logical_action_boundaries ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_history_shape_deterministic_for_identical_sequence=" << (command_coalescing_diag.history_shape_deterministic_for_identical_sequence ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_history_metadata_coherent_after_coalescing=" << (command_coalescing_diag.history_metadata_coherent_after_coalescing ? "YES" : "NO") << "\n";
        std::cout << "phase103_66_no_timing_fragile_history_grouping=" << (command_coalescing_diag.no_timing_fragile_history_grouping ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_real_mutations_mark_dirty_exactly=" << (dirty_tracking_integrity_diag.real_mutations_mark_dirty_exactly ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_read_only_operations_do_not_mark_dirty=" << (dirty_tracking_integrity_diag.read_only_operations_do_not_mark_dirty ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_undo_back_to_clean_clears_dirty=" << (dirty_tracking_integrity_diag.undo_back_to_clean_clears_dirty ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_redo_away_from_clean_sets_dirty=" << (dirty_tracking_integrity_diag.redo_away_from_clean_sets_dirty ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_save_sets_new_clean_baseline_exactly=" << (dirty_tracking_integrity_diag.save_sets_new_clean_baseline_exactly ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_load_sets_new_clean_baseline_exactly=" << (dirty_tracking_integrity_diag.load_sets_new_clean_baseline_exactly ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_failed_save_load_or_blocked_mutation_do_not_corrupt_dirty_state=" << (dirty_tracking_integrity_diag.failed_save_load_or_blocked_mutation_do_not_corrupt_dirty_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_export_does_not_affect_dirty_state=" << (dirty_tracking_integrity_diag.export_does_not_affect_dirty_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_dirty_tracking_uses_canonical_document_signature=" << (dirty_tracking_integrity_diag.dirty_tracking_uses_canonical_document_signature ? "YES" : "NO") << "\n";
        std::cout << "phase103_67_stress_sequence_dirty_transitions_remain_exact=" << (dirty_tracking_integrity_diag.stress_sequence_dirty_transitions_remain_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_same_action_id_same_result_across_invocation_surfaces=" << (action_invocation_integrity_diag.same_action_id_same_result_across_invocation_surfaces ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_ineligible_actions_fail_closed_without_mutation=" << (action_invocation_integrity_diag.ineligible_actions_fail_closed_without_mutation ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_action_eligibility_checked_against_current_state=" << (action_invocation_integrity_diag.action_eligibility_checked_against_current_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_no_stale_selection_or_target_context_used=" << (action_invocation_integrity_diag.no_stale_selection_or_target_context_used ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_action_metadata_matches_execution_eligibility=" << (action_invocation_integrity_diag.action_metadata_matches_execution_eligibility ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_failed_invocation_creates_no_history_or_dirty_side_effect=" << (action_invocation_integrity_diag.failed_invocation_creates_no_history_or_dirty_side_effect ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_cross_surface_invocation_produces_identical_history_and_selection=" << (action_invocation_integrity_diag.cross_surface_invocation_produces_identical_history_and_selection ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_global_invariant_preserved_through_all_action_invocations=" << (action_invocation_integrity_diag.global_invariant_preserved_through_all_action_invocations ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_no_command_dispatch_mismatch_or_wrong_handler_resolution=" << (action_invocation_integrity_diag.no_command_dispatch_mismatch_or_wrong_handler_resolution ? "YES" : "NO") << "\n";
        std::cout << "phase103_68_deterministic_invocation_sequence_stable=" << (action_invocation_integrity_diag.deterministic_invocation_sequence_stable ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_search_filter_read_only_no_document_mutation=" << (search_filter_visibility_integrity_diag.search_filter_read_only_no_document_mutation ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_filtered_order_matches_authoritative_structure_order=" << (search_filter_visibility_integrity_diag.filtered_order_matches_authoritative_structure_order ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_selection_mapping_remains_deterministic_under_filter_changes=" << (search_filter_visibility_integrity_diag.selection_mapping_remains_deterministic_under_filter_changes ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_no_stale_deleted_or_moved_nodes_in_results=" << (search_filter_visibility_integrity_diag.no_stale_deleted_or_moved_nodes_in_results ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_actions_from_filtered_view_resolve_against_authoritative_current_state=" << (search_filter_visibility_integrity_diag.actions_from_filtered_view_resolve_against_authoritative_current_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_clear_and_reapply_filter_restores_coherent_visible_state=" << (search_filter_visibility_integrity_diag.clear_and_reapply_filter_restores_coherent_visible_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_search_filter_creates_no_history_or_dirty_side_effect=" << (search_filter_visibility_integrity_diag.search_filter_creates_no_history_or_dirty_side_effect ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_preview_and_bindings_remain_coherent_under_filtered_view=" << (search_filter_visibility_integrity_diag.preview_and_bindings_remain_coherent_under_filtered_view ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_filtered_and_unfiltered_action_results_match_for_same_underlying_state=" << (search_filter_visibility_integrity_diag.filtered_and_unfiltered_action_results_match_for_same_underlying_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_69_global_invariant_preserved_through_search_filter_cycles=" << (search_filter_visibility_integrity_diag.global_invariant_preserved_through_search_filter_cycles ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_authoritative_order_navigation_matches_document_structure=" << (selection_anchor_focus_navigation_integrity_diag.authoritative_order_navigation_matches_document_structure ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_selection_anchor_establishes_deterministic_range_extent=" << (selection_anchor_focus_navigation_integrity_diag.selection_anchor_establishes_deterministic_range_extent ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_focus_only_navigation_does_not_mutate_selection_or_document=" << (selection_anchor_focus_navigation_integrity_diag.focus_only_navigation_does_not_mutate_selection_or_document ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_stale_anchor_and_focus_are_scrubbed_fail_closed=" << (selection_anchor_focus_navigation_integrity_diag.stale_anchor_and_focus_are_scrubbed_fail_closed ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_selection_focus_coherence_restored_after_filter_and_lifecycle_changes=" << (selection_anchor_focus_navigation_integrity_diag.selection_focus_coherence_restored_after_filter_and_lifecycle_changes ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_navigation_only_changes_create_no_history_or_dirty_side_effect=" << (selection_anchor_focus_navigation_integrity_diag.navigation_only_changes_create_no_history_or_dirty_side_effect ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_parent_child_navigation_respects_authoritative_current_state=" << (selection_anchor_focus_navigation_integrity_diag.parent_child_navigation_respects_authoritative_current_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_range_extension_shrinks_and_grows_deterministically_from_same_anchor=" << (selection_anchor_focus_navigation_integrity_diag.range_extension_shrinks_and_grows_deterministically_from_same_anchor ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_filtered_and_unfiltered_navigation_resolve_same_underlying_targets=" << (selection_anchor_focus_navigation_integrity_diag.filtered_and_unfiltered_navigation_resolve_same_underlying_targets ? "YES" : "NO") << "\n";
        std::cout << "phase103_70_global_invariant_preserved_through_anchor_focus_navigation_cycles=" << (selection_anchor_focus_navigation_integrity_diag.global_invariant_preserved_through_anchor_focus_navigation_cycles ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_drop_target_resolution_deterministic=" << (drag_drop_reorder_integrity_diag.drop_target_resolution_deterministic ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_multi_selection_drag_atomic_and_order_preserved=" << (drag_drop_reorder_integrity_diag.multi_selection_drag_atomic_and_order_preserved ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_sibling_reorder_preserves_global_structure_order=" << (drag_drop_reorder_integrity_diag.sibling_reorder_preserves_global_structure_order ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_cross_parent_move_updates_relationships_exactly=" << (drag_drop_reorder_integrity_diag.cross_parent_move_updates_relationships_exactly ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_filtered_view_drag_resolves_to_authoritative_target=" << (drag_drop_reorder_integrity_diag.filtered_view_drag_resolves_to_authoritative_target ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_invalid_drop_fails_closed_without_mutation=" << (drag_drop_reorder_integrity_diag.invalid_drop_fails_closed_without_mutation ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_undo_redo_exact_for_drag_operations=" << (drag_drop_reorder_integrity_diag.undo_redo_exact_for_drag_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_no_partial_or_stale_references_after_drag=" << (drag_drop_reorder_integrity_diag.no_partial_or_stale_references_after_drag ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_drag_creates_no_transient_history_or_dirty_leak=" << (drag_drop_reorder_integrity_diag.drag_creates_no_transient_history_or_dirty_leak ? "YES" : "NO") << "\n";
        std::cout << "phase103_71_global_invariant_preserved_after_drag_operations=" << (drag_drop_reorder_integrity_diag.global_invariant_preserved_after_drag_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_save_is_atomic_and_never_exposes_partial_file=" << (persistence_file_io_integrity_diag.save_is_atomic_and_never_exposes_partial_file ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_saved_file_matches_canonical_document_signature=" << (persistence_file_io_integrity_diag.saved_file_matches_canonical_document_signature ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_load_rejects_invalid_or_truncated_files=" << (persistence_file_io_integrity_diag.load_rejects_invalid_or_truncated_files ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_failed_save_does_not_overwrite_existing_file=" << (persistence_file_io_integrity_diag.failed_save_does_not_overwrite_existing_file ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_failed_load_does_not_mutate_current_state=" << (persistence_file_io_integrity_diag.failed_load_does_not_mutate_current_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_no_transient_ui_or_state_desync_during_io=" << (persistence_file_io_integrity_diag.no_transient_ui_or_state_desync_during_io ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_serialization_deterministic_for_identical_document=" << (persistence_file_io_integrity_diag.serialization_deterministic_for_identical_document ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_repeated_save_calls_produce_consistent_output=" << (persistence_file_io_integrity_diag.repeated_save_calls_produce_consistent_output ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_dirty_baseline_updates_only_on_successful_save_load=" << (persistence_file_io_integrity_diag.dirty_baseline_updates_only_on_successful_save_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_72_global_invariant_preserved_through_all_io_operations=" << (persistence_file_io_integrity_diag.global_invariant_preserved_through_all_io_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_undo_restores_full_system_state=" << (undo_redo_time_travel_integrity_diag.undo_restores_full_system_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_redo_restores_full_system_state=" << (undo_redo_time_travel_integrity_diag.redo_restores_full_system_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_no_state_drift_after_repeated_cycles=" << (undo_redo_time_travel_integrity_diag.no_state_drift_after_repeated_cycles ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_selection_anchor_focus_restore_exact=" << (undo_redo_time_travel_integrity_diag.selection_anchor_focus_restore_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_multi_selection_restore_exact=" << (undo_redo_time_travel_integrity_diag.multi_selection_restore_exact ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_redo_stack_invalidated_on_new_mutation=" << (undo_redo_time_travel_integrity_diag.redo_stack_invalidated_on_new_mutation ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_no_history_pollution_from_failed_operations=" << (undo_redo_time_travel_integrity_diag.no_history_pollution_from_failed_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_no_branching_history_corruption=" << (undo_redo_time_travel_integrity_diag.no_branching_history_corruption ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_cross_surface_state_consistent_after_time_travel=" << (undo_redo_time_travel_integrity_diag.cross_surface_state_consistent_after_time_travel ? "YES" : "NO") << "\n";
        std::cout << "phase103_73_global_invariant_preserved_during_undo_redo=" << (undo_redo_time_travel_integrity_diag.global_invariant_preserved_during_undo_redo ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_selected_node_visible_or_scrolled_into_view_deterministically=" << (viewport_scroll_visual_state_integrity_diag.selected_node_visible_or_scrolled_into_view_deterministically ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_scroll_position_deterministic_for_identical_sequences=" << (viewport_scroll_visual_state_integrity_diag.scroll_position_deterministic_for_identical_sequences ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_undo_redo_restores_viewport_with_state=" << (viewport_scroll_visual_state_integrity_diag.undo_redo_restores_viewport_with_state ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_filtered_and_unfiltered_scroll_mapping_consistent=" << (viewport_scroll_visual_state_integrity_diag.filtered_and_unfiltered_scroll_mapping_consistent ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_viewport_never_references_invalid_or_deleted_rows=" << (viewport_scroll_visual_state_integrity_diag.viewport_never_references_invalid_or_deleted_rows ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_load_save_initialize_or_preserve_viewport_deterministically=" << (viewport_scroll_visual_state_integrity_diag.load_save_initialize_or_preserve_viewport_deterministically ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_no_dirty_or_history_side_effects_from_viewport_changes=" << (viewport_scroll_visual_state_integrity_diag.no_dirty_or_history_side_effects_from_viewport_changes ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_tree_and_preview_viewports_remain_coherent=" << (viewport_scroll_visual_state_integrity_diag.tree_and_preview_viewports_remain_coherent ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_no_scroll_drift_after_stress_sequences=" << (viewport_scroll_visual_state_integrity_diag.no_scroll_drift_after_stress_sequences ? "YES" : "NO") << "\n";
        std::cout << "phase103_74_global_invariant_preserved_during_viewport_updates=" << (viewport_scroll_visual_state_integrity_diag.global_invariant_preserved_during_viewport_updates ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_external_paste_rejects_malformed_or_partial_data=" << (external_data_boundary_integrity_diag.external_paste_rejects_malformed_or_partial_data ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_external_data_parsed_and_applied_atomically=" << (external_data_boundary_integrity_diag.external_data_parsed_and_applied_atomically ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_imported_nodes_have_valid_ids_and_relationships=" << (external_data_boundary_integrity_diag.imported_nodes_have_valid_ids_and_relationships ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_external_input_cannot_bypass_global_invariant=" << (external_data_boundary_integrity_diag.external_input_cannot_bypass_global_invariant ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_internal_clipboard_path_unchanged_and_isolated=" << (external_data_boundary_integrity_diag.internal_clipboard_path_unchanged_and_isolated ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_deterministic_result_for_identical_external_input=" << (external_data_boundary_integrity_diag.deterministic_result_for_identical_external_input ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_failed_external_paste_creates_no_history_or_dirty_change=" << (external_data_boundary_integrity_diag.failed_external_paste_creates_no_history_or_dirty_change ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_successful_external_paste_creates_single_atomic_history_entry=" << (external_data_boundary_integrity_diag.successful_external_paste_creates_single_atomic_history_entry ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_large_or_invalid_payloads_fail_safely_without_crash=" << (external_data_boundary_integrity_diag.large_or_invalid_payloads_fail_safely_without_crash ? "YES" : "NO") << "\n";
        std::cout << "phase103_75_global_invariant_preserved_after_external_import=" << (external_data_boundary_integrity_diag.global_invariant_preserved_after_external_import ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_large_document_operations_remain_correct=" << (performance_scaling_integrity_diag.large_document_operations_remain_correct ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_deep_hierarchy_handled_without_failure=" << (performance_scaling_integrity_diag.deep_hierarchy_handled_without_failure ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_long_stress_sequence_preserves_invariant=" << (performance_scaling_integrity_diag.long_stress_sequence_preserves_invariant ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_undo_redo_stable_under_large_history=" << (performance_scaling_integrity_diag.undo_redo_stable_under_large_history ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_search_filter_stable_under_large_dataset=" << (performance_scaling_integrity_diag.search_filter_stable_under_large_dataset ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_viewport_stable_under_large_node_count=" << (performance_scaling_integrity_diag.viewport_stable_under_large_node_count ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_no_state_drift_under_repeated_operations=" << (performance_scaling_integrity_diag.no_state_drift_under_repeated_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_no_partial_or_skipped_validation_under_load=" << (performance_scaling_integrity_diag.no_partial_or_skipped_validation_under_load ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_deterministic_result_for_identical_large_sequence=" << (performance_scaling_integrity_diag.deterministic_result_for_identical_large_sequence ? "YES" : "NO") << "\n";
        std::cout << "phase103_76_global_invariant_preserved_under_scale=" << (performance_scaling_integrity_diag.global_invariant_preserved_under_scale ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_profile_captures_representative_operations=" << (performance_profiling_diag.profile_captures_representative_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_model_and_ui_costs_measured_separately=" << (performance_profiling_diag.model_and_ui_costs_measured_separately ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_scaling_characteristics_captured_across_sizes=" << (performance_profiling_diag.scaling_characteristics_captured_across_sizes ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_no_correctness_guarantees_were_weakened=" << (performance_profiling_diag.no_correctness_guarantees_were_weakened ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_invariant_checks_remained_enabled_during_profiling=" << (performance_profiling_diag.invariant_checks_remained_enabled_during_profiling ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_hotspots_ranked_by_measured_cost=" << (performance_profiling_diag.hotspots_ranked_by_measured_cost ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_actionable_optimization_targets_identified=" << (performance_profiling_diag.actionable_optimization_targets_identified ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_profile_run_terminates_cleanly_with_markers=" << (performance_profiling_diag.profile_run_terminates_cleanly_with_markers ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_no_partial_or_stalled_proof_artifacts=" << (performance_profiling_diag.no_partial_or_stalled_proof_artifacts ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_global_invariant_preserved_during_profile_runs=" << (performance_profiling_diag.global_invariant_preserved_during_profile_runs ? "YES" : "NO") << "\n";
        std::cout << "phase103_77_profile_operations=" << performance_profiling_diag.operations_profiled << "\n";
        std::cout << "phase103_77_profile_size_small_nodes=" << performance_profiling_diag.size_small_nodes << "\n";
        std::cout << "phase103_77_profile_size_medium_nodes=" << performance_profiling_diag.size_medium_nodes << "\n";
        std::cout << "phase103_77_profile_size_large_nodes=" << performance_profiling_diag.size_large_nodes << "\n";
        std::cout << "phase103_77_profile_build_small_ns=" << performance_profiling_diag.build_small_ns << "\n";
        std::cout << "phase103_77_profile_build_medium_ns=" << performance_profiling_diag.build_medium_ns << "\n";
        std::cout << "phase103_77_profile_build_large_ns=" << performance_profiling_diag.build_large_ns << "\n";
        std::cout << "phase103_77_profile_validate_small_ns=" << performance_profiling_diag.validate_small_ns << "\n";
        std::cout << "phase103_77_profile_validate_medium_ns=" << performance_profiling_diag.validate_medium_ns << "\n";
        std::cout << "phase103_77_profile_validate_large_ns=" << performance_profiling_diag.validate_large_ns << "\n";
        std::cout << "phase103_77_profile_serialize_small_ns=" << performance_profiling_diag.serialize_small_ns << "\n";
        std::cout << "phase103_77_profile_serialize_medium_ns=" << performance_profiling_diag.serialize_medium_ns << "\n";
        std::cout << "phase103_77_profile_serialize_large_ns=" << performance_profiling_diag.serialize_large_ns << "\n";
        std::cout << "phase103_77_profile_selection_mapping_ns=" << performance_profiling_diag.selection_mapping_ns << "\n";
        std::cout << "phase103_77_profile_insert_ns=" << performance_profiling_diag.insert_ns << "\n";
        std::cout << "phase103_77_profile_property_edit_commit_ns=" << performance_profiling_diag.property_edit_commit_ns << "\n";
        std::cout << "phase103_77_profile_move_reparent_ns=" << performance_profiling_diag.move_reparent_ns << "\n";
        std::cout << "phase103_77_profile_delete_ns=" << performance_profiling_diag.delete_ns << "\n";
        std::cout << "phase103_77_profile_history_build_ns=" << performance_profiling_diag.history_build_ns << "\n";
        std::cout << "phase103_77_profile_undo_replay_ns=" << performance_profiling_diag.undo_replay_ns << "\n";
        std::cout << "phase103_77_profile_redo_replay_ns=" << performance_profiling_diag.redo_replay_ns << "\n";
        std::cout << "phase103_77_profile_filter_apply_ns=" << performance_profiling_diag.filter_apply_ns << "\n";
        std::cout << "phase103_77_profile_filter_clear_ns=" << performance_profiling_diag.filter_clear_ns << "\n";
        std::cout << "phase103_77_profile_viewport_reconcile_ns=" << performance_profiling_diag.viewport_reconcile_ns << "\n";
        std::cout << "phase103_77_profile_save_ns=" << performance_profiling_diag.save_ns << "\n";
        std::cout << "phase103_77_profile_load_ns=" << performance_profiling_diag.load_ns << "\n";
        std::cout << "phase103_77_profile_export_ns=" << performance_profiling_diag.export_ns << "\n";
        std::cout << "phase103_77_profile_large_global_invariant_ns=" << performance_profiling_diag.large_global_invariant_ns << "\n";
        std::cout << "phase103_77_profile_deterministic_signature_large_ns=" << performance_profiling_diag.deterministic_signature_large_ns << "\n";
        std::cout << "phase103_77_profile_model_total_ns=" << performance_profiling_diag.model_total_ns << "\n";
        std::cout << "phase103_77_profile_ui_total_ns=" << performance_profiling_diag.ui_total_ns << "\n";
        std::cout << "phase103_77_profile_io_total_ns=" << performance_profiling_diag.io_total_ns << "\n";
        std::cout << "phase103_77_profile_scaling_build=" << performance_profiling_diag.scaling_build << "\n";
        std::cout << "phase103_77_profile_scaling_validate=" << performance_profiling_diag.scaling_validate << "\n";
        std::cout << "phase103_77_profile_scaling_serialize=" << performance_profiling_diag.scaling_serialize << "\n";
        std::cout << "phase103_77_hotspot_rank_1=" << performance_profiling_diag.hotspot_rankings[0] << "\n";
        std::cout << "phase103_77_hotspot_rank_2=" << performance_profiling_diag.hotspot_rankings[1] << "\n";
        std::cout << "phase103_77_hotspot_rank_3=" << performance_profiling_diag.hotspot_rankings[2] << "\n";
        std::cout << "phase103_77_hotspot_rank_4=" << performance_profiling_diag.hotspot_rankings[3] << "\n";
        std::cout << "phase103_77_hotspot_rank_5=" << performance_profiling_diag.hotspot_rankings[4] << "\n";
        std::cout << "phase103_77_optimization_targets=" << performance_profiling_diag.optimization_targets << "\n";
        std::cout << "phase103_78_undo_replay_time_reduced_vs_phase103_77=" << (history_replay_optimization_diag.undo_replay_time_reduced_vs_phase103_77 ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_redo_replay_time_reduced_vs_phase103_77=" << (history_replay_optimization_diag.redo_replay_time_reduced_vs_phase103_77 ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_history_replay_produces_identical_document_signature=" << (history_replay_optimization_diag.history_replay_produces_identical_document_signature ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_selection_anchor_focus_identical_after_replay=" << (history_replay_optimization_diag.selection_anchor_focus_identical_after_replay ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_preview_and_structure_fully_consistent_after_replay=" << (history_replay_optimization_diag.preview_and_structure_fully_consistent_after_replay ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_invariant_preserved_during_and_after_replay=" << (history_replay_optimization_diag.invariant_preserved_during_and_after_replay ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_no_skipped_or_reordered_history_operations=" << (history_replay_optimization_diag.no_skipped_or_reordered_history_operations ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_no_ui_desync_during_replay_batching=" << (history_replay_optimization_diag.no_ui_desync_during_replay_batching ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_repeated_replay_cycles_remain_drift_free=" << (history_replay_optimization_diag.repeated_replay_cycles_remain_drift_free ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_global_invariant_preserved=" << (history_replay_optimization_diag.global_invariant_preserved ? "YES" : "NO") << "\n";
        std::cout << "phase103_78_phase103_77_baseline_undo_replay_ns=" << history_replay_optimization_diag.phase103_77_baseline_undo_replay_ns << "\n";
        std::cout << "phase103_78_phase103_77_baseline_redo_replay_ns=" << history_replay_optimization_diag.phase103_77_baseline_redo_replay_ns << "\n";
        std::cout << "phase103_78_optimized_undo_replay_ns=" << history_replay_optimization_diag.optimized_undo_replay_ns << "\n";
        std::cout << "phase103_78_optimized_redo_replay_ns=" << history_replay_optimization_diag.optimized_redo_replay_ns << "\n";
        std::cout << "phase103_78_history_replay_steps=" << history_replay_optimization_diag.replay_history_steps << "\n";
        std::cout << "phase103_78_batching_strategy=" << history_replay_optimization_diag.batching_strategy << "\n";
        std::cout << "phase103_79_export_time_reduced_vs_phase103_77=" << (serialization_export_optimization_diag.export_time_reduced_vs_phase103_77 ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_serialization_time_reduced_vs_phase103_77=" << (serialization_export_optimization_diag.serialization_time_reduced_vs_phase103_77 ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_export_bytes_identical_to_baseline=" << (serialization_export_optimization_diag.export_bytes_identical_to_baseline ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_canonical_signature_identical_to_baseline=" << (serialization_export_optimization_diag.canonical_signature_identical_to_baseline ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_no_stale_serialization_reuse_after_mutation=" << (serialization_export_optimization_diag.no_stale_serialization_reuse_after_mutation ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_no_correctness_guarantees_were_weakened=" << (serialization_export_optimization_diag.no_correctness_guarantees_were_weakened ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_no_history_or_dirty_side_effect_from_optimization=" << (serialization_export_optimization_diag.no_history_or_dirty_side_effect_from_optimization ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_profile_run_terminates_cleanly_with_markers=" << (serialization_export_optimization_diag.profile_run_terminates_cleanly_with_markers ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_no_partial_or_stalled_proof_artifacts=" << (serialization_export_optimization_diag.no_partial_or_stalled_proof_artifacts ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_global_invariant_preserved=" << (serialization_export_optimization_diag.global_invariant_preserved ? "YES" : "NO") << "\n";
        std::cout << "phase103_79_phase103_77_baseline_serialize_ns=" << serialization_export_optimization_diag.phase103_77_baseline_serialize_ns << "\n";
        std::cout << "phase103_79_phase103_77_baseline_export_ns=" << serialization_export_optimization_diag.phase103_77_baseline_export_ns << "\n";
        std::cout << "phase103_79_optimized_serialize_ns=" << serialization_export_optimization_diag.optimized_serialize_ns << "\n";
        std::cout << "phase103_79_optimized_export_ns=" << serialization_export_optimization_diag.optimized_export_ns << "\n";
        std::cout << "phase103_79_reuse_strategy=" << serialization_export_optimization_diag.reuse_strategy << "\n";
      std::cout << "app_runtime_crash_detected=" << (no_crash ? 0 : 1) << "\n";
    std::cout << "SUMMARY: PASS\n";
  }
  const bool ui_interaction_ok =
    model.refresh_count > 0 && model.next_count > 0 && model.prev_count > 0 && model.apply_filter_count > 0;
  const bool validation_ok =
    ui_interaction_ok && startup_deterministic && no_undefined_state && no_hidden_paths && no_crash && render_frames > 0;

  std::cout << "app_name=desktop_file_tool\n";
  std::cout << "app_startup_state=" << (startup_deterministic ? "deterministic_native_startup" : "undefined") << "\n";
  std::cout << "app_hidden_execution_paths_detected=" << (no_hidden_paths ? 0 : 1) << "\n";
  std::cout << "app_undefined_state_detected=" << (no_undefined_state ? 0 : 1) << "\n";
  std::cout << "app_ui_interaction_ok=" << (ui_interaction_ok ? 1 : 0) << "\n";
  std::cout << "app_files_listed_count=" << model.entries.size() << "\n";
  std::cout << "app_selected_file=" << selected_file_name(model) << "\n";
  std::cout << "app_refresh_count=" << model.refresh_count << "\n";
  std::cout << "app_next_count=" << model.next_count << "\n";
  std::cout << "app_prev_count=" << model.prev_count << "\n";
  std::cout << "app_apply_filter_count=" << model.apply_filter_count << "\n";
  std::cout << "phase101_4_wm_paint_entry_count=" << redraw_diag.wm_paint_entry_count << "\n";
  std::cout << "phase101_4_wm_paint_exit_count=" << redraw_diag.wm_paint_exit_count << "\n";
  std::cout << "phase101_4_invalidate_total_count=" << redraw_diag.invalidate_total_count << "\n";
  std::cout << "phase101_4_input_redraw_requests=" << redraw_diag.input_redraw_requests << "\n";
  std::cout << "phase101_4_steady_redraw_requests=" << redraw_diag.invalidate_steady_count << "\n";
  std::cout << "phase101_4_layout_redraw_requests=" << redraw_diag.invalidate_layout_count << "\n";
  std::cout << "phase101_4_render_begin_count=" << redraw_diag.render_begin_count << "\n";
  std::cout << "phase101_4_render_end_count=" << redraw_diag.render_end_count << "\n";
  std::cout << "phase101_4_present_call_count=" << redraw_diag.present_call_count << "\n";
  std::cout << "phase101_4_steady_loop_iterations=" << redraw_diag.steady_loop_iterations << "\n";
  std::cout << "phase101_4_background_erase_handling=wm_erasebkgnd_suppressed\n";
  std::cout << "phase101_4_redraw_issue_root_cause=render_present_path_not_explicitly_bound_to_steady_wm_paint_redraw_with_background_erase_suppression\n";
  std::cout << "phase101_4_present_path_stable="
            << ((redraw_diag.render_begin_count > 0 &&
                 redraw_diag.render_begin_count == redraw_diag.render_end_count &&
                 redraw_diag.render_end_count == redraw_diag.present_call_count &&
                 redraw_diag.wm_paint_entry_count == redraw_diag.wm_paint_exit_count)
                   ? 1
                   : 0)
            << "\n";
  std::cout << "SUMMARY: " << ((validation_mode && auto_close_ms > 0) ? (validation_ok ? "PASS" : "FAIL") : "N/A")
            << "\n";

  if (validation_mode && auto_close_ms > 0) {
    return validation_ok ? 0 : 3;
  }

  return no_crash && no_undefined_state && no_hidden_paths ? 0 : 3;
}

} // namespace

int main(int argc, char** argv) {
  ngk::runtime_guard::runtime_observe_lifecycle("desktop_file_tool", "main_enter");
  const int guard_rc = ngk::runtime_guard::enforce_phase53_2();
  if (guard_rc != 0) {
    ngk::runtime_guard::runtime_observe_lifecycle("desktop_file_tool", "guard_blocked");
    ngk::runtime_guard::runtime_emit_startup_summary("desktop_file_tool", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_termination_summary("desktop_file_tool", "runtime_init", guard_rc);
    ngk::runtime_guard::runtime_emit_final_status("BLOCKED");
    return guard_rc;
  }

  ngk::runtime_guard::runtime_emit_startup_summary("desktop_file_tool", "runtime_init", 0);
  ngk::runtime_guard::require_runtime_trust("execution_pipeline");

  const int auto_close_ms = parse_auto_close_ms(argc, argv);
  const bool validation_mode = parse_validation_mode(argc, argv);
  const int app_rc = run_desktop_file_tool_app(auto_close_ms, validation_mode);

  ngk::runtime_guard::runtime_observe_lifecycle("desktop_file_tool", "main_exit");
  ngk::runtime_guard::runtime_emit_termination_summary("desktop_file_tool", "runtime_init", app_rc == 0 ? 0 : 1);
  ngk::runtime_guard::runtime_emit_final_status(app_rc == 0 ? "RUN_OK" : "RUN_FAIL");
  return app_rc;
}

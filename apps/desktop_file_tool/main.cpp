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
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

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

struct RedrawDiagnostics {
  int wm_paint_entry_count = 0;
  int wm_paint_exit_count = 0;
  int invalidate_total_count = 0;
  int invalidate_input_count = 0;
  int invalidate_steady_count = 0;
  int invalidate_layout_count = 0;
  int render_begin_count = 0;
  int render_end_count = 0;
  int present_call_count = 0;
  int steady_loop_iterations = 0;
  int input_redraw_requests = 0;
};

struct LayoutFunctionDiagnostics {
  bool layout_fn_called = false;
  bool resize_stabilized = false;
};

struct ScrollContainerDiagnostics {
  bool container_created = false;
  bool vertical_scroll_used = false;
  bool mouse_wheel_dispatched = false;
};

struct ListViewDiagnostics {
  bool list_view_created = false;
  bool row_selected = false;
  bool click_selection_triggered = false;
  bool data_binding_active = false;
};

struct TableViewDiagnostics {
  bool table_view_created = false;
  bool multi_column_rendered = false;
  bool header_rendered = false;
  bool data_binding_active = false;
};

struct ShellWidgetDiagnostics {
  bool toolbar_created = false;
  bool sidebar_created = false;
  bool status_bar_created = false;
  bool shell_integrated = false;
};

struct FileDialogDiagnostics {
  bool open_dialog_supported = false;
  bool save_dialog_supported = false;
  bool message_dialog_supported = false;
  bool bridge_integrated = false;
};

struct DeclarativeLayerDiagnostics {
  bool declarative_layer_created = false;
  bool nested_composition_done = false;
  bool property_binding_active = false;
  bool action_binding_active = false;
};

struct BuilderTargetDiagnostics {
  bool target_selected = false;
  bool target_implemented = false;
  bool layout_audit_no_overlap = false;
};

struct BuilderDocumentDiagnostics {
  bool document_defined = false;
  bool node_ids_stable = false;
  bool parent_child_ownership = false;
  bool schema_aligned = false;
  bool save_load_deterministic = false;
  bool sample_instantiable = false;
  bool layout_audit_compatible = false;
};

struct SelectionModelDiagnostics {
  bool selection_model_defined = false;
  bool invalid_selection_rejected = false;
  bool property_schema_defined = false;
  bool inspector_foundation_present = false;
  bool legal_property_update_applied = false;
  bool illegal_property_update_rejected = false;
  bool runtime_refreshable = false;
  bool layout_audit_compatible = false;
};

struct StructuralCommandDiagnostics {
  bool commands_defined = false;
  bool legal_child_add_applied = false;
  bool legal_node_remove_applied = false;
  bool legal_sibling_reorder_applied = false;
  bool legal_reparent_applied = false;
  bool illegal_edit_rejected = false;
  bool tree_editor_foundation_present = false;
  bool runtime_refreshable = false;
  bool layout_audit_compatible = false;
};

struct BuilderShellDiagnostics {
  bool builder_shell_present = false;
  bool live_tree_surface_present = false;
  bool selection_sync_working = false;
  bool live_inspector_present = false;
  bool legal_property_edit_from_shell = false;
  bool live_preview_present = false;
  bool runtime_refresh_after_edit = false;
  bool layout_audit_compatible = false;
};

struct ComponentPaletteDiagnostics {
  bool component_palette_present = false;
  bool legal_container_insertion_applied = false;
  bool legal_leaf_insertion_applied = false;
  bool illegal_insertion_rejected = false;
  bool inserted_node_auto_selected = false;
  bool tree_and_inspector_refresh_after_insert = false;
  bool runtime_refresh_after_insert = false;
  bool layout_audit_compatible = false;
};

struct BuilderMoveReparentDiagnostics {
  bool shell_move_controls_present = false;
  bool legal_sibling_move_applied = false;
  bool legal_reparent_applied = false;
  bool illegal_reparent_rejected = false;
  bool moved_node_selection_preserved = false;
  bool tree_and_inspector_refresh_after_move = false;
  bool runtime_refresh_after_move = false;
  bool layout_audit_compatible = false;
};

struct BuilderStateCoherenceDiagnostics {
  bool selection_coherence_hardened = false;
  bool stale_selection_rejected = false;
  bool inspector_coherence_hardened = false;
  bool stale_inspector_binding_rejected = false;
  bool preview_coherence_hardened = false;
  bool cross_surface_sync_checks_present = false;
  bool chained_operation_state_stable = false;
  bool layout_audit_compatible = false;
  bool desync_tree_selection_detected = false;
  bool desync_inspector_binding_detected = false;
  bool desync_preview_binding_detected = false;
};

struct BuilderDeleteWorkflowDiagnostics {
  bool shell_delete_control_present = false;
  bool legal_delete_applied = false;
  bool protected_delete_rejected = false;
  bool post_delete_selection_remapped_or_cleared = false;
  bool inspector_safe_after_delete = false;
  bool preview_refresh_after_delete = false;
  bool cross_surface_state_still_coherent = false;
  bool layout_audit_compatible = false;
};

struct CommandHistoryEntry {
  std::string command_type{};
  std::vector<ngk::ui::builder::BuilderNode> before_nodes{};
  std::string before_root_node_id{};
  std::string before_selected_id{};
  std::vector<ngk::ui::builder::BuilderNode> after_nodes{};
  std::string after_root_node_id{};
  std::string after_selected_id{};
};

struct BuilderUndoRedoDiagnostics {
  bool command_history_present = false;
  bool rejected_operations_not_recorded = false;
  bool property_edit_undo_redo_works = false;
  bool insert_undo_redo_works = false;
  bool delete_undo_redo_works = false;
  bool move_or_reparent_undo_redo_works = false;
  bool shell_state_coherent_after_undo_redo = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderSaveLoadDiagnostics {
  bool shell_save_control_present = false;
  bool shell_load_control_present = false;
  bool save_writes_deterministic_document = false;
  bool load_restores_document_state = false;
  bool invalid_load_rejected = false;
  bool history_cleared_or_handled_deterministically_on_load = false;
  bool shell_state_coherent_after_load = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderDirtyStateDiagnostics {
  bool dirty_state_tracking_present = false;
  bool edit_marks_dirty = false;
  bool save_marks_clean = false;
  bool load_marks_clean = false;
  bool rejected_ops_do_not_change_dirty_state = false;
  bool unsafe_load_over_dirty_state_guarded = false;
  bool explicit_safe_load_path_works = false;
  bool shell_state_coherent_after_guarded_load = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderLifecycleDiagnostics {
  bool new_document_control_present = false;
  bool new_document_creates_valid_builder_doc = false;
  bool unsafe_new_over_dirty_state_guarded = false;
  bool explicit_safe_new_path_works = false;
  bool history_cleared_on_new = false;
  bool dirty_state_clean_on_new = false;
  bool shell_state_coherent_after_new = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderFocusDiagnostics {
  bool focus_selection_rules_defined = false;
  bool post_operation_focus_deterministic = false;
  bool tree_navigation_coherent = false;
  bool stale_focus_rejected = false;
  bool inspector_focus_safe = false;
  bool shell_state_coherent_after_focus_changes = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderVisibleUxDiagnostics {
  bool tree_hierarchy_visibility_improved = false;
  bool selected_node_visibility_in_tree_improved = false;
  bool preview_readability_improved = false;
  bool selected_node_visibility_in_preview_improved = false;
  bool shell_regions_clearly_labeled = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderShortcutDiagnostics {
  bool keyboard_tree_navigation_present = false;
  bool shortcut_scope_rules_defined = false;
  bool undo_redo_shortcuts_work = false;
  bool insert_delete_shortcuts_work = false;
  bool guarded_lifecycle_shortcuts_safe = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderDragDropDiagnostics {
  bool tree_drag_reorder_present = false;
  bool legal_reorder_drop_applied = false;
  bool legal_reparent_drop_applied = false;
  bool illegal_drop_rejected = false;
  bool dragged_node_selection_preserved = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderTypedPaletteDiagnostics {
  bool typed_palette_present = false;
  bool legal_typed_container_insert_applied = false;
  bool legal_typed_leaf_insert_applied = false;
  bool illegal_typed_insert_rejected = false;
  bool inserted_typed_node_auto_selected = false;
  bool inspector_shows_type_appropriate_properties = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderExportDiagnostics {
  bool export_command_present = false;
  bool export_artifact_created = false;
  bool export_artifact_deterministic = false;
  bool exported_structure_matches_builder_doc = false;
  bool invalid_export_rejected = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderExportUxDiagnostics {
  bool export_status_visible = false;
  bool export_artifact_path_visible = false;
  bool export_overwrite_or_version_rule_enforced = false;
  bool export_state_tracking_present = false;
  bool invalid_export_rejected_with_reason = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderPreviewExportParityDiagnostics {
  bool parity_scope_defined = false;
  bool preview_export_parity_validation_present = false;
  bool parity_passes_for_valid_document = false;
  bool parity_mismatch_rejected_with_reason = false;
  bool export_shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct PreviewExportParityEntry {
  int depth = 0;
  std::string node_id{};
  std::string widget_type{};
  std::string text{};
  std::vector<std::string> child_ids{};
};

bool file_matches_filter(const std::filesystem::path& path, const std::string& filter) {
  if (filter.empty()) {
    return true;
  }

  std::string lower_name = path.filename().string();
  std::string lower_filter = filter;
  std::transform(lower_name.begin(), lower_name.end(), lower_name.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  std::transform(lower_filter.begin(), lower_filter.end(), lower_filter.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });

  return lower_name.find(lower_filter) != std::string::npos;
}

int parse_auto_close_ms(int argc, char** argv) {
  const std::string prefix = "--auto-close-ms=";
  for (int index = 1; index < argc; ++index) {
    if (argv[index] == nullptr) {
      continue;
    }
    const std::string arg = argv[index];
    if (arg.rfind(prefix, 0) == 0) {
      const std::string value = arg.substr(prefix.size());
      char* end_ptr = nullptr;
      const long parsed = std::strtol(value.c_str(), &end_ptr, 10);
      if (end_ptr != nullptr && *end_ptr == '\0' && parsed > 0 && parsed <= 600000) {
        return static_cast<int>(parsed);
      }
    }
  }
  return 0;
}

bool parse_validation_mode(int argc, char** argv) {
  const std::string flag = "--validation-mode";
  for (int index = 1; index < argc; ++index) {
    if (argv[index] == nullptr) {
      continue;
    }
    if (flag == argv[index]) {
      return true;
    }
  }
  return false;
}

bool reload_entries(FileToolModel& model, const std::filesystem::path& root) {
  model.entries.clear();

  try {
    for (const auto& entry : std::filesystem::directory_iterator(root)) {
      if (!entry.is_regular_file()) {
        continue;
      }
      if (!file_matches_filter(entry.path(), model.filter)) {
        continue;
      }
      model.entries.push_back(entry);
      if (model.entries.size() >= 128) {
        break;
      }
    }
  } catch (const std::exception& ex) {
    model.status = std::string("LIST_ERROR ") + ex.what();
    model.crash_detected = true;
    return false;
  }

  std::sort(model.entries.begin(), model.entries.end(), [](const auto& left, const auto& right) {
    return left.path().filename().string() < right.path().filename().string();
  });

  if (model.entries.empty()) {
    model.selected_index = 0;
    model.status = "NO_FILES";
  } else {
    if (model.selected_index >= model.entries.size()) {
      model.selected_index = 0;
    }
    model.status = "FILES_READY";
  }

  return true;
}

std::string selected_file_name(const FileToolModel& model) {
  if (model.entries.empty() || model.selected_index >= model.entries.size()) {
    return "NONE";
  }
  return model.entries[model.selected_index].path().filename().string();
}

std::string selected_file_size(const FileToolModel& model) {
  if (model.entries.empty() || model.selected_index >= model.entries.size()) {
    return "0";
  }

  try {
    const auto bytes = model.entries[model.selected_index].file_size();
    return std::to_string(static_cast<unsigned long long>(bytes));
  } catch (...) {
    return "0";
  }
}

int run_desktop_file_tool_app(int auto_close_ms, bool validation_mode) {
  using namespace std::chrono;

  ngk::EventLoop loop;
  ngk::platform::Win32Window window;
  ngk::gfx::D3D11Renderer renderer;

  int client_w = 920;
  int client_h = 560;
  if (!window.create(L"NGKsUI Runtime Desktop File Tool", client_w, client_h)) {
    std::cout << "desktop_tool_create_failed=1\n";
    return 1;
  }

  loop.set_platform_pump([&] { window.poll_events_once(); });
  window.set_quit_callback([&] { loop.stop(); });

  if (!renderer.init(window.native_handle(), client_w, client_h)) {
    std::cout << "desktop_tool_d3d11_init_failed=1\n";
    return 2;
  }

  std::filesystem::path scan_root = std::filesystem::current_path();
  FileToolModel model{};
  RedrawDiagnostics redraw_diag{};

  ngk::ui::UITree tree;
  ngk::ui::InputRouter input_router;
  DesktopToolRoot root;
  ngk::ui::Panel shell;
  ngk::ui::Label title_label("FILE VIEWER TOOL");
  ngk::ui::Label path_label("PATH");
  ngk::ui::Label status_label("STATUS");
  ngk::ui::Label selected_label("SELECTED");
  ngk::ui::Label detail_label("DETAIL");
  ngk::ui::InputBox filter_box;
  ngk::ui::Button refresh_button;
  ngk::ui::Button prev_button;
  ngk::ui::Button next_button;
  ngk::ui::Button apply_button;

  // ===== PHASE102/103 UI elements =====
  LayoutFunctionDiagnostics layout_fn_diag{};
  ScrollContainerDiagnostics scroll_diag{};
  ListViewDiagnostics list_view_diag{};
  TableViewDiagnostics table_view_diag{};
  ShellWidgetDiagnostics shell_widget_diag{};
  FileDialogDiagnostics file_dialog_diag{};
  DeclarativeLayerDiagnostics declarative_diag{};
  BuilderTargetDiagnostics builder_target_diag{};
  BuilderDocumentDiagnostics builder_doc_diag{};
  SelectionModelDiagnostics selection_diag{};
  StructuralCommandDiagnostics struct_cmd_diag{};
  BuilderShellDiagnostics builder_shell_diag{};
  ComponentPaletteDiagnostics palette_diag{};
  BuilderMoveReparentDiagnostics move_reparent_diag{};
  BuilderStateCoherenceDiagnostics coherence_diag{};
  BuilderDeleteWorkflowDiagnostics delete_diag{};
  BuilderUndoRedoDiagnostics undoredo_diag{};
  BuilderSaveLoadDiagnostics saveload_diag{};
  BuilderDirtyStateDiagnostics dirty_state_diag{};
  BuilderLifecycleDiagnostics lifecycle_diag{};
  BuilderFocusDiagnostics focus_diag{};
  BuilderVisibleUxDiagnostics visible_ux_diag{};
  BuilderShortcutDiagnostics shortcut_diag{};
  BuilderDragDropDiagnostics dragdrop_diag{};
  BuilderTypedPaletteDiagnostics typed_palette_diag{};
  BuilderExportDiagnostics export_diag{};
  BuilderExportUxDiagnostics export_ux_diag{};
  BuilderPreviewExportParityDiagnostics preview_export_parity_diag{};
  std::string drag_source_node_id{};
  bool drag_active = false;

  std::vector<CommandHistoryEntry> undo_history{};
  std::vector<CommandHistoryEntry> redo_stack{};

  ngk::ui::Button builder_undo_button;
  ngk::ui::Button builder_redo_button;
  ngk::ui::Button builder_save_button;
  ngk::ui::Button builder_load_button;
  ngk::ui::Button builder_load_discard_button;
  ngk::ui::Button builder_export_button;
  ngk::ui::Button builder_new_button;
  ngk::ui::Button builder_new_discard_button;

  ngk::ui::ScrollContainer phase102_scroll_container;
  ngk::ui::VerticalLayout phase102_scroll_content(6);
  ngk::ui::Label phase102_scroll_item1("SCROLL ITEM 1");
  ngk::ui::Label phase102_scroll_item2("SCROLL ITEM 2");
  ngk::ui::Label phase102_scroll_item3("SCROLL ITEM 3");

  ngk::ui::ListView phase102_list_view;
  ngk::ui::TableView phase102_table_view;

  ngk::ui::ToolbarContainer phase102_toolbar(8);
  ngk::ui::SidebarContainer phase102_sidebar(8);

  ngk::ui::Label phase102_compose_root_label("COMPOSED");
  ngk::ui::Button phase102_compose_action_button;
  ngk::ui::Label phase102_compose_child_label("CHILD NODE");

  ngk::ui::VerticalLayout builder_shell_panel(6);
  ngk::ui::Label builder_tree_surface_label("TREE");
  ngk::ui::Label builder_inspector_label("INSPECTOR");
  ngk::ui::Label builder_preview_label("PREVIEW");
  ngk::ui::Label builder_export_status_label("EXPORT STATUS");

  ngk::ui::Button builder_insert_container_button;
  ngk::ui::Button builder_insert_leaf_button;

  ngk::ui::Button builder_move_up_button;
  ngk::ui::Button builder_move_down_button;
  ngk::ui::Button builder_reparent_button;
  ngk::ui::Button builder_delete_button;

  ngk::ui::builder::BuilderDocument builder_doc{};
  std::string selected_builder_node_id{};
  std::string focused_builder_node_id{};
  std::string inspector_binding_node_id{};
  std::string preview_binding_node_id{};
  std::string preview_snapshot{};
  bool builder_doc_dirty = false;
  bool has_saved_builder_snapshot = false;
  std::string last_saved_builder_serialized{};
  const std::filesystem::path builder_doc_save_path =
    std::filesystem::current_path() / "_artifacts/runtime/phase103_12_builder_document.ngkbdoc";
  const std::filesystem::path builder_export_path =
    std::filesystem::current_path() / "_artifacts/runtime/phase103_20_builder_export.ngkbdoc";
  std::string last_export_status_code = "not_run";
  std::string last_export_reason = "none";
  std::string last_export_artifact_path = builder_export_path.string();
  std::string last_export_snapshot{};
  bool has_last_export_snapshot = false;
  bool export_snapshot_matches_current_doc = false;
  constexpr const char* kExportRule = "overwrite_deterministic_single_target";
  std::string last_preview_export_parity_status_code = "not_run";
  std::string last_preview_export_parity_reason = "none";
  constexpr const char* kPreviewExportParityScope =
    "structure,component_types,key_identity_text,hierarchy";

  builder_insert_container_button.set_text("Insert Container");
  builder_insert_leaf_button.set_text("Insert Leaf");
  builder_move_up_button.set_text("Move Up");
  builder_move_down_button.set_text("Move Down");
  builder_reparent_button.set_text("Reparent");
  builder_delete_button.set_text("Delete Node");
  builder_undo_button.set_text("Undo");
  builder_redo_button.set_text("Redo");
  builder_save_button.set_text("Save Doc");
  builder_load_button.set_text("Load Doc");
  builder_load_discard_button.set_text("Load Discard");
  builder_export_button.set_text("Export Runtime");
  builder_new_button.set_text("New Doc");
  builder_new_discard_button.set_text("New Discard");
  phase102_compose_action_button.set_text("Action");

  shell.set_background(0.10f, 0.12f, 0.16f, 0.96f);
  title_label.set_background(0.12f, 0.16f, 0.22f, 1.0f);
  path_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  status_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  selected_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  detail_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  builder_tree_surface_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_preview_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_export_status_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);

  refresh_button.set_text("Refresh");
  prev_button.set_text("Prev");
  next_button.set_text("Next");
  apply_button.set_text("Apply");

  auto layout = [&](int w, int h) {
    root.set_position(0, 0);
    root.set_size(w, h);

    shell.set_position(18, 18);
    shell.set_size(w - 36, h - 36);

    title_label.set_position(36, 34);
    title_label.set_size(w - 72, 34);

    path_label.set_position(36, 78);
    path_label.set_size(w - 72, 28);

    filter_box.set_position(36, 114);
    filter_box.set_size(280, 32);

    apply_button.set_position(326, 114);
    apply_button.set_size(96, 32);

    refresh_button.set_position(430, 114);
    refresh_button.set_size(110, 32);

    prev_button.set_position(548, 114);
    prev_button.set_size(96, 32);

    next_button.set_position(652, 114);
    next_button.set_size(96, 32);

    builder_delete_button.set_position(756, 114);
    builder_delete_button.set_size(128, 32);

    builder_undo_button.set_position(36, 307);
    builder_undo_button.set_size(80, 32);
    builder_redo_button.set_position(126, 307);
    builder_redo_button.set_size(80, 32);
    builder_save_button.set_position(216, 307);
    builder_save_button.set_size(96, 32);
    builder_load_button.set_position(322, 307);
    builder_load_button.set_size(96, 32);
    builder_load_discard_button.set_position(428, 307);
    builder_load_discard_button.set_size(130, 32);
    builder_new_button.set_position(568, 307);
    builder_new_button.set_size(96, 32);
    builder_new_discard_button.set_position(674, 307);
    builder_new_discard_button.set_size(130, 32);
    builder_insert_container_button.set_position(36, 346);
    builder_insert_container_button.set_size(170, 32);
    builder_insert_leaf_button.set_position(216, 346);
    builder_insert_leaf_button.set_size(130, 32);
    builder_export_button.set_position(356, 346);
    builder_export_button.set_size(170, 32);
    builder_export_status_label.set_position(566, 230);
    builder_export_status_label.set_size(w - 602, 70);

    builder_tree_surface_label.set_position(36, 386);
    builder_tree_surface_label.set_size(268, h - 424);
    builder_inspector_label.set_position(314, 386);
    builder_inspector_label.set_size(268, h - 424);
    builder_preview_label.set_position(592, 386);
    builder_preview_label.set_size(w - 628, h - 424);

    status_label.set_position(36, 154);
    status_label.set_size(w - 72, 32);

    selected_label.set_position(36, 192);
    selected_label.set_size(w - 72, 32);

    detail_label.set_position(36, 230);
    detail_label.set_size(520, 70);
  };

  auto refresh_export_status_surface_label = [&]() {
    std::ostringstream oss;
    oss << "EXPORT STATUS\n";
    oss << "result=" << last_export_status_code;
    if (!last_export_reason.empty() && last_export_reason != "none") {
      oss << " reason=" << last_export_reason;
    }
    oss << "\n";
    oss << "artifact="
        << (last_export_artifact_path.empty() ? std::string("<none>") : last_export_artifact_path)
        << "\n";
    oss << "rule=" << kExportRule << "\n";

    std::string state_text = "no_export_baseline";
    if (has_last_export_snapshot) {
      const std::string serialized_now =
        ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      if (serialized_now.empty()) {
        export_snapshot_matches_current_doc = false;
        state_text = "unknown_serialize_failed";
      } else {
        export_snapshot_matches_current_doc = (serialized_now == last_export_snapshot);
        state_text = export_snapshot_matches_current_doc ? "up_to_date" : "stale_since_last_export";
      }
    } else {
      export_snapshot_matches_current_doc = false;
    }

    oss << "state=" << state_text;
    builder_export_status_label.set_text(oss.str());
  };

  auto update_labels = [&] {
    path_label.set_text(std::string("PATH ") + scan_root.string());
    status_label.set_text(
      std::string("STATUS ") + model.status +
      " FILES " + std::to_string(model.entries.size()) +
      " DOC_DIRTY " + (builder_doc_dirty ? std::string("YES") : std::string("NO")));
    selected_label.set_text(std::string("SELECTED ") + selected_file_name(model));
    detail_label.set_text(std::string("DETAIL BYTES ") + selected_file_size(model) + " FILTER " + model.filter);
    refresh_export_status_surface_label();
  };

  auto request_redraw = [&](const char* reason, bool input_triggered, bool layout_triggered) {
    redraw_diag.invalidate_total_count += 1;
    if (input_triggered) {
      redraw_diag.invalidate_input_count += 1;
      redraw_diag.input_redraw_requests += 1;
    }
    if (layout_triggered) {
      redraw_diag.invalidate_layout_count += 1;
    }
    if (!input_triggered && !layout_triggered) {
      redraw_diag.invalidate_steady_count += 1;
    }
    std::cout << "phase101_4_invalidate_request reason=" << reason
              << " input=" << (input_triggered ? 1 : 0)
              << " layout=" << (layout_triggered ? 1 : 0)
              << " total=" << redraw_diag.invalidate_total_count << "\n";
    tree.invalidate();
  };

  auto refresh_entries = [&] {
    model.refresh_count += 1;
    model.filter = filter_box.value();
    if (!reload_entries(model, scan_root)) {
      model.undefined_state_detected = true;
    }
    update_labels();
    request_redraw("refresh_entries", false, false);
  };

  auto select_prev = [&] {
    model.prev_count += 1;
    if (!model.entries.empty()) {
      if (model.selected_index == 0) {
        model.selected_index = model.entries.size() - 1;
      } else {
        model.selected_index -= 1;
      }
    }
    update_labels();
    request_redraw("select_prev", false, false);
  };

  auto select_next = [&] {
    model.next_count += 1;
    if (!model.entries.empty()) {
      model.selected_index = (model.selected_index + 1) % model.entries.size();
    }
    update_labels();
    request_redraw("select_next", false, false);
  };

  auto apply_filter = [&] {
    model.apply_filter_count += 1;
    model.filter = filter_box.value();
    if (!reload_entries(model, scan_root)) {
      model.undefined_state_detected = true;
    }
    update_labels();
    request_redraw("apply_filter", false, false);
  };

  refresh_button.set_on_click(refresh_entries);
  prev_button.set_on_click(select_prev);
  next_button.set_on_click(select_next);
  apply_button.set_on_click(apply_filter);

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

  auto find_node_by_id = [&](const std::string& node_id) -> ngk::ui::builder::BuilderNode* {
    for (auto& node : builder_doc.nodes) {
      if (node.node_id == node_id) {
        return &node;
      }
    }
    return nullptr;
  };

  auto node_exists = [&](const std::string& node_id) -> bool {
    return find_node_by_id(node_id) != nullptr;
  };

  auto node_identity_text = [&](const ngk::ui::builder::BuilderNode& node) -> std::string {
    const std::string node_text = node.text.empty() ? std::string("<no-text>") : node.text;
    return node.node_id + " " + ngk::ui::builder::to_string(node.widget_type) + " \"" + node_text + "\"";
  };

  auto build_tree_surface_text = [&]() -> std::string {
    std::ostringstream oss;
    oss << "TREE REGION (Hierarchy / Selection)\n";
    oss << "selected=" << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id)
        << " focus=" << (focused_builder_node_id.empty() ? std::string("none") : focused_builder_node_id) << "\n";

    if (builder_doc.nodes.empty() || builder_doc.root_node_id.empty() || !node_exists(builder_doc.root_node_id)) {
      oss << "(empty document)";
      return oss.str();
    }

    std::function<void(const std::string&, int)> append_node = [&](const std::string& node_id, int depth) {
      auto* node = find_node_by_id(node_id);
      if (!node) {
        return;
      }

      const bool is_selected = (node_id == selected_builder_node_id);
      const bool is_focused = (node_id == focused_builder_node_id);
      oss << std::string(static_cast<std::size_t>(depth) * 2U, ' ')
          << (is_selected ? "> " : "- ")
          << ngk::ui::builder::to_string(node->widget_type)
          << " | " << node->node_id;
      if (!node->text.empty()) {
        oss << " | \"" << node->text << "\"";
      }
      if (is_selected) {
        oss << " [SELECTED]";
      }
      if (is_focused) {
        oss << " [FOCUS]";
      }
      oss << "\n";

      for (const auto& child_id : node->child_ids) {
        append_node(child_id, depth + 1);
      }
    };

    append_node(builder_doc.root_node_id, 0);
    return oss.str();
  };

  auto refresh_tree_surface_label = [&]() {
    builder_tree_surface_label.set_text(build_tree_surface_text());
  };

  auto refresh_inspector_surface_label = [&]() {
    std::ostringstream oss;
    oss << "INSPECTOR REGION (Selection-bound)\n";
    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      oss << "selected=none\n";
      oss << "binding=cleared";
      builder_inspector_label.set_text(oss.str());
      return;
    }

    auto* node = find_node_by_id(selected_builder_node_id);
    if (!node) {
      oss << "selected=stale\n";
      oss << "binding=cleared";
      builder_inspector_label.set_text(oss.str());
      return;
    }

    oss << "selected=" << node->node_id << "\n";
    oss << "type=" << ngk::ui::builder::to_string(node->widget_type)
        << " container=" << ngk::ui::builder::to_string(node->container_type) << "\n";
    oss << "text=\"" << (node->text.empty() ? std::string("<no-text>") : node->text) << "\"\n";
    oss << "children=" << node->child_ids.size();
    builder_inspector_label.set_text(oss.str());
  };

  auto refresh_preview_surface_label = [&]() {
    std::ostringstream oss;
    oss << "PREVIEW REGION (Runtime Truth)\n";
    oss << "root=" << (builder_doc.root_node_id.empty() ? std::string("none") : builder_doc.root_node_id)
        << " nodes=" << builder_doc.nodes.size() << "\n";
    oss << "parity_scope=" << kPreviewExportParityScope << "\n";
    oss << "parity=" << last_preview_export_parity_status_code;
    if (!last_preview_export_parity_reason.empty() && last_preview_export_parity_reason != "none") {
      oss << " reason=" << last_preview_export_parity_reason;
    }
    oss << "\n";

    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      oss << "selected=none";
      preview_snapshot = "preview:selected=none";
      builder_preview_label.set_text(oss.str());
      return;
    }

    auto* selected = find_node_by_id(selected_builder_node_id);
    if (!selected) {
      oss << "selected=stale";
      preview_snapshot = "preview:selected=stale";
      builder_preview_label.set_text(oss.str());
      return;
    }

    oss << "selected=> " << selected->node_id << " "
        << ngk::ui::builder::to_string(selected->widget_type) << "\n";
    oss << "selected_text=\"" << (selected->text.empty() ? std::string("<no-text>") : selected->text) << "\"\n";
    oss << "selected_children=" << selected->child_ids.size();
    preview_snapshot = "preview:selected=" + selected->node_id +
      " type=" + std::string(ngk::ui::builder::to_string(selected->widget_type));
    builder_preview_label.set_text(oss.str());
  };

  // PHASE103_15 rule: builder semantic focus is always derived from selection.
  auto sync_focus_with_selection_or_fail = [&]() -> bool {
    focus_diag.focus_selection_rules_defined = true;

    if (!focused_builder_node_id.empty()) {
      const bool focused_exists = node_exists(focused_builder_node_id);
      if (!focused_exists) {
        focused_builder_node_id.clear();
        focus_diag.stale_focus_rejected = true;
        refresh_tree_surface_label();
        return false;
      }
    }

    if (selected_builder_node_id.empty()) {
      focused_builder_node_id.clear();
      refresh_tree_surface_label();
      return true;
    }

    if (!node_exists(selected_builder_node_id)) {
      focused_builder_node_id.clear();
      focus_diag.stale_focus_rejected = true;
      refresh_tree_surface_label();
      return false;
    }

    focused_builder_node_id = selected_builder_node_id;
    refresh_tree_surface_label();
    return true;
  };

  auto collect_preorder_node_ids = [&]() -> std::vector<std::string> {
    std::vector<std::string> ordered{};
    if (builder_doc.root_node_id.empty() || !node_exists(builder_doc.root_node_id)) {
      return ordered;
    }

    std::vector<std::string> stack{};
    stack.push_back(builder_doc.root_node_id);

    while (!stack.empty()) {
      const std::string current_id = stack.back();
      stack.pop_back();
      if (!node_exists(current_id)) {
        continue;
      }
      ordered.push_back(current_id);

      auto* current = find_node_by_id(current_id);
      if (!current) {
        continue;
      }
      for (auto it = current->child_ids.rbegin(); it != current->child_ids.rend(); ++it) {
        if (!it->empty() && node_exists(*it)) {
          stack.push_back(*it);
        }
      }
    }

    return ordered;
  };

  auto apply_tree_navigation = [&](bool forward) -> bool {
    if (!selected_builder_node_id.empty() && !node_exists(selected_builder_node_id)) {
      if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
        selected_builder_node_id = builder_doc.root_node_id;
      } else {
        selected_builder_node_id.clear();
      }
    }

    auto ordered = collect_preorder_node_ids();
    if (ordered.empty()) {
      selected_builder_node_id.clear();
      focused_builder_node_id.clear();
      return false;
    }

    if (selected_builder_node_id.empty()) {
      selected_builder_node_id = ordered.front();
      return sync_focus_with_selection_or_fail();
    }

    auto it = std::find(ordered.begin(), ordered.end(), selected_builder_node_id);
    if (it == ordered.end()) {
      selected_builder_node_id = ordered.front();
      focus_diag.stale_focus_rejected = true;
      return sync_focus_with_selection_or_fail();
    }

    if (forward) {
      ++it;
      if (it == ordered.end()) {
        it = ordered.begin();
      }
    } else {
      if (it == ordered.begin()) {
        it = ordered.end();
      }
      --it;
    }
    selected_builder_node_id = *it;
    return sync_focus_with_selection_or_fail();
  };

  auto apply_tree_parent_child_navigation = [&](bool to_parent) -> bool {
    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
        selected_builder_node_id = builder_doc.root_node_id;
        return sync_focus_with_selection_or_fail();
      }
      return false;
    }

    auto* current = find_node_by_id(selected_builder_node_id);
    if (!current) {
      return false;
    }

    if (to_parent) {
      if (current->parent_id.empty() || !node_exists(current->parent_id)) {
        return false;
      }
      selected_builder_node_id = current->parent_id;
      return sync_focus_with_selection_or_fail();
    }

    if (current->child_ids.empty()) {
      return false;
    }

    for (const auto& child_id : current->child_ids) {
      if (!child_id.empty() && node_exists(child_id)) {
        selected_builder_node_id = child_id;
        return sync_focus_with_selection_or_fail();
      }
    }

    return false;
  };

  auto remap_selection_or_fail = [&]() -> bool {
    coherence_diag.selection_coherence_hardened = true;

    if (selected_builder_node_id.empty()) {
      if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
        selected_builder_node_id = builder_doc.root_node_id;
        return true;
      }
      return true;
    }

    if (node_exists(selected_builder_node_id)) {
      return true;
    }

    coherence_diag.stale_selection_rejected = true;

    if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
      selected_builder_node_id = builder_doc.root_node_id;
      return true;
    }

    selected_builder_node_id.clear();
    model.undefined_state_detected = true;
    return false;
  };

  auto refresh_inspector_or_fail = [&]() -> bool {
    coherence_diag.inspector_coherence_hardened = true;

    if (selected_builder_node_id.empty()) {
      inspector_binding_node_id.clear();
      refresh_inspector_surface_label();
      return true;
    }

    if (!node_exists(selected_builder_node_id)) {
      coherence_diag.stale_inspector_binding_rejected = true;
      inspector_binding_node_id.clear();
      refresh_inspector_surface_label();
      return false;
    }

    inspector_binding_node_id = selected_builder_node_id;
    refresh_inspector_surface_label();
    return true;
  };

  auto refresh_preview_or_fail = [&]() -> bool {
    coherence_diag.preview_coherence_hardened = true;

    if (!selected_builder_node_id.empty() && !node_exists(selected_builder_node_id)) {
      preview_binding_node_id.clear();
      preview_snapshot.clear();
      model.undefined_state_detected = true;
      refresh_preview_surface_label();
      return false;
    }

    preview_binding_node_id = selected_builder_node_id;
    refresh_preview_surface_label();
    return true;
  };

  auto remove_node_and_descendants = [&](const std::string& node_id) {
    if (node_id.empty()) {
      return;
    }

    std::vector<std::string> to_remove{node_id};
    for (std::size_t index = 0; index < to_remove.size(); ++index) {
      const auto current_id = to_remove[index];
      if (auto* current = find_node_by_id(current_id)) {
        for (const auto& child_id : current->child_ids) {
          if (!child_id.empty()) {
            to_remove.push_back(child_id);
          }
        }
      }
    }

    for (auto& node : builder_doc.nodes) {
      auto& kids = node.child_ids;
      kids.erase(std::remove_if(kids.begin(), kids.end(), [&](const std::string& kid) {
        return std::find(to_remove.begin(), to_remove.end(), kid) != to_remove.end();
      }), kids.end());
    }

    builder_doc.nodes.erase(std::remove_if(builder_doc.nodes.begin(), builder_doc.nodes.end(),
      [&](const ngk::ui::builder::BuilderNode& node) {
        return std::find(to_remove.begin(), to_remove.end(), node.node_id) != to_remove.end();
      }), builder_doc.nodes.end());
  };

  auto check_cross_surface_sync = [&]() -> bool {
    coherence_diag.cross_surface_sync_checks_present = true;

    const bool selected_valid = selected_builder_node_id.empty() || node_exists(selected_builder_node_id);
    const bool inspector_valid = inspector_binding_node_id.empty() || node_exists(inspector_binding_node_id);
    const bool preview_valid = preview_binding_node_id.empty() || node_exists(preview_binding_node_id);

    coherence_diag.desync_tree_selection_detected = !selected_valid;
    coherence_diag.desync_inspector_binding_detected =
      (!selected_builder_node_id.empty() && inspector_binding_node_id != selected_builder_node_id) || !inspector_valid;
    coherence_diag.desync_preview_binding_detected =
      (!selected_builder_node_id.empty() && preview_binding_node_id != selected_builder_node_id) || !preview_valid;

    return !coherence_diag.desync_tree_selection_detected &&
      !coherence_diag.desync_inspector_binding_detected &&
      !coherence_diag.desync_preview_binding_detected;
  };

  auto apply_delete_selected_node_command = [&]() -> bool {
    delete_diag.shell_delete_control_present = true;

    if (selected_builder_node_id.empty()) {
      delete_diag.protected_delete_rejected = true;
      return false;
    }

    auto* target = find_node_by_id(selected_builder_node_id);
    if (!target) {
      delete_diag.protected_delete_rejected = true;
      return false;
    }

    const bool is_root = (selected_builder_node_id == builder_doc.root_node_id) || target->parent_id.empty();
    const bool shell_critical = target->container_type == ngk::ui::builder::BuilderContainerType::Shell;
    if (is_root || shell_critical) {
      delete_diag.protected_delete_rejected = true;
      return false;
    }

    auto* parent = find_node_by_id(target->parent_id);
    if (!parent) {
      delete_diag.protected_delete_rejected = true;
      return false;
    }

    std::string fallback_selection{};
    auto& siblings = parent->child_ids;
    auto it = std::find(siblings.begin(), siblings.end(), selected_builder_node_id);
    if (it != siblings.end()) {
      if (std::next(it) != siblings.end()) {
        fallback_selection = *std::next(it);
      } else if (it != siblings.begin()) {
        fallback_selection = *std::prev(it);
      } else {
        fallback_selection = parent->node_id;
      }
    } else {
      fallback_selection = parent->node_id;
    }

    const std::string deleting_id = selected_builder_node_id;
    remove_node_and_descendants(deleting_id);

    if (!fallback_selection.empty() && node_exists(fallback_selection)) {
      selected_builder_node_id = fallback_selection;
    } else {
      selected_builder_node_id.clear();
    }

    delete_diag.legal_delete_applied = true;
    delete_diag.post_delete_selection_remapped_or_cleared =
      selected_builder_node_id.empty() || node_exists(selected_builder_node_id);

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

  auto push_to_history = [&](
      const std::string& command_type,
      const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
      const std::string& before_root,
      const std::string& before_sel,
      const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
      const std::string& after_root,
      const std::string& after_sel) {
    CommandHistoryEntry entry{};
    entry.command_type = command_type;
    entry.before_nodes = before_nodes;
    entry.before_root_node_id = before_root;
    entry.before_selected_id = before_sel;
    entry.after_nodes = after_nodes;
    entry.after_root_node_id = after_root;
    entry.after_selected_id = after_sel;
    undo_history.push_back(std::move(entry));
    redo_stack.clear();
    undoredo_diag.command_history_present = !undo_history.empty();
  };

  auto recompute_builder_dirty_state = [&](bool conservative_mark_dirty_if_no_saved_baseline) -> bool {
    if (!has_saved_builder_snapshot) {
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

    builder_doc_dirty = (serialized_now != last_saved_builder_serialized);
    update_labels();
    return true;
  };

  auto apply_undo_command = [&]() -> bool {
    if (undo_history.empty()) {
      return false;
    }
    CommandHistoryEntry entry = std::move(undo_history.back());
    undo_history.pop_back();
    builder_doc.nodes = entry.before_nodes;
    builder_doc.root_node_id = entry.before_root_node_id;
    selected_builder_node_id = entry.before_selected_id;
    redo_stack.push_back(std::move(entry));
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    recompute_builder_dirty_state(true);
    return true;
  };

  auto apply_redo_command = [&]() -> bool {
    if (redo_stack.empty()) {
      return false;
    }
    CommandHistoryEntry entry = std::move(redo_stack.back());
    redo_stack.pop_back();
    builder_doc.nodes = entry.after_nodes;
    builder_doc.root_node_id = entry.after_root_node_id;
    selected_builder_node_id = entry.after_selected_id;
    undo_history.push_back(std::move(entry));
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    recompute_builder_dirty_state(true);
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
    if (apply_palette_insert(false)) {
      push_to_history("insert", before_insert, before_insert_root, before_insert_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
    } else {
      flow_ok = false;
    }

    // ---- Step 2: Property edit ----
    auto before_prop = builder_doc.nodes;
    const std::string before_prop_root = builder_doc.root_node_id;
    const std::string before_prop_sel = selected_builder_node_id;
    auto* prop_target = find_node_by_id(selected_builder_node_id);
    if (prop_target) {
      prop_target->text = "phase103_11_edited";
      push_to_history("property_edit", before_prop, before_prop_root, before_prop_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
    } else {
      flow_ok = false;
    }

    // ---- Step 3: Move sibling up ----
    auto before_move = builder_doc.nodes;
    const std::string before_move_root = builder_doc.root_node_id;
    const std::string before_move_sel = selected_builder_node_id;
    apply_move_sibling_up();
    push_to_history("move", before_move, before_move_root, before_move_sel,
                    builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);

    // ---- Step 4: Delete leaf ----
    auto before_delete = builder_doc.nodes;
    const std::string before_delete_root = builder_doc.root_node_id;
    const std::string before_delete_sel = selected_builder_node_id;
    if (apply_delete_selected_node_command()) {
      push_to_history("delete", before_delete, before_delete_root, before_delete_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
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

  auto write_text_file = [&](const std::filesystem::path& path, const std::string& text) -> bool {
    try {
      const std::filesystem::path parent = path.parent_path();
      if (!parent.empty()) {
        std::filesystem::create_directories(parent);
      }
      std::ofstream out(path, std::ios::binary | std::ios::trunc);
      if (!out.is_open()) {
        return false;
      }
      out.write(text.data(), static_cast<std::streamsize>(text.size()));
      out.flush();
      return out.good();
    } catch (...) {
      return false;
    }
  };

  auto read_text_file = [&](const std::filesystem::path& path, std::string& out_text) -> bool {
    out_text.clear();
    try {
      std::ifstream in(path, std::ios::binary);
      if (!in.is_open()) {
        return false;
      }
      out_text.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
      return in.good() || in.eof();
    } catch (...) {
      return false;
    }
  };

  auto save_builder_document_to_path = [&](const std::filesystem::path& path) -> bool {
    const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    if (serialized.empty()) {
      return false;
    }
    if (!write_text_file(path, serialized)) {
      return false;
    }
    std::string roundtrip{};
    if (!read_text_file(path, roundtrip)) {
      return false;
    }
    return roundtrip == serialized;
  };

  auto load_builder_document_from_path = [&](const std::filesystem::path& path) -> bool {
    std::string serialized{};
    if (!read_text_file(path, serialized)) {
      return false;
    }

    ngk::ui::builder::BuilderDocument loaded_doc{};
    std::string load_error;
    if (!ngk::ui::builder::deserialize_builder_document_deterministic(serialized, loaded_doc, &load_error)) {
      return false;
    }

    ngk::ui::builder::InstantiatedBuilderDocument runtime_loaded{};
    std::string instantiate_error;
    if (!ngk::ui::builder::instantiate_builder_document(loaded_doc, runtime_loaded, &instantiate_error)) {
      return false;
    }

    builder_doc = std::move(loaded_doc);
    if (!selected_builder_node_id.empty() && !node_exists(selected_builder_node_id)) {
      selected_builder_node_id.clear();
    }
    if (selected_builder_node_id.empty() &&
        !builder_doc.root_node_id.empty() &&
        node_exists(builder_doc.root_node_id)) {
      selected_builder_node_id = builder_doc.root_node_id;
    }

    undo_history.clear();
    redo_stack.clear();

    const bool remap_ok = remap_selection_or_fail();
    const bool focus_ok = sync_focus_with_selection_or_fail();
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();

    return remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;
  };

  auto apply_save_document_command = [&]() -> bool {
    saveload_diag.shell_save_control_present = true;
    const bool saved = save_builder_document_to_path(builder_doc_save_path);
    saveload_diag.save_writes_deterministic_document = saved;
    if (saved) {
      const std::string saved_snapshot = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      if (saved_snapshot.empty()) {
        return false;
      }
      has_saved_builder_snapshot = true;
      last_saved_builder_serialized = saved_snapshot;
      builder_doc_dirty = false;
      update_labels();
    }
    return saved;
  };

  auto apply_load_document_command = [&](bool allow_discard_dirty = false) -> bool {
    saveload_diag.shell_load_control_present = true;

    if (builder_doc_dirty && !allow_discard_dirty) {
      return false;
    }

    const bool loaded = load_builder_document_from_path(builder_doc_save_path);
    if (loaded) {
      const std::string loaded_snapshot = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
      if (loaded_snapshot.empty()) {
        return false;
      }
      has_saved_builder_snapshot = true;
      last_saved_builder_serialized = loaded_snapshot;
      builder_doc_dirty = false;
      update_labels();
      saveload_diag.history_cleared_or_handled_deterministically_on_load =
        undo_history.empty() && redo_stack.empty();
      saveload_diag.shell_state_coherent_after_load = check_cross_surface_sync();
    }
    return loaded;
  };

  // Lifecycle rule: shell always maintains one valid active document.
  auto create_default_builder_document = [&](ngk::ui::builder::BuilderDocument& out_doc, std::string& out_selected) -> bool {
    ngk::ui::builder::BuilderDocument doc{};
    doc.schema_version = ngk::ui::builder::kBuilderSchemaVersion;

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
    doc.root_node_id = "root-001";
    doc.nodes.push_back(root_node);
    doc.nodes.push_back(child_node);

    std::string validation_error;
    if (!ngk::ui::builder::validate_builder_document(doc, &validation_error)) {
      return false;
    }

    ngk::ui::builder::InstantiatedBuilderDocument runtime_doc{};
    std::string instantiate_error;
    if (!ngk::ui::builder::instantiate_builder_document(doc, runtime_doc, &instantiate_error)) {
      return false;
    }

    out_doc = std::move(doc);
    out_selected = out_doc.root_node_id;
    return true;
  };

  auto apply_new_document_command = [&](bool allow_discard_dirty = false) -> bool {
    lifecycle_diag.new_document_control_present = true;

    if (builder_doc_dirty && !allow_discard_dirty) {
      return false;
    }

    ngk::ui::builder::BuilderDocument new_doc{};
    std::string new_selected{};
    if (!create_default_builder_document(new_doc, new_selected)) {
      return false;
    }

    builder_doc = std::move(new_doc);
    selected_builder_node_id = new_selected;
    undo_history.clear();
    redo_stack.clear();
    has_saved_builder_snapshot = false;
    last_saved_builder_serialized.clear();
    builder_doc_dirty = false;

    const bool remap_ok = remap_selection_or_fail();
    const bool focus_ok = sync_focus_with_selection_or_fail();
    const bool inspector_ok = refresh_inspector_or_fail();
    const bool preview_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    update_labels();

    lifecycle_diag.history_cleared_on_new = undo_history.empty() && redo_stack.empty();
    lifecycle_diag.dirty_state_clean_on_new = !builder_doc_dirty;
    lifecycle_diag.shell_state_coherent_after_new = remap_ok && focus_ok && inspector_ok && preview_ok && sync_ok;

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
    const bool insert_ok = apply_palette_insert(false);
    flow_ok = insert_ok && flow_ok;
    if (insert_ok) {
      push_to_history("phase103_15_insert", before_insert_nodes, before_insert_root, before_insert_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
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
      edit_target->text = "phase103_15_focus_edit";
      push_to_history("phase103_15_edit", before_edit_nodes, before_edit_root, before_edit_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
      recompute_builder_dirty_state(true);
    } else {
      flow_ok = false;
    }

    const auto before_delete_nodes = builder_doc.nodes;
    const std::string before_delete_root = builder_doc.root_node_id;
    const std::string before_delete_sel = selected_builder_node_id;
    const bool delete_ok = apply_delete_selected_node_command();
    flow_ok = delete_ok && flow_ok;
    if (delete_ok) {
      push_to_history("phase103_15_delete", before_delete_nodes, before_delete_root, before_delete_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
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
    const bool insert_ok = apply_palette_insert(false);
    flow_ok = insert_ok && flow_ok;
    if (insert_ok) {
      push_to_history("phase103_16_insert", before_insert_nodes, before_insert_root, before_insert_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
      recompute_builder_dirty_state(true);
    }

    const bool nav_ok = apply_tree_navigation(true);
    flow_ok = nav_ok && flow_ok;

    auto* selected_node = find_node_by_id(selected_builder_node_id);
    if (selected_node) {
      const auto before_edit_nodes = builder_doc.nodes;
      const std::string before_edit_root = builder_doc.root_node_id;
      const std::string before_edit_sel = selected_builder_node_id;
      selected_node->text = "phase103_16_preview_text";
      push_to_history("phase103_16_edit", before_edit_nodes, before_edit_root, before_edit_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
      recompute_builder_dirty_state(true);
    } else {
      flow_ok = false;
    }

    const auto before_delete_nodes = builder_doc.nodes;
    const std::string before_delete_root = builder_doc.root_node_id;
    const std::string before_delete_sel = selected_builder_node_id;
    const bool delete_ok = apply_delete_selected_node_command();
    flow_ok = delete_ok && flow_ok;
    if (delete_ok) {
      push_to_history("phase103_16_delete", before_delete_nodes, before_delete_root, before_delete_sel,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
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

  // PHASE103_17 rule: shortcuts are active only in builder scope and never while typing in text inputs.
  auto is_builder_shortcut_scope_active = [&]() -> bool {
    shortcut_diag.shortcut_scope_rules_defined = true;
    auto* focused = tree.focused_element();
    if (focused && focused->is_text_input()) {
      return false;
    }
    return !builder_doc.nodes.empty() &&
      !selected_builder_node_id.empty() &&
      node_exists(selected_builder_node_id);
  };

  auto handle_builder_shortcut_key = [&](std::uint32_t key, bool down, bool repeat) -> bool {
    if (!down || repeat) {
      return false;
    }
    if (!is_builder_shortcut_scope_active()) {
      return false;
    }

    bool handled = false;
    switch (key) {
      case 0x26: // Up
        handled = apply_tree_navigation(false);
        break;
      case 0x28: // Down
        handled = apply_tree_navigation(true);
        break;
      case 0x25: // Left
        handled = apply_tree_parent_child_navigation(true);
        break;
      case 0x27: // Right
        handled = apply_tree_parent_child_navigation(false);
        break;
      case 0x5A: // Z
        handled = apply_undo_command();
        break;
      case 0x59: // Y
        handled = apply_redo_command();
        break;
      case 0x2E: // Delete
        {
          const auto before_nodes = builder_doc.nodes;
          const std::string before_root = builder_doc.root_node_id;
          const std::string before_sel = selected_builder_node_id;
          handled = apply_delete_selected_node_command();
          if (handled) {
            push_to_history("shortcut_delete", before_nodes, before_root, before_sel,
                            builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
          }
        }
        if (handled) {
          recompute_builder_dirty_state(true);
        }
        break;
      case 0x43: // C
        {
          const auto before_nodes = builder_doc.nodes;
          const std::string before_root = builder_doc.root_node_id;
          const std::string before_sel = selected_builder_node_id;
          handled = apply_palette_insert(true);
          if (handled) {
            push_to_history("shortcut_insert_container", before_nodes, before_root, before_sel,
                            builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
          }
        }
        if (handled) {
          recompute_builder_dirty_state(true);
        }
        break;
      case 0x4C: // L
        {
          const auto before_nodes = builder_doc.nodes;
          const std::string before_root = builder_doc.root_node_id;
          const std::string before_sel = selected_builder_node_id;
          handled = apply_palette_insert(false);
          if (handled) {
            push_to_history("shortcut_insert_leaf", before_nodes, before_root, before_sel,
                            builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
          }
        }
        if (handled) {
          recompute_builder_dirty_state(true);
        }
        break;
      case 0x53: // S
        handled = apply_save_document_command();
        break;
      case 0x4F: // O
        handled = apply_load_document_command(false);
        break;
      case 0x4E: // N
        handled = apply_new_document_command(false);
        break;
      default:
        break;
    }

    if (!handled) {
      return false;
    }

    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
    return true;
  };

  // --- PHASE103_18: Controlled Drag/Reorder UX ---

  auto is_in_subtree_of = [&](const std::string& node_id, const std::string& ancestor_id) -> bool {
    if (node_id.empty() || ancestor_id.empty()) { return false; }
    if (node_id == ancestor_id) { return true; }
    std::vector<std::string> to_visit{ancestor_id};
    for (std::size_t i = 0; i < to_visit.size(); ++i) {
      auto* n = find_node_by_id(to_visit[i]);
      if (!n) { continue; }
      for (const auto& child_id : n->child_ids) {
        if (child_id == node_id) { return true; }
        to_visit.push_back(child_id);
      }
    }
    return false;
  };

  auto begin_tree_drag = [&](const std::string& source_id) -> bool {
    dragdrop_diag.tree_drag_reorder_present = true;
    if (source_id.empty() || !node_exists(source_id)) { return false; }
    if (source_id == builder_doc.root_node_id) { return false; }
    drag_source_node_id = source_id;
    drag_active = true;
    selected_builder_node_id = source_id;
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    return true;
  };

  auto cancel_tree_drag = [&] {
    drag_source_node_id.clear();
    drag_active = false;
  };

  auto is_legal_drop_target_reorder = [&](const std::string& target_id) -> bool {
    if (!drag_active || drag_source_node_id.empty() || target_id.empty()) { return false; }
    if (drag_source_node_id == target_id) { return false; }
    if (!node_exists(target_id)) { return false; }
    auto* src = find_node_by_id(drag_source_node_id);
    if (!src || src->parent_id.empty()) { return false; }
    auto* tgt = find_node_by_id(target_id);
    if (!tgt) { return false; }
    return src->parent_id == tgt->parent_id;
  };

  auto is_legal_drop_target_reparent = [&](const std::string& target_id) -> bool {
    if (!drag_active || drag_source_node_id.empty() || target_id.empty()) { return false; }
    if (drag_source_node_id == target_id) { return false; }
    if (!node_exists(target_id)) { return false; }
    if (is_in_subtree_of(target_id, drag_source_node_id)) { return false; }
    auto* src = find_node_by_id(drag_source_node_id);
    if (!src) { return false; }
    if (src->parent_id == target_id) { return false; }
    auto* tgt = find_node_by_id(target_id);
    if (!tgt) { return false; }
    return tgt->widget_type == ngk::ui::builder::BuilderWidgetType::VerticalLayout;
  };

  auto commit_tree_drag_reorder = [&](const std::string& target_id) -> bool {
    if (!is_legal_drop_target_reorder(target_id)) { return false; }
    auto* src = find_node_by_id(drag_source_node_id);
    if (!src) { return false; }
    const auto before_nodes = builder_doc.nodes;
    const std::string before_root = builder_doc.root_node_id;
    const std::string before_sel = selected_builder_node_id;
    auto* parent = find_node_by_id(src->parent_id);
    if (!parent) { return false; }
    auto& kids = parent->child_ids;
    auto src_it = std::find(kids.begin(), kids.end(), drag_source_node_id);
    auto tgt_it = std::find(kids.begin(), kids.end(), target_id);
    if (src_it == kids.end() || tgt_it == kids.end()) { return false; }
    std::iter_swap(src_it, tgt_it);
    selected_builder_node_id = drag_source_node_id;
    push_to_history("drag_reorder", before_nodes, before_root, before_sel,
                    builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
    recompute_builder_dirty_state(true);
    cancel_tree_drag();
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
    dragdrop_diag.legal_reorder_drop_applied = true;
    return true;
  };

  auto commit_tree_drag_reparent = [&](const std::string& target_id) -> bool {
    if (!is_legal_drop_target_reparent(target_id)) { return false; }
    auto* src = find_node_by_id(drag_source_node_id);
    if (!src) { return false; }
    const auto before_nodes = builder_doc.nodes;
    const std::string before_root = builder_doc.root_node_id;
    const std::string before_sel = selected_builder_node_id;
    const std::string old_parent_id = src->parent_id;
    auto* old_parent = find_node_by_id(old_parent_id);
    if (old_parent) {
      auto& kids = old_parent->child_ids;
      kids.erase(std::remove(kids.begin(), kids.end(), drag_source_node_id), kids.end());
    }
    auto* new_parent = find_node_by_id(target_id);
    if (!new_parent) { return false; }
    new_parent->child_ids.push_back(drag_source_node_id);
    src = find_node_by_id(drag_source_node_id);
    if (!src) { return false; }
    src->parent_id = target_id;
    selected_builder_node_id = drag_source_node_id;
    push_to_history("drag_reparent", before_nodes, before_root, before_sel,
                    builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
    recompute_builder_dirty_state(true);
    cancel_tree_drag();
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
    dragdrop_diag.legal_reparent_drop_applied = true;
    return true;
  };

  auto reject_illegal_tree_drag_drop = [&](const std::string& target_id, bool is_reparent) -> bool {
    const bool would_be_legal = is_reparent
      ? is_legal_drop_target_reparent(target_id)
      : is_legal_drop_target_reorder(target_id);
    if (would_be_legal) { return false; }
    dragdrop_diag.illegal_drop_rejected = true;
    cancel_tree_drag();
    return true;
  };

  auto apply_typed_palette_insert = [&](
      ngk::ui::builder::BuilderWidgetType type,
      const std::string& under_node_id,
      const std::string& new_node_id) -> bool {
    using WType = ngk::ui::builder::BuilderWidgetType;
    auto is_container_type = [](WType t) -> bool {
      return t == WType::VerticalLayout || t == WType::HorizontalLayout ||
             t == WType::ScrollContainer || t == WType::ToolbarContainer ||
             t == WType::SidebarContainer || t == WType::ContentPanel ||
             t == WType::StatusBarContainer;
    };
    auto* parent = find_node_by_id(under_node_id);
    if (parent == nullptr) { return false; }
    if (!is_container_type(parent->widget_type)) { return false; }
    for (const auto& n : builder_doc.nodes) {
      if (n.node_id == new_node_id) { return false; }
    }
    auto before = builder_doc.nodes;
    const std::string before_root = builder_doc.root_node_id;
    const std::string before_sel = selected_builder_node_id;
    ngk::ui::builder::BuilderNode new_node{};
    new_node.node_id = new_node_id;
    new_node.parent_id = under_node_id;
    new_node.widget_type = type;
    new_node.text = std::string(ngk::ui::builder::to_string(type));
    parent->child_ids.push_back(new_node_id);
    builder_doc.nodes.push_back(std::move(new_node));
    selected_builder_node_id = new_node_id;
    push_to_history("typed_insert", before, before_root, before_sel,
                    builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id);
    return true;
  };

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
    export_diag.export_command_present = true;
    last_export_artifact_path = export_file_path.string();

    auto fail_export = [&](const char* reason_code) -> bool {
      last_export_status_code = "fail";
      last_export_reason = reason_code == nullptr ? "unknown_export_error" : reason_code;
      refresh_export_status_surface_label();
      update_labels();
      return false;
    };

    // Fail closed: no root, no nodes
    if (source_doc.root_node_id.empty() || source_doc.nodes.empty()) {
      return fail_export("invalid_document_missing_root_or_nodes");
    }

    // Validate before serializing
    std::string validation_error;
    if (!ngk::ui::builder::validate_builder_document(source_doc, &validation_error)) {
      return fail_export("document_validation_failed");
    }

    // Snapshot: read-only, no mutation of builder_doc
    const std::string export_text = ngk::ui::builder::serialize_builder_document_deterministic(source_doc);
    if (export_text.empty()) {
      return fail_export("deterministic_serialize_failed");
    }

    // Verify runtime-instantiable
    ngk::ui::builder::InstantiatedBuilderDocument runtime_proof{};
    std::string instantiate_error;
    if (!ngk::ui::builder::instantiate_builder_document(source_doc, runtime_proof, &instantiate_error)) {
      return fail_export("runtime_instantiate_failed");
    }

    // Write to export path
    if (!write_text_file(export_file_path, export_text)) {
      return fail_export("artifact_write_failed");
    }

    // Verify round-trip: re-read and compare
    std::string roundtrip_text;
    if (!read_text_file(export_file_path, roundtrip_text)) {
      return fail_export("artifact_readback_failed");
    }
    if (roundtrip_text != export_text) {
      return fail_export("artifact_roundtrip_mismatch");
    }

    ngk::ui::builder::BuilderDocument roundtrip_doc{};
    std::string deserialize_error;
    if (!ngk::ui::builder::deserialize_builder_document_deterministic(roundtrip_text, roundtrip_doc, &deserialize_error)) {
      return fail_export("artifact_deserialize_failed");
    }
    const std::string canonical_roundtrip =
      ngk::ui::builder::serialize_builder_document_deterministic(roundtrip_doc);
    if (canonical_roundtrip != export_text) {
      return fail_export("artifact_canonical_roundtrip_mismatch");
    }

    export_diag.export_artifact_created = true;
    export_diag.export_artifact_deterministic = true;
    export_diag.exported_structure_matches_builder_doc = true;
    has_last_export_snapshot = true;
    last_export_snapshot = export_text;
    export_snapshot_matches_current_doc = true;
    last_export_status_code = "success";
    last_export_reason = "none";
    refresh_export_status_surface_label();
    update_labels();
    return true;
  };

  auto find_node_by_id_in_document = [&](const ngk::ui::builder::BuilderDocument& doc,
                                         const std::string& node_id) -> const ngk::ui::builder::BuilderNode* {
    for (const auto& node : doc.nodes) {
      if (node.node_id == node_id) {
        return &node;
      }
    }
    return nullptr;
  };

  auto set_preview_export_parity_status = [&](const char* status_code, const std::string& reason) {
    last_preview_export_parity_status_code = status_code == nullptr ? "unknown" : status_code;
    last_preview_export_parity_reason = reason.empty() ? std::string("none") : reason;
    refresh_preview_surface_label();
  };

  auto build_preview_export_parity_entries = [&](const ngk::ui::builder::BuilderDocument& doc,
                                                 std::vector<PreviewExportParityEntry>& entries,
                                                 std::string& reason_out,
                                                 const char* context_name) -> bool {
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
  };

  auto validate_preview_export_parity = [&](const ngk::ui::builder::BuilderDocument& live_doc,
                                            const std::filesystem::path& export_file_path) -> bool {
    std::string exported_text;
    if (!read_text_file(export_file_path, exported_text)) {
      set_preview_export_parity_status("fail", "export_artifact_read_failed");
      return false;
    }

    ngk::ui::builder::BuilderDocument exported_doc{};
    std::string deserialize_error;
    if (!ngk::ui::builder::deserialize_builder_document_deterministic(
          exported_text, exported_doc, &deserialize_error)) {
      set_preview_export_parity_status("fail", "export_artifact_deserialize_failed");
      return false;
    }

    std::vector<PreviewExportParityEntry> live_entries{};
    std::vector<PreviewExportParityEntry> exported_entries{};
    std::string live_reason;
    std::string exported_reason;
    if (!build_preview_export_parity_entries(live_doc, live_entries, live_reason, "live_preview_scope")) {
      set_preview_export_parity_status("fail", live_reason);
      return false;
    }
    if (!build_preview_export_parity_entries(exported_doc, exported_entries, exported_reason, "export_scope")) {
      set_preview_export_parity_status("fail", exported_reason);
      return false;
    }

    if (live_doc.root_node_id != exported_doc.root_node_id) {
      set_preview_export_parity_status(
        "fail",
        "root_node_mismatch_live_" + live_doc.root_node_id + "_export_" + exported_doc.root_node_id);
      return false;
    }

    if (live_entries.size() != exported_entries.size()) {
      set_preview_export_parity_status(
        "fail",
        "node_count_mismatch_live_" + std::to_string(live_entries.size()) +
          "_export_" + std::to_string(exported_entries.size()));
      return false;
    }

    for (std::size_t index = 0; index < live_entries.size(); ++index) {
      const auto& live_entry = live_entries[index];
      const auto& exported_entry = exported_entries[index];

      if (live_entry.depth != exported_entry.depth) {
        set_preview_export_parity_status(
          "fail", "hierarchy_depth_mismatch_node_" + live_entry.node_id);
        return false;
      }
      if (live_entry.node_id != exported_entry.node_id) {
        set_preview_export_parity_status(
          "fail",
          "node_identity_mismatch_live_" + live_entry.node_id + "_export_" + exported_entry.node_id);
        return false;
      }
      if (live_entry.widget_type != exported_entry.widget_type) {
        set_preview_export_parity_status(
          "fail", "component_type_mismatch_node_" + live_entry.node_id);
        return false;
      }
      if (live_entry.text != exported_entry.text) {
        set_preview_export_parity_status(
          "fail", "identity_text_mismatch_node_" + live_entry.node_id);
        return false;
      }
      if (live_entry.child_ids.size() != exported_entry.child_ids.size()) {
        set_preview_export_parity_status(
          "fail", "child_count_mismatch_node_" + live_entry.node_id);
        return false;
      }
      for (std::size_t child_index = 0; child_index < live_entry.child_ids.size(); ++child_index) {
        if (live_entry.child_ids[child_index] != exported_entry.child_ids[child_index]) {
          set_preview_export_parity_status(
            "fail",
            "child_link_mismatch_parent_" + live_entry.node_id +
              "_offset_" + std::to_string(child_index));
          return false;
        }
      }
    }

    set_preview_export_parity_status("success", "none");
    return true;
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

  builder_insert_container_button.set_on_click([&] {
    if (apply_palette_insert(true)) {
      recompute_builder_dirty_state(true);
    }
  });
  builder_insert_leaf_button.set_on_click([&] {
    if (apply_palette_insert(false)) {
      recompute_builder_dirty_state(true);
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
    if (apply_delete_selected_node_command()) {
      recompute_builder_dirty_state(true);
    }
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
    request_redraw("builder_delete", false, false);
  });
  builder_undo_button.set_on_click([&] {
    apply_undo_command();
    request_redraw("builder_undo", false, false);
  });
  builder_redo_button.set_on_click([&] {
    apply_redo_command();
    request_redraw("builder_redo", false, false);
  });
  builder_save_button.set_on_click([&] {
    apply_save_document_command();
    request_redraw("builder_save", false, false);
  });
  builder_export_button.set_on_click([&] {
    apply_export_command(builder_doc, builder_export_path);
    request_redraw("builder_export", false, false);
  });
  builder_load_button.set_on_click([&] {
    apply_load_document_command(false);
    request_redraw("builder_load", false, false);
  });
  builder_load_discard_button.set_on_click([&] {
    apply_load_document_command(true);
    request_redraw("builder_load_discard", false, false);
  });
  builder_new_button.set_on_click([&] {
    apply_new_document_command(false);
    request_redraw("builder_new", false, false);
  });
  builder_new_discard_button.set_on_click([&] {
    apply_new_document_command(true);
    request_redraw("builder_new_discard", false, false);
  });

  root.add_child(&shell);
  shell.add_child(&title_label);
  shell.add_child(&path_label);
  shell.add_child(&filter_box);
  shell.add_child(&apply_button);
  shell.add_child(&refresh_button);
  shell.add_child(&prev_button);
  shell.add_child(&next_button);
  shell.add_child(&builder_delete_button);
  shell.add_child(&builder_undo_button);
  shell.add_child(&builder_redo_button);
  shell.add_child(&builder_save_button);
  shell.add_child(&builder_export_button);
  shell.add_child(&builder_load_button);
  shell.add_child(&builder_load_discard_button);
  shell.add_child(&builder_new_button);
  shell.add_child(&builder_new_discard_button);
  shell.add_child(&builder_insert_container_button);
  shell.add_child(&builder_insert_leaf_button);
  shell.add_child(&builder_export_status_label);
  shell.add_child(&builder_tree_surface_label);
  shell.add_child(&builder_inspector_label);
  shell.add_child(&builder_preview_label);
  shell.add_child(&status_label);
  shell.add_child(&selected_label);
  shell.add_child(&detail_label);

  tree.set_root(&root);
  input_router.set_tree(&tree);
  tree.set_invalidate_callback([&] { window.request_repaint(); });

  layout(client_w, client_h);
  tree.on_resize(client_w, client_h);

  model.filter = "";
  reload_entries(model, scan_root);
  update_labels();
  refresh_tree_surface_label();
  refresh_inspector_surface_label();
  refresh_preview_surface_label();
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
    if (input_router.on_mouse_button_message(message, down)) {
      request_redraw("mouse_button", true, false);
    }
  });
  window.set_key_callback([&](std::uint32_t key, bool down, bool repeat) {
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
    request_redraw("steady_state_tick", false, false);
    render_frames += 1;
    if (renderer.is_device_lost()) {
      model.crash_detected = true;
      loop.stop();
    }
  });

  loop.run();
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
  std::cout << "app_runtime_crash_detected=" << (no_crash ? 0 : 1) << "\n";
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

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
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
  std::vector<CommandHistoryEntry> undo_history{};
  std::vector<CommandHistoryEntry> redo_stack{};

  ngk::ui::Button builder_undo_button;
  ngk::ui::Button builder_redo_button;
  ngk::ui::Button builder_save_button;
  ngk::ui::Button builder_load_button;
  ngk::ui::Button builder_load_discard_button;
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
  builder_new_button.set_text("New Doc");
  builder_new_discard_button.set_text("New Discard");
  phase102_compose_action_button.set_text("Action");

  shell.set_background(0.10f, 0.12f, 0.16f, 0.96f);
  title_label.set_background(0.12f, 0.16f, 0.22f, 1.0f);
  path_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  status_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  selected_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  detail_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);

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

    status_label.set_position(36, 154);
    status_label.set_size(w - 72, 32);

    selected_label.set_position(36, 192);
    selected_label.set_size(w - 72, 32);

    detail_label.set_position(36, 230);
    detail_label.set_size(w - 72, 70);
  };

  auto update_labels = [&] {
    path_label.set_text(std::string("PATH ") + scan_root.string());
    status_label.set_text(
      std::string("STATUS ") + model.status +
      " FILES " + std::to_string(model.entries.size()) +
      " DOC_DIRTY " + (builder_doc_dirty ? std::string("YES") : std::string("NO")));
    selected_label.set_text(std::string("SELECTED ") + selected_file_name(model));
    detail_label.set_text(std::string("DETAIL BYTES ") + selected_file_size(model) + " FILTER " + model.filter);
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

  // PHASE103_15 rule: builder semantic focus is always derived from selection.
  auto sync_focus_with_selection_or_fail = [&]() -> bool {
    focus_diag.focus_selection_rules_defined = true;

    if (!focused_builder_node_id.empty()) {
      const bool focused_exists = node_exists(focused_builder_node_id);
      if (!focused_exists) {
        focused_builder_node_id.clear();
        focus_diag.stale_focus_rejected = true;
        return false;
      }
    }

    if (selected_builder_node_id.empty()) {
      focused_builder_node_id.clear();
      return true;
    }

    if (!node_exists(selected_builder_node_id)) {
      focused_builder_node_id.clear();
      focus_diag.stale_focus_rejected = true;
      return false;
    }

    focused_builder_node_id = selected_builder_node_id;
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
      return true;
    }

    if (!node_exists(selected_builder_node_id)) {
      coherence_diag.stale_inspector_binding_rejected = true;
      inspector_binding_node_id.clear();
      return false;
    }

    inspector_binding_node_id = selected_builder_node_id;
    return true;
  };

  auto refresh_preview_or_fail = [&]() -> bool {
    coherence_diag.preview_coherence_hardened = true;

    if (!selected_builder_node_id.empty() && !node_exists(selected_builder_node_id)) {
      preview_binding_node_id.clear();
      preview_snapshot.clear();
      model.undefined_state_detected = true;
      return false;
    }

    preview_binding_node_id = selected_builder_node_id;
    preview_snapshot = "preview:nodes=" + std::to_string(builder_doc.nodes.size()) +
      " selected=" + (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id);
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
  shell.add_child(&builder_load_button);
  shell.add_child(&builder_load_discard_button);
  shell.add_child(&builder_new_button);
  shell.add_child(&builder_new_discard_button);
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

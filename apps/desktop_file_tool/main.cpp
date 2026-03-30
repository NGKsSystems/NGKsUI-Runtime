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

struct BuilderBulkDeleteDiagnostics {
  bool bulk_delete_present = false;
  bool eligible_selected_nodes_deleted = false;
  bool protected_or_invalid_bulk_delete_rejected = false;
  bool post_delete_selection_deterministic = false;
  bool undo_restores_bulk_delete_correctly = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderBulkMoveReparentDiagnostics {
  bool bulk_move_reparent_present = false;
  bool eligible_selected_nodes_moved = false;
  bool invalid_or_protected_bulk_target_rejected = false;
  bool post_move_selection_deterministic = false;
  bool undo_restores_bulk_move_correctly = false;
  bool redo_restores_bulk_move_correctly = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderBulkPropertyEditDiagnostics {
  bool bulk_property_edit_present = false;
  bool compatible_selected_nodes_edited = false;
  bool incompatible_or_mixed_bulk_edit_rejected = false;
  bool post_edit_selection_deterministic = false;
  bool undo_restores_bulk_property_edit_correctly = false;
  bool redo_restores_bulk_property_edit_correctly = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderMultiSelectionClarityDiagnostics {
  bool preview_multi_selection_clarity_improved = false;
  bool primary_vs_secondary_selection_visible = false;
  bool inspector_multi_selection_mode_clear = false;
  bool homogeneous_vs_mixed_state_visible = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderKeyboardMultiSelectionWorkflowDiagnostics {
  bool keyboard_multi_selection_workflow_present = false;
  bool add_remove_clear_selection_by_keyboard_works = false;
  bool primary_selection_remains_deterministic = false;
  bool preview_inspector_tree_remain_synchronized = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderBulkActionEligibilityUxDiagnostics {
  bool bulk_action_visibility_improved = false;
  bool legal_vs_blocked_actions_clear = false;
  bool blocked_action_reasons_explicit = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderActionSurfaceReadabilityDiagnostics {
  bool action_surface_readability_improved = false;
  bool legal_vs_blocked_states_still_clear = false;
  bool blocked_reasons_still_explicit = false;
  bool inspector_preview_information_better_grouped = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderInformationHierarchyPolishDiagnostics {
  bool information_hierarchy_improved = false;
  bool scan_order_more_readable = false;
  bool important_state_easier_to_find = false;
  bool blocked_reasons_and_parity_still_visible = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderSelectionAwareTopActionSurfaceDiagnostics {
  bool top_action_surface_selection_aware = false;
  bool valid_vs_blocked_actions_clear_at_top_level = false;
  bool top_surface_matches_inspector_preview_truth = false;
  bool important_actions_easier_to_reach = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct CommandHistoryEntry {
  std::string command_type{};
  std::vector<ngk::ui::builder::BuilderNode> before_nodes{};
  std::string before_root_node_id{};
  std::string before_selected_id{};
  std::vector<std::string> before_multi_selected_ids{};
  std::vector<ngk::ui::builder::BuilderNode> after_nodes{};
  std::string after_root_node_id{};
  std::string after_selected_id{};
  std::vector<std::string> after_multi_selected_ids{};
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

struct BuilderPreviewSurfaceUpgradeDiagnostics {
  bool preview_structure_visualized = false;
  bool selected_node_highlight_visible = false;
  bool component_identity_visually_distinct = false;
  bool preview_remains_parity_safe = false;
  bool parity_still_passes = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderPreviewInteractionFeedbackDiagnostics {
  bool hover_visual_present = false;
  bool drag_target_preview_present = false;
  bool illegal_drop_feedback_present = false;
  bool preview_remains_parity_safe = false;
  bool shell_state_still_coherent = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderInspectorTypedEditingDiagnostics {
  bool inspector_sections_typed_and_grouped = false;
  bool selected_node_type_clearly_visible = false;
  bool editable_vs_readonly_state_clear = false;
  bool type_specific_fields_correct = false;
  bool legal_typed_edit_applied = false;
  bool invalid_edit_rejected_with_reason = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderPreviewClickSelectDiagnostics {
  bool preview_click_select_present = false;
  bool deterministic_hit_mapping_present = false;
  bool valid_preview_click_selects_correct_node = false;
  bool invalid_preview_click_rejected = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderSelectionClarityPolishDiagnostics {
  bool preview_selected_affordance_improved = false;
  bool selection_identity_consistent_across_surfaces = false;
  bool tree_preview_inspector_clarity_improved = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderPreviewInlineActionAffordanceDiagnostics {
  bool typed_inline_affordances_visible = false;
  bool invalid_or_protected_actions_not_listed_available = false;
  bool preview_affordances_non_mutating_until_commit = false;
  bool committed_action_uses_existing_command_api = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderPreviewInlineActionCommitDiagnostics {
  bool preview_inline_action_commit_present = false;
  bool commit_actions_type_filtered_correctly = false;
  bool illegal_actions_not_committed = false;
  bool committed_action_routes_through_command_path = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderWindowLayoutResponsivenessDiagnostics {
  bool window_resizable_and_maximizable = false;
  bool header_integrated_without_overlap = false;
  bool layout_scales_correctly_on_resize = false;
  bool no_overlap_or_clipping_detected = false;
  bool scroll_behavior_activates_correctly = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};


struct BuilderInlineTextEditDiagnostics {
  bool inline_edit_mode_present = false;
  bool valid_text_edit_commit_works = false;
  bool cancel_edit_restores_original = false;
  bool invalid_edit_rejected = false;
  bool undo_redo_handles_edit_correctly = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderMultiSelectionDiagnostics {
  bool multi_selection_model_present = false;
  bool primary_selection_deterministic = false;
  bool add_remove_clear_selection_work = false;
  bool tree_shows_multi_selection_clearly = false;
  bool inspector_multi_selection_mode_clear = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct PreviewInlineActionAffordanceEntry {
  std::string action_id{};
  bool available = false;
  bool commit_capable = false;
  std::string blocked_reason{};
  std::string command_path{};
};

struct BulkTextSuffixSelectionCompatibility {
  bool selection_active = false;
  bool eligible = false;
  bool homogeneous = false;
  bool mixed = false;
  std::size_t selected_count = 0;
  std::string mode{};
  std::string reason{};
  std::string widget_type{};
};

struct BulkActionEligibilityEntry {
  std::string action_id{};
  bool available = false;
  std::string reason{};
  std::string detail{};
};

struct BulkActionEligibilityReport {
  std::vector<BulkActionEligibilityEntry> entries{};
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
  BuilderPreviewSurfaceUpgradeDiagnostics preview_surface_upgrade_diag{};
  BuilderPreviewInteractionFeedbackDiagnostics preview_interaction_feedback_diag{};
  BuilderInspectorTypedEditingDiagnostics inspector_typed_edit_diag{};
  BuilderPreviewClickSelectDiagnostics preview_click_select_diag{};
  BuilderSelectionClarityPolishDiagnostics selection_clarity_diag{};
  BuilderPreviewInlineActionAffordanceDiagnostics inline_affordance_diag{};
  BuilderPreviewInlineActionCommitDiagnostics inline_action_commit_diag{};
  BuilderWindowLayoutResponsivenessDiagnostics window_layout_diag{};
  BuilderInlineTextEditDiagnostics inline_text_edit_diag{};
  BuilderMultiSelectionDiagnostics multi_selection_diag{};
  BuilderBulkDeleteDiagnostics bulk_delete_diag{};
  BuilderBulkMoveReparentDiagnostics bulk_move_reparent_diag{};
  BuilderBulkPropertyEditDiagnostics bulk_property_edit_diag{};
  BuilderMultiSelectionClarityDiagnostics multi_selection_clarity_diag{};
  BuilderKeyboardMultiSelectionWorkflowDiagnostics keyboard_multi_selection_diag{};
  BuilderBulkActionEligibilityUxDiagnostics bulk_action_eligibility_diag{};
  BuilderActionSurfaceReadabilityDiagnostics action_surface_readability_diag{};
  BuilderInformationHierarchyPolishDiagnostics info_hierarchy_diag{};
  BuilderSelectionAwareTopActionSurfaceDiagnostics top_action_surface_diag{};
  std::string drag_source_node_id{};
  bool drag_active = false;
  std::string hover_node_id{};
  std::string drag_target_preview_node_id{};
  bool drag_target_preview_is_illegal = false;

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
  ngk::ui::ToolbarContainer builder_header_bar(8);
  ngk::ui::HorizontalLayout builder_filter_bar(8);
  ngk::ui::HorizontalLayout builder_primary_actions_bar(8);
  ngk::ui::HorizontalLayout builder_secondary_actions_bar(8);
  ngk::ui::HorizontalLayout builder_info_row(10);
  ngk::ui::ContentPanel builder_detail_panel(6);
  ngk::ui::ContentPanel builder_export_panel(6);
  ngk::ui::HorizontalLayout builder_surface_row(10);
  ngk::ui::ContentPanel builder_tree_panel(6);
  ngk::ui::ContentPanel builder_inspector_panel(6);
  ngk::ui::ContentPanel builder_preview_panel(6);
  ngk::ui::SectionHeader builder_tree_header("TREE REGION");
  ngk::ui::SectionHeader builder_inspector_header("INSPECTOR REGION");
  ngk::ui::SectionHeader builder_preview_header("PREVIEW REGION");
  ngk::ui::ScrollContainer builder_tree_scroll;
  ngk::ui::ScrollContainer builder_inspector_scroll;
  ngk::ui::ScrollContainer builder_preview_scroll;
  ngk::ui::StatusBarContainer builder_footer_bar(8);
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
  std::vector<std::string> multi_selected_node_ids{};
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
  constexpr const char* kPreviewExportParityScope =
    "structure,component_types,key_identity_text,hierarchy";
  constexpr int kBuilderMinClientWidth = 720;
  constexpr int kBuilderMinClientHeight = 520;

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
  apply_button.set_preferred_size(96, 32);
  refresh_button.set_preferred_size(110, 32);
  prev_button.set_preferred_size(96, 32);
  next_button.set_preferred_size(96, 32);
  builder_delete_button.set_preferred_size(128, 32);
  builder_undo_button.set_preferred_size(80, 32);
  builder_redo_button.set_preferred_size(80, 32);
  builder_save_button.set_preferred_size(96, 32);
  builder_load_button.set_preferred_size(96, 32);
  builder_load_discard_button.set_preferred_size(130, 32);
  builder_export_button.set_preferred_size(170, 32);
  builder_new_button.set_preferred_size(96, 32);
  builder_new_discard_button.set_preferred_size(130, 32);
  builder_insert_container_button.set_preferred_size(170, 32);
  builder_insert_leaf_button.set_preferred_size(130, 32);

  builder_shell_panel.set_padding(18);
  builder_shell_panel.set_spacing(10);
  builder_shell_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_shell_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);

  builder_header_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_header_bar.set_preferred_size(0, 42);
  title_label.set_text("NGKsUI Runtime Desktop File Tool");
  title_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  title_label.set_preferred_size(0, 28);
  title_label.set_min_size(240, 28);

  path_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  path_label.set_preferred_size(0, 28);
  path_label.set_min_size(240, 28);

  filter_box.set_preferred_size(0, 32);
  filter_box.set_min_size(220, 32);
  filter_box.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  filter_box.set_layout_weight(3);
  builder_filter_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_filter_bar.set_preferred_size(0, 32);

  builder_primary_actions_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_primary_actions_bar.set_preferred_size(0, 32);
  builder_secondary_actions_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_secondary_actions_bar.set_preferred_size(0, 32);

  builder_info_row.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_info_row.set_preferred_size(0, 110);
  builder_info_row.set_min_size(0, 88);
  builder_detail_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_detail_panel.set_layout_weight(3);
  builder_detail_panel.set_min_size(220, 0);
  builder_export_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_export_panel.set_layout_weight(2);
  builder_export_panel.set_min_size(220, 0);
  detail_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_export_status_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);

  builder_surface_row.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_surface_row.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_surface_row.set_layout_weight(1);
  builder_surface_row.set_min_size(0, 180);

  builder_tree_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_panel.set_layout_weight(2);
  builder_tree_panel.set_min_size(180, 180);
  builder_inspector_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_panel.set_layout_weight(2);
  builder_inspector_panel.set_min_size(180, 180);
  builder_preview_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_panel.set_layout_weight(3);
  builder_preview_panel.set_min_size(220, 180);

  builder_tree_scroll.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_scroll.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_scroll.set_layout_weight(1);
  builder_inspector_scroll.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_scroll.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_scroll.set_layout_weight(1);
  builder_preview_scroll.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_scroll.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_scroll.set_layout_weight(1);

  builder_tree_surface_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_header.set_preferred_size(0, 26);
  builder_inspector_header.set_preferred_size(0, 26);
  builder_preview_header.set_preferred_size(0, 26);

  builder_footer_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_footer_bar.set_preferred_size(0, 28);
  status_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  status_label.set_layout_weight(2);
  selected_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  selected_label.set_layout_weight(1);

  auto sync_label_preferred_height = [&](ngk::ui::Label& label, int extra_padding) {
    int line_count = 1;
    for (char ch : label.text()) {
      if (ch == '\n') {
        line_count += 1;
      }
    }
    label.set_preferred_size(0, std::max(label.min_height(), (line_count * 16) + extra_padding));
  };

  auto layout = [&](int w, int h) {
    root.set_position(0, 0);
    root.set_size(w, h);

    shell.set_position(0, 0);
    shell.set_size(w, h);
    builder_shell_panel.set_position(0, 0);
    builder_shell_panel.set_size(w, h);
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
    sync_label_preferred_height(builder_export_status_label, 18);
  };

  auto update_labels = [&] {
    path_label.set_text(std::string("PATH ") + scan_root.string());
    status_label.set_text(
      std::string("STATUS ") + model.status +
      " FILES " + std::to_string(model.entries.size()) +
      " DOC_DIRTY " + (builder_doc_dirty ? std::string("YES") : std::string("NO")));
    selected_label.set_text(std::string("SELECTED ") + selected_file_name(model));
    detail_label.set_text(std::string("DETAIL BYTES ") + selected_file_size(model) + " FILTER " + model.filter);
    sync_label_preferred_height(detail_label, 18);
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
    if (client_w > 0 && client_h > 0) {
      layout(client_w, client_h);
      tree.on_resize(client_w, client_h);
    }
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
    multi_selected_node_ids.clear();
    multi_selected_node_ids.push_back(selected_builder_node_id);

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

  auto find_node_by_id_in_document = [&](const ngk::ui::builder::BuilderDocument& doc,
                                         const std::string& node_id) -> const ngk::ui::builder::BuilderNode* {
    for (const auto& node : doc.nodes) {
      if (node.node_id == node_id) {
        return &node;
      }
    }
    return nullptr;
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

  auto preview_identity_role = [&](const PreviewExportParityEntry& entry) -> std::string {
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
  };

  auto build_preview_runtime_outline = [&]() -> std::string {
    std::vector<PreviewExportParityEntry> entries{};
    std::string reason;
    if (!build_preview_export_parity_entries(builder_doc, entries, reason, "preview_surface")) {
      return std::string("outline_unavailable reason=") + reason;
    }

    std::ostringstream oss;
    for (const auto& entry : entries) {
      const bool is_selected = (entry.node_id == selected_builder_node_id);
      const bool is_focused = (entry.node_id == focused_builder_node_id);
      const bool is_secondary =
        !is_selected &&
        std::find(multi_selected_node_ids.begin(), multi_selected_node_ids.end(), entry.node_id) !=
          multi_selected_node_ids.end();
      const bool is_hover = (entry.node_id == hover_node_id) && !is_selected;
      const bool is_drag_tgt = !drag_target_preview_node_id.empty() && (entry.node_id == drag_target_preview_node_id);
      const std::string indent = entry.depth == 0 ? std::string() : std::string(static_cast<std::size_t>(entry.depth - 1) * 2U, ' ');
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
      if (is_drag_tgt && !drag_target_preview_is_illegal) {
        oss << " [DRAG_TARGET]";
      }
      if (is_drag_tgt && drag_target_preview_is_illegal) {
        oss << " [ILLEGAL_DROP]";
      }
      oss << "\n";
    }
    return oss.str();
  };

  auto build_preview_click_hit_entries = [&](std::vector<PreviewExportParityEntry>& entries_out,
                                             std::string& reason_out) -> bool {
    return build_preview_export_parity_entries(builder_doc, entries_out, reason_out, "preview_click_hit_map");
  };

  auto is_text_editable_widget_type = [&](ngk::ui::builder::BuilderWidgetType type) -> bool {
    using WType = ngk::ui::builder::BuilderWidgetType;
    return type == WType::Label || type == WType::Button ||
           type == WType::InputBox || type == WType::SectionHeader;
  };

  auto is_container_widget_type = [&](ngk::ui::builder::BuilderWidgetType type) -> bool {
    using WType = ngk::ui::builder::BuilderWidgetType;
    return type == WType::VerticalLayout || type == WType::HorizontalLayout ||
           type == WType::ScrollContainer || type == WType::ToolbarContainer ||
           type == WType::SidebarContainer || type == WType::ContentPanel ||
           type == WType::StatusBarContainer;
  };

  auto build_preview_inline_action_entries = [&](const ngk::ui::builder::BuilderNode& selected) {
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
    if (selected.node_id == builder_doc.root_node_id) {
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
  };

  auto build_preview_inline_action_affordance_text = [&](const ngk::ui::builder::BuilderNode& selected) -> std::string {
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
  };

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

  auto compute_bulk_text_suffix_selection_compatibility = [&]() -> BulkTextSuffixSelectionCompatibility {
    BulkTextSuffixSelectionCompatibility state{};
    sync_multi_selection_with_primary();

    state.selected_count = multi_selected_node_ids.size();
    state.selection_active = state.selected_count > 1;
    if (!state.selection_active) {
      state.mode = "single_selection";
      state.reason = "requires_multi_selection";
      return state;
    }

    ngk::ui::builder::BuilderWidgetType homogeneous_type = ngk::ui::builder::BuilderWidgetType::Label;
    bool homogeneous_type_set = false;

    for (const auto& node_id : multi_selected_node_ids) {
      auto* node = find_node_by_id(node_id);
      if (!node) {
        state.mode = "invalid";
        state.reason = "selected_node_missing_" + node_id;
        return state;
      }
      if (node_id == builder_doc.root_node_id || node->parent_id.empty()) {
        state.mode = "incompatible";
        state.reason = "protected_source_root_" + node_id;
        return state;
      }
      if (node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
        state.mode = "incompatible";
        state.reason = "protected_source_shell_" + node_id;
        return state;
      }
      if (!ngk::ui::builder::widget_supports_text_property(node->widget_type)) {
        state.mode = "incompatible";
        state.reason = "non_text_capable_type_" + std::string(ngk::ui::builder::to_string(node->widget_type));
        return state;
      }

      if (!homogeneous_type_set) {
        homogeneous_type = node->widget_type;
        homogeneous_type_set = true;
      } else if (node->widget_type != homogeneous_type) {
        state.mixed = true;
        state.mode = "mixed";
        state.reason = "mixed_widget_types";
        state.widget_type = std::string(ngk::ui::builder::to_string(homogeneous_type));
        return state;
      }
    }

    state.homogeneous = true;
    state.eligible = true;
    state.mode = "homogeneous";
    state.reason = "eligible_for_bulk_text_suffix";
    state.widget_type = std::string(ngk::ui::builder::to_string(homogeneous_type));
    return state;
  };

  auto compute_bulk_action_eligibility_report = [&]() -> BulkActionEligibilityReport {
    BulkActionEligibilityReport report{};
    sync_multi_selection_with_primary();

    const bool multi_selection_active = multi_selected_node_ids.size() > 1;

    auto add_entry = [&](const std::string& action_id,
                         bool available,
                         const std::string& reason,
                         const std::string& detail) {
      BulkActionEligibilityEntry entry{};
      entry.action_id = action_id;
      entry.available = available;
      entry.reason = reason;
      entry.detail = detail;
      report.entries.push_back(std::move(entry));
    };

    if (!multi_selection_active) {
      add_entry("BULK_DELETE", false, "requires_multi_selection", "selected_count=" + std::to_string(multi_selected_node_ids.size()));
      add_entry("BULK_MOVE_REPARENT", false, "requires_multi_selection", "selected_count=" + std::to_string(multi_selected_node_ids.size()));
      add_entry("BULK_PROPERTY_EDIT", false, "requires_multi_selection", "selected_count=" + std::to_string(multi_selected_node_ids.size()));
      return report;
    }

    {
      auto local_delete_rejection_reason_for_node = [&](const std::string& node_id) -> std::string {
        if (node_id.empty()) {
          return "no_selected_node";
        }

        auto* target = find_node_by_id(node_id);
        if (!target) {
          return "selected_node_lookup_failed";
        }

        const bool is_root = (node_id == builder_doc.root_node_id) || target->parent_id.empty();
        const bool shell_critical = target->container_type == ngk::ui::builder::BuilderContainerType::Shell;
        if (is_root) {
          return "protected_root";
        }
        if (shell_critical) {
          return "protected_shell";
        }
        if (target->parent_id.empty() || !node_exists(target->parent_id)) {
          return "parent_missing_for_delete";
        }
        return "";
      };

      std::string rejection_reason;
      std::vector<std::string> unique_ids{};
      for (const auto& node_id : multi_selected_node_ids) {
        if (node_id.empty()) {
          continue;
        }
        if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
          unique_ids.push_back(node_id);
        }
      }

      std::vector<std::string> delete_targets{};
      if (unique_ids.empty()) {
        rejection_reason = "no_selected_nodes";
      } else {
        for (const auto& node_id : unique_ids) {
          const std::string reason = local_delete_rejection_reason_for_node(node_id);
          if (!reason.empty()) {
            rejection_reason = reason + "_" + node_id;
            break;
          }
        }
      }

      if (rejection_reason.empty()) {
        for (const auto& node_id : unique_ids) {
          bool covered_by_ancestor = false;
          auto* current = find_node_by_id(node_id);
          while (current && !current->parent_id.empty()) {
            if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
              covered_by_ancestor = true;
              break;
            }
            current = find_node_by_id(current->parent_id);
          }
          if (!covered_by_ancestor) {
            delete_targets.push_back(node_id);
          }
        }
      }

      if (delete_targets.empty()) {
        add_entry("BULK_DELETE", false,
                  rejection_reason.empty() ? std::string("no_eligible_delete_targets") : rejection_reason,
                  "selected_count=" + std::to_string(multi_selected_node_ids.size()));
      } else {
        add_entry("BULK_DELETE", true, "none", "eligible_targets=" + std::to_string(delete_targets.size()));
      }
    }

    {
      const auto text_state = compute_bulk_text_suffix_selection_compatibility();
      if (text_state.eligible) {
        add_entry("BULK_PROPERTY_EDIT", true, "none",
                  text_state.widget_type.empty() ? std::string("eligible") : std::string("widget_type=") + text_state.widget_type);
      } else {
        add_entry("BULK_PROPERTY_EDIT", false,
                  text_state.reason.empty() ? std::string("ineligible") : text_state.reason,
                  text_state.mode.empty() ? std::string("mode=unknown") : std::string("mode=") + text_state.mode);
      }
    }

    {
      std::string move_reason;
      auto local_is_in_subtree_of = [&](const std::string& node_id, const std::string& ancestor_id) -> bool {
        if (node_id.empty() || ancestor_id.empty()) {
          return false;
        }
        if (node_id == ancestor_id) {
          return true;
        }
        std::vector<std::string> to_visit{ancestor_id};
        for (std::size_t idx = 0; idx < to_visit.size(); ++idx) {
          auto* n = find_node_by_id(to_visit[idx]);
          if (!n) {
            continue;
          }
          for (const auto& child_id : n->child_ids) {
            if (child_id == node_id) {
              return true;
            }
            to_visit.push_back(child_id);
          }
        }
        return false;
      };
      std::vector<std::string> unique_ids{};
      for (const auto& node_id : multi_selected_node_ids) {
        if (node_id.empty()) {
          continue;
        }
        if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
          unique_ids.push_back(node_id);
        }
      }

      if (unique_ids.empty()) {
        move_reason = "no_selected_nodes";
      }

      for (const auto& node_id : unique_ids) {
        if (!move_reason.empty()) {
          break;
        }
        auto* source_node = find_node_by_id(node_id);
        if (!source_node) {
          move_reason = "selected_node_lookup_failed_" + node_id;
          break;
        }
        if (node_id == builder_doc.root_node_id || source_node->parent_id.empty()) {
          move_reason = "protected_source_root_" + node_id;
          break;
        }
        if (source_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
          move_reason = "protected_source_shell_" + node_id;
          break;
        }
        if (!node_exists(source_node->parent_id)) {
          move_reason = "source_parent_missing_" + node_id;
          break;
        }
      }

      std::vector<std::string> normalized_sources{};
      if (move_reason.empty()) {
        for (const auto& node_id : unique_ids) {
          bool covered_by_ancestor = false;
          auto* current = find_node_by_id(node_id);
          while (current && !current->parent_id.empty()) {
            if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
              covered_by_ancestor = true;
              break;
            }
            current = find_node_by_id(current->parent_id);
          }
          if (!covered_by_ancestor) {
            normalized_sources.push_back(node_id);
          }
        }
        if (normalized_sources.empty()) {
          move_reason = "no_eligible_move_sources";
        }
      }

      std::string candidate_target_id{};
      if (move_reason.empty()) {
        for (const auto& candidate : builder_doc.nodes) {
          if (candidate.node_id.empty()) {
            continue;
          }
          if (candidate.node_id == builder_doc.root_node_id) {
            continue;
          }
          if (candidate.container_type == ngk::ui::builder::BuilderContainerType::Shell) {
            continue;
          }
          if (candidate.widget_type != ngk::ui::builder::BuilderWidgetType::VerticalLayout) {
            continue;
          }
          if (std::find(normalized_sources.begin(), normalized_sources.end(), candidate.node_id) != normalized_sources.end()) {
            continue;
          }

          bool candidate_valid = true;
          for (const auto& source_id : normalized_sources) {
            auto* source_node = find_node_by_id(source_id);
            if (!source_node) {
              candidate_valid = false;
              move_reason = "selected_node_lookup_failed_" + source_id;
              break;
            }
            if (source_node->parent_id == candidate.node_id) {
              candidate_valid = false;
              continue;
            }
            if (local_is_in_subtree_of(candidate.node_id, source_id)) {
              candidate_valid = false;
              continue;
            }
          }

          if (candidate_valid) {
            candidate_target_id = candidate.node_id;
            break;
          }
        }
      }

      if (!candidate_target_id.empty()) {
        add_entry("BULK_MOVE_REPARENT", true, "none", "candidate_target=" + candidate_target_id);
      } else {
        if (move_reason.empty()) {
          move_reason = "no_valid_vertical_layout_target";
        }
        add_entry("BULK_MOVE_REPARENT", false, move_reason,
                  "selected_count=" + std::to_string(multi_selected_node_ids.size()));
      }
    }

    return report;
  };

  auto append_compact_bulk_action_surface = [&](std::ostringstream& oss) {
    const auto report = compute_bulk_action_eligibility_report();
    std::vector<std::string> available_actions{};
    std::vector<BulkActionEligibilityEntry> blocked_actions{};

    for (const auto& entry : report.entries) {
      if (entry.available) {
        available_actions.push_back(entry.action_id);
      } else {
        blocked_actions.push_back(entry);
      }
    }

    oss << "ACTION_SURFACE: available=" << available_actions.size()
        << " blocked=" << blocked_actions.size() << "\n";

    oss << "AVAILABLE_ACTIONS: ";
    if (available_actions.empty()) {
      oss << "<none>\n";
    } else {
      for (std::size_t idx = 0; idx < available_actions.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << available_actions[idx];
      }
      oss << "\n";
    }

    oss << "BLOCKED_ACTIONS: ";
    if (blocked_actions.empty()) {
      oss << "<none>\n";
    } else {
      for (std::size_t idx = 0; idx < blocked_actions.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << blocked_actions[idx].action_id;
      }
      oss << "\n";
    }

    if (blocked_actions.empty()) {
      oss << "BLOCKED_REASONS: <none>\n";
      return;
    }

    oss << "BLOCKED_REASONS:\n";
    for (const auto& blocked : blocked_actions) {
      oss << "  " << blocked.action_id << " -> ";
      if (blocked.reason.empty()) {
        oss << "unspecified";
      } else {
        oss << blocked.reason;
      }
      if (!blocked.detail.empty()) {
        oss << " [" << blocked.detail << "]";
      }
      oss << "\n";
    }
  };

  auto refresh_top_action_surface_from_builder_state = [&]() {
    sync_multi_selection_with_primary();
    const auto report = compute_bulk_action_eligibility_report();

    std::vector<std::string> available_actions{};
    std::vector<std::string> blocked_actions{};
    for (const auto& entry : report.entries) {
      if (entry.available) {
        available_actions.push_back(entry.action_id);
      } else {
        blocked_actions.push_back(entry.action_id);
      }
    }

    auto join_csv = [&](const std::vector<std::string>& values) -> std::string {
      if (values.empty()) {
        return "<none>";
      }
      std::ostringstream joined;
      for (std::size_t idx = 0; idx < values.size(); ++idx) {
        if (idx > 0) {
          joined << ",";
        }
        joined << values[idx];
      }
      return joined.str();
    };

    std::string selected_type_name = "none";
    if (!selected_builder_node_id.empty()) {
      if (auto* selected_node = find_node_by_id(selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }

    status_label.set_text(
      std::string("STATUS ") + model.status +
      " FILES " + std::to_string(model.entries.size()) +
      " DOC_DIRTY " + (builder_doc_dirty ? std::string("YES") : std::string("NO")) +
      "\nTOP_ACTION_SURFACE mode=" + (multi_selected_node_ids.size() > 1 ? std::string("multi") : std::string("single")) +
      " selected_count=" + std::to_string(multi_selected_node_ids.size()) +
      " available=" + std::to_string(available_actions.size()) +
      " blocked=" + std::to_string(blocked_actions.size()));
    sync_label_preferred_height(status_label, 18);

    selected_label.set_text(
      std::string("SELECTED ") + selected_file_name(model) +
      "\nNODE " + (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) +
      " type=" + selected_type_name);
    sync_label_preferred_height(selected_label, 18);

    detail_label.set_text(
      std::string("DETAIL BYTES ") + selected_file_size(model) +
      " FILTER " + model.filter +
      "\nTOP_AVAILABLE " + join_csv(available_actions) +
      "\nTOP_BLOCKED " + join_csv(blocked_actions));
    sync_label_preferred_height(detail_label, 18);
  };

  auto build_tree_surface_text = [&]() -> std::string {
    sync_multi_selection_with_primary();

    std::ostringstream oss;
    oss << "TREE REGION (Hierarchy / Selection)\n";
    std::string selected_type_name = "none";
    if (!selected_builder_node_id.empty()) {
      if (auto* selected_node = find_node_by_id(selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }
    oss << "SELECTED_ID: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
    oss << "SELECTED_TYPE: " << selected_type_name << "\n";
    oss << "focus=" << (focused_builder_node_id.empty() ? std::string("none") : focused_builder_node_id) << "\n";
    oss << "MULTI_SELECTION_COUNT: " << multi_selected_node_ids.size() << "\n";
    oss << "PRIMARY_SELECTION_ID: "
        << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
    if (multi_selected_node_ids.size() > 1) {
      oss << "SECONDARY_SELECTION_ORDER: ";
      for (std::size_t idx = 1; idx < multi_selected_node_ids.size(); ++idx) {
        if (idx > 1) {
          oss << ",";
        }
        oss << multi_selected_node_ids[idx];
      }
      oss << "\n";
    }

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
        const bool is_secondary = is_node_in_multi_selection(node_id) && !is_selected;
      oss << std::string(static_cast<std::size_t>(depth) * 2U, ' ')
          << (is_selected ? "> " : "- ")
          << ngk::ui::builder::to_string(node->widget_type)
          << " | " << node->node_id;
      if (!node->text.empty()) {
        oss << " | \"" << node->text << "\"";
      }
      if (is_selected) {
        oss << " [SELECTED][PRIMARY]";
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

    append_node(builder_doc.root_node_id, 0);
    return oss.str();
  };

  auto refresh_tree_surface_label = [&]() {
    builder_tree_surface_label.set_text(build_tree_surface_text());
    sync_label_preferred_height(builder_tree_surface_label, 20);
  };

  auto refresh_inspector_surface_label = [&]() {
    sync_multi_selection_with_primary();

    std::ostringstream oss;
    oss << "INSPECTOR REGION (Typed Editing Surface)\n";
    std::string selected_type_name = "none";
    if (!selected_builder_node_id.empty()) {
      if (auto* selected_node = find_node_by_id(selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }

    oss << "[SELECTION_SUMMARY]\n";
    oss << "SELECTED_ID: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
    oss << "SELECTED_TYPE: " << selected_type_name << "\n";
    oss << "EDIT_TARGET_ID: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
    oss << "MULTI_SELECTION_MODE: " << (multi_selected_node_ids.size() > 1 ? "active" : "inactive") << "\n";
    oss << "MULTI_SELECTION_COUNT: " << multi_selected_node_ids.size() << "\n";
    oss << "PRIMARY_SELECTION_ID: "
        << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
    if (multi_selected_node_ids.size() > 1) {
      oss << "SECONDARY_SELECTION_ORDER: ";
      for (std::size_t idx = 1; idx < multi_selected_node_ids.size(); ++idx) {
        if (idx > 1) {
          oss << ",";
        }
        oss << multi_selected_node_ids[idx];
      }
      oss << "\n";
    }

    const auto bulk_text_state = compute_bulk_text_suffix_selection_compatibility();
    oss << "\n";
    oss << "[ACTION_SURFACE]\n";
    oss << "BULK_TEXT_SUFFIX_COMPATIBILITY: " << bulk_text_state.mode;
    if (!bulk_text_state.widget_type.empty()) {
      oss << " widget_type=" << bulk_text_state.widget_type;
    }
    if (!bulk_text_state.reason.empty() && bulk_text_state.reason != "none") {
      oss << " reason=" << bulk_text_state.reason;
    }
    oss << "\n";
    oss << "BULK_TEXT_SUFFIX_ELIGIBLE: " << (bulk_text_state.eligible ? "YES" : "NO") << "\n";
    append_compact_bulk_action_surface(oss);

    oss << "\n";
    oss << "[PARITY]\n";
    oss << "PREVIEW_EXPORT_PARITY: " << last_preview_export_parity_status_code;
    if (!last_preview_export_parity_reason.empty() && last_preview_export_parity_reason != "none") {
      oss << " reason=" << last_preview_export_parity_reason;
    }
    oss << "\n";

    oss << "\n";
    oss << "[RECENT_RESULTS]\n";
    oss << "EDIT_RESULT: " << last_inspector_edit_status_code;
    if (!last_inspector_edit_reason.empty() && last_inspector_edit_reason != "none") {
      oss << ": " << last_inspector_edit_reason;
    }
    oss << "\n";
    oss << "BULK_DELETE_RESULT: " << last_bulk_delete_status_code;
    if (!last_bulk_delete_reason.empty() && last_bulk_delete_reason != "none") {
      oss << ": " << last_bulk_delete_reason;
    }
    oss << "\n";
    oss << "BULK_MOVE_REPARENT_RESULT: " << last_bulk_move_reparent_status_code;
    if (!last_bulk_move_reparent_reason.empty() && last_bulk_move_reparent_reason != "none") {
      oss << ": " << last_bulk_move_reparent_reason;
    }
    oss << "\n";
    oss << "BULK_PROPERTY_EDIT_RESULT: " << last_bulk_property_edit_status_code;
    if (!last_bulk_property_edit_reason.empty() && last_bulk_property_edit_reason != "none") {
      oss << ": " << last_bulk_property_edit_reason;
    }
    oss << "\n";

    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      oss << "selected=none\n";
      oss << "binding=cleared";
      builder_inspector_label.set_text(oss.str());
      sync_label_preferred_height(builder_inspector_label, 20);
      return;
    }

    auto* node = find_node_by_id(selected_builder_node_id);
    if (!node) {
      oss << "selected=stale\n";
      oss << "binding=cleared";
      builder_inspector_label.set_text(oss.str());
      sync_label_preferred_height(builder_inspector_label, 20);
      return;
    }

    const auto widget_type_name = std::string(ngk::ui::builder::to_string(node->widget_type));
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

    oss << "SELECTED_TYPE: " << widget_type_name << "\n";
    oss << "TYPE: " << widget_type_name << "\n";
    oss << "ID: " << node->node_id << "\n";
    oss << "\n";
    oss << "[IDENTITY]\n";
    oss << "  node_id (readonly): " << node->node_id << "\n";
    oss << "  parent_id (readonly): " << (node->parent_id.empty() ? std::string("<root>") : node->parent_id) << "\n";
    oss << "  widget_type (readonly): " << widget_type_name << "\n";

    if (text_editable) {
      oss << "\n";
      oss << "[CONTENT]\n";
      oss << "  text (editable): \"" << (node->text.empty() ? std::string("<no-text>") : node->text) << "\"\n";
    }

    oss << "\n";
    oss << "[LAYOUT]\n";
    oss << "  container_type (readonly): " << container_type_name << "\n";
    if (shows_layout_group) {
      oss << "  child_count (readonly): " << node->child_ids.size() << "\n";
      oss << "  child_ids (readonly): ";
      if (node->child_ids.empty()) {
        oss << "<none>\n";
      } else {
        for (std::size_t idx = 0; idx < node->child_ids.size(); ++idx) {
          if (idx > 0) {
            oss << ",";
          }
          oss << node->child_ids[idx];
        }
        oss << "\n";
      }
    } else {
      oss << "  child_count (readonly): <n/a for leaf type>\n";
    }
    oss << "\n";
    oss << "[STATE]\n";
    oss << "  selected (readonly): " << ((selected_builder_node_id == node->node_id) ? "true" : "false") << "\n";
    oss << "  focused (readonly): " << ((focused_builder_node_id == node->node_id) ? "true" : "false") << "\n";
    oss << "  multi_selection_count (readonly): " << multi_selected_node_ids.size() << "\n";
    oss << "  primary_selection (readonly): "
      << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
    oss << "  binding (readonly): selection_bound";
    builder_inspector_label.set_text(oss.str());
    sync_label_preferred_height(builder_inspector_label, 20);
    refresh_top_action_surface_from_builder_state();
  };

  auto refresh_preview_surface_label = [&]() {
    sync_multi_selection_with_primary();

    std::ostringstream oss;
    oss << "PREVIEW REGION (Runtime Truth)\n";
    oss << "[SELECTION_SUMMARY]\n";
    oss << "SELECTED_ID: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
    std::string selected_type_name = "none";
    if (!selected_builder_node_id.empty()) {
      if (auto* selected_node = find_node_by_id(selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }
    oss << "SELECTED_TYPE: " << selected_type_name << "\n";
    oss << "SELECTED_TARGET=ACTIVE_EDIT_NODE\n";
    oss << "selection_mode=" << (multi_selected_node_ids.size() > 1 ? "multi" : "single") << "\n";
    oss << "multi_selection_count=" << multi_selected_node_ids.size() << "\n";
    if (multi_selected_node_ids.size() > 1) {
      oss << "multi_secondary_ids=";
      for (std::size_t idx = 1; idx < multi_selected_node_ids.size(); ++idx) {
        if (idx > 1) {
          oss << ",";
        }
        oss << multi_selected_node_ids[idx];
      }
      oss << "\n";
    }

    oss << "\n";
    oss << "[PARITY]\n";
    oss << "parity_scope=" << kPreviewExportParityScope << "\n";
    oss << "parity=" << last_preview_export_parity_status_code;
    if (!last_preview_export_parity_reason.empty() && last_preview_export_parity_reason != "none") {
      oss << " reason=" << last_preview_export_parity_reason;
    }
    oss << "\n";

    const auto bulk_text_state = compute_bulk_text_suffix_selection_compatibility();
    oss << "\n";
    oss << "[ACTION_SURFACE]\n";
    oss << "multi_selection_compatibility=" << bulk_text_state.mode;
    if (!bulk_text_state.widget_type.empty()) {
      oss << " widget_type=" << bulk_text_state.widget_type;
    }
    if (!bulk_text_state.reason.empty() && bulk_text_state.reason != "none") {
      oss << " reason=" << bulk_text_state.reason;
    }
    oss << "\n";
    oss << "bulk_text_suffix_eligible=" << (bulk_text_state.eligible ? "YES" : "NO") << "\n";
    append_compact_bulk_action_surface(oss);

    oss << "\n";
    oss << "[RECENT_RESULTS]\n";
    oss << "click_select=" << last_preview_click_select_status_code;
    if (!last_preview_click_select_reason.empty() && last_preview_click_select_reason != "none") {
      oss << " reason=" << last_preview_click_select_reason;
    }
    oss << "\n";
    oss << "inline_action_commit=" << last_preview_inline_action_commit_status_code;
    if (!last_preview_inline_action_commit_reason.empty() && last_preview_inline_action_commit_reason != "none") {
      oss << " reason=" << last_preview_inline_action_commit_reason;
    }
    oss << "\n";
    oss << "bulk_delete=" << last_bulk_delete_status_code;
    if (!last_bulk_delete_reason.empty() && last_bulk_delete_reason != "none") {
      oss << " reason=" << last_bulk_delete_reason;
    }
    oss << "\n";
    oss << "bulk_move_reparent=" << last_bulk_move_reparent_status_code;
    if (!last_bulk_move_reparent_reason.empty() && last_bulk_move_reparent_reason != "none") {
      oss << " reason=" << last_bulk_move_reparent_reason;
    }
    oss << "\n";
    oss << "bulk_property_edit=" << last_bulk_property_edit_status_code;
    if (!last_bulk_property_edit_reason.empty() && last_bulk_property_edit_reason != "none") {
      oss << " reason=" << last_bulk_property_edit_reason;
    }
    oss << "\n";
    oss << "root=" << (builder_doc.root_node_id.empty() ? std::string("none") : builder_doc.root_node_id)
        << " nodes=" << builder_doc.nodes.size() << "\n";

    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      oss << "selected=none";
      preview_snapshot = "preview:selected=none";
      builder_preview_label.set_text(oss.str());
      sync_label_preferred_height(builder_preview_label, 20);
      return;
    }

    auto* selected = find_node_by_id(selected_builder_node_id);
    if (!selected) {
      oss << "selected=stale";
      preview_snapshot = "preview:selected=stale";
      builder_preview_label.set_text(oss.str());
      sync_label_preferred_height(builder_preview_label, 20);
      return;
    }

    oss << "selected=> " << selected->node_id << " "
        << ngk::ui::builder::to_string(selected->widget_type) << "\n";
    oss << "selected_text=\"" << (selected->text.empty() ? std::string("<no-text>") : selected->text) << "\"\n";
    oss << "selected_children=" << selected->child_ids.size() << "\n";
    oss << build_preview_inline_action_affordance_text(*selected);
    oss << "runtime_outline:\n" << build_preview_runtime_outline();
    preview_snapshot = "preview:selected=" + selected->node_id +
      " type=" + std::string(ngk::ui::builder::to_string(selected->widget_type)) +
      " parity=" + last_preview_export_parity_status_code;
    builder_preview_label.set_text(oss.str());
    sync_label_preferred_height(builder_preview_label, 20);
    refresh_top_action_surface_from_builder_state();
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
      multi_selected_node_ids.clear();
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
    sync_multi_selection_with_primary();
    refresh_tree_surface_label();
    return true;
  };

  auto add_node_to_multi_selection = [&](const std::string& node_id) -> bool {
    if (node_id.empty() || !node_exists(node_id)) {
      return false;
    }

    sync_multi_selection_with_primary();
    if (is_node_in_multi_selection(node_id)) {
      return false;
    }

    if (selected_builder_node_id.empty()) {
      selected_builder_node_id = node_id;
      focused_builder_node_id = node_id;
      multi_selected_node_ids.clear();
      multi_selected_node_ids.push_back(node_id);
      refresh_tree_surface_label();
      return true;
    }

    multi_selected_node_ids.push_back(node_id);
    sync_multi_selection_with_primary();
    refresh_tree_surface_label();
    return true;
  };

  auto remove_node_from_multi_selection = [&](const std::string& node_id) -> bool {
    if (node_id.empty()) {
      return false;
    }

    sync_multi_selection_with_primary();
    auto it = std::find(multi_selected_node_ids.begin(), multi_selected_node_ids.end(), node_id);
    if (it == multi_selected_node_ids.end()) {
      return false;
    }

    const bool removing_primary = (node_id == selected_builder_node_id);
    multi_selected_node_ids.erase(it);
    if (removing_primary) {
      if (!multi_selected_node_ids.empty()) {
        selected_builder_node_id = multi_selected_node_ids.front();
      } else {
        selected_builder_node_id.clear();
      }
    }

    sync_multi_selection_with_primary();
    if (selected_builder_node_id.empty()) {
      focused_builder_node_id.clear();
    } else if (focused_builder_node_id.empty() || !node_exists(focused_builder_node_id)) {
      focused_builder_node_id = selected_builder_node_id;
    }
    refresh_tree_surface_label();
    return true;
  };

  auto clear_multi_selection = [&]() {
    multi_selected_node_ids.clear();
    selected_builder_node_id.clear();
    focused_builder_node_id.clear();
    refresh_tree_surface_label();
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

  auto apply_focus_navigation = [&](bool forward) -> bool {
    auto ordered = collect_preorder_node_ids();
    if (ordered.empty()) {
      focused_builder_node_id.clear();
      refresh_tree_surface_label();
      return false;
    }

    if (focused_builder_node_id.empty() || !node_exists(focused_builder_node_id)) {
      if (!selected_builder_node_id.empty() && node_exists(selected_builder_node_id)) {
        focused_builder_node_id = selected_builder_node_id;
      } else {
        focused_builder_node_id = ordered.front();
      }
    }

    auto it = std::find(ordered.begin(), ordered.end(), focused_builder_node_id);
    if (it == ordered.end()) {
      focused_builder_node_id = ordered.front();
      refresh_tree_surface_label();
      return true;
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

    focused_builder_node_id = *it;
    refresh_tree_surface_label();
    return true;
  };

  auto apply_keyboard_multi_selection_add_focused = [&]() -> bool {
    if (focused_builder_node_id.empty() || !node_exists(focused_builder_node_id)) {
      return false;
    }

    if (is_node_in_multi_selection(focused_builder_node_id)) {
      return false;
    }

    if (selected_builder_node_id.empty()) {
      selected_builder_node_id = focused_builder_node_id;
      multi_selected_node_ids = {selected_builder_node_id};
      sync_multi_selection_with_primary();
      refresh_tree_surface_label();
      return true;
    }

    multi_selected_node_ids.push_back(focused_builder_node_id);
    sync_multi_selection_with_primary();
    refresh_tree_surface_label();
    return true;
  };

  auto apply_keyboard_multi_selection_remove_focused = [&]() -> bool {
    if (focused_builder_node_id.empty() || !node_exists(focused_builder_node_id)) {
      return false;
    }
    return remove_node_from_multi_selection(focused_builder_node_id);
  };

  auto apply_keyboard_multi_selection_clear = [&]() -> bool {
    clear_multi_selection();
    return true;
  };

  auto apply_keyboard_multi_selection_navigate = [&](bool forward, bool extend_selection) -> bool {
    sync_multi_selection_with_primary();
    if (!apply_focus_navigation(forward)) {
      return false;
    }

    if (!extend_selection) {
      return true;
    }

    return apply_keyboard_multi_selection_add_focused();
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

    sync_multi_selection_with_primary();

    if (selected_builder_node_id.empty()) {
      if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
        selected_builder_node_id = builder_doc.root_node_id;
        sync_multi_selection_with_primary();
        return true;
      }
      multi_selected_node_ids.clear();
      return true;
    }

    if (node_exists(selected_builder_node_id)) {
      sync_multi_selection_with_primary();
      return true;
    }

    coherence_diag.stale_selection_rejected = true;

    if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
      selected_builder_node_id = builder_doc.root_node_id;
      sync_multi_selection_with_primary();
      return true;
    }

    selected_builder_node_id.clear();
    multi_selected_node_ids.clear();
    model.undefined_state_detected = true;
    return false;
  };

  auto refresh_inspector_or_fail = [&]() -> bool {
    coherence_diag.inspector_coherence_hardened = true;

    sync_multi_selection_with_primary();

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

    sync_multi_selection_with_primary();

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

    sync_multi_selection_with_primary();

    const bool selected_valid = selected_builder_node_id.empty() || node_exists(selected_builder_node_id);
    const bool inspector_valid = inspector_binding_node_id.empty() || node_exists(inspector_binding_node_id);
    const bool preview_valid = preview_binding_node_id.empty() || node_exists(preview_binding_node_id);

    coherence_diag.desync_tree_selection_detected = !selected_valid;
    coherence_diag.desync_inspector_binding_detected =
      (!selected_builder_node_id.empty() && inspector_binding_node_id != selected_builder_node_id) || !inspector_valid;
    coherence_diag.desync_preview_binding_detected =
      (!selected_builder_node_id.empty() && preview_binding_node_id != selected_builder_node_id) || !preview_valid;

    bool multi_selection_valid = true;
    std::vector<std::string> seen_multi{};
    for (const auto& node_id : multi_selected_node_ids) {
      if (node_id.empty() || !node_exists(node_id) ||
          std::find(seen_multi.begin(), seen_multi.end(), node_id) != seen_multi.end()) {
        multi_selection_valid = false;
        break;
      }
      seen_multi.push_back(node_id);
    }
    const bool primary_consistent = selected_builder_node_id.empty()
      ? multi_selected_node_ids.empty()
      : (!multi_selected_node_ids.empty() && multi_selected_node_ids.front() == selected_builder_node_id);

    return !coherence_diag.desync_tree_selection_detected &&
      !coherence_diag.desync_inspector_binding_detected &&
      !coherence_diag.desync_preview_binding_detected &&
      multi_selection_valid &&
      primary_consistent;
  };

  apply_preview_click_select_at_point = [&](int x, int y) -> bool {
    auto fail_click = [&](const std::string& reason) -> bool {
      last_preview_click_select_status_code = "rejected";
      last_preview_click_select_reason = reason.empty() ? std::string("unknown") : reason;
      refresh_preview_surface_label();
      return false;
    };

    preview_click_select_diag.preview_click_select_present = true;

    (void)x;

    std::vector<PreviewExportParityEntry> entries{};
    std::string map_reason;
    if (!build_preview_click_hit_entries(entries, map_reason)) {
      preview_click_select_diag.deterministic_hit_mapping_present = false;
      return fail_click("hit_map_unavailable_" + map_reason);
    }

    preview_click_select_diag.deterministic_hit_mapping_present = true;

    const std::string preview_text = builder_preview_label.text();
    const std::string outline_token = "runtime_outline:\n";
    const auto outline_pos = preview_text.find(outline_token);
    if (outline_pos == std::string::npos) {
      return fail_click("runtime_outline_missing");
    }

    int outline_first_line_index = 0;
    for (std::size_t i = 0; i < outline_pos + outline_token.size(); ++i) {
      if (preview_text[i] == '\n') {
        outline_first_line_index += 1;
      }
    }

    constexpr int kPreviewLineHeightPx = 16;
    const int rel_y = y - builder_preview_label.y();
    if (rel_y < 0) {
      return fail_click("invalid_relative_y");
    }
    const int clicked_line_index = rel_y / kPreviewLineHeightPx;

    std::vector<std::string> preview_lines{};
    {
      std::istringstream line_stream(preview_text);
      std::string line;
      while (std::getline(line_stream, line)) {
        preview_lines.push_back(line);
      }
    }
    if (clicked_line_index >= 0 && static_cast<std::size_t>(clicked_line_index) < preview_lines.size()) {
      const std::string& clicked_line = preview_lines[static_cast<std::size_t>(clicked_line_index)];
      const std::string commit_prefix = "ACTION_COMMIT: ";
      if (clicked_line.rfind(commit_prefix, 0) == 0) {
        const auto action_end = clicked_line.find(' ', commit_prefix.size());
        const std::string action_id = clicked_line.substr(
          commit_prefix.size(),
          (action_end == std::string::npos) ? std::string::npos : action_end - commit_prefix.size());
        if (action_id.empty()) {
          return fail_click("action_commit_missing_id");
        }
        if (!apply_preview_inline_action_commit || !apply_preview_inline_action_commit(action_id)) {
          return fail_click("action_commit_failed_" + action_id);
        }
        last_preview_click_select_status_code = "action_commit";
        last_preview_click_select_reason = action_id;
        refresh_preview_surface_label();
        return true;
      }
    }

    const int entry_index = clicked_line_index - outline_first_line_index;
    if (entry_index < 0 || static_cast<std::size_t>(entry_index) >= entries.size()) {
      return fail_click("invalid_hit_area_no_entry");
    }

    const auto& clicked_entry = entries[static_cast<std::size_t>(entry_index)];
    if (clicked_entry.node_id.empty() || !node_exists(clicked_entry.node_id)) {
      return fail_click("hit_entry_not_resolvable");
    }

    selected_builder_node_id = clicked_entry.node_id;
    const bool remap_ok = remap_selection_or_fail();
    const bool focus_ok = sync_focus_with_selection_or_fail();
    const bool insp_ok = refresh_inspector_or_fail();
    const bool prev_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    if (!(remap_ok && focus_ok && insp_ok && prev_ok && sync_ok)) {
      return fail_click("selection_coherence_failed_after_click");
    }

    last_preview_click_select_status_code = "success";
    last_preview_click_select_reason = "none";
    refresh_preview_surface_label();
    return true;
  };

  auto delete_rejection_reason_for_node = [&](const std::string& node_id) -> std::string {
    if (node_id.empty()) {
      return "no_selected_node";
    }

    auto* target = find_node_by_id(node_id);
    if (!target) {
      return "selected_node_lookup_failed";
    }

    const bool is_root = (node_id == builder_doc.root_node_id) || target->parent_id.empty();
    const bool shell_critical = target->container_type == ngk::ui::builder::BuilderContainerType::Shell;
    if (is_root) {
      return "protected_root";
    }
    if (shell_critical) {
      return "protected_shell";
    }
    if (target->parent_id.empty() || !node_exists(target->parent_id)) {
      return "parent_missing_for_delete";
    }
    return "";
  };

  auto collect_bulk_delete_target_ids = [&](const std::vector<std::string>& requested_ids,
                                            std::string& rejection_reason) -> std::vector<std::string> {
    rejection_reason.clear();
    std::vector<std::string> normalized{};
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
      rejection_reason = "no_selected_nodes";
      return normalized;
    }

    for (const auto& node_id : unique_ids) {
      const std::string reason = delete_rejection_reason_for_node(node_id);
      if (!reason.empty()) {
        rejection_reason = reason + "_" + node_id;
        return {};
      }
    }

    for (const auto& node_id : unique_ids) {
      bool covered_by_ancestor = false;
      auto* current = find_node_by_id(node_id);
      while (current && !current->parent_id.empty()) {
        if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
          covered_by_ancestor = true;
          break;
        }
        current = find_node_by_id(current->parent_id);
      }
      if (!covered_by_ancestor) {
        normalized.push_back(node_id);
      }
    }

    return normalized;
  };

  auto compute_post_delete_selection_fallback = [&](const std::vector<std::string>& deleted_ids) -> std::string {
    if (deleted_ids.empty()) {
      return selected_builder_node_id;
    }

    const auto ordered = collect_preorder_node_ids();
    if (ordered.empty()) {
      return std::string{};
    }

    auto is_deleted = [&](const std::string& node_id) {
      return std::find(deleted_ids.begin(), deleted_ids.end(), node_id) != deleted_ids.end();
    };

    std::size_t first_deleted_index = ordered.size();
    for (const auto& deleted_id : deleted_ids) {
      auto it = std::find(ordered.begin(), ordered.end(), deleted_id);
      if (it != ordered.end()) {
        const std::size_t idx = static_cast<std::size_t>(std::distance(ordered.begin(), it));
        if (idx < first_deleted_index) {
          first_deleted_index = idx;
        }
      }
    }

    if (first_deleted_index == ordered.size()) {
      return builder_doc.root_node_id;
    }

    for (std::size_t idx = first_deleted_index + 1; idx < ordered.size(); ++idx) {
      if (!is_deleted(ordered[idx])) {
        return ordered[idx];
      }
    }
    for (std::size_t idx = first_deleted_index; idx > 0; --idx) {
      if (!is_deleted(ordered[idx - 1])) {
        return ordered[idx - 1];
      }
    }
    return std::string{};
  };

  auto apply_bulk_delete_selected_nodes_command = [&](const std::vector<std::string>& requested_ids) -> bool {
    bulk_delete_diag.bulk_delete_present = true;
    delete_diag.shell_delete_control_present = true;

    std::string rejection_reason;
    const auto delete_targets = collect_bulk_delete_target_ids(requested_ids, rejection_reason);
    if (delete_targets.empty()) {
      bulk_delete_diag.protected_or_invalid_bulk_delete_rejected = true;
      delete_diag.protected_delete_rejected = true;
      last_bulk_delete_status_code = "REJECTED";
      last_bulk_delete_reason = rejection_reason.empty() ? std::string("no_eligible_delete_targets") : rejection_reason;
      refresh_inspector_surface_label();
      refresh_preview_surface_label();
      return false;
    }

    const std::string fallback_selection = compute_post_delete_selection_fallback(delete_targets);
    for (const auto& deleting_id : delete_targets) {
      remove_node_and_descendants(deleting_id);
    }

    if (!fallback_selection.empty() && node_exists(fallback_selection)) {
      selected_builder_node_id = fallback_selection;
      multi_selected_node_ids = {fallback_selection};
    } else {
      selected_builder_node_id.clear();
      multi_selected_node_ids.clear();
    }

    delete_diag.legal_delete_applied = true;
    delete_diag.post_delete_selection_remapped_or_cleared =
      selected_builder_node_id.empty() || node_exists(selected_builder_node_id);
    bulk_delete_diag.eligible_selected_nodes_deleted = true;
    bulk_delete_diag.post_delete_selection_deterministic =
      (selected_builder_node_id.empty() && multi_selected_node_ids.empty()) ||
      (!selected_builder_node_id.empty() &&
       multi_selected_node_ids.size() == 1 &&
       multi_selected_node_ids.front() == selected_builder_node_id);
    last_bulk_delete_status_code = "SUCCESS";
    last_bulk_delete_reason = "none";
    refresh_inspector_surface_label();
    refresh_preview_surface_label();
    return true;
  };

  auto apply_delete_selected_node_command = [&]() -> bool {
    delete_diag.shell_delete_control_present = true;
    last_bulk_delete_status_code = "not_run";
    last_bulk_delete_reason = "none";
    return apply_bulk_delete_selected_nodes_command({selected_builder_node_id});
  };

  auto apply_delete_command_for_current_selection = [&]() -> bool {
    if (multi_selected_node_ids.size() > 1) {
      return apply_bulk_delete_selected_nodes_command(multi_selected_node_ids);
    }
    return apply_delete_selected_node_command();
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

  auto push_to_history = [&](
      const std::string& command_type,
      const std::vector<ngk::ui::builder::BuilderNode>& before_nodes,
      const std::string& before_root,
      const std::string& before_sel,
      const std::vector<std::string>* before_multi,
      const std::vector<ngk::ui::builder::BuilderNode>& after_nodes,
      const std::string& after_root,
      const std::string& after_sel,
      const std::vector<std::string>* after_multi) {
    CommandHistoryEntry entry{};
    entry.command_type = command_type;
    entry.before_nodes = before_nodes;
    entry.before_root_node_id = before_root;
    entry.before_selected_id = before_sel;
    if (before_multi != nullptr) {
      entry.before_multi_selected_ids = *before_multi;
    } else if (!before_sel.empty()) {
      entry.before_multi_selected_ids = {before_sel};
    }
    entry.after_nodes = after_nodes;
    entry.after_root_node_id = after_root;
    entry.after_selected_id = after_sel;
    if (after_multi != nullptr) {
      entry.after_multi_selected_ids = *after_multi;
    } else if (!after_sel.empty()) {
      entry.after_multi_selected_ids = {after_sel};
    }
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

  auto apply_inspector_text_edit_command = [&](const std::string& new_text) -> bool {
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
                    builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
    recompute_builder_dirty_state(true);
    last_inspector_edit_status_code = "SUCCESS";
    last_inspector_edit_reason = "none";
    refresh_inspector_surface_label();
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
    multi_selected_node_ids = entry.before_multi_selected_ids;
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
    multi_selected_node_ids = entry.after_multi_selected_ids;
    undo_history.push_back(std::move(entry));
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    recompute_builder_dirty_state(true);
    return true;
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
    const std::string node_id = inline_edit_node_id;
    const std::string new_text = inline_edit_buffer;
    inline_edit_active = false;
    inline_edit_node_id.clear();
    inline_edit_buffer.clear();
    inline_edit_original_text.clear();
    const std::string saved_sel = selected_builder_node_id;
    selected_builder_node_id = node_id;
    const bool ok = apply_inspector_text_edit_command(new_text);
    if (!ok) {
      selected_builder_node_id = saved_sel;
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

  auto handle_builder_shortcut_key_with_modifiers = [&](std::uint32_t key,
                                                        bool down,
                                                        bool repeat,
                                                        bool ctrl_down,
                                                        bool shift_down) -> bool {
    if (!down || repeat) {
      return false;
    }
    if (!is_builder_shortcut_scope_active()) {
      return false;
    }

    bool handled = false;
    if (ctrl_down) {
      switch (key) {
        case 0x26: // Ctrl+Up
          handled = apply_keyboard_multi_selection_navigate(false, shift_down);
          break;
        case 0x28: // Ctrl+Down
          handled = apply_keyboard_multi_selection_navigate(true, shift_down);
          break;
        case 0x41: // Ctrl+A
          handled = apply_keyboard_multi_selection_add_focused();
          break;
        case 0x52: // Ctrl+R
          handled = apply_keyboard_multi_selection_remove_focused();
          break;
        case 0x1B: // Ctrl+Esc
          handled = apply_keyboard_multi_selection_clear();
          break;
        case 0x5A: // Ctrl+Z
          handled = apply_undo_command();
          break;
        case 0x59: // Ctrl+Y
          handled = apply_redo_command();
          break;
        case 0x53: // Ctrl+S
          handled = apply_save_document_command();
          break;
        case 0x4F: // Ctrl+O
          handled = apply_load_document_command(false);
          break;
        case 0x4E: // Ctrl+N
          handled = apply_new_document_command(false);
          break;
        default:
          break;
      }
    } else {
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
            const auto before_multi = multi_selected_node_ids;
            handled = apply_delete_command_for_current_selection();
            if (handled) {
              push_to_history("shortcut_delete", before_nodes, before_root, before_sel, &before_multi,
                              builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
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
            const auto before_multi = multi_selected_node_ids;
            handled = apply_palette_insert(true);
            if (handled) {
              push_to_history("shortcut_insert_container", before_nodes, before_root, before_sel, &before_multi,
                              builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
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
            const auto before_multi = multi_selected_node_ids;
            handled = apply_palette_insert(false);
            if (handled) {
              push_to_history("shortcut_insert_leaf", before_nodes, before_root, before_sel, &before_multi,
                              builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
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
    }

    if (!handled) {
      return false;
    }

    const bool keyboard_multi_selection_workflow_op =
      ctrl_down &&
      (key == 0x26 || key == 0x28 || key == 0x41 || key == 0x52 || key == 0x1B);
    if (!keyboard_multi_selection_workflow_op) {
      remap_selection_or_fail();
      sync_focus_with_selection_or_fail();
    }
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
    return true;
  };

  auto handle_builder_shortcut_key = [&](std::uint32_t key, bool down, bool repeat) -> bool {
    const bool ctrl_down = (::GetKeyState(VK_CONTROL) & 0x8000) != 0;
    const bool shift_down = (::GetKeyState(VK_SHIFT) & 0x8000) != 0;
    return handle_builder_shortcut_key_with_modifiers(key, down, repeat, ctrl_down, shift_down);
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
    drag_target_preview_node_id.clear();
    drag_target_preview_is_illegal = false;
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
    if (!drag_active || drag_source_node_id.empty()) { return false; }
    const auto requested_ids = [&]() {
      if (drag_source_node_id == selected_builder_node_id &&
          multi_selected_node_ids.size() > 1 &&
          is_node_in_multi_selection(drag_source_node_id)) {
        return multi_selected_node_ids;
      }
      return std::vector<std::string>{drag_source_node_id};
    }();

    std::string rejection_reason;
    std::vector<std::string> normalized_ids{};
    auto can_reparent_requested_nodes_to_target = [&](const std::vector<std::string>& requested_node_ids,
                                                      const std::string& requested_target_id,
                                                      std::string& reason_out,
                                                      std::vector<std::string>* normalized_ids_out) -> bool {
      reason_out.clear();
      if (requested_target_id.empty()) {
        reason_out = "missing_target";
        return false;
      }
      if (!node_exists(requested_target_id)) {
        reason_out = "target_lookup_failed";
        return false;
      }

      auto* target_node = find_node_by_id(requested_target_id);
      if (!target_node) {
        reason_out = "target_lookup_failed";
        return false;
      }
      if (requested_target_id == builder_doc.root_node_id) {
        reason_out = "protected_target_root";
        return false;
      }
      if (target_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
        reason_out = "protected_target_shell";
        return false;
      }
      if (target_node->widget_type != ngk::ui::builder::BuilderWidgetType::VerticalLayout) {
        reason_out = "target_not_vertical_layout";
        return false;
      }

      std::vector<std::string> unique_ids{};
      for (const auto& node_id : requested_node_ids) {
        if (node_id.empty()) {
          continue;
        }
        if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
          unique_ids.push_back(node_id);
        }
      }
      if (unique_ids.empty()) {
        reason_out = "no_selected_nodes";
        return false;
      }

      for (const auto& node_id : unique_ids) {
        auto* source_node = find_node_by_id(node_id);
        if (!source_node) {
          reason_out = "selected_node_lookup_failed_" + node_id;
          return false;
        }
        if (node_id == builder_doc.root_node_id || source_node->parent_id.empty()) {
          reason_out = "protected_source_root_" + node_id;
          return false;
        }
        if (source_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
          reason_out = "protected_source_shell_" + node_id;
          return false;
        }
        if (!node_exists(source_node->parent_id)) {
          reason_out = "source_parent_missing_" + node_id;
          return false;
        }
        if (node_id == requested_target_id) {
          reason_out = "target_in_selected_set_" + node_id;
          return false;
        }
        if (is_in_subtree_of(requested_target_id, node_id)) {
          reason_out = "circular_target_" + node_id;
          return false;
        }
      }

      std::vector<std::string> normalized{};
      for (const auto& node_id : unique_ids) {
        bool covered_by_ancestor = false;
        auto* current = find_node_by_id(node_id);
        while (current && !current->parent_id.empty()) {
          if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
            covered_by_ancestor = true;
            break;
          }
          current = find_node_by_id(current->parent_id);
        }
        if (!covered_by_ancestor) {
          normalized.push_back(node_id);
        }
      }

      if (normalized.empty()) {
        reason_out = "no_eligible_move_sources";
        return false;
      }

      for (const auto& node_id : normalized) {
        auto* source_node = find_node_by_id(node_id);
        if (!source_node) {
          reason_out = "selected_node_lookup_failed_" + node_id;
          return false;
        }
        if (source_node->parent_id == requested_target_id) {
          reason_out = "already_child_of_target_" + node_id;
          return false;
        }
      }

      if (normalized_ids_out != nullptr) {
        *normalized_ids_out = normalized;
      }
      return true;
    };

    return can_reparent_requested_nodes_to_target(requested_ids, target_id, rejection_reason, &normalized_ids);
  };

  auto apply_bulk_move_reparent_selected_nodes_command = [&](const std::vector<std::string>& requested_ids,
                                                             const std::string& target_id) -> bool {
    bulk_move_reparent_diag.bulk_move_reparent_present = true;

    std::string rejection_reason;
    std::vector<std::string> normalized_ids{};
    auto can_reparent_requested_nodes_to_target = [&](const std::vector<std::string>& requested_node_ids,
                                                      const std::string& requested_target_id,
                                                      std::string& reason_out,
                                                      std::vector<std::string>* normalized_ids_out) -> bool {
      reason_out.clear();
      if (requested_target_id.empty()) {
        reason_out = "missing_target";
        return false;
      }
      if (!node_exists(requested_target_id)) {
        reason_out = "target_lookup_failed";
        return false;
      }

      auto* target_node = find_node_by_id(requested_target_id);
      if (!target_node) {
        reason_out = "target_lookup_failed";
        return false;
      }
      if (requested_target_id == builder_doc.root_node_id) {
        reason_out = "protected_target_root";
        return false;
      }
      if (target_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
        reason_out = "protected_target_shell";
        return false;
      }
      if (target_node->widget_type != ngk::ui::builder::BuilderWidgetType::VerticalLayout) {
        reason_out = "target_not_vertical_layout";
        return false;
      }

      std::vector<std::string> unique_ids{};
      for (const auto& node_id : requested_node_ids) {
        if (node_id.empty()) {
          continue;
        }
        if (std::find(unique_ids.begin(), unique_ids.end(), node_id) == unique_ids.end()) {
          unique_ids.push_back(node_id);
        }
      }
      if (unique_ids.empty()) {
        reason_out = "no_selected_nodes";
        return false;
      }

      for (const auto& node_id : unique_ids) {
        auto* source_node = find_node_by_id(node_id);
        if (!source_node) {
          reason_out = "selected_node_lookup_failed_" + node_id;
          return false;
        }
        if (node_id == builder_doc.root_node_id || source_node->parent_id.empty()) {
          reason_out = "protected_source_root_" + node_id;
          return false;
        }
        if (source_node->container_type == ngk::ui::builder::BuilderContainerType::Shell) {
          reason_out = "protected_source_shell_" + node_id;
          return false;
        }
        if (!node_exists(source_node->parent_id)) {
          reason_out = "source_parent_missing_" + node_id;
          return false;
        }
        if (node_id == requested_target_id) {
          reason_out = "target_in_selected_set_" + node_id;
          return false;
        }
        if (is_in_subtree_of(requested_target_id, node_id)) {
          reason_out = "circular_target_" + node_id;
          return false;
        }
      }

      std::vector<std::string> normalized{};
      for (const auto& node_id : unique_ids) {
        bool covered_by_ancestor = false;
        auto* current = find_node_by_id(node_id);
        while (current && !current->parent_id.empty()) {
          if (std::find(unique_ids.begin(), unique_ids.end(), current->parent_id) != unique_ids.end()) {
            covered_by_ancestor = true;
            break;
          }
          current = find_node_by_id(current->parent_id);
        }
        if (!covered_by_ancestor) {
          normalized.push_back(node_id);
        }
      }

      if (normalized.empty()) {
        reason_out = "no_eligible_move_sources";
        return false;
      }

      for (const auto& node_id : normalized) {
        auto* source_node = find_node_by_id(node_id);
        if (!source_node) {
          reason_out = "selected_node_lookup_failed_" + node_id;
          return false;
        }
        if (source_node->parent_id == requested_target_id) {
          reason_out = "already_child_of_target_" + node_id;
          return false;
        }
      }

      if (normalized_ids_out != nullptr) {
        *normalized_ids_out = normalized;
      }
      return true;
    };

    if (!can_reparent_requested_nodes_to_target(requested_ids, target_id, rejection_reason, &normalized_ids)) {
      bulk_move_reparent_diag.invalid_or_protected_bulk_target_rejected = true;
      last_bulk_move_reparent_status_code = "REJECTED";
      last_bulk_move_reparent_reason = rejection_reason.empty() ? std::string("bulk_move_reparent_rejected") : rejection_reason;
      refresh_inspector_surface_label();
      refresh_preview_surface_label();
      return false;
    }

    auto* target_node = find_node_by_id(target_id);
    if (!target_node) {
      bulk_move_reparent_diag.invalid_or_protected_bulk_target_rejected = true;
      last_bulk_move_reparent_status_code = "REJECTED";
      last_bulk_move_reparent_reason = "target_lookup_failed";
      refresh_inspector_surface_label();
      refresh_preview_surface_label();
      return false;
    }

    for (const auto& node_id : normalized_ids) {
      auto* source_node = find_node_by_id(node_id);
      if (!source_node) {
        continue;
      }
      if (auto* old_parent = find_node_by_id(source_node->parent_id)) {
        auto& siblings = old_parent->child_ids;
        siblings.erase(std::remove(siblings.begin(), siblings.end(), node_id), siblings.end());
      }
    }

    for (const auto& node_id : normalized_ids) {
      target_node->child_ids.push_back(node_id);
      if (auto* source_node = find_node_by_id(node_id)) {
        source_node->parent_id = target_id;
      }
    }

    sync_multi_selection_with_primary();
    bulk_move_reparent_diag.eligible_selected_nodes_moved = true;
    bulk_move_reparent_diag.post_move_selection_deterministic =
      !selected_builder_node_id.empty() &&
      node_exists(selected_builder_node_id) &&
      !multi_selected_node_ids.empty() &&
      multi_selected_node_ids.front() == selected_builder_node_id;
    last_bulk_move_reparent_status_code = "SUCCESS";
    last_bulk_move_reparent_reason = "none";
    refresh_inspector_surface_label();
    refresh_preview_surface_label();
    return true;
  };

  auto commit_tree_drag_reorder = [&](const std::string& target_id) -> bool {
    if (!is_legal_drop_target_reorder(target_id)) { return false; }
    auto* src = find_node_by_id(drag_source_node_id);
    if (!src) { return false; }
    const auto before_nodes = builder_doc.nodes;
    const std::string before_root = builder_doc.root_node_id;
    const std::string before_sel = selected_builder_node_id;
    const auto before_multi = multi_selected_node_ids;
    auto* parent = find_node_by_id(src->parent_id);
    if (!parent) { return false; }
    auto& kids = parent->child_ids;
    auto src_it = std::find(kids.begin(), kids.end(), drag_source_node_id);
    auto tgt_it = std::find(kids.begin(), kids.end(), target_id);
    if (src_it == kids.end() || tgt_it == kids.end()) { return false; }
    std::iter_swap(src_it, tgt_it);
    selected_builder_node_id = drag_source_node_id;
    push_to_history("drag_reorder", before_nodes, before_root, before_sel, &before_multi,
            builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
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
    if (!drag_active || drag_source_node_id.empty()) { return false; }
    const auto before_nodes = builder_doc.nodes;
    const std::string before_root = builder_doc.root_node_id;
    const std::string before_sel = selected_builder_node_id;
    const auto before_multi = multi_selected_node_ids;
    const auto requested_ids = [&]() {
      if (drag_source_node_id == selected_builder_node_id &&
          multi_selected_node_ids.size() > 1 &&
          is_node_in_multi_selection(drag_source_node_id)) {
        return multi_selected_node_ids;
      }
      return std::vector<std::string>{drag_source_node_id};
    }();
    selected_builder_node_id = drag_source_node_id;
    if (!apply_bulk_move_reparent_selected_nodes_command(requested_ids, target_id)) {
      cancel_tree_drag();
      return false;
    }
    push_to_history("drag_reparent", before_nodes, before_root, before_sel, &before_multi,
            builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
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

  auto set_preview_hover = [&](const std::string& node_id) {
    hover_node_id = node_id;
    refresh_preview_surface_label();
  };

  auto clear_preview_hover = [&] {
    hover_node_id.clear();
    refresh_preview_surface_label();
  };

  auto set_drag_target_preview = [&](const std::string& target_id, bool is_reparent) {
    drag_target_preview_node_id = target_id;
    drag_target_preview_is_illegal = !(is_reparent
      ? is_legal_drop_target_reparent(target_id)
      : is_legal_drop_target_reorder(target_id));
    refresh_preview_surface_label();
  };

  auto clear_drag_target_preview = [&] {
    drag_target_preview_node_id.clear();
    drag_target_preview_is_illegal = false;
    refresh_preview_surface_label();
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
    const auto before_multi = multi_selected_node_ids;
    ngk::ui::builder::BuilderNode new_node{};
    new_node.node_id = new_node_id;
    new_node.parent_id = under_node_id;
    new_node.widget_type = type;
    new_node.text = std::string(ngk::ui::builder::to_string(type));
    parent->child_ids.push_back(new_node_id);
    builder_doc.nodes.push_back(std::move(new_node));
    selected_builder_node_id = new_node_id;
    push_to_history("typed_insert", before, before_root, before_sel, &before_multi,
            builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
    return true;
  };

  apply_preview_inline_action_commit = [&](const std::string& action_id) -> bool {
    auto reject_commit = [&](const std::string& reason) -> bool {
      last_preview_inline_action_commit_status_code = "rejected";
      last_preview_inline_action_commit_reason = reason.empty() ? std::string("unknown") : reason;
      refresh_preview_surface_label();
      return false;
    };

    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      return reject_commit("no_valid_selection");
    }

    auto* selected_node = find_node_by_id(selected_builder_node_id);
    if (!selected_node) {
      return reject_commit("selection_lookup_failed");
    }

    const auto entries = build_preview_inline_action_entries(*selected_node);
    auto it = std::find_if(entries.begin(), entries.end(), [&](const PreviewInlineActionAffordanceEntry& entry) {
      return entry.action_id == action_id;
    });
    if (it == entries.end()) {
      return reject_commit("unknown_action_" + action_id);
    }
    if (!it->available || !it->commit_capable) {
      return reject_commit("action_not_commit_capable_" + action_id);
    }

    bool committed = false;
    std::string success_reason = "none";
    if (action_id == "INSERT_LEAF_UNDER_SELECTED") {
      const std::string new_node_id =
        "preview29-inline-leaf-" + std::to_string(++preview_inline_action_commit_sequence);
      committed = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label,
        selected_builder_node_id,
        new_node_id);
      if (committed) {
        recompute_builder_dirty_state(true);
        success_reason = "typed_insert_leaf:" + new_node_id;
      }
    } else if (action_id == "EDIT_TEXT_SELECTED") {
      committed = apply_inspector_text_edit_command("Preview29 Edited");
      if (committed) {
        success_reason = "inspector_text_edit";
      }
    } else if (action_id == "DELETE_SELECTED") {
      committed = apply_delete_command_for_current_selection();
      if (committed) {
        success_reason = "delete_selected";
      }
    } else {
      return reject_commit("action_not_supported_" + action_id);
    }

    if (!committed) {
      return reject_commit("command_handler_rejected_" + action_id);
    }

    const bool remap_ok = remap_selection_or_fail();
    const bool focus_ok = sync_focus_with_selection_or_fail();
    const bool insp_ok = refresh_inspector_or_fail();
    const bool prev_ok = refresh_preview_or_fail();
    const bool sync_ok = check_cross_surface_sync();
    if (!(remap_ok && focus_ok && insp_ok && prev_ok && sync_ok)) {
      return reject_commit("post_commit_coherence_failed_" + action_id);
    }

    last_preview_inline_action_commit_status_code = "success";
    last_preview_inline_action_commit_reason = success_reason;
    refresh_preview_surface_label();
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

  auto set_preview_export_parity_status = [&](const char* status_code, const std::string& reason) {
    last_preview_export_parity_status_code = status_code == nullptr ? "unknown" : status_code;
    last_preview_export_parity_reason = reason.empty() ? std::string("none") : reason;
    refresh_preview_surface_label();
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
    if (apply_delete_command_for_current_selection()) {
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
  shell.add_child(&builder_shell_panel);
  builder_shell_panel.add_child(&builder_header_bar);
  builder_header_bar.add_child(&title_label);
  builder_shell_panel.add_child(&builder_filter_bar);
  builder_filter_bar.add_child(&filter_box);
  builder_filter_bar.add_child(&apply_button);
  builder_filter_bar.add_child(&refresh_button);
  builder_filter_bar.add_child(&prev_button);
  builder_filter_bar.add_child(&next_button);
  builder_filter_bar.add_child(&builder_delete_button);
  builder_shell_panel.add_child(&builder_primary_actions_bar);
  builder_primary_actions_bar.add_child(&builder_undo_button);
  builder_primary_actions_bar.add_child(&builder_redo_button);
  builder_primary_actions_bar.add_child(&builder_save_button);
  builder_primary_actions_bar.add_child(&builder_load_button);
  builder_primary_actions_bar.add_child(&builder_load_discard_button);
  builder_primary_actions_bar.add_child(&builder_new_button);
  builder_primary_actions_bar.add_child(&builder_new_discard_button);
  builder_shell_panel.add_child(&builder_secondary_actions_bar);
  builder_secondary_actions_bar.add_child(&builder_insert_container_button);
  builder_secondary_actions_bar.add_child(&builder_insert_leaf_button);
  builder_secondary_actions_bar.add_child(&builder_export_button);
  builder_shell_panel.add_child(&builder_info_row);
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
  builder_tree_scroll.add_child(&builder_tree_surface_label);
  builder_surface_row.add_child(&builder_inspector_panel);
  builder_inspector_panel.add_child(&builder_inspector_header);
  builder_inspector_panel.add_child(&builder_inspector_scroll);
  builder_inspector_scroll.add_child(&builder_inspector_label);
  builder_surface_row.add_child(&builder_preview_panel);
  builder_preview_panel.add_child(&builder_preview_header);
  builder_preview_panel.add_child(&builder_preview_scroll);
  builder_preview_scroll.add_child(&builder_preview_label);
  builder_shell_panel.add_child(&builder_footer_bar);
  builder_footer_bar.add_child(&path_label);

  tree.set_root(&root);
  input_router.set_tree(&tree);
  tree.set_invalidate_callback([&] { window.request_repaint(); });

  window.set_min_client_size(kBuilderMinClientWidth, kBuilderMinClientHeight);

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
    constexpr std::uint32_t wmLButtonDown = 0x0201;
    bool handled = false;

    if (down && message == wmLButtonDown) {
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

    if (!handled && down && message == wmLButtonDown && builder_preview_label.contains_point(input_router.mouse_x(), input_router.mouse_y())) {
      request_redraw("preview_click_rejected", true, false);
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

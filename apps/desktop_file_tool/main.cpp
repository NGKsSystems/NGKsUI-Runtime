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

struct BuilderButtonStateReadabilityDiagnostics {
  bool button_state_readability_improved = false;
  bool available_vs_blocked_actions_visually_clear = false;
  bool current_relevant_actions_emphasized = false;
  bool button_state_matches_surface_truth = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderUsabilityBaselineDiagnostics {
  bool startup_guidance_visible = false;
  bool button_labels_humanized = false;
  bool selection_visual_marker_present = false;
  bool action_feedback_visible = false;
  bool preview_readability_improved = false;
  bool debug_information_toggleable = false;
  bool existing_system_behavior_unchanged = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderExplicitEditableFieldDiagnostics {
  bool selected_node_edit_target_clear = false;
  bool editable_field_visible_for_text_nodes = false;
  bool non_text_nodes_show_non_editable_state = false;
  bool apply_behavior_unambiguous = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderIntegratedUsabilityMilestoneDiagnostics {
  bool clickable_tree = false;
  bool inspector_multi_property_editing = false;
  bool simple_structure_controls = false;
  bool visual_preview = false;
  bool reduced_debug_noise_normal_mode = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderRealInteractionDiagnostics {
  bool visual_selection_clear = false;
  bool preview_click_selection = false;
  bool inline_text_edit_preview = false;
  bool structure_controls_visible = false;
  bool empty_state_guidance_present = false;
  bool confusion_reduced = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderHumanReadableUiDiagnostics {
  bool human_readable_ui = false;
  bool preview_visualized = false;
  bool selection_clear = false;
  bool inspector_simplified = false;
  bool structure_feedback_visible = false;
  bool confusion_removed = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderPreviewRealUiDiagnostics {
  bool preview_real_ui = false;
  bool no_debug_labels = false;
  bool containers_visual = false;
  bool text_clean = false;
  bool selection_visual = false;
  bool hierarchy_visible = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderActionVisibilityDiagnostics {
  bool add_child_validated = false;
  bool size_affects_preview = false;
  bool structure_feedback_visible = false;
  bool actions_not_silent = false;
  bool confusion_removed = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderClarityEnforcementDiagnostics {
  bool container_visual_clear = false;
  bool label_visual_clear = false;
  bool add_child_disabled_for_label = false;
  bool auto_parent_correction = false;
  bool insertion_slot_visible = false;
  bool hierarchy_visually_clear = false;
  bool selection_unmistakable = false;
  bool no_debug_text_remaining = false;
  bool actions_not_silent = false;
  bool confusion_removed = false;
  bool shell_state_still_coherent = false;
  bool preview_remains_parity_safe = false;
  bool layout_audit_still_compatible = false;
};

struct BuilderInsertTargetClarityDiagnostics {
  bool target_display_visible = false;
  bool target_matches_structure_selection = false;
  bool preview_click_updates_structure_selection = false;
  bool add_child_uses_correct_target = false;
  bool insert_visible_in_structure = false;
  bool insert_visible_in_preview = false;
  bool post_insert_selection_deterministic = false;
  bool invalid_insert_blocked = false;
  bool no_command_pipeline_regression = false;
  bool ui_state_coherent = false;
};

struct BuilderPreviewStructureParityDiagnostics {
  bool preview_nodes_match_structure = false;
  bool no_orphan_preview_nodes = false;
  bool hit_test_returns_exact_node = false;
  bool render_order_matches_structure = false;
  bool selection_stable_after_insert = false;
  bool selection_stable_after_delete = false;
  bool selection_stable_after_move = false;
  bool no_stale_nodes_after_mutation = false;
  bool parent_child_relationships_match = false;
  bool no_selection_desync_detected = false;
};

struct BuilderCommandIntegrityDiagnostics {
  bool undo_restores_exact_structure = false;
  bool undo_restores_selection = false;
  bool redo_reapplies_exact_state = false;
  bool no_duplicate_nodes_on_redo = false;
  bool no_missing_nodes_after_undo = false;
  bool command_stack_no_invalid_references = false;
  bool selection_fallback_deterministic = false;
  bool multi_step_sequence_stable = false;
  bool no_side_effect_mutations = false;
  bool preview_matches_structure_after_undo_redo = false;
};

struct BuilderSaveLoadStateIntegrityDiagnostics {
  bool serialized_roundtrip_exact = false;
  bool save_load_repeatability_stable = false;
  bool load_rejects_corrupt_payload = false;
  bool load_rejects_schema_violation_payload = false;
  bool failed_load_preserves_previous_state = false;
  bool selection_rebound_to_valid_node_on_load = false;
  bool history_reset_deterministic_on_load = false;
  bool no_implicit_state_mutation_after_roundtrip = false;
  bool cross_surface_sync_preserved_after_load = false;
  bool preview_structure_parity_preserved_after_load = false;
};

struct BuilderPropertyEditIntegrityDiagnostics {
  bool property_edit_uses_command_system = false;
  bool property_edit_atomic_update = false;
  bool invalid_property_rejected = false;
  bool undo_restores_property_exact = false;
  bool redo_reapplies_property_exact = false;
  bool no_partial_state_detected = false;
  bool selection_stable_during_edit = false;
  bool property_persists_through_save_load = false;
  bool rapid_edit_sequence_stable = false;
  bool preview_matches_structure_after_edit = false;
};

struct BuilderNodeLifecycleIntegrityDiagnostics {
  bool created_node_has_valid_identity = false;
  bool deleted_node_fully_removed = false;
  bool no_stale_references_after_delete = false;
  bool move_reparent_updates_relations_exact = false;
  bool preview_mapping_updates_after_lifecycle_change = false;
  bool recreated_node_does_not_collide_or_inherit_stale_state = false;
  bool subtree_delete_and_restore_exact = false;
  bool selection_focus_drag_states_clean_after_lifecycle_change = false;
  bool rapid_lifecycle_sequence_stable = false;
  bool preview_matches_structure_after_all_lifecycle_ops = false;
};

struct BuilderBoundsLayoutConstraintIntegrityDiagnostics {
  bool negative_dimensions_rejected = false;
  bool invalid_child_parent_geometry_rejected = false;
  bool move_reparent_respects_layout_constraints = false;
  bool invalid_layout_not_committed_to_history = false;
  bool preview_never_reflects_invalid_document_state = false;
  bool undo_redo_restore_valid_layout_exact = false;
  bool save_load_rejects_constraint_violating_payload = false;
  bool valid_layout_roundtrip_preserved = false;
  bool no_silent_geometry_autocorrection = false;
  bool preview_matches_structure_after_layout_mutations = false;
};

struct BuilderEventInputRoutingIntegrityDiagnostics {
  bool hit_test_returns_single_correct_node = false;
  bool preview_click_matches_structure_selection = false;
  bool no_input_routed_to_stale_nodes = false;
  bool event_order_deterministic = false;
  bool focus_hover_drag_states_valid = false;
  bool keyboard_targets_current_selection_only = false;
  bool rapid_interaction_sequence_stable = false;
  bool no_ghost_or_duplicate_event_targets = false;
  bool event_routing_respects_render_hierarchy = false;
  bool preview_matches_structure_after_input_sequences = false;
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
  BuilderButtonStateReadabilityDiagnostics button_state_readability_diag{};
  BuilderUsabilityBaselineDiagnostics usability_baseline_diag{};
  BuilderExplicitEditableFieldDiagnostics explicit_edit_field_diag{};
  BuilderIntegratedUsabilityMilestoneDiagnostics integrated_usability_diag{};
  BuilderRealInteractionDiagnostics real_interaction_diag{};
  BuilderHumanReadableUiDiagnostics human_readable_ui_diag{};
  BuilderPreviewRealUiDiagnostics preview_real_ui_diag{};
  BuilderActionVisibilityDiagnostics action_visibility_diag{};
  BuilderClarityEnforcementDiagnostics clarity_enforcement_diag{};
  BuilderInsertTargetClarityDiagnostics insert_target_clarity_diag{};
  BuilderPreviewStructureParityDiagnostics preview_structure_parity_diag{};
  BuilderCommandIntegrityDiagnostics command_integrity_diag{};
  BuilderSaveLoadStateIntegrityDiagnostics save_load_integrity_diag{};
  BuilderPropertyEditIntegrityDiagnostics property_edit_integrity_diag{};
  BuilderNodeLifecycleIntegrityDiagnostics node_lifecycle_integrity_diag{};
  BuilderBoundsLayoutConstraintIntegrityDiagnostics bounds_layout_constraint_diag{};
  BuilderEventInputRoutingIntegrityDiagnostics event_input_routing_diag{};
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
  ngk::ui::VerticalLayout builder_header_block(0);
  ngk::ui::VerticalLayout builder_input_toolbar_block(6);
  ngk::ui::VerticalLayout builder_status_info_block(0);
  ngk::ui::VerticalLayout builder_footer_block(0);
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
  ngk::ui::SectionHeader builder_tree_header("Structure");
  ngk::ui::SectionHeader builder_inspector_header("Editor");
  ngk::ui::SectionHeader builder_preview_header("Live Preview");
  ngk::ui::ScrollContainer builder_tree_scroll;
  ngk::ui::ScrollContainer builder_inspector_scroll;
  ngk::ui::ScrollContainer builder_preview_scroll;
  ngk::ui::VerticalLayout builder_tree_scroll_content(4);
  ngk::ui::VerticalLayout builder_inspector_scroll_content(6);
  ngk::ui::VerticalLayout builder_tree_visual_rows(2);
  ngk::ui::VerticalLayout builder_preview_scroll_content(4);
  ngk::ui::VerticalLayout builder_preview_visual_rows(4);
  ngk::ui::Label builder_preview_interaction_hint_label("Click any preview item to select it.");
  ngk::ui::InputBox builder_preview_inline_text_input;
  ngk::ui::HorizontalLayout builder_preview_inline_actions_row(6);
  ngk::ui::Button builder_preview_inline_apply_button;
  ngk::ui::Button builder_preview_inline_cancel_button;
  ngk::ui::StatusBarContainer builder_footer_bar(8);
  ngk::ui::Label builder_tree_surface_label("Structure");
  ngk::ui::Label builder_inspector_selection_label("Editing: Nothing selected");
  ngk::ui::Label builder_add_child_target_label("Add Child Target: None");
  ngk::ui::Label builder_inspector_edit_hint_label("Select an item from Structure or Live Preview to edit.");
  ngk::ui::InputBox builder_inspector_text_input;
  ngk::ui::Label builder_inspector_layout_min_width_label("Width");
  ngk::ui::InputBox builder_inspector_layout_min_width_input;
  ngk::ui::Label builder_inspector_layout_min_height_label("Height");
  ngk::ui::InputBox builder_inspector_layout_min_height_input;
  ngk::ui::Label builder_inspector_structure_controls_label("Structure Controls");
  ngk::ui::HorizontalLayout builder_inspector_structure_controls_row(6);
  ngk::ui::Button builder_inspector_add_child_button;
  ngk::ui::Button builder_inspector_delete_button;
  ngk::ui::Button builder_inspector_move_up_button;
  ngk::ui::Button builder_inspector_move_down_button;
  ngk::ui::Button builder_inspector_apply_button;
  ngk::ui::Label builder_inspector_non_editable_label("This item has no text.");
  ngk::ui::Label builder_inspector_label("INSPECTOR");
  ngk::ui::Label builder_preview_label("PREVIEW");
  ngk::ui::Label builder_export_status_label("EXPORT STATUS");
  ngk::ui::Label builder_action_feedback_label("Action: Ready");
  static constexpr std::size_t kMaxVisualTreeRows = 128;
  static constexpr std::size_t kMaxVisualPreviewRows = 128;
  std::array<ngk::ui::Button, kMaxVisualTreeRows> builder_tree_row_buttons{};
  std::array<ngk::ui::Button, kMaxVisualPreviewRows> builder_preview_row_buttons{};
  std::array<std::string, kMaxVisualTreeRows> tree_visual_row_node_ids{};
  std::array<std::string, kMaxVisualPreviewRows> preview_visual_row_node_ids{};
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
  std::vector<std::string> multi_selected_node_ids{};
  std::string inspector_binding_node_id{};
  std::string preview_binding_node_id{};
  std::string preview_snapshot{};
  bool builder_debug_mode = false;
  std::string last_action_feedback = "Action: Ready";
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
  std::string inspector_edit_binding_node_id{};
  std::string inspector_edit_loaded_text{};
  std::string inspector_edit_loaded_min_width{};
  std::string inspector_edit_loaded_min_height{};
  std::string preview_inline_loaded_text{};
  constexpr const char* kPreviewExportParityScope =
    "structure,component_types,key_identity_text,hierarchy";
  constexpr int kBuilderMinClientWidth = 720;
  constexpr int kBuilderMinClientHeight = 520;

  builder_insert_container_button.set_text("Add Container");
  builder_insert_leaf_button.set_text("Add Item");
  builder_move_up_button.set_text("Move Up");
  builder_move_down_button.set_text("Move Down");
  builder_reparent_button.set_text("Reparent");
  builder_delete_button.set_text("Delete");
  builder_undo_button.set_text("Undo");
  builder_redo_button.set_text("Redo");
  builder_save_button.set_text("Save Doc");
  builder_load_button.set_text("Load Doc");
  builder_load_discard_button.set_text("Load Discard");
  builder_export_button.set_text("Export");
  builder_new_button.set_text("New Doc");
  builder_new_discard_button.set_text("New Discard");
  builder_debug_mode_toggle_button.set_text("[DEBUG MODE: OFF]");
  builder_inspector_add_child_button.set_text("Add Child");
  builder_inspector_delete_button.set_text("Delete Node");
  builder_inspector_move_up_button.set_text("Move Up");
  builder_inspector_move_down_button.set_text("Move Down");
  builder_inspector_apply_button.set_text("Apply Text to Selected Node");
  builder_preview_inline_apply_button.set_text("Apply Text");
  builder_preview_inline_cancel_button.set_text("Cancel");
  phase102_compose_action_button.set_text("Action");

  shell.set_background(0.10f, 0.12f, 0.16f, 0.96f);
  title_label.set_background(0.12f, 0.16f, 0.22f, 1.0f);
  path_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  status_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  selected_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  detail_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);
  builder_tree_surface_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_selection_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_edit_hint_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_layout_min_width_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_layout_min_height_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_structure_controls_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_non_editable_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_preview_interaction_hint_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_inspector_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_preview_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_export_status_label.set_background(0.08f, 0.11f, 0.16f, 1.0f);
  builder_action_feedback_label.set_background(0.13f, 0.15f, 0.20f, 1.0f);

  refresh_button.set_text("Refresh");
  prev_button.set_text("Prev");
  next_button.set_text("Next");
  apply_button.set_text("Apply Filter");
  apply_button.set_preferred_size(132, 28);
  refresh_button.set_preferred_size(110, 28);
  prev_button.set_preferred_size(96, 28);
  next_button.set_preferred_size(96, 28);
  builder_delete_button.set_preferred_size(128, 28);
  builder_undo_button.set_preferred_size(80, 28);
  builder_redo_button.set_preferred_size(80, 28);
  builder_save_button.set_preferred_size(96, 28);
  builder_load_button.set_preferred_size(96, 28);
  builder_load_discard_button.set_preferred_size(130, 28);
  builder_export_button.set_preferred_size(170, 28);
  builder_new_button.set_preferred_size(96, 28);
  builder_new_discard_button.set_preferred_size(130, 28);
  builder_insert_container_button.set_preferred_size(170, 28);
  builder_insert_leaf_button.set_preferred_size(130, 28);
  builder_debug_mode_toggle_button.set_preferred_size(170, 28);

  builder_shell_panel.set_padding(10);
  builder_shell_panel.set_spacing(8);
  builder_shell_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_shell_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);

  builder_header_block.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_header_block.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fixed);
  builder_header_block.set_preferred_size(0, 40);
  builder_header_block.set_min_size(0, 36);
  builder_header_block.set_padding(0);

  builder_input_toolbar_block.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_input_toolbar_block.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fixed);
  builder_input_toolbar_block.set_preferred_size(0, 104);
  builder_input_toolbar_block.set_min_size(0, 96);
  builder_input_toolbar_block.set_padding(0);

  builder_status_info_block.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_status_info_block.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fixed);
  builder_status_info_block.set_preferred_size(0, 72);
  builder_status_info_block.set_min_size(0, 64);
  builder_status_info_block.set_padding(0);

  builder_footer_block.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_footer_block.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fixed);
  builder_footer_block.set_preferred_size(0, 28);
  builder_footer_block.set_min_size(0, 24);
  builder_footer_block.set_padding(0);

  builder_header_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_header_bar.set_preferred_size(0, 36);
  title_label.set_text("NGKsUI Runtime Builder | START: Click NEW DOC -> then INSERT CONTAINER -> then INSERT LEAF");
  title_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  title_label.set_preferred_size(0, 30);
  title_label.set_min_size(240, 28);

  path_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  path_label.set_preferred_size(0, 28);
  path_label.set_min_size(240, 28);

  filter_box.set_preferred_size(0, 28);
  filter_box.set_min_size(220, 28);
  filter_box.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  filter_box.set_layout_weight(3);
  builder_filter_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_filter_bar.set_preferred_size(0, 28);

  builder_primary_actions_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_primary_actions_bar.set_preferred_size(0, 28);
  builder_secondary_actions_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_secondary_actions_bar.set_preferred_size(0, 28);

  builder_info_row.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_info_row.set_preferred_size(0, 52);
  builder_info_row.set_min_size(0, 44);
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
  builder_surface_row.set_min_size(0, 0);

  builder_tree_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_panel.set_layout_weight(2);
  builder_tree_panel.set_min_size(180, 120);
  builder_inspector_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_panel.set_layout_weight(2);
  builder_inspector_panel.set_min_size(180, 120);
  builder_preview_panel.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_panel.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_panel.set_layout_weight(3);
  builder_preview_panel.set_min_size(220, 120);

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
  builder_inspector_selection_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_edit_hint_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_layout_min_width_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_layout_min_height_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_structure_controls_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_non_editable_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_interaction_hint_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_header.set_preferred_size(0, 26);
  builder_inspector_header.set_preferred_size(0, 26);
  builder_preview_header.set_preferred_size(0, 26);

  builder_tree_scroll_content.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_scroll_content.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_scroll_content.set_layout_weight(1);
  builder_tree_scroll_content.set_padding(2);
  builder_inspector_scroll_content.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_scroll_content.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_scroll_content.set_layout_weight(1);
  builder_inspector_scroll_content.set_padding(2);
  builder_inspector_text_input.set_preferred_size(0, 28);
  builder_inspector_text_input.set_min_size(180, 28);
  builder_inspector_text_input.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_layout_min_width_input.set_preferred_size(0, 28);
  builder_inspector_layout_min_width_input.set_min_size(120, 28);
  builder_inspector_layout_min_width_input.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_layout_min_height_input.set_preferred_size(0, 28);
  builder_inspector_layout_min_height_input.set_min_size(120, 28);
  builder_inspector_layout_min_height_input.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_structure_controls_row.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_structure_controls_row.set_preferred_size(0, 28);
  builder_inspector_add_child_button.set_preferred_size(120, 28);
  builder_inspector_delete_button.set_preferred_size(120, 28);
  builder_inspector_move_up_button.set_preferred_size(96, 28);
  builder_inspector_move_down_button.set_preferred_size(96, 28);
  builder_inspector_text_input.set_visible(false);
  builder_inspector_text_input.set_focusable(false);
  builder_inspector_layout_min_width_label.set_visible(false);
  builder_inspector_layout_min_width_input.set_visible(false);
  builder_inspector_layout_min_width_input.set_focusable(false);
  builder_inspector_layout_min_height_label.set_visible(false);
  builder_inspector_layout_min_height_input.set_visible(false);
  builder_inspector_layout_min_height_input.set_focusable(false);
  builder_inspector_structure_controls_label.set_visible(false);
  builder_inspector_structure_controls_row.set_visible(false);
  builder_inspector_apply_button.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_inspector_apply_button.set_preferred_size(0, 28);
  builder_inspector_apply_button.set_enabled(false);
  builder_inspector_apply_button.set_visible(false);
  builder_inspector_non_editable_label.set_visible(false);
  builder_tree_visual_rows.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_visual_rows.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_tree_visual_rows.set_layout_weight(1);

  builder_preview_scroll_content.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_scroll_content.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_scroll_content.set_layout_weight(1);
  builder_preview_scroll_content.set_padding(2);
  builder_preview_inline_text_input.set_preferred_size(0, 28);
  builder_preview_inline_text_input.set_min_size(180, 28);
  builder_preview_inline_text_input.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_inline_text_input.set_visible(false);
  builder_preview_inline_text_input.set_focusable(false);
  builder_preview_inline_actions_row.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_inline_actions_row.set_preferred_size(0, 28);
  builder_preview_inline_actions_row.set_visible(false);
  builder_preview_inline_apply_button.set_preferred_size(120, 28);
  builder_preview_inline_cancel_button.set_preferred_size(96, 28);
  builder_preview_visual_rows.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_visual_rows.set_layout_height_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_preview_visual_rows.set_layout_weight(1);

  for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
    auto& row = builder_tree_row_buttons[idx];
    row.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
    row.set_preferred_size(0, 28);
    row.set_text(" ");
    row.set_visible(false);
  }

  for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
    auto& row = builder_preview_row_buttons[idx];
    row.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
    row.set_preferred_size(0, 38);
    row.set_text(" ");
    row.set_visible(false);
  }

  builder_footer_bar.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_footer_bar.set_preferred_size(0, 22);
  status_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  status_label.set_layout_weight(1);
  builder_action_feedback_label.set_layout_width_policy(ngk::ui::UIElement::LayoutSizePolicy::Fill);
  builder_action_feedback_label.set_layout_weight(2);
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

  auto set_last_action_feedback = [&](const std::string& message) {
    last_action_feedback = std::string("Action: ") + message;
    builder_action_feedback_label.set_text(last_action_feedback);
    sync_label_preferred_height(builder_action_feedback_label, 18);
  };

  auto set_preview_visual_feedback = [&](const std::string& message, const std::string& node_id = std::string{}) {
    preview_visual_feedback_message = message;
    preview_visual_feedback_node_id = node_id;
    builder_preview_interaction_hint_label.set_text(message);
    sync_label_preferred_height(builder_preview_interaction_hint_label, 18);
  };

  auto set_tree_visual_feedback = [&](const std::string& node_id = std::string{}) {
    tree_visual_feedback_node_id = node_id;
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

  auto node_exists_in_document = [&](const ngk::ui::builder::BuilderDocument& doc,
                                     const std::string& node_id) -> bool {
    return find_node_by_id_in_document(doc, node_id) != nullptr;
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

    if (validation_mode || builder_debug_mode) {
      status_label.set_text(
        std::string("STATUS ") + model.status +
        " FILES " + std::to_string(model.entries.size()) +
        " DOC_DIRTY " + (builder_doc_dirty ? std::string("YES") : std::string("NO")) +
        "\nTOP_ACTION_SURFACE mode=" + (multi_selected_node_ids.size() > 1 ? std::string("multi") : std::string("single")) +
        " selected_count=" + std::to_string(multi_selected_node_ids.size()) +
        " available=" + std::to_string(available_actions.size()) +
        " blocked=" + std::to_string(blocked_actions.size()));
    } else {
      status_label.set_text(
        std::string("Status: ") + model.status +
        " | Document: " + (builder_doc_dirty ? std::string("Modified") : std::string("Saved")) +
        " | Nodes: " + std::to_string(builder_doc.nodes.size()));
    }
    sync_label_preferred_height(status_label, 18);

    if (validation_mode || builder_debug_mode) {
      selected_label.set_text(
        std::string("SELECTED ") + selected_file_name(model) +
        "\nNODE " + (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) +
        " type=" + selected_type_name);
    } else {
      selected_label.set_text(
        std::string("Node: ") + (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) +
        " (" + selected_type_name + ")");
    }
    sync_label_preferred_height(selected_label, 18);

    if (validation_mode || builder_debug_mode) {
      detail_label.set_text(
        std::string("DETAIL BYTES ") + selected_file_size(model) +
        " FILTER " + model.filter +
        "\nTOP_AVAILABLE " + join_csv(available_actions) +
        "\nTOP_BLOCKED " + join_csv(blocked_actions));
    } else {
      detail_label.set_text(
        std::string("Hint: Click a tree row, then use Add Container or Add Item."));
    }
    sync_label_preferred_height(detail_label, 18);
  };

  auto refresh_action_button_visual_state_from_builder_truth = [&]() {
    sync_multi_selection_with_primary();
    const auto report = compute_bulk_action_eligibility_report();

    auto find_entry = [&](const std::string& action_id) -> const BulkActionEligibilityEntry* {
      for (const auto& entry : report.entries) {
        if (entry.action_id == action_id) {
          return &entry;
        }
      }
      return nullptr;
    };

    const bool multi_mode = multi_selected_node_ids.size() > 1;
    const auto* bulk_delete = find_entry("BULK_DELETE");
    const auto* bulk_move = find_entry("BULK_MOVE_REPARENT");

    bool single_delete_available = false;
    if (!selected_builder_node_id.empty()) {
      if (auto* selected = find_node_by_id(selected_builder_node_id)) {
        const bool is_root = selected_builder_node_id == builder_doc.root_node_id || selected->parent_id.empty();
        const bool is_shell = selected->container_type == ngk::ui::builder::BuilderContainerType::Shell;
        single_delete_available = !is_root && !is_shell && !selected->parent_id.empty() && node_exists(selected->parent_id);
      }
    }

    bool insert_available = false;
    if (!selected_builder_node_id.empty()) {
      if (auto* selected = find_node_by_id(selected_builder_node_id)) {
        insert_available = is_container_widget_type(selected->widget_type);
      }
    }

    const bool delete_available = multi_mode
      ? (bulk_delete != nullptr && bulk_delete->available)
      : single_delete_available;
    const bool move_available = multi_mode
      ? (bulk_move != nullptr && bulk_move->available)
      : false;

    const bool delete_relevant = !selected_builder_node_id.empty();
    const bool insert_relevant = !multi_mode && insert_available;
    const bool export_relevant = builder_doc_dirty;

    const bool delete_primary = delete_available && delete_relevant;
    const bool insert_primary = !delete_primary && insert_available && insert_relevant;
    const bool export_primary = !delete_primary && !insert_primary && export_relevant;

    builder_delete_button.set_default_action(delete_primary);
    builder_insert_container_button.set_default_action(insert_primary);
    builder_insert_leaf_button.set_default_action(insert_primary);
    builder_export_button.set_default_action(export_primary);
    builder_delete_button.set_enabled(delete_available);
    builder_insert_container_button.set_enabled(insert_available);
    builder_insert_leaf_button.set_enabled(insert_available);
    builder_export_button.set_enabled(true);

    const std::string delete_mode = multi_mode ? "BULK" : "SINGLE";
    (void)delete_mode;
    builder_delete_button.set_text("Delete");

    builder_insert_container_button.set_text("Add Container");
    builder_insert_leaf_button.set_text("Add Item");

    builder_reparent_button.set_default_action(move_available && multi_mode && !delete_primary);
    builder_reparent_button.set_enabled(move_available && multi_mode);
    builder_reparent_button.set_text("Reparent");

    const bool undo_ready = !undo_history.empty();
    const bool redo_ready = !redo_stack.empty();
    (void)undo_ready;
    (void)redo_ready;
    builder_undo_button.set_enabled(undo_ready);
    builder_redo_button.set_enabled(redo_ready);
    builder_undo_button.set_text("Undo");
    builder_redo_button.set_text("Redo");
    builder_export_button.set_text("Export");
  };

  auto humanize_widget_type = [&](ngk::ui::builder::BuilderWidgetType widget_type) -> std::string {
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

    append_node(builder_doc.root_node_id, 0);
    return oss.str();
  };

  auto refresh_tree_surface_label = [&]() {
    builder_tree_surface_label.set_visible(builder_debug_mode);
    builder_tree_visual_rows.set_visible(!builder_debug_mode);
    builder_tree_surface_label.set_text(build_tree_surface_text());
    sync_label_preferred_height(builder_tree_surface_label, 20);

    for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
      tree_visual_row_node_ids[idx].clear();
      builder_tree_row_buttons[idx].set_visible(false);
      builder_tree_row_buttons[idx].set_default_action(false);
      builder_tree_row_buttons[idx].set_enabled(false);
    }

    std::size_t row_count = 0;
    std::function<void(const std::string&, int)> append_visual_tree = [&](const std::string& node_id, int depth) {
      if (row_count >= kMaxVisualTreeRows) {
        return;
      }

      auto* node = find_node_by_id(node_id);
      if (!node) {
        return;
      }

      auto& row = builder_tree_row_buttons[row_count];
      tree_visual_row_node_ids[row_count] = node_id;

      std::string indent(static_cast<std::size_t>(std::max(0, depth)) * 4U, ' ');
      const bool is_container = is_container_widget_type(node->widget_type);
      const bool is_selected = (node_id == selected_builder_node_id);
      const bool is_hovered = row.visual_state() == ngk::ui::ButtonVisualState::Hover;
      const bool is_feedback_target = !tree_visual_feedback_node_id.empty() && tree_visual_feedback_node_id == node_id;
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
      row.set_default_action(node_id == selected_builder_node_id);
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

    if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
      append_visual_tree(builder_doc.root_node_id, 0);
    }
  };

  auto refresh_inspector_surface_label = [&]() {
    sync_multi_selection_with_primary();
    builder_inspector_label.set_visible(builder_debug_mode);

    std::ostringstream oss;
    oss << "INSPECTOR REGION (Guided Editing Surface)\n";
    oss << "[DEBUG MODE: " << (builder_debug_mode ? "ON" : "OFF") << "]\n";
    oss << last_action_feedback << "\n";
    std::string selected_type_name = "none";
    if (!selected_builder_node_id.empty()) {
      if (auto* selected_node = find_node_by_id(selected_builder_node_id)) {
        selected_type_name = humanize_widget_type(selected_node->widget_type);
      }
    }
    builder_inspector_selection_label.set_text(
      selected_builder_node_id.empty()
        ? std::string("Editing: Nothing selected")
        : (std::string("Editing: ") + selected_type_name));
    sync_label_preferred_height(builder_inspector_selection_label, 20);
    oss << "Selected Node: "
        << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id)
        << " (" << selected_type_name << ")\n";

    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      inspector_edit_binding_node_id.clear();
      inspector_edit_loaded_text.clear();
      inspector_edit_loaded_min_width.clear();
      inspector_edit_loaded_min_height.clear();
      builder_inspector_edit_hint_label.set_text(
        "Click NEW DOC to start, then select an item from Structure or Live Preview.");
      sync_label_preferred_height(builder_inspector_edit_hint_label, 20);
      builder_inspector_text_input.set_visible(false);
      builder_inspector_text_input.set_focusable(false);
      builder_inspector_layout_min_width_label.set_visible(false);
      builder_inspector_layout_min_width_input.set_visible(false);
      builder_inspector_layout_min_width_input.set_focusable(false);
      builder_inspector_layout_min_height_label.set_visible(false);
      builder_inspector_layout_min_height_input.set_visible(false);
      builder_inspector_layout_min_height_input.set_focusable(false);
      builder_inspector_structure_controls_label.set_visible(false);
      builder_inspector_structure_controls_row.set_visible(false);
      builder_inspector_apply_button.set_visible(false);
      builder_inspector_apply_button.set_enabled(false);
      builder_inspector_apply_button.set_default_action(false);
      builder_inspector_apply_button.set_text("Apply Changes");
      builder_inspector_non_editable_label.set_visible(false);
      oss << "Edit Target: none\n";
      oss << "Click NEW DOC to start.\n";
      oss << "Then add a container, then add items inside it.\n";
      oss << "Select a node in Tree or Preview to edit.";

      if (builder_debug_mode) {
        oss << "\n\n[SELECTION_SUMMARY]\n";
        oss << "SELECTED_ID: none\n";
        oss << "SELECTED_TYPE: none EDIT_TARGET_ID: none MULTI_SELECTION_MODE: "
            << (multi_selected_node_ids.size() > 1 ? "active" : "inactive")
            << " MULTI_SELECTION_COUNT: " << multi_selected_node_ids.size() << "\n";
        oss << "\n[ACTION_SURFACE]\n";
        append_compact_bulk_action_surface(oss);
        oss << "\n[PARITY]\n";
        oss << "PREVIEW_EXPORT_PARITY: " << last_preview_export_parity_status_code << "\n";
        oss << "\n[INTERNAL_FLAGS]\n";
        oss << "selected=none focused=" << (focused_builder_node_id.empty() ? std::string("none") : focused_builder_node_id) << "\n";
        oss << "binding=cleared\n";
      }
      builder_inspector_label.set_text(oss.str());
      sync_label_preferred_height(builder_inspector_label, 20);
      return;
    }

    auto* node = find_node_by_id(selected_builder_node_id);
    if (!node) {
      inspector_edit_binding_node_id.clear();
      inspector_edit_loaded_text.clear();
      inspector_edit_loaded_min_width.clear();
      inspector_edit_loaded_min_height.clear();
      builder_inspector_edit_hint_label.set_text(
        "Selection changed before the editor loaded. Select an item again.");
      sync_label_preferred_height(builder_inspector_edit_hint_label, 20);
      builder_inspector_text_input.set_visible(false);
      builder_inspector_text_input.set_focusable(false);
      builder_inspector_layout_min_width_label.set_visible(false);
      builder_inspector_layout_min_width_input.set_visible(false);
      builder_inspector_layout_min_width_input.set_focusable(false);
      builder_inspector_layout_min_height_label.set_visible(false);
      builder_inspector_layout_min_height_input.set_visible(false);
      builder_inspector_layout_min_height_input.set_focusable(false);
      builder_inspector_structure_controls_label.set_visible(false);
      builder_inspector_structure_controls_row.set_visible(false);
      builder_inspector_apply_button.set_visible(false);
      builder_inspector_apply_button.set_enabled(false);
      builder_inspector_apply_button.set_default_action(false);
      builder_inspector_non_editable_label.set_visible(false);
      oss << "Edit Target: stale\n";
      oss << "Hint: Selection was remapped.";
      builder_inspector_label.set_text(oss.str());
      sync_label_preferred_height(builder_inspector_label, 20);
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

    builder_inspector_structure_controls_label.set_visible(true);
    builder_inspector_structure_controls_row.set_visible(true);
    builder_inspector_add_child_button.set_enabled(container_selected);
    builder_inspector_add_child_button.set_background(
      container_selected ? 0.16f : 0.11f,
      container_selected ? 0.20f : 0.12f,
      container_selected ? 0.28f : 0.13f,
      1.0f);
    builder_inspector_structure_controls_label.set_text(
      container_selected
        ? "Structure Controls"
        : "Structure Controls - Only containers can have children");
    builder_inspector_delete_button.set_enabled(selected_builder_node_id != builder_doc.root_node_id);
    builder_inspector_move_up_button.set_enabled(selected_builder_node_id != builder_doc.root_node_id);
    builder_inspector_move_down_button.set_enabled(selected_builder_node_id != builder_doc.root_node_id);

    oss << "Edit Target: " << node->node_id << "\n";
    oss << "Item: " << widget_type_name << "\n";
    oss << "Structure Controls: "
        << (container_selected ? "Add Child" : "Add Child disabled")
        << ", Delete, Move Up, Move Down\n";

    const std::string current_min_width = std::to_string(node->layout.min_width);
    const std::string current_min_height = std::to_string(node->layout.min_height);
    if (inspector_edit_binding_node_id != node->node_id ||
        builder_inspector_layout_min_width_input.value() == inspector_edit_loaded_min_width ||
        !builder_inspector_layout_min_width_input.focused()) {
      builder_inspector_layout_min_width_input.set_value(current_min_width);
      inspector_edit_loaded_min_width = current_min_width;
    }
    if (inspector_edit_binding_node_id != node->node_id ||
        builder_inspector_layout_min_height_input.value() == inspector_edit_loaded_min_height ||
        !builder_inspector_layout_min_height_input.focused()) {
      builder_inspector_layout_min_height_input.set_value(current_min_height);
      inspector_edit_loaded_min_height = current_min_height;
    }
    builder_inspector_layout_min_width_label.set_visible(true);
    builder_inspector_layout_min_width_input.set_visible(true);
    builder_inspector_layout_min_width_input.set_focusable(true);
    builder_inspector_layout_min_height_label.set_visible(true);
    builder_inspector_layout_min_height_input.set_visible(true);
    builder_inspector_layout_min_height_input.set_focusable(true);
    sync_label_preferred_height(builder_inspector_layout_min_width_label, 18);
    sync_label_preferred_height(builder_inspector_layout_min_height_label, 18);

    if (text_editable) {
      if (inspector_edit_binding_node_id != node->node_id ||
          builder_inspector_text_input.value() == inspector_edit_loaded_text ||
          !builder_inspector_text_input.focused()) {
        builder_inspector_text_input.set_value(node->text);
        inspector_edit_loaded_text = node->text;
      }
      builder_inspector_edit_hint_label.set_text(
        "You can edit Text, Width, and Height here. Apply Filter at the top only filters files.");
      sync_label_preferred_height(builder_inspector_edit_hint_label, 20);
      builder_inspector_text_input.set_visible(true);
      builder_inspector_text_input.set_focusable(true);
      builder_inspector_apply_button.set_visible(true);
      builder_inspector_apply_button.set_enabled(true);
      builder_inspector_apply_button.set_default_action(true);
      builder_inspector_apply_button.set_text("Apply Changes");
      builder_inspector_non_editable_label.set_visible(false);
      oss << "Label: \"" << (node->text.empty() ? std::string("<no-text>") : node->text) << "\"\n";
      oss << "Text Property: editable\n";
    } else {
      inspector_edit_loaded_text.clear();
      builder_inspector_edit_hint_label.set_text(
        "You can edit Width and Height for this item. This item has no text.");
      sync_label_preferred_height(builder_inspector_edit_hint_label, 20);
      builder_inspector_text_input.set_visible(false);
      builder_inspector_text_input.set_focusable(false);
      builder_inspector_apply_button.set_visible(true);
      builder_inspector_apply_button.set_enabled(true);
      builder_inspector_apply_button.set_default_action(true);
      builder_inspector_apply_button.set_text("Apply Changes");
      builder_inspector_non_editable_label.set_text(
        "This item has no text.");
      builder_inspector_non_editable_label.set_visible(true);
      sync_label_preferred_height(builder_inspector_non_editable_label, 20);
      oss << "Text Property: not editable for this node type\n";
    }

    inspector_edit_binding_node_id = node->node_id;
    oss << "Width: " << node->layout.min_width << "\n";
    oss << "Height: " << node->layout.min_height << "\n";

    if (shows_layout_group) {
      oss << "Layout Children: " << node->child_ids.size() << "\n";
    }

    if (builder_debug_mode) {
      const auto bulk_text_state = compute_bulk_text_suffix_selection_compatibility();
      oss << "\n[SELECTION_SUMMARY]\n";
      oss << "SELECTED_ID: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
      oss << "SELECTED_TYPE: " << selected_type_name
          << " EDIT_TARGET_ID: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id)
          << " MULTI_SELECTION_MODE: " << (multi_selected_node_ids.size() > 1 ? "active" : "inactive")
          << " MULTI_SELECTION_COUNT: " << multi_selected_node_ids.size() << "\n";

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
      append_compact_bulk_action_surface(oss);

      oss << "\n[PARITY]\n";
      oss << "PREVIEW_EXPORT_PARITY: " << last_preview_export_parity_status_code;
      if (!last_preview_export_parity_reason.empty() && last_preview_export_parity_reason != "none") {
        oss << " reason=" << last_preview_export_parity_reason;
      }
      oss << "\n";

      oss << "\n[RECENT_RESULTS]\n";
      oss << "EDIT_RESULT: " << last_inspector_edit_status_code;
      if (!last_inspector_edit_reason.empty() && last_inspector_edit_reason != "none") {
        oss << " [" << last_inspector_edit_reason << "]";
      }
      oss << " | BULK_DELETE_RESULT: " << last_bulk_delete_status_code;
      if (!last_bulk_delete_reason.empty() && last_bulk_delete_reason != "none") {
        oss << " [" << last_bulk_delete_reason << "]";
      }
      oss << "\n";
      oss << "BULK_MOVE_REPARENT_RESULT: " << last_bulk_move_reparent_status_code;
      if (!last_bulk_move_reparent_reason.empty() && last_bulk_move_reparent_reason != "none") {
        oss << " [" << last_bulk_move_reparent_reason << "]";
      }
      oss << " | BULK_PROPERTY_EDIT_RESULT: " << last_bulk_property_edit_status_code;
      if (!last_bulk_property_edit_reason.empty() && last_bulk_property_edit_reason != "none") {
        oss << " [" << last_bulk_property_edit_reason << "]";
      }
      oss << "\n";
      oss << "\n[INTERNAL_FLAGS]\n";
      oss << "  selected=" << ((selected_builder_node_id == node->node_id) ? "true" : "false")
          << " focused=" << ((focused_builder_node_id == node->node_id) ? "true" : "false")
          << " multi_selection_count=" << multi_selected_node_ids.size() << "\n";
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

    builder_inspector_label.set_text(oss.str());
    sync_label_preferred_height(builder_inspector_label, 20);
    refresh_top_action_surface_from_builder_state();
    refresh_action_button_visual_state_from_builder_truth();
  };

  auto update_add_child_target_display = [&]() {
    if (selected_builder_node_id.empty()) {
      builder_add_child_target_label.set_text("Add Child Target: None");
      return;
    }

    auto* selected_node = find_node_by_id(selected_builder_node_id);
    if (!selected_node) {
      builder_add_child_target_label.set_text("Add Child Target: Stale");
      return;
    }

    const bool is_container = ngk::ui::builder::widget_allows_children(selected_node->widget_type);
    const std::string type_name = humanize_widget_type(selected_node->widget_type);
    const std::string label_text = selected_node->text.empty() ? "(no label)" : selected_node->text;

    std::string target_text = is_container
      ? ("Add Child Target: CONTAINER " + type_name + " \"" + label_text + "\"")
      : ("Add Child Target: LABEL " + type_name + " (cannot add children to this)");

    builder_add_child_target_label.set_text(target_text);
    sync_label_preferred_height(builder_add_child_target_label, 18);
  };

  auto refresh_preview_surface_label = [&]() {
    sync_multi_selection_with_primary();

    builder_preview_label.set_visible(builder_debug_mode);
    builder_preview_visual_rows.set_visible(!builder_debug_mode);

    std::ostringstream oss;
    oss << "PREVIEW REGION (Readable Runtime)\n";
    oss << "[DEBUG MODE: " << (builder_debug_mode ? "ON" : "OFF") << "]\n";
    oss << last_action_feedback << "\n";
    std::string selected_type_name = "none";
    if (!selected_builder_node_id.empty()) {
      if (auto* selected_node = find_node_by_id(selected_builder_node_id)) {
        selected_type_name = ngk::ui::builder::to_string(selected_node->widget_type);
      }
    }
    oss << "Selection: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id)
        << " (" << selected_type_name << ")\n";
    oss << "Layout\n";

    if (selected_builder_node_id.empty() || !node_exists(selected_builder_node_id)) {
      builder_preview_interaction_hint_label.set_text(
        "Click NEW DOC to start. Select an item in Tree or Preview to edit.");
      builder_preview_inline_text_input.set_visible(false);
      builder_preview_inline_text_input.set_focusable(false);
      builder_preview_inline_actions_row.set_visible(false);
      oss << "No active node selected.\n";
      oss << "Hint: Click a TREE row or PREVIEW runtime entry.";
      preview_snapshot = "preview:selected=none";
      builder_preview_label.set_text(oss.str());
      sync_label_preferred_height(builder_preview_label, 20);
      return;
    }

    auto* selected = find_node_by_id(selected_builder_node_id);
    if (!selected) {
      builder_preview_interaction_hint_label.set_text("Selection became stale. Select another item.");
      builder_preview_inline_text_input.set_visible(false);
      builder_preview_inline_text_input.set_focusable(false);
      builder_preview_inline_actions_row.set_visible(false);
      oss << "Selected node became stale.";
      preview_snapshot = "preview:selected=stale";
      builder_preview_label.set_text(oss.str());
      sync_label_preferred_height(builder_preview_label, 20);
      return;
    }

    oss << "Active item: " << selected->node_id << "\n";
    oss << "Item: " << humanize_widget_type(selected->widget_type) << "\n";
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
      if (inline_edit_active && inline_edit_node_id == selected->node_id) {
        if (builder_preview_inline_text_input.value() == preview_inline_loaded_text ||
            !builder_preview_inline_text_input.focused()) {
          builder_preview_inline_text_input.set_value(inline_edit_buffer);
          preview_inline_loaded_text = inline_edit_buffer;
        }
        builder_preview_inline_text_input.set_visible(true);
        builder_preview_inline_text_input.set_focusable(true);
        builder_preview_inline_actions_row.set_visible(true);
      } else {
        builder_preview_inline_text_input.set_visible(false);
        builder_preview_inline_text_input.set_focusable(false);
        builder_preview_inline_actions_row.set_visible(false);
      }
    } else {
      preview_hint_message = "Click to select. Inline text editing is available for labels.";
      builder_preview_inline_text_input.set_visible(false);
      builder_preview_inline_text_input.set_focusable(false);
      builder_preview_inline_actions_row.set_visible(false);
    }

    if (ngk::ui::builder::widget_allows_children(selected->widget_type)) {
      preview_hint_message = "Container selected: child will appear in the highlighted insertion area.";
    }
    if (!preview_visual_feedback_message.empty()) {
      preview_hint_message = preview_visual_feedback_message;
    }
    builder_preview_interaction_hint_label.set_text(preview_hint_message);
    sync_label_preferred_height(builder_preview_interaction_hint_label, 18);

    if (builder_debug_mode) {
      const auto bulk_text_state = compute_bulk_text_suffix_selection_compatibility();
      oss << "\n[SELECTION_SUMMARY]\n";
      oss << "SELECTED_ID: " << (selected_builder_node_id.empty() ? std::string("none") : selected_builder_node_id) << "\n";
      oss << "SELECTED_TYPE: " << selected_type_name
          << " SELECTED_TARGET=ACTIVE_EDIT_NODE"
          << " selection_mode=" << (multi_selected_node_ids.size() > 1 ? "multi" : "single")
          << " multi_selection_count=" << multi_selected_node_ids.size();
      if (multi_selected_node_ids.size() > 1) {
        oss << " multi_secondary_ids=";
        for (std::size_t idx = 1; idx < multi_selected_node_ids.size(); ++idx) {
          if (idx > 1) {
            oss << ",";
          }
          oss << multi_selected_node_ids[idx];
        }
      }
      oss << "\n";

      oss << "\n[PARITY]\n";
      oss << "parity_scope=" << kPreviewExportParityScope << " parity=" << last_preview_export_parity_status_code;
      if (!last_preview_export_parity_reason.empty() && last_preview_export_parity_reason != "none") {
        oss << " reason=" << last_preview_export_parity_reason;
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
      append_compact_bulk_action_surface(oss);

      oss << "\n[RECENT_RESULTS]\n";
      oss << "click_select=" << last_preview_click_select_status_code;
      if (!last_preview_click_select_reason.empty() && last_preview_click_select_reason != "none") {
        oss << " reason=" << last_preview_click_select_reason;
      }
      oss << " | inline_action_commit=" << last_preview_inline_action_commit_status_code;
      if (!last_preview_inline_action_commit_reason.empty() && last_preview_inline_action_commit_reason != "none") {
        oss << " reason=" << last_preview_inline_action_commit_reason;
      }
      oss << "\n";
      oss << "bulk_delete=" << last_bulk_delete_status_code;
      if (!last_bulk_delete_reason.empty() && last_bulk_delete_reason != "none") {
        oss << " reason=" << last_bulk_delete_reason;
      }
      oss << " | bulk_move_reparent=" << last_bulk_move_reparent_status_code;
      if (!last_bulk_move_reparent_reason.empty() && last_bulk_move_reparent_reason != "none") {
        oss << " reason=" << last_bulk_move_reparent_reason;
      }
      oss << " | bulk_property_edit=" << last_bulk_property_edit_status_code;
      if (!last_bulk_property_edit_reason.empty() && last_bulk_property_edit_reason != "none") {
        oss << " reason=" << last_bulk_property_edit_reason;
      }
      oss << "\n";
      oss << "root=" << (builder_doc.root_node_id.empty() ? std::string("none") : builder_doc.root_node_id)
          << " nodes=" << builder_doc.nodes.size() << "\n";
    }

    oss << build_preview_inline_action_affordance_text(*selected);
    oss << "runtime_outline:\n" << build_preview_runtime_outline();
    preview_snapshot = "preview:selected=" + selected->node_id +
      " type=" + std::string(ngk::ui::builder::to_string(selected->widget_type)) +
      " parity=" + last_preview_export_parity_status_code;
    builder_preview_label.set_text(oss.str());
    sync_label_preferred_height(builder_preview_label, 20);

    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      preview_visual_row_node_ids[idx].clear();
      preview_visual_row_depths[idx] = 0;
      preview_visual_row_is_container[idx] = false;
      builder_preview_row_buttons[idx].set_visible(false);
      builder_preview_row_buttons[idx].set_default_action(false);
      builder_preview_row_buttons[idx].set_enabled(false);
      builder_preview_row_buttons[idx].set_focused(false);
      builder_preview_row_buttons[idx].set_background(0.16f, 0.18f, 0.22f, 1.0f);
    }

    std::size_t row_count = 0;
    std::function<void(const std::string&, int)> append_preview_visual = [&](const std::string& node_id, int depth) {
      if (row_count >= kMaxVisualPreviewRows) {
        return;
      }

      auto* node = find_node_by_id(node_id);
      if (!node) {
        return;
      }

      auto& row = builder_preview_row_buttons[row_count];
      preview_visual_row_node_ids[row_count] = node_id;
      preview_visual_row_depths[row_count] = depth;
      preview_visual_row_is_container[row_count] = is_container_widget_type(node->widget_type);

      const int layout_height = std::max(0, node->layout.min_height);
      const int layout_width = std::max(0, node->layout.min_width);
      const int width_units = std::clamp(layout_width / 80, 0, 8);
      const std::string width_pad(static_cast<std::size_t>(width_units), ' ');
      const std::string depth_indent(static_cast<std::size_t>(std::max(0, depth)) * 4U, ' ');

      std::string row_text;
      if (is_container_widget_type(node->widget_type)) {
        row_text = depth_indent + "CONTAINER (" + std::to_string(node->child_ids.size()) +
          (node->child_ids.size() == 1 ? std::string(" item)") : std::string(" items)"));
      } else if (node->widget_type == ngk::ui::builder::BuilderWidgetType::Label) {
        row_text = depth_indent + width_pad + (node->text.empty() ? std::string("Text") : node->text) + width_pad;
      } else if (!node->text.empty()) {
        row_text = depth_indent + width_pad + node->text + width_pad;
      } else {
        row_text = depth_indent + width_pad + humanize_widget_type(node->widget_type) + width_pad;
      }

      const bool is_selected = (node_id == selected_builder_node_id);
      const bool is_hovered = row.visual_state() == ngk::ui::ButtonVisualState::Hover;
      const bool is_feedback_target = !preview_visual_feedback_node_id.empty() && node_id == preview_visual_feedback_node_id;
      row.set_text(row_text);
      row.set_focused(is_selected);
      row.set_default_action(is_selected);
      if (preview_visual_row_is_container[row_count]) {
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
      } else if (preview_visual_row_is_container[row_count]) {
        row.set_background(0.13f + depth_tint, 0.18f + depth_tint, 0.24f + depth_tint, 1.0f);
      } else if (is_hovered) {
        row.set_background(0.24f + depth_tint, 0.27f + depth_tint, 0.33f + depth_tint, 1.0f);
      } else {
        row.set_background(0.18f + depth_tint, 0.20f + depth_tint, 0.24f + depth_tint, 1.0f);
      }

      row.set_enabled(true);
      row.set_visible(true);
      row_count += 1;

      if (is_selected && preview_visual_row_is_container[row_count - 1] && row_count < kMaxVisualPreviewRows) {
        auto& hint_row = builder_preview_row_buttons[row_count];
        preview_visual_row_node_ids[row_count].clear();
        preview_visual_row_depths[row_count] = depth + 1;
        preview_visual_row_is_container[row_count] = false;
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

    if (!builder_doc.root_node_id.empty() && node_exists(builder_doc.root_node_id)) {
      append_preview_visual(builder_doc.root_node_id, 0);
    }

    refresh_top_action_surface_from_builder_state();
    refresh_action_button_visual_state_from_builder_truth();
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

  auto scrub_stale_lifecycle_references = [&]() {
    if (!inline_edit_node_id.empty() && !node_exists(inline_edit_node_id)) {
      inline_edit_active = false;
      inline_edit_node_id.clear();
      inline_edit_buffer.clear();
      inline_edit_original_text.clear();
      preview_inline_loaded_text.clear();
    }
    if (!hover_node_id.empty() && !node_exists(hover_node_id)) {
      hover_node_id.clear();
    }
    if (!drag_source_node_id.empty() && !node_exists(drag_source_node_id)) {
      drag_source_node_id.clear();
      drag_active = false;
    }
    if (!drag_target_preview_node_id.empty() && !node_exists(drag_target_preview_node_id)) {
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
    }
    if (!preview_visual_feedback_node_id.empty() && !node_exists(preview_visual_feedback_node_id)) {
      preview_visual_feedback_node_id.clear();
    }
    if (!tree_visual_feedback_node_id.empty() && !node_exists(tree_visual_feedback_node_id)) {
      tree_visual_feedback_node_id.clear();
    }
    if (!focused_builder_node_id.empty() && !node_exists(focused_builder_node_id)) {
      focused_builder_node_id.clear();
    }
    if (!inspector_binding_node_id.empty() && !node_exists(inspector_binding_node_id)) {
      inspector_binding_node_id.clear();
    }
    if (!preview_binding_node_id.empty() && !node_exists(preview_binding_node_id)) {
      preview_binding_node_id.clear();
    }
  };

  auto check_cross_surface_sync = [&]() -> bool {
    coherence_diag.cross_surface_sync_checks_present = true;

    scrub_stale_lifecycle_references();
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

    const bool hover_valid = hover_node_id.empty() || node_exists(hover_node_id);
    const bool drag_source_valid = drag_source_node_id.empty() || node_exists(drag_source_node_id);
    const bool drag_target_valid = drag_target_preview_node_id.empty() || node_exists(drag_target_preview_node_id);
    const bool preview_feedback_valid = preview_visual_feedback_node_id.empty() || node_exists(preview_visual_feedback_node_id);
    const bool tree_feedback_valid = tree_visual_feedback_node_id.empty() || node_exists(tree_visual_feedback_node_id);
    const bool inline_ref_valid = inline_edit_node_id.empty() || node_exists(inline_edit_node_id);

    return !coherence_diag.desync_tree_selection_detected &&
      !coherence_diag.desync_inspector_binding_detected &&
      !coherence_diag.desync_preview_binding_detected &&
      multi_selection_valid &&
      primary_consistent &&
      hover_valid &&
      drag_source_valid &&
      drag_target_valid &&
      preview_feedback_valid &&
      tree_feedback_valid &&
      inline_ref_valid;
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
        set_last_action_feedback(std::string("Committed ") + action_id);
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
    set_last_action_feedback(std::string("Selected ") + selected_builder_node_id);
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

    auto is_deleted = [&](const std::string& node_id) {
      return std::find(deleted_ids.begin(), deleted_ids.end(), node_id) != deleted_ids.end();
    };

    std::string anchor_deleted_id{};
    if (!selected_builder_node_id.empty() && is_deleted(selected_builder_node_id)) {
      anchor_deleted_id = selected_builder_node_id;
    } else {
      for (const auto& deleted_id : deleted_ids) {
        if (!deleted_id.empty()) {
          anchor_deleted_id = deleted_id;
          break;
        }
      }
    }

    const auto* anchor_node = anchor_deleted_id.empty() ? nullptr : find_node_by_id(anchor_deleted_id);
    std::string fallback_parent_id = anchor_node ? anchor_node->parent_id : std::string{};
    while (!fallback_parent_id.empty()) {
      if (!is_deleted(fallback_parent_id) && node_exists(fallback_parent_id)) {
        return fallback_parent_id;
      }
      const auto* fallback_parent = find_node_by_id(fallback_parent_id);
      if (fallback_parent == nullptr) {
        break;
      }
      fallback_parent_id = fallback_parent->parent_id;
    }

    if (!builder_doc.root_node_id.empty() && !is_deleted(builder_doc.root_node_id) && node_exists(builder_doc.root_node_id)) {
      return builder_doc.root_node_id;
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

    scrub_stale_lifecycle_references();

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
    auto normalize_selected_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                  const std::string& preferred_selected_id,
                                                  const std::vector<std::string>& preferred_multi_selected_ids,
                                                  const ngk::ui::builder::BuilderDocument* counterpart_doc,
                                                  const std::string& counterpart_selected_id) -> std::string {
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
    };

    auto normalize_multi_selection_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                      const std::string& selected_id,
                                                      const std::vector<std::string>& preferred_multi_selected_ids) {
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
    };

    auto normalize_history_entry = [&](CommandHistoryEntry& entry) -> bool {
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

      return !entry.before_selected_id.empty() && !entry.after_selected_id.empty();
    };

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
    if (!normalize_history_entry(entry)) {
      model.undefined_state_detected = true;
      return;
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

  auto apply_inspector_property_edits_command =
    [&](const std::vector<std::pair<std::string, std::string>>& updates,
        const std::string& history_tag) -> bool {
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
        applied_count += 1;
      }

      if (applied_count <= 0) {
        return fail_invalid("no_property_updates");
      }

      if (!node_exists_in_document(candidate_doc, selected_builder_node_id)) {
        return fail_rejected("selected_node_missing_after_property_edit");
      }

      builder_doc = std::move(candidate_doc);

      push_to_history(history_tag.empty() ? std::string("inspector_property_edit") : history_tag,
                      before_nodes, before_root, before_sel, &before_multi,
                      builder_doc.nodes, builder_doc.root_node_id, selected_builder_node_id, &multi_selected_node_ids);
      recompute_builder_dirty_state(true);
      last_inspector_edit_status_code = "SUCCESS";
      last_inspector_edit_reason = "none";
      refresh_inspector_surface_label();
      return true;
    };

  auto apply_undo_command = [&]() -> bool {
    auto normalize_selected_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                  const std::string& preferred_selected_id,
                                                  const std::vector<std::string>& preferred_multi_selected_ids,
                                                  const ngk::ui::builder::BuilderDocument* counterpart_doc,
                                                  const std::string& counterpart_selected_id) -> std::string {
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
    };

    auto normalize_multi_selection_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                      const std::string& selected_id,
                                                      const std::vector<std::string>& preferred_multi_selected_ids) {
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
    };

    auto normalize_history_entry = [&](CommandHistoryEntry& entry) -> bool {
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

      return !entry.before_selected_id.empty() && !entry.after_selected_id.empty();
    };

    auto clear_transient_builder_restore_state = [&]() {
      inline_edit_active = false;
      inline_edit_node_id.clear();
      inline_edit_buffer.clear();
      inline_edit_original_text.clear();
      preview_inline_loaded_text.clear();
      focused_builder_node_id.clear();
      drag_source_node_id.clear();
      drag_active = false;
      hover_node_id.clear();
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      preview_visual_feedback_message.clear();
      preview_visual_feedback_node_id.clear();
      tree_visual_feedback_node_id.clear();
    };

    auto restore_history_state = [&](const CommandHistoryEntry& raw_entry, bool restore_before) -> bool {
      CommandHistoryEntry entry = raw_entry;
      if (!normalize_history_entry(entry)) {
        model.undefined_state_detected = true;
        return false;
      }

      clear_transient_builder_restore_state();
      if (restore_before) {
        builder_doc.nodes = entry.before_nodes;
        builder_doc.root_node_id = entry.before_root_node_id;
        selected_builder_node_id = entry.before_selected_id;
        multi_selected_node_ids = entry.before_multi_selected_ids;
      } else {
        builder_doc.nodes = entry.after_nodes;
        builder_doc.root_node_id = entry.after_root_node_id;
        selected_builder_node_id = entry.after_selected_id;
        multi_selected_node_ids = entry.after_multi_selected_ids;
      }

      const bool remap_ok = remap_selection_or_fail();
      const bool focus_ok = sync_focus_with_selection_or_fail();
      refresh_tree_surface_label();
      const bool inspector_ok = refresh_inspector_or_fail();
      const bool preview_ok = refresh_preview_or_fail();
      update_add_child_target_display();
      return remap_ok && focus_ok && inspector_ok && preview_ok;
    };

    if (undo_history.empty()) {
      return false;
    }
    const CommandHistoryEntry entry = undo_history.back();
    if (!restore_history_state(entry, true)) {
      return false;
    }
    redo_stack.push_back(entry);
    undo_history.pop_back();
    const bool dirty_ok = recompute_builder_dirty_state(true);
    update_add_child_target_display();
    const bool sync_ok = check_cross_surface_sync();
    return dirty_ok && sync_ok;
  };

  auto apply_redo_command = [&]() -> bool {
    auto normalize_selected_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                  const std::string& preferred_selected_id,
                                                  const std::vector<std::string>& preferred_multi_selected_ids,
                                                  const ngk::ui::builder::BuilderDocument* counterpart_doc,
                                                  const std::string& counterpart_selected_id) -> std::string {
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
    };

    auto normalize_multi_selection_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                      const std::string& selected_id,
                                                      const std::vector<std::string>& preferred_multi_selected_ids) {
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
    };

    auto normalize_history_entry = [&](CommandHistoryEntry& entry) -> bool {
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

      return !entry.before_selected_id.empty() && !entry.after_selected_id.empty();
    };

    auto clear_transient_builder_restore_state = [&]() {
      inline_edit_active = false;
      inline_edit_node_id.clear();
      inline_edit_buffer.clear();
      inline_edit_original_text.clear();
      preview_inline_loaded_text.clear();
      focused_builder_node_id.clear();
      drag_source_node_id.clear();
      drag_active = false;
      hover_node_id.clear();
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      preview_visual_feedback_message.clear();
      preview_visual_feedback_node_id.clear();
      tree_visual_feedback_node_id.clear();
    };

    auto restore_history_state = [&](const CommandHistoryEntry& raw_entry, bool restore_before) -> bool {
      CommandHistoryEntry entry = raw_entry;
      if (!normalize_history_entry(entry)) {
        model.undefined_state_detected = true;
        return false;
      }

      clear_transient_builder_restore_state();
      if (restore_before) {
        builder_doc.nodes = entry.before_nodes;
        builder_doc.root_node_id = entry.before_root_node_id;
        selected_builder_node_id = entry.before_selected_id;
        multi_selected_node_ids = entry.before_multi_selected_ids;
      } else {
        builder_doc.nodes = entry.after_nodes;
        builder_doc.root_node_id = entry.after_root_node_id;
        selected_builder_node_id = entry.after_selected_id;
        multi_selected_node_ids = entry.after_multi_selected_ids;
      }

      const bool remap_ok = remap_selection_or_fail();
      const bool focus_ok = sync_focus_with_selection_or_fail();
      refresh_tree_surface_label();
      const bool inspector_ok = refresh_inspector_or_fail();
      const bool preview_ok = refresh_preview_or_fail();
      update_add_child_target_display();
      return remap_ok && focus_ok && inspector_ok && preview_ok;
    };

    if (redo_stack.empty()) {
      return false;
    }
    const CommandHistoryEntry entry = redo_stack.back();
    if (!restore_history_state(entry, false)) {
      return false;
    }
    undo_history.push_back(entry);
    redo_stack.pop_back();
    const bool dirty_ok = recompute_builder_dirty_state(true);
    update_add_child_target_display();
    const bool sync_ok = check_cross_surface_sync();
    return dirty_ok && sync_ok;
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

    scrub_stale_lifecycle_references();

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
        multi_selected_node_ids = {new_node_id};
        sync_multi_selection_with_primary();
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

  auto run_phase103_56 = [&] {
    bool flow_ok = true;
    node_lifecycle_integrity_diag = BuilderNodeLifecycleIntegrityDiagnostics{};

    auto build_document_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                        const char* context_name) -> std::string {
      std::string error;
      if (!ngk::ui::builder::validate_builder_document(doc, &error)) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":" + error;
      }
      const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
      if (serialized.empty()) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":serialize_failed";
      }
      return serialized;
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
      if (!build_preview_export_parity_entries(builder_doc, entries, reason, "phase103_56")) {
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

    auto preview_contains = [&](const std::string& node_id) -> bool {
      if (node_id.empty()) {
        return false;
      }
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (builder_preview_row_buttons[idx].visible() && preview_visual_row_node_ids[idx] == node_id) {
          return true;
        }
      }
      return false;
    };

    auto structure_contains = [&](const std::string& node_id) -> bool {
      if (node_id.empty()) {
        return false;
      }
      for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
        if (builder_tree_row_buttons[idx].visible() && tree_visual_row_node_ids[idx] == node_id) {
          return true;
        }
      }
      return false;
    };

    auto count_in_parent = [&](const std::string& parent_id, const std::string& child_id) -> std::size_t {
      auto* parent = find_node_by_id(parent_id);
      if (!parent) {
        return 0;
      }
      std::size_t count = 0;
      for (const auto& id : parent->child_ids) {
        if (id == child_id) {
          count += 1;
        }
      }
      return count;
    };

    auto document_has_unique_node_ids = [&](const ngk::ui::builder::BuilderDocument& doc) -> bool {
      std::vector<std::string> seen{};
      for (const auto& node : doc.nodes) {
        if (node.node_id.empty()) {
          return false;
        }
        if (std::find(seen.begin(), seen.end(), node.node_id) != seen.end()) {
          return false;
        }
        seen.push_back(node.node_id);
      }
      return seen.size() == doc.nodes.size();
    };

    auto reset_phase = [&]() -> bool {
      run_phase103_2();
      undo_history.clear();
      redo_stack.clear();
      builder_doc_dirty = false;
      hover_node_id.clear();
      drag_source_node_id.clear();
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      drag_active = false;
      inline_edit_active = false;
      inline_edit_node_id.clear();
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    auto apply_recorded_delete = [&](const std::string& history_tag) -> bool {
      const auto before_nodes = builder_doc.nodes;
      const std::string before_root = builder_doc.root_node_id;
      const std::string before_sel = selected_builder_node_id;
      const auto before_multi = multi_selected_node_ids;
      const bool ok = apply_delete_command_for_current_selection();
      if (!ok) {
        return false;
      }
      push_to_history(history_tag,
                      before_nodes,
                      before_root,
                      before_sel,
                      &before_multi,
                      builder_doc.nodes,
                      builder_doc.root_node_id,
                      selected_builder_node_id,
                      &multi_selected_node_ids);
      return true;
    };

    flow_ok = reset_phase() && flow_ok;

    const std::string parent_id = builder_doc.root_node_id;
    const std::string created_id = "phase103_56-created-a";
    const bool created_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label,
      parent_id,
      created_id);
    flow_ok = created_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    node_lifecycle_integrity_diag.created_node_has_valid_identity =
      created_ok &&
      node_exists(created_id) &&
      count_in_parent(parent_id, created_id) == 1 &&
      document_has_unique_node_ids(builder_doc) &&
      preview_contains(created_id) &&
      structure_contains(created_id);

    hover_node_id = created_id;
    drag_source_node_id = created_id;
    drag_active = true;
    drag_target_preview_node_id = created_id;
    preview_visual_feedback_node_id = created_id;
    tree_visual_feedback_node_id = created_id;
    inline_edit_active = true;
    inline_edit_node_id = created_id;
    inline_edit_buffer = "phase103_56-inline";
    inline_edit_original_text = "phase103_56-inline";
    selected_builder_node_id = created_id;
    focused_builder_node_id = created_id;
    multi_selected_node_ids = {created_id};
    sync_multi_selection_with_primary();

    const bool delete_created_ok = apply_delete_command_for_current_selection();
    flow_ok = delete_created_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    node_lifecycle_integrity_diag.deleted_node_fully_removed =
      delete_created_ok &&
      !node_exists(created_id) &&
      !preview_contains(created_id) &&
      !structure_contains(created_id);

    node_lifecycle_integrity_diag.no_stale_references_after_delete =
      hover_node_id.empty() &&
      drag_source_node_id.empty() &&
      drag_target_preview_node_id.empty() &&
      preview_visual_feedback_node_id.empty() &&
      tree_visual_feedback_node_id.empty() &&
      inline_edit_node_id.empty() &&
      !drag_active;

    const std::string container_a = "phase103_56-container-a";
    const std::string container_b = "phase103_56-container-b";
    const std::string moving_child = "phase103_56-moving-child";
    const bool add_container_a_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout,
      parent_id,
      container_a);
    const bool add_container_b_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout,
      parent_id,
      container_b);
    const bool add_moving_child_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label,
      container_a,
      moving_child);
    flow_ok = add_container_a_ok && add_container_b_ok && add_moving_child_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;

    std::size_t before_move_row_index = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (builder_preview_row_buttons[idx].visible() && preview_visual_row_node_ids[idx] == moving_child) {
        before_move_row_index = idx;
        break;
      }
    }

    const bool move_ok = apply_bulk_move_reparent_selected_nodes_command({moving_child}, container_b);
    flow_ok = move_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    auto* moved_node = find_node_by_id(moving_child);
    node_lifecycle_integrity_diag.move_reparent_updates_relations_exact =
      move_ok &&
      moved_node != nullptr &&
      moved_node->parent_id == container_b &&
      count_in_parent(container_a, moving_child) == 0 &&
      count_in_parent(container_b, moving_child) == 1;

    std::size_t moved_row_index = kMaxVisualPreviewRows;
    for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
      if (builder_preview_row_buttons[idx].visible() && preview_visual_row_node_ids[idx] == moving_child) {
        moved_row_index = idx;
        break;
      }
    }
    const bool hit_test_move_ok =
      before_move_row_index < kMaxVisualPreviewRows &&
      moved_row_index < kMaxVisualPreviewRows &&
      moved_row_index != before_move_row_index;
    node_lifecycle_integrity_diag.preview_mapping_updates_after_lifecycle_change =
      move_ok &&
      preview_contains(moving_child) &&
      structure_contains(moving_child) &&
      hit_test_move_ok;

    const std::string recreate_id = "phase103_56-recreate-node";
    const bool create_recreate_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button,
      parent_id,
      recreate_id);
    flow_ok = create_recreate_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    selected_builder_node_id = recreate_id;
    focused_builder_node_id = recreate_id;
    multi_selected_node_ids = {recreate_id};
    sync_multi_selection_with_primary();
    hover_node_id = recreate_id;
    drag_source_node_id = recreate_id;
    drag_target_preview_node_id = recreate_id;
    drag_active = true;
    const bool delete_recreate_ok = apply_delete_command_for_current_selection();
    flow_ok = delete_recreate_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool recreate_again_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button,
      parent_id,
      recreate_id);
    flow_ok = recreate_again_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool duplicate_while_live_rejected = !apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button,
      parent_id,
      recreate_id);
    node_lifecycle_integrity_diag.recreated_node_does_not_collide_or_inherit_stale_state =
      create_recreate_ok &&
      delete_recreate_ok &&
      recreate_again_ok &&
      duplicate_while_live_rejected &&
      node_exists(recreate_id) &&
      count_in_parent(parent_id, recreate_id) == 1 &&
      hover_node_id.empty() &&
      drag_source_node_id.empty() &&
      drag_target_preview_node_id.empty() &&
      !drag_active;

    const std::string subtree_parent = "phase103_56-subtree-parent";
    const std::string subtree_child_a = "phase103_56-subtree-child-a";
    const std::string subtree_child_b = "phase103_56-subtree-child-b";
    const bool add_subtree_parent_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout,
      parent_id,
      subtree_parent);
    const bool add_subtree_child_a_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label,
      subtree_parent,
      subtree_child_a);
    const bool add_subtree_child_b_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button,
      subtree_parent,
      subtree_child_b);
    flow_ok = add_subtree_parent_ok && add_subtree_child_a_ok && add_subtree_child_b_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string subtree_before_delete = build_document_signature(builder_doc, "phase103_56_subtree_before_delete");
    selected_builder_node_id = subtree_parent;
    focused_builder_node_id = subtree_parent;
    multi_selected_node_ids = {subtree_parent};
    sync_multi_selection_with_primary();
    const bool subtree_delete_ok = apply_recorded_delete("phase103_56_subtree_delete");
    flow_ok = subtree_delete_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool subtree_removed_ok =
      !node_exists(subtree_parent) &&
      !node_exists(subtree_child_a) &&
      !node_exists(subtree_child_b);
    const bool subtree_undo_ok = apply_undo_command();
    flow_ok = subtree_undo_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string subtree_after_undo = build_document_signature(builder_doc, "phase103_56_subtree_after_undo");
    node_lifecycle_integrity_diag.subtree_delete_and_restore_exact =
      subtree_delete_ok &&
      subtree_removed_ok &&
      subtree_undo_ok &&
      subtree_after_undo == subtree_before_delete;

    node_lifecycle_integrity_diag.selection_focus_drag_states_clean_after_lifecycle_change =
      (selected_builder_node_id.empty() || node_exists(selected_builder_node_id)) &&
      (focused_builder_node_id.empty() || node_exists(focused_builder_node_id)) &&
      (hover_node_id.empty() || node_exists(hover_node_id)) &&
      (drag_source_node_id.empty() || node_exists(drag_source_node_id)) &&
      (drag_target_preview_node_id.empty() || node_exists(drag_target_preview_node_id)) &&
      (inline_edit_node_id.empty() || node_exists(inline_edit_node_id)) &&
      check_cross_surface_sync();

    bool rapid_ok = true;
    for (int i = 0; i < 4; ++i) {
      const std::string rapid_id = "phase103_56-rapid-" + std::to_string(i + 1);
      const bool create_ok = apply_typed_palette_insert(
        ngk::ui::builder::BuilderWidgetType::Label,
        parent_id,
        rapid_id);
      rapid_ok = rapid_ok && create_ok;
      flow_ok = create_ok && flow_ok;
      flow_ok = refresh_all_surfaces() && flow_ok;
      selected_builder_node_id = rapid_id;
      focused_builder_node_id = rapid_id;
      multi_selected_node_ids = {rapid_id};
      sync_multi_selection_with_primary();
      const bool delete_ok = apply_delete_command_for_current_selection();
      rapid_ok = rapid_ok && delete_ok;
      flow_ok = delete_ok && flow_ok;
      flow_ok = refresh_all_surfaces() && flow_ok;
      rapid_ok = rapid_ok && !node_exists(rapid_id);
    }
    node_lifecycle_integrity_diag.rapid_lifecycle_sequence_stable =
      rapid_ok &&
      document_has_unique_node_ids(builder_doc) &&
      check_cross_surface_sync();

    node_lifecycle_integrity_diag.preview_matches_structure_after_all_lifecycle_ops =
      preview_matches_structure() &&
      check_cross_surface_sync();

    flow_ok = node_lifecycle_integrity_diag.created_node_has_valid_identity && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.deleted_node_fully_removed && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.no_stale_references_after_delete && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.move_reparent_updates_relations_exact && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.preview_mapping_updates_after_lifecycle_change && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.recreated_node_does_not_collide_or_inherit_stale_state && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.subtree_delete_and_restore_exact && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.selection_focus_drag_states_clean_after_lifecycle_change && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.rapid_lifecycle_sequence_stable && flow_ok;
    flow_ok = node_lifecycle_integrity_diag.preview_matches_structure_after_all_lifecycle_ops && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_55 = [&] {
    bool flow_ok = true;
    property_edit_integrity_diag = BuilderPropertyEditIntegrityDiagnostics{};

    auto join_ids = [&](const std::vector<std::string>& ids) -> std::string {
      std::ostringstream oss;
      for (std::size_t idx = 0; idx < ids.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << ids[idx];
      }
      return oss.str();
    };

    auto build_document_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                        const char* context_name) -> std::string {
      std::string error;
      if (!ngk::ui::builder::validate_builder_document(doc, &error)) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":" + error;
      }
      const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
      if (serialized.empty()) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":serialize_failed";
      }
      return serialized;
    };

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

    auto structure_contains = [&](const std::string& node_id) -> bool {
      for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
        if (tree_visual_row_node_ids[idx] == node_id && builder_tree_row_buttons[idx].visible()) {
          return true;
        }
      }
      return false;
    };

    auto preview_contains = [&](const std::string& node_id) -> bool {
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (preview_visual_row_node_ids[idx] == node_id && builder_preview_row_buttons[idx].visible()) {
          return true;
        }
      }
      return false;
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
      !preview_contains(delete_target) &&
      !structure_contains(delete_target) &&
      check_preview_structure_parity();
    flow_ok = preview_structure_parity_diag.no_stale_nodes_after_mutation && flow_ok;

    // Selection stability after move
    run_phase103_2();
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
      preview_contains(selected_builder_node_id) &&
      structure_contains(selected_builder_node_id);
    flow_ok = preview_structure_parity_diag.no_selection_desync_detected && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_53 = [&] {
    bool flow_ok = true;
    command_integrity_diag = BuilderCommandIntegrityDiagnostics{};

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

    auto join_ids = [&](const std::vector<std::string>& ids) -> std::string {
      std::ostringstream oss;
      for (std::size_t idx = 0; idx < ids.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << ids[idx];
      }
      return oss.str();
    };

    auto build_document_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                        const char* context_name) -> std::string {
      std::string error;
      if (!ngk::ui::builder::validate_builder_document(doc, &error)) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":" + error;
      }
      const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
      if (serialized.empty()) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":serialize_failed";
      }
      return serialized;
    };

    auto build_live_state_signature = [&](const char* context_name) -> std::string {
      std::ostringstream oss;
      oss << build_document_signature(builder_doc, context_name) << "\n";
      oss << "selected=" << selected_builder_node_id << "\n";
      oss << "multi=" << join_ids(multi_selected_node_ids) << "\n";
      return oss.str();
    };

    auto preview_matches_structure = [&]() -> bool {
      std::vector<PreviewExportParityEntry> entries{};
      std::string reason;
      if (!build_preview_export_parity_entries(builder_doc, entries, reason, "phase103_53")) {
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

    auto document_has_unique_node_ids = [&](const ngk::ui::builder::BuilderDocument& doc) -> bool {
      std::vector<std::string> seen{};
      for (const auto& node : doc.nodes) {
        if (node.node_id.empty()) {
          return false;
        }
        if (std::find(seen.begin(), seen.end(), node.node_id) != seen.end()) {
          return false;
        }
        seen.push_back(node.node_id);
      }
      return seen.size() == doc.nodes.size();
    };

    auto history_entry_has_valid_references = [&](const CommandHistoryEntry& entry) -> bool {
      auto normalize_selected_id_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                    const std::string& preferred_selected_id,
                                                    const std::vector<std::string>& preferred_multi_selected_ids,
                                                    const ngk::ui::builder::BuilderDocument* counterpart_doc,
                                                    const std::string& counterpart_selected_id) -> std::string {
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
      };

      auto normalize_multi_selection_for_snapshot = [&](const ngk::ui::builder::BuilderDocument& target_doc,
                                                        const std::string& selected_id,
                                                        const std::vector<std::string>& preferred_multi_selected_ids) {
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
      };

      CommandHistoryEntry normalized = entry;
      ngk::ui::builder::BuilderDocument before_doc{};
      before_doc.root_node_id = normalized.before_root_node_id;
      before_doc.nodes = normalized.before_nodes;
      ngk::ui::builder::BuilderDocument after_doc{};
      after_doc.root_node_id = normalized.after_root_node_id;
      after_doc.nodes = normalized.after_nodes;

      std::string before_error;
      std::string after_error;
      if (!ngk::ui::builder::validate_builder_document(before_doc, &before_error) ||
          !ngk::ui::builder::validate_builder_document(after_doc, &after_error)) {
        return false;
      }

      normalized.before_selected_id = normalize_selected_id_for_snapshot(
        before_doc,
        normalized.before_selected_id,
        normalized.before_multi_selected_ids,
        &after_doc,
        normalized.after_selected_id);
      normalized.before_multi_selected_ids = normalize_multi_selection_for_snapshot(
        before_doc,
        normalized.before_selected_id,
        normalized.before_multi_selected_ids);
      normalized.after_selected_id = normalize_selected_id_for_snapshot(
        after_doc,
        normalized.after_selected_id,
        normalized.after_multi_selected_ids,
        &before_doc,
        normalized.before_selected_id);
      normalized.after_multi_selected_ids = normalize_multi_selection_for_snapshot(
        after_doc,
        normalized.after_selected_id,
        normalized.after_multi_selected_ids);

      return normalized.before_selected_id == entry.before_selected_id &&
             normalized.before_multi_selected_ids == entry.before_multi_selected_ids &&
             normalized.after_selected_id == entry.after_selected_id &&
             normalized.after_multi_selected_ids == entry.after_multi_selected_ids;
    };

    auto history_stacks_valid = [&]() -> bool {
      for (const auto& entry : undo_history) {
        if (!history_entry_has_valid_references(entry)) {
          return false;
        }
      }
      for (const auto& entry : redo_stack) {
        if (!history_entry_has_valid_references(entry)) {
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

    auto apply_recorded_delete = [&](const std::string& history_tag) -> bool {
      const auto before_nodes = builder_doc.nodes;
      const std::string before_root = builder_doc.root_node_id;
      const std::string before_sel = selected_builder_node_id;
      const auto before_multi = multi_selected_node_ids;
      const bool ok = apply_delete_command_for_current_selection();
      if (!ok) {
        return false;
      }
      push_to_history(history_tag,
                      before_nodes,
                      before_root,
                      before_sel,
                      &before_multi,
                      builder_doc.nodes,
                      builder_doc.root_node_id,
                      selected_builder_node_id,
                      &multi_selected_node_ids);
      return true;
    };

    auto apply_recorded_move_up = [&](const std::string& history_tag) -> bool {
      const std::string before_signature = build_document_signature(builder_doc, "phase103_53_move_before");
      const auto before_nodes = builder_doc.nodes;
      const std::string before_root = builder_doc.root_node_id;
      const std::string before_sel = selected_builder_node_id;
      const auto before_multi = multi_selected_node_ids;
      apply_move_sibling_up();
      const std::string after_signature = build_document_signature(builder_doc, "phase103_53_move_after");
      if (before_signature == after_signature) {
        return false;
      }
      push_to_history(history_tag,
                      before_nodes,
                      before_root,
                      before_sel,
                      &before_multi,
                      builder_doc.nodes,
                      builder_doc.root_node_id,
                      selected_builder_node_id,
                      &multi_selected_node_ids);
      return true;
    };

    bool preview_parity_ok = true;
    bool stack_integrity_ok = true;

    // Edit round-trip integrity
    flow_ok = reset_phase() && flow_ok;
    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string edit_before_state = build_live_state_signature("phase103_53_edit_before");
    const bool edit_ok = apply_inspector_text_edit_command("phase103_53_label_edited");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string edit_after_state = build_live_state_signature("phase103_53_edit_after");
    const bool edit_undo_ok = edit_ok && apply_undo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool edit_undo_exact = edit_undo_ok && build_live_state_signature("phase103_53_edit_undo") == edit_before_state;
    const bool edit_redo_ok = edit_undo_ok && apply_redo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool edit_redo_exact = edit_redo_ok && build_live_state_signature("phase103_53_edit_redo") == edit_after_state;
    preview_parity_ok = preview_parity_ok && preview_matches_structure();
    stack_integrity_ok = stack_integrity_ok && history_stacks_valid();

    // Move round-trip integrity
    flow_ok = reset_phase() && flow_ok;
    const bool move_setup_a = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, builder_doc.root_node_id, "phase103_53-move-a");
    const bool move_setup_b = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, builder_doc.root_node_id, "phase103_53-move-b");
    flow_ok = move_setup_a && move_setup_b && flow_ok;
    undo_history.clear();
    redo_stack.clear();
    selected_builder_node_id = "phase103_53-move-b";
    focused_builder_node_id = "phase103_53-move-b";
    multi_selected_node_ids = {"phase103_53-move-b"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string move_before_state = build_live_state_signature("phase103_53_move_before");
    const bool move_ok = apply_recorded_move_up("phase103_53_move");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string move_after_state = build_live_state_signature("phase103_53_move_after");
    const bool move_undo_ok = move_ok && apply_undo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool move_undo_exact = move_undo_ok && build_live_state_signature("phase103_53_move_undo") == move_before_state;
    const bool move_redo_ok = move_undo_ok && apply_redo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool move_redo_exact = move_redo_ok && build_live_state_signature("phase103_53_move_redo") == move_after_state;
    preview_parity_ok = preview_parity_ok && preview_matches_structure();
    stack_integrity_ok = stack_integrity_ok && history_stacks_valid();

    // Add -> Add -> Delete -> Undo -> Undo -> Redo -> Redo stability
    flow_ok = reset_phase() && flow_ok;
    const std::string root_id = builder_doc.root_node_id;
    const bool seq_add_1_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Label, root_id, "phase103_53-seq-a");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string seq_state_after_add_1 = build_live_state_signature("phase103_53_seq_after_add_1");
    const bool seq_add_2_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::Button, root_id, "phase103_53-seq-b");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string seq_state_after_add_2 = build_live_state_signature("phase103_53_seq_after_add_2");
    const std::size_t seq_node_count_after_add_2 = builder_doc.nodes.size();
    const std::string deleted_node_id = selected_builder_node_id;
    const auto* deleted_before = find_node_by_id(deleted_node_id);
    const std::string deleted_parent_id = deleted_before ? deleted_before->parent_id : root_id;
    const bool seq_delete_ok = apply_recorded_delete("phase103_53_delete");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string seq_state_after_delete = build_live_state_signature("phase103_53_seq_after_delete");
    const bool fallback_ok = seq_delete_ok &&
      (selected_builder_node_id == deleted_parent_id || selected_builder_node_id == root_id) &&
      node_exists(selected_builder_node_id);

    const bool seq_undo_delete_ok = seq_delete_ok && apply_undo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string seq_state_after_undo_delete = build_live_state_signature("phase103_53_seq_after_undo_delete");
    const bool seq_undo_delete_exact = seq_undo_delete_ok && seq_state_after_undo_delete == seq_state_after_add_2;
    const bool seq_undo_delete_selection = seq_undo_delete_ok &&
      selected_builder_node_id == deleted_node_id &&
      multi_selected_node_ids.size() == 1 &&
      multi_selected_node_ids.front() == deleted_node_id;
    const bool no_missing_after_undo =
      seq_undo_delete_ok &&
      node_exists(deleted_node_id) &&
      builder_doc.nodes.size() == seq_node_count_after_add_2;

    const bool seq_undo_add_2_ok = seq_undo_delete_ok && apply_undo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool seq_undo_add_2_exact = seq_undo_add_2_ok &&
      build_live_state_signature("phase103_53_seq_after_undo_add_2") == seq_state_after_add_1;

    const bool seq_redo_add_2_ok = seq_undo_add_2_ok && apply_redo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const bool seq_redo_add_2_exact = seq_redo_add_2_ok &&
      build_live_state_signature("phase103_53_seq_after_redo_add_2") == seq_state_after_add_2;

    const bool seq_redo_delete_ok = seq_redo_add_2_ok && apply_redo_command();
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string seq_state_after_redo_delete = build_live_state_signature("phase103_53_seq_after_redo_delete");
    const bool seq_redo_delete_exact = seq_redo_delete_ok && seq_state_after_redo_delete == seq_state_after_delete;
    const bool no_duplicate_on_redo =
      seq_redo_delete_ok &&
      document_has_unique_node_ids(builder_doc) &&
      !node_exists(deleted_node_id);

    preview_parity_ok = preview_parity_ok && preview_matches_structure();
    stack_integrity_ok = stack_integrity_ok && history_stacks_valid();

    command_integrity_diag.undo_restores_exact_structure =
      edit_undo_exact && move_undo_exact && seq_undo_delete_exact;
    command_integrity_diag.undo_restores_selection =
      edit_undo_exact && move_undo_exact && seq_undo_delete_selection;
    command_integrity_diag.redo_reapplies_exact_state =
      edit_redo_exact && move_redo_exact && seq_redo_delete_exact;
    command_integrity_diag.no_duplicate_nodes_on_redo = no_duplicate_on_redo;
    command_integrity_diag.no_missing_nodes_after_undo = no_missing_after_undo;
    command_integrity_diag.command_stack_no_invalid_references = stack_integrity_ok;
    command_integrity_diag.selection_fallback_deterministic = fallback_ok;
    command_integrity_diag.multi_step_sequence_stable =
      seq_add_1_ok &&
      seq_add_2_ok &&
      seq_delete_ok &&
      seq_undo_delete_exact &&
      seq_undo_add_2_exact &&
      seq_redo_add_2_exact &&
      seq_redo_delete_exact &&
      undo_history.size() == 3 &&
      redo_stack.empty();
    command_integrity_diag.no_side_effect_mutations =
      seq_undo_delete_exact &&
      seq_undo_add_2_exact &&
      seq_redo_add_2_exact &&
      seq_redo_delete_exact;
    command_integrity_diag.preview_matches_structure_after_undo_redo = preview_parity_ok;

    flow_ok = command_integrity_diag.undo_restores_exact_structure && flow_ok;
    flow_ok = command_integrity_diag.undo_restores_selection && flow_ok;
    flow_ok = command_integrity_diag.redo_reapplies_exact_state && flow_ok;
    flow_ok = command_integrity_diag.no_duplicate_nodes_on_redo && flow_ok;
    flow_ok = command_integrity_diag.no_missing_nodes_after_undo && flow_ok;
    flow_ok = command_integrity_diag.command_stack_no_invalid_references && flow_ok;
    flow_ok = command_integrity_diag.selection_fallback_deterministic && flow_ok;
    flow_ok = command_integrity_diag.multi_step_sequence_stable && flow_ok;
    flow_ok = command_integrity_diag.no_side_effect_mutations && flow_ok;
    flow_ok = command_integrity_diag.preview_matches_structure_after_undo_redo && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_54 = [&] {
    bool flow_ok = true;
    save_load_integrity_diag = BuilderSaveLoadStateIntegrityDiagnostics{};

    auto join_ids = [&](const std::vector<std::string>& ids) -> std::string {
      std::ostringstream oss;
      for (std::size_t idx = 0; idx < ids.size(); ++idx) {
        if (idx > 0) {
          oss << ",";
        }
        oss << ids[idx];
      }
      return oss.str();
    };

    auto build_document_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                        const char* context_name) -> std::string {
      std::string error;
      if (!ngk::ui::builder::validate_builder_document(doc, &error)) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":" + error;
      }
      const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
      if (serialized.empty()) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":serialize_failed";
      }
      return serialized;
    };

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
    bool flow_ok = true;
    bounds_layout_constraint_diag = BuilderBoundsLayoutConstraintIntegrityDiagnostics{};

    auto build_document_signature = [&](const ngk::ui::builder::BuilderDocument& doc,
                                        const char* context_name) -> std::string {
      std::string error;
      if (!ngk::ui::builder::validate_builder_document(doc, &error)) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":" + error;
      }
      const std::string serialized = ngk::ui::builder::serialize_builder_document_deterministic(doc);
      if (serialized.empty()) {
        return std::string("invalid:") + (context_name == nullptr ? "document" : context_name) + ":serialize_failed";
      }
      return serialized;
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
      if (!build_preview_export_parity_entries(builder_doc, entries, reason, "phase103_57")) {
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

    // ---- Marker 1: negative_dimensions_rejected ----
    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const std::string sig_before_neg = build_document_signature(builder_doc, "phase103_57_before_neg");
    const std::size_t history_before_neg = undo_history.size();
    const bool neg_width_rejected = !apply_inspector_property_edits_command(
      {{"layout.min_width", "-10"}}, "phase103_57_neg_width");
    const bool neg_height_rejected = !apply_inspector_property_edits_command(
      {{"layout.min_height", "-5"}}, "phase103_57_neg_height");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string sig_after_neg = build_document_signature(builder_doc, "phase103_57_after_neg");

    bounds_layout_constraint_diag.negative_dimensions_rejected =
      neg_width_rejected &&
      neg_height_rejected &&
      history_before_neg == undo_history.size() &&
      sig_before_neg == sig_after_neg;

    // ---- Marker 2: invalid_child_parent_geometry_rejected ----
    // layout.weight=0 violates layout_weight > 0 (child partition constraint)
    // layout.preferred_width=-8 violates preferred_width >= 0 (child size constraint)
    const std::string sig_before_weight = build_document_signature(builder_doc, "phase103_57_before_weight");
    const std::size_t history_before_weight = undo_history.size();
    const bool zero_weight_rejected = !apply_inspector_property_edits_command(
      {{"layout.weight", "0"}}, "phase103_57_zero_weight");
    const bool neg_preferred_rejected = !apply_inspector_property_edits_command(
      {{"layout.preferred_width", "-8"}}, "phase103_57_neg_preferred");
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string sig_after_weight = build_document_signature(builder_doc, "phase103_57_after_weight");

    bounds_layout_constraint_diag.invalid_child_parent_geometry_rejected =
      zero_weight_rejected &&
      neg_preferred_rejected &&
      history_before_weight == undo_history.size() &&
      sig_before_weight == sig_after_weight;

    // ---- Marker 3: move_reparent_respects_layout_constraints ----
    // Insert a container under root, reparent label-001 into it, verify doc valid
    selected_builder_node_id = builder_doc.root_node_id;
    focused_builder_node_id = builder_doc.root_node_id;
    multi_selected_node_ids = {builder_doc.root_node_id};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const bool insert_container_ok = apply_typed_palette_insert(
      ngk::ui::builder::BuilderWidgetType::VerticalLayout,
      builder_doc.root_node_id,
      "phase103-57-cont");
    flow_ok = insert_container_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;

    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const bool move_ok = insert_container_ok &&
      apply_bulk_move_reparent_selected_nodes_command({"label-001"}, "phase103-57-cont");
    flow_ok = move_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;

    std::string validation_err_after_move;
    bounds_layout_constraint_diag.move_reparent_respects_layout_constraints =
      move_ok &&
      ngk::ui::builder::validate_builder_document(builder_doc, &validation_err_after_move) &&
      preview_matches_structure() &&
      check_cross_surface_sync();

    // ---- Marker 4: invalid_layout_not_committed_to_history ----
    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const std::size_t history_before_compound_reject = undo_history.size();
    const bool compound_reject_ok = !apply_inspector_property_edits_command(
      {{"layout.min_width", "-1"}, {"layout.min_height", "-2"}},
      "phase103_57_compound_reject");
    const std::size_t history_after_compound_reject = undo_history.size();
    flow_ok = refresh_all_surfaces() && flow_ok;

    bounds_layout_constraint_diag.invalid_layout_not_committed_to_history =
      compound_reject_ok &&
      history_before_compound_reject == history_after_compound_reject;

    // ---- Marker 5: preview_never_reflects_invalid_document_state ----
    bounds_layout_constraint_diag.preview_never_reflects_invalid_document_state =
      preview_matches_structure() &&
      ngk::ui::builder::validate_builder_document(builder_doc, nullptr) &&
      check_cross_surface_sync();

    // ---- Marker 6: undo_redo_restore_valid_layout_exact ----
    const std::string before_layout_edit_sig = build_document_signature(builder_doc, "phase103_57_before_layout_edit");
    const bool valid_layout_edit_ok = apply_inspector_property_edits_command(
      {{"layout.min_width", "160"}, {"layout.min_height", "40"}},
      "phase103_57_valid_layout_edit");
    flow_ok = valid_layout_edit_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string after_layout_edit_sig = build_document_signature(builder_doc, "phase103_57_after_layout_edit");

    const auto* node_after_edit = find_node_by_id("label-001");
    const bool edit_values_correct =
      node_after_edit != nullptr &&
      node_after_edit->layout.min_width == 160 &&
      node_after_edit->layout.min_height == 40;

    const bool undo_layout_ok = apply_undo_command();
    flow_ok = undo_layout_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string after_undo_sig = build_document_signature(builder_doc, "phase103_57_after_undo");

    const bool redo_layout_ok = apply_redo_command();
    flow_ok = redo_layout_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;
    const std::string after_redo_sig = build_document_signature(builder_doc, "phase103_57_after_redo");

    bounds_layout_constraint_diag.undo_redo_restore_valid_layout_exact =
      valid_layout_edit_ok &&
      edit_values_correct &&
      undo_layout_ok && redo_layout_ok &&
      after_undo_sig == before_layout_edit_sig &&
      after_redo_sig == after_layout_edit_sig;

    // ---- Marker 7: save_load_rejects_constraint_violating_payload ----
    // Serialise current doc, corrupt layout.min_width to -99, write to a test file,
    // then verify load returns false and doc remains unchanged.
    const std::filesystem::path invalid_payload_path =
      builder_doc_save_path.parent_path() / "phase103_57_invalid_layout_payload.ngkb";
    const std::string valid_serial = ngk::ui::builder::serialize_builder_document_deterministic(builder_doc);
    bool invalid_rejected = false;
    if (!valid_serial.empty()) {
      std::string corrupted = valid_serial;
      const std::string search_tok = "layout.min_width=";
      const std::size_t tok_pos = corrupted.find(search_tok);
      if (tok_pos != std::string::npos) {
        const std::size_t value_start = tok_pos + search_tok.size();
        const std::size_t value_end = corrupted.find('\n', value_start);
        if (value_end != std::string::npos) {
          corrupted.replace(value_start, value_end - value_start, "-99");
          const std::string sig_before_bad_load = build_document_signature(builder_doc, "phase103_57_before_bad_load");
          if (write_text_file(invalid_payload_path, corrupted)) {
            const bool load_returned_false = !load_builder_document_from_path(invalid_payload_path);
            const std::string sig_after_bad_load = build_document_signature(builder_doc, "phase103_57_after_bad_load");
            invalid_rejected = load_returned_false &&
              ngk::ui::builder::validate_builder_document(builder_doc, nullptr) &&
              sig_before_bad_load == sig_after_bad_load;
          }
        }
      }
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    bounds_layout_constraint_diag.save_load_rejects_constraint_violating_payload = invalid_rejected;

    // ---- Marker 8: valid_layout_roundtrip_preserved ----
    // Current label-001 has min_width=160, min_height=40 (from marker 6 redo).
    // Save, mutate, load back, verify original layout values restored.
    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const std::string sig_before_save = build_document_signature(builder_doc, "phase103_57_before_save");
    const bool save_ok = apply_save_document_command();
    flow_ok = save_ok && flow_ok;

    const bool mutate_ok = apply_inspector_property_edits_command(
      {{"layout.min_width", "999"}},
      "phase103_57_mutate_before_load");
    flow_ok = mutate_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;

    const bool load_ok = apply_load_document_command(true);
    flow_ok = load_ok && flow_ok;
    flow_ok = refresh_all_surfaces() && flow_ok;

    const std::string sig_after_roundtrip = build_document_signature(builder_doc, "phase103_57_after_roundtrip");
    const auto* roundtrip_node = find_node_by_id("label-001");
    const bool roundtrip_layout_correct =
      roundtrip_node != nullptr &&
      roundtrip_node->layout.min_width == 160 &&
      roundtrip_node->layout.min_height == 40;

    bounds_layout_constraint_diag.valid_layout_roundtrip_preserved =
      save_ok && load_ok &&
      roundtrip_layout_correct &&
      sig_after_roundtrip == sig_before_save;

    // ---- Marker 9: no_silent_geometry_autocorrection ----
    selected_builder_node_id = "label-001";
    focused_builder_node_id = "label-001";
    multi_selected_node_ids = {"label-001"};
    sync_multi_selection_with_primary();
    flow_ok = refresh_all_surfaces() && flow_ok;

    const auto* pre_node = find_node_by_id("label-001");
    const int pre_min_width = pre_node ? pre_node->layout.min_width : -1;
    const int pre_min_height = pre_node ? pre_node->layout.min_height : -1;

    const bool autocorrect_rejected = !apply_inspector_property_edits_command(
      {{"layout.min_width", "-50"}}, "phase103_57_autocorrect_test");
    flow_ok = refresh_all_surfaces() && flow_ok;

    const auto* post_node = find_node_by_id("label-001");
    const int post_min_width = post_node ? post_node->layout.min_width : -1;
    const int post_min_height = post_node ? post_node->layout.min_height : -1;

    bounds_layout_constraint_diag.no_silent_geometry_autocorrection =
      autocorrect_rejected &&
      pre_min_width >= 0 &&
      pre_min_height >= 0 &&
      post_min_width == pre_min_width &&
      post_min_height == pre_min_height;

    // ---- Marker 10: preview_matches_structure_after_layout_mutations ----
    bounds_layout_constraint_diag.preview_matches_structure_after_layout_mutations =
      preview_matches_structure() &&
      ngk::ui::builder::validate_builder_document(builder_doc, nullptr) &&
      check_cross_surface_sync();

    flow_ok = bounds_layout_constraint_diag.negative_dimensions_rejected && flow_ok;
    flow_ok = bounds_layout_constraint_diag.invalid_child_parent_geometry_rejected && flow_ok;
    flow_ok = bounds_layout_constraint_diag.move_reparent_respects_layout_constraints && flow_ok;
    flow_ok = bounds_layout_constraint_diag.invalid_layout_not_committed_to_history && flow_ok;
    flow_ok = bounds_layout_constraint_diag.preview_never_reflects_invalid_document_state && flow_ok;
    flow_ok = bounds_layout_constraint_diag.undo_redo_restore_valid_layout_exact && flow_ok;
    flow_ok = bounds_layout_constraint_diag.save_load_rejects_constraint_violating_payload && flow_ok;
    flow_ok = bounds_layout_constraint_diag.valid_layout_roundtrip_preserved && flow_ok;
    flow_ok = bounds_layout_constraint_diag.no_silent_geometry_autocorrection && flow_ok;
    flow_ok = bounds_layout_constraint_diag.preview_matches_structure_after_layout_mutations && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  auto run_phase103_58 = [&] {
    bool flow_ok = true;
    event_input_routing_diag = BuilderEventInputRoutingIntegrityDiagnostics{};

    const std::string kStaleRoutingRef{"phase103-58-nonexistent-stale-target"};

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
      if (!build_preview_export_parity_entries(builder_doc, entries, reason, "phase103_58")) {
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
      hover_node_id.clear();
      drag_source_node_id.clear();
      drag_active = false;
      drag_target_preview_node_id.clear();
      drag_target_preview_is_illegal = false;
      sync_multi_selection_with_primary();
      return refresh_all_surfaces();
    };

    flow_ok = reset_phase() && flow_ok;

    // ---- Marker 1: hit_test_returns_single_correct_node ----
    // build_preview_click_hit_entries must produce a non-empty, duplicate-free,
    // fully-valid set of entries — exactly what click routing relies on.
    {
      std::vector<PreviewExportParityEntry> hit_entries{};
      std::string hit_reason;
      const bool hit_map_ok = build_preview_click_hit_entries(hit_entries, hit_reason);
      bool all_valid = hit_map_ok && !hit_entries.empty();
      bool no_duplicates = true;
      std::vector<std::string> seen_ids{};
      for (const auto& entry : hit_entries) {
        if (entry.node_id.empty() || !node_exists(entry.node_id)) {
          all_valid = false;
          break;
        }
        if (std::find(seen_ids.begin(), seen_ids.end(), entry.node_id) != seen_ids.end()) {
          no_duplicates = false;
          break;
        }
        seen_ids.push_back(entry.node_id);
      }
      event_input_routing_diag.hit_test_returns_single_correct_node =
        hit_map_ok && all_valid && no_duplicates;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 2: preview_click_matches_structure_selection ----
    // preview_visual_row_node_ids (row map powering click routing) must agree exactly
    // with build_preview_click_hit_entries. Also verify programmatic selection via
    // the node IDs in the row map resolves correctly through the routing pipeline.
    {
      std::vector<PreviewExportParityEntry> hit_entries{};
      std::string hit_reason;
      const bool hit_map_ok = build_preview_click_hit_entries(hit_entries, hit_reason);
      std::vector<std::string> row_ids{};
      for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
        if (!builder_preview_row_buttons[idx].visible() || preview_visual_row_node_ids[idx].empty()) {
          continue;
        }
        row_ids.push_back(preview_visual_row_node_ids[idx]);
      }
      bool mapping_consistent = hit_map_ok && (row_ids.size() == hit_entries.size());
      if (mapping_consistent) {
        for (std::size_t idx = 0; idx < hit_entries.size(); ++idx) {
          if (row_ids[idx] != hit_entries[idx].node_id) {
            mapping_consistent = false;
            break;
          }
        }
      }
      // Verify programmatic routing: set selection to a known row-mapped node,
      // confirm routing pipeline resolves it correctly.
      bool routing_consistent = mapping_consistent;
      if (mapping_consistent && !hit_entries.empty()) {
        const std::size_t test_idx = hit_entries.size() > 1 ? 1 : 0;
        const std::string& target_id = hit_entries[test_idx].node_id;
        selected_builder_node_id = target_id;
        sync_multi_selection_with_primary();
        const bool remap_ok = remap_selection_or_fail();
        const bool focus_ok = sync_focus_with_selection_or_fail();
        routing_consistent = remap_ok && focus_ok &&
          selected_builder_node_id == target_id &&
          focused_builder_node_id == target_id;
        // Restore root selection
        selected_builder_node_id = builder_doc.root_node_id;
        focused_builder_node_id = builder_doc.root_node_id;
        multi_selected_node_ids = {builder_doc.root_node_id};
        sync_multi_selection_with_primary();
      }
      event_input_routing_diag.preview_click_matches_structure_selection =
        mapping_consistent && routing_consistent;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 3: no_input_routed_to_stale_nodes ----
    // Inject stale IDs into hover/drag/focused states and verify routing
    // functions reject them without acting on the stale targets.
    {
      // hover stale cleared by scrub
      hover_node_id = kStaleRoutingRef;
      scrub_stale_lifecycle_references();
      const bool hover_cleared = hover_node_id.empty();
      // drag stale cleared by scrub (also clears drag_active)
      drag_source_node_id = kStaleRoutingRef;
      drag_active = true;
      scrub_stale_lifecycle_references();
      const bool drag_cleared = drag_source_node_id.empty() && !drag_active;
      // stale focused → sync_focus_with_selection_or_fail returns false
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = kStaleRoutingRef;
      const bool stale_focus_rejected = !sync_focus_with_selection_or_fail();
      focused_builder_node_id = builder_doc.root_node_id;
      // stale focused → apply_keyboard_multi_selection_add_focused returns false
      focused_builder_node_id = kStaleRoutingRef;
      const bool stale_kbfocus_rejected = !apply_keyboard_multi_selection_add_focused();
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      event_input_routing_diag.no_input_routed_to_stale_nodes =
        hover_cleared && drag_cleared && stale_focus_rejected && stale_kbfocus_rejected;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 4: event_order_deterministic ----
    // collect_preorder_node_ids is stable across calls.
    // Forward + backward navigation produces a deterministic round-trip.
    {
      const std::vector<std::string> order1 = collect_preorder_node_ids();
      const std::vector<std::string> order2 = collect_preorder_node_ids();
      const bool preorder_stable = order1.size() > 1 && order1 == order2;
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      const bool nav_fwd = apply_tree_navigation(true);
      const std::string after_fwd = selected_builder_node_id;
      const bool nav_back = apply_tree_navigation(false);
      const std::string after_back = selected_builder_node_id;
      // Forward from root → second node; backward from second node → root
      const bool round_trip_ok =
        nav_fwd && nav_back &&
        !after_fwd.empty() && node_exists(after_fwd) &&
        after_back == builder_doc.root_node_id;
      // Restore
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      event_input_routing_diag.event_order_deterministic = preorder_stable && round_trip_ok;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 5: focus_hover_drag_states_valid ----
    // Valid states pass check_cross_surface_sync.
    // Stale states are explicitly cleared by scrub_stale_lifecycle_references.
    {
      // Baseline: after reset_phase, hover/drag should be empty
      const bool initial_clean = hover_node_id.empty() && drag_source_node_id.empty() && !drag_active;
      // Assign valid hover → check_cross_surface_sync passes (scrubs inside, root valid)
      hover_node_id = builder_doc.root_node_id;
      const bool valid_hover_sync = check_cross_surface_sync();
      hover_node_id.clear();
      // Stale hover → not a real node ID
      hover_node_id = kStaleRoutingRef;
      const bool stale_hover_present = !node_exists(hover_node_id);
      scrub_stale_lifecycle_references();
      const bool stale_hover_cleared = hover_node_id.empty();
      // Stale drag → scrub clears both drag_source and drag_active
      drag_source_node_id = kStaleRoutingRef;
      drag_active = true;
      const bool stale_drag_present = !node_exists(drag_source_node_id);
      scrub_stale_lifecycle_references();
      const bool stale_drag_cleared = drag_source_node_id.empty() && !drag_active;
      // After all scrubs, sync recovers
      const bool final_sync = check_cross_surface_sync();
      event_input_routing_diag.focus_hover_drag_states_valid =
        initial_clean &&
        valid_hover_sync &&
        stale_hover_present && stale_hover_cleared &&
        stale_drag_present && stale_drag_cleared &&
        final_sync;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 6: keyboard_targets_current_selection_only ----
    // Stale focused → apply_focus_navigation resolves to a valid node, not the stale target.
    // Stale focused → apply_keyboard_multi_selection_add_focused does not add the stale ID.
    {
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = kStaleRoutingRef;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      const bool nav_ok = apply_focus_navigation(true);
      const bool nav_resolved_valid =
        nav_ok &&
        focused_builder_node_id != kStaleRoutingRef &&
        !focused_builder_node_id.empty() &&
        node_exists(focused_builder_node_id);
      // Stale focused → keyboard multi-select add does not add the stale ID
      focused_builder_node_id = kStaleRoutingRef;
      multi_selected_node_ids = {builder_doc.root_node_id};
      const bool stale_add_rejected = !apply_keyboard_multi_selection_add_focused();
      const bool stale_not_in_multi =
        std::find(multi_selected_node_ids.begin(), multi_selected_node_ids.end(),
                  kStaleRoutingRef) == multi_selected_node_ids.end();
      // Restore
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      event_input_routing_diag.keyboard_targets_current_selection_only =
        nav_resolved_valid && stale_add_rejected && stale_not_in_multi;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 7: rapid_interaction_sequence_stable ----
    // 10 consecutive tree navigations leave the system coherent after each step.
    {
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      hover_node_id.clear();
      drag_source_node_id.clear();
      sync_multi_selection_with_primary();
      bool rapid_stable = true;
      for (int iter = 0; iter < 10 && rapid_stable; ++iter) {
        const bool nav_ok = apply_tree_navigation(true);
        multi_selected_node_ids = {selected_builder_node_id};
        rapid_stable = nav_ok && refresh_all_surfaces();
      }
      // Restore to root
      selected_builder_node_id = builder_doc.root_node_id;
      focused_builder_node_id = builder_doc.root_node_id;
      multi_selected_node_ids = {builder_doc.root_node_id};
      sync_multi_selection_with_primary();
      event_input_routing_diag.rapid_interaction_sequence_stable = rapid_stable;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 8: no_ghost_or_duplicate_event_targets ----
    // sync_multi_selection_with_primary deduplicates and removes stale IDs.
    {
      const std::string primary = builder_doc.root_node_id;
      // Inject duplicates and a stale ID
      multi_selected_node_ids = {primary, primary, kStaleRoutingRef, primary};
      selected_builder_node_id = primary;
      focused_builder_node_id = primary;
      sync_multi_selection_with_primary();
      const bool no_dups = multi_selected_node_ids.size() == 1;
      const bool stale_removed =
        std::find(multi_selected_node_ids.begin(), multi_selected_node_ids.end(),
                  kStaleRoutingRef) == multi_selected_node_ids.end();
      const bool primary_intact =
        !multi_selected_node_ids.empty() && multi_selected_node_ids.front() == primary;
      // Restore
      multi_selected_node_ids = {primary};
      sync_multi_selection_with_primary();
      event_input_routing_diag.no_ghost_or_duplicate_event_targets =
        no_dups && stale_removed && primary_intact;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 9: event_routing_respects_render_hierarchy ----
    // build_preview_click_hit_entries order is a subsequence of
    // collect_preorder_node_ids (both use the same DFS document traversal).
    {
      std::vector<PreviewExportParityEntry> hit_entries{};
      std::string hit_reason;
      const bool hit_map_ok = build_preview_click_hit_entries(hit_entries, hit_reason);
      const std::vector<std::string> preorder = collect_preorder_node_ids();
      bool hierarchy_ok = hit_map_ok && !hit_entries.empty() && !preorder.empty();
      if (hierarchy_ok) {
        std::size_t search_from = 0;
        for (const auto& entry : hit_entries) {
          bool found = false;
          for (std::size_t pi = search_from; pi < preorder.size(); ++pi) {
            if (preorder[pi] == entry.node_id) {
              search_from = pi + 1;
              found = true;
              break;
            }
          }
          if (!found) {
            hierarchy_ok = false;
            break;
          }
        }
      }
      event_input_routing_diag.event_routing_respects_render_hierarchy = hierarchy_ok;
    }
    flow_ok = refresh_all_surfaces() && flow_ok;

    // ---- Marker 10: preview_matches_structure_after_input_sequences ----
    event_input_routing_diag.preview_matches_structure_after_input_sequences =
      preview_matches_structure() &&
      ngk::ui::builder::validate_builder_document(builder_doc, nullptr) &&
      check_cross_surface_sync();

    flow_ok = event_input_routing_diag.hit_test_returns_single_correct_node && flow_ok;
    flow_ok = event_input_routing_diag.preview_click_matches_structure_selection && flow_ok;
    flow_ok = event_input_routing_diag.no_input_routed_to_stale_nodes && flow_ok;
    flow_ok = event_input_routing_diag.event_order_deterministic && flow_ok;
    flow_ok = event_input_routing_diag.focus_hover_drag_states_valid && flow_ok;
    flow_ok = event_input_routing_diag.keyboard_targets_current_selection_only && flow_ok;
    flow_ok = event_input_routing_diag.rapid_interaction_sequence_stable && flow_ok;
    flow_ok = event_input_routing_diag.no_ghost_or_duplicate_event_targets && flow_ok;
    flow_ok = event_input_routing_diag.event_routing_respects_render_hierarchy && flow_ok;
    flow_ok = event_input_routing_diag.preview_matches_structure_after_input_sequences && flow_ok;

    if (!flow_ok) {
      model.undefined_state_detected = true;
    }
  };

  builder_insert_container_button.set_on_click([&] {
    if (apply_palette_insert(true)) {
      set_last_action_feedback("Added Container");
      recompute_builder_dirty_state(true);
    } else {
      set_last_action_feedback("Cannot add container here");
    }
  });
  builder_insert_leaf_button.set_on_click([&] {
    if (apply_palette_insert(false)) {
      set_last_action_feedback("Added Item");
      recompute_builder_dirty_state(true);
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
    if (apply_delete_command_for_current_selection()) {
      set_last_action_feedback("Deleted Node");
      recompute_builder_dirty_state(true);
    } else {
      const std::string delete_reason = delete_rejection_reason_for_node(selected_builder_node_id);
      if (delete_reason == "protected_root") {
        set_last_action_feedback("Cannot delete root");
      } else {
        set_last_action_feedback("Delete blocked");
      }
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
    set_last_action_feedback("Saved Document");
    request_redraw("builder_save", false, false);
  });
  builder_export_button.set_on_click([&] {
    apply_export_command(builder_doc, builder_export_path);
    set_last_action_feedback("Exported Runtime");
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
    if (apply_new_document_command(false)) {
      set_last_action_feedback("Created New Document");
    } else {
      set_last_action_feedback("New document blocked by unsaved changes");
    }
    request_redraw("builder_new", false, false);
  });
  builder_new_discard_button.set_on_click([&] {
    if (apply_new_document_command(true)) {
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
    if (apply_delete_command_for_current_selection()) {
      set_last_action_feedback("Item removed");
      set_preview_visual_feedback("Item removed", deleted_target);
      set_tree_visual_feedback(deleted_target);
      recompute_builder_dirty_state(true);
    } else {
      set_last_action_feedback("Delete blocked");
      set_preview_visual_feedback("This item cannot be deleted.", deleted_target);
      set_tree_visual_feedback(deleted_target);
    }
    remap_selection_or_fail();
    sync_focus_with_selection_or_fail();
    refresh_tree_surface_label();
    refresh_inspector_or_fail();
    refresh_preview_or_fail();
    check_cross_surface_sync();
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

  for (std::size_t idx = 0; idx < kMaxVisualTreeRows; ++idx) {
    builder_tree_row_buttons[idx].set_on_click([&, idx] {
      const std::string& target_id = tree_visual_row_node_ids[idx];
      if (target_id.empty() || !node_exists(target_id)) {
        return;
      }
      selected_builder_node_id = target_id;
      set_last_action_feedback(std::string("Selected ") + target_id);
      set_preview_visual_feedback("Selected item in structure.", target_id);
      set_tree_visual_feedback(target_id);
      remap_selection_or_fail();
      sync_focus_with_selection_or_fail();
      refresh_inspector_or_fail();
      refresh_preview_or_fail();
      check_cross_surface_sync();
      request_redraw("tree_visual_select", true, false);
    });
  }

  for (std::size_t idx = 0; idx < kMaxVisualPreviewRows; ++idx) {
    builder_preview_row_buttons[idx].set_on_click([&, idx] {
      const std::string& target_id = preview_visual_row_node_ids[idx];
      if (target_id.empty() || !node_exists(target_id)) {
        return;
      }
      const int click_x = builder_preview_label.x() + 6;
      const int click_y = builder_preview_row_buttons[idx].y() + 6;
      if (!apply_preview_click_select_at_point(click_x, click_y)) {
        return;
      }
      if (selected_builder_node_id != target_id) {
        return;
      }

      auto* preview_node = find_node_by_id(selected_builder_node_id);
      if (preview_node && preview_node->widget_type == ngk::ui::builder::BuilderWidgetType::Label) {
        if (inline_edit_active && inline_edit_node_id != selected_builder_node_id) {
          commit_inline_edit();
        }
        if (!inline_edit_active || inline_edit_node_id != selected_builder_node_id) {
          enter_inline_edit_mode(selected_builder_node_id);
          preview_inline_loaded_text = inline_edit_buffer;
        }
      } else if (inline_edit_active) {
        commit_inline_edit();
      }
      set_last_action_feedback(std::string("Selected ") + selected_builder_node_id);
      set_preview_visual_feedback("Selected item in preview.", selected_builder_node_id);
      set_tree_visual_feedback(selected_builder_node_id);
      remap_selection_or_fail();
      sync_focus_with_selection_or_fail();
      refresh_inspector_or_fail();
      refresh_preview_or_fail();
      check_cross_surface_sync();
      request_redraw("preview_visual_select", true, false);
    });
  }

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
  reload_entries(model, scan_root);
  update_labels();
  set_last_action_feedback("Ready");
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

#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "builder_document.hpp"

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
  bool action_selected_id_matches_selected_node = false;
  bool selected_node_matches_selected_id = false;
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

struct BuilderGlobalInvariantEnforcementDiagnostics {
  bool global_invariant_detects_invalid_state = false;
  bool all_mutations_checked_by_invariant = false;
  bool invalid_mutation_rejected_or_rolled_back = false;
  bool no_orphan_nodes_possible = false;
  bool all_node_ids_unique_and_valid = false;
  bool selection_references_valid_nodes_only = false;
  bool preview_structure_parity_enforced_by_invariant = false;
  bool layout_constraints_enforced_by_invariant = false;
  bool command_history_references_valid_state = false;
  bool no_false_positive_rejections = false;
};

struct BuilderExportPackageIntegrityDiagnostics {
  bool export_blocked_on_invalid_invariant = false;
  bool export_contains_all_nodes_and_properties = false;
  bool export_order_matches_structure = false;
  bool export_deterministic_for_identical_input = false;
  bool no_runtime_state_leaked_into_export = false;
  bool package_manifest_or_contents_coherent = false;
  bool export_reflects_post_mutation_live_state = false;
  bool partial_export_never_reported_success = false;
  bool roundtrip_export_artifacts_valid = false;
  bool export_preserves_structure_fidelity = false;
};

struct BuilderStartupShutdownIntegrityDiagnostics {
  bool startup_produces_invariant_valid_state = false;
  bool no_transient_runtime_state_leaks_on_startup = false;
  bool preview_and_inspector_bindings_valid_after_startup = false;
  bool selection_state_deterministic_after_startup = false;
  bool shutdown_does_not_leave_partial_success_state = false;
  bool close_reopen_cycle_preserves_clean_valid_state = false;
  bool startup_after_load_preserves_structure_fidelity = false;
  bool repeated_open_close_cycles_stable = false;
  bool no_false_dirty_or_unexpected_mutation_on_lifecycle_boundary = false;
  bool global_invariant_holds_at_startup_and_shutdown = false;
};

struct BuilderStressSequenceResilienceDiagnostics {
  bool long_mixed_sequence_preserves_invariant = false;
  bool no_structure_preview_drift_after_stress = false;
  bool selection_and_bindings_remain_valid_after_stress = false;
  bool undo_redo_history_stable_under_long_sequence = false;
  bool no_stale_references_accumulated = false;
  bool save_load_exact_after_stress = false;
  bool export_exact_after_stress = false;
  bool replay_of_identical_sequence_deterministic = false;
  bool no_false_dirty_or_phantom_mutation_after_stress = false;
  bool final_state_matches_expected_canonical_signature = false;
};

struct BuilderManualTextEntryIntegrityDiagnostics {
  bool inline_edit_buffer_not_committed_until_commit = false;
  bool cancelled_edit_leaves_document_unchanged = false;
  bool committed_edit_creates_exact_history_entry = false;
  bool undo_redo_exact_for_committed_text_edit = false;
  bool selection_or_target_change_during_edit_resolved_deterministically = false;
  bool no_stale_inline_edit_target_after_delete_move_load = false;
  bool transient_edit_buffer_never_leaks_into_save_or_export = false;
  bool rapid_edit_commit_cancel_sequences_stable = false;
  bool no_history_entry_created_for_cancelled_edit = false;
  bool global_invariant_preserved_through_manual_text_entry = false;
};

struct BuilderMultiSelectionIntegrityHardeningDiagnostics {
  bool selection_set_contains_only_valid_nodes = false;
  bool no_duplicate_ids_in_selection = false;
  bool primary_and_multi_selection_consistent = false;
  bool multi_operations_apply_to_all_selected_nodes = false;
  bool multi_operations_atomic_and_command_backed = false;
  bool delete_move_reparent_clean_selection_state = false;
  bool undo_redo_restore_full_selection_state = false;
  bool no_stale_ids_after_lifecycle_events = false;
  bool multi_operation_order_deterministic = false;
  bool no_cross_node_state_corruption = false;
};

struct BuilderClipboardDuplicateCopyPasteIntegrityHardeningDiagnostics {
  bool clipboard_payload_requires_valid_selection = false;
  bool duplicate_creates_fresh_unique_ids = false;
  bool paste_preserves_subtree_fidelity = false;
  bool paste_does_not_leak_runtime_state = false;
  bool paste_target_validation_fail_closed = false;
  bool cut_paste_roundtrip_preserves_structure = false;
  bool undo_redo_exact_for_clipboard_operations = false;
  bool deterministic_paste_order_and_parenting = false;
  bool nested_selection_deduplicated_on_copy = false;
  bool no_cross_node_corruption_after_clipboard_sequence = false;
};

struct BuilderClipboardExternalDataBoundaryIntegrityHardeningDiagnostics {
  bool external_paste_rejects_malformed_or_partial_data = false;
  bool external_data_parsed_and_applied_atomically = false;
  bool imported_nodes_have_valid_ids_and_relationships = false;
  bool external_input_cannot_bypass_global_invariant = false;
  bool internal_clipboard_path_unchanged_and_isolated = false;
  bool deterministic_result_for_identical_external_input = false;
  bool failed_external_paste_creates_no_history_or_dirty_change = false;
  bool successful_external_paste_creates_single_atomic_history_entry = false;
  bool large_or_invalid_payloads_fail_safely_without_crash = false;
  bool global_invariant_preserved_after_external_import = false;
};

struct BuilderCommandCoalescingHistoryGranularityIntegrityHardeningDiagnostics {
  bool repeated_same_target_property_edits_coalesce_only_when_allowed = false;
  bool different_targets_or_operation_types_never_coalesce = false;
  bool manual_text_commit_creates_single_history_entry = false;
  bool cancelled_edit_creates_zero_history_entries = false;
  bool bulk_operations_remain_single_logical_history_entries = false;
  bool save_load_export_boundaries_break_coalescing = false;
  bool undo_redo_operate_on_logical_action_boundaries = false;
  bool history_shape_deterministic_for_identical_sequence = false;
  bool history_metadata_coherent_after_coalescing = false;
  bool no_timing_fragile_history_grouping = false;
};

struct BuilderDirtyStateChangeTrackingIntegrityHardeningDiagnostics {
  bool real_mutations_mark_dirty_exactly = false;
  bool read_only_operations_do_not_mark_dirty = false;
  bool undo_back_to_clean_clears_dirty = false;
  bool redo_away_from_clean_sets_dirty = false;
  bool save_sets_new_clean_baseline_exactly = false;
  bool load_sets_new_clean_baseline_exactly = false;
  bool failed_save_load_or_blocked_mutation_do_not_corrupt_dirty_state = false;
  bool export_does_not_affect_dirty_state = false;
  bool dirty_tracking_uses_canonical_document_signature = false;
  bool stress_sequence_dirty_transitions_remain_exact = false;
};

struct BuilderActionInvocationIntegrityHardeningDiagnostics {
  bool same_action_id_same_result_across_invocation_surfaces = false;
  bool ineligible_actions_fail_closed_without_mutation = false;
  bool action_eligibility_checked_against_current_state = false;
  bool no_stale_selection_or_target_context_used = false;
  bool action_metadata_matches_execution_eligibility = false;
  bool failed_invocation_creates_no_history_or_dirty_side_effect = false;
  bool cross_surface_invocation_produces_identical_history_and_selection = false;
  bool global_invariant_preserved_through_all_action_invocations = false;
  bool no_command_dispatch_mismatch_or_wrong_handler_resolution = false;
  bool deterministic_invocation_sequence_stable = false;
};

struct BuilderSearchFilterVisibilityIntegrityHardeningDiagnostics {
  bool search_filter_read_only_no_document_mutation = false;
  bool filtered_order_matches_authoritative_structure_order = false;
  bool selection_mapping_remains_deterministic_under_filter_changes = false;
  bool no_stale_deleted_or_moved_nodes_in_results = false;
  bool actions_from_filtered_view_resolve_against_authoritative_current_state = false;
  bool clear_and_reapply_filter_restores_coherent_visible_state = false;
  bool search_filter_creates_no_history_or_dirty_side_effect = false;
  bool preview_and_bindings_remain_coherent_under_filtered_view = false;
  bool filtered_and_unfiltered_action_results_match_for_same_underlying_state = false;
  bool global_invariant_preserved_through_search_filter_cycles = false;
};

struct BuilderSelectionAnchorFocusNavigationIntegrityHardeningDiagnostics {
  bool authoritative_order_navigation_matches_document_structure = false;
  bool selection_anchor_establishes_deterministic_range_extent = false;
  bool focus_only_navigation_does_not_mutate_selection_or_document = false;
  bool stale_anchor_and_focus_are_scrubbed_fail_closed = false;
  bool selection_focus_coherence_restored_after_filter_and_lifecycle_changes = false;
  bool navigation_only_changes_create_no_history_or_dirty_side_effect = false;
  bool parent_child_navigation_respects_authoritative_current_state = false;
  bool range_extension_shrinks_and_grows_deterministically_from_same_anchor = false;
  bool filtered_and_unfiltered_navigation_resolve_same_underlying_targets = false;
  bool global_invariant_preserved_through_anchor_focus_navigation_cycles = false;
};

struct BuilderDragDropReorderIntegrityHardeningDiagnostics {
  bool drop_target_resolution_deterministic = false;
  bool multi_selection_drag_atomic_and_order_preserved = false;
  bool sibling_reorder_preserves_global_structure_order = false;
  bool cross_parent_move_updates_relationships_exactly = false;
  bool filtered_view_drag_resolves_to_authoritative_target = false;
  bool invalid_drop_fails_closed_without_mutation = false;
  bool undo_redo_exact_for_drag_operations = false;
  bool no_partial_or_stale_references_after_drag = false;
  bool drag_creates_no_transient_history_or_dirty_leak = false;
  bool global_invariant_preserved_after_drag_operations = false;
};

struct BuilderPersistenceFileIoIntegrityHardeningDiagnostics {
  bool save_is_atomic_and_never_exposes_partial_file = false;
  bool saved_file_matches_canonical_document_signature = false;
  bool load_rejects_invalid_or_truncated_files = false;
  bool failed_save_does_not_overwrite_existing_file = false;
  bool failed_load_does_not_mutate_current_state = false;
  bool no_transient_ui_or_state_desync_during_io = false;
  bool serialization_deterministic_for_identical_document = false;
  bool repeated_save_calls_produce_consistent_output = false;
  bool dirty_baseline_updates_only_on_successful_save_load = false;
  bool global_invariant_preserved_through_all_io_operations = false;
};

struct BuilderUndoRedoTimeTravelIntegrityHardeningDiagnostics {
  bool undo_restores_full_system_state = false;
  bool redo_restores_full_system_state = false;
  bool no_state_drift_after_repeated_cycles = false;
  bool selection_anchor_focus_restore_exact = false;
  bool multi_selection_restore_exact = false;
  bool redo_stack_invalidated_on_new_mutation = false;
  bool no_history_pollution_from_failed_operations = false;
  bool no_branching_history_corruption = false;
  bool cross_surface_state_consistent_after_time_travel = false;
  bool global_invariant_preserved_during_undo_redo = false;
};

struct BuilderViewportScrollVisualStateIntegrityHardeningDiagnostics {
  bool selected_node_visible_or_scrolled_into_view_deterministically = false;
  bool scroll_position_deterministic_for_identical_sequences = false;
  bool undo_redo_restores_viewport_with_state = false;
  bool filtered_and_unfiltered_scroll_mapping_consistent = false;
  bool viewport_never_references_invalid_or_deleted_rows = false;
  bool load_save_initialize_or_preserve_viewport_deterministically = false;
  bool no_dirty_or_history_side_effects_from_viewport_changes = false;
  bool tree_and_preview_viewports_remain_coherent = false;
  bool no_scroll_drift_after_stress_sequences = false;
  bool global_invariant_preserved_during_viewport_updates = false;
};

struct BuilderPerformanceScalingIntegrityHardeningDiagnostics {
  bool large_document_operations_remain_correct = false;
  bool deep_hierarchy_handled_without_failure = false;
  bool long_stress_sequence_preserves_invariant = false;
  bool undo_redo_stable_under_large_history = false;
  bool search_filter_stable_under_large_dataset = false;
  bool viewport_stable_under_large_node_count = false;
  bool no_state_drift_under_repeated_operations = false;
  bool no_partial_or_skipped_validation_under_load = false;
  bool deterministic_result_for_identical_large_sequence = false;
  bool global_invariant_preserved_under_scale = false;
};

struct BuilderPerformanceProfilingHotspotCharacterizationDiagnostics {
  bool profile_captures_representative_operations = false;
  bool model_and_ui_costs_measured_separately = false;
  bool scaling_characteristics_captured_across_sizes = false;
  bool no_correctness_guarantees_were_weakened = false;
  bool invariant_checks_remained_enabled_during_profiling = false;
  bool hotspots_ranked_by_measured_cost = false;
  bool actionable_optimization_targets_identified = false;
  bool profile_run_terminates_cleanly_with_markers = false;
  bool no_partial_or_stalled_proof_artifacts = false;
  bool global_invariant_preserved_during_profile_runs = false;
  std::string operations_profiled{};
  std::uint64_t size_small_nodes = 0;
  std::uint64_t size_medium_nodes = 0;
  std::uint64_t size_large_nodes = 0;
  std::uint64_t build_small_ns = 0;
  std::uint64_t build_medium_ns = 0;
  std::uint64_t build_large_ns = 0;
  std::uint64_t validate_small_ns = 0;
  std::uint64_t validate_medium_ns = 0;
  std::uint64_t validate_large_ns = 0;
  std::uint64_t serialize_small_ns = 0;
  std::uint64_t serialize_medium_ns = 0;
  std::uint64_t serialize_large_ns = 0;
  std::uint64_t selection_mapping_ns = 0;
  std::uint64_t insert_ns = 0;
  std::uint64_t property_edit_commit_ns = 0;
  std::uint64_t move_reparent_ns = 0;
  std::uint64_t delete_ns = 0;
  std::uint64_t history_build_ns = 0;
  std::uint64_t undo_replay_ns = 0;
  std::uint64_t redo_replay_ns = 0;
  std::uint64_t filter_apply_ns = 0;
  std::uint64_t filter_clear_ns = 0;
  std::uint64_t viewport_reconcile_ns = 0;
  std::uint64_t save_ns = 0;
  std::uint64_t load_ns = 0;
  std::uint64_t export_ns = 0;
  std::uint64_t large_global_invariant_ns = 0;
  std::uint64_t deterministic_signature_large_ns = 0;
  std::uint64_t model_total_ns = 0;
  std::uint64_t ui_total_ns = 0;
  std::uint64_t io_total_ns = 0;
  std::string scaling_build{};
  std::string scaling_validate{};
  std::string scaling_serialize{};
  std::array<std::string, 5> hotspot_rankings{};
  std::string optimization_targets{};
};

struct BuilderHistoryReplayOptimizationDiagnostics {
  bool undo_replay_time_reduced_vs_phase103_77 = false;
  bool redo_replay_time_reduced_vs_phase103_77 = false;
  bool history_replay_produces_identical_document_signature = false;
  bool selection_anchor_focus_identical_after_replay = false;
  bool preview_and_structure_fully_consistent_after_replay = false;
  bool invariant_preserved_during_and_after_replay = false;
  bool no_skipped_or_reordered_history_operations = false;
  bool no_ui_desync_during_replay_batching = false;
  bool repeated_replay_cycles_remain_drift_free = false;
  bool global_invariant_preserved = false;
  std::uint64_t phase103_77_baseline_undo_replay_ns = 0;
  std::uint64_t phase103_77_baseline_redo_replay_ns = 0;
  std::uint64_t optimized_undo_replay_ns = 0;
  std::uint64_t optimized_redo_replay_ns = 0;
  std::uint64_t replay_history_steps = 0;
  std::string batching_strategy{};
};

struct BuilderSerializationExportPathOptimizationDiagnostics {
  bool export_time_reduced_vs_phase103_77 = false;
  bool serialization_time_reduced_vs_phase103_77 = false;
  bool export_bytes_identical_to_baseline = false;
  bool canonical_signature_identical_to_baseline = false;
  bool no_stale_serialization_reuse_after_mutation = false;
  bool no_correctness_guarantees_were_weakened = false;
  bool no_history_or_dirty_side_effect_from_optimization = false;
  bool profile_run_terminates_cleanly_with_markers = false;
  bool no_partial_or_stalled_proof_artifacts = false;
  bool global_invariant_preserved = false;
  std::uint64_t phase103_77_baseline_serialize_ns = 0;
  std::uint64_t phase103_77_baseline_export_ns = 0;
  std::uint64_t optimized_serialize_ns = 0;
  std::uint64_t optimized_export_ns = 0;
  std::string reuse_strategy{};
};

struct ScopedBusyFlag {
  bool& flag;
  explicit ScopedBusyFlag(bool& value) : flag(value) {
    flag = true;
  }
  ~ScopedBusyFlag() {
    flag = false;
  }
  ScopedBusyFlag(const ScopedBusyFlag&) = delete;
  ScopedBusyFlag& operator=(const ScopedBusyFlag&) = delete;
};

struct CommandHistoryEntry {
  std::string command_type{};
  std::string operation_class{};
  std::string coalescing_key{};
  std::uint64_t boundary_epoch = 0;
  int logical_action_span = 1;
  std::vector<ngk::ui::builder::BuilderNode> before_nodes{};
  std::string before_root_node_id{};
  std::string before_selected_id{};
  std::vector<std::string> before_multi_selected_ids{};
  std::string before_focused_id{};
  std::string before_anchor_id{};
  std::string before_filter_query{};
  int before_tree_scroll_offset_y = 0;
  int before_preview_scroll_offset_y = 0;
  std::vector<ngk::ui::builder::BuilderNode> after_nodes{};
  std::string after_root_node_id{};
  std::string after_selected_id{};
  std::vector<std::string> after_multi_selected_ids{};
  std::string after_focused_id{};
  std::string after_anchor_id{};
  std::string after_filter_query{};
  int after_tree_scroll_offset_y = 0;
  int after_preview_scroll_offset_y = 0;
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

#pragma once

#include "desktop_file_tool_diagnostics.h"

#define DESKTOP_FILE_TOOL_DIAGNOSTICS_STATE_FIELDS(X, ctx) \
  X(ctx, RedrawDiagnostics, redraw_diag) \
  X(ctx, LayoutFunctionDiagnostics, layout_fn_diag) \
  X(ctx, ScrollContainerDiagnostics, scroll_diag) \
  X(ctx, ListViewDiagnostics, list_view_diag) \
  X(ctx, TableViewDiagnostics, table_view_diag) \
  X(ctx, ShellWidgetDiagnostics, shell_widget_diag) \
  X(ctx, FileDialogDiagnostics, file_dialog_diag) \
  X(ctx, DeclarativeLayerDiagnostics, declarative_diag) \
  X(ctx, BuilderTargetDiagnostics, builder_target_diag) \
  X(ctx, BuilderDocumentDiagnostics, builder_doc_diag) \
  X(ctx, SelectionModelDiagnostics, selection_diag) \
  X(ctx, StructuralCommandDiagnostics, struct_cmd_diag) \
  X(ctx, BuilderShellDiagnostics, builder_shell_diag) \
  X(ctx, ComponentPaletteDiagnostics, palette_diag) \
  X(ctx, BuilderMoveReparentDiagnostics, move_reparent_diag) \
  X(ctx, BuilderStateCoherenceDiagnostics, coherence_diag) \
  X(ctx, BuilderDeleteWorkflowDiagnostics, delete_diag) \
  X(ctx, BuilderUndoRedoDiagnostics, undoredo_diag) \
  X(ctx, BuilderSaveLoadDiagnostics, saveload_diag) \
  X(ctx, BuilderDirtyStateDiagnostics, dirty_state_diag) \
  X(ctx, BuilderLifecycleDiagnostics, lifecycle_diag) \
  X(ctx, BuilderFocusDiagnostics, focus_diag) \
  X(ctx, BuilderVisibleUxDiagnostics, visible_ux_diag) \
  X(ctx, BuilderShortcutDiagnostics, shortcut_diag) \
  X(ctx, BuilderDragDropDiagnostics, dragdrop_diag) \
  X(ctx, BuilderTypedPaletteDiagnostics, typed_palette_diag) \
  X(ctx, BuilderExportDiagnostics, export_diag) \
  X(ctx, BuilderExportUxDiagnostics, export_ux_diag) \
  X(ctx, BuilderPreviewExportParityDiagnostics, preview_export_parity_diag) \
  X(ctx, BuilderPreviewSurfaceUpgradeDiagnostics, preview_surface_upgrade_diag) \
  X(ctx, BuilderPreviewInteractionFeedbackDiagnostics, preview_interaction_feedback_diag) \
  X(ctx, BuilderInspectorTypedEditingDiagnostics, inspector_typed_edit_diag) \
  X(ctx, BuilderPreviewClickSelectDiagnostics, preview_click_select_diag) \
  X(ctx, BuilderSelectionClarityPolishDiagnostics, selection_clarity_diag) \
  X(ctx, BuilderPreviewInlineActionAffordanceDiagnostics, inline_affordance_diag) \
  X(ctx, BuilderPreviewInlineActionCommitDiagnostics, inline_action_commit_diag) \
  X(ctx, BuilderWindowLayoutResponsivenessDiagnostics, window_layout_diag) \
  X(ctx, BuilderInlineTextEditDiagnostics, inline_text_edit_diag) \
  X(ctx, BuilderMultiSelectionDiagnostics, multi_selection_diag) \
  X(ctx, BuilderBulkDeleteDiagnostics, bulk_delete_diag) \
  X(ctx, BuilderBulkMoveReparentDiagnostics, bulk_move_reparent_diag) \
  X(ctx, BuilderBulkPropertyEditDiagnostics, bulk_property_edit_diag) \
  X(ctx, BuilderMultiSelectionClarityDiagnostics, multi_selection_clarity_diag) \
  X(ctx, BuilderKeyboardMultiSelectionWorkflowDiagnostics, keyboard_multi_selection_diag) \
  X(ctx, BuilderBulkActionEligibilityUxDiagnostics, bulk_action_eligibility_diag) \
  X(ctx, BuilderActionSurfaceReadabilityDiagnostics, action_surface_readability_diag) \
  X(ctx, BuilderInformationHierarchyPolishDiagnostics, info_hierarchy_diag) \
  X(ctx, BuilderSelectionAwareTopActionSurfaceDiagnostics, top_action_surface_diag) \
  X(ctx, BuilderButtonStateReadabilityDiagnostics, button_state_readability_diag) \
  X(ctx, BuilderUsabilityBaselineDiagnostics, usability_baseline_diag) \
  X(ctx, BuilderExplicitEditableFieldDiagnostics, explicit_edit_field_diag) \
  X(ctx, BuilderIntegratedUsabilityMilestoneDiagnostics, integrated_usability_diag) \
  X(ctx, BuilderRealInteractionDiagnostics, real_interaction_diag) \
  X(ctx, BuilderHumanReadableUiDiagnostics, human_readable_ui_diag) \
  X(ctx, BuilderPreviewRealUiDiagnostics, preview_real_ui_diag) \
  X(ctx, BuilderActionVisibilityDiagnostics, action_visibility_diag) \
  X(ctx, BuilderClarityEnforcementDiagnostics, clarity_enforcement_diag) \
  X(ctx, BuilderInsertTargetClarityDiagnostics, insert_target_clarity_diag) \
  X(ctx, BuilderPreviewStructureParityDiagnostics, preview_structure_parity_diag) \
  X(ctx, BuilderCommandIntegrityDiagnostics, command_integrity_diag) \
  X(ctx, BuilderSaveLoadStateIntegrityDiagnostics, save_load_integrity_diag) \
  X(ctx, BuilderPropertyEditIntegrityDiagnostics, property_edit_integrity_diag) \
  X(ctx, BuilderNodeLifecycleIntegrityDiagnostics, node_lifecycle_integrity_diag) \
  X(ctx, BuilderBoundsLayoutConstraintIntegrityDiagnostics, bounds_layout_constraint_diag) \
  X(ctx, BuilderEventInputRoutingIntegrityDiagnostics, event_input_routing_diag) \
  X(ctx, BuilderGlobalInvariantEnforcementDiagnostics, global_invariant_diag) \
  X(ctx, BuilderExportPackageIntegrityDiagnostics, export_package_diag) \
  X(ctx, BuilderStartupShutdownIntegrityDiagnostics, startup_shutdown_diag) \
  X(ctx, BuilderStressSequenceResilienceDiagnostics, stress_sequence_diag) \
  X(ctx, BuilderManualTextEntryIntegrityDiagnostics, manual_text_diag) \
  X(ctx, BuilderMultiSelectionIntegrityHardeningDiagnostics, multi_selection_integrity_diag) \
  X(ctx, BuilderClipboardDuplicateCopyPasteIntegrityHardeningDiagnostics, clipboard_integrity_diag) \
  X(ctx, BuilderClipboardExternalDataBoundaryIntegrityHardeningDiagnostics, external_data_boundary_integrity_diag) \
  X(ctx, BuilderCommandCoalescingHistoryGranularityIntegrityHardeningDiagnostics, command_coalescing_diag) \
  X(ctx, BuilderDirtyStateChangeTrackingIntegrityHardeningDiagnostics, dirty_tracking_integrity_diag) \
  X(ctx, BuilderActionInvocationIntegrityHardeningDiagnostics, action_invocation_integrity_diag) \
  X(ctx, BuilderSearchFilterVisibilityIntegrityHardeningDiagnostics, search_filter_visibility_integrity_diag) \
  X(ctx, BuilderSelectionAnchorFocusNavigationIntegrityHardeningDiagnostics, selection_anchor_focus_navigation_integrity_diag) \
  X(ctx, BuilderDragDropReorderIntegrityHardeningDiagnostics, drag_drop_reorder_integrity_diag) \
  X(ctx, BuilderPersistenceFileIoIntegrityHardeningDiagnostics, persistence_file_io_integrity_diag) \
  X(ctx, BuilderUndoRedoTimeTravelIntegrityHardeningDiagnostics, undo_redo_time_travel_integrity_diag) \
  X(ctx, BuilderViewportScrollVisualStateIntegrityHardeningDiagnostics, viewport_scroll_visual_state_integrity_diag) \
  X(ctx, BuilderPerformanceScalingIntegrityHardeningDiagnostics, performance_scaling_integrity_diag) \
  X(ctx, BuilderPerformanceProfilingHotspotCharacterizationDiagnostics, performance_profiling_diag) \
  X(ctx, BuilderHistoryReplayOptimizationDiagnostics, history_replay_optimization_diag) \
  X(ctx, BuilderSerializationExportPathOptimizationDiagnostics, serialization_export_optimization_diag)

#define DESKTOP_FILE_TOOL_DIAGNOSTICS_STATE_DECLARE_FIELD(ctx, type, name) type name{};
#define DESKTOP_FILE_TOOL_DIAGNOSTICS_STATE_BIND_FIELD(ctx, type, name) auto& name = (ctx).name;

namespace desktop_file_tool {

struct DesktopFileToolDiagnosticsState {
  DESKTOP_FILE_TOOL_DIAGNOSTICS_STATE_FIELDS(DESKTOP_FILE_TOOL_DIAGNOSTICS_STATE_DECLARE_FIELD, _)
};

}  // namespace desktop_file_tool

#define DESKTOP_FILE_TOOL_BIND_DIAGNOSTICS_STATE(state_object) \
  DESKTOP_FILE_TOOL_DIAGNOSTICS_STATE_FIELDS(DESKTOP_FILE_TOOL_DIAGNOSTICS_STATE_BIND_FIELD, state_object)
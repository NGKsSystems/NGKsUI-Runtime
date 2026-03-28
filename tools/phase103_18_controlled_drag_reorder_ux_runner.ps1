#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

$expectedWorkspace = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
$workspaceRoot = (Get-Location).Path
if ($workspaceRoot -ne $expectedWorkspace) {
  Write-Host 'wrong workspace for phase103_18 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_18_controlled_drag_reorder_ux_${timestamp}_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$($proofName).zip"

$checksFile = Join-Path $stageRoot '90_controlled_drag_reorder_ux_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'
$uiElementPath = Join-Path $workspaceRoot 'engine/ui/ui_element.hpp'
$rendererHeaderPath = Join-Path $workspaceRoot 'engine/gfx/win32/include/ngk/gfx/d3d11_renderer.hpp'
$rendererSourcePath = Join-Path $workspaceRoot 'engine/gfx/win32/src/d3d11_renderer.cpp'

$failureCategory = 'none'
$failureReason = ''

$requiredApiPreflightPresent = $false
$buildPreconditionsHardened = $false
$builderCapabilityIntegrityChecksPresent = $false
$failureCategoriesExplicit = $true

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

function Remove-PathIfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Test-LinePresent {
  param([string]$Text, [string]$Pattern)
  return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
}

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

function Fail-Closed {
  param([string]$Category, [string]$Reason, [string]$LogPath = '')

  $script:failureCategory = $Category
  $script:failureReason = $Reason

  if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    Add-Content -LiteralPath $LogPath -Value ("failure_category=$Category")
    Add-Content -LiteralPath $LogPath -Value ("failure_reason=$Reason")
  }

  Write-Host "failure_category=$Category"
  Write-Host "failure_reason=$Reason"
  throw $Reason
}

function Assert-RequiredPatterns {
  param(
    [string]$SourceText,
    [array]$Checks,
    [string]$Category,
    [string]$LogPath,
    [string]$ContextName
  )

  $missing = @()
  foreach ($check in $Checks) {
    if ($SourceText -notmatch $check.pattern) {
      $missing += $check.name
    }
  }

  if ($missing.Count -gt 0) {
    $missingSummary = ($missing -join ', ')
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
      Add-Content -LiteralPath $LogPath -Value ("missing_$ContextName=$missingSummary")
    }
    Fail-Closed -Category $Category -Reason ("missing required ${ContextName}: $missingSummary") -LogPath $LogPath
  }
}

function Ensure-PlanOutputDirectories {
  param([object]$PlanJson, [string]$LogPath)

  $created = 0
  foreach ($node in $PlanJson.nodes) {
    foreach ($output in $node.outputs) {
      if ([string]::IsNullOrWhiteSpace($output)) {
        continue
      }
      $dir = Split-Path -Path $output -Parent
      if ([string]::IsNullOrWhiteSpace($dir)) {
        continue
      }
      if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $created += 1
      }
    }
  }

  Add-Content -LiteralPath $LogPath -Value ("precreated_output_directories=$created")
}

function Invoke-CmdChecked {
  param([string]$CommandLine, [string]$LogPath, [string]$StepName)
  Add-Content -LiteralPath $LogPath -Value ("STEP=$StepName")
  cmd /c $CommandLine *>&1 | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
  if ($LASTEXITCODE -ne 0) {
    if ($StepName -like 'Compile*') {
      Fail-Closed -Category 'compile_failed' -Reason "$StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
    }
    if ($StepName -like 'Link*') {
      Fail-Closed -Category 'compile_failed' -Reason "$StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
    }
    Fail-Closed -Category 'build_precondition_failed' -Reason "$StepName failed with exit code $LASTEXITCODE" -LogPath $LogPath
  }
}

if (-not (Test-Path -LiteralPath $mainPath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'desktop_file_tool main.cpp missing' -LogPath $buildOut
}

if (-not (Test-Path -LiteralPath $uiElementPath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'engine/ui/ui_element.hpp missing' -LogPath $buildOut
}
if (-not (Test-Path -LiteralPath $rendererHeaderPath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'd3d11_renderer.hpp missing' -LogPath $buildOut
}
if (-not (Test-Path -LiteralPath $rendererSourcePath)) {
  Fail-Closed -Category 'feature_missing' -Reason 'd3d11_renderer.cpp missing' -LogPath $buildOut
}

$uiElementText = Get-Content -LiteralPath $uiElementPath -Raw
Assert-RequiredPatterns -SourceText $uiElementText -Checks @(
  @{ name = 'LayoutSizePolicy enum'; pattern = 'enum class LayoutSizePolicy' },
  @{ name = 'set_min_size API'; pattern = 'set_min_size\s*\(' },
  @{ name = 'min_width API'; pattern = 'min_width\s*\(' },
  @{ name = 'min_height API'; pattern = 'min_height\s*\(' },
  @{ name = 'set_layout_width_policy API'; pattern = 'set_layout_width_policy\s*\(' },
  @{ name = 'set_layout_height_policy API'; pattern = 'set_layout_height_policy\s*\(' },
  @{ name = 'set_layout_weight API'; pattern = 'set_layout_weight\s*\(' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'builder_runtime_apis'

$rendererHeaderText = Get-Content -LiteralPath $rendererHeaderPath -Raw
Assert-RequiredPatterns -SourceText $rendererHeaderText -Checks @(
  @{ name = 'set_clip_rect declaration'; pattern = 'set_clip_rect\s*\(' },
  @{ name = 'reset_clip_rect declaration'; pattern = 'reset_clip_rect\s*\(' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'builder_runtime_apis'

$rendererSourceText = Get-Content -LiteralPath $rendererSourcePath -Raw
Assert-RequiredPatterns -SourceText $rendererSourceText -Checks @(
  @{ name = 'set_clip_rect implementation'; pattern = 'D3D11Renderer::set_clip_rect\s*\(' },
  @{ name = 'reset_clip_rect implementation'; pattern = 'D3D11Renderer::reset_clip_rect\s*\(' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'builder_runtime_apis'

$requiredApiPreflightPresent = $true

$mainText = Get-Content -LiteralPath $mainPath -Raw
Assert-RequiredPatterns -SourceText $mainText -Checks @(
  @{ name = 'phase103_17 marker'; pattern = 'phase103_17_keyboard_tree_navigation_present' },
  @{ name = 'phase103_18 marker'; pattern = 'phase103_18_tree_drag_reorder_present' },
  @{ name = 'BuilderDragDropDiagnostics struct'; pattern = 'BuilderDragDropDiagnostics' },
  @{ name = 'is_in_subtree_of lambda'; pattern = 'is_in_subtree_of' },
  @{ name = 'begin_tree_drag lambda'; pattern = 'begin_tree_drag' },
  @{ name = 'cancel_tree_drag lambda'; pattern = 'cancel_tree_drag' },
  @{ name = 'is_legal_drop_target_reorder lambda'; pattern = 'is_legal_drop_target_reorder' },
  @{ name = 'is_legal_drop_target_reparent lambda'; pattern = 'is_legal_drop_target_reparent' },
  @{ name = 'commit_tree_drag_reorder lambda'; pattern = 'commit_tree_drag_reorder' },
  @{ name = 'commit_tree_drag_reparent lambda'; pattern = 'commit_tree_drag_reparent' },
  @{ name = 'reject_illegal_tree_drag_drop lambda'; pattern = 'reject_illegal_tree_drag_drop' },
  @{ name = 'run_phase103_18 flow'; pattern = 'run_phase103_18' },
  @{ name = 'drag_source_node_id state'; pattern = 'drag_source_node_id' },
  @{ name = 'drag_active state'; pattern = 'drag_active' },
  @{ name = 'drag_reorder history entry'; pattern = 'drag_reorder' },
  @{ name = 'drag_reparent history entry'; pattern = 'drag_reparent' },
  @{ name = 'phase103_2 marker'; pattern = 'phase103_2_builder_document_defined' },
  @{ name = 'phase103_9 marker'; pattern = 'phase103_9_selection_coherence_hardened' },
  @{ name = 'phase103_17 keyboard nav marker'; pattern = 'phase103_17_keyboard_tree_navigation_present' },
  @{ name = 'apply_move_sibling_up'; pattern = 'apply_move_sibling_up' },
  @{ name = 'apply_move_sibling_down'; pattern = 'apply_move_sibling_down' },
  @{ name = 'apply_reparent_legal'; pattern = 'apply_reparent_legal' },
  @{ name = 'push_to_history'; pattern = 'push_to_history' },
  @{ name = 'apply_undo_command'; pattern = 'apply_undo_command' },
  @{ name = 'apply_redo_command'; pattern = 'apply_redo_command' },
  @{ name = 'apply_save_document_command'; pattern = 'apply_save_document_command' },
  @{ name = 'apply_load_document_command'; pattern = 'apply_load_document_command' },
  @{ name = 'apply_new_document_command'; pattern = 'apply_new_document_command' },
  @{ name = 'remap_selection_or_fail'; pattern = 'remap_selection_or_fail' },
  @{ name = 'sync_focus_with_selection_or_fail'; pattern = 'sync_focus_with_selection_or_fail' },
  @{ name = 'refresh_inspector_or_fail'; pattern = 'refresh_inspector_or_fail' },
  @{ name = 'refresh_preview_or_fail'; pattern = 'refresh_preview_or_fail' },
  @{ name = 'check_cross_surface_sync'; pattern = 'check_cross_surface_sync' },
  @{ name = 'recompute_builder_dirty_state'; pattern = 'recompute_builder_dirty_state' },
  @{ name = 'handle_builder_shortcut_key'; pattern = 'handle_builder_shortcut_key' },
  @{ name = 'apply_tree_parent_child_navigation'; pattern = 'apply_tree_parent_child_navigation' }
) -Category 'feature_missing' -LogPath $buildOut -ContextName 'phase103_18_capabilities'

$builderCapabilityIntegrityChecksPresent = $true

& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
  Out-File -LiteralPath $buildOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'build_precondition_failed' -Reason 'desktop_file_tool build-plan generation failed' -LogPath $buildOut
}

if (-not (Test-Path -LiteralPath $planPath)) {
  Fail-Closed -Category 'build_precondition_failed' -Reason 'desktop_file_tool build plan missing' -LogPath $buildOut
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]

if ($engineCompileNodes.Count -eq 0 -or $null -eq $appCompileNode -or $null -eq $engineLibNode -or $null -eq $appLinkNode) {
  Fail-Closed -Category 'build_precondition_failed' -Reason 'required compile/link nodes missing from build plan' -LogPath $buildOut
}

Ensure-PlanOutputDirectories -PlanJson $planJson -LogPath $buildOut
$buildPreconditionsHardened = $true

& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 |
  Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -LogPath $buildOut -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -LogPath $buildOut -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd -LogPath $buildOut -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd -LogPath $buildOut -StepName $appLinkNode.desc

if (-not (Test-Path -LiteralPath $exePath)) {
  Fail-Closed -Category 'compile_failed' -Reason 'desktop_file_tool executable missing after compile/link' -LogPath $buildOut
}

& $exePath --validation-mode --auto-close-ms=9800 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  Fail-Closed -Category 'runtime_validation_failed' -Reason "desktop_file_tool validation run failed (exit $LASTEXITCODE)" -LogPath $runOut
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

# --- PHASE103_18 markers ---
$phase103_18_treeDragReorderPresent      = Test-LinePresent -Text $runText -Pattern '^phase103_18_tree_drag_reorder_present=1$'
$phase103_18_legalReorderDropApplied     = Test-LinePresent -Text $runText -Pattern '^phase103_18_legal_reorder_drop_applied=1$'
$phase103_18_legalReparentDropApplied    = Test-LinePresent -Text $runText -Pattern '^phase103_18_legal_reparent_drop_applied=1$'
$phase103_18_illegalDropRejected         = Test-LinePresent -Text $runText -Pattern '^phase103_18_illegal_drop_rejected=1$'
$phase103_18_draggedNodeSelectionPreserved = Test-LinePresent -Text $runText -Pattern '^phase103_18_dragged_node_selection_preserved=1$'
$phase103_18_shellStateStillCoherent     = Test-LinePresent -Text $runText -Pattern '^phase103_18_shell_state_still_coherent=1$'
$phase103_18_layoutAuditStillCompatible  = Test-LinePresent -Text $runText -Pattern '^phase103_18_layout_audit_still_compatible=1$'

$phase103_18_ok =
  $phase103_18_treeDragReorderPresent -and
  $phase103_18_legalReorderDropApplied -and
  $phase103_18_legalReparentDropApplied -and
  $phase103_18_illegalDropRejected -and
  $phase103_18_draggedNodeSelectionPreserved -and
  $phase103_18_shellStateStillCoherent -and
  $phase103_18_layoutAuditStillCompatible

# --- Regression markers (PHASE103_17 and earlier) ---
$keyboardTreeNavigationPresent = Test-LinePresent -Text $runText -Pattern '^phase103_17_keyboard_tree_navigation_present=1$'
$shortcutScopeRulesDefined = Test-LinePresent -Text $runText -Pattern '^phase103_17_shortcut_scope_rules_defined=1$'
$undoRedoShortcutsWork = Test-LinePresent -Text $runText -Pattern '^phase103_17_undo_redo_shortcuts_work=1$'
$insertDeleteShortcutsWork = Test-LinePresent -Text $runText -Pattern '^phase103_17_insert_delete_shortcuts_work=1$'
$guardedLifecycleShortcutsSafe = Test-LinePresent -Text $runText -Pattern '^phase103_17_guarded_lifecycle_shortcuts_safe=1$'
$phase103_17_shellStateStillCoherent = Test-LinePresent -Text $runText -Pattern '^phase103_17_shell_state_still_coherent=1$'
$phase103_17_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_17_layout_audit_still_compatible=1$'

$phase103_17_ok =
  $keyboardTreeNavigationPresent -and
  $shortcutScopeRulesDefined -and
  $undoRedoShortcutsWork -and
  $insertDeleteShortcutsWork -and
  $guardedLifecycleShortcutsSafe -and
  $phase103_17_shellStateStillCoherent -and
  $phase103_17_layoutAuditStillCompatible

$treeHierarchyVisibilityImproved = Test-LinePresent -Text $runText -Pattern '^phase103_16_tree_hierarchy_visibility_improved=1$'
$selectedNodeVisibilityInTreeImproved = Test-LinePresent -Text $runText -Pattern '^phase103_16_selected_node_visibility_in_tree_improved=1$'
$previewReadabilityImproved = Test-LinePresent -Text $runText -Pattern '^phase103_16_preview_readability_improved=1$'
$selectedNodeVisibilityInPreviewImproved = Test-LinePresent -Text $runText -Pattern '^phase103_16_selected_node_visibility_in_preview_improved=1$'
$shellRegionsClearlyLabeled = Test-LinePresent -Text $runText -Pattern '^phase103_16_shell_regions_clearly_labeled=1$'
$shellStateStillCoherent = Test-LinePresent -Text $runText -Pattern '^phase103_16_shell_state_still_coherent=1$'
$phase103_16_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_16_layout_audit_still_compatible=1$'

$phase103_16_ok =
  $treeHierarchyVisibilityImproved -and
  $selectedNodeVisibilityInTreeImproved -and
  $previewReadabilityImproved -and
  $selectedNodeVisibilityInPreviewImproved -and
  $shellRegionsClearlyLabeled -and
  $shellStateStillCoherent -and
  $phase103_16_layoutAuditStillCompatible

$focusSelectionRulesDefined = Test-LinePresent -Text $runText -Pattern '^phase103_15_focus_selection_rules_defined=1$'
$postOperationFocusDeterministic = Test-LinePresent -Text $runText -Pattern '^phase103_15_post_operation_focus_deterministic=1$'
$treeNavigationCoherent = Test-LinePresent -Text $runText -Pattern '^phase103_15_tree_navigation_coherent=1$'
$staleFocusRejected = Test-LinePresent -Text $runText -Pattern '^phase103_15_stale_focus_rejected=1$'
$inspectorFocusSafe = Test-LinePresent -Text $runText -Pattern '^phase103_15_inspector_focus_safe=1$'
$shellStateCoherentAfterFocusChanges = Test-LinePresent -Text $runText -Pattern '^phase103_15_shell_state_coherent_after_focus_changes=1$'
$phase103_15_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_15_layout_audit_still_compatible=1$'

$phase103_15_ok =
  $focusSelectionRulesDefined -and
  $postOperationFocusDeterministic -and
  $treeNavigationCoherent -and
  $staleFocusRejected -and
  $inspectorFocusSafe -and
  $shellStateCoherentAfterFocusChanges -and
  $phase103_15_layoutAuditStillCompatible

$newDocumentControlPresent = Test-LinePresent -Text $runText -Pattern '^phase103_14_new_document_control_present=1$'
$newDocumentCreatesValidBuilderDoc = Test-LinePresent -Text $runText -Pattern '^phase103_14_new_document_creates_valid_builder_doc=1$'
$unsafeNewOverDirtyStateGuarded = Test-LinePresent -Text $runText -Pattern '^phase103_14_unsafe_new_over_dirty_state_guarded=1$'
$explicitSafeNewPathWorks = Test-LinePresent -Text $runText -Pattern '^phase103_14_explicit_safe_new_path_works=1$'
$historyClearedOnNew = Test-LinePresent -Text $runText -Pattern '^phase103_14_history_cleared_on_new=1$'
$dirtyStateCleanOnNew = Test-LinePresent -Text $runText -Pattern '^phase103_14_dirty_state_clean_on_new=1$'
$shellStateCoherentAfterNew = Test-LinePresent -Text $runText -Pattern '^phase103_14_shell_state_coherent_after_new=1$'
$phase103_14_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_14_layout_audit_still_compatible=1$'

$phase103_14_ok =
  $newDocumentControlPresent -and
  $newDocumentCreatesValidBuilderDoc -and
  $unsafeNewOverDirtyStateGuarded -and
  $explicitSafeNewPathWorks -and
  $historyClearedOnNew -and
  $dirtyStateCleanOnNew -and
  $shellStateCoherentAfterNew -and
  $phase103_14_layoutAuditStillCompatible

$dirtyStateTrackingPresent = Test-LinePresent -Text $runText -Pattern '^phase103_13_dirty_state_tracking_present=1$'
$editMarksDirty = Test-LinePresent -Text $runText -Pattern '^phase103_13_edit_marks_dirty=1$'
$saveMarksClean = Test-LinePresent -Text $runText -Pattern '^phase103_13_save_marks_clean=1$'
$loadMarksClean = Test-LinePresent -Text $runText -Pattern '^phase103_13_load_marks_clean=1$'
$rejectedOpsDoNotChangeDirtyState = Test-LinePresent -Text $runText -Pattern '^phase103_13_rejected_ops_do_not_change_dirty_state=1$'
$unsafeLoadOverDirtyStateGuarded = Test-LinePresent -Text $runText -Pattern '^phase103_13_unsafe_load_over_dirty_state_guarded=1$'
$explicitSafeLoadPathWorks = Test-LinePresent -Text $runText -Pattern '^phase103_13_explicit_safe_load_path_works=1$'
$shellStateCoherentAfterGuardedLoad = Test-LinePresent -Text $runText -Pattern '^phase103_13_shell_state_coherent_after_guarded_load=1$'
$phase103_13_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_13_layout_audit_still_compatible=1$'

$phase103_13_ok =
  $dirtyStateTrackingPresent -and
  $editMarksDirty -and
  $saveMarksClean -and
  $loadMarksClean -and
  $rejectedOpsDoNotChangeDirtyState -and
  $unsafeLoadOverDirtyStateGuarded -and
  $explicitSafeLoadPathWorks -and
  $shellStateCoherentAfterGuardedLoad -and
  $phase103_13_layoutAuditStillCompatible

$shellSaveControlPresent = Test-LinePresent -Text $runText -Pattern '^phase103_12_shell_save_control_present=1$'
$shellLoadControlPresent = Test-LinePresent -Text $runText -Pattern '^phase103_12_shell_load_control_present=1$'
$saveWritesDeterministicDocument = Test-LinePresent -Text $runText -Pattern '^phase103_12_save_writes_deterministic_document=1$'
$loadRestoresDocumentState = Test-LinePresent -Text $runText -Pattern '^phase103_12_load_restores_document_state=1$'
$invalidLoadRejected = Test-LinePresent -Text $runText -Pattern '^phase103_12_invalid_load_rejected=1$'
$historyClearedOnLoad = Test-LinePresent -Text $runText -Pattern '^phase103_12_history_cleared_or_handled_deterministically_on_load=1$'
$shellStateCoherentAfterLoad = Test-LinePresent -Text $runText -Pattern '^phase103_12_shell_state_coherent_after_load=1$'
$phase103_12_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_12_layout_audit_still_compatible=1$'

$phase103_12_ok =
  $shellSaveControlPresent -and
  $shellLoadControlPresent -and
  $saveWritesDeterministicDocument -and
  $loadRestoresDocumentState -and
  $invalidLoadRejected -and
  $historyClearedOnLoad -and
  $shellStateCoherentAfterLoad -and
  $phase103_12_layoutAuditStillCompatible

$selectionCoherenceHardened = Test-LinePresent -Text $runText -Pattern '^phase103_9_selection_coherence_hardened=1$'
$staleSelectionRejected = Test-LinePresent -Text $runText -Pattern '^phase103_9_stale_selection_rejected=1$'
$inspectorCoherenceHardened = Test-LinePresent -Text $runText -Pattern '^phase103_9_inspector_coherence_hardened=1$'
$staleInspectorBindingRejected = Test-LinePresent -Text $runText -Pattern '^phase103_9_stale_inspector_binding_rejected=1$'
$previewCoherenceHardened = Test-LinePresent -Text $runText -Pattern '^phase103_9_preview_coherence_hardened=1$'
$crossSurfaceSyncChecksPresent = Test-LinePresent -Text $runText -Pattern '^phase103_9_cross_surface_sync_checks_present=1$'
$chainedOperationStateStable = Test-LinePresent -Text $runText -Pattern '^phase103_9_chained_operation_state_stable=1$'
$phase103_9_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_9_layout_audit_still_compatible=1$'
$desyncTreeSelectionDetected = Test-LinePresent -Text $runText -Pattern '^phase103_9_desync_tree_selection_detected=1$'
$desyncInspectorBindingDetected = Test-LinePresent -Text $runText -Pattern '^phase103_9_desync_inspector_binding_detected=1$'
$desyncPreviewBindingDetected = Test-LinePresent -Text $runText -Pattern '^phase103_9_desync_preview_binding_detected=1$'
$noCrossSurfaceDesync = -not $desyncTreeSelectionDetected -and -not $desyncInspectorBindingDetected -and -not $desyncPreviewBindingDetected

$phase103_9_ok =
  $selectionCoherenceHardened -and
  $staleSelectionRejected -and
  $inspectorCoherenceHardened -and
  $staleInspectorBindingRejected -and
  $previewCoherenceHardened -and
  $crossSurfaceSyncChecksPresent -and
  $chainedOperationStateStable -and
  $phase103_9_layoutAuditStillCompatible -and
  $noCrossSurfaceDesync

$shellDeleteControlPresent = Test-LinePresent -Text $runText -Pattern '^phase103_10_shell_delete_control_present=1$'
$legalDeleteApplied = Test-LinePresent -Text $runText -Pattern '^phase103_10_legal_delete_applied=1$'
$protectedDeleteRejected = Test-LinePresent -Text $runText -Pattern '^phase103_10_protected_delete_rejected=1$'
$postDeleteSelectionRemappedOrCleared = Test-LinePresent -Text $runText -Pattern '^phase103_10_post_delete_selection_remapped_or_cleared=1$'
$inspectorSafeAfterDelete = Test-LinePresent -Text $runText -Pattern '^phase103_10_inspector_safe_after_delete=1$'
$previewRefreshAfterDelete = Test-LinePresent -Text $runText -Pattern '^phase103_10_preview_refresh_after_delete=1$'
$crossSurfaceStateStillCoherent = Test-LinePresent -Text $runText -Pattern '^phase103_10_cross_surface_state_still_coherent=1$'
$phase103_10_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_10_layout_audit_still_compatible=1$'

$phase103_10_ok =
  $shellDeleteControlPresent -and
  $legalDeleteApplied -and
  $protectedDeleteRejected -and
  $postDeleteSelectionRemappedOrCleared -and
  $inspectorSafeAfterDelete -and
  $previewRefreshAfterDelete -and
  $crossSurfaceStateStillCoherent -and
  $phase103_10_layoutAuditStillCompatible

$commandHistoryPresent = Test-LinePresent -Text $runText -Pattern '^phase103_11_command_history_present=1$'
$rejectedOperationsNotRecorded = Test-LinePresent -Text $runText -Pattern '^phase103_11_rejected_operations_not_recorded=1$'
$propertyEditUndoRedoWorks = Test-LinePresent -Text $runText -Pattern '^phase103_11_property_edit_undo_redo_works=1$'
$insertUndoRedoWorks = Test-LinePresent -Text $runText -Pattern '^phase103_11_insert_undo_redo_works=1$'
$deleteUndoRedoWorks = Test-LinePresent -Text $runText -Pattern '^phase103_11_delete_undo_redo_works=1$'
$moveOrReparentUndoRedoWorks = Test-LinePresent -Text $runText -Pattern '^phase103_11_move_or_reparent_undo_redo_works=1$'
$shellStateCoherentAfterUndoRedo = Test-LinePresent -Text $runText -Pattern '^phase103_11_shell_state_coherent_after_undo_redo=1$'
$phase103_11_layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_11_layout_audit_still_compatible=1$'

$phase103_11_ok =
  $commandHistoryPresent -and
  $rejectedOperationsNotRecorded -and
  $propertyEditUndoRedoWorks -and
  $insertUndoRedoWorks -and
  $deleteUndoRedoWorks -and
  $moveOrReparentUndoRedoWorks -and
  $shellStateCoherentAfterUndoRedo -and
  $phase103_11_layoutAuditStillCompatible

$shellMoveControlsPresent = Test-LinePresent -Text $runText -Pattern '^phase103_7_shell_move_controls_present=1$'
$legalSiblingMoveApplied = Test-LinePresent -Text $runText -Pattern '^phase103_7_legal_sibling_move_applied=1$'
$legalReparentApplied = Test-LinePresent -Text $runText -Pattern '^phase103_7_legal_reparent_applied=1$'
$illegalReparentRejected = Test-LinePresent -Text $runText -Pattern '^phase103_7_illegal_reparent_rejected=1$'
$movedNodeSelectionPreserved = Test-LinePresent -Text $runText -Pattern '^phase103_7_moved_node_selection_preserved=1$'
$treeAndInspectorRefreshAfterMove = Test-LinePresent -Text $runText -Pattern '^phase103_7_tree_and_inspector_refresh_after_move=1$'
$runtimeRefreshAfterMove = Test-LinePresent -Text $runText -Pattern '^phase103_7_runtime_refresh_after_move=1$'
$layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_7_layout_audit_still_compatible=1$'

$phase103_6_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_component_palette_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_legal_container_insertion_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_legal_leaf_insertion_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_illegal_insertion_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_inserted_node_auto_selected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_tree_and_inspector_refresh_after_insert=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_runtime_refresh_after_insert=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_6_layout_audit_still_compatible=1$')

$phase103_5_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_builder_shell_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_live_tree_surface_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_selection_sync_working=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_live_inspector_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_legal_property_edit_from_shell=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_live_preview_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_runtime_refresh_after_edit=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_5_layout_audit_still_compatible=1$')

$phase103_4_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_structural_commands_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_child_add_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_node_remove_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_sibling_reorder_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_reparent_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_illegal_structure_edit_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_tree_editor_foundation_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_runtime_refreshable_after_structure_edit=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_4_layout_audit_still_compatible=1$')

$phase103_3_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_selection_model_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_invalid_selection_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_property_schema_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_inspector_foundation_present=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_legal_property_update_applied=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_illegal_property_update_rejected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_runtime_refreshable_after_edit=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_3_layout_audit_still_compatible=1$')

$phase103_2_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_2_builder_document_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_2_builder_node_ids_stable=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_2_parent_child_ownership_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_2_runtime_aligned_schema_defined=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_2_deterministic_save_load=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_2_sample_document_instantiable=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_2_layout_audit_compatible=1$')

$phase103_1_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase103_1_first_builder_target_selected=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_1_first_builder_target_implemented=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase103_1_layout_audit_no_overlap=1$')

$phase102_2_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_layout_functionalized=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_predictable_resize_behavior=1$')
$phase102_3_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_3_scroll_container_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_3_vertical_scroll_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_3_mouse_wheel_supported=1$')
$phase102_4_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_list_view_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_row_selection_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_click_selection_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_data_binding_working=1$')
$phase102_5_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_table_view_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_multi_column_rendering_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_header_rendering_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_data_binding_working=1$')
$phase102_6_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_toolbar_container_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_sidebar_container_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_status_bar_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_shell_widgets_integrated=1$')
$phase102_7_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_7_open_file_dialog_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_7_save_file_dialog_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_7_message_dialog_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_7_bridge_integrated=1$')
$phase102_8_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_8_declarative_layer_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_8_nested_composition_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_8_property_binding_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_8_basic_action_binding_supported=1$')
$phase102_9_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_7_open_file_dialog_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_7_save_file_dialog_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_7_message_dialog_supported=1$')
$noCrash = Test-LinePresent -Text $runText -Pattern '^app_runtime_crash_detected=0$'
$summaryPass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'

$noRegressions =
  $phase103_18_ok -and
  $phase103_17_ok -and $phase103_16_ok -and $phase103_15_ok -and $phase103_14_ok -and
  $phase103_13_ok -and $phase103_12_ok -and $phase103_11_ok -and $phase103_10_ok -and
  $phase103_9_ok -and $phase103_6_ok -and $phase103_5_ok -and $phase103_4_ok -and
  $phase103_3_ok -and $phase103_2_ok -and $phase103_1_ok -and
  $phase102_2_ok -and $phase102_3_ok -and $phase102_4_ok -and $phase102_5_ok -and
  $phase102_6_ok -and $phase102_7_ok -and $phase102_8_ok -and $phase102_9_ok -and
  $noCrash -and $summaryPass

$phaseStatus = if (
  $requiredApiPreflightPresent -and
  $buildPreconditionsHardened -and
  $builderCapabilityIntegrityChecksPresent -and
  $failureCategoriesExplicit -and
  $phase103_18_ok -and
  $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }

$checksLines = @(
  "required_api_preflight_present=$(if ($requiredApiPreflightPresent) { 'YES' } else { 'NO' })",
  "build_preconditions_hardened=$(if ($buildPreconditionsHardened) { 'YES' } else { 'NO' })",
  "builder_capability_integrity_checks_present=$(if ($builderCapabilityIntegrityChecksPresent) { 'YES' } else { 'NO' })",
  "failure_categories_explicit=$(if ($failureCategoriesExplicit) { 'YES' } else { 'NO' })",
  "tree_drag_reorder_present=$(if ($phase103_18_treeDragReorderPresent) { 'YES' } else { 'NO' })",
  "legal_reorder_drop_applied=$(if ($phase103_18_legalReorderDropApplied) { 'YES' } else { 'NO' })",
  "legal_reparent_drop_applied=$(if ($phase103_18_legalReparentDropApplied) { 'YES' } else { 'NO' })",
  "illegal_drop_rejected=$(if ($phase103_18_illegalDropRejected) { 'YES' } else { 'NO' })",
  "dragged_node_selection_preserved=$(if ($phase103_18_draggedNodeSelectionPreserved) { 'YES' } else { 'NO' })",
  "shell_state_still_coherent=$(if ($phase103_18_shellStateStillCoherent) { 'YES' } else { 'NO' })",
  "layout_audit_still_compatible=$(if ($phase103_18_layoutAuditStillCompatible) { 'YES' } else { 'NO' })",
  "phase103_18_regression_ok=$(if ($phase103_18_ok) { 'YES' } else { 'NO' })",
  "phase103_17_regression_ok=$(if ($phase103_17_ok) { 'YES' } else { 'NO' })",
  "phase103_16_regression_ok=$(if ($phase103_16_ok) { 'YES' } else { 'NO' })",
  "phase103_15_regression_ok=$(if ($phase103_15_ok) { 'YES' } else { 'NO' })",
  "phase103_14_regression_ok=$(if ($phase103_14_ok) { 'YES' } else { 'NO' })",
  "phase103_13_regression_ok=$(if ($phase103_13_ok) { 'YES' } else { 'NO' })",
  "phase103_12_regression_ok=$(if ($phase103_12_ok) { 'YES' } else { 'NO' })",
  "phase103_11_regression_ok=$(if ($phase103_11_ok) { 'YES' } else { 'NO' })",
  "phase103_10_regression_ok=$(if ($phase103_10_ok) { 'YES' } else { 'NO' })",
  "phase103_9_regression_ok=$(if ($phase103_9_ok) { 'YES' } else { 'NO' })",
  "phase103_6_regression_ok=$(if ($phase103_6_ok) { 'YES' } else { 'NO' })",
  "phase103_5_regression_ok=$(if ($phase103_5_ok) { 'YES' } else { 'NO' })",
  "phase103_4_regression_ok=$(if ($phase103_4_ok) { 'YES' } else { 'NO' })",
  "phase103_3_regression_ok=$(if ($phase103_3_ok) { 'YES' } else { 'NO' })",
  "phase103_2_regression_ok=$(if ($phase103_2_ok) { 'YES' } else { 'NO' })",
  "phase103_1_regression_ok=$(if ($phase103_1_ok) { 'YES' } else { 'NO' })",
  "failure_category=$failureCategory",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = $checksLines
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  throw '90_controlled_drag_reorder_ux_checks.txt is malformed'
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  throw '99_contract_summary.txt is malformed'
}

Remove-PathIfExists -Path $buildOut
Remove-PathIfExists -Path $runOut

try {
  Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force
} catch {
  $message = $_.Exception.Message
  if ($message -match 'being used by another process') {
    Fail-Closed -Category 'artifact_lock' -Reason "proof artifact lock detected at $zipPath"
  }
  throw
}

if (-not (Test-Path -LiteralPath $zipPath)) {
  throw 'proof zip was not created'
}

Remove-PathIfExists -Path $stageRoot

Write-Host ("tree_drag_reorder_present=$(if ($phase103_18_treeDragReorderPresent) { 'YES' } else { 'NO' })")
Write-Host ("legal_reorder_drop_applied=$(if ($phase103_18_legalReorderDropApplied) { 'YES' } else { 'NO' })")
Write-Host ("legal_reparent_drop_applied=$(if ($phase103_18_legalReparentDropApplied) { 'YES' } else { 'NO' })")
Write-Host ("illegal_drop_rejected=$(if ($phase103_18_illegalDropRejected) { 'YES' } else { 'NO' })")
Write-Host ("dragged_node_selection_preserved=$(if ($phase103_18_draggedNodeSelectionPreserved) { 'YES' } else { 'NO' })")
Write-Host ("shell_state_still_coherent=$(if ($phase103_18_shellStateStillCoherent) { 'YES' } else { 'NO' })")
Write-Host ("layout_audit_still_compatible=$(if ($phase103_18_layoutAuditStillCompatible) { 'YES' } else { 'NO' })")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}

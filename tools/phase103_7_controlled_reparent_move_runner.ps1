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
  Write-Host 'wrong workspace for phase103_7 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_7_controlled_reparent_move_${timestamp}_$([guid]::NewGuid().ToString('N').Substring(0,8))"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$($proofName).zip"

$checksFile = Join-Path $stageRoot '90_controlled_reparent_move_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$mainPath = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'

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

function Invoke-CmdChecked {
  param([string]$CommandLine, [string]$LogPath, [string]$StepName)
  Add-Content -LiteralPath $LogPath -Value ("STEP=$StepName")
  cmd /c $CommandLine *>&1 | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
  if ($LASTEXITCODE -ne 0) {
    throw "$StepName failed with exit code $LASTEXITCODE"
  }
}

if (-not (Test-Path -LiteralPath $mainPath)) {
  throw 'desktop_file_tool main.cpp missing'
}

$mainText = Get-Content -LiteralPath $mainPath -Raw
$moveReparentCodePresent =
  ($mainText -match 'phase103_7_shell_move_controls_present') -and
  ($mainText -match 'builder_move_up_button') -and
  ($mainText -match 'builder_move_down_button') -and
  ($mainText -match 'builder_reparent_button') -and
  ($mainText -match 'apply_move_sibling_up') -and
  ($mainText -match 'apply_move_sibling_down') -and
  ($mainText -match 'apply_reparent_legal') -and
  ($mainText -match 'apply_reparent_illegal')

& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
  Out-File -LiteralPath $buildOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw 'desktop_file_tool build-plan generation failed'
}

if (-not (Test-Path -LiteralPath $planPath)) {
  throw 'desktop_file_tool build plan missing'
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]

if ($engineCompileNodes.Count -eq 0 -or $null -eq $appCompileNode -or $null -eq $engineLibNode -or $null -eq $appLinkNode) {
  throw 'required compile/link nodes missing from build plan'
}

& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 |
  Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -LogPath $buildOut -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -LogPath $buildOut -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd -LogPath $buildOut -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd -LogPath $buildOut -StepName $appLinkNode.desc

if (-not (Test-Path -LiteralPath $exePath)) {
  throw 'desktop_file_tool executable missing after compile/link'
}

& $exePath --validation-mode --auto-close-ms=5300 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw "desktop_file_tool validation run failed (exit $LASTEXITCODE)"
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

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
  $phase103_6_ok -and $phase103_5_ok -and $phase103_4_ok -and $phase103_3_ok -and $phase103_2_ok -and $phase103_1_ok -and
  $phase102_2_ok -and $phase102_3_ok -and $phase102_4_ok -and $phase102_5_ok -and
  $phase102_6_ok -and $phase102_7_ok -and $phase102_8_ok -and $phase102_9_ok -and
  $noCrash -and $summaryPass

$phaseStatus = if (
  $moveReparentCodePresent -and
  $shellMoveControlsPresent -and
  $legalSiblingMoveApplied -and
  $legalReparentApplied -and
  $illegalReparentRejected -and
  $movedNodeSelectionPreserved -and
  $treeAndInspectorRefreshAfterMove -and
  $runtimeRefreshAfterMove -and
  $layoutAuditStillCompatible -and
  $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }

$checksLines = @(
  "shell_move_controls_present=$(if ($shellMoveControlsPresent) { 'YES' } else { 'NO' })",
  "legal_sibling_move_applied=$(if ($legalSiblingMoveApplied) { 'YES' } else { 'NO' })",
  "legal_reparent_applied=$(if ($legalReparentApplied) { 'YES' } else { 'NO' })",
  "illegal_reparent_rejected=$(if ($illegalReparentRejected) { 'YES' } else { 'NO' })",
  "moved_node_selection_preserved=$(if ($movedNodeSelectionPreserved) { 'YES' } else { 'NO' })",
  "tree_and_inspector_refresh_after_move=$(if ($treeAndInspectorRefreshAfterMove) { 'YES' } else { 'NO' })",
  "runtime_refresh_after_move=$(if ($runtimeRefreshAfterMove) { 'YES' } else { 'NO' })",
  "layout_audit_still_compatible=$(if ($layoutAuditStillCompatible) { 'YES' } else { 'NO' })",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = @(
  "shell_move_controls_present=$(if ($shellMoveControlsPresent) { 'YES' } else { 'NO' })",
  "legal_sibling_move_applied=$(if ($legalSiblingMoveApplied) { 'YES' } else { 'NO' })",
  "legal_reparent_applied=$(if ($legalReparentApplied) { 'YES' } else { 'NO' })",
  "illegal_reparent_rejected=$(if ($illegalReparentRejected) { 'YES' } else { 'NO' })",
  "moved_node_selection_preserved=$(if ($movedNodeSelectionPreserved) { 'YES' } else { 'NO' })",
  "tree_and_inspector_refresh_after_move=$(if ($treeAndInspectorRefreshAfterMove) { 'YES' } else { 'NO' })",
  "runtime_refresh_after_move=$(if ($runtimeRefreshAfterMove) { 'YES' } else { 'NO' })",
  "layout_audit_still_compatible=$(if ($layoutAuditStillCompatible) { 'YES' } else { 'NO' })",
  "phase103_6_regression_ok=$(if ($phase103_6_ok) { 'YES' } else { 'NO' })",
  "phase103_5_regression_ok=$(if ($phase103_5_ok) { 'YES' } else { 'NO' })",
  "phase103_4_regression_ok=$(if ($phase103_4_ok) { 'YES' } else { 'NO' })",
  "phase103_3_regression_ok=$(if ($phase103_3_ok) { 'YES' } else { 'NO' })",
  "phase103_2_regression_ok=$(if ($phase103_2_ok) { 'YES' } else { 'NO' })",
  "phase103_1_regression_ok=$(if ($phase103_1_ok) { 'YES' } else { 'NO' })",
  "phase102_2_regression_ok=$(if ($phase102_2_ok) { 'YES' } else { 'NO' })",
  "phase102_3_regression_ok=$(if ($phase102_3_ok) { 'YES' } else { 'NO' })",
  "phase102_4_regression_ok=$(if ($phase102_4_ok) { 'YES' } else { 'NO' })",
  "phase102_5_regression_ok=$(if ($phase102_5_ok) { 'YES' } else { 'NO' })",
  "phase102_6_regression_ok=$(if ($phase102_6_ok) { 'YES' } else { 'NO' })",
  "phase102_7_regression_ok=$(if ($phase102_7_ok) { 'YES' } else { 'NO' })",
  "phase102_8_regression_ok=$(if ($phase102_8_ok) { 'YES' } else { 'NO' })",
  "phase102_9_regression_ok=$(if ($phase102_9_ok) { 'YES' } else { 'NO' })",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  throw '90_controlled_reparent_move_checks.txt is malformed'
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
    throw "proof artifact lock detected at $zipPath"
  }
  throw
}

if (-not (Test-Path -LiteralPath $zipPath)) {
  throw 'proof zip was not created'
}

Remove-PathIfExists -Path $stageRoot

Write-Host ("shell_move_controls_present=$(if ($shellMoveControlsPresent) { 'YES' } else { 'NO' })")
Write-Host ("legal_sibling_move_applied=$(if ($legalSiblingMoveApplied) { 'YES' } else { 'NO' })")
Write-Host ("legal_reparent_applied=$(if ($legalReparentApplied) { 'YES' } else { 'NO' })")
Write-Host ("illegal_reparent_rejected=$(if ($illegalReparentRejected) { 'YES' } else { 'NO' })")
Write-Host ("moved_node_selection_preserved=$(if ($movedNodeSelectionPreserved) { 'YES' } else { 'NO' })")
Write-Host ("tree_and_inspector_refresh_after_move=$(if ($treeAndInspectorRefreshAfterMove) { 'YES' } else { 'NO' })")
Write-Host ("runtime_refresh_after_move=$(if ($runtimeRefreshAfterMove) { 'YES' } else { 'NO' })")
Write-Host ("layout_audit_still_compatible=$(if ($layoutAuditStillCompatible) { 'YES' } else { 'NO' })")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}


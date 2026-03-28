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
  Write-Host 'wrong workspace for phase103_4 runner'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_4_tree_editor_structural_commands_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile = Join-Path $stageRoot '90_tree_editor_structural_commands_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$builderDocHeaderPath = Join-Path $workspaceRoot 'engine/ui/builder_document.hpp'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase103_4_tree_editor_structural_commands_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

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

if (-not (Test-Path -LiteralPath $builderDocHeaderPath)) {
  throw 'builder_document.hpp missing'
}

$builderHeaderText = Get-Content -LiteralPath $builderDocHeaderPath -Raw
$structuralCommandsDefinedInCode =
  ($builderHeaderText -match 'apply_add_child_command') -and
  ($builderHeaderText -match 'apply_remove_node_command') -and
  ($builderHeaderText -match 'apply_move_sibling_command') -and
  ($builderHeaderText -match 'apply_reparent_node_command') -and
  ($builderHeaderText -match 'allows_child_widget_type') -and
  ($builderHeaderText -match 'inspect_tree_structure')

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

& $exePath --validation-mode --auto-close-ms=3600 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw "desktop_file_tool validation run failed (exit $LASTEXITCODE)"
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$structuralCommandsDefined = Test-LinePresent -Text $runText -Pattern '^phase103_4_structural_commands_defined=1$'
$legalChildAddApplied = Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_child_add_applied=1$'
$legalNodeRemoveApplied = Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_node_remove_applied=1$'
$legalSiblingReorderApplied = Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_sibling_reorder_applied=1$'
$legalReparentApplied = Test-LinePresent -Text $runText -Pattern '^phase103_4_legal_reparent_applied=1$'
$illegalStructureEditRejected = Test-LinePresent -Text $runText -Pattern '^phase103_4_illegal_structure_edit_rejected=1$'
$treeEditorFoundationPresent = Test-LinePresent -Text $runText -Pattern '^phase103_4_tree_editor_foundation_present=1$'
$runtimeRefreshableAfterStructureEdit = Test-LinePresent -Text $runText -Pattern '^phase103_4_runtime_refreshable_after_structure_edit=1$'
$layoutAuditStillCompatible = Test-LinePresent -Text $runText -Pattern '^phase103_4_layout_audit_still_compatible=1$'

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
  $phase103_3_ok -and $phase103_2_ok -and $phase103_1_ok -and
  $phase102_2_ok -and $phase102_3_ok -and $phase102_4_ok -and $phase102_5_ok -and
  $phase102_6_ok -and $phase102_7_ok -and $phase102_8_ok -and $phase102_9_ok -and
  $noCrash -and $summaryPass

$phaseStatus = if (
  $structuralCommandsDefinedInCode -and
  $structuralCommandsDefined -and
  $legalChildAddApplied -and
  $legalNodeRemoveApplied -and
  $legalSiblingReorderApplied -and
  $legalReparentApplied -and
  $illegalStructureEditRejected -and
  $treeEditorFoundationPresent -and
  $runtimeRefreshableAfterStructureEdit -and
  $layoutAuditStillCompatible -and
  $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }

$checksLines = @(
  "structural_commands_defined=$(if ($structuralCommandsDefined) { 'YES' } else { 'NO' })",
  "legal_child_add_applied=$(if ($legalChildAddApplied) { 'YES' } else { 'NO' })",
  "legal_node_remove_applied=$(if ($legalNodeRemoveApplied) { 'YES' } else { 'NO' })",
  "legal_sibling_reorder_applied=$(if ($legalSiblingReorderApplied) { 'YES' } else { 'NO' })",
  "legal_reparent_applied=$(if ($legalReparentApplied) { 'YES' } else { 'NO' })",
  "illegal_structure_edit_rejected=$(if ($illegalStructureEditRejected) { 'YES' } else { 'NO' })",
  "tree_editor_foundation_present=$(if ($treeEditorFoundationPresent) { 'YES' } else { 'NO' })",
  "runtime_refreshable_after_structure_edit=$(if ($runtimeRefreshableAfterStructureEdit) { 'YES' } else { 'NO' })",
  "layout_audit_still_compatible=$(if ($layoutAuditStillCompatible) { 'YES' } else { 'NO' })",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = @(
  "structural_commands_defined=$(if ($structuralCommandsDefined) { 'YES' } else { 'NO' })",
  "legal_child_add_applied=$(if ($legalChildAddApplied) { 'YES' } else { 'NO' })",
  "legal_node_remove_applied=$(if ($legalNodeRemoveApplied) { 'YES' } else { 'NO' })",
  "legal_sibling_reorder_applied=$(if ($legalSiblingReorderApplied) { 'YES' } else { 'NO' })",
  "legal_reparent_applied=$(if ($legalReparentApplied) { 'YES' } else { 'NO' })",
  "illegal_structure_edit_rejected=$(if ($illegalStructureEditRejected) { 'YES' } else { 'NO' })",
  "tree_editor_foundation_present=$(if ($treeEditorFoundationPresent) { 'YES' } else { 'NO' })",
  "runtime_refreshable_after_structure_edit=$(if ($runtimeRefreshableAfterStructureEdit) { 'YES' } else { 'NO' })",
  "layout_audit_still_compatible=$(if ($layoutAuditStillCompatible) { 'YES' } else { 'NO' })",
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
  throw '90_tree_editor_structural_commands_checks.txt is malformed'
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  throw '99_contract_summary.txt is malformed'
}

Remove-PathIfExists -Path $buildOut
Remove-PathIfExists -Path $runOut

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force
if (-not (Test-Path -LiteralPath $zipPath)) {
  throw 'proof zip was not created'
}

Remove-PathIfExists -Path $stageRoot

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot |
  Where-Object { $_.Name -like 'phase103_4_tree_editor_structural_commands_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  throw 'packaging rule violated: expected exactly one phase103_4 artifact'
}

Write-Host ("structural_commands_defined=$(if ($structuralCommandsDefined) { 'YES' } else { 'NO' })")
Write-Host ("legal_child_add_applied=$(if ($legalChildAddApplied) { 'YES' } else { 'NO' })")
Write-Host ("legal_node_remove_applied=$(if ($legalNodeRemoveApplied) { 'YES' } else { 'NO' })")
Write-Host ("legal_sibling_reorder_applied=$(if ($legalSiblingReorderApplied) { 'YES' } else { 'NO' })")
Write-Host ("legal_reparent_applied=$(if ($legalReparentApplied) { 'YES' } else { 'NO' })")
Write-Host ("illegal_structure_edit_rejected=$(if ($illegalStructureEditRejected) { 'YES' } else { 'NO' })")
Write-Host ("tree_editor_foundation_present=$(if ($treeEditorFoundationPresent) { 'YES' } else { 'NO' })")
Write-Host ("runtime_refreshable_after_structure_edit=$(if ($runtimeRefreshableAfterStructureEdit) { 'YES' } else { 'NO' })")
Write-Host ("layout_audit_still_compatible=$(if ($layoutAuditStillCompatible) { 'YES' } else { 'NO' })")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}

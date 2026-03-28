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
  Write-Host 'hey stupid Fucker, wrong window again'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase103_1_layout_aware_builder_roadmap_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile = Join-Path $stageRoot '90_layout_aware_builder_roadmap_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'
$roadmapPath = Join-Path $workspaceRoot 'docs/phase103_1_layout_aware_builder_roadmap.md'
$auditHeaderPath = Join-Path $workspaceRoot 'engine/ui/layout_audit.hpp'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase103_1_layout_aware_builder_roadmap_*.zip' -ErrorAction SilentlyContinue |
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

if (-not (Test-Path -LiteralPath $roadmapPath)) {
  throw 'phase103_1 roadmap document missing'
}
if (-not (Test-Path -LiteralPath $auditHeaderPath)) {
  throw 'layout_audit.hpp missing'
}

$roadmapText = Get-Content -LiteralPath $roadmapPath -Raw
$builderRoadmapDefined =
  ($roadmapText -match 'Ordered Roadmap') -and
  ($roadmapText -match 'layout foundation') -and
  ($roadmapText -match 'scroll container') -and
  ($roadmapText -match 'list/table') -and
  ($roadmapText -match 'shell widgets') -and
  ($roadmapText -match 'native dialogs') -and
  ($roadmapText -match 'declarative composition') -and
  ($roadmapText -match 'packaging/export')

$firstBuilderTargetSelected =
  ($roadmapText -match 'First Builder-Facing Target \(Selected\)') -and
  ($roadmapText -match 'Builder Layout Audit Pass')

$dependencyNotes = 'layout_foundation;scroll_container;list_table;shell_widgets;native_dialogs;declarative_composition;packaging_export'
$runtimeBehaviorChanges = 'audit_markers_only_no_visual_redesign'
$changesIntroduced = 'phase103_1_builder_roadmap_doc;layout_audit_first_slice;desktop_file_tool_phase103_markers'

$headerText = Get-Content -LiteralPath $auditHeaderPath -Raw
$firstTargetImplemented =
  ($headerText -match 'audit_layout_tree') -and
  ($headerText -match 'rects_overlap') -and
  ($headerText -match 'minimum_violations')

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
  throw 'Required compile/link nodes missing from build plan'
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

$targetSelectedRuntime = Test-LinePresent -Text $runText -Pattern '^phase103_1_first_builder_target_selected=1$'
$targetImplementedRuntime = Test-LinePresent -Text $runText -Pattern '^phase103_1_first_builder_target_implemented=1$'
$layoutAuditNoOverlap = Test-LinePresent -Text $runText -Pattern '^phase103_1_layout_audit_no_overlap=1$'
$layoutAuditMinimums = Test-LinePresent -Text $runText -Pattern '^phase103_1_layout_audit_minimums_ok=(0|1)$'
$auditCheckedNodes = if ($runText -match '(?m)^phase103_1_layout_audit_checked_nodes=(\d+)$') { [int]$matches[1] } else { 0 }

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
  $phase102_2_ok -and $phase102_3_ok -and $phase102_4_ok -and $phase102_5_ok -and
  $phase102_6_ok -and $phase102_7_ok -and $phase102_8_ok -and $phase102_9_ok -and $noCrash -and $summaryPass

$phaseStatus = if (
  $builderRoadmapDefined -and $firstBuilderTargetSelected -and $firstTargetImplemented -and
  $targetSelectedRuntime -and $targetImplementedRuntime -and $layoutAuditNoOverlap -and
  $layoutAuditMinimums -and ($auditCheckedNodes -gt 0) -and $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }

$checksLines = @(
  "builder_roadmap_defined=$(if ($builderRoadmapDefined) { 'YES' } else { 'NO' })",
  "first_builder_target_selected=$(if ($firstBuilderTargetSelected -and $targetSelectedRuntime) { 'YES' } else { 'NO' })",
  "dependency_notes=$dependencyNotes",
  "changes_introduced=$changesIntroduced",
  "runtime_behavior_changes=$runtimeBehaviorChanges",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = @(
  "builder_roadmap_defined=$(if ($builderRoadmapDefined) { 'YES' } else { 'NO' })",
  "first_builder_target_selected=$(if ($firstBuilderTargetSelected -and $targetSelectedRuntime) { 'YES' } else { 'NO' })",
  "first_builder_target_implemented=$(if ($firstTargetImplemented -and $targetImplementedRuntime) { 'YES' } else { 'NO' })",
  "dependency_notes=$dependencyNotes",
  "changes_introduced=$changesIntroduced",
  "runtime_behavior_changes=$runtimeBehaviorChanges",
  "layout_audit_no_overlap=$(if ($layoutAuditNoOverlap) { 'YES' } else { 'NO' })",
  "layout_audit_minimums_ok=$(if ($layoutAuditMinimums) { 'YES' } else { 'NO' })",
  "layout_audit_checked_nodes=$auditCheckedNodes",
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
  throw '90_layout_aware_builder_roadmap_checks.txt is malformed'
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
  Where-Object { $_.Name -like 'phase103_1_layout_aware_builder_roadmap_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  throw 'packaging rule violated: expected exactly one phase103_1 artifact'
}

Write-Host ("builder_roadmap_defined=$(if ($builderRoadmapDefined) { 'YES' } else { 'NO' })")
Write-Host ("first_builder_target_selected=$(if ($firstBuilderTargetSelected -and $targetSelectedRuntime) { 'YES' } else { 'NO' })")
Write-Host ("dependency_notes=$dependencyNotes")
Write-Host ("changes_introduced=$changesIntroduced")
Write-Host ("runtime_behavior_changes=$runtimeBehaviorChanges")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}

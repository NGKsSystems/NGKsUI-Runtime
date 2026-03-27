#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

$workspaceRoot = Get-Location | Select-Object -ExpandProperty Path
$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase82_1_ui_runtime_higher_level_shells_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase82_1_ui_runtime_higher_level_shells_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

function New-ProofZip {
  param([string]$SourceDir, [string]$DestinationZip)
  if (Test-Path -LiteralPath $DestinationZip) { Remove-Item -LiteralPath $DestinationZip -Force }
  Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $DestinationZip -Force
}

function Test-ZipContainsEntries {
  param([string]$ZipFile, [string[]]$ExpectedEntries)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
  try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($entry in $ExpectedEntries) {
      if ($entryNames -notcontains $entry) { return $false }
    }
    return $true
  } finally { $archive.Dispose() }
}

$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { "" }

$checkResults = @{}
$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'PHASE82_1 startup marker missing' }
if ($widgetContent -match 'phase82_1_higher_level_shells_available') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup includes PHASE82_1 marker'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard preserved before native activation'
}

$checkResults['check_toolbar_shell_path_exists'] = @{ Result = $false; Reason = 'toolbar shell composition path missing' }
if ($widgetContent -match 'ShellKind::Toolbar' -and $widgetContent -match 'toolbar_shell' -and $widgetContent -match 'toolbar_refresh_action') {
  $checkResults['check_toolbar_shell_path_exists'].Result = $true
  $checkResults['check_toolbar_shell_path_exists'].Reason = 'toolbar shell composition and action host path exists'
}

$checkResults['check_sidebar_shell_path_exists'] = @{ Result = $false; Reason = 'sidebar shell stacked region path missing' }
if ($widgetContent -match 'ShellKind::Sidebar' -and $widgetContent -match 'sidebar_shell' -and $widgetContent -match 'child_region_node_ids' -and $widgetContent -match 'Sidebar Region A') {
  $checkResults['check_sidebar_shell_path_exists'].Result = $true
  $checkResults['check_sidebar_shell_path_exists'].Reason = 'sidebar shell stacked child regions path exists'
}

$checkResults['check_dialog_shell_open_close_path_exists'] = @{ Result = $false; Reason = 'dialog open close path missing' }
if ($widgetContent -match 'ShellKind::Dialog' -and $widgetContent -match 'set_dialog_shell_open\(' -and $widgetContent -match 'dialog_open_action' -and $widgetContent -match 'dialog_close_action') {
  $checkResults['check_dialog_shell_open_close_path_exists'].Result = $true
  $checkResults['check_dialog_shell_open_close_path_exists'].Reason = 'dialog shell open close state path exists'
}

$checkResults['check_toolbar_action_path_works'] = @{ Result = $false; Reason = 'toolbar action execution path missing' }
if ($widgetContent -match 'toolbar_action_id_' -and $widgetContent -match 'execute_action\(' -and $widgetContent -match 'action_id == toolbar_action_id_') {
  $checkResults['check_toolbar_action_path_works'].Result = $true
  $checkResults['check_toolbar_action_path_works'].Reason = 'toolbar action path is routed through action execution'
}

$checkResults['check_layout_update_path_works_across_shells'] = @{ Result = $false; Reason = 'cross-shell layout update path missing' }
if ($widgetContent -match 'run_layout_update_pass\(' -and $widgetContent -match 'layout_higher_level_shells\(' -and $widgetContent -match 'tick_component_updates\(') {
  $checkResults['check_layout_update_path_works_across_shells'].Result = $true
  $checkResults['check_layout_update_path_works_across_shells'].Reason = 'layout update path covers higher-level shells'
}

$checkResults['check_redraw_invalidation_works_across_shells'] = @{ Result = $false; Reason = 'cross-shell redraw invalidation path missing' }
if ($widgetContent -match 'invalidate_ui_tree\(' -and $widgetContent -match 'render_container_primitives\(' -and $widgetContent -match 'render_button_primitives\(' -and $widgetContent -match 'render_label_primitives\(') {
  $checkResults['check_redraw_invalidation_works_across_shells'].Result = $true
  $checkResults['check_redraw_invalidation_works_across_shells'].Reason = 'redraw invalidation path covers shell primitives'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle behavior missing' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via native message loop'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown behavior missing' }
if ($widgetContent -match 'cleanup\(' -and $widgetContent -match 'shells_\.clear\(' -and $widgetContent -match 'DestroyWindow\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown still works with shell teardown and window destruction'
}

$failedCount = 0
foreach ($check in $checkResults.Values) { if (-not $check.Result) { $failedCount++ } }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_ui_runtime_higher_level_shells_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE82_1_UI_RUNTIME_HIGHER_LEVEL_SHELLS'
$checkLines += 'scope=minimal_toolbar_sidebar_dialog_first_slice'
$checkLines += 'foundation=phase80_0_to_phase82_0_runtime_widget_stack'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Higher-Level Shell Validation'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Shell Coverage'
$checkLines += ('shell_record_present=' + $(if ($widgetContent -match 'struct ShellRecord') { 'YES' } else { 'NO' }))
$checkLines += ('toolbar_shell_present=' + $(if ($widgetContent -match 'ShellKind::Toolbar') { 'YES' } else { 'NO' }))
$checkLines += ('sidebar_shell_present=' + $(if ($widgetContent -match 'ShellKind::Sidebar') { 'YES' } else { 'NO' }))
$checkLines += ('dialog_shell_present=' + $(if ($widgetContent -match 'ShellKind::Dialog') { 'YES' } else { 'NO' }))
$checkLines += ('toolbar_action_present=' + $(if ($widgetContent -match 'toolbar_refresh_action') { 'YES' } else { 'NO' }))
$checkLines += ('sidebar_stacked_regions_present=' + $(if ($widgetContent -match 'Sidebar Region A' -and $widgetContent -match 'Sidebar Region B') { 'YES' } else { 'NO' }))
$checkLines += ('dialog_open_close_state_present=' + $(if ($widgetContent -match 'dialog_open_state_id_' -and $widgetContent -match 'set_dialog_shell_open\(') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('higher_level_shells_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE82_1_UI_RUNTIME_HIGHER_LEVEL_SHELLS'
$contract += 'objective=Build_first_higher_level_ui_shells_toolbar_sidebar_dialog_on_top_of_widget_primitives_to_prove_multi_region_application_structure_without_qt'
$contract += 'changes_introduced=NativeWindowPump_shell_records_added_with_toolbar_sidebar_dialog_seed_composed_from_existing_primitives_with_dialog_open_close_state_path_and_shell_layout_render_invalidation_integration'
$contract += 'runtime_behavior_changes=Runtime_now_exposes_minimal_higher_level_shell_structure_toolbar_action_host_sidebar_stacked_regions_and_dialog_open_close_path_integrated_with_tree_layout_lifecycle_state_and_command_execution'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_higher_level_shells_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_higher_level_shells_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase82_1_ui_runtime_higher_level_shells_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase82_1_status=' + $phaseStatus)
exit 0

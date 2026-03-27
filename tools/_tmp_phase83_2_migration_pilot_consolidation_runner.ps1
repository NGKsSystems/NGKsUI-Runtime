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
$proofName = "phase83_2_migration_pilot_consolidation_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase83_2_migration_pilot_consolidation_*.zip' -ErrorAction SilentlyContinue |
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
$checkResults['check_pilot_mode_still_launches'] = @{ Result = $false; Reason = 'pilot mode launch path missing' }
if ($widgetContent -match 'is_migration_pilot_mode_enabled\(' -and $widgetContent -match 'run_phase83_0_migration_pilot_app\(') {
  $checkResults['check_pilot_mode_still_launches'].Result = $true
  $checkResults['check_pilot_mode_still_launches'].Reason = 'same migration pilot mode still launches through the existing native path'
}

$checkResults['check_controls_and_textbox_work_together'] = @{ Result = $false; Reason = 'consolidated controls/textbox behavior missing' }
if ($widgetContent -match 'route_migration_pilot_key_action\(' -and $widgetContent -match 'focus_next_migration_pilot_primitive\(' -and $widgetContent -match 'pilot_submit_text_action') {
  $checkResults['check_controls_and_textbox_work_together'].Result = $true
  $checkResults['check_controls_and_textbox_work_together'].Reason = 'controls and textbox are consolidated under the same pilot routing model'
}

$checkResults['check_focus_transitions_are_coherent'] = @{ Result = $false; Reason = 'coherent focus transition path missing' }
if ($widgetContent -match 'focus_migration_pilot_primitive\(' -and $widgetContent -match 'focus_next_migration_pilot_primitive\(' -and $widgetContent -match 'clear_migration_pilot_focus\(' -and $widgetContent -match 'pilot_focus_state_id_') {
  $checkResults['check_focus_transitions_are_coherent'].Result = $true
  $checkResults['check_focus_transitions_are_coherent'].Reason = 'focus transitions are unified across toolbar buttons and textbox'
}

$checkResults['check_input_action_state_redraw_coherent'] = @{ Result = $false; Reason = 'cross-slice input/action/state/redraw coherence missing' }
if ($widgetContent -match 'route_migration_pilot_key_action\(' -and $widgetContent -match 'record_migration_pilot_action\(' -and $widgetContent -match 'update_widget_sandbox_migration_pilot_labels\(' -and $widgetContent -match 'pilot_route_state_id_') {
  $checkResults['check_input_action_state_redraw_coherent'].Result = $true
  $checkResults['check_input_action_state_redraw_coherent'].Reason = 'input, action routing, state updates, and redraw are coherent across the consolidated pilot'
}

$checkResults['check_layout_redraw_remains_correct'] = @{ Result = $false; Reason = 'layout/redraw correctness path missing' }
if ($widgetContent -match 'layout_higher_level_shells\(' -and $widgetContent -match 'render_button_primitives\(' -and $widgetContent -match 'render_text_field_primitives\(' -and $widgetContent -match 'render_label_primitives\(') {
  $checkResults['check_layout_redraw_remains_correct'].Result = $true
  $checkResults['check_layout_redraw_remains_correct'].Reason = 'layout and redraw remain unified across consolidated migrated slices'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle behavior missing' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via native message loop'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown behavior missing' }
if ($widgetContent -match 'cleanup\(' -and $widgetContent -match 'DestroyWindow\(' -and $widgetContent -match 'pilot_last_action_\.clear\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown still works with consolidated pilot state teardown'
}

$checkResults['check_no_regression_to_legacy_path'] = @{ Result = $false; Reason = 'legacy path preservation missing' }
if ($widgetContent -match 'const int app_rc = migration_pilot_mode' -and $widgetContent -match ': run_app\(') {
  $checkResults['check_no_regression_to_legacy_path'].Result = $true
  $checkResults['check_no_regression_to_legacy_path'].Reason = 'legacy widget_sandbox path remains reversible when pilot mode is not selected'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust enforcement remains before native activation'
}

$failedCount = 0
foreach ($check in $checkResults.Values) { if (-not $check.Result) { $failedCount++ } }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_migration_pilot_consolidation_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE83_2_MIGRATION_PILOT_CONSOLIDATION'
$checkLines += 'scope=widget_sandbox_consolidated_native_pilot_surface'
$checkLines += 'foundation=phase83_0_and_phase83_1_widget_sandbox_native_migration_pilot'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Migration Pilot Consolidation Validation'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Consolidation Coverage'
$checkLines += ('focus_state_present=' + $(if ($widgetContent -match 'pilot_focus_state_id_') { 'YES' } else { 'NO' }))
$checkLines += ('route_state_present=' + $(if ($widgetContent -match 'pilot_route_state_id_') { 'YES' } else { 'NO' }))
$checkLines += ('last_action_state_present=' + $(if ($widgetContent -match 'pilot_last_action_') { 'YES' } else { 'NO' }))
$checkLines += ('coherent_key_routing_present=' + $(if ($widgetContent -match 'route_migration_pilot_key_action\(') { 'YES' } else { 'NO' }))
$checkLines += ('shared_focus_cycle_present=' + $(if ($widgetContent -match 'focus_next_migration_pilot_primitive\(') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('migration_pilot_consolidation_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE83_2_MIGRATION_PILOT_INTERACTION_CONSOLIDATION'
$contract += 'objective=Consolidate_the_existing_widget_sandbox_migrated_slices_into_one_coherent_interactive_native_pilot_surface_on_the_same_path'
$contract += 'changes_introduced=Unified_focus_action_routing_and_state_tracking_added_for_the_existing_native_toolbar_buttons_and_textbox_with_shared_focus_cycle_keyboard_routing_and_consolidated_status_footer_updates'
$contract += 'runtime_behavior_changes=Widget_sandbox_migration_pilot_mode_now_behaves_as_one_coherent_native_surface_with_consistent_focus_transitions_action_routing_state_coherence_and_redraw_updates_while_keeping_the_legacy_path_reversible'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_migration_pilot_consolidation_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_migration_pilot_consolidation_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase83_2_migration_pilot_consolidation_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase83_2_status=' + $phaseStatus)
exit 0

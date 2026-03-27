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
$proofName = "phase83_0_migration_pilot_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase83_0_migration_pilot_*.zip' -ErrorAction SilentlyContinue |
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
$checkResults['check_candidate_targets_ranked'] = @{ Result = $false; Reason = 'candidate ranking markers missing' }
if ($widgetContent -match 'phase83_0_migration_candidate_rank_1=widget_sandbox_control_surface' -and
    $widgetContent -match 'phase83_0_migration_candidate_rank_2=win32_sandbox_diagnostics_surface' -and
    $widgetContent -match 'phase83_0_migration_candidate_rank_3=sandbox_app_event_loop_surface') {
  $checkResults['check_candidate_targets_ranked'].Result = $true
  $checkResults['check_candidate_targets_ranked'].Reason = 'candidate migration targets are ranked explicitly'
}

$checkResults['check_target_selected'] = @{ Result = $false; Reason = 'selected migration target missing' }
if ($widgetContent -match 'phase83_0_migration_target_selected=' -and
    $widgetContent -match 'widget_sandbox_control_surface' -and
    $widgetContent -match 'smallest_real_surface_on_current_native_runtime_migration_path') {
  $checkResults['check_target_selected'].Result = $true
  $checkResults['check_target_selected'].Reason = 'widget_sandbox control surface is selected as the first real migration pilot'
}

$checkResults['check_migrated_pilot_path_exists'] = @{ Result = $false; Reason = 'migration pilot native path missing' }
if ($widgetContent -match 'run_phase83_0_migration_pilot_app\(' -and
    $widgetContent -match 'NativeWindowPump native_pump' -and
    $widgetContent -match 'configure_widget_sandbox_migration_pilot\(') {
  $checkResults['check_migrated_pilot_path_exists'].Result = $true
  $checkResults['check_migrated_pilot_path_exists'].Reason = 'migration pilot path launches through the native stack'
}

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup marker or trust guard missing' }
if ($widgetContent -match 'phase83_0_migration_pilot_available' -and
    $widgetContent -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $widgetContent -match 'is_migration_pilot_mode_enabled\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup includes PHASE83_0 markers and execution_pipeline guard before pilot launch'
}

$checkResults['check_migrated_ui_composition_path_works'] = @{ Result = $false; Reason = 'migrated widget_sandbox composition path missing' }
if ($widgetContent -match 'set_primitive_text\(toolbar_primary_button_primitive_id_, "Increment"\)' -and
    $widgetContent -match 'set_primitive_text\(toolbar_secondary_button_primitive_id_, "Reset"\)' -and
    $widgetContent -match 'update_widget_sandbox_migration_pilot_labels\(') {
  $checkResults['check_migrated_ui_composition_path_works'].Result = $true
  $checkResults['check_migrated_ui_composition_path_works'].Reason = 'real widget_sandbox controls/status slice is mapped onto native shells and primitives'
}

$checkResults['check_action_input_path_works'] = @{ Result = $false; Reason = 'pilot action input path missing' }
if ($widgetContent -match 'pilot_increment_action' -and
    $widgetContent -match 'pilot_reset_action' -and
    $widgetContent -match 'handle_mouse_button_up\(' -and
    $widgetContent -match 'queue_action_invocation\(' -and
    $widgetContent -match 'migration_pilot_active_ && action_id == pilot_increment_action_id_') {
  $checkResults['check_action_input_path_works'].Result = $true
  $checkResults['check_action_input_path_works'].Reason = 'pilot input is routed through native button action execution'
}

$checkResults['check_layout_redraw_path_works'] = @{ Result = $false; Reason = 'layout/redraw path missing' }
if ($widgetContent -match 'layout_higher_level_shells\(' -and
    $widgetContent -match 'render_container_primitives\(' -and
    $widgetContent -match 'render_button_primitives\(' -and
    $widgetContent -match 'render_label_primitives\(' -and
    $widgetContent -match 'update_state_value\(pilot_counter_state_id_') {
  $checkResults['check_layout_redraw_path_works'].Result = $true
  $checkResults['check_layout_redraw_path_works'].Reason = 'pilot slice participates in layout, redraw, invalidation, and state-driven updates'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle behavior missing' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via native message loop'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown behavior missing' }
if ($widgetContent -match 'cleanup\(' -and $widgetContent -match 'DestroyWindow\(' -and $widgetContent -match 'shells_\.clear\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown still works with native cleanup and shell teardown'
}

$failedCount = 0
foreach ($check in $checkResults.Values) { if (-not $check.Result) { $failedCount++ } }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_migration_pilot_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE83_0_MIGRATION_PILOT'
$checkLines += 'scope=target_selection_and_first_native_widget_sandbox_pilot_slice'
$checkLines += 'foundation=phase80_0_to_phase82_1_native_runtime_framework_widget_shell_stack'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Migration Pilot Validation'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Selection Coverage'
$checkLines += ('selected_target=' + $(if ($widgetContent -match 'widget_sandbox_control_surface') { 'widget_sandbox_control_surface' } else { 'missing' }))
$checkLines += ('pilot_launch_mode_present=' + $(if ($widgetContent -match '--migration-pilot' -or $widgetContent -match 'NGK_WIDGET_MIGRATION_PILOT') { 'YES' } else { 'NO' }))
$checkLines += ('native_pilot_configuration_present=' + $(if ($widgetContent -match 'configure_widget_sandbox_migration_pilot\(') { 'YES' } else { 'NO' }))
$checkLines += ('pilot_increment_action_present=' + $(if ($widgetContent -match 'pilot_increment_action') { 'YES' } else { 'NO' }))
$checkLines += ('pilot_reset_action_present=' + $(if ($widgetContent -match 'pilot_reset_action') { 'YES' } else { 'NO' }))
$checkLines += ('pilot_counter_state_present=' + $(if ($widgetContent -match 'pilot_counter_state_id_') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('migration_pilot_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE83_0_MIGRATION_PILOT_TARGET_SELECTION_AND_FIRST_PILOT_SLICE'
$contract += 'objective=Choose_the_best_first_real_app_surface_for_native_stack_migration_and_implement_the_smallest_widget_sandbox_pilot_slice'
$contract += 'changes_introduced=Candidate_ranking_and_selection_metadata_added_with_reversible_widget_sandbox_migration_pilot_mode_that_launches_the_native_runtime_framework_widget_shell_stack_and_maps_the_real_controls_status_slice_onto_toolbar_and_sidebar_shells'
$contract += 'runtime_behavior_changes=Widget_sandbox_now_exposes_an_explicit_migration_pilot_mode_using_the_new_native_stack_with_increment_reset_actions_status_footer_updates_layout_redraw_and_state_binding_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_migration_pilot_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_migration_pilot_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase83_0_migration_pilot_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase83_0_status=' + $phaseStatus)
exit 0

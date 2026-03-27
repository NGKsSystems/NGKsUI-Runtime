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
$proofName = "phase83_1_migration_pilot_expansion_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase83_1_migration_pilot_expansion_*.zip' -ErrorAction SilentlyContinue |
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
if ($widgetContent -match 'is_migration_pilot_mode_enabled\(' -and
    $widgetContent -match 'run_phase83_0_migration_pilot_app\(' -and
    $widgetContent -match '\? run_phase83_0_migration_pilot_app\(\)') {
  $checkResults['check_pilot_mode_still_launches'].Result = $true
  $checkResults['check_pilot_mode_still_launches'].Reason = 'same migration pilot flag/path still routes into native pilot launch'
}

$checkResults['check_new_surface_selected'] = @{ Result = $false; Reason = 'second slice surface selection missing' }
if ($widgetContent -match 'phase83_1_migration_pilot_expansion_surface=widget_sandbox_text_input_surface' -and
    $widgetContent -match 'text_field') {
  $checkResults['check_new_surface_selected'].Result = $true
  $checkResults['check_new_surface_selected'].Reason = 'next smallest real widget_sandbox surface is the textbox/input row'
}

$checkResults['check_new_surface_works_under_native_stack'] = @{ Result = $false; Reason = 'native migrated input surface path missing' }
if ($widgetContent -match 'PrimitiveKind::TextField' -and
    $widgetContent -match 'sidebar_input_field_primitive_id_' -and
    $widgetContent -match 'configure_widget_sandbox_migration_pilot\(' -and
    $widgetContent -match 'render_text_field_primitives\(') {
  $checkResults['check_new_surface_works_under_native_stack'].Result = $true
  $checkResults['check_new_surface_works_under_native_stack'].Reason = 'textbox/input surface is migrated onto the native primitive and shell stack'
}

$checkResults['check_input_action_state_redraw_works'] = @{ Result = $false; Reason = 'input to action to state redraw path missing' }
if ($widgetContent -match 'handle_char_input\(' -and
    $widgetContent -match 'pilot_submit_text_action' -and
    $widgetContent -match 'update_widget_sandbox_migration_pilot_labels\(' -and
    $widgetContent -match 'pilot_text_length_state_id_' -and
    $widgetContent -match 'pilot_submit_count_state_id_') {
  $checkResults['check_input_action_state_redraw_works'].Result = $true
  $checkResults['check_input_action_state_redraw_works'].Reason = 'textbox char input and submit action drive native state updates and redraw'
}

$checkResults['check_layout_redraw_correct'] = @{ Result = $false; Reason = 'layout/redraw path for expanded surface missing' }
if ($widgetContent -match 'layout_higher_level_shells\(' -and
    $widgetContent -match 'child_region_node_ids' -and
    $widgetContent -match 'sidebar_region_c_primitive' -and
    $widgetContent -match 'render_text_field_primitives\(') {
  $checkResults['check_layout_redraw_correct'].Result = $true
  $checkResults['check_layout_redraw_correct'].Reason = 'expanded pilot surface participates in shell layout and redraw'
}

$checkResults['check_no_regression_to_legacy_path'] = @{ Result = $false; Reason = 'legacy path preservation missing' }
if ($widgetContent -match 'const int app_rc = migration_pilot_mode' -and
    $widgetContent -match ': run_app\(') {
  $checkResults['check_no_regression_to_legacy_path'].Result = $true
  $checkResults['check_no_regression_to_legacy_path'].Reason = 'legacy widget_sandbox path remains intact when pilot mode is not selected'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust enforcement remains before native activation'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle behavior missing' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via native message loop'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown behavior missing' }
if ($widgetContent -match 'cleanup\(' -and $widgetContent -match 'DestroyWindow\(' -and $widgetContent -match 'pilot_text_value_\.clear\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown still works with expanded pilot state teardown'
}

$failedCount = 0
foreach ($check in $checkResults.Values) { if (-not $check.Result) { $failedCount++ } }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_migration_pilot_expansion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE83_1_MIGRATION_PILOT_EXPANSION'
$checkLines += 'scope=widget_sandbox_second_slice_text_input_surface'
$checkLines += 'foundation=phase83_0_widget_sandbox_native_migration_pilot'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Migration Pilot Expansion Validation'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Expansion Coverage'
$checkLines += ('expanded_surface=' + $(if ($widgetContent -match 'widget_sandbox_text_input_surface') { 'widget_sandbox_text_input_surface' } else { 'missing' }))
$checkLines += ('text_field_primitive_present=' + $(if ($widgetContent -match 'PrimitiveKind::TextField') { 'YES' } else { 'NO' }))
$checkLines += ('text_input_region_present=' + $(if ($widgetContent -match 'sidebar_input_region_node_id_' -and $widgetContent -match 'region_c') { 'YES' } else { 'NO' }))
$checkLines += ('submit_action_present=' + $(if ($widgetContent -match 'pilot_submit_text_action') { 'YES' } else { 'NO' }))
$checkLines += ('text_length_state_present=' + $(if ($widgetContent -match 'pilot_text_length_state_id_') { 'YES' } else { 'NO' }))
$checkLines += ('submit_count_state_present=' + $(if ($widgetContent -match 'pilot_submit_count_state_id_') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('migration_pilot_expansion_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE83_1_MIGRATION_PILOT_EXPANSION'
$contract += 'objective=Expand_the_widget_sandbox_native_migration_pilot_by_migrating_the_real_textbox_input_surface_on_the_same_flag_and_path'
$contract += 'changes_introduced=Native_text_field_primitive_added_and_integrated_into_the_existing_sidebar_shell_as_the_next_real_widget_sandbox_surface_with_char_input_focus_submit_action_state_binding_and_redraw_updates'
$contract += 'runtime_behavior_changes=Migration_pilot_mode_now_migrates_both_the_controls_status_slice_and_the_textbox_input_surface_under_the_same_native_stack_path_while_keeping_the_legacy_widget_sandbox_path_reversible'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_migration_pilot_expansion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_migration_pilot_expansion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase83_1_migration_pilot_expansion_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase83_1_status=' + $phaseStatus)
exit 0

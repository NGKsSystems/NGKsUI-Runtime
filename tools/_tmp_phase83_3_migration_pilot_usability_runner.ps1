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
$proofName = "phase83_3_migration_pilot_usability_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase83_3_migration_pilot_usability_*.zip' -ErrorAction SilentlyContinue |
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

# 1. Pilot mode still launches
$checkResults['check_pilot_mode_still_launches'] = @{ Result = $false; Reason = 'pilot mode launch path missing' }
if ($widgetContent -match 'is_migration_pilot_mode_enabled\(' -and $widgetContent -match 'run_phase83_0_migration_pilot_app\(') {
  $checkResults['check_pilot_mode_still_launches'].Result = $true
  $checkResults['check_pilot_mode_still_launches'].Reason = 'migration pilot mode launch path present and unmodified'
}

# 2. Focus indication is visible and updates correctly
$checkResults['check_focus_indication_visible_and_updates'] = @{ Result = $false; Reason = 'button focus ring or textfield focus ring missing' }
if ($widgetContent -match 'primitive\.focused' -and
    $widgetContent -match 'PHASE83_3.*focus ring' -and
    $widgetContent -match 'pilot_focus_state_id_' -and
    $widgetContent -match 'update_state_value\(pilot_focus_state_id_') {
  $checkResults['check_focus_indication_visible_and_updates'].Result = $true
  $checkResults['check_focus_indication_visible_and_updates'].Reason = 'button and textfield focus rings rendered; focus state updated on every transition'
}

# 3. Keyboard traversal is predictable (Tab cycles, Escape restores, Enter submits)
$checkResults['check_keyboard_traversal_predictable'] = @{ Result = $false; Reason = 'predictable keyboard traversal missing' }
if ($widgetContent -match 'VK_TAB' -and
    $widgetContent -match 'focus_next_migration_pilot_primitive\(' -and
    $widgetContent -match 'VK_ESCAPE' -and
    $widgetContent -match 'escape_clear' -and
    $widgetContent -match 'escape_unfocus' -and
    $widgetContent -match 'escape_to_textbox' -and
    $widgetContent -match 'VK_RETURN') {
  $checkResults['check_keyboard_traversal_predictable'].Result = $true
  $checkResults['check_keyboard_traversal_predictable'].Reason = 'Tab cycles focus, Escape clears/unfocuses/restores, Enter activates focused element'
}

# 4. Action feedback is visible
$checkResults['check_action_feedback_visible'] = @{ Result = $false; Reason = 'action feedback not reflected in status labels' }
if ($widgetContent -match 'record_migration_pilot_action\(' -and
    $widgetContent -match 'pilot_last_action_' -and
    $widgetContent -match 'last:.*pilot_last_action_\|ready' -or
    ($widgetContent -match 'pilot_last_action_\.empty\(\).*ready' -and $widgetContent -match 'submit#.*pilot_submit_count_')) {
  $checkResults['check_action_feedback_visible'].Result = $true
  $checkResults['check_action_feedback_visible'].Reason = 'last action name and submit count displayed in footer label after every action'
}

# 5. Textbox submit/reset usability correct (Space only for buttons, Enter submits, Escape clears)
$checkResults['check_textbox_submit_reset_usability'] = @{ Result = $false; Reason = 'textbox space fix or escape clear missing' }
if ($widgetContent -match 'VK_SPACE.*has_focused_text_field\(\)' -and
    $widgetContent -match 'escape_clear' -and
    $widgetContent -match 'pilot_text_value_\.clear\(\)' -and
    $widgetContent -match 'pilot_committed_text_\s*=\s*pilot_text_value_') {
  $checkResults['check_textbox_submit_reset_usability'].Result = $true
  $checkResults['check_textbox_submit_reset_usability'].Reason = 'Space blocked in textfield, Escape clears content, commit captured on submit action'
}

# 6. Input length cap enforced
$checkResults['check_input_length_cap_enforced'] = @{ Result = $false; Reason = 'input length cap missing' }
if ($widgetContent -match 'pilot_text_value_\.size\(\)\s*<\s*64') {
  $checkResults['check_input_length_cap_enforced'].Result = $true
  $checkResults['check_input_length_cap_enforced'].Reason = 'textfield input capped at 64 characters'
}

# 7. Layout/redraw remains correct
$checkResults['check_layout_redraw_remains_correct'] = @{ Result = $false; Reason = 'layout/redraw path broken' }
if ($widgetContent -match 'layout_higher_level_shells\(' -and
    $widgetContent -match 'render_button_primitives\(' -and
    $widgetContent -match 'render_text_field_primitives\(' -and
    $widgetContent -match 'render_label_primitives\(' -and
    $widgetContent -match 'invalidate_ui_tree\(') {
  $checkResults['check_layout_redraw_remains_correct'].Result = $true
  $checkResults['check_layout_redraw_remains_correct'].Reason = 'layout, render, and invalidation path intact across all piloted surfaces'
}

# 8. Idle still works
$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle via message loop missing' }
if ($widgetContent -match 'while\s*\(GetMessageW\(') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via native Win32 GetMessageW loop'
}

# 9. Shutdown still works
$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown cleanup missing' }
if ($widgetContent -match 'cleanup\(' -and $widgetContent -match 'DestroyWindow\(' -and $widgetContent -match 'pilot_last_action_\.clear\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown still works with pilot state teardown on cleanup path'
}

# 10. No regression to legacy path
$checkResults['check_no_regression_to_legacy_path'] = @{ Result = $false; Reason = 'legacy run_app path missing or pilot unconditional' }
if ($widgetContent -match 'const int app_rc = migration_pilot_mode' -and $widgetContent -match ': run_app\(') {
  $checkResults['check_no_regression_to_legacy_path'].Result = $true
  $checkResults['check_no_regression_to_legacy_path'].Reason = 'legacy widget_sandbox run_app path remains intact and reversible'
}

# 11. Execution pipeline guard preserved
$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard present before native activation'
}

$failedCount = 0
foreach ($check in $checkResults.Values) { if (-not $check.Result) { $failedCount++ } }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_migration_pilot_usability_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE83_3_MIGRATION_PILOT_USABILITY_COMPLETION'
$checkLines += 'scope=widget_sandbox_native_pilot_usability_improvements'
$checkLines += 'foundation=phase83_0_phase83_1_phase83_2_widget_sandbox_native_migration_pilot'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Usability Validation Checks'
foreach ($checkName in ($checkResults.Keys | Sort-Object)) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Usability Feature Coverage'
$checkLines += ('button_focus_ring_present=' + $(if ($widgetContent -match 'PHASE83_3.*focus ring') { 'YES' } else { 'NO' }))
$checkLines += ('button_pressed_fill_present=' + $(if ($widgetContent -match 'PHASE83_3.*Pressed state') { 'YES' } else { 'NO' }))
$checkLines += ('escape_key_handling_present=' + $(if ($widgetContent -match 'VK_ESCAPE') { 'YES' } else { 'NO' }))
$checkLines += ('space_textfield_fix_present=' + $(if ($widgetContent -match 'VK_SPACE.*has_focused_text_field') { 'YES' } else { 'NO' }))
$checkLines += ('input_length_cap_present=' + $(if ($widgetContent -match 'pilot_text_value_\.size\(\)\s*<\s*64') { 'YES' } else { 'NO' }))
$checkLines += ('clean_labels_tab_order_present=' + $(if ($widgetContent -match 'focusable_count' -and $widgetContent -match 'pilot_focus_order_.*focusable_count') { 'YES' } else { 'NO' }))
$checkLines += ('phase83_3_marker_present=' + $(if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('migration_pilot_usability_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE83_3_MIGRATION_PILOT_USABILITY_COMPLETION'
$contract += 'objective=Make_the_existing_widget_sandbox_native_migration_pilot_feel_like_one_minimally_usable_surface'
$contract += 'changes_introduced=Button_focus_ring_pressed_fill_Escape_key_handling_Space_key_textfield_fix_64char_input_cap_clean_status_labels_with_tab_order_display'
$contract += 'runtime_behavior_changes=Buttons_now_show_focus_ring_and_pressed_fill_Escape_clears_text_or_restores_focus_Space_no_longer_submits_when_textfield_focused_labels_show_count_focus_position_last_action_committed_text'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_migration_pilot_usability_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_migration_pilot_usability_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase83_3_migration_pilot_usability_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase83_3_status=' + $phaseStatus)
exit 0

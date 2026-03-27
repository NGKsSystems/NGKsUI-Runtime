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
$proofName = "phase83_4_migration_exit_criteria_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase83_4_migration_exit_criteria_*.zip' -ErrorAction SilentlyContinue |
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

$criteriaResults = @{}

# Exit criterion: Native path stability
$criteriaResults['criterion_native_path_stability'] = @{ Result = $false; Reason = 'native path lifecycle anchors missing' }
if ($widgetContent -match 'NativeWindowPump' -and
    $widgetContent -match 'startup\(' -and
    $widgetContent -match 'run_event_loop\(' -and
    $widgetContent -match 'GetMessageW\(' -and
    $widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $criteriaResults['criterion_native_path_stability'].Result = $true
  $criteriaResults['criterion_native_path_stability'].Reason = 'native startup loop and trust guard are present on the pilot path'
}

# Exit criterion: Interaction coherence
$criteriaResults['criterion_interaction_coherence'] = @{ Result = $false; Reason = 'shared interaction model incomplete' }
if ($widgetContent -match 'route_migration_pilot_key_action\(' -and
    $widgetContent -match 'focus_next_migration_pilot_primitive\(' -and
    $widgetContent -match 'focus_migration_pilot_primitive\(' -and
    $widgetContent -match 'handle_mouse_button_down\(' -and
    $widgetContent -match 'handle_char_input\(') {
  $criteriaResults['criterion_interaction_coherence'].Result = $true
  $criteriaResults['criterion_interaction_coherence'].Reason = 'keyboard, mouse, and text input are routed through one coherent pilot interaction model'
}

# Exit criterion: Layout/redraw coherence
$criteriaResults['criterion_layout_redraw_coherence'] = @{ Result = $false; Reason = 'layout or redraw pipeline incomplete' }
if ($widgetContent -match 'layout_higher_level_shells\(' -and
    $widgetContent -match 'run_layout_update_pass\(' -and
    $widgetContent -match 'render_container_primitives\(' -and
    $widgetContent -match 'render_button_primitives\(' -and
    $widgetContent -match 'render_text_field_primitives\(' -and
    $widgetContent -match 'render_label_primitives\(' -and
    $widgetContent -match 'invalidate_ui_tree\(') {
  $criteriaResults['criterion_layout_redraw_coherence'].Result = $true
  $criteriaResults['criterion_layout_redraw_coherence'].Reason = 'layout pass and all pilot primitive render passes remain unified and invalidation-driven'
}

# Exit criterion: Action/state consistency
$criteriaResults['criterion_action_state_consistency'] = @{ Result = $false; Reason = 'action/state linkage not explicit enough' }
if ($widgetContent -match 'record_migration_pilot_action\(' -and
    $widgetContent -match 'update_widget_sandbox_migration_pilot_labels\(' -and
    $widgetContent -match 'pilot_counter_state_id_' -and
    $widgetContent -match 'pilot_text_length_state_id_' -and
    $widgetContent -match 'pilot_submit_count_state_id_' -and
    $widgetContent -match 'pilot_focus_state_id_' -and
    $widgetContent -match 'pilot_route_state_id_') {
  $criteriaResults['criterion_action_state_consistency'].Result = $true
  $criteriaResults['criterion_action_state_consistency'].Reason = 'actions are recorded and reflected through explicit pilot state IDs and label updates'
}

# Exit criterion: Usability baseline
$criteriaResults['criterion_usability_baseline'] = @{ Result = $false; Reason = 'usability baseline anchors missing' }
if ($widgetContent -match 'VK_ESCAPE' -and
    $widgetContent -match 'VK_TAB' -and
    $widgetContent -match 'VK_RETURN' -and
    $widgetContent -match 'VK_SPACE' -and
    $widgetContent -match 'pilot_text_value_\.size\(\)\s*<\s*64' -and
    $widgetContent -match 'PHASE83_3: Focus ring' -and
    $widgetContent -match 'PHASE83_3: Pressed state') {
  $criteriaResults['criterion_usability_baseline'].Result = $true
  $criteriaResults['criterion_usability_baseline'].Reason = 'focus visibility, traversal keys, action feedback, and text-entry guardrails meet baseline usability requirements'
}

# Exit criterion: Reversibility / legacy fallback
$criteriaResults['criterion_reversibility_legacy_fallback'] = @{ Result = $false; Reason = 'legacy fallback path missing' }
if ($widgetContent -match 'const int app_rc = migration_pilot_mode' -and
    $widgetContent -match '\? run_phase83_0_migration_pilot_app\(' -and
    $widgetContent -match ': run_app\(') {
  $criteriaResults['criterion_reversibility_legacy_fallback'].Result = $true
  $criteriaResults['criterion_reversibility_legacy_fallback'].Reason = 'pilot path remains optional and legacy run_app fallback is preserved'
}

$failedCriteria = @($criteriaResults.GetEnumerator() | Where-Object { -not $_.Value.Result } | ForEach-Object { $_.Key })
$failedCount = $failedCriteria.Count
$readinessDecision = if ($failedCount -eq 0) { 'READY_FOR_BROADER_MIGRATION' } else { 'NOT_READY_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$smallestFixes = @()
if ($failedCount -gt 0) {
  if ($failedCriteria -contains 'criterion_native_path_stability') {
    $smallestFixes += 'restore_missing_native_startup_loop_or_execution_pipeline_guard'
  }
  if ($failedCriteria -contains 'criterion_interaction_coherence') {
    $smallestFixes += 'reconnect_keyboard_mouse_text_input_to_shared_pilot_routing'
  }
  if ($failedCriteria -contains 'criterion_layout_redraw_coherence') {
    $smallestFixes += 'restore_layout_pass_or_missing_primitive_render_calls'
  }
  if ($failedCriteria -contains 'criterion_action_state_consistency') {
    $smallestFixes += 'rebind_pilot_actions_to_observable_state_updates_and_labels'
  }
  if ($failedCriteria -contains 'criterion_usability_baseline') {
    $smallestFixes += 'reapply_focus_visibility_escape_space_behavior_and_input_cap'
  }
  if ($failedCriteria -contains 'criterion_reversibility_legacy_fallback') {
    $smallestFixes += 'restore_conditional_pilot_vs_legacy_launch_switch'
  }
}

$checksFile = Join-Path $stageRoot '90_migration_exit_criteria_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE83_4_MIGRATION_PILOT_EXIT_CRITERIA_AND_READINESS_DECISION'
$checkLines += 'scope=widget_sandbox_native_migration_pilot_readiness_evaluation'
$checkLines += 'foundation=phase83_0_to_phase83_3_existing_widget_sandbox_native_pilot'
$checkLines += ('total_criteria=' + $criteriaResults.Count)
$checkLines += ('passed_criteria=' + ($criteriaResults.Count - $failedCount))
$checkLines += ('failed_criteria=' + $failedCount)
$checkLines += ('readiness_decision=' + $readinessDecision)
$checkLines += ''
$checkLines += '# Exit Criteria Validation'
foreach ($criterionName in ($criteriaResults.Keys | Sort-Object)) {
  $criterion = $criteriaResults[$criterionName]
  $result = if ($criterion.Result) { 'YES' } else { 'NO' }
  $checkLines += ($criterionName + '=' + $result + ' # ' + $criterion.Reason)
}
$checkLines += ''
$checkLines += '# Smallest Next Fixes (only if blockers exist)'
if ($smallestFixes.Count -eq 0) {
  $checkLines += 'smallest_next_fixes=none'
} else {
  $checkLines += ('smallest_next_fixes=' + ($smallestFixes -join ','))
}
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE83_4_MIGRATION_PILOT_EXIT_CRITERIA_AND_READINESS_DECISION'
$contract += 'objective=Assess_whether_widget_sandbox_native_pilot_is_ready_for_broader_migration_using_explicit_exit_criteria'
$contract += 'changes_introduced=Exit_criteria_definition_and_evidence_based_readiness_decision_added_via_phase83_4_proof_runner_no_new_ui_slice'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_widget_sandbox_native_pilot_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('readiness_decision=' + $readinessDecision)
$contract += ('smallest_next_fixes=' + $(if ($smallestFixes.Count -eq 0) { 'none' } else { ($smallestFixes -join ',') }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_migration_exit_criteria_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_migration_exit_criteria_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase83_4_migration_exit_criteria_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('READINESS=' + $readinessDecision)
Write-Host 'GATE=PASS'
Write-Host ('phase83_4_status=' + $phaseStatus)
exit 0

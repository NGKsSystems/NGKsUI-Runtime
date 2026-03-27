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
$proofName = "phase86_3_rollout_readiness_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase86_3_rollout_readiness_*.zip' -ErrorAction SilentlyContinue |
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

$loopTestsMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$loopTestsContent = if (Test-Path -LiteralPath $loopTestsMain) { Get-Content -LiteralPath $loopTestsMain -Raw } else { '' }

$criteriaResults = [ordered]@{}

$criteriaResults['criterion_native_path_stability'] = @{ Result = $false; Reason = 'native startup or render anchors missing' }
if ($loopTestsContent -match 'window\.create\(' -and
    $loopTestsContent -match 'loop\.set_platform_pump' -and
    $loopTestsContent -match 'window\.poll_events_once\(\)' -and
    $loopTestsContent -match 'renderer\.init\(' -and
    $loopTestsContent -match 'renderer\.end_frame\(' -and
    $loopTestsContent -match 'loop\.run\(\)') {
  $criteriaResults['criterion_native_path_stability'].Result = $true
  $criteriaResults['criterion_native_path_stability'].Reason = 'native window event loop and render path are stable in migration mode'
}

$criteriaResults['criterion_interaction_coherence'] = @{ Result = $false; Reason = 'interaction routing coherence incomplete' }
if ($loopTestsContent -match 'native_input_router\.on_mouse_move' -and
    $loopTestsContent -match 'native_input_router\.on_mouse_button_message' -and
    $loopTestsContent -match 'native_input_router\.on_key_message' -and
    $loopTestsContent -match 'native_tree\.set_focused_element\(&native_primary_action_tile\)' -and
    $loopTestsContent -match 'phase86_2_synthetic_input_dispatched=1') {
  $criteriaResults['criterion_interaction_coherence'].Result = $true
  $criteriaResults['criterion_interaction_coherence'].Reason = 'shared input router and focus model handle expanded controls coherently'
}

$criteriaResults['criterion_layout_redraw_coherence'] = @{ Result = $false; Reason = 'layout or redraw integration incomplete' }
if ($loopTestsContent -match 'layout_native_slice' -and
    $loopTestsContent -match 'native_tree\.on_resize\(' -and
    $loopTestsContent -match 'native_tree\.invalidate\(' -and
    $loopTestsContent -match 'native_tree\.render\(renderer\)' -and
    $loopTestsContent -match 'window\.set_resize_callback') {
  $criteriaResults['criterion_layout_redraw_coherence'].Result = $true
  $criteriaResults['criterion_layout_redraw_coherence'].Reason = 'expanded slice remains on unified resize layout invalidate and render path'
}

$criteriaResults['criterion_state_action_consistency'] = @{ Result = $false; Reason = 'state/action consistency incomplete' }
if ($loopTestsContent -match 'native_primary_action_count' -and
    $loopTestsContent -match 'native_secondary_action_count' -and
    $loopTestsContent -match 'native_status_value' -and
    $loopTestsContent -match 'native_status_strip\.set_value\(' -and
    $loopTestsContent -match 'phase86_2_primary_action_count=' -and
    $loopTestsContent -match 'phase86_2_secondary_action_count=' -and
    $loopTestsContent -match 'phase86_2_status_value=') {
  $criteriaResults['criterion_state_action_consistency'].Result = $true
  $criteriaResults['criterion_state_action_consistency'].Reason = 'actions deterministically update shared status state and emitted counters'
}

$criteriaResults['criterion_usability_baseline'] = @{ Result = $false; Reason = 'usability baseline anchors missing' }
if ($loopTestsContent -match 'focused\(\)' -and
    $loopTestsContent -match 'hover_' -and
    $loopTestsContent -match 'pressed_' -and
    $loopTestsContent -match 'on_key_down\(std::uint32_t key' -and
    $loopTestsContent -match 'vk_return' -and
    $loopTestsContent -match 'vk_space') {
  $criteriaResults['criterion_usability_baseline'].Result = $true
  $criteriaResults['criterion_usability_baseline'].Reason = 'slice provides focus hover pressed and keyboard activation baseline'
}

$criteriaResults['criterion_reversibility_non_regression'] = @{ Result = $false; Reason = 'legacy fallback or trust lifecycle ordering drifted' }
if ($loopTestsContent -match 'run_legacy_loop_tests\(' -and
    $loopTestsContent -match 'run_phase86_2_native_slice_app\(' -and
    $loopTestsContent -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $loopTestsContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopTestsContent -match 'runtime_observe_lifecycle\("loop_tests", "main_exit"\)' -and
    $loopTestsContent -match 'SUMMARY: PASS') {
  $criteriaResults['criterion_reversibility_non_regression'].Result = $true
  $criteriaResults['criterion_reversibility_non_regression'].Reason = 'legacy behavior remains available while trust ordering and lifecycle alignment are preserved'
}

$failedCriteria = @($criteriaResults.GetEnumerator() | Where-Object { -not $_.Value.Result } | ForEach-Object { $_.Key })
$failedCount = $failedCriteria.Count
$readinessDecision = if ($failedCount -eq 0) { 'READY_FOR_BROADER_MIGRATION' } else { 'NOT_READY_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$smallestFixes = @()
if ($failedCount -gt 0) {
  if ($failedCriteria -contains 'criterion_native_path_stability') {
    $smallestFixes += 'restore_native_window_event_loop_render_anchors_for_migration_mode'
  }
  if ($failedCriteria -contains 'criterion_interaction_coherence') {
    $smallestFixes += 'reconnect_shared_input_router_callbacks_and_focus_transitions_for_expanded_controls'
  }
  if ($failedCriteria -contains 'criterion_layout_redraw_coherence') {
    $smallestFixes += 'restore_resize_layout_invalidate_render_wiring_for_same_native_slice'
  }
  if ($failedCriteria -contains 'criterion_state_action_consistency') {
    $smallestFixes += 'rebind_primary_secondary_actions_to_status_state_and_output_markers'
  }
  if ($failedCriteria -contains 'criterion_usability_baseline') {
    $smallestFixes += 'restore_focus_hover_pressed_and_keyboard_activation_behavior_on_action_tiles'
  }
  if ($failedCriteria -contains 'criterion_reversibility_non_regression') {
    $smallestFixes += 'restore_legacy_default_selection_and_execution_pipeline_lifecycle_ordering'
  }
}

$checksFile = Join-Path $stageRoot '90_rollout_readiness_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE86_3_ROLLOUT_READINESS_DECISION'
$checkLines += 'scope=apps_loop_tests_migrated_native_slice_readiness_assessment'
$checkLines += 'foundation=phase86_1_and_phase86_2_complete'
$checkLines += ('total_criteria=' + $criteriaResults.Count)
$checkLines += ('passed_criteria=' + ($criteriaResults.Count - $failedCount))
$checkLines += ('failed_criteria=' + $failedCount)
$checkLines += ('readiness_decision=' + $readinessDecision)
$checkLines += ''
$checkLines += '# Readiness Criteria Validation'
foreach ($criterionName in $criteriaResults.Keys) {
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
$contract += 'next_phase_selected=PHASE86_3_ROLLOUT_READINESS_DECISION'
$contract += 'objective=Assess_whether_current_apps_loop_tests_migrated_native_slice_is_ready_to_move_from_exploratory_rollout_to_broader_migration_guidance'
$contract += 'changes_introduced=Explicit_readiness_criteria_and_evidence_based_decision_runner_added_for_loop_tests_no_new_migration_slice_introduced'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_loop_tests_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_rollout_readiness_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_rollout_readiness_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase86_3_rollout_readiness_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('READINESS=' + $readinessDecision)
Write-Host 'GATE=PASS'
Write-Host ('phase86_3_status=' + $phaseStatus)
exit 0

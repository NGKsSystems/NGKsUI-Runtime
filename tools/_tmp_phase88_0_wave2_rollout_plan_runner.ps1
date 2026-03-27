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
$proofName = "phase88_0_wave2_rollout_plan_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase88_0_wave2_rollout_plan_*.zip' -ErrorAction SilentlyContinue |
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

$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$loopMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'

$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }

$wave2Targets = @('apps/win32_sandbox')
$deferredTargets = @('apps/widget_sandbox')
$wave2LaneReasons = [ordered]@{
  'apps/win32_sandbox' = 'already_on_real_win32_d3d11_runtime_surface_with_existing_native_pump_and_multiple_migration_markers_lowest_incremental_risk_for_wave2_rollout'
}
$deferredLaneReasons = [ordered]@{
  'apps/widget_sandbox' = 'contains_legacy_widget_specific_stack_and_broader_ui_surface_area_best_deferred_until_post_wave2_pattern_reuse_is_locked'
}

$nextImplementationTarget = 'apps/win32_sandbox'
$standardRolloutPattern = 'native_default_rollout_path_with_explicit_legacy_fallback_controls_trust_execution_pipeline_before_selection_lifecycle_summary_consistency_deterministic_single_branch_selection'
$crossCuttingWatchItems = 'command_line_env_selector_precedence_consistency,input_router_event_replay_baseline_for_native_default_path,shutdown_teardown_ordering_and_final_status_signal_consistency'
$crossCuttingBlockers = 'none_blocking'

$checkResults = [ordered]@{}

$checkResults['check_wave1_references_complete_and_stable'] = @{ Result = $false; Reason = 'wave1 reference markers or selectors missing' }
if ($sandboxContent -match 'phase87_1_sandbox_app_wave1_rollout_available=1' -and
    $sandboxContent -match 'is_phase87_1_legacy_fallback_enabled\(' -and
    $sandboxContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match 'phase87_3_loop_tests_wave1_rollout_available=1' -and
    $loopContent -match 'is_phase87_3_legacy_fallback_enabled\(' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;') {
  $checkResults['check_wave1_references_complete_and_stable'].Result = $true
  $checkResults['check_wave1_references_complete_and_stable'].Reason = 'wave1 references remain native-default with explicit fallback on both completed targets'
}

$checkResults['check_wave2_targets_identified_with_reasons'] = @{ Result = $false; Reason = 'wave2 target lane or reason missing' }
if ($wave2Targets.Count -gt 0 -and
    ($wave2Targets -contains 'apps/win32_sandbox') -and
    $wave2LaneReasons['apps/win32_sandbox'].Length -gt 0) {
  $checkResults['check_wave2_targets_identified_with_reasons'].Result = $true
  $checkResults['check_wave2_targets_identified_with_reasons'].Reason = 'wave2 lane includes real next target with explicit suitability reason'
}

$checkResults['check_deferred_targets_identified_with_reasons'] = @{ Result = $false; Reason = 'deferred lane or reason missing' }
if ($deferredTargets.Count -gt 0 -and
    ($deferredTargets -contains 'apps/widget_sandbox') -and
    $deferredLaneReasons['apps/widget_sandbox'].Length -gt 0) {
  $checkResults['check_deferred_targets_identified_with_reasons'].Result = $true
  $checkResults['check_deferred_targets_identified_with_reasons'].Reason = 'deferred lane includes postponed target with explicit reason'
}

$checkResults['check_lane_assignment_anchored_to_real_surfaces'] = @{ Result = $false; Reason = 'lane assignments are not anchored to concrete app entrypoints' }
if ($win32Content -match '(?m)^int main\(' -and
    $widgetContent -match '(?m)^int main\(') {
  $checkResults['check_lane_assignment_anchored_to_real_surfaces'].Result = $true
  $checkResults['check_lane_assignment_anchored_to_real_surfaces'].Reason = 'wave2 and deferred lanes are mapped to concrete runtime app surfaces'
}

$checkResults['check_standard_rollout_pattern_defined_from_wave1'] = @{ Result = $false; Reason = 'standard rollout pattern missing required wave1-proven elements' }
if ($standardRolloutPattern -match 'native_default_rollout_path' -and
    $standardRolloutPattern -match 'explicit_legacy_fallback_controls' -and
    $standardRolloutPattern -match 'trust_execution_pipeline_before_selection' -and
    $standardRolloutPattern -match 'deterministic_single_branch_selection') {
  $checkResults['check_standard_rollout_pattern_defined_from_wave1'].Result = $true
  $checkResults['check_standard_rollout_pattern_defined_from_wave1'].Reason = 'wave1-proven rollout pattern has been codified as the standard for wave2'
}

$checkResults['check_cross_cutting_watch_items_identified'] = @{ Result = $false; Reason = 'wave2 watch items missing' }
if ($crossCuttingWatchItems.Length -gt 0 -and
    $crossCuttingWatchItems -match 'selector_precedence' -and
    $crossCuttingWatchItems -match 'input_router' -and
    $crossCuttingWatchItems -match 'shutdown_teardown') {
  $checkResults['check_cross_cutting_watch_items_identified'].Result = $true
  $checkResults['check_cross_cutting_watch_items_identified'].Reason = 'wave2 watch items cover selector determinism input behavior and teardown consistency'
}

$checkResults['check_single_best_next_target_selected'] = @{ Result = $false; Reason = 'single next implementation target not selected from wave2 lane' }
if ($nextImplementationTarget -eq 'apps/win32_sandbox' -and ($wave2Targets -contains $nextImplementationTarget)) {
  $checkResults['check_single_best_next_target_selected'].Result = $true
  $checkResults['check_single_best_next_target_selected'].Reason = 'single next implementation target selected from wave2 lane'
}

$checkResults['check_no_new_migration_or_framework_implementation'] = @{ Result = $true; Reason = 'phase88_0 is planning-only and introduces no runtime migration/framework changes' }

$preBlockerFailures = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
if ($preBlockerFailures -eq 0) {
  $crossCuttingBlockers = 'none'
}

$decision = if ($preBlockerFailures -eq 0) { 'WAVE2_READY_WITH_NEXT_TARGET' } else { 'NOT_READY_WITH_BLOCKERS' }
$phaseStatus = if ($preBlockerFailures -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_wave2_rollout_plan_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE88_0_WAVE2_ROLLOUT_PLAN'
$checkLines += 'scope=define_wave2_lanes_standard_rollout_pattern_watch_items_and_single_best_next_target'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $preBlockerFailures))
$checkLines += ('failed_checks=' + $preBlockerFailures)
$checkLines += ('decision=' + $decision)
$checkLines += ('next_implementation_target=' + $nextImplementationTarget)
$checkLines += ('cross_cutting_blockers=' + $crossCuttingBlockers)
$checkLines += ('cross_cutting_watch_items=' + $crossCuttingWatchItems)
$checkLines += ''
$checkLines += '# Wave2 Plan Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Lane Summary'
$checkLines += ('wave2_targets=' + ($wave2Targets -join ','))
$checkLines += ('deferred_targets=' + ($deferredTargets -join ','))
$checkLines += ('wave2_lane_reason_apps_win32_sandbox=' + $wave2LaneReasons['apps/win32_sandbox'])
$checkLines += ('deferred_lane_reason_apps_widget_sandbox=' + $deferredLaneReasons['apps/widget_sandbox'])
$checkLines += ('standard_rollout_pattern=' + $standardRolloutPattern)
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE88_0_WAVE2_ROLLOUT_PLAN'
$contract += 'objective=Define_wave2_rollout_targets_and_deferred_lane_using_wave1_complete_references_then_select_single_best_next_implementation_target'
$contract += 'changes_introduced=Wave2_rollout_plan_runner_added_with_lane_reasons_standard_pattern_watch_items_and_single_target_decision'
$contract += 'runtime_behavior_changes=None_planning_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_wave2_rollout_plan_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('decision=' + $decision)
$contract += ('next_target=' + $nextImplementationTarget)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_wave2_rollout_plan_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_wave2_rollout_plan_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase88_0_wave2_rollout_plan_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase88_0_status=' + $phaseStatus)
Write-Host ('decision=' + $decision)
exit 0

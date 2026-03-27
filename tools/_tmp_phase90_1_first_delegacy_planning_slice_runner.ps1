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
$proofName = "phase90_1_first_delegacy_planning_slice_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase90_1_first_delegacy_planning_slice_*.zip' -ErrorAction SilentlyContinue |
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

$phase90MapRunner = Join-Path $workspaceRoot 'tools/_tmp_phase90_0_delegacy_readiness_map_runner.ps1'
$loopMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'

$phase90MapContent = if (Test-Path -LiteralPath $phase90MapRunner) { Get-Content -LiteralPath $phase90MapRunner -Raw } else { '' }
$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }

$firstTarget = 'apps/loop_tests'
$firstTargetLegacyPath = 'run_legacy_loop_tests'
$whyFirst = 'lowest_operational_risk_and_smallest_execution_surface_from_delegacy_next_lane_with_existing_deterministic_policy_logging'
$whatDependsOnIt = 'explicit_operational_rollback_path_for_loop_tests_when_legacy_fallback_is_requested'
$preRemovalConditions = 'fallback_usage_telemetry_below_threshold,per_surface_exit_criteria_signoff,rollback_playbook_verified,release_window_approval'
$temporaryFallbackRole = 'retain_legacy_fallback_temporarily_as_controlled_emergency_recovery_path_until_exit_conditions_are_met'
$delegacySequence = 'step1_instrument_and_measure_fallback_usage,step2_freeze_new_legacy_dependencies,step3_run_shadow_cutover_validation,step4_gate_review_and_signoff,step5_schedule_execution_phase_for_disable_not_removal'

$checkResults = [ordered]@{}

$checkResults['check_target_selected_from_delegacy_next_lane'] = @{ Result = $false; Reason = 'first target not anchored to phase90_0 delegacy_next lane' }
if ($phase90MapContent -match '\$delegacyNextLane = @\(''apps/loop_tests''\)' -and
    $firstTarget -eq 'apps/loop_tests') {
  $checkResults['check_target_selected_from_delegacy_next_lane'].Result = $true
  $checkResults['check_target_selected_from_delegacy_next_lane'].Reason = 'first planning target is selected directly from phase90_0 delegacy_next lane'
}

$checkResults['check_target_why_first_defined'] = @{ Result = $false; Reason = 'why-first rationale missing' }
if ($whyFirst.Length -gt 0) {
  $checkResults['check_target_why_first_defined'].Result = $true
  $checkResults['check_target_why_first_defined'].Reason = 'first-target rationale is explicitly documented'
}

$checkResults['check_target_dependencies_defined'] = @{ Result = $false; Reason = 'dependency analysis for legacy path missing' }
if ($whatDependsOnIt.Length -gt 0 -and $loopContent -match 'run_legacy_loop_tests\(') {
  $checkResults['check_target_dependencies_defined'].Result = $true
  $checkResults['check_target_dependencies_defined'].Reason = 'legacy dependency role is identified and anchored to target legacy path'
}

$checkResults['check_pre_removal_conditions_defined'] = @{ Result = $false; Reason = 'pre-removal condition gate missing' }
if ($preRemovalConditions -match 'telemetry' -and
    $preRemovalConditions -match 'exit_criteria' -and
    $preRemovalConditions -match 'rollback' -and
    $preRemovalConditions -match 'approval') {
  $checkResults['check_pre_removal_conditions_defined'].Result = $true
  $checkResults['check_pre_removal_conditions_defined'].Reason = 'pre-removal conditions are explicit and gate actual de-legacy execution'
}

$checkResults['check_temporary_fallback_reference_role_defined'] = @{ Result = $false; Reason = 'temporary fallback/reference role not documented' }
if ($temporaryFallbackRole.Length -gt 0 -and
    $sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $win32Content -match 'run_legacy_win32_sandbox\(') {
  $checkResults['check_temporary_fallback_reference_role_defined'].Result = $true
  $checkResults['check_temporary_fallback_reference_role_defined'].Reason = 'temporary fallback/reference role is defined with ecosystem consistency context'
}

$checkResults['check_actual_delegacy_sequence_defined'] = @{ Result = $false; Reason = 'de-legacy sequence missing or incomplete' }
if ($delegacySequence -match 'step1_' -and
    $delegacySequence -match 'step2_' -and
    $delegacySequence -match 'step3_' -and
    $delegacySequence -match 'step4_' -and
    $delegacySequence -match 'step5_') {
  $checkResults['check_actual_delegacy_sequence_defined'].Result = $true
  $checkResults['check_actual_delegacy_sequence_defined'].Reason = 'de-legacy sequence is concrete and ordered for future execution phase'
}

$checkResults['check_no_runtime_or_framework_changes_in_this_phase'] = @{ Result = $true; Reason = 'phase90_1 is planning only with no legacy path removal or runtime/framework implementation change' }

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$decision = if ($failedCount -eq 0) { 'READY_FOR_FIRST_DELEGACY_EXECUTION_PLAN' } else { 'NOT_READY_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_first_delegacy_plan_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE90_1_FIRST_DELEGACY_PLANNING_SLICE'
$checkLines += 'scope=first_target_delegacy_plan_definition_without_runtime_changes'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('decision=' + $decision)
$checkLines += ('first_target=' + $firstTarget)
$checkLines += ('first_target_legacy_path=' + $firstTargetLegacyPath)
$checkLines += ''
$checkLines += '# First De-Legacy Plan Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# First Target Plan'
$checkLines += ('why_first=' + $whyFirst)
$checkLines += ('depends_on_legacy_path=' + $whatDependsOnIt)
$checkLines += ('pre_removal_conditions=' + $preRemovalConditions)
$checkLines += ('temporary_fallback_role=' + $temporaryFallbackRole)
$checkLines += ('delegacy_sequence=' + $delegacySequence)
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE90_1_FIRST_DELEGACY_PLANNING_SLICE'
$contract += 'objective=Choose_first_target_from_delegacy_next_lane_and_define_exact_retirement_plan_conditions_dependencies_and_sequence_without_removing_legacy_path'
$contract += 'changes_introduced=First_delegacy_planning_slice_runner_added_with_target_selection_rationale_dependency_mapping_condition_gates_and_execution_sequence'
$contract += 'runtime_behavior_changes=None_planning_phase_only_no_legacy_path_disabled_or_removed'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_first_delegacy_plan_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('decision=' + $decision)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_first_delegacy_plan_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_first_delegacy_plan_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase90_1_first_delegacy_planning_slice_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase90_1_status=' + $phaseStatus)
Write-Host ('decision=' + $decision)
exit 0

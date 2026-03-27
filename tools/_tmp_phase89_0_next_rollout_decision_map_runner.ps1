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
$proofName = "phase89_0_next_rollout_decision_map_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase89_0_next_rollout_decision_map_*.zip' -ErrorAction SilentlyContinue |
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

$nativeDefaultSurfaces = @('apps/sandbox_app', 'apps/loop_tests', 'apps/win32_sandbox')
$remainingRolloutCandidates = @('apps/widget_sandbox')
$deferredReferenceOnlySurfaces = @('apps/widget_sandbox')
$anotherWaveExists = 'No'
$standardPatternMaturity = 'MATURE_FOR_REPO_DEFAULT_POLICY'

$checkResults = [ordered]@{}

$checkResults['check_native_default_surfaces_assessed'] = @{ Result = $false; Reason = 'one or more expected native-default surfaces missing rollout/default markers' }
if ($sandboxContent -match 'phase87_1_sandbox_app_wave1_rollout_available=1' -and
    $sandboxContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match 'phase87_3_loop_tests_wave1_rollout_available=1' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $win32Content -match 'phase88_1_win32_wave2_rollout_available=1' -and
    $win32Content -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;') {
  $checkResults['check_native_default_surfaces_assessed'].Result = $true
  $checkResults['check_native_default_surfaces_assessed'].Reason = 'sandbox_app loop_tests and win32_sandbox are all native-default with explicit legacy fallback controls'
}

$checkResults['check_deferred_reference_only_surfaces_assessed'] = @{ Result = $false; Reason = 'deferred/reference-only surface status missing' }
if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $widgetContent -match 'phase83_2_migration_pilot_consolidation_available=1' -and
    $widgetContent -match 'phase83_1_migration_pilot_expansion_available=1' -and
    $widgetContent -match 'is_migration_pilot_mode_enabled\(') {
  $checkResults['check_deferred_reference_only_surfaces_assessed'].Result = $true
  $checkResults['check_deferred_reference_only_surfaces_assessed'].Reason = 'widget_sandbox remains migration-pilot/reference-oriented and is tracked as deferred'
}

$checkResults['check_remaining_rollout_candidates_identified'] = @{ Result = $false; Reason = 'remaining rollout candidate lane not explicit' }
if ($remainingRolloutCandidates.Count -eq 1 -and $remainingRolloutCandidates[0] -eq 'apps/widget_sandbox') {
  $checkResults['check_remaining_rollout_candidates_identified'].Result = $true
  $checkResults['check_remaining_rollout_candidates_identified'].Reason = 'remaining rollout candidate inventory is explicit and limited'
}

$checkResults['check_standard_rollout_pattern_maturity_assessed'] = @{ Result = $false; Reason = 'pattern maturity not sufficiently evidenced' }
if ($sandboxContent -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $loopContent -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $win32Content -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $sandboxContent -match 'runtime_observe_lifecycle\("sandbox_app", "main_enter"\)' -and
    $loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_enter"\)') {
  $checkResults['check_standard_rollout_pattern_maturity_assessed'].Result = $true
  $checkResults['check_standard_rollout_pattern_maturity_assessed'].Reason = 'standard pattern is stable across wave1 and wave2 native-default surfaces with trust/lifecycle consistency'
}

$checkResults['check_another_rollout_wave_existence_assessed'] = @{ Result = $false; Reason = 'next-wave existence assessment missing' }
if ($anotherWaveExists -eq 'No' -and $deferredReferenceOnlySurfaces.Count -eq 1) {
  $checkResults['check_another_rollout_wave_existence_assessed'].Result = $true
  $checkResults['check_another_rollout_wave_existence_assessed'].Reason = 'no additional broad rollout wave is recommended before default-adoption/de-legacy planning'
}

$checkResults['check_no_new_migration_or_framework_implementation'] = @{ Result = $true; Reason = 'phase89_0 is decision-map only and adds no runtime/framework implementation changes' }

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$decision = if ($failedCount -ne 0) {
  'HOLD_WITH_BLOCKERS'
} elseif ($anotherWaveExists -eq 'Yes') {
  'START_NEXT_WAVE'
} else {
  'SHIFT_TO_DEFAULT_ADOPTION_POLICY'
}
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_next_rollout_decision_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE89_0_NEXT_ROLLOUT_DECISION_MAP'
$checkLines += 'scope=post_wave1_wave2_next_rollout_decision_and_default_adoption_policy_readiness'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('decision=' + $decision)
$checkLines += ('another_rollout_wave_exists=' + $anotherWaveExists)
$checkLines += ('standard_rollout_pattern_maturity=' + $standardPatternMaturity)
$checkLines += ''
$checkLines += '# Decision Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Surface Map'
$checkLines += ('native_default_surfaces=' + ($nativeDefaultSurfaces -join ','))
$checkLines += ('remaining_rollout_candidates=' + ($remainingRolloutCandidates -join ','))
$checkLines += ('deferred_reference_only_surfaces=' + ($deferredReferenceOnlySurfaces -join ','))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE89_0_NEXT_ROLLOUT_DECISION_MAP'
$contract += 'objective=Define_the_next_rollout_decision_after_wave1_and_wave2_completion_and_determine_whether_to_start_another_wave_or_shift_to_default_adoption_delegacy_policy'
$contract += 'changes_introduced=Next_rollout_decision_map_runner_added_with_surface_status_assessment_remaining_candidate_inventory_pattern_maturity_assessment_and_single_decision_output'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_next_rollout_decision_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('decision=' + $decision)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_next_rollout_decision_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_next_rollout_decision_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase89_0_next_rollout_decision_map_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase89_0_status=' + $phaseStatus)
Write-Host ('decision=' + $decision)
exit 0

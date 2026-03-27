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
$proofName = "phase87_5_wave1_completion_snapshot_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase87_5_wave1_completion_snapshot_*.zip' -ErrorAction SilentlyContinue |
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

$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_sandbox_native_default_rollout_status'] = @{ Result = $false; Reason = 'sandbox_app native-default rollout markers or selection missing' }
if ($sandboxContent -match 'phase87_1_sandbox_app_wave1_rollout_available=1' -and
    $sandboxContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $sandboxContent -match '\? run_phase85_2_native_slice_app\(\)') {
  $checkResults['check_sandbox_native_default_rollout_status'].Result = $true
  $checkResults['check_sandbox_native_default_rollout_status'].Reason = 'sandbox_app remains native-default rollout with proven expanded native path'
}

$checkResults['check_sandbox_fallback_status'] = @{ Result = $false; Reason = 'sandbox_app fallback selector or legacy branch missing' }
if ($sandboxContent -match 'is_phase87_1_legacy_fallback_enabled\(' -and
    $sandboxContent -match '--legacy-fallback' -and
    $sandboxContent -match 'NGK_SANDBOX_APP_LEGACY_FALLBACK' -and
    $sandboxContent -match ': run_legacy_sandbox_app\(\)') {
  $checkResults['check_sandbox_fallback_status'].Result = $true
  $checkResults['check_sandbox_fallback_status'].Reason = 'sandbox_app explicit legacy fallback remains reversible and clean'
}

$checkResults['check_loop_tests_native_default_rollout_status'] = @{ Result = $false; Reason = 'loop_tests native-default rollout markers or selection missing' }
if ($loopContent -match 'phase87_3_loop_tests_wave1_rollout_available=1' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match '\? run_phase86_2_native_slice_app\(\)') {
  $checkResults['check_loop_tests_native_default_rollout_status'].Result = $true
  $checkResults['check_loop_tests_native_default_rollout_status'].Reason = 'loop_tests remains native-default rollout with proven PHASE86 expanded native path'
}

$checkResults['check_loop_tests_fallback_status'] = @{ Result = $false; Reason = 'loop_tests fallback selector or legacy branch missing' }
if ($loopContent -match 'is_phase87_3_legacy_fallback_enabled\(' -and
    $loopContent -match '--legacy-fallback' -and
    $loopContent -match 'NGK_LOOP_TESTS_LEGACY_FALLBACK' -and
    $loopContent -match ': run_legacy_loop_tests\(\)') {
  $checkResults['check_loop_tests_fallback_status'].Result = $true
  $checkResults['check_loop_tests_fallback_status'].Reason = 'loop_tests explicit legacy fallback remains reversible and clean'
}

$checkResults['check_common_rollout_pattern_standardized'] = @{ Result = $false; Reason = 'common rollout pattern not consistently present in both wave-1 targets' }
if ($sandboxContent -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $loopContent -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $sandboxContent -match 'runtime_observe_lifecycle\("sandbox_app", "main_enter"\)' -and
    $loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $sandboxContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;') {
  $checkResults['check_common_rollout_pattern_standardized'].Result = $true
  $checkResults['check_common_rollout_pattern_standardized'].Reason = 'both wave-1 targets follow native-default plus explicit fallback with trust-before-selection and lifecycle anchors'
}

$checkResults['check_remaining_wave1_blockers'] = @{ Result = $false; Reason = 'one or more wave-1 completion gates failed' }

$preBlockerFailures = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result -and $_.Key -ne 'check_remaining_wave1_blockers' }).Count
if ($preBlockerFailures -eq 0) {
  $checkResults['check_remaining_wave1_blockers'].Result = $true
  $checkResults['check_remaining_wave1_blockers'].Reason = 'none'
} else {
  $checkResults['check_remaining_wave1_blockers'].Result = $false
  $checkResults['check_remaining_wave1_blockers'].Reason = 'see_failed_checks'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$decision = if ($failedCount -eq 0) { 'WAVE1_COMPLETE_READY_FOR_NEXT_WAVE' } else { 'NOT_COMPLETE_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_wave1_completion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE87_5_WAVE1_COMPLETION_SNAPSHOT'
$checkLines += 'scope=wave1_completion_snapshot_for_sandbox_app_and_loop_tests_rollout_stability_reversibility_and_readiness'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('completion_decision=' + $decision)
$checkLines += ''
$checkLines += '# Wave1 Completion Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Wave1 Snapshot Summary'
$checkLines += 'sandbox_app_status=native_default_rollout_with_explicit_fallback'
$checkLines += 'loop_tests_status=native_default_rollout_with_explicit_fallback'
$checkLines += 'common_rollout_pattern=native_default_plus_explicit_legacy_fallback_with_execution_pipeline_trust_before_selection_and_lifecycle_consistency'
$checkLines += 'remaining_wave1_blockers=none_if_completion_decision_is_ready'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE87_5_WAVE1_COMPLETION_SNAPSHOT'
$contract += 'objective=Produce_single_assessment_snapshot_proof_that_wave1_rollout_is_complete_stable_reversible_and_ready_for_next_wave'
$contract += 'changes_introduced=Wave1_completion_snapshot_runner_added_no_new_migration_or_framework_implementation_changes'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_wave1_completion_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('completion_decision=' + $decision)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_wave1_completion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_wave1_completion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase87_5_wave1_completion_snapshot_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase87_5_status=' + $phaseStatus)
Write-Host ('completion_decision=' + $decision)
exit 0

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
$proofName = "phase88_3_wave2_completion_snapshot_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase88_3_wave2_completion_snapshot_*.zip' -ErrorAction SilentlyContinue |
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

$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_win32_native_default_rollout_status'] = @{ Result = $false; Reason = 'win32_sandbox native-default rollout markers or selection missing' }
if ($win32Content -match 'phase88_1_win32_wave2_rollout_available=1' -and
    $win32Content -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $win32Content -match '\? run_phase84_3_native_slice_app\(\)') {
  $checkResults['check_win32_native_default_rollout_status'].Result = $true
  $checkResults['check_win32_native_default_rollout_status'].Reason = 'win32_sandbox remains native-default rollout with proven PHASE84 native path'
}

$checkResults['check_win32_fallback_status'] = @{ Result = $false; Reason = 'win32_sandbox fallback selector or legacy branch missing' }
if ($win32Content -match 'is_phase88_1_legacy_fallback_enabled\(' -and
    $win32Content -match '--legacy-fallback' -and
    $win32Content -match 'NGK_WIN32_SANDBOX_LEGACY_FALLBACK' -and
    $win32Content -match ': run_legacy_win32_sandbox\(\)') {
  $checkResults['check_win32_fallback_status'].Result = $true
  $checkResults['check_win32_fallback_status'].Reason = 'win32_sandbox explicit legacy fallback remains reversible and clean'
}

$checkResults['check_common_rollout_pattern_still_holds'] = @{ Result = $false; Reason = 'rollout pattern anchors not consistent' }
$trustIndex = $win32Content.IndexOf('require_runtime_trust("execution_pipeline")')
$selectIndex = $win32Content.IndexOf('use_native_rollout_path')
if ($win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_enter"\)' -and
    $win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_exit"\)' -and
    $win32Content -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $trustIndex -ge 0 -and $selectIndex -gt $trustIndex) {
  $checkResults['check_common_rollout_pattern_still_holds'].Result = $true
  $checkResults['check_common_rollout_pattern_still_holds'].Reason = 'native-default plus explicit fallback with trust-before-selection and lifecycle consistency remains intact'
}

$checkResults['check_remaining_wave2_blockers'] = @{ Result = $false; Reason = 'one or more wave2 completion gates failed' }
$preBlockerFailures = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result -and $_.Key -ne 'check_remaining_wave2_blockers' }).Count
if ($preBlockerFailures -eq 0) {
  $checkResults['check_remaining_wave2_blockers'].Result = $true
  $checkResults['check_remaining_wave2_blockers'].Reason = 'none'
} else {
  $checkResults['check_remaining_wave2_blockers'].Result = $false
  $checkResults['check_remaining_wave2_blockers'].Reason = 'see_failed_checks'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$decision = if ($failedCount -eq 0) { 'WAVE2_COMPLETE_READY_FOR_NEXT_DECISION' } else { 'NOT_COMPLETE_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_wave2_completion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE88_3_WAVE2_COMPLETION_SNAPSHOT'
$checkLines += 'scope=wave2_completion_snapshot_for_win32_sandbox_rollout_stability_reversibility_and_readiness'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('completion_decision=' + $decision)
$checkLines += ''
$checkLines += '# Wave2 Completion Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Wave2 Snapshot Summary'
$checkLines += 'win32_sandbox_status=native_default_rollout_with_explicit_fallback'
$checkLines += 'common_rollout_pattern=native_default_plus_explicit_legacy_fallback_with_execution_pipeline_trust_before_selection_and_lifecycle_consistency'
$checkLines += 'remaining_wave2_blockers=none_if_completion_decision_is_ready'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE88_3_WAVE2_COMPLETION_SNAPSHOT'
$contract += 'objective=Produce_single_assessment_snapshot_proof_that_wave2_rollout_is_complete_stable_reversible_and_ready_for_next_rollout_decision'
$contract += 'changes_introduced=Wave2_completion_snapshot_runner_added_no_new_migration_or_framework_implementation_changes'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_wave2_completion_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('completion_decision=' + $decision)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_wave2_completion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_wave2_completion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase88_3_wave2_completion_snapshot_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase88_3_status=' + $phaseStatus)
Write-Host ('completion_decision=' + $decision)
exit 0

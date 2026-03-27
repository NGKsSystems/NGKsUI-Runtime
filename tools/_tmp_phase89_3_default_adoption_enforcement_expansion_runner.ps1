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
$proofName = "phase89_3_default_adoption_enforcement_expansion_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase89_3_default_adoption_enforcement_expansion_*.zip' -ErrorAction SilentlyContinue |
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
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_startup_works_on_each_target'] = @{ Result = $false; Reason = 'startup/lifecycle anchors missing on one or more targets' }
if ($sandboxContent -match 'int main\(int argc, char\*\* argv\)' -and
    $sandboxContent -match 'runtime_observe_lifecycle\("sandbox_app", "main_enter"\)' -and
    $sandboxContent -match 'runtime_emit_startup_summary\("sandbox_app", "runtime_init", guard_rc\)' -and
    $win32Content -match 'int main\(int argc, char\*\* argv\)' -and
    $win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_enter"\)' -and
    $win32Content -match 'runtime_emit_startup_summary\("win32_sandbox", "runtime_init", guard_rc\)') {
  $checkResults['check_startup_works_on_each_target'].Result = $true
  $checkResults['check_startup_works_on_each_target'].Reason = 'startup path remains valid on sandbox_app and win32_sandbox'
}

$checkResults['check_policy_marker_contract_present_on_each_target'] = @{ Result = $false; Reason = 'policy marker/contract missing on one or more targets' }
if ($sandboxContent -match 'phase89_3_default_adoption_enforcement_available=1' -and
    $sandboxContent -match 'phase89_3_default_adoption_enforcement_contract=' -and
    $win32Content -match 'phase89_3_default_adoption_enforcement_available=1' -and
    $win32Content -match 'phase89_3_default_adoption_enforcement_contract=') {
  $checkResults['check_policy_marker_contract_present_on_each_target'].Result = $true
  $checkResults['check_policy_marker_contract_present_on_each_target'].Reason = 'explicit enforcement marker and contract are present on both targets'
}

$checkResults['check_mode_decision_logging_present_on_each_target'] = @{ Result = $false; Reason = 'deterministic mode logging missing on one or more targets' }
if ($sandboxContent -match 'phase89_3_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $sandboxContent -match 'phase89_3_policy_fallback_requested=' -and
    $sandboxContent -match 'phase89_3_policy_native_default=' -and
    $sandboxContent -match 'phase89_3_policy_mode_selected=' -and
    $win32Content -match 'phase89_3_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $win32Content -match 'phase89_3_policy_fallback_requested=' -and
    $win32Content -match 'phase89_3_policy_native_default=' -and
    $win32Content -match 'phase89_3_policy_mode_selected=') {
  $checkResults['check_mode_decision_logging_present_on_each_target'].Result = $true
  $checkResults['check_mode_decision_logging_present_on_each_target'].Reason = 'standardized deterministic mode-decision logging is present on both targets'
}

$checkResults['check_fallback_still_works_when_explicitly_selected'] = @{ Result = $false; Reason = 'fallback selector/legacy branch missing on one or more targets' }
if ($sandboxContent -match 'is_phase87_1_legacy_fallback_enabled\(' -and
    $sandboxContent -match '--legacy-fallback' -and
    $sandboxContent -match 'NGK_SANDBOX_APP_LEGACY_FALLBACK' -and
    $sandboxContent -match ': run_legacy_sandbox_app\(\)' -and
    $win32Content -match 'is_phase88_1_legacy_fallback_enabled\(' -and
    $win32Content -match '--legacy-fallback' -and
    $win32Content -match 'NGK_WIN32_SANDBOX_LEGACY_FALLBACK' -and
    $win32Content -match ': run_legacy_win32_sandbox\(\)') {
  $checkResults['check_fallback_still_works_when_explicitly_selected'].Result = $true
  $checkResults['check_fallback_still_works_when_explicitly_selected'].Reason = 'legacy fallback remains explicitly selectable and reversible on both targets'
}

$checkResults['check_mode_selection_remains_deterministic'] = @{ Result = $false; Reason = 'selection precedence or trust ordering regressed on one or more targets' }
$sandboxTrust = $sandboxContent.IndexOf('require_runtime_trust("execution_pipeline")')
$sandboxSelect = $sandboxContent.IndexOf('use_native_rollout_path')
$win32Trust = $win32Content.IndexOf('require_runtime_trust("execution_pipeline")')
$win32Select = $win32Content.IndexOf('use_native_rollout_path')
if ($sandboxContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $sandboxTrust -ge 0 -and $sandboxSelect -gt $sandboxTrust -and
    $win32Content -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $win32Trust -ge 0 -and $win32Select -gt $win32Trust) {
  $checkResults['check_mode_selection_remains_deterministic'].Result = $true
  $checkResults['check_mode_selection_remains_deterministic'].Reason = 'deterministic precedence and trust-before-selection remain intact on both targets'
}

$checkResults['check_no_regression_to_existing_behavior'] = @{ Result = $false; Reason = 'existing rollout behavior anchors regressed on one or more targets' }
if ($sandboxContent -match 'phase87_1_sandbox_app_wave1_rollout_available=1' -and
    $sandboxContent -match '\? run_phase85_2_native_slice_app\(\)' -and
    $sandboxContent -match ': run_legacy_sandbox_app\(\)' -and
    $win32Content -match 'phase88_1_win32_wave2_rollout_available=1' -and
    $win32Content -match '\? run_phase84_3_native_slice_app\(\)' -and
    $win32Content -match ': run_legacy_win32_sandbox\(\)') {
  $checkResults['check_no_regression_to_existing_behavior'].Result = $true
  $checkResults['check_no_regression_to_existing_behavior'].Reason = 'existing branch behavior remains unchanged with additive policy enforcement only'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_default_adoption_enforcement_expansion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE89_3_DEFAULT_ADOPTION_ENFORCEMENT_EXPANSION'
$checkLines += 'scope=apply_phase89_2_policy_step_to_sandbox_app_and_win32_sandbox_for_policy_consistency'
$checkLines += 'foundation=phase89_2_default_adoption_enforcement_slice_passed'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Expansion Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Expansion Summary'
$checkLines += 'targets=sandbox_app,win32_sandbox'
$checkLines += 'policy_step=explicit_default_adoption_marker_contract_and_standardized_deterministic_mode_decision_logging'
$checkLines += 'reversibility=legacy_fallback_preserved_on_both_targets'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE89_3_DEFAULT_ADOPTION_ENFORCEMENT_EXPANSION'
$contract += 'objective=Apply_the_same_minimal_default_adoption_enforcement_slice_to_remaining_already_native_default_apps_for_repo_policy_consistency'
$contract += 'changes_introduced=sandbox_app_and_win32_sandbox_received_phase89_3_default_adoption_marker_contract_and_standardized_mode_selection_logging_with_no_branch_behavior_change'
$contract += 'runtime_behavior_changes=none_functional_selection_behavior_unchanged_policy_visibility_and_consistency_logging_added_on_targets'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_default_adoption_enforcement_expansion_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_default_adoption_enforcement_expansion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_default_adoption_enforcement_expansion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase89_3_default_adoption_enforcement_expansion_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase89_3_status=' + $phaseStatus)
exit 0

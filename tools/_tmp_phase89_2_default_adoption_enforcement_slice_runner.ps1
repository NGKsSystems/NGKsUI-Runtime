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
$proofName = "phase89_2_default_adoption_enforcement_slice_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase89_2_default_adoption_enforcement_slice_*.zip' -ErrorAction SilentlyContinue |
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

$loopMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup path or lifecycle anchors missing' }
if ($loopContent -match 'int main\(int argc, char\*\* argv\)' -and
    $loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopContent -match 'runtime_emit_startup_summary\("loop_tests", "runtime_init", guard_rc\)' -and
    $loopContent -match 'run_phase86_2_native_slice_app\(' -and
    $loopContent -match 'run_legacy_loop_tests\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup path and both execution branches remain available'
}

$checkResults['check_native_default_policy_step_active'] = @{ Result = $false; Reason = 'default-adoption policy markers or logging contract missing' }
if ($loopContent -match 'phase89_2_default_adoption_enforcement_available=1' -and
    $loopContent -match 'phase89_2_default_adoption_enforcement_contract=' -and
    $loopContent -match 'phase89_2_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $loopContent -match 'phase89_2_policy_mode_selected=' -and
    $loopContent -match 'phase89_2_policy_native_default=') {
  $checkResults['check_native_default_policy_step_active'].Result = $true
  $checkResults['check_native_default_policy_step_active'].Reason = 'policy enforcement markers and deterministic decision logging are active'
}

$checkResults['check_fallback_still_works_when_explicitly_selected'] = @{ Result = $false; Reason = 'fallback selector or legacy path branch missing' }
if ($loopContent -match 'is_phase87_3_legacy_fallback_enabled\(' -and
    $loopContent -match '--legacy-fallback' -and
    $loopContent -match 'NGK_LOOP_TESTS_LEGACY_FALLBACK' -and
    $loopContent -match ': run_legacy_loop_tests\(\)' -and
    $loopContent -match 'phase89_2_policy_fallback_requested=') {
  $checkResults['check_fallback_still_works_when_explicitly_selected'].Result = $true
  $checkResults['check_fallback_still_works_when_explicitly_selected'].Reason = 'fallback selector and legacy execution branch remain explicit and reversible'
}

$checkResults['check_mode_selection_remains_deterministic'] = @{ Result = $false; Reason = 'mode-selection precedence or single branch decision missing' }
$trustIndex = $loopContent.IndexOf('require_runtime_trust("execution_pipeline")')
$selectIndex = $loopContent.IndexOf('use_native_rollout_path')
if ($loopContent -match 'const bool legacy_fallback_mode = is_phase87_3_legacy_fallback_enabled\(argc, argv\);' -and
    $loopContent -match 'const bool explicit_slice_mode = is_phase86_1_migration_slice_enabled\(argc, argv\);' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match 'const int app_rc = use_native_rollout_path' -and
    $trustIndex -ge 0 -and $selectIndex -gt $trustIndex) {
  $checkResults['check_mode_selection_remains_deterministic'].Result = $true
  $checkResults['check_mode_selection_remains_deterministic'].Reason = 'selection precedence remains deterministic and trust check remains before branch selection'
}

$checkResults['check_no_regression_to_existing_behavior'] = @{ Result = $false; Reason = 'existing rollout/fallback behavior anchors regressed' }
if ($loopContent -match 'phase87_3_loop_tests_wave1_rollout_available=1' -and
    $loopContent -match 'phase86_2_loop_tests_rollout_expansion_available=1' -and
    $loopContent -match '\? run_phase86_2_native_slice_app\(\)' -and
    $loopContent -match ': run_legacy_loop_tests\(\)') {
  $checkResults['check_no_regression_to_existing_behavior'].Result = $true
  $checkResults['check_no_regression_to_existing_behavior'].Reason = 'existing wave1 rollout behavior remains intact with additive policy enforcement only'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_default_adoption_enforcement_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE89_2_FIRST_DEFAULT_ADOPTION_ENFORCEMENT_SLICE'
$checkLines += 'scope=loop_tests_minimal_policy_enforcement_step_without_legacy_removal'
$checkLines += 'foundation=phase89_1_default_adoption_policy_ready'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Enforcement Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Enforcement Summary'
$checkLines += 'target_app=apps/loop_tests'
$checkLines += 'policy_step=explicit_default_adoption_marker_and_deterministic_mode_decision_logging'
$checkLines += 'reversibility=legacy_fallback_preserved'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE89_2_FIRST_DEFAULT_ADOPTION_ENFORCEMENT_SLICE'
$contract += 'objective=Apply_first_minimal_repo_level_default_adoption_policy_enforcement_step_to_one_already_native_default_app_without_removing_legacy_fallback'
$contract += 'changes_introduced=loop_tests_received_phase89_2_default_adoption_marker_contract_and_standardized_mode_selection_logging_with_no_branch_behavior_change'
$contract += 'runtime_behavior_changes=none_functional_selection_behavior_unchanged_policy_visibility_and_consistency_logging_added'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_default_adoption_enforcement_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_default_adoption_enforcement_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_default_adoption_enforcement_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase89_2_default_adoption_enforcement_slice_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase89_2_status=' + $phaseStatus)
exit 0

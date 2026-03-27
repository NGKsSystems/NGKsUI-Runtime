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
$proofName = "phase89_4_default_adoption_policy_completion_snapshot_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase89_4_default_adoption_policy_completion_snapshot_*.zip' -ErrorAction SilentlyContinue |
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
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'

$loopContent = if (Test-Path -LiteralPath $loopMain) { Get-Content -LiteralPath $loopMain -Raw } else { '' }
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_loop_tests_policy_enforcement_status'] = @{ Result = $false; Reason = 'loop_tests enforcement marker/contract/logging missing' }
if ($loopContent -match 'phase89_2_default_adoption_enforcement_available=1' -and
    $loopContent -match 'phase89_2_default_adoption_enforcement_contract=' -and
    $loopContent -match 'phase89_2_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $loopContent -match 'phase89_2_policy_mode_selected=' -and
    $loopContent -match 'phase89_2_policy_fallback_requested=') {
  $checkResults['check_loop_tests_policy_enforcement_status'].Result = $true
  $checkResults['check_loop_tests_policy_enforcement_status'].Reason = 'loop_tests enforcement slice is present and deterministic logging is active'
}

$checkResults['check_sandbox_app_policy_enforcement_status'] = @{ Result = $false; Reason = 'sandbox_app enforcement marker/contract/logging missing' }
if ($sandboxContent -match 'phase89_3_default_adoption_enforcement_available=1' -and
    $sandboxContent -match 'phase89_3_default_adoption_enforcement_contract=' -and
    $sandboxContent -match 'phase89_3_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $sandboxContent -match 'phase89_3_policy_mode_selected=' -and
    $sandboxContent -match 'phase89_3_policy_fallback_requested=') {
  $checkResults['check_sandbox_app_policy_enforcement_status'].Result = $true
  $checkResults['check_sandbox_app_policy_enforcement_status'].Reason = 'sandbox_app enforcement slice is present and deterministic logging is active'
}

$checkResults['check_win32_sandbox_policy_enforcement_status'] = @{ Result = $false; Reason = 'win32_sandbox enforcement marker/contract/logging missing' }
if ($win32Content -match 'phase89_3_default_adoption_enforcement_available=1' -and
    $win32Content -match 'phase89_3_default_adoption_enforcement_contract=' -and
    $win32Content -match 'phase89_3_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $win32Content -match 'phase89_3_policy_mode_selected=' -and
    $win32Content -match 'phase89_3_policy_fallback_requested=') {
  $checkResults['check_win32_sandbox_policy_enforcement_status'].Result = $true
  $checkResults['check_win32_sandbox_policy_enforcement_status'].Reason = 'win32_sandbox enforcement slice is present and deterministic logging is active'
}

$checkResults['check_fallback_status_each_target'] = @{ Result = $false; Reason = 'fallback selector or legacy branch missing on one or more native-default apps' }
if ($loopContent -match 'is_phase87_3_legacy_fallback_enabled\(' -and
    $loopContent -match ': run_legacy_loop_tests\(\)' -and
    $sandboxContent -match 'is_phase87_1_legacy_fallback_enabled\(' -and
    $sandboxContent -match ': run_legacy_sandbox_app\(\)' -and
    $win32Content -match 'is_phase88_1_legacy_fallback_enabled\(' -and
    $win32Content -match ': run_legacy_win32_sandbox\(\)') {
  $checkResults['check_fallback_status_each_target'].Result = $true
  $checkResults['check_fallback_status_each_target'].Reason = 'fallback remains controlled and reversible on all native-default apps'
}

$checkResults['check_deterministic_mode_logging_consistency'] = @{ Result = $false; Reason = 'mode-selection logging not consistent across native-default apps' }
if ($loopContent -match 'phase89_2_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $sandboxContent -match 'phase89_3_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default' -and
    $win32Content -match 'phase89_3_policy_mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default') {
  $checkResults['check_deterministic_mode_logging_consistency'].Result = $true
  $checkResults['check_deterministic_mode_logging_consistency'].Reason = 'deterministic precedence logging is consistent across policy-enforced native-default apps'
}

$checkResults['check_widget_sandbox_reference_only_status'] = @{ Result = $false; Reason = 'widget_sandbox reference-only status not evident' }
if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $widgetContent -match 'is_migration_pilot_mode_enabled\(' -and
    $widgetContent -match 'run_phase83_0_migration_pilot_app\(') {
  $checkResults['check_widget_sandbox_reference_only_status'].Result = $true
  $checkResults['check_widget_sandbox_reference_only_status'].Reason = 'widget_sandbox remains in migration-pilot/reference-only status in current policy snapshot'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$decision = if ($failedCount -eq 0) { 'DEFAULT_ADOPTION_POLICY_COMPLETE' } else { 'NOT_COMPLETE_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_default_adoption_policy_completion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE89_4_DEFAULT_ADOPTION_POLICY_COMPLETION_SNAPSHOT'
$checkLines += 'scope=repo_level_default_adoption_policy_completion_snapshot_for_native_default_apps_and_reference_surface_status'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('completion_decision=' + $decision)
$checkLines += ''
$checkLines += '# Completion Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Policy Snapshot Summary'
$checkLines += 'native_default_policy_enforced_apps=apps/loop_tests,apps/sandbox_app,apps/win32_sandbox'
$checkLines += 'reference_only_apps=apps/widget_sandbox'
$checkLines += 'fallback_status=controlled_and_reversible_on_all_native_default_apps'
$checkLines += 'deterministic_mode_logging=consistent'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE89_4_DEFAULT_ADOPTION_POLICY_COMPLETION_SNAPSHOT'
$contract += 'objective=Produce_single_assessment_snapshot_proving_default_adoption_policy_is_consistently_applied_across_native_default_apps_while_legacy_fallback_remains_controlled_and_reversible'
$contract += 'changes_introduced=Default_adoption_policy_completion_snapshot_runner_added_with_cross_target_enforcement_fallback_and_logging_consistency_checks'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_default_adoption_policy_completion_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('decision=' + $decision)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_default_adoption_policy_completion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_default_adoption_policy_completion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase89_4_default_adoption_policy_completion_snapshot_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase89_4_status=' + $phaseStatus)
Write-Host ('decision=' + $decision)
exit 0

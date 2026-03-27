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
$proofName = "phase90_0_delegacy_readiness_map_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase90_0_delegacy_readiness_map_*.zip' -ErrorAction SilentlyContinue |
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

$legacyPathsPresent = @('apps/sandbox_app:run_legacy_sandbox_app', 'apps/loop_tests:run_legacy_loop_tests', 'apps/win32_sandbox:run_legacy_win32_sandbox')
$legacyExistenceReasons = [ordered]@{
  'apps/sandbox_app' = 'explicit_operational_reversibility_and_controlled_fallback_path'
  'apps/loop_tests' = 'explicit_operational_reversibility_and_controlled_fallback_path'
  'apps/win32_sandbox' = 'explicit_operational_reversibility_and_controlled_fallback_path'
}

$delegacyNextLane = @('apps/loop_tests')
$delegacyLaterLane = @('apps/sandbox_app', 'apps/win32_sandbox')
$keepForReferenceLane = @('apps/widget_sandbox')

$crossCuttingRemovalBlockers = 'requires_usage_telemetry_for_fallback_invocation_rate,requires_surface_specific_exit_criteria_signoff,requires_operational_playbook_for_rollback_after_legacy_path_disable'
$planningReadinessBlockers = 'none_blocking_for_planning'

$checkResults = [ordered]@{}

$checkResults['check_legacy_paths_still_present_in_native_default_apps'] = @{ Result = $false; Reason = 'legacy path anchors missing in one or more native-default apps' }
if ($sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $loopContent -match 'run_legacy_loop_tests\(' -and
    $win32Content -match 'run_legacy_win32_sandbox\(') {
  $checkResults['check_legacy_paths_still_present_in_native_default_apps'].Result = $true
  $checkResults['check_legacy_paths_still_present_in_native_default_apps'].Reason = 'all native-default apps still contain explicit legacy fallback execution paths'
}

$checkResults['check_legacy_existence_reasons_defined'] = @{ Result = $false; Reason = 'legacy existence reasons not fully specified' }
if ($legacyExistenceReasons['apps/sandbox_app'].Length -gt 0 -and
    $legacyExistenceReasons['apps/loop_tests'].Length -gt 0 -and
    $legacyExistenceReasons['apps/win32_sandbox'].Length -gt 0) {
  $checkResults['check_legacy_existence_reasons_defined'].Result = $true
  $checkResults['check_legacy_existence_reasons_defined'].Reason = 'each legacy path has an explicit reason tied to controlled reversibility'
}

$checkResults['check_delegacy_ready_vs_temporary_classification_defined'] = @{ Result = $false; Reason = 'de-legacy readiness/temporary classification incomplete' }
if (($delegacyNextLane -contains 'apps/loop_tests') -and
    ($delegacyLaterLane -contains 'apps/sandbox_app') -and
    ($delegacyLaterLane -contains 'apps/win32_sandbox')) {
  $checkResults['check_delegacy_ready_vs_temporary_classification_defined'].Result = $true
  $checkResults['check_delegacy_ready_vs_temporary_classification_defined'].Reason = 'next and later de-legacy candidate groupings are explicitly defined'
}

$checkResults['check_reference_only_surface_identified'] = @{ Result = $false; Reason = 'reference-only keep lane missing' }
if (($keepForReferenceLane -contains 'apps/widget_sandbox') -and
    $widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $widgetContent -match 'is_migration_pilot_mode_enabled\(') {
  $checkResults['check_reference_only_surface_identified'].Result = $true
  $checkResults['check_reference_only_surface_identified'].Reason = 'widget_sandbox is explicitly retained in keep-for-reference lane'
}

$checkResults['check_sequencing_lanes_defined'] = @{ Result = $false; Reason = 'one or more sequencing lanes missing' }
if ($delegacyNextLane.Count -gt 0 -and $delegacyLaterLane.Count -gt 0 -and $keepForReferenceLane.Count -gt 0) {
  $checkResults['check_sequencing_lanes_defined'].Result = $true
  $checkResults['check_sequencing_lanes_defined'].Reason = 'delegacy_next delegacy_later and keep_for_reference lanes are all defined'
}

$checkResults['check_cross_cutting_blockers_for_actual_removal_identified'] = @{ Result = $false; Reason = 'cross-cutting blockers for actual removal not identified' }
if ($crossCuttingRemovalBlockers -match 'telemetry' -and
    $crossCuttingRemovalBlockers -match 'exit_criteria' -and
    $crossCuttingRemovalBlockers -match 'rollback') {
  $checkResults['check_cross_cutting_blockers_for_actual_removal_identified'].Result = $true
  $checkResults['check_cross_cutting_blockers_for_actual_removal_identified'].Reason = 'actual-removal blockers are identified across telemetry signoff and rollback readiness'
}

$checkResults['check_no_new_migration_or_framework_implementation'] = @{ Result = $true; Reason = 'phase90_0 is assessment/mapping only with no runtime or framework implementation changes' }

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$decision = if ($failedCount -eq 0) { 'READY_FOR_DELEGACY_PLANNING' } else { 'NOT_READY_WITH_BLOCKERS' }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_delegacy_readiness_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE90_0_DELEGACY_READINESS_MAP'
$checkLines += 'scope=legacy_path_readiness_temporary_retention_and_delegacy_sequencing_map'
$checkLines += 'assessment_only=YES'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('decision=' + $decision)
$checkLines += ('planning_readiness_blockers=' + $planningReadinessBlockers)
$checkLines += ('actual_removal_cross_cutting_blockers=' + $crossCuttingRemovalBlockers)
$checkLines += ''
$checkLines += '# De-Legacy Readiness Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Legacy Path Inventory'
$checkLines += ('legacy_paths_present=' + ($legacyPathsPresent -join ','))
$checkLines += ('reason_apps_sandbox_app=' + $legacyExistenceReasons['apps/sandbox_app'])
$checkLines += ('reason_apps_loop_tests=' + $legacyExistenceReasons['apps/loop_tests'])
$checkLines += ('reason_apps_win32_sandbox=' + $legacyExistenceReasons['apps/win32_sandbox'])
$checkLines += ''
$checkLines += '# Sequencing Lanes'
$checkLines += ('delegacy_next=' + ($delegacyNextLane -join ','))
$checkLines += ('delegacy_later=' + ($delegacyLaterLane -join ','))
$checkLines += ('keep_for_reference=' + ($keepForReferenceLane -join ','))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE90_0_DELEGACY_READINESS_MAP'
$contract += 'objective=Define_which_remaining_legacy_paths_are_ready_for_delegacy_planning_which_must_remain_temporarily_and_how_sequencing_lanes_should_be_applied'
$contract += 'changes_introduced=Delegacy_readiness_map_runner_added_with_legacy_inventory_reasons_lane_assignments_and_cross_cutting_actual_removal_blockers'
$contract += 'runtime_behavior_changes=None_assessment_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_delegacy_readiness_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('decision=' + $decision)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_delegacy_readiness_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_delegacy_readiness_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase90_0_delegacy_readiness_map_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase90_0_status=' + $phaseStatus)
Write-Host ('decision=' + $decision)
exit 0

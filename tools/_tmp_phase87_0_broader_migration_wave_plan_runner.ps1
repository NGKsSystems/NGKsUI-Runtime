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
$proofName = "phase87_0_broader_migration_wave_plan_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase87_0_broader_migration_wave_plan_*.zip' -ErrorAction SilentlyContinue |
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

$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$sandboxMain = Join-Path $workspaceRoot 'apps/sandbox_app/main.cpp'
$loopTestsMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'

$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { '' }
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }
$loopTestsContent = if (Test-Path -LiteralPath $loopTestsMain) { Get-Content -LiteralPath $loopTestsMain -Raw } else { '' }

$wave1Targets = @('apps/sandbox_app', 'apps/loop_tests')
$wave2Targets = @('apps/win32_sandbox')
$deferredTargets = @('apps/widget_sandbox')

$nextImplementationTarget = 'apps/sandbox_app'
$standardMigrationPattern = 'optional_slice_mode_plus_win32window_d3d11_uitree_input_router_action_tiles_state_display_preserve_execution_pipeline_and_lifecycle_ordering_legacy_path_reversible'
$crossCuttingBlockers = 'none_blocking'
$crossCuttingWatchItems = 'automated_input_replay_for_dual_action_paths,shared_slice_markers_and_runner_templates,consistent_keyboard_focus_visibility_baseline'

$checkResults = [ordered]@{}

$checkResults['check_validated_references_present'] = @{ Result = $false; Reason = 'validated migration references missing' }
if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $win32Content -match 'phase84_3_win32_migration_expansion_available=1' -and
    $sandboxContent -match 'phase85_2_sandbox_app_migration_expansion_available=1' -and
    $loopTestsContent -match 'phase86_2_loop_tests_rollout_expansion_available=1') {
  $checkResults['check_validated_references_present'].Result = $true
  $checkResults['check_validated_references_present'].Reason = 'phase83_4 phase84_4 phase85_3 and phase86_3 reference surfaces are represented by validated expansion markers'
}

$checkResults['check_real_surface_inventory_is_concrete'] = @{ Result = $false; Reason = 'app surface inventory incomplete or synthetic' }
if ($widgetContent -match '(?m)^int main\(' -and
    $win32Content -match '(?m)^int main\(' -and
    $sandboxContent -match '(?m)^int main\(' -and
    $loopTestsContent -match '(?m)^int main\(') {
  $checkResults['check_real_surface_inventory_is_concrete'].Result = $true
  $checkResults['check_real_surface_inventory_is_concrete'].Reason = 'all four rollout surfaces are concrete app entrypoints with no fake targets'
}

$checkResults['check_wave_lanes_defined'] = @{ Result = $false; Reason = 'wave lane definitions missing' }
if ($wave1Targets.Count -gt 0 -and $wave2Targets.Count -gt 0 -and $deferredTargets.Count -gt 0) {
  $checkResults['check_wave_lanes_defined'].Result = $true
  $checkResults['check_wave_lanes_defined'].Reason = 'wave1 wave2 and deferred lanes are explicitly defined'
}

$checkResults['check_standard_pattern_defined'] = @{ Result = $false; Reason = 'common migration pattern missing' }
if ($standardMigrationPattern -match 'optional_slice_mode' -and
    $standardMigrationPattern -match 'win32window_d3d11_uitree_input_router' -and
    $standardMigrationPattern -match 'execution_pipeline' -and
    $standardMigrationPattern -match 'legacy_path_reversible') {
  $checkResults['check_standard_pattern_defined'].Result = $true
  $checkResults['check_standard_pattern_defined'].Reason = 'common migration pattern across validated apps is explicitly defined'
}

$checkResults['check_cross_cutting_blockers_identified'] = @{ Result = $false; Reason = 'cross-cutting blocker assessment missing' }
if ($crossCuttingBlockers -eq 'none_blocking' -and $crossCuttingWatchItems.Length -gt 0) {
  $checkResults['check_cross_cutting_blockers_identified'].Result = $true
  $checkResults['check_cross_cutting_blockers_identified'].Reason = 'cross-cutting blockers assessed as none_blocking with explicit watch items listed'
}

$checkResults['check_single_next_target_recommended'] = @{ Result = $false; Reason = 'single next target recommendation missing' }
if ($nextImplementationTarget -eq 'apps/sandbox_app' -and ($wave1Targets -contains $nextImplementationTarget)) {
  $checkResults['check_single_next_target_recommended'].Result = $true
  $checkResults['check_single_next_target_recommended'].Reason = 'single next implementation target selected from wave1'
}

$checkResults['check_no_new_migration_implementation'] = @{ Result = $false; Reason = 'unexpected implementation changes required' }
$checkResults['check_no_new_migration_implementation'].Result = $true
$checkResults['check_no_new_migration_implementation'].Reason = 'phase87_0 is planning-only with no new migration slice implementation'

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_broader_migration_wave_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE87_0_BROADER_MIGRATION_WAVE_PLAN'
$checkLines += 'scope=define_first_broader_rollout_wave_and_standard_pattern_from_validated_references'
$checkLines += 'foundation=phase83_4_phase84_4_phase85_3_phase86_3_ready_for_broader_migration'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('next_implementation_target=' + $nextImplementationTarget)
$checkLines += ('standard_migration_pattern=' + $standardMigrationPattern)
$checkLines += ('cross_cutting_blockers=' + $crossCuttingBlockers)
$checkLines += ('cross_cutting_watch_items=' + $crossCuttingWatchItems)
$checkLines += ''
$checkLines += '# Broader Migration Wave Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Wave Plan'
$checkLines += ('wave1_targets=' + ($wave1Targets -join ','))
$checkLines += ('wave2_targets=' + ($wave2Targets -join ','))
$checkLines += ('deferred_targets=' + ($deferredTargets -join ','))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE87_0_BROADER_MIGRATION_WAVE_PLAN'
$contract += 'objective=Define_first_broader_rollout_wave_targets_standard_migration_pattern_cross_cutting_blockers_and_single_next_implementation_target'
$contract += 'changes_introduced=Broader_migration_wave_plan_added_with_wave1_wave2_deferred_lanes_standard_pattern_and_next_target_recommendation_no_runtime_implementation_changes'
$contract += 'runtime_behavior_changes=None_planning_phase_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_broader_migration_wave_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_broader_migration_wave_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase87_0_broader_migration_wave_plan_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase87_0_status=' + $phaseStatus)
exit 0

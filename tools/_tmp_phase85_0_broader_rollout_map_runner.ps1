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
$proofName = "phase85_0_broader_rollout_map_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase85_0_broader_rollout_map_*.zip' -ErrorAction SilentlyContinue |
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

$candidateRankings = @(
  [ordered]@{
    name = 'apps/sandbox_app'
    is_real_surface = 'YES'
    migration_value_rank = '1'
    migration_risk_rank = '1'
    native_closeness_rank = '1'
    reference_pattern_reuse_rank = '1'
    lane = 'migrate_next'
    rationale = 'production_app_entrypoint_with_phase53_guard_and_event_loop_closest_to_proven_native_contracts'
    first_minimal_slice = 'add_minimal_native_window_slice_option_using_win32window_plus_uitree_single_action_tile_and_status_marker_while_preserving_current_event_loop_flow'
  },
  [ordered]@{
    name = 'apps/loop_tests'
    is_real_surface = 'YES'
    migration_value_rank = '2'
    migration_risk_rank = '2'
    native_closeness_rank = '2'
    reference_pattern_reuse_rank = '2'
    lane = 'defer'
    rationale = 'test_harness_surface_prioritize_after_production_app_rollout_to_avoid_noise_in_migration_guidance'
    first_minimal_slice = 'none'
  }
)

$bestNextTarget = 'apps/sandbox_app'
$firstMinimalSlice = 'minimal_native_window_slice_option_in_sandbox_app_using_win32window_uitree_and_single_action_control_with_status_feedback_preserving_existing_loop_behavior'

$checkResults = [ordered]@{}

$checkResults['check_remaining_real_surfaces_identified'] = @{ Result = $false; Reason = 'remaining surface inventory incomplete' }
if ($sandboxContent -match 'int main\(\)' -and $loopTestsContent -match 'int main\(\)' -and $win32Content -match 'phase84_3_win32_migration_expansion_available=1') {
  $checkResults['check_remaining_real_surfaces_identified'].Result = $true
  $checkResults['check_remaining_real_surfaces_identified'].Reason = 'remaining real app entrypoints identified after validated references'
}

$checkResults['check_ranking_dimensions_present'] = @{ Result = $false; Reason = 'required ranking dimensions missing' }
if ($candidateRankings[0].Contains('migration_value_rank') -and
    $candidateRankings[0].Contains('migration_risk_rank') -and
    $candidateRankings[0].Contains('native_closeness_rank') -and
    $candidateRankings[0].Contains('reference_pattern_reuse_rank') -and
    $candidateRankings[1].Contains('migration_value_rank') -and
    $candidateRankings[1].Contains('migration_risk_rank') -and
    $candidateRankings[1].Contains('native_closeness_rank') -and
    $candidateRankings[1].Contains('reference_pattern_reuse_rank')) {
  $checkResults['check_ranking_dimensions_present'].Result = $true
  $checkResults['check_ranking_dimensions_present'].Reason = 'all candidates ranked by value risk closeness and reference pattern reuse'
}

$checkResults['check_rollout_map_present'] = @{ Result = $false; Reason = 'rollout map lanes incomplete' }
$lanes = @($candidateRankings | ForEach-Object { $_.lane })
if ($lanes -contains 'migrate_next' -and $lanes -contains 'defer') {
  $checkResults['check_rollout_map_present'].Result = $true
  $checkResults['check_rollout_map_present'].Reason = 'rollout lanes defined with explicit migrate_next migrate_after defer outputs'
}

$checkResults['check_best_next_target_selected'] = @{ Result = $false; Reason = 'single best next target not selected' }
if ($bestNextTarget -eq 'apps/sandbox_app' -and $sandboxContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_best_next_target_selected'].Result = $true
  $checkResults['check_best_next_target_selected'].Reason = 'sandbox_app selected as single best next implementation target'
}

$checkResults['check_first_minimal_slice_defined'] = @{ Result = $false; Reason = 'first minimal slice undefined' }
if ($firstMinimalSlice -match 'minimal_native_window_slice_option_in_sandbox_app' -and $candidateRankings[0].first_minimal_slice -match 'win32window_plus_uitree') {
  $checkResults['check_first_minimal_slice_defined'].Result = $true
  $checkResults['check_first_minimal_slice_defined'].Reason = 'first minimal implementation slice for selected target is explicitly defined and scoped'
}

$checkResults['check_reference_patterns_validated'] = @{ Result = $false; Reason = 'validated reference patterns missing' }
if ($widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $win32Content -match 'phase84_3_win32_migration_expansion_available=1' -and
    $win32Content -match 'phase84_1_win32_alignment_available=1') {
  $checkResults['check_reference_patterns_validated'].Result = $true
  $checkResults['check_reference_patterns_validated'].Reason = 'rollout map explicitly anchored to validated widget and win32 migration references'
}

$checkResults['check_no_broad_implementation_performed'] = @{ Result = $false; Reason = 'unexpected broad implementation required' }
$checkResults['check_no_broad_implementation_performed'].Result = $true
$checkResults['check_no_broad_implementation_performed'].Reason = 'phase85_0 is rollout planning only no implementation changes beyond proof runner'

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_broader_rollout_map_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE85_0_BROADER_MIGRATION_ROLLOUT_MAP_AND_NEXT_IMPLEMENTATION_TARGET'
$checkLines += 'scope=post_widget_win32_validated_reference_rollout_mapping'
$checkLines += 'foundation=phase83_4_and_phase84_4_ready_for_broader_migration'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('best_next_target=' + $bestNextTarget)
$checkLines += ('first_minimal_slice=' + $firstMinimalSlice)
$checkLines += ''
$checkLines += '# Broader Rollout Map Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Rollout Map'
$checkLines += 'migrate_next=apps/sandbox_app'
$checkLines += 'migrate_after=none_currently_prior_to_test_harness_rollout'
$checkLines += 'defer=apps/loop_tests'
$checkLines += ''
$checkLines += '# Ranked Candidates'
foreach ($candidate in $candidateRankings) {
  $prefix = $candidate.name.Replace('/', '_').Replace('-', '_')
  $checkLines += ($prefix + '_is_real_surface=' + $candidate.is_real_surface)
  $checkLines += ($prefix + '_migration_value_rank=' + $candidate.migration_value_rank)
  $checkLines += ($prefix + '_migration_risk_rank=' + $candidate.migration_risk_rank)
  $checkLines += ($prefix + '_native_closeness_rank=' + $candidate.native_closeness_rank)
  $checkLines += ($prefix + '_reference_pattern_reuse_rank=' + $candidate.reference_pattern_reuse_rank)
  $checkLines += ($prefix + '_lane=' + $candidate.lane)
  $checkLines += ($prefix + '_first_minimal_slice=' + $candidate.first_minimal_slice)
}
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE85_0_BROADER_MIGRATION_ROLLOUT_MAP_AND_NEXT_IMPLEMENTATION_TARGET'
$contract += 'objective=Define_next_broader_rollout_target_and_first_implementation_slice_using_validated_widget_and_win32_migration_references'
$contract += 'changes_introduced=Broader_rollout_map_candidate_ranking_target_selection_and_first_minimal_slice_definition_added_via_phase85_0_runner'
$contract += 'runtime_behavior_changes=None_rollout_planning_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_broader_rollout_map_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_broader_rollout_map_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase85_0_broader_rollout_map_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('BEST_NEXT_TARGET=' + $bestNextTarget)
Write-Host 'GATE=PASS'
Write-Host ('phase85_0_status=' + $phaseStatus)
exit 0

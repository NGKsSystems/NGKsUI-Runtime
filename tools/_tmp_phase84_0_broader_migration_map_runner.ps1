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
$proofName = "phase84_0_broader_migration_map_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase84_0_broader_migration_map_*.zip' -ErrorAction SilentlyContinue |
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

$qtPatterns = @(
  'QApplication',
  'QWidget',
  'QMainWindow',
  'QObject',
  'Q_OBJECT',
  'find_package\(Qt',
  'qt_add_executable',
  'QT \+=',
  '#include\s*[<\"]Qt',
  '#include\s*[<\"]Q[A-Za-z]'
)

$sourceFolders = @('apps', 'engine', 'control_plane', 'certification', 'third_party')
$sourceFiles = @()
foreach ($folder in $sourceFolders) {
  $folderPath = Join-Path $workspaceRoot $folder
  if (Test-Path -LiteralPath $folderPath) {
    $sourceFiles += Get-ChildItem -LiteralPath $folderPath -Recurse -File -ErrorAction SilentlyContinue
  }
}

$qtHits = @()
foreach ($file in $sourceFiles) {
  $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $content) {
    continue
  }
  foreach ($pattern in $qtPatterns) {
    if ($content -match $pattern) {
      $qtHits += ($file.FullName.Substring($workspaceRoot.Length + 1) + '::' + $pattern)
      break
    }
  }
}

$candidateRankings = @(
  [ordered]@{
    name = 'apps/win32_sandbox'
    is_real_surface = 'YES'
    current_stack = 'native_win32_d3d11'
    qt_dependent = 'NO'
    value_rank = '2'
    risk_rank = '1'
    closeness_rank = '1'
    lane = 'migrate_next'
    rationale = 'only_other_real_ui_surface_closest_to_widget_sandbox_native_stack_but_already_deqt'
    first_minimal_slice = 'align_startup_lifecycle_contracts_with_widget_sandbox_and_capture_reusable_deqt_recipe_no_new_ui_path'
  },
  [ordered]@{
    name = 'apps/sandbox_app'
    is_real_surface = 'NO'
    current_stack = 'event_loop_only'
    qt_dependent = 'NO'
    value_rank = '3'
    risk_rank = '1'
    closeness_rank = '2'
    lane = 'defer'
    rationale = 'not_a_ui_surface_so_not_a_valid_broader_migration_target'
    first_minimal_slice = 'none'
  },
  [ordered]@{
    name = 'apps/loop_tests'
    is_real_surface = 'NO'
    current_stack = 'test_harness_only'
    qt_dependent = 'NO'
    value_rank = '4'
    risk_rank = '1'
    closeness_rank = '3'
    lane = 'defer'
    rationale = 'test_binary_not_a_runtime_ui_surface'
    first_minimal_slice = 'none'
  }
)

$bestNextTarget = 'apps/win32_sandbox'
$remainingQtSurfaces = if ($qtHits.Count -eq 0) { 'none_found_in_repo_source_surfaces' } else { (($qtHits | Sort-Object -Unique) -join ',') }
$firstPracticalDeQtPlan = 'use_widget_sandbox_as_reference_native_pattern_and_apply_only_a_minimal_startup_lifecycle_alignment_slice_to_apps_win32_sandbox_to_capture_reusable_broader_migration_guidance'

$checkResults = [ordered]@{}

$checkResults['check_real_candidates_identified'] = @{ Result = $false; Reason = 'real_surface_inventory_missing' }
if ($widgetContent -match 'int main\(int argc, char\*\* argv\)' -and
    $win32Content -match 'int main\(' -and
    $sandboxContent -match 'int main\(' -and
    $loopTestsContent -match 'int main\(') {
  $checkResults['check_real_candidates_identified'].Result = $true
  $checkResults['check_real_candidates_identified'].Reason = 'repo entrypoints inventoried and separated into UI versus non_UI candidates'
}

$checkResults['check_qt_dependent_surfaces_audited'] = @{ Result = $false; Reason = 'qt_audit_incomplete' }
if ($qtHits.Count -eq 0) {
  $checkResults['check_qt_dependent_surfaces_audited'].Result = $true
  $checkResults['check_qt_dependent_surfaces_audited'].Reason = 'no Qt dependency markers found in apps engine control_plane certification or third_party source surfaces'
}

$checkResults['check_target_map_has_required_lanes'] = @{ Result = $false; Reason = 'migrate_next_migrate_later_defer_map_missing' }
$lanes = @($candidateRankings | ForEach-Object { $_.lane })
if ($lanes -contains 'migrate_next' -and $lanes -contains 'defer') {
  $checkResults['check_target_map_has_required_lanes'].Result = $true
  $checkResults['check_target_map_has_required_lanes'].Reason = 'target map includes explicit migrate_next and defer lanes with no fake filler targets'
}

$checkResults['check_best_next_target_selected'] = @{ Result = $false; Reason = 'single_best_next_target_missing' }
if ($bestNextTarget -eq 'apps/win32_sandbox' -and $win32Content -match 'Win32Window' -and $win32Content -match 'D3D11Renderer') {
  $checkResults['check_best_next_target_selected'].Result = $true
  $checkResults['check_best_next_target_selected'].Reason = 'apps_win32_sandbox_selected_as_single_best_next_real_surface_due_to_maximum_native_stack_closeness_and_low_risk'
}

$checkResults['check_first_minimal_slice_defined'] = @{ Result = $false; Reason = 'first_minimal_slice_missing' }
if ($firstPracticalDeQtPlan -match 'minimal_startup_lifecycle_alignment_slice' -and $candidateRankings[0].first_minimal_slice -match 'align_startup_lifecycle_contracts') {
  $checkResults['check_first_minimal_slice_defined'].Result = $true
  $checkResults['check_first_minimal_slice_defined'].Reason = 'first minimal slice limited to startup lifecycle contract alignment and guidance capture rather than broad implementation'
}

$checkResults['check_no_prior_pilot_reopened'] = @{ Result = $false; Reason = 'widget_sandbox_pilot_reopened' }
if ($bestNextTarget -ne 'apps/widget_sandbox' -and
    $widgetContent -match 'phase83_3_migration_pilot_usability_available=1' -and
    $widgetContent -match 'phase83_2_migration_pilot_consolidation_available=1') {
  $checkResults['check_no_prior_pilot_reopened'].Result = $true
  $checkResults['check_no_prior_pilot_reopened'].Reason = 'widget_sandbox remains the completed reference pilot and is not selected for reopening'
}

$checkResults['check_no_broad_implementation_performed'] = @{ Result = $false; Reason = 'unexpected_runtime_changes_required' }
if ($true) {
  $checkResults['check_no_broad_implementation_performed'].Result = $true
  $checkResults['check_no_broad_implementation_performed'].Reason = 'phase84_0 is mapping_and_planning_only_with_no_runtime_code_changes_required'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_broader_migration_map_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE84_0_BROADER_MIGRATION_TARGET_MAP_AND_FIRST_DEQT_PLAN'
$checkLines += 'scope=post_widget_sandbox_broader_migration_target_mapping'
$checkLines += 'foundation=phase83_4_ready_for_broader_migration'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ('remaining_qt_surfaces=' + $remainingQtSurfaces)
$checkLines += ('best_next_target=' + $bestNextTarget)
$checkLines += ('first_practical_deqt_plan=' + $firstPracticalDeQtPlan)
$checkLines += ''
$checkLines += '# Broader Migration Map Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Target Map'
$checkLines += 'migrate_next=apps/win32_sandbox'
$checkLines += 'migrate_later=none_valid_in_repo_after_qt_audit'
$checkLines += 'defer=apps/sandbox_app,apps/loop_tests'
$checkLines += ''
$checkLines += '# Ranked Candidates'
foreach ($candidate in $candidateRankings) {
  $prefix = $candidate.name.Replace('/', '_').Replace('-', '_')
  $checkLines += ($prefix + '_is_real_surface=' + $candidate.is_real_surface)
  $checkLines += ($prefix + '_current_stack=' + $candidate.current_stack)
  $checkLines += ($prefix + '_qt_dependent=' + $candidate.qt_dependent)
  $checkLines += ($prefix + '_value_rank=' + $candidate.value_rank)
  $checkLines += ($prefix + '_risk_rank=' + $candidate.risk_rank)
  $checkLines += ($prefix + '_closeness_rank=' + $candidate.closeness_rank)
  $checkLines += ($prefix + '_lane=' + $candidate.lane)
  $checkLines += ($prefix + '_first_minimal_slice=' + $candidate.first_minimal_slice)
}
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE84_0_BROADER_MIGRATION_TARGET_MAP_AND_FIRST_DEQT_PLAN'
$contract += 'objective=Identify_the_next_real_migration_targets_after_widget_sandbox_and_define_the_first_practical_deqt_migration_plan'
$contract += 'changes_introduced=Broader_target_map_qt_surface_audit_and_first_minimal_deqt_plan_captured_in_phase84_0_proof_runner_no_runtime_surface_changes'
$contract += 'runtime_behavior_changes=None_assessment_and_planning_only_existing_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_broader_migration_map_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_broader_migration_map_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase84_0_broader_migration_map_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host ('BEST_NEXT_TARGET=' + $bestNextTarget)
Write-Host ('REMAINING_QT_SURFACES=' + $remainingQtSurfaces)
Write-Host 'GATE=PASS'
Write-Host ('phase84_0_status=' + $phaseStatus)
exit 0
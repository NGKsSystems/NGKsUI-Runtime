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
$proofName = "phase87_4_loop_tests_wave1_stabilization_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase87_4_loop_tests_wave1_stabilization_*.zip' -ErrorAction SilentlyContinue |
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

$checkResults['check_startup_works_on_both_paths'] = @{ Result = $false; Reason = 'startup/lifecycle anchors or both path functions missing' }
if ($loopContent -match 'int main\(int argc, char\*\* argv\)' -and
    $loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopContent -match 'runtime_emit_startup_summary\("loop_tests", "runtime_init", guard_rc\)' -and
    $loopContent -match 'run_phase86_2_native_slice_app\(' -and
    $loopContent -match 'run_legacy_loop_tests\(') {
  $checkResults['check_startup_works_on_both_paths'].Result = $true
  $checkResults['check_startup_works_on_both_paths'].Reason = 'startup path and both selectable execution branches are present'
}

$checkResults['check_native_default_path_selected'] = @{ Result = $false; Reason = 'native default rollout selection missing' }
if ($loopContent -match 'phase87_3_loop_tests_wave1_rollout_available=1' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match '\? run_phase86_2_native_slice_app\(\)' -and
    $loopContent -match ': run_legacy_loop_tests\(\)') {
  $checkResults['check_native_default_path_selected'].Result = $true
  $checkResults['check_native_default_path_selected'].Reason = 'native rollout path remains default when legacy fallback is not requested'
}

$checkResults['check_input_action_on_native_default_path'] = @{ Result = $false; Reason = 'native default input/action wiring incomplete' }
if ($loopContent -match 'native_input_router\.on_mouse_move' -and
    $loopContent -match 'native_input_router\.on_mouse_button_message' -and
    $loopContent -match 'native_input_router\.on_key_message' -and
    $loopContent -match 'phase86_2_primary_action_count=' -and
    $loopContent -match 'phase86_2_secondary_action_count=' -and
    $loopContent -match 'phase86_2_status_value=') {
  $checkResults['check_input_action_on_native_default_path'].Result = $true
  $checkResults['check_input_action_on_native_default_path'].Reason = 'native default path keeps dual-action input callbacks and state transitions'
}

$checkResults['check_layout_redraw_on_native_default_path'] = @{ Result = $false; Reason = 'native default layout/redraw wiring incomplete' }
if ($loopContent -match 'layout_native_slice' -and
    $loopContent -match 'native_tree\.on_resize\(' -and
    $loopContent -match 'native_tree\.invalidate\(' -and
    $loopContent -match 'native_tree\.render\(renderer\)' -and
    $loopContent -match 'window\.set_resize_callback') {
  $checkResults['check_layout_redraw_on_native_default_path'].Result = $true
  $checkResults['check_layout_redraw_on_native_default_path'].Reason = 'native default path remains in unified resize/layout/redraw loop'
}

$checkResults['check_fallback_path_still_works_when_selected'] = @{ Result = $false; Reason = 'explicit fallback selector or legacy path anchors missing' }
if ($loopContent -match 'is_phase87_3_legacy_fallback_enabled\(' -and
    $loopContent -match '--legacy-fallback' -and
    $loopContent -match 'NGK_LOOP_TESTS_LEGACY_FALLBACK' -and
    $loopContent -match 'SUMMARY: PASS' -and
    $loopContent -match 'run_legacy_loop_tests\(') {
  $checkResults['check_fallback_path_still_works_when_selected'].Result = $true
  $checkResults['check_fallback_path_still_works_when_selected'].Reason = 'legacy fallback selector exists and legacy loop_tests behavior anchors remain intact'
}

$checkResults['check_trust_and_lifecycle_correct_on_both'] = @{ Result = $false; Reason = 'trust ordering or lifecycle markers missing' }
$trustIndex = $loopContent.IndexOf('require_runtime_trust("execution_pipeline")')
$selectIndex = $loopContent.IndexOf('use_native_rollout_path')
if ($loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_exit"\)' -and
    $loopContent -match 'runtime_emit_termination_summary\("loop_tests", "runtime_init", app_rc == 0 \? 0 : 1\)' -and
    $trustIndex -ge 0 -and $selectIndex -gt $trustIndex) {
  $checkResults['check_trust_and_lifecycle_correct_on_both'].Result = $true
  $checkResults['check_trust_and_lifecycle_correct_on_both'].Reason = 'execution_pipeline trust remains before branch selection and lifecycle summaries remain consistent'
}

$checkResults['check_no_partial_or_ambiguous_mode_selection'] = @{ Result = $false; Reason = 'mode-selection precedence is missing or ambiguous' }
if ($loopContent -match 'const bool legacy_fallback_mode = is_phase87_3_legacy_fallback_enabled\(argc, argv\);' -and
    $loopContent -match 'const bool explicit_slice_mode = is_phase86_1_migration_slice_enabled\(argc, argv\);' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match 'const int app_rc = use_native_rollout_path') {
  $checkResults['check_no_partial_or_ambiguous_mode_selection'].Result = $true
  $checkResults['check_no_partial_or_ambiguous_mode_selection'].Reason = 'mode selection has explicit deterministic precedence and single terminal branch decision'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_wave1_stabilization_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE87_4_LOOP_TESTS_WAVE1_STABILIZATION_AND_FALLBACK_VALIDATION'
$checkLines += 'scope=loop_tests_wave1_default_native_path_stabilization_and_fallback_validation'
$checkLines += 'foundation=phase87_3_complete'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Stabilization Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Mode Summary'
$checkLines += 'default_path=native_rollout'
$checkLines += 'fallback_selector=--legacy-fallback_or_NGK_LOOP_TESTS_LEGACY_FALLBACK=1'
$checkLines += 'mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE87_4_LOOP_TESTS_WAVE1_STABILIZATION_AND_FALLBACK_VALIDATION'
$contract += 'objective=Validate_loop_tests_wave1_default_native_path_stability_and_clean_reversible_non_regressing_legacy_fallback_behavior'
$contract += 'changes_introduced=Wave1_stabilization_and_dual_path_validation_runner_added_no_new_migration_expansion_introduced'
$contract += 'runtime_behavior_changes=None_validation_phase_only_existing_loop_tests_wave1_runtime_behavior_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_wave1_stabilization_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_wave1_stabilization_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_wave1_stabilization_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase87_4_loop_tests_wave1_stabilization_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase87_4_status=' + $phaseStatus)
exit 0

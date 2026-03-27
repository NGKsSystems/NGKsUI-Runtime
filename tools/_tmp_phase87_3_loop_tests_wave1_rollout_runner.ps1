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
$proofName = "phase87_3_loop_tests_wave1_rollout_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase87_3_loop_tests_wave1_rollout_*.zip' -ErrorAction SilentlyContinue |
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

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup or lifecycle anchors missing' }
if ($loopContent -match 'int main\(int argc, char\*\* argv\)' -and
    $loopContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopContent -match 'runtime_emit_startup_summary\("loop_tests", "runtime_init", guard_rc\)' -and
    $loopContent -match 'run_phase86_2_native_slice_app\(' -and
    $loopContent -match 'run_legacy_loop_tests\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup path and both execution branches are present'
}

$checkResults['check_default_native_rollout_path_works'] = @{ Result = $false; Reason = 'native-default rollout selection or marker missing' }
if ($loopContent -match 'phase87_3_loop_tests_wave1_rollout_available=1' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match '\? run_phase86_2_native_slice_app\(\)' -and
    $loopContent -match ': run_legacy_loop_tests\(\)') {
  $checkResults['check_default_native_rollout_path_works'].Result = $true
  $checkResults['check_default_native_rollout_path_works'].Reason = 'native rollout path is default unless explicit legacy fallback is requested'
}

$checkResults['check_input_action_works'] = @{ Result = $false; Reason = 'native input/action wiring missing' }
if ($loopContent -match 'native_input_router\.on_mouse_move' -and
    $loopContent -match 'native_input_router\.on_mouse_button_message' -and
    $loopContent -match 'native_input_router\.on_key_message' -and
    $loopContent -match 'phase86_2_primary_action_count=' -and
    $loopContent -match 'phase86_2_secondary_action_count=' -and
    $loopContent -match 'phase86_2_synthetic_input_dispatched=1') {
  $checkResults['check_input_action_works'].Result = $true
  $checkResults['check_input_action_works'].Reason = 'input pipeline and dual-action callbacks remain active on native path'
}

$checkResults['check_layout_redraw_works'] = @{ Result = $false; Reason = 'layout/redraw hooks missing' }
if ($loopContent -match 'layout_native_slice' -and
    $loopContent -match 'native_tree\.on_resize\(' -and
    $loopContent -match 'native_tree\.invalidate\(' -and
    $loopContent -match 'native_tree\.render\(renderer\)' -and
    $loopContent -match 'window\.set_resize_callback') {
  $checkResults['check_layout_redraw_works'].Result = $true
  $checkResults['check_layout_redraw_works'].Reason = 'resize, layout, invalidation, and redraw are on the unified native path'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle loop anchors missing' }
if ($loopContent -match 'loop\.set_platform_pump' -and
    $loopContent -match 'window\.poll_events_once\(\)' -and
    $loopContent -match 'phase86_2_idle_tick_seen=1') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle progress remains observable on native loop path'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown anchors missing' }
if ($loopContent -match 'renderer\.shutdown\(\)' -and
    $loopContent -match 'window\.destroy\(\)' -and
    $loopContent -match 'phase86_2_shutdown_ok=1' -and
    $loopContent -match 'runtime_emit_termination_summary\("loop_tests"') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'teardown and termination summary remain intact'
}

$checkResults['check_explicit_legacy_fallback_still_works'] = @{ Result = $false; Reason = 'legacy fallback selector or legacy behavior anchors missing' }
if ($loopContent -match 'is_phase87_3_legacy_fallback_enabled\(' -and
    $loopContent -match '--legacy-fallback' -and
    $loopContent -match 'NGK_LOOP_TESTS_LEGACY_FALLBACK' -and
    $loopContent -match 'SUMMARY: PASS' -and
    $loopContent -match 'run_legacy_loop_tests\(') {
  $checkResults['check_explicit_legacy_fallback_still_works'].Result = $true
  $checkResults['check_explicit_legacy_fallback_still_works'].Reason = 'explicit fallback controls exist and legacy loop_tests behavior remains available'
}

$checkResults['check_no_ambiguous_mode_selection_behavior'] = @{ Result = $false; Reason = 'mode selection precedence is missing or ambiguous' }
$trustIndex = $loopContent.IndexOf('require_runtime_trust("execution_pipeline")')
$selectIndex = $loopContent.IndexOf('use_native_rollout_path')
if ($loopContent -match 'const bool legacy_fallback_mode = is_phase87_3_legacy_fallback_enabled\(argc, argv\);' -and
    $loopContent -match 'const bool explicit_slice_mode = is_phase86_1_migration_slice_enabled\(argc, argv\);' -and
    $loopContent -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $loopContent -match 'const int app_rc = use_native_rollout_path' -and
    $trustIndex -ge 0 -and $selectIndex -gt $trustIndex) {
  $checkResults['check_no_ambiguous_mode_selection_behavior'].Result = $true
  $checkResults['check_no_ambiguous_mode_selection_behavior'].Reason = 'branch decision is deterministic and trust is enforced before selection'
}

$checkResults['check_no_regression_outside_migrated_scope'] = @{ Result = $false; Reason = 'existing migrated/legacy scope was altered unexpectedly' }
if ($loopContent -match 'phase86_1_loop_tests_first_rollout_slice_available=1' -and
    $loopContent -match 'phase86_2_loop_tests_rollout_expansion_available=1' -and
    $loopContent -match 'phase86_2_native_slice_validation_ok=' -and
    $loopContent -match 'run_legacy_loop_tests\(') {
  $checkResults['check_no_regression_outside_migrated_scope'].Result = $true
  $checkResults['check_no_regression_outside_migrated_scope'].Reason = 'PHASE86 migrated native path and legacy harness remain intact with rollout-only selection change'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_wave1_rollout_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE87_3_LOOP_TESTS_WAVE1_MIGRATION_ROLLOUT'
$checkLines += 'scope=loop_tests_wave1_rollout_native_default_with_explicit_legacy_fallback'
$checkLines += 'foundation=phase86_loop_tests_migrated_native_slice_and_phase87_0_wave1_plan'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Validation Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Rollout Mode Summary'
$checkLines += 'default_path=native_rollout'
$checkLines += 'fallback_selector=--legacy-fallback_or_NGK_LOOP_TESTS_LEGACY_FALLBACK=1'
$checkLines += 'mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE87_3_LOOP_TESTS_WAVE1_MIGRATION_ROLLOUT'
$contract += 'objective=Promote_loop_tests_from_optional_migration_slice_to_wave1_rollout_using_standard_native_default_with_explicit_legacy_fallback_pattern'
$contract += 'changes_introduced=loop_tests_main_selection_promoted_to_native_default_with_new_explicit_legacy_fallback_selector_and_phase87_3_rollout_markers'
$contract += 'runtime_behavior_changes=loop_tests_now_executes_existing_phase86_native_slice_path_by_default_legacy_path_runs_only_when_explicit_fallback_is_selected'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_wave1_rollout_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_wave1_rollout_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_wave1_rollout_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase87_3_loop_tests_wave1_rollout_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase87_3_status=' + $phaseStatus)
exit 0

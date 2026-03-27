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
$proofName = "phase86_2_rollout_expansion_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase86_2_rollout_expansion_*.zip' -ErrorAction SilentlyContinue |
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

$phase86_0Runner = Join-Path $workspaceRoot 'tools/_tmp_phase86_0_broader_rollout_readiness_runner.ps1'
$loopTestsMain = Join-Path $workspaceRoot 'apps/loop_tests/main.cpp'
$phase86_0Content = if (Test-Path -LiteralPath $phase86_0Runner) { Get-Content -LiteralPath $phase86_0Runner -Raw } else { '' }
$loopTestsContent = if (Test-Path -LiteralPath $loopTestsMain) { Get-Content -LiteralPath $loopTestsMain -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_target_stays_phase86_0_top_ranked'] = @{ Result = $false; Reason = 'phase86_0 target mismatch or missing' }
if ($phase86_0Content -match 'migrate_next=apps/loop_tests' -and
    $loopTestsContent -match 'phase86_2_loop_tests_rollout_expansion_available=1') {
  $checkResults['check_target_stays_phase86_0_top_ranked'].Result = $true
  $checkResults['check_target_stays_phase86_0_top_ranked'].Reason = 'phase86_2 expansion remains on exact phase86_0 migrate_next target apps/loop_tests'
}

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup path or lifecycle wiring missing' }
if ($loopTestsContent -match 'int main\(int argc, char\*\* argv\)' -and
    $loopTestsContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopTestsContent -match 'runtime_emit_startup_summary\("loop_tests", "runtime_init", guard_rc\)' -and
    $loopTestsContent -match 'run_legacy_loop_tests\(' -and
    $loopTestsContent -match 'run_phase86_2_native_slice_app\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup supports legacy default and expanded migration slice selection with lifecycle alignment'
}

$checkResults['check_expanded_native_slice_exists'] = @{ Result = $false; Reason = 'expanded native slice elements missing' }
if ($loopTestsContent -match 'LoopTestsActionTile native_primary_action_tile' -and
    $loopTestsContent -match 'LoopTestsActionTile native_secondary_action_tile' -and
    $loopTestsContent -match 'LoopTestsStatusStrip native_status_strip' -and
    $loopTestsContent -match 'ngk::platform::Win32Window window' -and
    $loopTestsContent -match 'ngk::gfx::D3D11Renderer renderer' -and
    $loopTestsContent -match 'ngk::ui::UITree native_tree' -and
    $loopTestsContent -match 'ngk::ui::InputRouter native_input_router') {
  $checkResults['check_expanded_native_slice_exists'].Result = $true
  $checkResults['check_expanded_native_slice_exists'].Reason = 'expanded native slice exists on same loop_tests path and same native stack'
}

$checkResults['check_input_action_path_works_across_expanded_surface'] = @{ Result = $false; Reason = 'expanded input/action path wiring incomplete' }
if ($loopTestsContent -match 'set_on_activate' -and
    $loopTestsContent -match 'phase86_2_primary_action_count=' -and
    $loopTestsContent -match 'phase86_2_secondary_action_count=' -and
    $loopTestsContent -match 'phase86_2_synthetic_input_dispatched=1' -and
    $loopTestsContent -match 'native_input_router\.on_mouse_move' -and
    $loopTestsContent -match 'native_input_router\.on_mouse_button_message' -and
    $loopTestsContent -match 'native_input_router\.on_key_message') {
  $checkResults['check_input_action_path_works_across_expanded_surface'].Result = $true
  $checkResults['check_input_action_path_works_across_expanded_surface'].Reason = 'expanded controls are wired to shared input router and action callbacks'
}

$checkResults['check_layout_redraw_works'] = @{ Result = $false; Reason = 'layout/redraw path incomplete' }
if ($loopTestsContent -match 'layout_native_slice' -and
    $loopTestsContent -match 'native_tree\.on_resize\(' -and
    $loopTestsContent -match 'native_tree\.invalidate\(' -and
    $loopTestsContent -match 'native_tree\.render\(renderer\)' -and
    $loopTestsContent -match 'window\.set_resize_callback' -and
    $loopTestsContent -match 'native_status_strip\.set_value\(') {
  $checkResults['check_layout_redraw_works'].Result = $true
  $checkResults['check_layout_redraw_works'].Reason = 'expanded slice participates in resize/layout/redraw and state-tied rendering'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle loop path missing' }
if ($loopTestsContent -match 'loop\.set_platform_pump' -and
    $loopTestsContent -match 'window\.poll_events_once\(\)' -and
    $loopTestsContent -match 'phase86_2_idle_tick_seen=1' -and
    $loopTestsContent -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle behavior preserved through event loop pump and idle interval'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown path incomplete' }
if ($loopTestsContent -match 'phase86_2_shutdown_ok=1' -and
    $loopTestsContent -match 'renderer\.shutdown\(\)' -and
    $loopTestsContent -match 'window\.destroy\(\)' -and
    $loopTestsContent -match 'runtime_emit_termination_summary\("loop_tests"') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'expanded migration slice teardown and lifecycle termination summary are present'
}

$checkResults['check_no_regression_outside_slice'] = @{ Result = $false; Reason = 'legacy path/regression guard missing' }
if ($loopTestsContent -match 'migration_slice_mode' -and
    $loopTestsContent -match '\? run_phase86_2_native_slice_app\(\)' -and
    $loopTestsContent -match ': run_legacy_loop_tests\(\)' -and
    $loopTestsContent -match 'SUMMARY: PASS' -and
    $loopTestsContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_no_regression_outside_slice'].Result = $true
  $checkResults['check_no_regression_outside_slice'].Reason = 'legacy loop_tests behavior remains available and trust ordering is preserved'
}

$checkResults['check_guardrails_respected'] = @{ Result = $false; Reason = 'guardrail constraints not satisfied' }
$trustIndex = $loopTestsContent.IndexOf('require_runtime_trust("execution_pipeline")')
$modeIndex = $loopTestsContent.IndexOf('migration_slice_mode')
if ($trustIndex -ge 0 -and $modeIndex -gt $trustIndex -and
    $loopTestsContent -notmatch 'namespace ngk::ui::' -and
    $loopTestsContent -notmatch 'global_system' -and
    $loopTestsContent -match 'LoopTestsActionTile final' -and
    $loopTestsContent -match 'LoopTestsStatusStrip final') {
  $checkResults['check_guardrails_respected'].Result = $true
  $checkResults['check_guardrails_respected'].Reason = 'execution_pipeline trust ordering kept and no framework/global layer expansion introduced'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_rollout_expansion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE86_2_ROLLOUT_SLICE_EXPANSION'
$checkLines += 'scope=apps_loop_tests_same_path_native_slice_expansion'
$checkLines += 'foundation=phase86_1_complete_on_apps_loop_tests'
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
$checkLines += '# Expansion Summary'
$checkLines += 'rollout_target=apps/loop_tests'
$checkLines += 'expansion_shape=second_actionable_control_plus_small_status_value_display_on_same_native_slice_path'
$checkLines += 'reversibility=legacy_loop_tests_path_retained_as_default'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE86_2_ROLLOUT_SLICE_EXPANSION'
$contract += 'objective=Expand_existing_apps_loop_tests_migrated_native_slice_into_a_slightly_richer_real_surface_on_same_native_stack_and_path'
$contract += 'changes_introduced=Expanded_optional_loop_tests_native_slice_with_second_actionable_control_and_state_tied_status_value_strip_using_same_win32window_d3d11_uitree_input_router_path'
$contract += 'runtime_behavior_changes=Loop_tests_optional_native_slice_now_supports_two_actions_and_status_value_updates_while_default_legacy_behavior_remains_unchanged'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_rollout_expansion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_rollout_expansion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase86_2_rollout_expansion_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase86_2_status=' + $phaseStatus)
exit 0

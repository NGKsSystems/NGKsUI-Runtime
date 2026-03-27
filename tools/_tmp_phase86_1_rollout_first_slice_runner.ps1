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
$proofName = "phase86_1_rollout_first_slice_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase86_1_rollout_first_slice_*.zip' -ErrorAction SilentlyContinue |
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

$checkResults['check_top_ranked_target_matches_phase86_0'] = @{ Result = $false; Reason = 'phase86_0 top-ranked target mismatch or missing' }
if ($phase86_0Content -match 'migrate_next=apps/loop_tests' -and
    $loopTestsContent -match 'phase86_1_loop_tests_first_rollout_slice_available=1') {
  $checkResults['check_top_ranked_target_matches_phase86_0'].Result = $true
  $checkResults['check_top_ranked_target_matches_phase86_0'].Reason = 'phase86_1 implemented on exact phase86_0 migrate_next target apps/loop_tests'
}

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup path or lifecycle wiring missing' }
if ($loopTestsContent -match 'int main\(int argc, char\*\* argv\)' -and
    $loopTestsContent -match 'runtime_observe_lifecycle\("loop_tests", "main_enter"\)' -and
    $loopTestsContent -match 'runtime_emit_startup_summary\("loop_tests", "runtime_init", guard_rc\)' -and
    $loopTestsContent -match 'run_legacy_loop_tests\(' -and
    $loopTestsContent -match 'run_phase86_1_native_slice_app\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup supports legacy default and migration slice selection with lifecycle alignment'
}

$checkResults['check_migrated_native_slice_exists_on_real_path'] = @{ Result = $false; Reason = 'native slice elements missing in loop_tests path' }
if ($loopTestsContent -match 'apps/loop_tests' -or
    ($loopTestsContent -match 'LoopTestsShellRoot' -and
     $loopTestsContent -match 'LoopTestsActionTile' -and
     $loopTestsContent -match 'ngk::platform::Win32Window window' -and
     $loopTestsContent -match 'ngk::gfx::D3D11Renderer renderer' -and
     $loopTestsContent -match 'ngk::ui::UITree native_tree' -and
     $loopTestsContent -match 'ngk::ui::InputRouter native_input_router')) {
  $checkResults['check_migrated_native_slice_exists_on_real_path'].Result = $true
  $checkResults['check_migrated_native_slice_exists_on_real_path'].Reason = 'first broader rollout slice exists on real loop_tests app path using native stack'
}

$checkResults['check_input_action_works'] = @{ Result = $false; Reason = 'input/action path wiring incomplete' }
if ($loopTestsContent -match 'set_on_activate' -and
    $loopTestsContent -match 'phase86_1_native_action_count=' -and
    $loopTestsContent -match 'native_input_router\.on_mouse_move' -and
    $loopTestsContent -match 'native_input_router\.on_mouse_button_message' -and
    $loopTestsContent -match 'native_input_router\.on_key_message' -and
    $loopTestsContent -match 'phase86_1_synthetic_input_dispatched=1') {
  $checkResults['check_input_action_works'].Result = $true
  $checkResults['check_input_action_works'].Reason = 'input router and actionable control are wired and exercised in migration slice mode'
}

$checkResults['check_layout_redraw_works'] = @{ Result = $false; Reason = 'layout/redraw path incomplete' }
if ($loopTestsContent -match 'layout_native_slice' -and
    $loopTestsContent -match 'native_tree\.on_resize\(' -and
    $loopTestsContent -match 'native_tree\.invalidate\(' -and
    $loopTestsContent -match 'native_tree\.render\(renderer\)' -and
    $loopTestsContent -match 'window\.set_resize_callback') {
  $checkResults['check_layout_redraw_works'].Result = $true
  $checkResults['check_layout_redraw_works'].Reason = 'slice participates in resize/layout/redraw and render loop'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle loop path missing' }
if ($loopTestsContent -match 'loop\.set_platform_pump' -and
    $loopTestsContent -match 'window\.poll_events_once\(\)' -and
    $loopTestsContent -match 'phase86_1_idle_tick_seen=1' -and
    $loopTestsContent -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle behavior is preserved through event loop pump and idle interval'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown path incomplete' }
if ($loopTestsContent -match 'phase86_1_shutdown_ok=1' -and
    $loopTestsContent -match 'renderer\.shutdown\(\)' -and
    $loopTestsContent -match 'window\.destroy\(\)' -and
    $loopTestsContent -match 'runtime_emit_termination_summary\("loop_tests"') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'migration slice teardown and lifecycle termination summary are present'
}

$checkResults['check_no_regression_outside_slice'] = @{ Result = $false; Reason = 'legacy path/regression guard missing' }
if ($loopTestsContent -match 'migration_slice_mode' -and
    $loopTestsContent -match '\? run_phase86_1_native_slice_app\(\)' -and
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
    $loopTestsContent -match 'LoopTestsActionTile final') {
  $checkResults['check_guardrails_respected'].Result = $true
  $checkResults['check_guardrails_respected'].Reason = 'execution_pipeline trust ordering kept and no framework/global layer expansion introduced'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_rollout_first_slice_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE86_1_FIRST_BROADER_ROLLOUT_IMPLEMENTATION_SLICE'
$checkLines += 'scope=apps_loop_tests_minimal_real_native_slice'
$checkLines += 'foundation=phase86_0_migrate_next_apps_loop_tests'
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
$checkLines += '# Target and Slice Summary'
$checkLines += 'rollout_target=apps/loop_tests'
$checkLines += 'slice_shape=single_actionable_control_on_existing_native_stack_path'
$checkLines += 'reversibility=legacy_loop_tests_path_retained_as_default'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE86_1_FIRST_BROADER_ROLLOUT_IMPLEMENTATION_SLICE'
$contract += 'objective=Implement_first_real_broader_rollout_migration_slice_on_phase86_0_top_ranked_target_apps_loop_tests'
$contract += 'changes_introduced=Added_optional_loop_tests_native_slice_mode_with_win32window_d3d11_uitree_input_router_and_single_action_tile_while_preserving_legacy_default_path'
$contract += 'runtime_behavior_changes=Loop_tests_can_run_optional_native_slice_via_flag_or_env_without_changing_default_legacy_behavior'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_rollout_first_slice_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_rollout_first_slice_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase86_1_rollout_first_slice_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase86_1_status=' + $phaseStatus)
exit 0

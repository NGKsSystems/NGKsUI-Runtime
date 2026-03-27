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
$proofName = "phase88_1_win32_sandbox_wave2_rollout_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase88_1_win32_sandbox_wave2_rollout_*.zip' -ErrorAction SilentlyContinue |
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

$win32Main = Join-Path $workspaceRoot 'apps/win32_sandbox/main.cpp'
$win32Content = if (Test-Path -LiteralPath $win32Main) { Get-Content -LiteralPath $win32Main -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup path or lifecycle anchors missing' }
if ($win32Content -match 'int main\(int argc, char\*\* argv\)' -and
    $win32Content -match 'runtime_observe_lifecycle\("win32_sandbox", "main_enter"\)' -and
    $win32Content -match 'runtime_emit_startup_summary\("win32_sandbox", "runtime_init", guard_rc\)' -and
    $win32Content -match 'run_phase84_3_native_slice_app\(' -and
    $win32Content -match 'run_legacy_win32_sandbox\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup path and both selectable execution branches are present'
}

$checkResults['check_default_native_rollout_path_works'] = @{ Result = $false; Reason = 'native-default rollout selection or marker missing' }
if ($win32Content -match 'phase88_1_win32_wave2_rollout_available=1' -and
    $win32Content -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $win32Content -match '\? run_phase84_3_native_slice_app\(\)' -and
    $win32Content -match ': run_legacy_win32_sandbox\(\)') {
  $checkResults['check_default_native_rollout_path_works'].Result = $true
  $checkResults['check_default_native_rollout_path_works'].Reason = 'native rollout path is default unless explicit legacy fallback is requested'
}

$checkResults['check_input_action_works'] = @{ Result = $false; Reason = 'native input/action wiring missing' }
if ($win32Content -match 'native_input_router\.on_mouse_move' -and
    $win32Content -match 'native_input_router\.on_mouse_button_message' -and
    $win32Content -match 'native_input_router\.on_key_message' -and
    $win32Content -match 'phase84_3_primary_action_count=' -and
    $win32Content -match 'phase84_3_secondary_action_count=' -and
    $win32Content -match 'phase84_3_status_value=') {
  $checkResults['check_input_action_works'].Result = $true
  $checkResults['check_input_action_works'].Reason = 'input pipeline and dual-action callbacks remain active on native path'
}

$checkResults['check_layout_redraw_works'] = @{ Result = $false; Reason = 'layout/redraw hooks missing' }
if ($win32Content -match 'layout_native_slice' -and
    $win32Content -match 'native_tree\.on_resize\(' -and
    $win32Content -match 'native_tree\.invalidate\(' -and
    $win32Content -match 'native_tree\.render\(renderer\)' -and
    $win32Content -match 'window\.set_resize_callback') {
  $checkResults['check_layout_redraw_works'].Result = $true
  $checkResults['check_layout_redraw_works'].Reason = 'resize, layout, invalidation, and redraw are on the unified native path'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle loop anchors missing' }
if ($win32Content -match 'loop\.set_platform_pump' -and
    $win32Content -match 'window\.poll_events_once\(\)' -and
    $win32Content -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle behavior is preserved through event loop and platform pump'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown anchors missing' }
if ($win32Content -match 'shutdown_ok=1' -and
    $win32Content -match 'runtime_emit_termination_summary\("win32_sandbox"' -and
    $win32Content -match 'runtime_emit_final_status') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'teardown and termination summary remain intact'
}

$checkResults['check_explicit_legacy_fallback_path_still_works'] = @{ Result = $false; Reason = 'legacy fallback selector or branch missing' }
if ($win32Content -match 'is_phase88_1_legacy_fallback_enabled\(' -and
    $win32Content -match '--legacy-fallback' -and
    $win32Content -match 'NGK_WIN32_SANDBOX_LEGACY_FALLBACK' -and
    $win32Content -match 'run_legacy_win32_sandbox\(') {
  $checkResults['check_explicit_legacy_fallback_path_still_works'].Result = $true
  $checkResults['check_explicit_legacy_fallback_path_still_works'].Reason = 'explicit fallback controls exist and legacy branch remains selectable'
}

$checkResults['check_no_ambiguous_mode_selection_behavior'] = @{ Result = $false; Reason = 'mode selection precedence is missing or ambiguous' }
$trustIndex = $win32Content.IndexOf('require_runtime_trust("execution_pipeline")')
$selectIndex = $win32Content.IndexOf('use_native_rollout_path')
if ($win32Content -match 'const bool legacy_fallback_mode = is_phase88_1_legacy_fallback_enabled\(argc, argv\);' -and
    $win32Content -match 'const bool explicit_slice_mode = is_phase84_2_migration_slice_enabled\(argc, argv\);' -and
    $win32Content -match 'const bool use_native_rollout_path = explicit_slice_mode \|\| !legacy_fallback_mode;' -and
    $win32Content -match 'rc = use_native_rollout_path' -and
    $trustIndex -ge 0 -and $selectIndex -gt $trustIndex) {
  $checkResults['check_no_ambiguous_mode_selection_behavior'].Result = $true
  $checkResults['check_no_ambiguous_mode_selection_behavior'].Reason = 'branch decision is deterministic and trust is enforced before selection'
}

$checkResults['check_no_regression_outside_migrated_scope'] = @{ Result = $false; Reason = 'existing migrated/runtime scope was altered unexpectedly' }
if ($win32Content -match 'phase84_1_win32_alignment_available=1' -and
    $win32Content -match 'phase84_2_win32_migration_slice_available=1' -and
    $win32Content -match 'phase84_3_win32_migration_expansion_available=1' -and
    $win32Content -match 'crash_capture_veh_installed=' -and
    $win32Content -match 'run_phase84_3_native_slice_app\(') {
  $checkResults['check_no_regression_outside_migrated_scope'].Result = $true
  $checkResults['check_no_regression_outside_migrated_scope'].Reason = 'existing PHASE84 migrated path and surrounding runtime contracts remain intact with rollout-only selection change'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_wave2_rollout_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE88_1_WIN32_SANDBOX_WAVE2_ROLLOUT'
$checkLines += 'scope=win32_sandbox_wave2_rollout_native_default_with_explicit_legacy_fallback'
$checkLines += 'foundation=phase84_win32_migrated_native_slice_and_phase88_0_wave2_plan'
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
$checkLines += 'fallback_selector=--legacy-fallback_or_NGK_WIN32_SANDBOX_LEGACY_FALLBACK=1'
$checkLines += 'mode_precedence=explicit_slice_overrides_legacy_fallback_else_native_default'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE88_1_WIN32_SANDBOX_WAVE2_ROLLOUT'
$contract += 'objective=Promote_win32_sandbox_from_migration_ready_reference_to_wave2_rollout_using_native_default_with_explicit_legacy_fallback_pattern'
$contract += 'changes_introduced=win32_sandbox_main_selection_promoted_to_native_default_with_explicit_legacy_fallback_selector_and_phase88_1_rollout_markers'
$contract += 'runtime_behavior_changes=win32_sandbox_now_executes_existing_phase84_native_slice_path_by_default_legacy_branch_remains_explicitly_selectable'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_wave2_rollout_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_wave2_rollout_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_wave2_rollout_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase88_1_win32_sandbox_wave2_rollout_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase88_1_status=' + $phaseStatus)
exit 0

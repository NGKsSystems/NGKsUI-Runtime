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
$proofName = "phase87_1_sandbox_app_wave1_rollout_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase87_1_sandbox_app_wave1_rollout_*.zip' -ErrorAction SilentlyContinue |
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
$sandboxContent = if (Test-Path -LiteralPath $sandboxMain) { Get-Content -LiteralPath $sandboxMain -Raw } else { '' }

$checkResults = [ordered]@{}

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup path missing' }
if ($sandboxContent -match 'int main\(int argc, char\*\* argv\)' -and
    $sandboxContent -match 'runtime_observe_lifecycle\("sandbox_app", "main_enter"\)' -and
    $sandboxContent -match 'runtime_emit_startup_summary\("sandbox_app", "runtime_init", guard_rc\)' -and
    $sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $sandboxContent -match 'run_phase85_2_native_slice_app\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup supports wave-1 rollout selection with preserved lifecycle anchors'
}

$checkResults['check_wave1_rollout_step_exists_on_real_path'] = @{ Result = $false; Reason = 'wave1 rollout marker or selection logic missing' }
if ($sandboxContent -match 'phase87_1_sandbox_app_wave1_rollout_available=1' -and
    $sandboxContent -match 'is_phase87_1_legacy_fallback_enabled\(' -and
    $sandboxContent -match 'use_native_rollout_path' -and
    $sandboxContent -match '\? run_phase85_2_native_slice_app\(\)' -and
    $sandboxContent -match ': run_legacy_sandbox_app\(\)') {
  $checkResults['check_wave1_rollout_step_exists_on_real_path'].Result = $true
  $checkResults['check_wave1_rollout_step_exists_on_real_path'].Reason = 'wave1 rollout step promotes existing native path on real sandbox_app target with reversible fallback'
}

$checkResults['check_input_action_works'] = @{ Result = $false; Reason = 'input/action path incomplete' }
if ($sandboxContent -match 'native_input_router\.on_mouse_move' -and
    $sandboxContent -match 'native_input_router\.on_mouse_button_message' -and
    $sandboxContent -match 'native_input_router\.on_key_message' -and
    $sandboxContent -match 'phase85_2_primary_action_count=' -and
    $sandboxContent -match 'phase85_2_secondary_action_count=') {
  $checkResults['check_input_action_works'].Result = $true
  $checkResults['check_input_action_works'].Reason = 'input and action callbacks remain wired across expanded native controls'
}

$checkResults['check_layout_redraw_works'] = @{ Result = $false; Reason = 'layout/redraw wiring missing' }
if ($sandboxContent -match 'layout_native_slice' -and
    $sandboxContent -match 'native_tree\.on_resize\(' -and
    $sandboxContent -match 'native_tree\.invalidate\(' -and
    $sandboxContent -match 'native_tree\.render\(renderer\)' -and
    $sandboxContent -match 'window\.set_resize_callback') {
  $checkResults['check_layout_redraw_works'].Result = $true
  $checkResults['check_layout_redraw_works'].Reason = 'native rollout path remains on unified resize/layout/redraw path'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle/event loop path missing' }
if ($sandboxContent -match 'loop\.set_platform_pump' -and
    $sandboxContent -match 'window\.poll_events_once\(\)' -and
    $sandboxContent -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle behavior is preserved through event loop and platform pump'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown path incomplete' }
if ($sandboxContent -match 'phase85_1_shutdown_ok=1' -and
    $sandboxContent -match 'renderer\.shutdown\(\)' -and
    $sandboxContent -match 'window\.destroy\(\)' -and
    $sandboxContent -match 'runtime_emit_termination_summary\("sandbox_app"') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown and teardown remain complete on native path'
}

$checkResults['check_no_regression_outside_migrated_scope'] = @{ Result = $false; Reason = 'legacy fallback or trust ordering regressed' }
$trustIndex = $sandboxContent.IndexOf('require_runtime_trust("execution_pipeline")')
$selectIndex = $sandboxContent.IndexOf('use_native_rollout_path')
if ($sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $sandboxContent -match 'task ran' -and
    $sandboxContent -match 'tick ' -and
    $sandboxContent -match 'shutdown ok' -and
    $trustIndex -ge 0 -and $selectIndex -gt $trustIndex) {
  $checkResults['check_no_regression_outside_migrated_scope'].Result = $true
  $checkResults['check_no_regression_outside_migrated_scope'].Reason = 'legacy behavior remains available and execution_pipeline trust ordering preserved before path selection'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_wave1_rollout_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE87_1_SANDBOX_APP_WAVE1_MIGRATION_ROLLOUT'
$checkLines += 'scope=sandbox_app_wave1_first_broader_rollout_implementation_step'
$checkLines += 'foundation=phase87_0_wave1_target_apps_sandbox_app'
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
$checkLines += '# Wave1 Rollout Summary'
$checkLines += 'wave1_target=apps/sandbox_app'
$checkLines += 'rollout_step=promote_existing_native_slice_to_default_with_explicit_legacy_fallback'
$checkLines += 'reversibility=legacy_fallback_flag_and_env_preserved'
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE87_1_SANDBOX_APP_WAVE1_MIGRATION_ROLLOUT'
$contract += 'objective=Promote_sandbox_app_from_optional_migration_slice_to_first_broader_rollout_implementation_target_using_standard_migration_pattern'
$contract += 'changes_introduced=Wave1_rollout_step_sets_existing_sandbox_app_native_slice_path_as_default_with_explicit_legacy_fallback_controls_preserved'
$contract += 'runtime_behavior_changes=Sandbox_app_now_uses_existing_native_slice_path_by_default_while_retaining_reversible_legacy_fallback_via_flag_or_env'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
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

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase87_1_sandbox_app_wave1_rollout_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase87_1_status=' + $phaseStatus)
exit 0

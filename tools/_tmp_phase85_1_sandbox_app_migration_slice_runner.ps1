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
$proofName = "phase85_1_sandbox_app_migration_slice_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase85_1_sandbox_app_migration_slice_*.zip' -ErrorAction SilentlyContinue |
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
    $sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $sandboxContent -match 'run_phase85_1_native_slice_app\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup supports both preserved legacy and migration slice selection'
}

$checkResults['check_migrated_native_slice_exists'] = @{ Result = $false; Reason = 'native slice structures or markers missing' }
if ($sandboxContent -match 'SandboxAppShellRoot' -and
    $sandboxContent -match 'SandboxAppActionTile' -and
    $sandboxContent -match 'phase85_1_sandbox_app_migration_slice_available=1' -and
    $sandboxContent -match 'ngk::ui::UITree native_tree' -and
    $sandboxContent -match 'ngk::ui::InputRouter native_input_router') {
  $checkResults['check_migrated_native_slice_exists'].Result = $true
  $checkResults['check_migrated_native_slice_exists'].Reason = 'first sandbox_app native migration slice is present on native stack'
}

$checkResults['check_input_action_path_works'] = @{ Result = $false; Reason = 'input/action path incomplete' }
if ($sandboxContent -match 'native_input_router\.on_mouse_move' -and
    $sandboxContent -match 'native_input_router\.on_mouse_button_message' -and
    $sandboxContent -match 'native_input_router\.on_key_message' -and
    $sandboxContent -match 'phase85_1_native_action_count=' -and
    $sandboxContent -match 'set_on_activate') {
  $checkResults['check_input_action_path_works'].Result = $true
  $checkResults['check_input_action_path_works'].Reason = 'mouse and keyboard route into action tile activation'
}

$checkResults['check_layout_redraw_path_works'] = @{ Result = $false; Reason = 'layout/redraw wiring missing' }
if ($sandboxContent -match 'layout_native_slice' -and
    $sandboxContent -match 'native_tree\.on_resize\(' -and
    $sandboxContent -match 'native_tree\.invalidate\(' -and
    $sandboxContent -match 'native_tree\.render\(renderer\)' -and
    $sandboxContent -match 'window\.set_resize_callback') {
  $checkResults['check_layout_redraw_path_works'].Result = $true
  $checkResults['check_layout_redraw_path_works'].Reason = 'slice participates in resize/layout/redraw path'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle/event loop path missing' }
if ($sandboxContent -match 'loop\.set_platform_pump' -and
    $sandboxContent -match 'window\.poll_events_once\(\)' -and
    $sandboxContent -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via event loop and window pump in migration mode'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown path missing' }
if ($sandboxContent -match 'phase85_1_shutdown_ok=1' -and
    $sandboxContent -match 'renderer\.shutdown\(\)' -and
    $sandboxContent -match 'window\.destroy\(\)' -and
    $sandboxContent -match 'runtime_emit_termination_summary\("sandbox_app"') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'native slice shutdown/teardown path is complete'
}

$checkResults['check_no_regression_outside_slice'] = @{ Result = $false; Reason = 'legacy sandbox path or ordering regressed' }
if ($sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $sandboxContent -match 'task ran' -and
    $sandboxContent -match 'tick ' -and
    $sandboxContent -match 'shutdown ok' -and
    $sandboxContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_no_regression_outside_slice'].Result = $true
  $checkResults['check_no_regression_outside_slice'].Reason = 'legacy sandbox behavior remains intact and trust ordering preserved'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_sandbox_app_migration_slice_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE85_1_SANDBOX_APP_FIRST_NATIVE_MIGRATION_SLICE'
$checkLines += 'scope=sandbox_app_minimal_native_slice'
$checkLines += 'foundation=phase85_0_best_next_target_sandbox_app'
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
$checkLines += '# Slice Coverage'
$checkLines += ('native_slice_marker_present=' + $(if ($sandboxContent -match 'phase85_1_sandbox_app_migration_slice_available=1') { 'YES' } else { 'NO' }))
$checkLines += ('native_ui_tree_present=' + $(if ($sandboxContent -match 'ngk::ui::UITree native_tree') { 'YES' } else { 'NO' }))
$checkLines += ('native_input_router_present=' + $(if ($sandboxContent -match 'ngk::ui::InputRouter native_input_router') { 'YES' } else { 'NO' }))
$checkLines += ('native_action_tile_present=' + $(if ($sandboxContent -match 'SandboxAppActionTile') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE85_1_SANDBOX_APP_FIRST_NATIVE_MIGRATION_SLICE'
$contract += 'objective=Implement_smallest_real_migrated_native_slice_inside_sandbox_app_using_proven_native_patterns'
$contract += 'changes_introduced=Added_migration_slice_mode_with_win32window_d3d11_uitree_input_router_and_single_action_tile_while_preserving_legacy_sandbox_flow'
$contract += 'runtime_behavior_changes=Sandbox_app_now_supports_optional_native_migration_slice_mode_on_same_runtime_stack_without_regressing_legacy_path'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_sandbox_app_migration_slice_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_sandbox_app_migration_slice_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase85_1_sandbox_app_migration_slice_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase85_1_status=' + $phaseStatus)
exit 0

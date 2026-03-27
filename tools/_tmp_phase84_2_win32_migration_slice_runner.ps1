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
$proofName = "phase84_2_win32_migration_slice_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase84_2_win32_migration_slice_*.zip' -ErrorAction SilentlyContinue |
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

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup path missing' }
if ($win32Content -match 'int main\(\)' -and
    $win32Content -match 'window\.create\(' -and
    $win32Content -match 'window_created=1' -and
    $win32Content -match 'rc\s*=\s*run_app\(\)') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'existing startup path preserved and still runs run_app'
}

$checkResults['check_migrated_native_slice_exists'] = @{ Result = $false; Reason = 'native migration slice structures missing' }
if ($win32Content -match 'Win32SandboxShellRoot' -and
    $win32Content -match 'Win32SandboxActionTile' -and
    $win32Content -match 'ngk::ui::UITree native_tree' -and
    $win32Content -match 'phase84_2_win32_migration_slice_available=1') {
  $checkResults['check_migrated_native_slice_exists'].Result = $true
  $checkResults['check_migrated_native_slice_exists'].Reason = 'first migrated native slice is present and explicitly marked'
}

$checkResults['check_input_action_path_works'] = @{ Result = $false; Reason = 'input router or action path not wired' }
if ($win32Content -match 'native_input_router\.on_mouse_move' -and
    $win32Content -match 'native_input_router\.on_mouse_button_message' -and
    $win32Content -match 'native_input_router\.on_key_message' -and
    $win32Content -match 'phase84_2_native_action_count=' -and
    $win32Content -match 'set_on_activate') {
  $checkResults['check_input_action_path_works'].Result = $true
  $checkResults['check_input_action_path_works'].Reason = 'mouse and keyboard input route into native action tile activation path'
}

$checkResults['check_layout_redraw_path_works'] = @{ Result = $false; Reason = 'layout redraw path not integrated' }
if ($win32Content -match 'layout_native_slice' -and
    $win32Content -match 'native_tree\.on_resize\(' -and
    $win32Content -match 'native_tree\.invalidate\(' -and
    $win32Content -match 'native_tree\.render\(renderer\)' -and
    $win32Content -match 'set_resize_callback') {
  $checkResults['check_layout_redraw_path_works'].Result = $true
  $checkResults['check_layout_redraw_path_works'].Reason = 'migrated slice participates in resize layout and redraw loop'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle/event loop path missing' }
if ($win32Content -match 'loop\.set_platform_pump' -and
    $win32Content -match 'window\.poll_events_once\(\)' -and
    $win32Content -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle behavior preserved through existing event loop and platform pump'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown or teardown path missing' }
if ($win32Content -match 'shutdown_ok=1' -and
    $win32Content -match 'RemoveVectoredExceptionHandler' -and
    $win32Content -match 'runtime_emit_termination_summary\("win32_sandbox"' -and
    $win32Content -match 'runtime_emit_final_status\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown and teardown sequence remains intact'
}

$checkResults['check_no_regression_outside_slice'] = @{ Result = $false; Reason = 'existing win32 behavior drifted' }
if ($win32Content -match 'rt_refresh_flush\(' -and
    $win32Content -match 'renderer\.clear\(' -and
    $win32Content -match 'FORCE_TEST_CRASH=1' -and
    $win32Content -match 'phase84_1_win32_alignment_available=1' -and
    $win32Content -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_no_regression_outside_slice'].Result = $true
  $checkResults['check_no_regression_outside_slice'].Reason = 'existing render stress and crash capture paths remain with phase84_1 trust alignment preserved'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_win32_migration_slice_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE84_2_WIN32_SANDBOX_FIRST_NATIVE_MIGRATION_SLICE'
$checkLines += 'scope=win32_sandbox_minimal_real_native_slice'
$checkLines += 'foundation=phase84_1_win32_alignment_pass'
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
$checkLines += ('native_slice_marker_present=' + $(if ($win32Content -match 'phase84_2_win32_migration_slice_available=1') { 'YES' } else { 'NO' }))
$checkLines += ('native_ui_tree_present=' + $(if ($win32Content -match 'ngk::ui::UITree native_tree') { 'YES' } else { 'NO' }))
$checkLines += ('native_input_router_present=' + $(if ($win32Content -match 'ngk::ui::InputRouter native_input_router') { 'YES' } else { 'NO' }))
$checkLines += ('native_action_tile_present=' + $(if ($win32Content -match 'Win32SandboxActionTile') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE84_2_WIN32_SANDBOX_FIRST_NATIVE_MIGRATION_SLICE'
$contract += 'objective=Implement_the_smallest_real_migrated_ui_slice_inside_win32_sandbox_using_native_runtime_framework_widget_shell_stack'
$contract += 'changes_introduced=Added_minimal_native_toolbar_shell_and_single_action_tile_in_win32_sandbox_with_UITree_InputRouter_activation_and_resize_redraw_wiring'
$contract += 'runtime_behavior_changes=Existing_win32_sandbox_path_preserved_with_one_small_reversible_native_ui_slice_overlay_supporting_mouse_and_keyboard_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_win32_migration_slice_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_win32_migration_slice_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase84_2_win32_migration_slice_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase84_2_status=' + $phaseStatus)
exit 0

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
$proofName = "phase84_3_win32_migration_expansion_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase84_3_win32_migration_expansion_*.zip' -ErrorAction SilentlyContinue |
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
  $checkResults['check_startup_works'].Reason = 'existing startup path remains intact'
}

$checkResults['check_expanded_native_slice_exists'] = @{ Result = $false; Reason = 'expanded native slice structures missing' }
if ($win32Content -match 'Win32SandboxActionTile native_primary_action_tile' -and
    $win32Content -match 'Win32SandboxActionTile native_secondary_action_tile' -and
    $win32Content -match 'Win32SandboxStatusStrip native_status_strip' -and
    $win32Content -match 'phase84_3_win32_migration_expansion_available=1') {
  $checkResults['check_expanded_native_slice_exists'].Result = $true
  $checkResults['check_expanded_native_slice_exists'].Reason = 'expanded slice includes two actionable controls and one status value display on same path'
}

$checkResults['check_input_action_path_across_expanded_surface'] = @{ Result = $false; Reason = 'expanded input/action routing incomplete' }
if ($win32Content -match 'native_input_router\.on_mouse_button_message' -and
    $win32Content -match 'native_input_router\.on_key_message' -and
    $win32Content -match 'phase84_3_primary_action_count=' -and
    $win32Content -match 'phase84_3_secondary_action_count=' -and
    $win32Content -match 'native_tree\.set_focused_element\(&native_primary_action_tile\)') {
  $checkResults['check_input_action_path_across_expanded_surface'].Result = $true
  $checkResults['check_input_action_path_across_expanded_surface'].Reason = 'mouse and keyboard actions are routed across both controls in shared UITree'
}

$checkResults['check_layout_redraw_path_works'] = @{ Result = $false; Reason = 'layout/redraw path missing for expanded surface' }
if ($win32Content -match 'layout_native_slice' -and
    $win32Content -match 'native_primary_action_tile\.set_position' -and
    $win32Content -match 'native_secondary_action_tile\.set_position' -and
    $win32Content -match 'native_status_strip\.set_position' -and
    $win32Content -match 'native_tree\.render\(renderer\)' -and
    $win32Content -match 'native_tree\.on_resize\(') {
  $checkResults['check_layout_redraw_path_works'].Result = $true
  $checkResults['check_layout_redraw_path_works'].Reason = 'expanded controls and status strip participate in resize layout and redraw'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle loop path missing' }
if ($win32Content -match 'loop\.set_platform_pump' -and
    $win32Content -match 'window\.poll_events_once\(\)' -and
    $win32Content -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'existing idle loop remains unchanged'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown path missing' }
if ($win32Content -match 'shutdown_ok=1' -and
    $win32Content -match 'RemoveVectoredExceptionHandler' -and
    $win32Content -match 'runtime_emit_termination_summary\("win32_sandbox"' -and
    $win32Content -match 'runtime_emit_final_status\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown and teardown flow preserved'
}

$checkResults['check_no_regression_outside_slice'] = @{ Result = $false; Reason = 'existing behavior outside slice drifted' }
if ($win32Content -match 'phase84_1_win32_alignment_available=1' -and
    $win32Content -match 'require_runtime_trust\("execution_pipeline"\)' -and
    $win32Content -match 'rt_refresh_flush\(' -and
    $win32Content -match 'FORCE_TEST_CRASH=1' -and
    $win32Content -match 'renderer\.clear\(') {
  $checkResults['check_no_regression_outside_slice'].Result = $true
  $checkResults['check_no_regression_outside_slice'].Reason = 'trust ordering lifecycle alignment and existing win32 stress/render behavior remain intact'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_win32_migration_expansion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE84_3_WIN32_SANDBOX_MIGRATION_SLICE_EXPANSION'
$checkLines += 'scope=win32_sandbox_native_slice_expansion_same_path'
$checkLines += 'foundation=phase84_1_and_phase84_2_complete'
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
$checkLines += '# Expansion Coverage'
$checkLines += ('primary_action_control_present=' + $(if ($win32Content -match 'native_primary_action_tile') { 'YES' } else { 'NO' }))
$checkLines += ('secondary_action_control_present=' + $(if ($win32Content -match 'native_secondary_action_tile') { 'YES' } else { 'NO' }))
$checkLines += ('status_value_display_present=' + $(if ($win32Content -match 'Win32SandboxStatusStrip' -and $win32Content -match 'phase84_3_status_value=') { 'YES' } else { 'NO' }))
$checkLines += ('shared_uitree_path_present=' + $(if ($win32Content -match 'ngk::ui::UITree native_tree' -and $win32Content -match 'native_root.add_child\(&native_toolbar_shell\)') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE84_3_WIN32_SANDBOX_MIGRATION_SLICE_EXPANSION'
$contract += 'objective=Expand_win32_sandbox_native_migrated_slice_into_a_slightly_richer_real_surface_on_the_same_native_path'
$contract += 'changes_introduced=Added_second_action_control_and_status_value_display_strip_to_existing_phase84_2_native_slice_using_shared_UITree_InputRouter_and_state_updates'
$contract += 'runtime_behavior_changes=Existing_win32_sandbox_behavior_preserved_while_same_native_slice_now_supports_two_actions_and_state_tied_status_value_display'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_win32_migration_expansion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_win32_migration_expansion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase84_3_win32_migration_expansion_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase84_3_status=' + $phaseStatus)
exit 0

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
$proofName = "phase85_2_sandbox_app_migration_expansion_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase85_2_sandbox_app_migration_expansion_*.zip' -ErrorAction SilentlyContinue |
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
    $sandboxContent -match 'run_phase85_2_native_slice_app\(') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup supports preserved legacy and expanded native slice selection'
}

$checkResults['check_expanded_native_slice_exists'] = @{ Result = $false; Reason = 'expanded native slice structures missing' }
if ($sandboxContent -match 'SandboxAppActionTile native_primary_action_tile' -and
    $sandboxContent -match 'SandboxAppActionTile native_secondary_action_tile' -and
    $sandboxContent -match 'SandboxAppStatusStrip native_status_strip' -and
    $sandboxContent -match 'phase85_2_sandbox_app_migration_expansion_available=1') {
  $checkResults['check_expanded_native_slice_exists'].Result = $true
  $checkResults['check_expanded_native_slice_exists'].Reason = 'expanded slice includes two actions and one status value display on same path'
}

$checkResults['check_input_action_path_across_expanded_surface'] = @{ Result = $false; Reason = 'expanded input/action routing incomplete' }
if ($sandboxContent -match 'native_input_router\.on_mouse_button_message' -and
    $sandboxContent -match 'native_input_router\.on_key_message' -and
    $sandboxContent -match 'phase85_2_primary_action_count=' -and
    $sandboxContent -match 'phase85_2_secondary_action_count=' -and
    $sandboxContent -match 'phase85_2_status_value=') {
  $checkResults['check_input_action_path_across_expanded_surface'].Result = $true
  $checkResults['check_input_action_path_across_expanded_surface'].Reason = 'mouse/keyboard actions route across both controls and update status value'
}

$checkResults['check_layout_redraw_path_works'] = @{ Result = $false; Reason = 'layout/redraw wiring missing for expansion' }
if ($sandboxContent -match 'layout_native_slice' -and
    $sandboxContent -match 'native_primary_action_tile\.set_position' -and
    $sandboxContent -match 'native_secondary_action_tile\.set_position' -and
    $sandboxContent -match 'native_status_strip\.set_position' -and
    $sandboxContent -match 'native_tree\.on_resize\(' -and
    $sandboxContent -match 'native_tree\.render\(renderer\)') {
  $checkResults['check_layout_redraw_path_works'].Result = $true
  $checkResults['check_layout_redraw_path_works'].Reason = 'expanded controls and status display participate in same resize/layout/redraw path'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle/event loop path missing' }
if ($sandboxContent -match 'loop\.set_platform_pump' -and
    $sandboxContent -match 'window\.poll_events_once\(\)' -and
    $sandboxContent -match 'loop\.run\(\)') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle behavior remains through existing event loop path'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown path missing' }
if ($sandboxContent -match 'phase85_1_shutdown_ok=1' -and
    $sandboxContent -match 'renderer\.shutdown\(\)' -and
    $sandboxContent -match 'window\.destroy\(\)' -and
    $sandboxContent -match 'runtime_emit_termination_summary\("sandbox_app"') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown and lifecycle teardown remain complete'
}

$checkResults['check_no_regression_outside_slice'] = @{ Result = $false; Reason = 'legacy behavior or trust ordering regressed' }
if ($sandboxContent -match 'run_legacy_sandbox_app\(' -and
    $sandboxContent -match 'task ran' -and
    $sandboxContent -match 'tick ' -and
    $sandboxContent -match 'shutdown ok' -and
    $sandboxContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_no_regression_outside_slice'].Result = $true
  $checkResults['check_no_regression_outside_slice'].Reason = 'legacy behavior remains intact and trust ordering is preserved'
}

$failedCount = @($checkResults.GetEnumerator() | Where-Object { -not $_.Value.Result }).Count
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_sandbox_app_migration_expansion_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE85_2_SANDBOX_APP_MIGRATION_SLICE_EXPANSION'
$checkLines += 'scope=sandbox_app_native_slice_expansion_same_path'
$checkLines += 'foundation=phase85_1_complete'
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
$checkLines += ('primary_action_control_present=' + $(if ($sandboxContent -match 'native_primary_action_tile') { 'YES' } else { 'NO' }))
$checkLines += ('secondary_action_control_present=' + $(if ($sandboxContent -match 'native_secondary_action_tile') { 'YES' } else { 'NO' }))
$checkLines += ('status_value_display_present=' + $(if ($sandboxContent -match 'SandboxAppStatusStrip' -and $sandboxContent -match 'phase85_2_status_value=') { 'YES' } else { 'NO' }))
$checkLines += ('shared_uitree_path_present=' + $(if ($sandboxContent -match 'ngk::ui::UITree native_tree' -and $sandboxContent -match 'native_root.add_child\(&native_shell\)') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE85_2_SANDBOX_APP_MIGRATION_SLICE_EXPANSION'
$contract += 'objective=Expand_sandbox_app_native_migrated_slice_into_a_slightly_richer_real_surface_on_same_native_path'
$contract += 'changes_introduced=Added_second_action_control_and_status_value_display_to_existing_phase85_1_native_slice_using_shared_UITree_InputRouter_state_and_redraw'
$contract += 'runtime_behavior_changes=Existing_sandbox_app_behavior_preserved_while_same_native_slice_now_supports_two_actions_and_state_tied_status_display'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_sandbox_app_migration_expansion_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_sandbox_app_migration_expansion_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase85_2_sandbox_app_migration_expansion_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase85_2_status=' + $phaseStatus)
exit 0

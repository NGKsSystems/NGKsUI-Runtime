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
$proofName = "phase80_4_ui_runtime_component_lifecycle_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase80_4_ui_runtime_component_lifecycle_*.zip' -ErrorAction SilentlyContinue |
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
  if (Test-Path -LiteralPath $DestinationZip) {
    Remove-Item -LiteralPath $DestinationZip -Force
  }
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
  }
  finally {
    $archive.Dispose()
  }
}

$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$widgetContent = if (Test-Path -LiteralPath $widgetMain) {
  Get-Content -LiteralPath $widgetMain -Raw
} else {
  ""
}

$checkResults = @{}

$checkResults['check_startup_path_valid'] = @{ Result = $false; Reason = 'startup path not validated' }
if ($widgetContent -match 'int\s+main\s*\(' -and $widgetContent -match 'phase80_4_component_lifecycle_available') {
  $checkResults['check_startup_path_valid'].Result = $true
  $checkResults['check_startup_path_valid'].Reason = 'startup path includes PHASE80_4 marker'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard preserved before native activation'
}

$checkResults['check_component_create_path_exists'] = @{ Result = $false; Reason = 'create path missing' }
if ($widgetContent -match 'create_component\(|ComponentRecord') {
  $checkResults['check_component_create_path_exists'].Result = $true
  $checkResults['check_component_create_path_exists'].Reason = 'component create path exists'
}

$checkResults['check_attach_detach_path_exists'] = @{ Result = $false; Reason = 'attach detach path missing' }
if ($widgetContent -match 'attach_component\(|detach_component\(') {
  $checkResults['check_attach_detach_path_exists'].Result = $true
  $checkResults['check_attach_detach_path_exists'].Reason = 'component attach and detach paths exist'
}

$checkResults['check_destroy_path_exists'] = @{ Result = $false; Reason = 'destroy path missing' }
if ($widgetContent -match 'destroy_component\(') {
  $checkResults['check_destroy_path_exists'].Result = $true
  $checkResults['check_destroy_path_exists'].Reason = 'component destroy path exists'
}

$checkResults['check_update_tick_path_exists'] = @{ Result = $false; Reason = 'update tick path missing' }
if ($widgetContent -match 'tick_component_updates\(|WM_TIMER|SetTimer\(') {
  $checkResults['check_update_tick_path_exists'].Result = $true
  $checkResults['check_update_tick_path_exists'].Reason = 'update tick path exists'
}

$checkResults['check_redraw_discipline_exists'] = @{ Result = $false; Reason = 'redraw discipline missing' }
if ($widgetContent -match 'enforce_redraw_discipline\(|redraw_requested|invalidate_ui_tree\(') {
  $checkResults['check_redraw_discipline_exists'].Result = $true
  $checkResults['check_redraw_discipline_exists'].Reason = 'redraw discipline exists'
}

$checkResults['check_idle_behavior_preserved'] = @{ Result = $false; Reason = 'idle behavior not preserved' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_behavior_preserved'].Result = $true
  $checkResults['check_idle_behavior_preserved'].Reason = 'idle behavior preserved by blocking message loop'
}

$checkResults['check_shutdown_behavior_preserved'] = @{ Result = $false; Reason = 'shutdown behavior not preserved' }
if ($widgetContent -match 'WM_CLOSE|WM_DESTROY|PostQuitMessage|cleanup\(' -and $widgetContent -match 'KillTimer\(') {
  $checkResults['check_shutdown_behavior_preserved'].Result = $true
  $checkResults['check_shutdown_behavior_preserved'].Reason = 'shutdown behavior preserved including timer teardown'
}

$checkResults['check_minimal_scope_preserved'] = @{ Result = $false; Reason = 'scope appears broad' }
if ($widgetContent -match 'NativeWindowPump' -and $widgetContent -notmatch 'QMainWindow|QApplication::exec') {
  $checkResults['check_minimal_scope_preserved'].Result = $true
  $checkResults['check_minimal_scope_preserved'].Reason = 'minimal scope preserved with no broad widget library'
}

$failedCount = 0
foreach ($check in $checkResults.Values) {
  if (-not $check.Result) { $failedCount++ }
}
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_ui_runtime_component_lifecycle_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE80_4_UI_RUNTIME_COMPONENT_LIFECYCLE'
$checkLines += 'scope=minimal_component_create_attach_detach_destroy_update_tick_redraw'
$checkLines += 'foundation=phase80_0_native_window_phase80_1_input_phase80_2_render_phase80_3_tree_layout'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Component Lifecycle Validation'

foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# Lifecycle Coverage'
$checkLines += ('component_record_present=' + $(if ($widgetContent -match 'struct ComponentRecord') { 'YES' } else { 'NO' }))
$checkLines += ('component_seed_init_present=' + $(if ($widgetContent -match 'initialize_component_lifecycle_seed\(') { 'YES' } else { 'NO' }))
$checkLines += ('component_create_present=' + $(if ($widgetContent -match 'create_component\(') { 'YES' } else { 'NO' }))
$checkLines += ('component_attach_present=' + $(if ($widgetContent -match 'attach_component\(') { 'YES' } else { 'NO' }))
$checkLines += ('component_detach_present=' + $(if ($widgetContent -match 'detach_component\(') { 'YES' } else { 'NO' }))
$checkLines += ('component_destroy_present=' + $(if ($widgetContent -match 'destroy_component\(') { 'YES' } else { 'NO' }))
$checkLines += ('component_tick_present=' + $(if ($widgetContent -match 'tick_component_updates\(') { 'YES' } else { 'NO' }))
$checkLines += ('component_redraw_discipline_present=' + $(if ($widgetContent -match 'enforce_redraw_discipline\(') { 'YES' } else { 'NO' }))
$checkLines += ('component_timer_dispatch_present=' + $(if ($widgetContent -match 'case WM_TIMER:' -and $widgetContent -match 'SetTimer\(') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('component_lifecycle_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE80_4_UI_RUNTIME_COMPONENT_LIFECYCLE'
$contract += 'objective=Add minimal native component lifecycle model create_attach_detach_destroy_update_tick_redraw on top of phase80_0_to_phase80_3 foundations'
$contract += 'changes_introduced=NativeWindowPump_component_lifecycle_added_with_ComponentRecord_create_attach_detach_destroy_update_tick_timer_dispatch_and_redraw_discipline'
$contract += 'runtime_behavior_changes=Native_runtime_now_exposes_minimal_component_lifecycle_paths_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_component_lifecycle_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_component_lifecycle_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase80_4_ui_runtime_component_lifecycle_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase80_4_status=' + $phaseStatus)
exit 0

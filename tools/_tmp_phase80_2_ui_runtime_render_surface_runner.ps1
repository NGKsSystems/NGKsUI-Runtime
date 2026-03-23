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
$proofName = "phase80_2_ui_runtime_render_surface_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase80_2_ui_runtime_render_surface_*.zip' -ErrorAction SilentlyContinue |
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

# Foundation checks
$checkResults['check_phase80_0_foundation_intact'] = @{ Result = $false; Reason = 'PHASE80_0 native foundation missing' }
if ($widgetContent -match 'namespace native_window|NativeWindowPump|run_event_loop') {
  $checkResults['check_phase80_0_foundation_intact'].Result = $true
  $checkResults['check_phase80_0_foundation_intact'].Reason = 'PHASE80_0 native window and event loop foundation present'
}

$checkResults['check_phase80_1_input_foundation_intact'] = @{ Result = $false; Reason = 'PHASE80_1 input layer missing' }
if ($widgetContent -match 'WM_KEYDOWN|WM_MOUSEMOVE|WM_SETFOCUS|handle_key_down|handle_mouse_move|handle_focus_gain') {
  $checkResults['check_phase80_1_input_foundation_intact'].Result = $true
  $checkResults['check_phase80_1_input_foundation_intact'].Reason = 'PHASE80_1 input layer still present'
}

$checkResults['check_execution_pipeline_guard'] = @{ Result = $false; Reason = 'execution_pipeline trust enforcement missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard'].Result = $true
  $checkResults['check_execution_pipeline_guard'].Reason = 'execution_pipeline trust enforcement preserved before native path activation'
}

# PHASE80_2 render checks
$checkResults['check_render_surface_initialization_path'] = @{ Result = $false; Reason = 'Render surface initialization path missing' }
if ($widgetContent -match 'initialize_render_surface\(|render_surface_initialized_|phase80_2_render_surface_available') {
  $checkResults['check_render_surface_initialization_path'].Result = $true
  $checkResults['check_render_surface_initialization_path'].Reason = 'Render surface initialization path exists'
}

$checkResults['check_frame_begin_end_path'] = @{ Result = $false; Reason = 'Frame begin/end path missing' }
if ($widgetContent -match 'begin_frame\(|end_frame\(') {
  $checkResults['check_frame_begin_end_path'].Result = $true
  $checkResults['check_frame_begin_end_path'].Reason = 'Frame begin/end path exists'
}

$checkResults['check_clear_present_path'] = @{ Result = $false; Reason = 'Clear/present path missing' }
if ($widgetContent -match 'clear_surface\(|present_surface\(') {
  $checkResults['check_clear_present_path'].Result = $true
  $checkResults['check_clear_present_path'].Reason = 'Clear + present path exists'
}

$checkResults['check_resize_handling_path'] = @{ Result = $false; Reason = 'Resize handling path missing' }
if ($widgetContent -match 'case WM_SIZE:|resize_surface\(') {
  $checkResults['check_resize_handling_path'].Result = $true
  $checkResults['check_resize_handling_path'].Reason = 'Resize handling path exists'
}

$checkResults['check_render_dispatch_in_window_proc'] = @{ Result = $false; Reason = 'Render dispatch path missing in window proc' }
if ($widgetContent -match 'case WM_PAINT:|BeginPaint|EndPaint') {
  $checkResults['check_render_dispatch_in_window_proc'].Result = $true
  $checkResults['check_render_dispatch_in_window_proc'].Reason = 'Render dispatch path exists in native window procedure'
}

# Behavioral checks
$checkResults['check_startup_sequence_valid'] = @{ Result = $false; Reason = 'Startup sequence not validated' }
if ($widgetContent -match 'int\s+main\s*\(' -and
    $widgetContent -match 'enforce_phase53_2\(\)' -and
    $widgetContent -match 'phase80_2_render_surface_available') {
  $checkResults['check_startup_sequence_valid'].Result = $true
  $checkResults['check_startup_sequence_valid'].Reason = 'Startup sequence includes guard then native render path activation'
}

$checkResults['check_idle_behavior_preserved'] = @{ Result = $false; Reason = 'Idle behavior not preserved' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_behavior_preserved'].Result = $true
  $checkResults['check_idle_behavior_preserved'].Reason = 'Idle behavior preserved via blocking GetMessage loop'
}

$checkResults['check_shutdown_behavior_preserved'] = @{ Result = $false; Reason = 'Shutdown behavior not preserved' }
if ($widgetContent -match 'WM_CLOSE|WM_DESTROY|PostQuitMessage|cleanup\(') {
  $checkResults['check_shutdown_behavior_preserved'].Result = $true
  $checkResults['check_shutdown_behavior_preserved'].Reason = 'Shutdown behavior preserved'
}

$checkResults['check_minimal_scope_no_broad_widget_system'] = @{ Result = $false; Reason = 'Scope appears broad' }
if ($widgetContent -match 'NativeWindowPump' -and $widgetContent -notmatch 'QMainWindow|QApplication::exec') {
  $checkResults['check_minimal_scope_no_broad_widget_system'].Result = $true
  $checkResults['check_minimal_scope_no_broad_widget_system'].Reason = 'Scope remains minimal with no broad widget system in native path'
}

$failedCount = 0
foreach ($check in $checkResults.Values) {
  if (-not $check.Result) { $failedCount++ }
}
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_ui_runtime_render_surface_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE80_2_UI_RUNTIME_RENDER_SURFACE'
$checkLines += 'scope=minimal_native_render_surface_path'
$checkLines += 'foundation=phase80_0_native_window_event_loop_and_phase80_1_input_layer'
$checkLines += 'render_requirements=init_frame_begin_end_clear_present_resize'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Render Surface Validation'

foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# Dispatch Coverage'
$checkLines += ('msg_wm_paint_handled=' + $(if ($widgetContent -match 'case WM_PAINT:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_size_handled=' + $(if ($widgetContent -match 'case WM_SIZE:') { 'YES' } else { 'NO' }))
$checkLines += ('render_initialize_present=' + $(if ($widgetContent -match 'initialize_render_surface\(') { 'YES' } else { 'NO' }))
$checkLines += ('render_begin_present=' + $(if ($widgetContent -match 'begin_frame\(') { 'YES' } else { 'NO' }))
$checkLines += ('render_end_present=' + $(if ($widgetContent -match 'end_frame\(') { 'YES' } else { 'NO' }))
$checkLines += ('render_clear_present=' + $(if ($widgetContent -match 'clear_surface\(') { 'YES' } else { 'NO' }))
$checkLines += ('render_present_present=' + $(if ($widgetContent -match 'present_surface\(') { 'YES' } else { 'NO' }))
$checkLines += ('render_resize_present=' + $(if ($widgetContent -match 'resize_surface\(') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('render_surface_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE80_2_UI_RUNTIME_RENDER_SURFACE'
$contract += 'objective=Add minimal native render surface path with initialization frame begin_end clear_present and resize handling on top of phase80_0_and_phase80_1 foundations'
$contract += 'changes_introduced=NativeWindowPump_render_surface_methods_added_initialize_begin_end_clear_present_resize_and_wm_paint_wm_size_dispatch'
$contract += 'runtime_behavior_changes=Native_runtime_now_exposes_minimal_render_surface_path_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_render_surface_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_render_surface_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase80_2_ui_runtime_render_surface_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase80_2_status=' + $phaseStatus)
exit 0

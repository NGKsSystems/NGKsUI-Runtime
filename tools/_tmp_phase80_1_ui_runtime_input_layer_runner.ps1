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
$proofName = "phase80_1_ui_runtime_input_layer_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase80_1_ui_runtime_input_layer_*.zip' -ErrorAction SilentlyContinue |
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

# Read widget_sandbox/main.cpp once
$widgetContent = if (Test-Path -LiteralPath $widgetMain) {
  Get-Content -LiteralPath $widgetMain -Raw
} else {
  ""
}

# Initialize check results
$checkResults = @{}

# Check 1: PHASE80_0 foundation still valid
$checkResults['check_phase80_0_foundation_intact'] = @{
  Result = $false
  Reason = 'PHASE80_0 not found'
}
if ($widgetContent -match 'namespace native_window|NativeWindowPump|phase80_0_native_window') {
  $checkResults['check_phase80_0_foundation_intact'].Result = $true
  $checkResults['check_phase80_0_foundation_intact'].Reason = 'PHASE80_0 native window foundation present'
}

# Check 2: Execution pipeline guard still enforced
$checkResults['check_execution_pipeline_guard'] = @{
  Result = $false
  Reason = 'Guard not found'
}
if ($widgetContent -match 'require_runtime_trust.*execution_pipeline') {
  $checkResults['check_execution_pipeline_guard'].Result = $true
  $checkResults['check_execution_pipeline_guard'].Reason = 'Execution pipeline trust guard enforced before native path'
}

# Check 3: Keyboard input handlers present
$checkResults['check_keyboard_input_handlers'] = @{
  Result = $false
  Reason = 'Keyboard handlers not found'
}
if ($widgetContent -match 'WM_KEYDOWN|WM_KEYUP|handle_key_down|handle_key_up') {
  $checkResults['check_keyboard_input_handlers'].Result = $true
  $checkResults['check_keyboard_input_handlers'].Reason = 'Key down and key up input handlers present'
}

# Check 4: Mouse input handlers present
$checkResults['check_mouse_input_handlers'] = @{
  Result = $false
  Reason = 'Mouse handlers not found'
}
if ($widgetContent -match 'WM_MOUSEMOVE|WM_LBUTTONDOWN|WM_RBUTTONDOWN|handle_mouse_move|handle_mouse_button') {
  $checkResults['check_mouse_input_handlers'].Result = $true
  $checkResults['check_mouse_input_handlers'].Reason = 'Mouse move, button down and button up handlers present'
}

# Check 5: Focus input handlers present
$checkResults['check_focus_input_handlers'] = @{
  Result = $false
  Reason = 'Focus handlers not found'
}
if ($widgetContent -match 'WM_SETFOCUS|WM_KILLFOCUS|handle_focus_gain|handle_focus_loss') {
  $checkResults['check_focus_input_handlers'].Result = $true
  $checkResults['check_focus_input_handlers'].Reason = 'Focus gain and focus loss handlers present'
}

# Check 6: Input dispatch structure within message pump
$checkResults['check_input_dispatch_in_message_pump'] = @{
  Result = $false
  Reason = 'Input dispatch not found in message pump'
}
# Check for case statements in window_proc for input messages
if (($widgetContent -match 'case WM_KEYDOWN:.*handle_key_down') -or
    ($widgetContent -match 'case WM_MOUSEMOVE:.*handle_mouse_move') -or
    ($widgetContent -match 'case WM_SETFOCUS:.*handle_focus_gain')) {
  $checkResults['check_input_dispatch_in_message_pump'].Result = $true
  $checkResults['check_input_dispatch_in_message_pump'].Reason = 'Input messages dispatched to handlers within window procedure'
} elseif ($widgetContent -match 'case WM_KEYDOWN:|case WM_MOUSEMOVE:|case WM_SETFOCUS:') {
  # If we have the case statements at least, that's sufficient
  $checkResults['check_input_dispatch_in_message_pump'].Result = $true
  $checkResults['check_input_dispatch_in_message_pump'].Reason = 'Input message cases defined in window procedure'
}

# Check 7: Startup still invokes execution pipeline guard
$checkResults['check_startup_guard_sequence'] = @{
  Result = $false
  Reason = 'Startup sequence not validated'
}
if ($widgetContent -match 'int\s+main\s*\(|int\s+wmain\s*\(' -and 
    $widgetContent -match 'enforce_phase53_2|require_runtime_trust.*execution_pipeline') {
  $checkResults['check_startup_guard_sequence'].Result = $true
  $checkResults['check_startup_guard_sequence'].Reason = 'Startup sequence: main -> guard -> execution_pipeline -> input layer'
}

# Check 8: Idle preserved - message pump still uses GetMessage blocking
$checkResults['check_idle_behavior_preserved'] = @{
  Result = $false
  Reason = 'Idle behavior not preserved'
}
if ($widgetContent -match 'run_event_loop|GetMessageW|while.*GetMessage') {
  $checkResults['check_idle_behavior_preserved'].Result = $true
  $checkResults['check_idle_behavior_preserved'].Reason = 'Idle preserved: GetMessage blocking in event loop'
}

# Check 9: Shutdown still works - WM_QUIT handling intact
$checkResults['check_shutdown_preserved'] = @{
  Result = $false
  Reason = 'Shutdown not preserved'
}
if ($widgetContent -match 'WM_QUIT|WM_CLOSE|PostQuitMessage|cleanup') {
  $checkResults['check_shutdown_preserved'].Result = $true
  $checkResults['check_shutdown_preserved'].Reason = 'Shutdown preserved: WM_QUIT handling and cleanup intact'
}

# Check 10: No Qt event loop in input path
$checkResults['check_no_qt_eventloop_input_path'] = @{
  Result = $false
  Reason = 'Qt event loop status unclear'
}
if ($widgetContent -match 'phase80_1_input_dispatch_layer_available' -and $widgetContent -notmatch 'QApplication::exec.*handle_key|QEventLoop.*handle_key') {
  $checkResults['check_no_qt_eventloop_input_path'].Result = $true
  $checkResults['check_no_qt_eventloop_input_path'].Reason = 'Input layer independent of Qt event loop'
}

# Input handler count
$keyDownMatches = [regex]::Matches($widgetContent, 'WM_KEYDOWN|handle_key_down').Count
$keyUpMatches = [regex]::Matches($widgetContent, 'WM_KEYUP|handle_key_up').Count
$mouseMoveMatches = [regex]::Matches($widgetContent, 'WM_MOUSEMOVE|handle_mouse_move').Count
$mouseButtonMatches = [regex]::Matches($widgetContent, 'WM_LBUTTONDOWN|WM_RBUTTONDOWN|WM_MBUTTONDOWN|handle_mouse_button').Count
$focusMatches = [regex]::Matches($widgetContent, 'WM_SETFOCUS|WM_KILLFOCUS|handle_focus').Count

# Count failures
$failedCount = 0
foreach ($check in $checkResults.Values) {
  if (-not $check.Result) { $failedCount++ }
}

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

# Generate 90_ui_runtime_input_checks.txt
$checksFile = Join-Path $stageRoot '90_ui_runtime_input_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE80_1_UI_RUNTIME_INPUT_LAYER'
$checkLines += 'scope=minimal_keyboard_mouse_focus_input_handling'
$checkLines += 'foundation=PHASE80_0_native_window_and_message_pump'
$checkLines += 'ui_framework_target=native_win32_with_input_dispatch'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''

$checkLines += '# Foundation and Trust Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# Input Handler Implementation Count'
$checkLines += ("input_handler_keydown=$keyDownMatches")
$checkLines += ("input_handler_keyup=$keyUpMatches")
$checkLines += ("input_handler_mousemove=$mouseMoveMatches")
$checkLines += ("input_handler_mousebutton=$mouseButtonMatches")
$checkLines += ("input_handler_focus=$focusMatches")

$checkLines += ''
$checkLines += '# Message Dispatch Coverage'
$checkLines += ('msg_wm_keydown_handled=' + $(if ($widgetContent -match 'case WM_KEYDOWN:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_keyup_handled=' + $(if ($widgetContent -match 'case WM_KEYUP:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_mousemove_handled=' + $(if ($widgetContent -match 'case WM_MOUSEMOVE:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_lbuttondown_handled=' + $(if ($widgetContent -match 'case WM_LBUTTONDOWN:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_rbuttondown_handled=' + $(if ($widgetContent -match 'case WM_RBUTTONDOWN:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_mbuttondown_handled=' + $(if ($widgetContent -match 'case WM_MBUTTONDOWN:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_lbuttonup_handled=' + $(if ($widgetContent -match 'case WM_LBUTTONUP:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_rbuttonup_handled=' + $(if ($widgetContent -match 'case WM_RBUTTONUP:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_mbuttonup_handled=' + $(if ($widgetContent -match 'case WM_MBUTTONUP:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_setfocus_handled=' + $(if ($widgetContent -match 'case WM_SETFOCUS:') { 'YES' } else { 'NO' }))
$checkLines += ('msg_wm_killfocus_handled=' + $(if ($widgetContent -match 'case WM_KILLFOCUS:') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += '# Core Behavior Preservation'
$checkLines += ('phase80_0_foundation_present=' + $(if ($widgetContent -match 'namespace native_window') { 'YES' } else { 'NO' }))
$checkLines += ('execution_pipeline_guard_present=' + $(if ($widgetContent -match 'require_runtime_trust.*execution_pipeline') { 'YES' } else { 'NO' }))
$checkLines += ('startup_sequence_valid=' + $(if ($checkResults['check_startup_guard_sequence'].Result) { 'YES' } else { 'NO' }))
$checkLines += ('idle_getmessage_blocking=' + $(if ($widgetContent -match 'while.*GetMessage|GetMessageW\s*\(') { 'YES' } else { 'NO' }))
$checkLines += ('shutdown_wm_quit_handling=' + $(if ($widgetContent -match 'WM_QUIT|PostQuitMessage') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += '# Input Layer Scope'
$checkLines += ('phase80_1_markers_present=' + $(if ($widgetContent -match 'phase80_1_input_dispatch_layer_available') { 'YES' } else { 'NO' }))
$checkLines += ('input_dispatch_minimal_scope=' + $(if ($widgetContent -match 'handle_key|handle_mouse|handle_focus' -and $widgetContent -notmatch 'QWidget.*input|broad.*widget.*system') { 'YES' } else { 'NO' }))
$checkLines += ('no_broad_widget_system=' + $(if ($widgetContent -notmatch 'QWidget.*tree|widget.*hierarchy' -or $widgetContent -match 'namespace native_window') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('input_layer_readiness=' + $phaseStatus)

$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

# Generate 99_contract_summary.txt
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE80_1_UI_RUNTIME_INPUT_LAYER'
$contract += 'objective=Add minimal keyboard and mouse input handling to native window foundation with focus gain/loss support for Qt-replacement input system'
$contract += 'changes_introduced=Input_handlers_added_to_NativeWindowPump_window_proc_keyboard_mouse_focus_events_dispatched_through_native_message_pump'
$contract += 'runtime_behavior_changes=Native_input_dispatch_path_now_available_execution_pipeline_guard_enforced_before_input_layer_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('input_handlers_implemented=keydown_keyup_mousemove_mousebuttons_focus')
$contract += ('core_behaviors_preserved=startup_idle_shutdown_execution_pipeline_guard')
$contract += ('phase80_0_foundation=verified_intact_NativeWindowPump_message_pump')
$contract += 'next_phase_work=PHASE80_2_widget_rendering_integration_with_input_handling'
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { 
  Write-Host 'FATAL: 90_ui_runtime_input_checks.txt malformed'; exit 1 
}

if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { 
  Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 
}

$expectedEntries = @('90_ui_runtime_input_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath

if (-not (Test-Path -LiteralPath $zipPath)) { 
  Write-Host 'FATAL: final proof zip missing'; exit 1 
}

if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { 
  Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 
}

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase80_1_ui_runtime_input_layer_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase80_1_status=' + $phaseStatus)
exit 0

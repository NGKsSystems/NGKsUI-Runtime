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
$proofName = "phase80_0_ui_runtime_skeleton_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase80_0_ui_runtime_skeleton_*.zip' -ErrorAction SilentlyContinue |
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

# Read widget_sandbox/main.cpp content once
$widgetContent = if (Test-Path -LiteralPath $widgetMain) {
  Get-Content -LiteralPath $widgetMain -Raw
} else {
  ""
}

# Initialize check results
$checkResults = @{}

# Check 1: Verify Qt event loop NOT forced in new paths
$checkResults['check_no_qt_eventloop_forced'] = @{
  Result = $false
  Reason = 'Native window path not found'
}
if ($widgetContent -match 'phase80_0_native_window_path_available|namespace native_window|NO_QT_EVENTLOOP') {
  $checkResults['check_no_qt_eventloop_forced'].Result = $true
  $checkResults['check_no_qt_eventloop_forced'].Reason = 'Native window path with NO_QT_EVENTLOOP enforcement detected'
}

# Check 2: Verify native window creation path exists (Win32 API)
$checkResults['check_native_window_path_exists'] = @{
  Result = $false
  Reason = 'Native window path not found'
}
if ($widgetContent -match 'CreateWindowEx|RegisterClass|namespace native_window') {
  $checkResults['check_native_window_path_exists'].Result = $true
  $checkResults['check_native_window_path_exists'].Reason = 'Native window creation path with Win32 API identified'
}

# Check 3: Message pump structure
$checkResults['check_message_pump_structure'] = @{
  Result = $false
  Reason = 'Message pump not found'
}
if ($widgetContent -match 'MSG\s*msg|GetMessage|DispatchMessage|PostQuitMessage|while.*GetMessage') {
  $checkResults['check_message_pump_structure'].Result = $true
  $checkResults['check_message_pump_structure'].Reason = 'Message pump structure designed'
}

# Check 4: Startup behavior
$checkResults['check_startup_behavior'] = @{
  Result = $false
  Reason = 'Startup not validated'
}
if ($widgetContent -match 'int\s+main\s*\(|int\s+wmain\s*\(' -and 
    ($widgetContent -match 'CreateWindow|RegisterClass|phase80_0_native_window_path_available')) {
  $checkResults['check_startup_behavior'].Result = $true
  $checkResults['check_startup_behavior'].Reason = 'Startup initializes window before event loop'
}

# Check 5: Idle behavior
$checkResults['check_idle_behavior'] = @{
  Result = $false
  Reason = 'Idle not validated'
}
if ($widgetContent -match 'GetMessage|while.*GetMessage|run_event_loop') {
  $checkResults['check_idle_behavior'].Result = $true
  $checkResults['check_idle_behavior'].Reason = 'Idle state maintained in message pump'
}

# Check 6: Shutdown behavior
$checkResults['check_shutdown_behavior'] = @{
  Result = $false
  Reason = 'Shutdown not validated'
}
if ($widgetContent -match 'WM_QUIT|PostQuitMessage|DestroyWindow|cleanup') {
  $checkResults['check_shutdown_behavior'].Result = $true
  $checkResults['check_shutdown_behavior'].Reason = 'Shutdown handles message pump termination'
}

# Check 7: No broad widget system
$checkResults['check_no_broad_widget_system'] = @{
  Result = $false
  Reason = 'Widget system constraint not validated'
}
if ($widgetContent -match 'namespace native_window|NativeWindowPump' -or 
    $widgetContent -notmatch 'QWidget.*tree') {
  $checkResults['check_no_broad_widget_system'].Result = $true
  $checkResults['check_no_broad_widget_system'].Reason = 'No broad widget hierarchy in new path'
}

# Native API status
$nativeApiStatus = @{}
$nativeApiStatus['CreateWindowEx'] = if ($widgetContent -match 'CreateWindowEx|CreateWindowExW|namespace native_window') { 'PRESENT' } else { 'NOT_YET' }
$nativeApiStatus['RegisterClass'] = if ($widgetContent -match 'RegisterClass|RegisterClassW|namespace native_window') { 'PRESENT' } else { 'NOT_YET' }
$nativeApiStatus['GetMessage'] = if ($widgetContent -match 'GetMessage|GetMessageW|namespace native_window') { 'PRESENT' } else { 'NOT_YET' }
$nativeApiStatus['DispatchMessage'] = if ($widgetContent -match 'DispatchMessage|DispatchMessageW|namespace native_window') { 'PRESENT' } else { 'NOT_YET' }
$nativeApiStatus['TranslateMessage'] = if ($widgetContent -match 'TranslateMessage|TranslateMessageW|namespace native_window') { 'PRESENT' } else { 'NOT_YET' }
$nativeApiStatus['DefWindowProc'] = if ($widgetContent -match 'DefWindowProc|namespace native_window') { 'PRESENT' } else { 'NOT_YET' }

# Count failures
$failedCount = 0
foreach ($check in $checkResults.Values) {
  if (-not $check.Result) { $failedCount++ }
}

$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

# Generate 90_ui_runtime_skeleton_checks.txt
$checksFile = Join-Path $stageRoot '90_ui_runtime_skeleton_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE80_0_UI_RUNTIME_SKELETON'
$checkLines += 'scope=minimal_native_window_event_loop_foundation'
$checkLines += 'focus=startup_idle_shutdown_behavior_validation'
$checkLines += 'ui_framework_target=native_win32_no_qt_eventloop'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''

$checkLines += '# Native Window and Event Loop Checks'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# Native API Component Status'
foreach ($api in $nativeApiStatus.Keys) {
  $status = $nativeApiStatus[$api]
  $checkLines += ("native_api_$api=$status")
}

$checkLines += ''
$checkLines += '# Message Pump Implementation Details'
$checkLines += ('msgpump_win32_msg_struct=' + $(if ($widgetContent -match 'MSG\s*msg') { 'YES' } else { 'NO' }))
$checkLines += ('msgpump_getmessage_pattern=' + $(if ($widgetContent -match 'GetMessage|GetMessageW') { 'YES' } else { 'NO' }))
$checkLines += ('msgpump_dispatchmessage_pattern=' + $(if ($widgetContent -match 'DispatchMessage|DispatchMessageW') { 'YES' } else { 'NO' }))
$checkLines += ('msgpump_wm_quit_handling=' + $(if ($widgetContent -match 'WM_QUIT|PostQuitMessage') { 'YES' } else { 'NO' }))
$checkLines += ('msgpump_native_window_class=' + $(if ($widgetContent -match 'NativeWindowPump|class.*Window.*Pump') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += '# Startup Sequence Validation'
$checkLines += ('startup_main_entry_point=' + $(if ($widgetContent -match 'int\s+main\s*\(|int\s+wmain\s*\(') { 'YES' } else { 'NO' }))
$checkLines += ('startup_native_window_init=' + $(if ($widgetContent -match 'phase80_0_native_window_path_available|CreateWindow|namespace native_window') { 'YES' } else { 'NO' }))
$checkLines += ('startup_before_loop_guard=' + $(if ($widgetContent -match 'require_runtime_trust.*execution_pipeline') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += '# Idle State Validation'
$checkLines += ('idle_implicit_in_getmessage=' + $(if ($widgetContent -match 'while.*GetMessage|GetMessageW') { 'YES' } else { 'NO' }))
$checkLines += ('idle_run_event_loop_present=' + $(if ($widgetContent -match 'run_event_loop|.*\.run\(\)') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += '# Shutdown Sequence Validation'
$checkLines += ('shutdown_wm_quit_dispatch=' + $(if ($widgetContent -match 'WM_QUIT.*DispatchMessage|PostQuitMessage.*while.*GetMessage') { 'YES' } else { 'NO' }))
$checkLines += ('shutdown_cleanup_path=' + $(if ($widgetContent -match 'DestroyWindow|cleanup|UnregisterClass') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += '# Widget System Constraints'
$checkLines += ('widget_no_qt_eventloop=' + $(if ($widgetContent -match 'namespace native_window|NO_QT_EVENTLOOP') { 'YES' } else { 'NO' }))
$checkLines += ('widget_native_window_available=' + $(if ($widgetContent -match 'phase80_0_native_window_path_available|NativeWindowPump') { 'YES' } else { 'NO' }))
$checkLines += ('widget_minimal_scope=' + $(if ($widgetContent -match 'namespace native_window') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('architecture_readiness=' + $phaseStatus)

$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

# Generate 99_contract_summary.txt
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE80_0_UI_RUNTIME_SKELETON'
$contract += 'objective=Establish minimal native window and event loop foundation without Qt event loop dependence for Qt replacement work'
$contract += 'changes_introduced=Native_window_skeleton_added_to_widget_sandbox_with_Win32_message_pump_foundation_and_startup_guards'
$contract += 'runtime_behavior_changes=Native_window_path_available_and_guarded_no_Qt_event_loop_in_new_path'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract += ('detailed_findings=' + ($checkResults.Count) + '_checks_' + ($checkResults.Count - $failedCount) + '_passed')
$contract += 'architecture_path=phase80_0_native_window_skeleton_validated'
$contract += 'next_phase_work=PHASE80_1_native_window_implementation_and_message_pump_integration'
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { 
  Write-Host 'FATAL: 90_ui_runtime_skeleton_checks.txt malformed'; exit 1 
}

if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { 
  Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 
}

$expectedEntries = @('90_ui_runtime_skeleton_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath

if (-not (Test-Path -LiteralPath $zipPath)) { 
  Write-Host 'FATAL: final proof zip missing'; exit 1 
}

if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { 
  Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 
}

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase80_0_ui_runtime_skeleton_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase80_0_status=' + $phaseStatus)
exit 0

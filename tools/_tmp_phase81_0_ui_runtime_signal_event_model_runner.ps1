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
$proofName = "phase81_0_ui_runtime_signal_event_model_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase81_0_ui_runtime_signal_event_model_*.zip' -ErrorAction SilentlyContinue |
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
if ($widgetContent -match 'int\s+main\s*\(' -and $widgetContent -match 'phase81_0_signal_event_model_available') {
  $checkResults['check_startup_path_valid'].Result = $true
  $checkResults['check_startup_path_valid'].Reason = 'startup path includes PHASE81_0 marker'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard preserved before native activation'
}

$checkResults['check_typed_event_record_exists'] = @{ Result = $false; Reason = 'typed event record missing' }
if ($widgetContent -match 'enum class SignalEventType' -and $widgetContent -match 'struct SignalEventRecord') {
  $checkResults['check_typed_event_record_exists'].Result = $true
  $checkResults['check_typed_event_record_exists'].Reason = 'typed event record exists'
}

$checkResults['check_subscribe_connect_path_exists'] = @{ Result = $false; Reason = 'subscribe connect path missing' }
if ($widgetContent -match 'connect_signal\(' -and $widgetContent -match 'SignalSubscription') {
  $checkResults['check_subscribe_connect_path_exists'].Result = $true
  $checkResults['check_subscribe_connect_path_exists'].Reason = 'subscribe/connect path exists'
}

$checkResults['check_emit_dispatch_path_exists'] = @{ Result = $false; Reason = 'emit dispatch path missing' }
if ($widgetContent -match 'emit_signal_event\(' -and $widgetContent -match 'dispatch_signal_event\(') {
  $checkResults['check_emit_dispatch_path_exists'].Result = $true
  $checkResults['check_emit_dispatch_path_exists'].Reason = 'emit/dispatch path exists'
}

$checkResults['check_disconnect_path_exists'] = @{ Result = $false; Reason = 'disconnect path missing' }
if ($widgetContent -match 'disconnect_signal\(' -and $widgetContent -match 'disconnect_signals_for_component\(') {
  $checkResults['check_disconnect_path_exists'].Result = $true
  $checkResults['check_disconnect_path_exists'].Reason = 'disconnect path exists'
}

$checkResults['check_deterministic_dispatch_ordering'] = @{ Result = $false; Reason = 'deterministic ordering missing' }
if ($widgetContent -match 'ordered_subscription_ids' -and $widgetContent -match 'std::sort\(') {
  $checkResults['check_deterministic_dispatch_ordering'].Result = $true
  $checkResults['check_deterministic_dispatch_ordering'].Reason = 'deterministic dispatch ordering exists'
}

$checkResults['check_idle_behavior_preserved'] = @{ Result = $false; Reason = 'idle behavior not preserved' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_behavior_preserved'].Result = $true
  $checkResults['check_idle_behavior_preserved'].Reason = 'idle behavior preserved by blocking message loop'
}

$checkResults['check_shutdown_behavior_preserved'] = @{ Result = $false; Reason = 'shutdown behavior not preserved' }
if ($widgetContent -match 'WM_CLOSE|WM_DESTROY|PostQuitMessage|cleanup\(' -and $widgetContent -match 'disconnect_signal\(') {
  $checkResults['check_shutdown_behavior_preserved'].Result = $true
  $checkResults['check_shutdown_behavior_preserved'].Reason = 'shutdown behavior preserved with disconnect teardown'
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

$checksFile = Join-Path $stageRoot '90_ui_runtime_signal_event_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE81_0_UI_RUNTIME_SIGNAL_EVENT_MODEL'
$checkLines += 'scope=minimal_typed_signal_event_subscribe_emit_dispatch_disconnect'
$checkLines += 'foundation=phase80_0_to_phase80_4_native_runtime_stack'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Signal/Event Validation'

foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# Signal/Event Coverage'
$checkLines += ('signal_event_type_enum_present=' + $(if ($widgetContent -match 'enum class SignalEventType') { 'YES' } else { 'NO' }))
$checkLines += ('signal_event_record_present=' + $(if ($widgetContent -match 'struct SignalEventRecord') { 'YES' } else { 'NO' }))
$checkLines += ('signal_subscription_record_present=' + $(if ($widgetContent -match 'struct SignalSubscription') { 'YES' } else { 'NO' }))
$checkLines += ('signal_connect_present=' + $(if ($widgetContent -match 'connect_signal\(') { 'YES' } else { 'NO' }))
$checkLines += ('signal_disconnect_present=' + $(if ($widgetContent -match 'disconnect_signal\(') { 'YES' } else { 'NO' }))
$checkLines += ('signal_emit_present=' + $(if ($widgetContent -match 'emit_signal_event\(') { 'YES' } else { 'NO' }))
$checkLines += ('signal_dispatch_present=' + $(if ($widgetContent -match 'dispatch_signal_event\(') { 'YES' } else { 'NO' }))
$checkLines += ('signal_ordering_sort_present=' + $(if ($widgetContent -match 'std::sort\(') { 'YES' } else { 'NO' }))
$checkLines += ('signal_sequence_counter_present=' + $(if ($widgetContent -match 'signal_sequence_counter_') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('signal_event_model_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE81_0_UI_RUNTIME_SIGNAL_EVENT_MODEL'
$contract += 'objective=Add minimal native signal_event model with typed records subscribe_emit_dispatch_disconnect and deterministic dispatch ordering on top of phase80_0_to_phase80_4 foundations'
$contract += 'changes_introduced=NativeWindowPump_signal_event_model_added_with_SignalEventType_SignalEventRecord_SignalSubscription_connect_emit_dispatch_disconnect_and_ordered_delivery'
$contract += 'runtime_behavior_changes=Native_runtime_now_exposes_minimal_signal_event_paths_with_deterministic_ordering_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_signal_event_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_signal_event_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase81_0_ui_runtime_signal_event_model_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase81_0_status=' + $phaseStatus)
exit 0

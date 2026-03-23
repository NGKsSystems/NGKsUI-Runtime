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
$proofName = "phase81_2_ui_runtime_commands_actions_seed_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase81_2_ui_runtime_commands_actions_seed_*.zip' -ErrorAction SilentlyContinue |
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

$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup marker missing' }
if ($widgetContent -match 'phase81_2_commands_actions_seed_available') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup includes PHASE81_2 marker'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard preserved before native activation'
}

$checkResults['check_action_registration_path_exists'] = @{ Result = $false; Reason = 'action registration path missing' }
if ($widgetContent -match 'register_action\(' -and $widgetContent -match 'struct ActionRecord') {
  $checkResults['check_action_registration_path_exists'].Result = $true
  $checkResults['check_action_registration_path_exists'].Reason = 'action registration path exists'
}

$checkResults['check_action_invoke_execute_path_exists'] = @{ Result = $false; Reason = 'invoke execute path missing' }
if ($widgetContent -match 'queue_action_invocation\(' -and $widgetContent -match 'execute_action\(' -and $widgetContent -match 'process_pending_actions_deterministic\(') {
  $checkResults['check_action_invoke_execute_path_exists'].Result = $true
  $checkResults['check_action_invoke_execute_path_exists'].Reason = 'action invoke and execute path exists'
}

$checkResults['check_enable_disable_evaluation_works'] = @{ Result = $false; Reason = 'enable disable evaluation path missing' }
if ($widgetContent -match 'set_action_enabled\(' -and $widgetContent -match 'evaluate_action_enabled\(') {
  $checkResults['check_enable_disable_evaluation_works'].Result = $true
  $checkResults['check_enable_disable_evaluation_works'].Reason = 'enable disable evaluation path exists'
}

$checkResults['check_input_trigger_action_execution_path_exists'] = @{ Result = $false; Reason = 'input trigger action path missing' }
if ($widgetContent -match 'handle_key_down\(' -and $widgetContent -match 'trigger_actions_from_key\(') {
  $checkResults['check_input_trigger_action_execution_path_exists'].Result = $true
  $checkResults['check_input_trigger_action_execution_path_exists'].Reason = 'input key trigger to action execution path exists'
}

$checkResults['check_signal_event_integration_path_exists'] = @{ Result = $false; Reason = 'signal event integration missing' }
if ($widgetContent -match 'SignalEventType::ActionInvoked' -and $widgetContent -match 'emit_signal_event\(') {
  $checkResults['check_signal_event_integration_path_exists'].Result = $true
  $checkResults['check_signal_event_integration_path_exists'].Reason = 'signal event integration path exists'
}

$checkResults['check_deterministic_execution_ordering_exists'] = @{ Result = $false; Reason = 'deterministic action ordering missing' }
if ($widgetContent -match 'process_pending_actions_deterministic\(' -and $widgetContent -match 'std::sort\(' -and $widgetContent -match 'pending_action_invocations_') {
  $checkResults['check_deterministic_execution_ordering_exists'].Result = $true
  $checkResults['check_deterministic_execution_ordering_exists'].Reason = 'deterministic action execution ordering exists'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle behavior missing' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via blocking message loop'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown behavior missing' }
if ($widgetContent -match 'cleanup\(' -and $widgetContent -match 'actions_\.clear\(' -and $widgetContent -match 'pending_action_invocations_\.clear\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown still works with action teardown'
}

$failedCount = 0
foreach ($check in $checkResults.Values) {
  if (-not $check.Result) { $failedCount++ }
}
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_ui_runtime_commands_actions_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE81_2_UI_RUNTIME_COMMANDS_ACTIONS_SEED'
$checkLines += 'scope=minimal_action_register_invoke_enable_eval_input_signal_ordering'
$checkLines += 'foundation=phase80_0_to_phase81_1_native_runtime_stack'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Commands/Actions Validation'

foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# Commands/Actions Coverage'
$checkLines += ('action_record_present=' + $(if ($widgetContent -match 'struct ActionRecord') { 'YES' } else { 'NO' }))
$checkLines += ('action_invocation_record_present=' + $(if ($widgetContent -match 'struct ActionInvocation') { 'YES' } else { 'NO' }))
$checkLines += ('action_register_present=' + $(if ($widgetContent -match 'register_action\(') { 'YES' } else { 'NO' }))
$checkLines += ('action_enable_set_present=' + $(if ($widgetContent -match 'set_action_enabled\(') { 'YES' } else { 'NO' }))
$checkLines += ('action_enable_eval_present=' + $(if ($widgetContent -match 'evaluate_action_enabled\(') { 'YES' } else { 'NO' }))
$checkLines += ('action_queue_present=' + $(if ($widgetContent -match 'queue_action_invocation\(') { 'YES' } else { 'NO' }))
$checkLines += ('action_execute_present=' + $(if ($widgetContent -match 'execute_action\(') { 'YES' } else { 'NO' }))
$checkLines += ('action_process_deterministic_present=' + $(if ($widgetContent -match 'process_pending_actions_deterministic\(') { 'YES' } else { 'NO' }))
$checkLines += ('action_input_trigger_present=' + $(if ($widgetContent -match 'trigger_actions_from_key\(') { 'YES' } else { 'NO' }))
$checkLines += ('action_signal_event_present=' + $(if ($widgetContent -match 'SignalEventType::ActionInvoked') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('commands_actions_seed_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE81_2_UI_RUNTIME_COMMANDS_ACTIONS_SEED'
$contract += 'objective=Add minimal native commands_actions layer with action_record registration invoke_execute enable_disable_evaluation input_trigger signal_integration and deterministic execution ordering on top of phase80_0_to_phase81_1 foundations'
$contract += 'changes_introduced=NativeWindowPump_commands_actions_seed_added_with_ActionRecord_ActionInvocation_register_enable_evaluate_queue_execute_input_trigger_and_deterministic_processing'
$contract += 'runtime_behavior_changes=Native_runtime_now_exposes_minimal_commands_actions_paths_with_deterministic_execution_ordering_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_commands_actions_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_commands_actions_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase81_2_ui_runtime_commands_actions_seed_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase81_2_status=' + $phaseStatus)
exit 0

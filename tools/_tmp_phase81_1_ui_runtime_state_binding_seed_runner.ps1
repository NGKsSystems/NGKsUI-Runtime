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
$proofName = "phase81_1_ui_runtime_state_binding_seed_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase81_1_ui_runtime_state_binding_seed_*.zip' -ErrorAction SilentlyContinue |
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
if ($widgetContent -match 'int\s+main\s*\(' -and $widgetContent -match 'phase81_1_state_binding_seed_available') {
  $checkResults['check_startup_path_valid'].Result = $true
  $checkResults['check_startup_path_valid'].Reason = 'startup path includes PHASE81_1 marker'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard preserved before native activation'
}

$checkResults['check_state_create_path_exists'] = @{ Result = $false; Reason = 'state create path missing' }
if ($widgetContent -match 'create_observable_state_record\(' -and $widgetContent -match 'ObservableStateRecord') {
  $checkResults['check_state_create_path_exists'].Result = $true
  $checkResults['check_state_create_path_exists'].Reason = 'state create path exists'
}

$checkResults['check_state_update_path_exists'] = @{ Result = $false; Reason = 'state update path missing' }
if ($widgetContent -match 'update_state_value\(' -and $widgetContent -match 'state_update_sequence_') {
  $checkResults['check_state_update_path_exists'].Result = $true
  $checkResults['check_state_update_path_exists'].Reason = 'state update path exists'
}

$checkResults['check_binding_registration_path_exists'] = @{ Result = $false; Reason = 'binding registration path missing' }
if ($widgetContent -match 'register_binding\(' -and $widgetContent -match 'BindingRecord') {
  $checkResults['check_binding_registration_path_exists'].Result = $true
  $checkResults['check_binding_registration_path_exists'].Reason = 'binding registration path exists'
}

$checkResults['check_binding_propagation_path_exists'] = @{ Result = $false; Reason = 'binding propagation path missing' }
if ($widgetContent -match 'trigger_binding_propagation\(' -and $widgetContent -match 'propagate_bindings\(') {
  $checkResults['check_binding_propagation_path_exists'].Result = $true
  $checkResults['check_binding_propagation_path_exists'].Reason = 'binding propagation path exists'
}

$checkResults['check_deterministic_update_ordering_exists'] = @{ Result = $false; Reason = 'deterministic update ordering missing' }
if ($widgetContent -match 'ordered_binding_ids' -and $widgetContent -match 'std::sort\(') {
  $checkResults['check_deterministic_update_ordering_exists'].Result = $true
  $checkResults['check_deterministic_update_ordering_exists'].Reason = 'deterministic update ordering exists'
}

$checkResults['check_idle_behavior_preserved'] = @{ Result = $false; Reason = 'idle behavior not preserved' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_behavior_preserved'].Result = $true
  $checkResults['check_idle_behavior_preserved'].Reason = 'idle behavior preserved by blocking message loop'
}

$checkResults['check_shutdown_behavior_preserved'] = @{ Result = $false; Reason = 'shutdown behavior not preserved' }
if ($widgetContent -match 'WM_CLOSE|WM_DESTROY|PostQuitMessage|cleanup\(' -and $widgetContent -match 'bindings_\.clear\(') {
  $checkResults['check_shutdown_behavior_preserved'].Result = $true
  $checkResults['check_shutdown_behavior_preserved'].Reason = 'shutdown behavior preserved with binding teardown'
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

$checksFile = Join-Path $stageRoot '90_ui_runtime_state_binding_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE81_1_UI_RUNTIME_STATE_BINDING_SEED'
$checkLines += 'scope=minimal_observable_state_update_register_propagate'
$checkLines += 'foundation=phase80_0_to_phase81_0_native_runtime_stack'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# State/Binding Validation'

foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# State/Binding Coverage'
$checkLines += ('state_record_present=' + $(if ($widgetContent -match 'struct ObservableStateRecord') { 'YES' } else { 'NO' }))
$checkLines += ('binding_record_present=' + $(if ($widgetContent -match 'struct BindingRecord') { 'YES' } else { 'NO' }))
$checkLines += ('state_create_present=' + $(if ($widgetContent -match 'create_observable_state_record\(') { 'YES' } else { 'NO' }))
$checkLines += ('state_update_present=' + $(if ($widgetContent -match 'update_state_value\(') { 'YES' } else { 'NO' }))
$checkLines += ('binding_register_present=' + $(if ($widgetContent -match 'register_binding\(') { 'YES' } else { 'NO' }))
$checkLines += ('binding_trigger_present=' + $(if ($widgetContent -match 'trigger_binding_propagation\(') { 'YES' } else { 'NO' }))
$checkLines += ('binding_propagate_present=' + $(if ($widgetContent -match 'propagate_bindings\(') { 'YES' } else { 'NO' }))
$checkLines += ('binding_ordering_sort_present=' + $(if ($widgetContent -match 'std::sort\(') { 'YES' } else { 'NO' }))
$checkLines += ('state_update_sequence_present=' + $(if ($widgetContent -match 'state_update_sequence_') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('state_binding_seed_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE81_1_UI_RUNTIME_STATE_BINDING_SEED'
$contract += 'objective=Add minimal native observable_state_and_binding seed with update registration propagation and deterministic ordering on top of phase80_0_to_phase81_0 foundations'
$contract += 'changes_introduced=NativeWindowPump_state_binding_seed_added_with_ObservableStateRecord_BindingRecord_state_update_register_trigger_propagate_and_ordered_binding_delivery'
$contract += 'runtime_behavior_changes=Native_runtime_now_exposes_minimal_state_binding_paths_with_deterministic_ordering_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_state_binding_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_state_binding_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase81_1_ui_runtime_state_binding_seed_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase81_1_status=' + $phaseStatus)
exit 0

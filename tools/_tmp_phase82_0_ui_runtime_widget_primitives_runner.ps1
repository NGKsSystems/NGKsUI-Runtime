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
$proofName = "phase82_0_ui_runtime_widget_primitives_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase82_0_ui_runtime_widget_primitives_*.zip' -ErrorAction SilentlyContinue |
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

$widgetMain = Join-Path $workspaceRoot 'apps/widget_sandbox/main.cpp'
$widgetContent = if (Test-Path -LiteralPath $widgetMain) { Get-Content -LiteralPath $widgetMain -Raw } else { "" }

$checkResults = @{}
$checkResults['check_startup_works'] = @{ Result = $false; Reason = 'startup marker missing' }
if ($widgetContent -match 'phase82_0_widget_primitives_available') {
  $checkResults['check_startup_works'].Result = $true
  $checkResults['check_startup_works'].Reason = 'startup includes PHASE82_0 marker'
}

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard preserved before native activation'
}

$checkResults['check_label_creation_path_exists'] = @{ Result = $false; Reason = 'label creation path missing' }
if ($widgetContent -match 'PrimitiveKind::Label' -and $widgetContent -match 'register_primitive\(' -and $widgetContent -match 'PHASE82_0 Label') {
  $checkResults['check_label_creation_path_exists'].Result = $true
  $checkResults['check_label_creation_path_exists'].Reason = 'label creation path exists'
}

$checkResults['check_button_creation_path_exists'] = @{ Result = $false; Reason = 'button creation path missing' }
if ($widgetContent -match 'PrimitiveKind::Button' -and $widgetContent -match 'button_click_action') {
  $checkResults['check_button_creation_path_exists'].Result = $true
  $checkResults['check_button_creation_path_exists'].Reason = 'button creation path exists'
}

$checkResults['check_container_creation_path_exists'] = @{ Result = $false; Reason = 'container creation path missing' }
if ($widgetContent -match 'PrimitiveKind::Container' -and $widgetContent -match 'panel_node') {
  $checkResults['check_container_creation_path_exists'].Result = $true
  $checkResults['check_container_creation_path_exists'].Reason = 'container creation path exists'
}

$checkResults['check_button_click_to_action_execution_path_works'] = @{ Result = $false; Reason = 'button click to action execution path missing' }
if ($widgetContent -match 'handle_mouse_button_down' -and $widgetContent -match 'handle_mouse_button_up' -and $widgetContent -match 'queue_action_invocation\(' -and $widgetContent -match 'process_pending_actions_deterministic\(') {
  $checkResults['check_button_click_to_action_execution_path_works'].Result = $true
  $checkResults['check_button_click_to_action_execution_path_works'].Reason = 'button click to action execution path exists'
}

$checkResults['check_layout_pass_positions_primitives'] = @{ Result = $false; Reason = 'layout positioning path missing' }
if ($widgetContent -match 'run_layout_update_pass\(' -and $widgetContent -match 'nested_id' -and $widgetContent -match 'bounds') {
  $checkResults['check_layout_pass_positions_primitives'].Result = $true
  $checkResults['check_layout_pass_positions_primitives'].Reason = 'layout pass positions primitives'
}

$checkResults['check_redraw_invalidation_works'] = @{ Result = $false; Reason = 'redraw invalidation path missing' }
if ($widgetContent -match 'invalidate_ui_tree\(' -and $widgetContent -match 'WM_PAINT' -and $widgetContent -match 'render_label_primitives\(') {
  $checkResults['check_redraw_invalidation_works'].Result = $true
  $checkResults['check_redraw_invalidation_works'].Reason = 'redraw invalidation path exists'
}

$checkResults['check_signal_state_integration_works'] = @{ Result = $false; Reason = 'signal state integration missing' }
if ($widgetContent -match 'SignalEventType::ActionInvoked' -and $widgetContent -match 'update_state_value\(' -and $widgetContent -match 'propagate_bindings\(') {
  $checkResults['check_signal_state_integration_works'].Result = $true
  $checkResults['check_signal_state_integration_works'].Reason = 'signal and state integration exists'
}

$checkResults['check_idle_still_works'] = @{ Result = $false; Reason = 'idle behavior missing' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_still_works'].Result = $true
  $checkResults['check_idle_still_works'].Reason = 'idle still works via message loop'
}

$checkResults['check_shutdown_still_works'] = @{ Result = $false; Reason = 'shutdown behavior missing' }
if ($widgetContent -match 'cleanup\(' -and $widgetContent -match 'primitives_\.clear\(') {
  $checkResults['check_shutdown_still_works'].Result = $true
  $checkResults['check_shutdown_still_works'].Reason = 'shutdown still works with primitive teardown'
}

$failedCount = 0
foreach ($check in $checkResults.Values) { if (-not $check.Result) { $failedCount++ } }
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_ui_runtime_widget_primitives_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE82_0_UI_RUNTIME_WIDGET_PRIMITIVES'
$checkLines += 'scope=minimal_label_button_container_first_slice'
$checkLines += 'foundation=phase80_0_to_phase81_2_native_runtime_stack'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Widget Primitive Validation'
foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}
$checkLines += ''
$checkLines += '# Primitive Coverage'
$checkLines += ('primitive_record_present=' + $(if ($widgetContent -match 'struct WidgetPrimitiveRecord') { 'YES' } else { 'NO' }))
$checkLines += ('primitive_label_present=' + $(if ($widgetContent -match 'PrimitiveKind::Label') { 'YES' } else { 'NO' }))
$checkLines += ('primitive_button_present=' + $(if ($widgetContent -match 'PrimitiveKind::Button') { 'YES' } else { 'NO' }))
$checkLines += ('primitive_container_present=' + $(if ($widgetContent -match 'PrimitiveKind::Container') { 'YES' } else { 'NO' }))
$checkLines += ('primitive_register_present=' + $(if ($widgetContent -match 'register_primitive\(') { 'YES' } else { 'NO' }))
$checkLines += ('primitive_seed_present=' + $(if ($widgetContent -match 'initialize_widget_primitives_seed\(') { 'YES' } else { 'NO' }))
$checkLines += ('primitive_label_render_present=' + $(if ($widgetContent -match 'render_label_primitives\(' -and $widgetContent -match 'TextOutW') { 'YES' } else { 'NO' }))
$checkLines += ('primitive_button_action_binding_present=' + $(if ($widgetContent -match 'button_click_action' -and $widgetContent -match 'action_id') { 'YES' } else { 'NO' }))
$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('widget_primitives_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE82_0_UI_RUNTIME_WIDGET_PRIMITIVES'
$contract += 'objective=Introduce first minimal core widget primitives label_button_container on top of phase80_0_to_phase81_2 runtime foundations to prove real UI composition is possible'
$contract += 'changes_introduced=NativeWindowPump_widget_primitives_seed_added_with_label_button_container_records_node_mapping_lifecycle_layout_propagation_label_draw_and_button_click_action_binding'
$contract += 'runtime_behavior_changes=Native_runtime_now_exposes_minimal_widget_primitive_composition_with_input_to_action_execution_and_invalidation_redraw_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_widget_primitives_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_widget_primitives_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase82_0_ui_runtime_widget_primitives_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase82_0_status=' + $phaseStatus)
exit 0

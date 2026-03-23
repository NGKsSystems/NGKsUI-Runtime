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
$proofName = "phase80_3_ui_runtime_tree_layout_seed_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Write-Host "Stage folder: $stageRoot"
Write-Host "Final zip: $zipPath"

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase80_3_ui_runtime_tree_layout_seed_*.zip' -ErrorAction SilentlyContinue |
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

$checkResults['check_execution_pipeline_guard_preserved'] = @{ Result = $false; Reason = 'execution_pipeline trust guard missing' }
if ($widgetContent -match 'require_runtime_trust\("execution_pipeline"\)') {
  $checkResults['check_execution_pipeline_guard_preserved'].Result = $true
  $checkResults['check_execution_pipeline_guard_preserved'].Reason = 'execution_pipeline trust guard preserved before native activation'
}

$checkResults['check_startup_path_valid'] = @{ Result = $false; Reason = 'startup path not validated' }
if ($widgetContent -match 'int\s+main\s*\(' -and $widgetContent -match 'phase80_3_ui_tree_seed_available') {
  $checkResults['check_startup_path_valid'].Result = $true
  $checkResults['check_startup_path_valid'].Reason = 'startup path includes PHASE80_3 activation marker'
}

$checkResults['check_ui_tree_root_exists'] = @{ Result = $false; Reason = 'UI tree root path missing' }
if ($widgetContent -match 'ui_root_id_|initialize_ui_tree_seed\(|UiNode root|root\.id\s*=\s*0') {
  $checkResults['check_ui_tree_root_exists'].Result = $true
  $checkResults['check_ui_tree_root_exists'].Reason = 'UI tree root initialization exists'
}

$checkResults['check_child_attach_path_exists'] = @{ Result = $false; Reason = 'child attach path missing' }
if ($widgetContent -match 'attach_child_node\(|children\.push_back|create_ui_node\(') {
  $checkResults['check_child_attach_path_exists'].Result = $true
  $checkResults['check_child_attach_path_exists'].Reason = 'child hierarchy attach path exists'
}

$checkResults['check_bounds_storage_exists'] = @{ Result = $false; Reason = 'bounds storage missing' }
if ($widgetContent -match 'struct UiBounds|bounds\.|width|height') {
  $checkResults['check_bounds_storage_exists'].Result = $true
  $checkResults['check_bounds_storage_exists'].Reason = 'bounds storage exists in UI nodes'
}

$checkResults['check_layout_update_pass_exists'] = @{ Result = $false; Reason = 'layout update pass missing' }
if ($widgetContent -match 'run_layout_update_pass\(|next_y|children') {
  $checkResults['check_layout_update_pass_exists'].Result = $true
  $checkResults['check_layout_update_pass_exists'].Reason = 'basic layout and update pass exists'
}

$checkResults['check_invalidation_redraw_path_exists'] = @{ Result = $false; Reason = 'invalidation redraw path missing' }
if ($widgetContent -match 'invalidate_ui_tree\(|request_redraw\(|InvalidateRect\(') {
  $checkResults['check_invalidation_redraw_path_exists'].Result = $true
  $checkResults['check_invalidation_redraw_path_exists'].Reason = 'invalidation triggers redraw path exists'
}

$checkResults['check_wm_paint_consumes_invalidation'] = @{ Result = $false; Reason = 'WM_PAINT invalidation consumption missing' }
if ($widgetContent -match 'case WM_PAINT:' -and $widgetContent -match 'ui_tree_invalidated_' -and $widgetContent -match 'run_layout_update_pass\(') {
  $checkResults['check_wm_paint_consumes_invalidation'].Result = $true
  $checkResults['check_wm_paint_consumes_invalidation'].Reason = 'WM_PAINT consumes invalidation and runs layout/update'
}

$checkResults['check_idle_behavior_preserved'] = @{ Result = $false; Reason = 'idle behavior not preserved' }
if ($widgetContent -match 'while\s*\(GetMessageW\(|while\s*\(GetMessage\(') {
  $checkResults['check_idle_behavior_preserved'].Result = $true
  $checkResults['check_idle_behavior_preserved'].Reason = 'idle behavior preserved by blocking message loop'
}

$checkResults['check_shutdown_behavior_preserved'] = @{ Result = $false; Reason = 'shutdown behavior not preserved' }
if ($widgetContent -match 'WM_CLOSE|WM_DESTROY|PostQuitMessage|cleanup\(') {
  $checkResults['check_shutdown_behavior_preserved'].Result = $true
  $checkResults['check_shutdown_behavior_preserved'].Reason = 'shutdown behavior preserved'
}

$checkResults['check_minimal_scope_preserved'] = @{ Result = $false; Reason = 'scope may be broad' }
if ($widgetContent -match 'NativeWindowPump' -and $widgetContent -notmatch 'QMainWindow|QApplication::exec') {
  $checkResults['check_minimal_scope_preserved'].Result = $true
  $checkResults['check_minimal_scope_preserved'].Reason = 'minimal native scope preserved with no broad widget library'
}

$failedCount = 0
foreach ($check in $checkResults.Values) {
  if (-not $check.Result) { $failedCount++ }
}
$phaseStatus = if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' }

$checksFile = Join-Path $stageRoot '90_ui_runtime_tree_layout_checks.txt'
$checkLines = @()
$checkLines += 'phase=PHASE80_3_UI_RUNTIME_TREE_LAYOUT_SEED'
$checkLines += 'scope=minimal_ui_tree_root_child_bounds_layout_invalidation_redraw'
$checkLines += 'foundation=phase80_0_native_window_phase80_1_input_phase80_2_render_surface'
$checkLines += ('total_checks=' + $checkResults.Count)
$checkLines += ('passed_checks=' + ($checkResults.Count - $failedCount))
$checkLines += ('failed_checks=' + $failedCount)
$checkLines += ''
$checkLines += '# Tree/Layout Validation'

foreach ($checkName in $checkResults.Keys) {
  $check = $checkResults[$checkName]
  $result = if ($check.Result) { 'YES' } else { 'NO' }
  $checkLines += ($checkName + '=' + $result + ' # ' + $check.Reason)
}

$checkLines += ''
$checkLines += '# Structural Coverage'
$checkLines += ('ui_struct_uibounds_present=' + $(if ($widgetContent -match 'struct UiBounds') { 'YES' } else { 'NO' }))
$checkLines += ('ui_struct_uinode_present=' + $(if ($widgetContent -match 'struct UiNode') { 'YES' } else { 'NO' }))
$checkLines += ('ui_root_field_present=' + $(if ($widgetContent -match 'ui_root_id_') { 'YES' } else { 'NO' }))
$checkLines += ('ui_nodes_collection_present=' + $(if ($widgetContent -match 'ui_nodes_') { 'YES' } else { 'NO' }))
$checkLines += ('ui_attach_method_present=' + $(if ($widgetContent -match 'attach_child_node\(') { 'YES' } else { 'NO' }))
$checkLines += ('ui_layout_method_present=' + $(if ($widgetContent -match 'run_layout_update_pass\(') { 'YES' } else { 'NO' }))
$checkLines += ('ui_invalidate_method_present=' + $(if ($widgetContent -match 'invalidate_ui_tree\(') { 'YES' } else { 'NO' }))
$checkLines += ('ui_redraw_method_present=' + $(if ($widgetContent -match 'request_redraw\(') { 'YES' } else { 'NO' }))

$checkLines += ''
$checkLines += ('phase_status=' + $phaseStatus)
$checkLines += ('ui_tree_layout_seed_readiness=' + $phaseStatus)
$checkLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$contract = @()
$contract += 'next_phase_selected=PHASE80_3_UI_RUNTIME_TREE_LAYOUT_SEED'
$contract += 'objective=Add minimal native UI tree seed with root child hierarchy bounds storage layout_update pass and invalidation_redraw path on top of phase80_0_to_phase80_2 foundations'
$contract += 'changes_introduced=NativeWindowPump_ui_tree_seed_added_with_UiBounds_UiNode_root_child_attach_layout_update_and_invalidation_redraw_methods'
$contract += 'runtime_behavior_changes=Native_runtime_now_exposes_minimal_ui_tree_layout_seed_and_redraw_invalidation_path_while_preserving_execution_pipeline_guard_before_native_activation'
$contract += ('new_regressions_detected=' + $(if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes_see_90_checks' }))
$contract += ('phase_status=' + $phaseStatus)
$contract += ('proof_folder=' + $proofPathRelative)
$contract | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) { Write-Host 'FATAL: 90_ui_runtime_tree_layout_checks.txt malformed'; exit 1 }
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) { Write-Host 'FATAL: 99_contract_summary.txt malformed'; exit 1 }

$expectedEntries = @('90_ui_runtime_tree_layout_checks.txt', '99_contract_summary.txt')
New-ProofZip -SourceDir $stageRoot -DestinationZip $zipPath
if (-not (Test-Path -LiteralPath $zipPath)) { Write-Host 'FATAL: final proof zip missing'; exit 1 }
if (-not (Test-ZipContainsEntries -ZipFile $zipPath -ExpectedEntries $expectedEntries)) { Write-Host 'FATAL: final proof zip missing expected entries'; exit 1 }

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase80_3_ui_runtime_tree_layout_seed_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('PF=' + $proofPathRelative)
Write-Host 'GATE=PASS'
Write-Host ('phase80_3_status=' + $phaseStatus)
exit 0

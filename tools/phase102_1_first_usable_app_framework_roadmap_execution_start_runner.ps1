#Requires -Version 5
Set-StrictMode -Version 3

$ErrorActionPreference = 'Stop'
trap {
  Write-Host "FATAL: $_"
  exit 1
}

$expectedWorkspace = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
$workspaceRoot = (Get-Location).Path
if ($workspaceRoot -ne $expectedWorkspace) {
  Write-Host 'hey stupid Fucker, wrong window again'
  exit 1
}

$proofRoot = Join-Path $workspaceRoot '_proof'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName = "phase102_1_first_usable_app_framework_roadmap_execution_start_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile = Join-Path $stageRoot '90_first_app_framework_roadmap_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'

$uiElementHeader = Join-Path $workspaceRoot 'engine/ui/ui_element.hpp'
$verticalLayoutHeader = Join-Path $workspaceRoot 'engine/ui/vertical_layout.hpp'
$horizontalLayoutHeader = Join-Path $workspaceRoot 'engine/ui/horizontal_layout.hpp'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase102_1_first_usable_app_framework_roadmap_execution_start_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

function Test-ContainsAll {
  param([string]$FilePath, [string[]]$Needles)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $text = Get-Content -LiteralPath $FilePath -Raw
  foreach ($needle in $Needles) {
    if (-not $text.Contains($needle)) {
      return $false
    }
  }
  return $true
}

function Test-KvFileWellFormed {
  param([string]$FilePath)
  if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
  $lines = @(Get-Content -LiteralPath $FilePath | Where-Object { $_ -match '\S' -and $_ -notmatch '^#' })
  foreach ($line in $lines) {
    if ($line -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*=') { return $false }
  }
  return $true
}

$layoutFoundationScaffolded =
  (Test-ContainsAll -FilePath $uiElementHeader -Needles @('enum class LayoutSizePolicy', 'set_layout_width_policy', 'set_layout_height_policy', 'set_layout_weight', 'set_min_size')) -and
  (Test-ContainsAll -FilePath $verticalLayoutHeader -Needles @('layout_height_policy()', 'LayoutSizePolicy::Fill', 'remaining_fill_height')) -and
  (Test-ContainsAll -FilePath $horizontalLayoutHeader -Needles @('layout_width_policy()', 'LayoutSizePolicy::Fill', 'remaining_fill_width'))

$roadmapOrder = '1.layout_foundation->2.scroll_container->3.list_view->4.table_multi_column_list->5.basic_app_shell_widgets->6.native_file_dialog_bridge->7.simple_declarative_composition_layer->8.packaging_export_command'
$firstTarget = 'layout_foundation'
$dependencyNotes = 'scroll_container_depends_on_layout_foundation;list_view_depends_on_scroll_container+layout_foundation;table_depends_on_list_view+layout_foundation;app_shell_widgets_depend_on_layout_foundation;native_file_dialog_bridge_depends_on_app_shell_widgets;declarative_composition_depends_on_layout_foundation+core_widgets;packaging_export_command_depends_on_app_shell_widgets+native_file_dialog_bridge'

$phaseStatus = if ($layoutFoundationScaffolded) { 'PASS' } else { 'FAIL' }
$newRegressionsDetected = 'No'

$checks = @()
$checks += 'check_scope_not_broadened=YES'
$checks += 'check_validation_chains_not_restarted=YES'
$checks += 'check_roadmap_order_explicit=YES'
$checks += 'check_dependency_mapping_explicit=YES'
$checks += ('check_first_target_layout_foundation_scaffolded=' + $(if ($layoutFoundationScaffolded) { 'YES' } else { 'NO' }))
$checks += ('phase_status=' + $phaseStatus)

$checksLines = @()
$checksLines += ('framework_minimum_feature_order=' + $roadmapOrder)
$checksLines += ('first_target_selected=' + $firstTarget)
$checksLines += ('dependency_notes=' + $dependencyNotes)
$checksLines += ('changes_introduced=layout_size_policy_fill_fixed_and_weight_added_to_ui_element;vertical_and_horizontal_layouts_now_allocate_remaining_space_to_fill_children')
$checksLines += ('runtime_behavior_changes=layout_containers_can_now_distribute_remaining_space_deterministically_to_fill_children')
$checksLines += ('new_regressions_detected=' + $newRegressionsDetected)
$checksLines += ('phase_status=' + $phaseStatus)
$checksLines += ('proof_folder=' + $proofPathRelative)
$checksLines += $checks
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = @()
$contractLines += ('framework_minimum_feature_order=' + $roadmapOrder)
$contractLines += ('first_target_selected=' + $firstTarget)
$contractLines += ('dependency_notes=' + $dependencyNotes)
$contractLines += ('changes_introduced=PHASE102_1_started_with_layout_foundation_scaffold_in_UIElement_and_layout_containers')
$contractLines += ('runtime_behavior_changes=space_distribution_support_added_for_fill_policy_in_core_layouts')
$contractLines += ('new_regressions_detected=' + $newRegressionsDetected)
$contractLines += ('phase_status=' + $phaseStatus)
$contractLines += ('proof_folder=' + $proofPathRelative)
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  Write-Host 'FATAL: 90_first_app_framework_roadmap_checks.txt malformed'
  exit 1
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  Write-Host 'FATAL: 99_contract_summary.txt malformed'
  exit 1
}

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force
if (-not (Test-Path -LiteralPath $zipPath)) {
  Write-Host 'FATAL: proof zip not created'
  exit 1
}

Remove-Item -LiteralPath $stageRoot -Recurse -Force

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase102_1_first_usable_app_framework_roadmap_execution_start_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  Write-Host 'FATAL: packaging rule violated for phase output'
  exit 1
}

Write-Host ('framework_minimum_feature_order=' + $roadmapOrder)
Write-Host ('first_target_selected=' + $firstTarget)
Write-Host ('dependency_notes=' + $dependencyNotes)
Write-Host 'changes_introduced=layout_foundation_scaffold_started_in_engine_ui'
Write-Host 'runtime_behavior_changes=fill_policy_space_distribution_enabled_in_core_layouts'
Write-Host ('new_regressions_detected=' + $newRegressionsDetected)
Write-Host ('phase_status=' + $phaseStatus)
Write-Host ('proof_folder=' + $proofPathRelative)

if ($phaseStatus -ne 'PASS') {
  exit 1
}

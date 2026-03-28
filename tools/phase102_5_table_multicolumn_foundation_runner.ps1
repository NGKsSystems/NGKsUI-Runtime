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
$proofName = "phase102_5_table_multicolumn_foundation_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile = Join-Path $stageRoot '90_table_multicolumn_foundation_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase102_5_table_multicolumn_foundation_*.zip' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

function Remove-PathIfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Test-LinePresent {
  param([string]$Text, [string]$Pattern)
  return [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
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

function Invoke-CmdChecked {
  param([string]$CommandLine, [string]$LogPath, [string]$StepName)
  Add-Content -LiteralPath $LogPath -Value ("STEP=$StepName")
  cmd /c $CommandLine *>&1 | Out-File -LiteralPath $LogPath -Append -Encoding UTF8
  if ($LASTEXITCODE -ne 0) {
    throw "$StepName failed with exit code $LASTEXITCODE"
  }
}

$tableHeaderPath = Join-Path $workspaceRoot 'engine/ui/table_view.hpp'
if (-not (Test-Path -LiteralPath $tableHeaderPath)) {
  throw 'table_view.hpp missing from engine/ui/'
}

$tableHeaderText = Get-Content -LiteralPath $tableHeaderPath -Raw
$tableCreatedInHeader =
  ($tableHeaderText -match 'class TableView') -and
  ($tableHeaderText -match 'set_data') -and
  ($tableHeaderText -match 'on_mouse_down') -and
  ($tableHeaderText -match 'set_selected_index')

& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 |
  Out-File -LiteralPath $buildOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw 'desktop_file_tool build-plan generation failed'
}

if (-not (Test-Path -LiteralPath $planPath)) {
  throw 'desktop_file_tool build plan missing'
}

$planJson = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json

$engineCompileNodes = @($planJson.nodes | Where-Object { $_.desc -like 'Compile engine/* for engine' })
$appCompileNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]

if ($engineCompileNodes.Count -eq 0 -or $null -eq $appCompileNode -or $null -eq $engineLibNode -or $null -eq $appLinkNode) {
  throw 'Required compile/link nodes missing from build plan'
}

& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 |
  Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -LogPath $buildOut -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -LogPath $buildOut -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd -LogPath $buildOut -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd -LogPath $buildOut -StepName $appLinkNode.desc

if (-not (Test-Path -LiteralPath $exePath)) {
  throw 'desktop_file_tool executable missing after compile/link'
}

& $exePath --validation-mode --auto-close-ms=3000 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw "desktop_file_tool validation run failed (exit $LASTEXITCODE)"
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$tableViewCreatedRuntime = Test-LinePresent -Text $runText -Pattern '^phase102_5_table_view_created=1$'
$multiColumnRenderingSupported = Test-LinePresent -Text $runText -Pattern '^phase102_5_multi_column_rendering_supported=1$'
$headerRenderingSupported = Test-LinePresent -Text $runText -Pattern '^phase102_5_header_rendering_supported=1$'
$rowSelectionSupported = Test-LinePresent -Text $runText -Pattern '^phase102_5_row_selection_supported=1$'
$clickSelectionSupported = Test-LinePresent -Text $runText -Pattern '^phase102_5_click_selection_supported=1$'
$dataBindingWorking = Test-LinePresent -Text $runText -Pattern '^phase102_5_data_binding_working=1$'
$refreshSafe = Test-LinePresent -Text $runText -Pattern '^phase102_5_refresh_safe=1$'

$phase102_2_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_layout_functionalized=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_predictable_resize_behavior=1$')
$phase102_3_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_3_scroll_container_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_3_vertical_scroll_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_3_mouse_wheel_supported=1$')
$phase102_4_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_list_view_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_row_selection_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_click_selection_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_4_data_binding_working=1$')
$noCrash =
  (Test-LinePresent -Text $runText -Pattern '^app_runtime_crash_detected=0$') -and
  (Test-LinePresent -Text $runText -Pattern '^runtime_final_status=RUN_OK$')
$summaryPass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'

$tableRowCount = if ($runText -match '(?m)^phase102_5_table_row_count=(\d+)$') { $matches[1] } else { '0' }
$tableColumnCount = if ($runText -match '(?m)^phase102_5_table_column_count=(\d+)$') { $matches[1] } else { '0' }
$tableBindCount = if ($runText -match '(?m)^phase102_5_table_bind_count=(\d+)$') { $matches[1] } else { '0' }

$noRegressions = $phase102_2_ok -and $phase102_3_ok -and $phase102_4_ok -and $noCrash -and $summaryPass
$tableViewCreated = $tableCreatedInHeader -and $tableViewCreatedRuntime

$phaseStatus = if (
  $tableViewCreated -and $multiColumnRenderingSupported -and $headerRenderingSupported -and
  $rowSelectionSupported -and $clickSelectionSupported -and $dataBindingWorking -and
  $refreshSafe -and $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }

$changesIntroduced = 'table_view_hpp_added_to_engine_ui;table_view_integrated_into_desktop_file_tool;multi_column_rows_rendered;column_headers_rendered;row_click_selection_enabled;in_memory_data_binding_and_rebind_safety'

$checksLines = @(
  "table_view_created=$(if ($tableViewCreated) { 'YES' } else { 'NO' })",
  "multi_column_rendering_supported=$(if ($multiColumnRenderingSupported) { 'YES' } else { 'NO' })",
  "header_rendering_supported=$(if ($headerRenderingSupported) { 'YES' } else { 'NO' })",
  "row_selection_supported=$(if ($rowSelectionSupported) { 'YES' } else { 'NO' })",
  "click_selection_supported=$(if ($clickSelectionSupported) { 'YES' } else { 'NO' })",
  "data_binding_working=$(if ($dataBindingWorking) { 'YES' } else { 'NO' })",
  "refresh_safe=$(if ($refreshSafe) { 'YES' } else { 'NO' })",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = @(
  "table_view_created=$(if ($tableViewCreated) { 'YES' } else { 'NO' })",
  "multi_column_rendering_supported=$(if ($multiColumnRenderingSupported) { 'YES' } else { 'NO' })",
  "header_rendering_supported=$(if ($headerRenderingSupported) { 'YES' } else { 'NO' })",
  "row_selection_supported=$(if ($rowSelectionSupported) { 'YES' } else { 'NO' })",
  "click_selection_supported=$(if ($clickSelectionSupported) { 'YES' } else { 'NO' })",
  "data_binding_working=$(if ($dataBindingWorking) { 'YES' } else { 'NO' })",
  "refresh_safe=$(if ($refreshSafe) { 'YES' } else { 'NO' })",
  "table_row_count=$tableRowCount",
  "table_column_count=$tableColumnCount",
  "table_bind_count=$tableBindCount",
  "phase102_2_regression_ok=$(if ($phase102_2_ok) { 'YES' } else { 'NO' })",
  "phase102_3_regression_ok=$(if ($phase102_3_ok) { 'YES' } else { 'NO' })",
  "phase102_4_regression_ok=$(if ($phase102_4_ok) { 'YES' } else { 'NO' })",
  "changes_introduced=$changesIntroduced",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  throw '90_table_multicolumn_foundation_checks.txt is malformed'
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  throw '99_contract_summary.txt is malformed'
}

Remove-PathIfExists -Path $buildOut
Remove-PathIfExists -Path $runOut

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force
if (-not (Test-Path -LiteralPath $zipPath)) {
  throw 'proof zip was not created'
}

Remove-PathIfExists -Path $stageRoot

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot |
  Where-Object { $_.Name -like 'phase102_5_table_multicolumn_foundation_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  throw 'packaging rule violated: expected exactly one phase102_5 artifact'
}

Write-Host ("table_view_created=$(if ($tableViewCreated) { 'YES' } else { 'NO' })")
Write-Host ("multi_column_rendering_supported=$(if ($multiColumnRenderingSupported) { 'YES' } else { 'NO' })")
Write-Host ("header_rendering_supported=$(if ($headerRenderingSupported) { 'YES' } else { 'NO' })")
Write-Host ("row_selection_supported=$(if ($rowSelectionSupported) { 'YES' } else { 'NO' })")
Write-Host ("click_selection_supported=$(if ($clickSelectionSupported) { 'YES' } else { 'NO' })")
Write-Host ("data_binding_working=$(if ($dataBindingWorking) { 'YES' } else { 'NO' })")
Write-Host ("refresh_safe=$(if ($refreshSafe) { 'YES' } else { 'NO' })")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}

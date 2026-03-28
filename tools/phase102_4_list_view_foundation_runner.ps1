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

$proofRoot     = Join-Path $workspaceRoot '_proof'
$timestamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$proofName     = "phase102_4_list_view_foundation_$timestamp"
$stageRoot     = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath       = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile  = Join-Path $stageRoot '90_list_view_foundation_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut    = Join-Path $stageRoot '__build_stdout.txt'
$runOut      = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath  = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'

New-Item -ItemType Directory -Path $proofRoot  -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot  -Force | Out-Null

# Remove any prior phase102_4 zips so exactly-one rule is enforceable.
Get-ChildItem -LiteralPath $proofRoot -Filter 'phase102_4_list_view_foundation_*.zip' -ErrorAction SilentlyContinue |
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

# ── Source-level audit: verify list_view.hpp exists ────────────────────────────
$listHeaderPath = Join-Path $workspaceRoot 'engine/ui/list_view.hpp'
if (-not (Test-Path -LiteralPath $listHeaderPath)) {
  throw 'list_view.hpp missing from engine/ui/'
}

$listHeaderText = Get-Content -LiteralPath $listHeaderPath -Raw
$listCreatedInHeader =
  ($listHeaderText -match 'class ListView') -and
  ($listHeaderText -match 'set_items') -and
  ($listHeaderText -match 'selected_index') -and
  ($listHeaderText -match 'set_selected_index') -and
  ($listHeaderText -match 'on_mouse_down')

# ── Build plan generation ──────────────────────────────────────────────────────
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
$appCompileNode     = @($planJson.nodes | Where-Object { $_.desc -eq 'Compile apps/desktop_file_tool/main.cpp for desktop_file_tool' })[0]
$engineLibNode      = @($planJson.nodes | Where-Object { $_.desc -eq 'Link engine' })[0]
$appLinkNode        = @($planJson.nodes | Where-Object { $_.desc -eq 'Link desktop_file_tool' })[0]

if ($engineCompileNodes.Count -eq 0 -or $null -eq $appCompileNode -or $null -eq $engineLibNode -or $null -eq $appLinkNode) {
  throw 'Required compile/link nodes missing from build plan'
}

# ── Compile ────────────────────────────────────────────────────────────────────
& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 |
  Out-File -LiteralPath $buildOut -Append -Encoding UTF8

foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -LogPath $buildOut -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -LogPath $buildOut -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd  -LogPath $buildOut -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd    -LogPath $buildOut -StepName $appLinkNode.desc

if (-not (Test-Path -LiteralPath $exePath)) {
  throw 'desktop_file_tool executable missing after compile/link'
}

# ── Validation run ─────────────────────────────────────────────────────────────
& $exePath --validation-mode --auto-close-ms=2600 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw "desktop_file_tool validation run failed (exit $LASTEXITCODE)"
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

# ── Parse PHASE102_4 markers ───────────────────────────────────────────────────
$listCreatedRuntime         = Test-LinePresent -Text $runText -Pattern '^phase102_4_list_view_created=1$'
$rowSelectionSupported      = Test-LinePresent -Text $runText -Pattern '^phase102_4_row_selection_supported=1$'
$clickSelectionSupported    = Test-LinePresent -Text $runText -Pattern '^phase102_4_click_selection_supported=1$'
$scrollIntegrationWorking   = Test-LinePresent -Text $runText -Pattern '^phase102_4_scroll_integration_working=1$'
$dataBindingWorking         = Test-LinePresent -Text $runText -Pattern '^phase102_4_data_binding_working=1$'

# ── Parse regression markers (PHASE102_2 and PHASE102_3) ─────────────────────────
$phase102_2_ok = (Test-LinePresent -Text $runText -Pattern '^phase102_2_layout_functionalized=1$') -and
                 (Test-LinePresent -Text $runText -Pattern '^phase102_2_predictable_resize_behavior=1$')
$phase102_3_ok = (Test-LinePresent -Text $runText -Pattern '^phase102_3_scroll_container_created=1$') -and
                 (Test-LinePresent -Text $runText -Pattern '^phase102_3_vertical_scroll_supported=1$') -and
                 (Test-LinePresent -Text $runText -Pattern '^phase102_3_mouse_wheel_supported=1$')
$noCrash       = (Test-LinePresent -Text $runText -Pattern '^app_runtime_crash_detected=0$') -and
                 (Test-LinePresent -Text $runText -Pattern '^runtime_final_status=RUN_OK$')
$summaryPass   = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'

# Extract numeric values for the contract file.
$listItemCount = if ($runText -match '(?m)^phase102_4_list_item_count=(\d+)$') { $matches[1] } else { '0' }
$highlightChanges = if ($runText -match '(?m)^phase102_4_selection_highlight_changes=(\d+)$') { $matches[1] } else { '0' }

$noRegressions =
  $phase102_2_ok -and $phase102_3_ok -and $noCrash -and $summaryPass

$listCreated = $listCreatedInHeader -and $listCreatedRuntime

$phaseStatus = if (
  $listCreated -and $rowSelectionSupported -and $clickSelectionSupported -and
  $scrollIntegrationWorking -and $dataBindingWorking -and $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }

# ── Write 90_list_view_foundation_checks.txt ──────────────────────────────────
$changesIntroduced = 'list_view_hpp_added_to_engine_ui;list_view_integrated_into_desktop_file_tool;file_list_shows_filtered_files;row_selection_with_visual_highlight;click_changes_selection;data_binding_from_model'

$checksLines = @(
  "list_view_created=$(if ($listCreated) { 'YES' } else { 'NO' })",
  "row_selection_supported=$(if ($rowSelectionSupported) { 'YES' } else { 'NO' })",
  "click_selection_supported=$(if ($clickSelectionSupported) { 'YES' } else { 'NO' })",
  "scroll_integration_working=$(if ($scrollIntegrationWorking) { 'YES' } else { 'NO' })",
  "data_binding_working=$(if ($dataBindingWorking) { 'YES' } else { 'NO' })",
  "changes_introduced=$changesIntroduced",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

# ── Write 99_contract_summary.txt ─────────────────────────────────────────────
$contractLines = @(
  "list_view_created=$(if ($listCreated) { 'YES' } else { 'NO' })",
  "row_selection_supported=$(if ($rowSelectionSupported) { 'YES' } else { 'NO' })",
  "click_selection_supported=$(if ($clickSelectionSupported) { 'YES' } else { 'NO' })",
  "scroll_integration_working=$(if ($scrollIntegrationWorking) { 'YES' } else { 'NO' })",
  "data_binding_working=$(if ($dataBindingWorking) { 'YES' } else { 'NO' })",
  "list_item_count=$listItemCount",
  "selection_highlight_changes=$highlightChanges",
  "phase102_2_regression_ok=$(if ($phase102_2_ok) { 'YES' } else { 'NO' })",
  "phase102_3_regression_ok=$(if ($phase102_3_ok) { 'YES' } else { 'NO' })",
  "changes_introduced=$changesIntroduced",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  throw '90_list_view_foundation_checks.txt is malformed'
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  throw '99_contract_summary.txt is malformed'
}

# ── Package zip ───────────────────────────────────────────────────────────────
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

# Exactly-one-artifact enforcement.
$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot |
  Where-Object { $_.Name -like 'phase102_4_list_view_foundation_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  throw 'packaging rule violated: expected exactly one phase102_4 artifact'
}

# ── Final console output ───────────────────────────────────────────────────────
Write-Host ("list_view_created=$(if ($listCreated) { 'YES' } else { 'NO' })")
Write-Host ("row_selection_supported=$(if ($rowSelectionSupported) { 'YES' } else { 'NO' })")
Write-Host ("click_selection_supported=$(if ($clickSelectionSupported) { 'YES' } else { 'NO' })")
Write-Host ("scroll_integration_working=$(if ($scrollIntegrationWorking) { 'YES' } else { 'NO' })")
Write-Host ("data_binding_working=$(if ($dataBindingWorking) { 'YES' } else { 'NO' })")
Write-Host ("changes_introduced=$changesIntroduced")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}

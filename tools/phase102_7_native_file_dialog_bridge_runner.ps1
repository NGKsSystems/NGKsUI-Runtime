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
$proofName = "phase102_7_native_file_dialog_bridge_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile = Join-Path $stageRoot '90_native_file_dialog_bridge_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase102_7_native_file_dialog_bridge_*.zip' -ErrorAction SilentlyContinue |
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

$dialogBridgeHeaderPath = Join-Path $workspaceRoot 'engine/platform/win32/include/ngk/platform/native_dialog_bridge.hpp'
if (-not (Test-Path -LiteralPath $dialogBridgeHeaderPath)) {
  throw 'native_dialog_bridge.hpp missing from engine/platform/win32/include/ngk/platform/'
}

$dialogBridgeHeaderText = Get-Content -LiteralPath $dialogBridgeHeaderPath -Raw
$bridgeDefinedInHeader =
  ($dialogBridgeHeaderText -match 'open_file_dialog') -and
  ($dialogBridgeHeaderText -match 'save_file_dialog') -and
  ($dialogBridgeHeaderText -match 'message_dialog') -and
  ($dialogBridgeHeaderText -match 'GetOpenFileNameW') -and
  ($dialogBridgeHeaderText -match 'GetSaveFileNameW') -and
  ($dialogBridgeHeaderText -match 'MessageBoxW')

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

& $exePath --validation-mode --auto-close-ms=3400 *>&1 |
  Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw "desktop_file_tool validation run failed (exit $LASTEXITCODE)"
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$openFileDialogSupportedRuntime = Test-LinePresent -Text $runText -Pattern '^phase102_7_open_file_dialog_supported=1$'
$saveFileDialogSupported = Test-LinePresent -Text $runText -Pattern '^phase102_7_save_file_dialog_supported=1$'
$messageDialogSupported = Test-LinePresent -Text $runText -Pattern '^phase102_7_message_dialog_supported=1$'
$dialogResultVisibleInUi = Test-LinePresent -Text $runText -Pattern '^phase102_7_dialog_result_visible_in_ui=1$'
$bridgeIntegrated = Test-LinePresent -Text $runText -Pattern '^phase102_7_bridge_integrated=1$'

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
$phase102_5_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_table_view_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_multi_column_rendering_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_header_rendering_supported=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_5_data_binding_working=1$')
$phase102_6_ok =
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_toolbar_container_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_sidebar_container_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_status_bar_created=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_6_shell_widgets_integrated=1$')
$noCrash =
  (Test-LinePresent -Text $runText -Pattern '^app_runtime_crash_detected=0$') -and
  (Test-LinePresent -Text $runText -Pattern '^runtime_final_status=RUN_OK$')
$summaryPass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'

$noRegressions = $phase102_2_ok -and $phase102_3_ok -and $phase102_4_ok -and $phase102_5_ok -and $phase102_6_ok -and $noCrash -and $summaryPass
$openFileDialogSupported = $bridgeDefinedInHeader -and $openFileDialogSupportedRuntime

$phaseStatus = if (
  $openFileDialogSupported -and $saveFileDialogSupported -and $messageDialogSupported -and
  $dialogResultVisibleInUi -and $bridgeIntegrated -and $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }
$changesIntroduced = 'native_dialog_bridge_hpp_added;open_save_message_dialog_apis_added;toolbar_dialog_actions_integrated;dialog_results_published_to_status_ui'

$checksLines = @(
  "open_file_dialog_supported=$(if ($openFileDialogSupported) { 'YES' } else { 'NO' })",
  "save_file_dialog_supported=$(if ($saveFileDialogSupported) { 'YES' } else { 'NO' })",
  "message_dialog_supported=$(if ($messageDialogSupported) { 'YES' } else { 'NO' })",
  "dialog_result_visible_in_ui=$(if ($dialogResultVisibleInUi) { 'YES' } else { 'NO' })",
  "bridge_integrated=$(if ($bridgeIntegrated) { 'YES' } else { 'NO' })",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = @(
  "open_file_dialog_supported=$(if ($openFileDialogSupported) { 'YES' } else { 'NO' })",
  "save_file_dialog_supported=$(if ($saveFileDialogSupported) { 'YES' } else { 'NO' })",
  "message_dialog_supported=$(if ($messageDialogSupported) { 'YES' } else { 'NO' })",
  "dialog_result_visible_in_ui=$(if ($dialogResultVisibleInUi) { 'YES' } else { 'NO' })",
  "bridge_integrated=$(if ($bridgeIntegrated) { 'YES' } else { 'NO' })",
  "phase102_2_regression_ok=$(if ($phase102_2_ok) { 'YES' } else { 'NO' })",
  "phase102_3_regression_ok=$(if ($phase102_3_ok) { 'YES' } else { 'NO' })",
  "phase102_4_regression_ok=$(if ($phase102_4_ok) { 'YES' } else { 'NO' })",
  "phase102_5_regression_ok=$(if ($phase102_5_ok) { 'YES' } else { 'NO' })",
  "phase102_6_regression_ok=$(if ($phase102_6_ok) { 'YES' } else { 'NO' })",
  "changes_introduced=$changesIntroduced",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  throw '90_native_file_dialog_bridge_checks.txt is malformed'
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
  Where-Object { $_.Name -like 'phase102_7_native_file_dialog_bridge_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  throw 'packaging rule violated: expected exactly one phase102_7 artifact'
}

Write-Host ("open_file_dialog_supported=$(if ($openFileDialogSupported) { 'YES' } else { 'NO' })")
Write-Host ("save_file_dialog_supported=$(if ($saveFileDialogSupported) { 'YES' } else { 'NO' })")
Write-Host ("message_dialog_supported=$(if ($messageDialogSupported) { 'YES' } else { 'NO' })")
Write-Host ("dialog_result_visible_in_ui=$(if ($dialogResultVisibleInUi) { 'YES' } else { 'NO' })")
Write-Host ("bridge_integrated=$(if ($bridgeIntegrated) { 'YES' } else { 'NO' })")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}

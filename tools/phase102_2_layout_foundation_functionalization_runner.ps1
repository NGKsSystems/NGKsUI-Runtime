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
$proofName = "phase102_2_layout_foundation_functionalization_$timestamp"
$stageRoot = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile = Join-Path $stageRoot '90_layout_foundation_functionalization_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut = Join-Path $stageRoot '__build_stdout.txt'
$runOut = Join-Path $stageRoot '__run_stdout.txt'

$appMain = Join-Path $workspaceRoot 'apps/desktop_file_tool/main.cpp'
$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'

New-Item -ItemType Directory -Path $proofRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Get-ChildItem -LiteralPath $proofRoot -Filter 'phase102_2_layout_foundation_functionalization_*.zip' -ErrorAction SilentlyContinue |
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

$appText = Get-Content -LiteralPath $appMain -Raw
$manualPositioningReduced = -not [regex]::IsMatch(
  $appText,
  'title_label\.set_position|path_label\.set_position|filter_box\.set_position|apply_button\.set_position|refresh_button\.set_position|prev_button\.set_position|next_button\.set_position|status_label\.set_position|selected_label\.set_position|detail_label\.set_position')

& (Join-Path $workspaceRoot '.venv/Scripts/python.exe') -m ngksgraph build --profile debug --msvc-auto --target desktop_file_tool *>&1 | Out-File -LiteralPath $buildOut -Encoding UTF8
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
  throw 'desktop_file_tool compile/link nodes missing in plan'
}

& (Join-Path $workspaceRoot 'tools/enter_msvc_env.ps1') *>&1 | Out-File -LiteralPath $buildOut -Append -Encoding UTF8
foreach ($node in $engineCompileNodes) {
  Invoke-CmdChecked -CommandLine $node.cmd -LogPath $buildOut -StepName $node.desc
}
Invoke-CmdChecked -CommandLine $appCompileNode.cmd -LogPath $buildOut -StepName $appCompileNode.desc
Invoke-CmdChecked -CommandLine $engineLibNode.cmd -LogPath $buildOut -StepName $engineLibNode.desc
Invoke-CmdChecked -CommandLine $appLinkNode.cmd -LogPath $buildOut -StepName $appLinkNode.desc

if (-not (Test-Path -LiteralPath $exePath)) {
  throw 'desktop_file_tool executable missing after compile/link'
}

& $exePath --validation-mode --auto-close-ms=2600 *>&1 | Out-File -LiteralPath $runOut -Encoding UTF8
if ($LASTEXITCODE -ne 0) {
  throw 'desktop_file_tool validation run failed'
}

$runText = (Get-Content -LiteralPath $runOut -Raw) -replace "`r", ''

$layoutFunctionalized =
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_layout_functionalized=1$') -and
  (Test-LinePresent -Text $runText -Pattern '^phase102_2_predictable_resize_behavior=1$')
$nestedLayoutsSupported = Test-LinePresent -Text $runText -Pattern '^phase102_2_nested_layouts_supported=1$'
$minimumSizeEnforced = Test-LinePresent -Text $runText -Pattern '^phase102_2_minimum_size_enforced=1$'
$manualPositioningReported = Test-LinePresent -Text $runText -Pattern '^phase102_2_manual_positioning_reduced=1$'
$fillWeightBehaviorCorrect = Test-LinePresent -Text $runText -Pattern '^phase102_2_fill_weight_behavior=1$'
$noCrashes = (Test-LinePresent -Text $runText -Pattern '^app_runtime_crash_detected=0$') -and (Test-LinePresent -Text $runText -Pattern '^runtime_final_status=RUN_OK$')
$summaryPass = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'

$phaseStatus = if ($layoutFunctionalized -and $nestedLayoutsSupported -and $minimumSizeEnforced -and $manualPositioningReduced -and $manualPositioningReported -and $fillWeightBehaviorCorrect -and $noCrashes -and $summaryPass) { 'PASS' } else { 'FAIL' }
$newRegressionsDetected = if ($phaseStatus -eq 'PASS') { 'No' } else { 'Yes' }

$checks = @()
$checks += ('layout_functionalized=' + $(if ($layoutFunctionalized) { 'YES' } else { 'NO' }))
$checks += ('nested_layouts_supported=' + $(if ($nestedLayoutsSupported) { 'YES' } else { 'NO' }))
$checks += ('minimum_size_enforced=' + $(if ($minimumSizeEnforced) { 'YES' } else { 'NO' }))
$checks += ('manual_positioning_reduced=' + $(if ($manualPositioningReduced -and $manualPositioningReported) { 'YES' } else { 'NO' }))
$checks += ('fill_weight_behavior_correct=' + $(if ($fillWeightBehaviorCorrect) { 'YES' } else { 'NO' }))
$checks += ('no_crashes=' + $(if ($noCrashes) { 'YES' } else { 'NO' }))
$checks += ('phase_status=' + $phaseStatus)

$checksLines = @()
$checksLines += ('layout_functionalized=' + $(if ($layoutFunctionalized) { 'YES' } else { 'NO' }))
$checksLines += ('nested_layouts_supported=' + $(if ($nestedLayoutsSupported) { 'YES' } else { 'NO' }))
$checksLines += ('minimum_size_enforced=' + $(if ($minimumSizeEnforced) { 'YES' } else { 'NO' }))
$checksLines += ('manual_positioning_reduced=' + $(if ($manualPositioningReduced -and $manualPositioningReported) { 'YES' } else { 'NO' }))
$checksLines += ('changes_introduced=desktop_file_tool_shell_moved_to_nested_vertical_horizontal_layouts;layout_minimum_size_enforcement_enabled_in_ui_element;validation_resizes_now_prove_weighted_fill_distribution')
$checksLines += ('new_regressions_detected=' + $newRegressionsDetected)
$checksLines += ('phase_status=' + $phaseStatus)
$checksLines += ('proof_folder=' + $proofPathRelative)
$checksLines += $checks
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

$contractLines = @()
$contractLines += ('layout_functionalized=' + $(if ($layoutFunctionalized) { 'YES' } else { 'NO' }))
$contractLines += ('nested_layouts_supported=' + $(if ($nestedLayoutsSupported) { 'YES' } else { 'NO' }))
$contractLines += ('minimum_size_enforced=' + $(if ($minimumSizeEnforced) { 'YES' } else { 'NO' }))
$contractLines += ('manual_positioning_reduced=' + $(if ($manualPositioningReduced -and $manualPositioningReported) { 'YES' } else { 'NO' }))
$contractLines += ('changes_introduced=PHASE102_2_functionalized_layout_foundation_in_real_app_shell_with_nested_rows_columns_and_resize_proof')
$contractLines += ('new_regressions_detected=' + $newRegressionsDetected)
$contractLines += ('phase_status=' + $phaseStatus)
$contractLines += ('proof_folder=' + $proofPathRelative)
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  throw '90_layout_foundation_functionalization_checks.txt malformed'
}
if (-not (Test-KvFileWellFormed -FilePath $contractFile)) {
  throw '99_contract_summary.txt malformed'
}

Remove-PathIfExists -Path $buildOut
Remove-PathIfExists -Path $runOut

if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force
if (-not (Test-Path -LiteralPath $zipPath)) {
  throw 'proof zip not created'
}

Remove-PathIfExists -Path $stageRoot

$phaseArtifacts = @(Get-ChildItem -LiteralPath $proofRoot | Where-Object { $_.Name -like 'phase102_2_layout_foundation_functionalization_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  throw 'packaging rule violated for phase output'
}

Write-Host ('layout_functionalized=' + $(if ($layoutFunctionalized) { 'YES' } else { 'NO' }))
Write-Host ('nested_layouts_supported=' + $(if ($nestedLayoutsSupported) { 'YES' } else { 'NO' }))
Write-Host ('minimum_size_enforced=' + $(if ($minimumSizeEnforced) { 'YES' } else { 'NO' }))
Write-Host ('manual_positioning_reduced=' + $(if ($manualPositioningReduced -and $manualPositioningReported) { 'YES' } else { 'NO' }))
Write-Host 'changes_introduced=desktop_file_tool_shell_now_uses_nested_layout_containers_instead_of_manual_widget_positioning'
Write-Host ('new_regressions_detected=' + $newRegressionsDetected)
Write-Host ('phase_status=' + $phaseStatus)
Write-Host ('proof_folder=' + $proofPathRelative)

if ($phaseStatus -ne 'PASS') {
  exit 1
}
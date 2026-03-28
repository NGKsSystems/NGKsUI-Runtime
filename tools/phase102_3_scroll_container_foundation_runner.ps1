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
$proofName     = "phase102_3_scroll_container_foundation_$timestamp"
$stageRoot     = Join-Path $workspaceRoot ("_artifacts/runtime/" + $proofName)
$zipPath       = Join-Path $proofRoot ($proofName + '.zip')
$proofPathRelative = "_proof/$proofName.zip"

$checksFile  = Join-Path $stageRoot '90_scroll_container_foundation_checks.txt'
$contractFile = Join-Path $stageRoot '99_contract_summary.txt'
$buildOut    = Join-Path $stageRoot '__build_stdout.txt'
$runOut      = Join-Path $stageRoot '__run_stdout.txt'

$planPath = Join-Path $workspaceRoot 'build_graph/debug/ngksbuildcore_plan.json'
$exePath  = Join-Path $workspaceRoot 'build/debug/bin/desktop_file_tool.exe'

New-Item -ItemType Directory -Path $proofRoot  -Force | Out-Null
New-Item -ItemType Directory -Path $stageRoot  -Force | Out-Null

# Remove any prior phase102_3 zips so exactly-one rule is enforceable.
Get-ChildItem -LiteralPath $proofRoot -Filter 'phase102_3_scroll_container_foundation_*.zip' -ErrorAction SilentlyContinue |
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

# ── Source-level audit: verify scroll_container.hpp exists ────────────────────
$scrollHeaderPath = Join-Path $workspaceRoot 'engine/ui/scroll_container.hpp'
if (-not (Test-Path -LiteralPath $scrollHeaderPath)) {
  throw 'scroll_container.hpp missing from engine/ui/'
}

$scrollHeaderText = Get-Content -LiteralPath $scrollHeaderPath -Raw
$scrollCreatedInHeader =
  ($scrollHeaderText -match 'class ScrollContainer') -and
  ($scrollHeaderText -match 'on_mouse_wheel') -and
  ($scrollHeaderText -match 'set_clip_rect') -and
  ($scrollHeaderText -match 'scroll_offset_y') -and
  ($scrollHeaderText -match 'content_height')

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

# ── Parse PHASE102_3 markers ───────────────────────────────────────────────────
$scrollCreatedRuntime   = Test-LinePresent -Text $runText -Pattern '^phase102_3_scroll_container_created=1$'
$verticalScrollWorks    = Test-LinePresent -Text $runText -Pattern '^phase102_3_vertical_scroll_supported=1$'
$clippingSupported      = Test-LinePresent -Text $runText -Pattern '^phase102_3_clipping_supported=1$'
$mouseWheelSupported    = Test-LinePresent -Text $runText -Pattern '^phase102_3_mouse_wheel_supported=1$'
$layoutIntegrationWorks = Test-LinePresent -Text $runText -Pattern '^phase102_3_layout_integration_working=1$'

# ── Parse PHASE102_2 regression markers ───────────────────────────────────────
$nestedLayoutsOk    = Test-LinePresent -Text $runText -Pattern '^phase102_2_nested_layouts_supported=1$'
$minimumSizeOk      = Test-LinePresent -Text $runText -Pattern '^phase102_2_minimum_size_enforced=1$'
$fillWeightOk       = Test-LinePresent -Text $runText -Pattern '^phase102_2_fill_weight_behavior=1$'
$predictableResizeOk = Test-LinePresent -Text $runText -Pattern '^phase102_2_predictable_resize_behavior=1$'
$noCrash            = (Test-LinePresent -Text $runText -Pattern '^app_runtime_crash_detected=0$') -and
                      (Test-LinePresent -Text $runText -Pattern '^runtime_final_status=RUN_OK$')
$summaryPass        = Test-LinePresent -Text $runText -Pattern '^SUMMARY: PASS$'

# Extract numeric values for the contract file.
$scrollOffset   = if ($runText -match '(?m)^phase102_3_scroll_offset=(\d+)$')    { $matches[1] } else { '0' }
$contentHeight  = if ($runText -match '(?m)^phase102_3_content_height=(\d+)$')   { $matches[1] } else { '0' }
$viewportHeight = if ($runText -match '(?m)^phase102_3_viewport_height=(\d+)$')  { $matches[1] } else { '0' }
$wheelCount     = if ($runText -match '(?m)^phase102_3_wheel_event_count=(\d+)$') { $matches[1] } else { '0' }

$noRegressions =
  $nestedLayoutsOk -and $minimumSizeOk -and $fillWeightOk -and $predictableResizeOk -and $noCrash -and $summaryPass

$scrollCreated = $scrollCreatedInHeader -and $scrollCreatedRuntime

$phaseStatus = if (
  $scrollCreated -and $verticalScrollWorks -and $clippingSupported -and
  $mouseWheelSupported -and $layoutIntegrationWorks -and $noRegressions
) { 'PASS' } else { 'FAIL' }

$newRegressionsDetected = if ($noRegressions) { 'No' } else { 'Yes' }

# ── Write 90_scroll_container_foundation_checks.txt ───────────────────────────
$changesIntroduced = 'scroll_container_hpp_added_to_engine_ui;clip_rect_api_added_to_d3d11_renderer;mouse_wheel_routing_added_to_input_router;desktop_file_tool_detail_panel_now_scrollable_with_15_item_content'

$checksLines = @(
  "scroll_container_created=$(if ($scrollCreated) { 'YES' } else { 'NO' })",
  "vertical_scroll_supported=$(if ($verticalScrollWorks) { 'YES' } else { 'NO' })",
  "clipping_supported=$(if ($clippingSupported) { 'YES' } else { 'NO' })",
  "mouse_wheel_supported=$(if ($mouseWheelSupported) { 'YES' } else { 'NO' })",
  "layout_integration_working=$(if ($layoutIntegrationWorks) { 'YES' } else { 'NO' })",
  "changes_introduced=$changesIntroduced",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$checksLines | Out-File -FilePath $checksFile -Encoding UTF8 -Force

# ── Write 99_contract_summary.txt ─────────────────────────────────────────────
$contractLines = @(
  "scroll_container_created=$(if ($scrollCreated) { 'YES' } else { 'NO' })",
  "vertical_scroll_supported=$(if ($verticalScrollWorks) { 'YES' } else { 'NO' })",
  "clipping_supported=$(if ($clippingSupported) { 'YES' } else { 'NO' })",
  "mouse_wheel_supported=$(if ($mouseWheelSupported) { 'YES' } else { 'NO' })",
  "layout_integration_working=$(if ($layoutIntegrationWorks) { 'YES' } else { 'NO' })",
  "scroll_offset_after_wheel=$scrollOffset",
  "content_height=$contentHeight",
  "viewport_height=$viewportHeight",
  "wheel_events=$wheelCount",
  "changes_introduced=$changesIntroduced",
  "new_regressions_detected=$newRegressionsDetected",
  "phase_status=$phaseStatus",
  "proof_folder=$proofPathRelative"
)
$contractLines | Out-File -FilePath $contractFile -Encoding UTF8 -Force

if (-not (Test-KvFileWellFormed -FilePath $checksFile)) {
  throw '90_scroll_container_foundation_checks.txt is malformed'
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
  Where-Object { $_.Name -like 'phase102_3_scroll_container_foundation_*' })
if ($phaseArtifacts.Count -ne 1 -or $phaseArtifacts[0].Name -ne ($proofName + '.zip')) {
  throw 'packaging rule violated: expected exactly one phase102_3 artifact'
}

# ── Final console output ───────────────────────────────────────────────────────
Write-Host ("scroll_container_created=$(if ($scrollCreated) { 'YES' } else { 'NO' })")
Write-Host ("vertical_scroll_supported=$(if ($verticalScrollWorks) { 'YES' } else { 'NO' })")
Write-Host ("clipping_supported=$(if ($clippingSupported) { 'YES' } else { 'NO' })")
Write-Host ("mouse_wheel_supported=$(if ($mouseWheelSupported) { 'YES' } else { 'NO' })")
Write-Host ("layout_integration_working=$(if ($layoutIntegrationWorks) { 'YES' } else { 'NO' })")
Write-Host ("changes_introduced=$changesIntroduced")
Write-Host ("new_regressions_detected=$newRegressionsDetected")
Write-Host ("phase_status=$phaseStatus")
Write-Host ("proof_folder=$proofPathRelative")

if ($phaseStatus -ne 'PASS') {
  exit 1
}

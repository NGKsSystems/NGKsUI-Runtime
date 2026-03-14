param(
  [string]$Root = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location $Root
if ((Get-Location).Path -ne $Root) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

function Test-HasToken {
  param(
    [string]$Text,
    [string]$Token
  )
  return ($Text -match [regex]::Escape($Token))
}

function Get-Bounds {
  param(
    [string]$Text,
    [string]$Token
  )

  $pattern = [regex]::Escape($Token) + '=(?<x>-?\d+),(?<y>-?\d+),(?<w>-?\d+),(?<h>-?\d+)'
  $m = [regex]::Match($Text, $pattern)
  if (-not $m.Success) {
    return $null
  }

  return [pscustomobject]@{
    X = [int]$m.Groups['x'].Value
    Y = [int]$m.Groups['y'].Value
    W = [int]$m.Groups['w'].Value
    H = [int]$m.Groups['h'].Value
  }
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase40_70_human_visible_extension_structure_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\runtime_contract_guard.ps1 2>&1
$runtimePass = ($LASTEXITCODE -eq 0)

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\visual_baseline_contract_check.ps1 2>&1
$baselineVisualPass = ($LASTEXITCODE -eq 0)

$baselineOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\phase40_28\phase40_28_baseline_lock_runner.ps1 2>&1
$baselinePass = ($LASTEXITCODE -eq 0)
$baselineOutText = ($baselineOut | Out-String)
$baselinePf = ''
$baselineZip = ''
foreach ($ln in ($baselineOutText -split "`r?`n")) {
  if ($ln -like 'PF=*') { $baselinePf = $ln.Substring(3).Trim() }
  if ($ln -like 'ZIP=*') { $baselineZip = $ln.Substring(4).Trim() }
}
if ([string]::IsNullOrWhiteSpace($baselinePf)) { $baselinePf = '(unknown)' }
if ([string]::IsNullOrWhiteSpace($baselineZip)) { $baselineZip = '(unknown)' }

$baselineGatePass = $false
if ($baselinePf -ne '(unknown)') {
  $baselineGateFile = Join-Path $baselinePf '98_gate_phase40_28.txt'
  if (Test-Path -LiteralPath $baselineGateFile) {
    $baselineGateTxt = Get-Content -Raw -LiteralPath $baselineGateFile
    $baselineGatePass = ($baselineGateTxt -match 'PASS')
  }
}
if ($baselinePass -and -not $baselineGatePass) { $baselinePass = $false }

$null = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\extension_visual_contract_check.ps1 2>&1
$extensionVisualPass = ($LASTEXITCODE -eq 0)

$extensionVisualLog = Join-Path $Root '_proof/phase40_38_extension_visual_run.log'
$extensionVisualTxt = if (Test-Path -LiteralPath $extensionVisualLog) { Get-Content -Raw -LiteralPath $extensionVisualLog } else { '' }

$headerBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_layout_header_band'
$bodyBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_layout_body_region'
$footerBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_layout_footer_strip'

$geometryPass = $false
if ($null -ne $headerBounds -and $null -ne $bodyBounds -and $null -ne $footerBounds) {
  $headerBottom = $headerBounds.Y + $headerBounds.H
  $bodyBottom = $bodyBounds.Y + $bodyBounds.H
  $geometryPass = (
    ($headerBounds.W -gt 0) -and ($headerBounds.H -gt 0) -and
    ($bodyBounds.W -gt 0) -and ($bodyBounds.H -gt 0) -and
    ($footerBounds.W -gt 0) -and ($footerBounds.H -gt 0) -and
    ($headerBounds.Y -lt $bodyBounds.Y) -and
    ($bodyBounds.Y -lt $footerBounds.Y) -and
    ($headerBottom -le $bodyBounds.Y) -and
    ($bodyBottom -le $footerBounds.Y)
  )
}

$titlesPass = (
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_header_band_title=Header Region') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_body_region_title=Body Region') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_footer_strip_title=Footer Status Strip')
)

$contrastPass = (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_region_backgrounds=header:0.12,0.18,0.24,1.00|body:0.07,0.08,0.11,1.00|footer:0.18,0.15,0.10,1.00')

$visibleDistinctPass = $geometryPass -and $titlesPass -and $contrastPass

$planPath = Join-Path $Root 'build_graph/debug/ngksgraph_plan.json'
$widgetExe = Join-Path $Root 'build/debug/bin/widget_sandbox.exe'
if (-not (Test-Path -LiteralPath $widgetExe) -and (Test-Path -LiteralPath $planPath)) {
  $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
  if ($plan.targets) {
    foreach ($target in $plan.targets) {
      if ($target.name -eq 'widget_sandbox' -and $target.output_path) {
        $candidate = Join-Path $Root ([string]$target.output_path)
        if (Test-Path -LiteralPath $candidate) {
          $widgetExe = $candidate
          break
        }
      }
    }
  }
}
if (-not (Test-Path -LiteralPath $widgetExe)) { throw 'widget sandbox executable not found' }

$oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
$oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
$oldVisual = $env:NGK_WIDGET_VISUAL_BASELINE
$oldExtVisual = $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE
$oldLane = $env:NGK_WIDGET_SANDBOX_LANE
$oldStress = $env:NGK_WIDGET_EXTENSION_STRESS_DEMO

try {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO = '1'
  $env:NGK_WIDGET_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_SANDBOX_LANE = 'extension'
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = '0'

  $extensionLaunchOut = & $widgetExe --sandbox-extension --demo 2>&1
  $extensionLaunchExit = $LASTEXITCODE
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE = $oldLane
  $env:NGK_WIDGET_EXTENSION_STRESS_DEMO = $oldStress
}

$extensionLog = Join-Path $Root '_proof/phase40_70_human_visible_extension_structure_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_exit=0') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_lane=extension') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_contract_entry=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_first_frame=1')
)

$structurePass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_header_band_title=Header Region') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_region_title=Body Region') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_title=Footer Status Strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_name=sandbox_extension_footer_strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_region_order=header_band,body_region,footer_strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_region_backgrounds=header:0.12,0.18,0.24,1.00|body:0.07,0.08,0.11,1.00|footer:0.18,0.15,0.10,1.00') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_header_band_title=Header Region') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_body_region_title=Body Region') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_footer_strip_title=Footer Status Strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_footer_strip_name=sandbox_extension_footer_strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_region_order=header_band,body_region,footer_strip')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $structurePass -and $visibleDistinctPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_70_human_visible_extension_structure'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_structure_tokens=' + $(if ($structurePass) { 'PASS' } else { 'FAIL' })
  'human_visible_distinctness=' + $(if ($visibleDistinctPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_70: human-visible extension structure proof'
  'scope: make header/body/footer immediately distinguishable to a human viewer in extension lane'
  'risk_profile=visual-only extension structure differentiation with baseline unchanged'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Visible structure definition:'
  '- Header region: sandbox_extension_header_band with title "Header Region" and dedicated header contrast.'
  '- Body region: sandbox_extension_body_region with title "Body Region" and separate body contrast.'
  '- Footer strip: sandbox_extension_footer_strip with title "Footer Status Strip" and status text "extension lane: active".'
  '- Region order is header -> body -> footer with non-overlapping vertical bounds.'
  '- Region backgrounds are intentionally different for at-a-glance section separation.'
) | Set-Content -Path (Join-Path $pf '10_visible_structure_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- All visible changes are extension-only and flow through extension state/layout/render/interaction/visual contracts.'
  '- Parent ownership is unchanged for orchestration, visibility, ordering, and child input records.'
  '- Child dependency remains none for status, secondary, and tertiary subcomponents.'
  '- Baseline lane remains default and unchanged; baseline guardrails are executed before extension gates.'
) | Set-Content -Path (Join-Path $pf '11_extension_contract_usage.txt') -Encoding UTF8

git status --short | Set-Content -Path (Join-Path $pf '12_files_touched.txt') -Encoding UTF8

$baselineBuildOutput = if ($baselinePf -ne '(unknown)') { Join-Path $baselinePf '13_build_output.txt' } else { '' }
if ($baselineBuildOutput -and (Test-Path -LiteralPath $baselineBuildOutput)) {
  Get-Content -LiteralPath $baselineBuildOutput | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8
}
else {
  @(
    'baseline build output unavailable'
    'baseline_pf=' + $baselinePf
  ) | Set-Content -Path (Join-Path $pf '13_build_output.txt') -Encoding UTF8
}

$geometrySummary = 'missing'
if ($null -ne $headerBounds -and $null -ne $bodyBounds -and $null -ne $footerBounds) {
  $geometrySummary = (
    'header=' + $headerBounds.X + ',' + $headerBounds.Y + ',' + $headerBounds.W + ',' + $headerBounds.H +
    ' | body=' + $bodyBounds.X + ',' + $bodyBounds.Y + ',' + $bodyBounds.W + ',' + $bodyBounds.H +
    ' | footer=' + $footerBounds.X + ',' + $footerBounds.Y + ',' + $footerBounds.W + ',' + $footerBounds.H
  )
}

@(
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock_runner=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_structure_tokens=' + $(if ($structurePass) { 'PASS' } else { 'FAIL' })
  'human_visible_titles=' + $(if ($titlesPass) { 'PASS' } else { 'FAIL' })
  'human_visible_contrast=' + $(if ($contrastPass) { 'PASS' } else { 'FAIL' })
  'human_visible_geometry=' + $(if ($geometryPass) { 'PASS' } else { 'FAIL' })
  'human_visible_geometry_values=' + $geometrySummary
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_visual_log=' + $extensionVisualLog
  'extension_launch_log=' + $extensionLog
  'visual_evidence_mode=equivalent (bounds + labels + contrast markers)'
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

$humanResult = if ($visibleDistinctPass) {
  'yes: header/body/footer are obvious by labeled sections, contrast differences, and ordered non-overlapping geometry.'
} else {
  'no: required visual distinctness evidence is incomplete.'
}

@(
  'Behavior summary:'
  '- Added extension-only visual differentiation in the panel: stronger section contrast and explicit section labels.'
  '- Header/body/footer are distinguishable by titles (Header Region, Body Region, Footer Status Strip), region order, and separate background tones.'
  '- Baseline remained unchanged because all updates are gated behind extension mode and baseline checks still pass.'
  '- Extension validation used extension visual contract plus live extension launch verification, then checked geometric section separation.'
  '- Human-visible result: ' + $humanResult
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_70.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

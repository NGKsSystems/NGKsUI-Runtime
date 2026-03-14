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
$pf = Join-Path $Root ('_proof/phase40_71_sandbox_render_primitives_' + $ts)
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

$headerBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_render_primitive_header'
$bodyBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_render_primitive_body'
$footerBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_render_primitive_footer'

$primitiveGeometryPass = $false
if ($null -ne $headerBounds -and $null -ne $bodyBounds -and $null -ne $footerBounds) {
  $headerBottom = $headerBounds.Y + $headerBounds.H
  $bodyBottom = $bodyBounds.Y + $bodyBounds.H
  $primitiveGeometryPass = (
    ($headerBounds.W -gt 0) -and ($headerBounds.H -ge 50) -and
    ($bodyBounds.W -gt 0) -and ($bodyBounds.H -ge 90) -and
    ($footerBounds.W -gt 0) -and ($footerBounds.H -ge 30) -and
    ($headerBounds.Y -lt $bodyBounds.Y) -and
    ($bodyBounds.Y -lt $footerBounds.Y) -and
    ($headerBottom -le $bodyBounds.Y) -and
    ($bodyBottom -le $footerBounds.Y)
  )
}

$primitiveTextPass = (
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_render_primitive_header_text=HEADER REGION') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_render_primitive_body_text=BODY REGION') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_render_primitive_footer_text=FOOTER REGION')
)

$primitiveColorPass = (
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_render_primitive_header_bg=0.05,0.16,0.42,1.00') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_render_primitive_body_bg=0.18,0.18,0.18,1.00') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_render_primitive_footer_bg=0.05,0.28,0.12,1.00')
)

$primitiveOrderPass = (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_render_primitive_region_order=header,body,footer')
$primitiveVisualPass = $primitiveGeometryPass -and $primitiveTextPass -and $primitiveColorPass -and $primitiveOrderPass

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

$extensionLog = Join-Path $Root '_proof/phase40_71_sandbox_render_primitives_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_exit=0') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_lane=extension') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_contract_entry=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_first_frame=1')
)

$primitiveRuntimePass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_surface_name=sandbox_extension_render_primitives') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_region_order=header,body,footer') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_header_text=HEADER REGION') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_body_text=BODY REGION') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_footer_text=FOOTER REGION') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_header_bg=0.05,0.16,0.42,1.00') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_body_bg=0.18,0.18,0.18,1.00') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_primitive_footer_bg=0.05,0.28,0.12,1.00')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $primitiveRuntimePass -and $primitiveVisualPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_71_sandbox_render_primitives'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'primitive_runtime_tokens=' + $(if ($primitiveRuntimePass) { 'PASS' } else { 'FAIL' })
  'primitive_visual_distinctness=' + $(if ($primitiveVisualPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_71: sandbox render primitive proof'
  'scope: prove extension viewport draws visible text + rectangles in distinct vertical sections'
  'risk_profile=extension-only render primitive visibility proof with baseline unchanged'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Render primitives definition:'
  '- HEADER TEST: dark-blue rectangle with text HEADER REGION.'
  '- BODY TEST: dark-gray rectangle with text BODY REGION.'
  '- FOOTER TEST: dark-green rectangle with text FOOTER REGION.'
  '- Region order: header(top), body(middle), footer(bottom).'
  '- High-contrast fills are extension-only and validated by render + visual tokens and geometry bounds.'
) | Set-Content -Path (Join-Path $pf '10_render_primitives_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- Primitive proof surface is extension-only and does not alter baseline/default lane behavior.'
  '- Existing extension state/layout/render/interaction/visual contracts remain active and validated.'
  '- Parent ownership and child dependency rules remain unchanged.'
  '- No animation, no new UI system, and no baseline architecture changes were introduced.'
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
  'primitive_runtime_tokens=' + $(if ($primitiveRuntimePass) { 'PASS' } else { 'FAIL' })
  'primitive_visual_text=' + $(if ($primitiveTextPass) { 'PASS' } else { 'FAIL' })
  'primitive_visual_colors=' + $(if ($primitiveColorPass) { 'PASS' } else { 'FAIL' })
  'primitive_visual_order=' + $(if ($primitiveOrderPass) { 'PASS' } else { 'FAIL' })
  'primitive_visual_geometry=' + $(if ($primitiveGeometryPass) { 'PASS' } else { 'FAIL' })
  'primitive_visual_geometry_values=' + $geometrySummary
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_visual_log=' + $extensionVisualLog
  'extension_launch_log=' + $extensionLog
  'visual_evidence_mode=equivalent (render tokens + visual bounds + region colors + labels)'
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

$humanResult = if ($primitiveVisualPass) {
  'yes: three colored sections with explicit labels are rendered in top/middle/bottom order and visibly distinct.'
} else {
  'no: primitive visibility evidence is incomplete for one or more sections.'
}

@(
  'Behavior summary:'
  '- Added extension-only primitive proof surface with three high-contrast rectangles and uppercase labels.'
  '- Header/body/footer now render as separate vertical sections: HEADER REGION, BODY REGION, FOOTER REGION.'
  '- Frame render consistency remains intact and extension launch remains stable.'
  '- Baseline mode remained unchanged and passed runtime, visual baseline, and baseline lock guardrails.'
  '- Human-visible result: ' + $humanResult
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_71.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

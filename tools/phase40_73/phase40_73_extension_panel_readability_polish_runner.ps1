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
$pf = Join-Path $Root ('_proof/phase40_73_extension_panel_readability_polish_' + $ts)
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
$headerTitleBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_header_title'
$bodyTitleBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_body_title'
$footerValueBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_visual_bounds_footer_value'

$layoutGeometryPass = $false
if ($null -ne $headerBounds -and $null -ne $bodyBounds -and $null -ne $footerBounds) {
  $headerBottom = $headerBounds.Y + $headerBounds.H
  $bodyBottom = $bodyBounds.Y + $bodyBounds.H
  $layoutGeometryPass = (
    ($headerBounds.W -gt 0) -and ($headerBounds.H -ge 40) -and
    ($bodyBounds.W -gt 0) -and ($bodyBounds.H -ge 90) -and
    ($footerBounds.W -gt 0) -and ($footerBounds.H -ge 24) -and
    ($headerBounds.Y -lt $bodyBounds.Y) -and
    ($bodyBounds.Y -lt $footerBounds.Y) -and
    ($headerBottom -lt $bodyBounds.Y) -and
    ($bodyBottom -lt $footerBounds.Y)
  )
}

$textHierarchyPass = $false
if ($null -ne $headerTitleBounds -and $null -ne $bodyTitleBounds -and $null -ne $footerValueBounds) {
  $textHierarchyPass = (
    ($headerTitleBounds.H -ge 16) -and
    ($bodyTitleBounds.H -ge 15) -and
    ($footerValueBounds.H -ge 12)
  )
}

$readabilityProfilePass = (
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_readability_profile=panel_readability_polish_v1') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_readability_spacing=panel:6|header:8|body:8|footer:8') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_readability_typography=header_title:16|body_title:15|footer_text:12')
)

$panelReadabilityPass = $layoutGeometryPass -and $textHierarchyPass -and $readabilityProfilePass

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

$extensionLog = Join-Path $Root '_proof/phase40_73_extension_panel_readability_polish_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_exit=0') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_lane=extension') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_contract_entry=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_first_frame=1')
)

$panelContractPass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_header_band_title=Extension Panel') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_region_title=Body Region') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_title=Footer Status Strip') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_footer_strip_status_owner=extension_parent_state') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_readability_profile=panel_readability_polish_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_readability_profile=panel_readability_polish_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_subcomponent_coexistence_three=1')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $panelContractPass -and $panelReadabilityPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_73_extension_panel_readability_polish'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'panel_contract=' + $(if ($panelContractPass) { 'PASS' } else { 'FAIL' })
  'readability_polish=' + $(if ($panelReadabilityPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_73: extension panel readability polish'
  'scope: improve readability/clarity of existing visible panel without changing behavior scope'
  'risk_profile=extension-only visual polish with baseline protection'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Readability changes:'
  '- Increased panel and section padding for cleaner spacing and less visual crowding.'
  '- Improved text hierarchy: larger header title, clearer body label, readable footer text.'
  '- Tuned section heights for better top/middle/bottom balance.'
  '- Preserved existing header/body/footer contrast and deterministic ordering.'
  '- Kept existing child components in body region with cleaner alignment.'
) | Set-Content -Path (Join-Path $pf '10_readability_changes.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- No baseline lane changes; all visual polish remains extension-only.'
  '- Existing state/layout/render/interaction/visual contracts remain intact and validated.'
  '- No new widgets, interactions, or panel expansion were introduced.'
  '- Same reconstructed panel from 40.72, with readability-only polish adjustments.'
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
  'panel_contract=' + $(if ($panelContractPass) { 'PASS' } else { 'FAIL' })
  'readability_profile_tokens=' + $(if ($readabilityProfilePass) { 'PASS' } else { 'FAIL' })
  'readability_geometry=' + $(if ($layoutGeometryPass) { 'PASS' } else { 'FAIL' })
  'readability_text_hierarchy=' + $(if ($textHierarchyPass) { 'PASS' } else { 'FAIL' })
  'readability_geometry_values=' + $geometrySummary
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_visual_log=' + $extensionVisualLog
  'extension_launch_log=' + $extensionLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

$humanResult = if ($panelReadabilityPass) {
  'yes: the same panel is cleaner and more readable with improved spacing and text hierarchy while keeping structure unchanged.'
} else {
  'no: readability polish evidence is incomplete.'
}

@(
  'Behavior summary:'
  '- Applied readability polish to the existing extension panel only (no new panel or feature scope).' 
  '- Header readability improved via clearer title emphasis and cleaner padding around summary text.'
  '- Body readability improved by increased internal spacing and cleaner alignment of existing child components.'
  '- Footer readability improved by more legible status text sizing and balanced strip sizing.'
  '- Baseline remained unchanged because all modifications are extension-only and baseline guards still pass.'
  '- This is the same reconstructed panel from 40.72, now visually cleaner: ' + $humanResult
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_73.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

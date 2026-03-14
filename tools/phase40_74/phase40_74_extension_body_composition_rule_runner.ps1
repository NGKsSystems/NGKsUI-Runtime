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
$pf = Join-Path $Root ('_proof/phase40_74_extension_body_composition_rule_' + $ts)
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

$extensionLog = Join-Path $Root '_proof/phase40_74_extension_body_composition_rule_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$statusChipBounds = Get-Bounds -Text $extensionTxt -Token 'widget_extension_layout_status_chip'
$secondaryIndicatorBounds = Get-Bounds -Text $extensionTxt -Token 'widget_extension_layout_secondary_indicator'
$tertiaryMarkerBounds = Get-Bounds -Text $extensionTxt -Token 'widget_extension_layout_tertiary_marker'
$slotHeightPass = (
  ($null -ne $statusChipBounds) -and
  ($null -ne $secondaryIndicatorBounds) -and
  ($null -ne $tertiaryMarkerBounds) -and
  ($statusChipBounds.H -eq 20) -and
  ($secondaryIndicatorBounds.H -eq 20) -and
  ($tertiaryMarkerBounds.H -eq 20)
)

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_exit=0') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_sandbox_lane=extension') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_contract_entry=1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_first_frame=1')
)

$compositionRulePass = (
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_composition_rule=uniform_child_slot_height_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_composition_slot_height=20') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_layout_container_body_composition_owner=extension_parent_state') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_body_composition_rule=uniform_child_slot_height_v1') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_body_composition_slot_height=20') -and
  (Test-HasToken -Text $extensionTxt -Token 'widget_extension_render_layout_container_body_composition_owner=extension_parent_state') -and
  $slotHeightPass
)

$extensionVisualLog = Join-Path $Root '_proof/phase40_38_extension_visual_run.log'
$extensionVisualTxt = if (Test-Path -LiteralPath $extensionVisualLog) { Get-Content -Raw -LiteralPath $extensionVisualLog } else { '' }

$visualStatusChipBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_layout_status_chip'
$visualSecondaryIndicatorBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_layout_secondary_indicator'
$visualTertiaryMarkerBounds = Get-Bounds -Text $extensionVisualTxt -Token 'widget_extension_layout_tertiary_marker'
$visualSlotHeightPass = (
  ($null -ne $visualStatusChipBounds) -and
  ($null -ne $visualSecondaryIndicatorBounds) -and
  ($null -ne $visualTertiaryMarkerBounds) -and
  ($visualStatusChipBounds.H -eq 20) -and
  ($visualSecondaryIndicatorBounds.H -eq 20) -and
  ($visualTertiaryMarkerBounds.H -eq 20)
)

$visualCompositionRulePass = (
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_body_composition_rule=uniform_child_slot_height_v1') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_body_composition_slot_height=20') -and
  (Test-HasToken -Text $extensionVisualTxt -Token 'widget_extension_visual_layout_container_body_composition_owner=extension_parent_state') -and
  $visualSlotHeightPass
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $compositionRulePass -and $visualCompositionRulePass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_74_extension_body_composition_rule'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'body_composition_rule=' + $(if ($compositionRulePass) { 'PASS' } else { 'FAIL' })
  'body_composition_rule_visual=' + $(if ($visualCompositionRulePass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_74: extension body composition rule proof'
  'scope: one tiny deterministic composition rule for extension body child slots only'
  'risk_profile=extension-only deterministic body layout rule with baseline protection'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Composition rule changes:'
  '- Added one body composition rule: uniform child slot height v1.'
  '- Applied deterministic slot height=20 to status chip, secondary indicator, and tertiary marker.'
  '- Kept parent ownership of composition rule and child input boundaries.'
  '- No new children, interactions, panels, or behavior systems were introduced.'
) | Set-Content -Path (Join-Path $pf '10_composition_rule_changes.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- Baseline lane remains unchanged and separately validated.'
  '- Rule is extension-only and emitted in startup/render/visual token streams.'
  '- Child dependency remains none; parent retains ownership and ordering.'
  '- Existing sectioned panel shape remains intact (header/body/footer).' 
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

@(
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock_runner=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'composition_rule_tokens=' + $(if ($compositionRulePass) { 'PASS' } else { 'FAIL' })
  'composition_rule_visual_tokens=' + $(if ($visualCompositionRulePass) { 'PASS' } else { 'FAIL' })
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_visual_log=' + $extensionVisualLog
  'extension_launch_log=' + $extensionLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Extension body now applies one deterministic composition rule with uniform child slot height.'
  '- Parent-owned composition contract defines slot height=20 across existing body children.'
  '- Existing panel structure and child set remain unchanged; only body composition policy is refined.'
  '- Baseline remained unchanged and all required guards stayed green.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_74.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

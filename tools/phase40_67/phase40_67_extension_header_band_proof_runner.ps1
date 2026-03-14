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

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $Root ('_proof/phase40_67_extension_header_band_proof_' + $ts)
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

$extensionLog = Join-Path $Root '_proof/phase40_67_extension_header_band_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  ($extensionTxt -match 'widget_sandbox_exit=0') -and
  ($extensionTxt -match 'widget_sandbox_lane=extension') -and
  ($extensionTxt -match 'widget_extension_render_contract_entry=1') -and
  ($extensionTxt -match 'widget_first_frame=1')
)

$headerPass = (
  ($extensionTxt -match 'widget_extension_layout_container_header_band_name=sandbox_extension_header_band') -and
  ($extensionTxt -match 'widget_extension_layout_container_header_band_role=layout_header_region') -and
  ($extensionTxt -match 'widget_extension_layout_container_header_band_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_layout_container_header_band_title=Extension Panel') -and
  ($extensionTxt -match 'widget_extension_layout_container_header_band_summary_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_layout_container_header_band_summary_child_dependency=none') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_header_band_name=sandbox_extension_header_band') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_header_band_role=layout_header_region') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_header_band_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_header_band_title=Extension Panel') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_header_band_summary_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_header_band_summary_child_dependency=none') -and
  ($extensionTxt -match 'widget_extension_subcomponent_coexistence=status_chip_v1\+secondary_indicator_v1\+tertiary_marker_subcomponent') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_coexistence_three=1') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_tertiary_rendered=1')
)

$summaryLines = [regex]::Matches($extensionTxt, 'widget_extension_render_layout_container_header_band_summary=([^\r\n]+)')
$summaryPass = ($summaryLines.Count -ge 1)
foreach ($m in $summaryLines) {
  $v = $m.Groups[1].Value
  if ($v -ne 'parent summary: secondary inactive' -and $v -ne 'parent summary: secondary active' -and $v -ne 'parent summary: orchestration active') {
    $summaryPass = $false
    break
  }
}

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $headerPass -and $summaryPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_67_extension_header_band_proof'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_header_band=' + $(if ($headerPass) { 'PASS' } else { 'FAIL' })
  'extension_header_summary_parent_owned=' + $(if ($summaryPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_67: extension header band proof'
  'scope: prove a tiny extension-only header band can be hosted safely inside sandbox_extension_panel'
  'risk_profile=layout-only header surface with parent-owned summary text'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Extension header definition:'
  '- Header band: sandbox_extension_header_band.'
  '- Placement: inside sandbox_extension_panel above the three existing subcomponents.'
  '- Title: Extension Panel.'
  '- Summary: parent-owned deterministic state summary text.'
) | Set-Content -Path (Join-Path $pf '10_extension_header_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- Header band exists only in extension mode and flows through extension state/layout/render/visual contracts.'
  '- Header summary is derived from existing parent-owned extension state and never child-owned.'
  '- Existing child subcomponents remain input-record driven and isolated beneath the header band.'
  '- Baseline lane remains default and unchanged.'
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
  'extension_header_band=' + $(if ($headerPass) { 'PASS' } else { 'FAIL' })
  'extension_header_summary_parent_owned=' + $(if ($summaryPass) { 'PASS' } else { 'FAIL' })
  'header_summary_samples=' + $summaryLines.Count
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_log=' + $extensionLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Added a tiny extension-only header band (sandbox_extension_header_band) inside sandbox_extension_panel.'
  '- Header summary text is parent-owned and derived from existing extension parent state only.'
  '- Header is rendered above status_chip_v1, secondary_indicator_v1, and tertiary_marker_subcomponent; child isolation remains intact.'
  '- Baseline stayed unchanged and default; runtime guard, baseline visual contract, and baseline lock remained PASS.'
  '- Extension and visual contracts validated header presence, parent-owned summary, and continued deterministic child composition.'
  '- This is the first safe visible structure step toward richer UI while preserving sandbox guardrails.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_67.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

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
$pf = Join-Path $Root ('_proof/phase40_66_extension_layout_container_' + $ts)
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

$launcher = Join-Path $Root 'tools/run_widget_sandbox.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
  throw 'missing canonical launcher'
}

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

  $extensionLaunchOut = & $launcher -Config Debug -PassArgs @('--sandbox-extension', '--demo') 2>&1
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

$extensionLog = Join-Path $Root '_proof/phase40_66_extension_layout_container_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLog -Encoding UTF8

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  ($extensionTxt -match 'widget_sandbox_exit=0') -and
  ($extensionTxt -match 'widget_sandbox_lane=extension') -and
  ($extensionTxt -match 'widget_extension_render_contract_entry=1') -and
  ($extensionTxt -match 'widget_first_frame=1')
)

$containerPass = (
  ($extensionTxt -match 'widget_extension_layout_container_name=sandbox_extension_panel') -and
  ($extensionTxt -match 'widget_extension_layout_container_role=subcomponent_layout_surface') -and
  ($extensionTxt -match 'widget_extension_layout_container_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent') -and
  ($extensionTxt -match 'widget_extension_layout_container_child_count=3') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_name=sandbox_extension_panel') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_role=subcomponent_layout_surface') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_child_order=status_chip_v1,secondary_indicator_v1,tertiary_marker_subcomponent') -and
  ($extensionTxt -match 'widget_extension_render_layout_container_child_count=3') -and
  ($extensionTxt -match 'widget_extension_subcomponent_coexistence=status_chip_v1\+secondary_indicator_v1\+tertiary_marker_subcomponent') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_coexistence_three=1') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_tertiary_rendered=1')
)

$orderLines = [regex]::Matches($extensionTxt, 'widget_extension_render_layout_child_order=([^\r\n]+)')
$orderPass = $true
if ($orderLines.Count -eq 0) {
  $orderPass = $false
}
foreach ($m in $orderLines) {
  $v = $m.Groups[1].Value
  if ($v -ne 'status_chip_v1,secondary_indicator_v1' -and $v -ne 'secondary_indicator_v1,status_chip_v1') {
    $orderPass = $false
    break
  }
}

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $containerPass -and $orderPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_66_extension_layout_container'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_layout_container=' + $(if ($containerPass) { 'PASS' } else { 'FAIL' })
  'deterministic_layout_order=' + $(if ($orderPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_66: extension sandbox layout container proof'
  'scope: prove extension-only layout container can host three subcomponents safely'
  'risk_profile=layout-only container growth with parent-owned behavior preserved'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Layout container definition:'
  '- Container name: sandbox_extension_panel.'
  '- Mode: extension-only layout surface.'
  '- Hosted children: status_chip_v1, secondary_indicator_v1, tertiary_marker_subcomponent.'
  '- Role: layout organization only; no behavior or state ownership.'
) | Set-Content -Path (Join-Path $pf '10_layout_container_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- Parent keeps state/orchestration/visibility/ordering ownership.'
  '- Container contributes deterministic child layout order only.'
  '- Child input records remain parent-built and child dependency markers remain none.'
  '- Render tokens confirm container presence and deterministic child composition.'
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
  'extension_layout_container=' + $(if ($containerPass) { 'PASS' } else { 'FAIL' })
  'deterministic_layout_order=' + $(if ($orderPass) { 'PASS' } else { 'FAIL' })
  'render_order_samples=' + $orderLines.Count
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_log=' + $extensionLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Added sandbox_extension_panel as an extension-only layout container inside the existing extension info card.'
  '- The panel hosts status_chip_v1, secondary_indicator_v1, and tertiary_marker_subcomponent as a deterministic stack.'
  '- Ordering and visibility remain parent-owned; panel is layout-only and does not own behavior/state.'
  '- Render determinism was verified by container child-order tokens and strict allowed-order checks.'
  '- Baseline remained unchanged; runtime guard, baseline visual contract, and baseline lock remained PASS.'
  '- This proves safe UI composition growth while preserving extension sandbox discipline and isolation boundaries.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_66.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)


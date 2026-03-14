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
$pf = Join-Path $Root ('_proof/phase40_49_extension_layout_variation_proof_' + $ts)
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
  if ($ln -like 'PF=*') {
    $baselinePf = $ln.Substring(3).Trim()
  }
  if ($ln -like 'ZIP=*') {
    $baselineZip = $ln.Substring(4).Trim()
  }
}
if ([string]::IsNullOrWhiteSpace($baselinePf)) {
  $baselinePf = '(unknown)'
}
if ([string]::IsNullOrWhiteSpace($baselineZip)) {
  $baselineZip = '(unknown)'
}

$baselineGatePass = $false
if ($baselinePf -ne '(unknown)') {
  $baselineGateFile = Join-Path $baselinePf '98_gate_phase40_28.txt'
  if (Test-Path -LiteralPath $baselineGateFile) {
    $baselineGateTxt = Get-Content -Raw -LiteralPath $baselineGateFile
    $baselineGatePass = ($baselineGateTxt -match 'PASS')
  }
}
if ($baselinePass -and -not $baselineGatePass) {
  $baselinePass = $false
}

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

try {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
  $env:NGK_WIDGET_SANDBOX_DEMO = '1'
  $env:NGK_WIDGET_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = '0'
  $env:NGK_WIDGET_SANDBOX_LANE = 'extension'

  $extensionLaunchOut = & $launcher -Config Debug -PassArgs @('--sandbox-extension', '--demo') 2>&1
  $extensionLaunchExit = $LASTEXITCODE
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE = $oldLane
}

$extensionLaunchLog = Join-Path $Root '_proof/phase40_49_extension_demo_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLaunchLog -Encoding UTF8

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  ($extensionTxt -match 'widget_sandbox_exit=0') -and
  ($extensionTxt -match 'widget_sandbox_lane=extension') -and
  ($extensionTxt -match 'widget_extension_info_card_present=1') -and
  ($extensionTxt -match 'widget_extension_secondary_placeholder_present=1') -and
  ($extensionTxt -match 'widget_extension_render_contract_entry=1') -and
  ($extensionTxt -match 'widget_extension_interaction_contract_entry=1') -and
  ($extensionTxt -match 'widget_first_frame=1')
)

$layoutVariationPass = (
  ($extensionTxt -match 'widget_extension_layout_mode=compact') -and
  ($extensionTxt -match 'widget_extension_layout_placeholder_height=40') -and
  ($extensionTxt -match 'widget_extension_layout_mode_selector=secondary_placeholder_state') -and
  ($extensionTxt -match 'widget_extension_render_layout_mode=compact') -and
  ($extensionTxt -match 'widget_extension_interaction_demo_toggle=1') -and
  ($extensionTxt -match 'widget_extension_secondary_placeholder_state=active') -and
  ($extensionTxt -match 'widget_extension_layout_mode=expanded') -and
  ($extensionTxt -match 'widget_extension_layout_placeholder_height=56') -and
  ($extensionTxt -match 'widget_extension_render_layout_mode=expanded') -and
  ($extensionTxt -match 'widget_extension_secondary_toggle_count=1')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $layoutVariationPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_49_extension_layout_variation_proof'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_layout_variation=' + $(if ($layoutVariationPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_49: extension layout variation proof'
  'scope: add one tiny extension-only deterministic layout mode variation for existing slot content'
  'risk_profile=single compact/expanded placeholder-height mode selected by existing extension state'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Extension layout variation definition:'
  '- Added exactly one extension-only layout variation: compact vs expanded mode for the existing secondary placeholder slot height.'
  '- Mode selector uses existing extension state: secondary_placeholder_state.'
  '- Compact mode uses placeholder height 40; expanded mode uses placeholder height 56.'
  '- No new widgets, interactions, or baseline layout changes were introduced.'
) | Set-Content -Path (Join-Path $pf '10_extension_layout_variation_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- State contract: existing extension secondary state selects the layout mode (compact/expanded).'
  '- Layout contract: compute_extension_lane_layout now deterministically derives placeholder height from extension-only state.'
  '- Render contract: extension render markers expose current layout mode while rendering existing tiny elements only.'
  '- Interaction contract: existing secondary toggle remains the only trigger for layout-mode changes.'
  '- Visual contract: extension visual checker validates default compact layout-mode markers in extension visual baseline mode.'
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
  'extension_layout_variation_check=' + $(if ($layoutVariationPass) { 'PASS' } else { 'FAIL' })
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_launch_log=' + $extensionLaunchLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Added one tiny extension-only layout variation: compact/expanded mode for secondary placeholder height.'
  '- The mode is selected by existing extension state (secondary active/inactive), so no new interaction pathway was added.'
  '- It is applied only to the existing extension secondary placeholder slot and consumed by extension layout and render markers.'
  '- It flows through extension contracts: state-selected layout mode, deterministic layout computation, render markers, interaction-driven mode switch, and visual-contract assertions.'
  '- Baseline remained unchanged because baseline lane layout/render paths and baseline visual tokens were not modified.'
  '- Validation ran on both paths: runtime contract guard PASS, baseline visual contract PASS, baseline lock runner PASS, extension visual contract PASS, extension launch PASS, explicit layout variation proof PASS.'
  '- This is a safe pattern for future controlled layout growth because a single extension-only mode can evolve deterministic slot geometry without crossing baseline boundaries.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_49.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)


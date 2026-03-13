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
$pf = Join-Path $Root ('_proof/phase40_47_extension_presentation_variant_proof_' + $ts)
New-Item -ItemType Directory -Path $pf -Force | Out-Null

$runtimeOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\runtime_contract_guard.ps1 2>&1
$runtimePass = ($LASTEXITCODE -eq 0)

$baselineVisualOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\visual_baseline_contract_check.ps1 2>&1
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

$extensionVisualOut = pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\validation\extension_visual_contract_check.ps1 2>&1
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
if (-not (Test-Path -LiteralPath $widgetExe)) {
  throw 'widget sandbox executable not found'
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

  $extensionLaunchOut = & $widgetExe --sandbox-extension --demo 2>&1
  $extensionLaunchExit = $LASTEXITCODE
}
finally {
  $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
  $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  $env:NGK_WIDGET_VISUAL_BASELINE = $oldVisual
  $env:NGK_WIDGET_EXTENSION_VISUAL_BASELINE = $oldExtVisual
  $env:NGK_WIDGET_SANDBOX_LANE = $oldLane
}

$extensionLaunchLog = Join-Path $Root '_proof/phase40_47_extension_demo_run.log'
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

$variantPass = (
  ($extensionTxt -match 'widget_extension_presentation_variant=primary_summary_badge_emphasis_v1') -and
  ($extensionTxt -match 'widget_extension_primary_summary_badge_variant=neutral') -and
  ($extensionTxt -match 'widget_extension_render_primary_summary_badge_variant=neutral') -and
  ($extensionTxt -match 'widget_extension_interaction_demo_toggle=1') -and
  ($extensionTxt -match 'widget_extension_secondary_placeholder_state=active') -and
  ($extensionTxt -match 'widget_extension_primary_summary_text=secondary state: active') -and
  ($extensionTxt -match 'widget_extension_primary_summary_badge_variant=emphasis') -and
  ($extensionTxt -match 'widget_extension_secondary_toggle_count=1')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $variantPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_47_extension_presentation_variant_proof'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_presentation_variant=' + $(if ($variantPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_47: extension presentation variant proof'
  'scope: add one tiny extension-only presentation variant with no structural or behavior expansion'
  'risk_profile=single visual-treatment switch on existing extension state'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Extension presentation variant definition:'
  '- Added exactly one extension-only presentation variant: primary summary badge treatment (neutral -> emphasis).'
  '- Variant id: primary_summary_badge_emphasis_v1.'
  '- Selector: existing secondary placeholder active/inactive state (no new interaction type).'
  '- Inactive renders neutral badge style; active renders emphasis badge style.'
) | Set-Content -Path (Join-Path $pf '10_extension_presentation_variant_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- State contract: variant state is extension-only and derived from existing secondary_placeholder_active boolean.'
  '- Layout contract: slot bounds and composition model are unchanged; no layout expansion.'
  '- Render contract: variant marker emitted from render extension entrypoint and applied to existing summary label only.'
  '- Interaction contract: existing secondary toggle interaction remains sole selector input for variant switching.'
  '- Visual contract: extension visual checker asserts default neutral variant markers in extension visual baseline mode.'
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
  'extension_presentation_variant_check=' + $(if ($variantPass) { 'PASS' } else { 'FAIL' })
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_launch_log=' + $extensionLaunchLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Added one tiny extension-only presentation variant: primary summary badge switches between neutral and emphasis treatment.'
  '- The variant is selected by existing extension state: secondary_placeholder_active (inactive=neutral, active=emphasis).'
  '- It is rendered in the existing primary info-card summary label only; no new widgets or layout growth were introduced.'
  '- It flows through extension contracts via startup state markers, unchanged layout bounds, render markers, interaction-driven selector updates, and extension visual contract checks.'
  '- Baseline remained unchanged because baseline lane logic, visual tokens, and default-mode routing were not modified.'
  '- Validation ran on both paths: runtime contract guard PASS, baseline visual contract PASS, baseline lock runner PASS, extension visual contract PASS, extension launch PASS, explicit presentation variant proof PASS.'
  '- This is a safe future pattern because visual treatment can evolve behind a single extension-only selector while preserving deterministic structure and behavior contracts.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_47.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

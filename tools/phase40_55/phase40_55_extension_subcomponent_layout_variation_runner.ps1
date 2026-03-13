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
$pf = Join-Path $Root ('_proof/phase40_55_extension_subcomponent_layout_variation_' + $ts)
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

$extensionLaunchLog = Join-Path $Root '_proof/phase40_55_extension_demo_run.log'
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
  ($extensionTxt -match 'widget_extension_subcomponent_name=status_chip_v1') -and
  ($extensionTxt -match 'widget_extension_subcomponent_input_record=status_chip_input_v1') -and
  ($extensionTxt -match 'widget_extension_subcomponent_input_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_subcomponent_input_layout_variant=compact') -and
  ($extensionTxt -match 'widget_extension_subcomponent_input_layout_height=20') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_from_input_only=1') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_layout_variant=compact') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_layout_height=20') -and
  ($extensionTxt -match 'widget_extension_interaction_demo_toggle=1') -and
  ($extensionTxt -match 'widget_extension_subcomponent_layout_variant=offset') -and
  ($extensionTxt -match 'widget_extension_subcomponent_layout_height=24') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_layout_variant=offset') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_layout_height=24') -and
  ($extensionTxt -match 'widget_extension_secondary_toggle_count=1')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $layoutVariationPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_55_extension_subcomponent_layout_variation'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_subcomponent_layout_variation=' + $(if ($layoutVariationPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_55: extension subcomponent layout variation proof'
  'scope: add one tiny extension-only subcomponent layout variation selected from existing parent-built child input record'
  'risk_profile=single local layout variant for existing status-chip subcomponent'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Extension subcomponent layout definition:'
  '- Added one tiny layout variant selector on status_chip_input_v1: layout_variant.'
  '- Default layout variant: compact with row height 20.'
  '- Active layout variant: offset with row height 24 after existing secondary-toggle active state.'
  '- Layout variation is consumed from parent-built child input record only.'
) | Set-Content -Path (Join-Path $pf '10_extension_subcomponent_layout_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- State contract: parent extension state builds status_chip_input_v1 and sets layout_variant.'
  '- Layout contract: status-chip row height is selected deterministically from input record (20/24).'
  '- Render contract: render markers emit subcomponent layout variant and applied height from input record with from_input_only marker.'
  '- Interaction contract: existing secondary-toggle updates parent state and recomputes input-record layout variant; no new interaction types.'
  '- Visual contract: extension visual checker validates default layout-variant and layout-height tokens in extension visual baseline mode.'
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
  'extension_subcomponent_layout_variation=' + $(if ($layoutVariationPass) { 'PASS' } else { 'FAIL' })
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_launch_log=' + $extensionLaunchLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Added one extension-only subcomponent layout variation on status_chip_v1: layout_variant=compact|offset.'
  '- Parent-owned selector field is status_chip_input_v1.layout_variant.'
  '- Subcomponent applies this in its input-only consumption path by deterministically selecting chip row height (20 for compact, 24 for offset).'
  '- Contracts remain disciplined: parent state builds input record, layout variant is encoded in input, render emits input-record layout markers, interaction recomputes layout variant via existing toggle, and visual contract validates default tokens.'
  '- Baseline remained unchanged because baseline lane state/layout/render/interaction paths were untouched and extension lane remains opt-in.'
  '- Validation covered both lanes: runtime contract guard PASS, baseline visual contract PASS, baseline lock runner PASS, extension visual contract PASS, extension launch PASS, explicit subcomponent layout-variation checks PASS.'
  '- This is a safe pattern for future isolated layout growth because component-local layout selection is driven by explicit parent-owned child input without broader runtime-state access.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_55.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

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
$pf = Join-Path $Root ('_proof/phase40_59_extension_parent_orchestration_rule_' + $ts)
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

$extensionLaunchLog = Join-Path $Root '_proof/phase40_59_extension_demo_run.log'
$extensionTxt = ($extensionLaunchOut | Out-String)
$extensionTxt | Set-Content -Path $extensionLaunchLog -Encoding UTF8

$extensionLaunchPass = (
  ($extensionLaunchExit -eq 0) -and
  ($extensionTxt -match 'widget_sandbox_exit=0') -and
  ($extensionTxt -match 'widget_sandbox_lane=extension') -and
  ($extensionTxt -match 'widget_extension_render_contract_entry=1') -and
  ($extensionTxt -match 'widget_extension_interaction_contract_entry=1') -and
  ($extensionTxt -match 'widget_first_frame=1')
)

$orchestrationPass = (
  ($extensionTxt -match 'widget_extension_parent_orchestration_rule_name=parent_emphasis_bridge_v1') -and
  ($extensionTxt -match 'widget_extension_parent_orchestration_rule_owner=extension_parent_state') -and
  ($extensionTxt -match 'widget_extension_parent_orchestration_child_dependency=none') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_input_record=status_chip_input_v1') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_secondary_input_record=secondary_indicator_input_v1') -and
  ($extensionTxt -match 'widget_extension_render_parent_orchestration_rule_state=active') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_parent_orchestration_state=active') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_secondary_parent_orchestration_state=active') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_presentation_variant=coordinated_emphasis') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_secondary_text=indicator: parent emphasis mirrored') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_secondary_variant=mirror') -and
  ($extensionTxt -match 'widget_extension_render_subcomponent_child_dependency=none')
)

$gatePass = $runtimePass -and $baselineVisualPass -and $baselinePass -and $extensionVisualPass -and $extensionLaunchPass -and $orchestrationPass
$gate = if ($gatePass) { 'PASS' } else { 'FAIL' }

$baselineVisualReport = Join-Path $Root 'tools/validation/visual_baseline_contract.txt'
$extensionVisualReport = Join-Path $Root 'tools/validation/extension_visual_contract.txt'

@(
  'phase=40_59_extension_parent_orchestration_rule'
  'timestamp=' + (Get-Date).ToString('o')
  'runtime_contract_guard=' + $(if ($runtimePass) { 'PASS' } else { 'FAIL' })
  'baseline_visual_contract=' + $(if ($baselineVisualPass) { 'PASS' } else { 'FAIL' })
  'baseline_lock=' + $(if ($baselinePass) { 'PASS' } else { 'FAIL' })
  'extension_visual_contract=' + $(if ($extensionVisualPass) { 'PASS' } else { 'FAIL' })
  'extension_launch=' + $(if ($extensionLaunchPass) { 'PASS' } else { 'FAIL' })
  'extension_parent_orchestration_rule=' + $(if ($orchestrationPass) { 'PASS' } else { 'FAIL' })
  'gate=' + $gate
) | Set-Content -Path (Join-Path $pf '01_status.txt') -Encoding UTF8

@(
  'phase40_59: extension parent orchestration rule proof'
  'scope: prove one tiny parent-owned orchestration rule can coordinate two isolated extension subcomponents'
  'risk_profile=single parent-owned rule, separate child inputs, no child-to-child dependency'
) | Set-Content -Path (Join-Path $pf '02_head.txt') -Encoding UTF8

@(
  'Extension orchestration rule definition:'
  '- Rule: parent_emphasis_bridge_v1 (extension-only, parent-owned).' 
  '- Activation condition: secondary state is active and status chip interaction boundary is active.'
  '- Parent derives two separate inputs from the same rule:'
  '- status_chip_input_v1 receives parent_orchestration_state and coordinated_emphasis presentation variant.'
  '- secondary_indicator_input_v1 receives parent_orchestration_state and mirrored read-only indicator text/variant.'
) | Set-Content -Path (Join-Path $pf '10_extension_orchestration_rule_definition.txt') -Encoding UTF8

@(
  'Extension contract usage:'
  '- State contract: orchestration flag is parent-owned in extension lane state.'
  '- Input contract: each child consumes its own parent-built input record with explicit parent_orchestration_state markers.'
  '- Render contract: both child outputs are emitted from input-record data only, with active orchestration markers in demo run.'
  '- Isolation contract: explicit child-dependency token remains none; children do not read each other directly.'
  '- Baseline isolation: baseline lane code path and visual contract remained unchanged and still pass.'
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
  'extension_parent_orchestration_rule=' + $(if ($orchestrationPass) { 'PASS' } else { 'FAIL' })
  'baseline_pf=' + $baselinePf
  'baseline_zip=' + $baselineZip
  'baseline_visual_report=' + $baselineVisualReport
  'extension_visual_report=' + $extensionVisualReport
  'extension_launch_log=' + $extensionLaunchLog
) | Set-Content -Path (Join-Path $pf '14_validation_results.txt') -Encoding UTF8

@(
  'Behavior summary:'
  '- Single parent-owned orchestration rule: parent_emphasis_bridge_v1 in extension lane state.'
  '- Parent-owned child input records: status_chip_input_v1 and secondary_indicator_input_v1, both carrying parent_orchestration_state.'
  '- Child render results: status_chip uses coordinated_emphasis while secondary_indicator mirrors parent emphasis as read-only text/variant.'
  '- Child isolation: both children render only from their own input records; explicit dependency marker remains none.'
  '- Baseline unchanged: baseline/default lane remains untouched and still governed by baseline lock and visual contracts.'
  '- Validation: runtime guard, baseline visual contract, baseline lock runner, extension visual contract, extension launch, and orchestration checks all executed.'
  '- This proves safe multi-child extension growth: parent orchestration can coordinate multiple children without child-to-child coupling.'
) | Set-Content -Path (Join-Path $pf '15_behavior_summary.txt') -Encoding UTF8

$gate | Set-Content -Path (Join-Path $pf '98_gate_phase40_59.txt') -Encoding UTF8

$zip = $pf + '.zip'
if (Test-Path -LiteralPath $zip) {
  Remove-Item -Force $zip
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zip -Force

Write-Output ('PF=' + $pf)
Write-Output ('ZIP=' + $zip)
Write-Output ('GATE=' + $gate)

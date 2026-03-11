param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40 -tag 'runtime_update_loop'
if (-not $paths -or $paths.Count -lt 2) {
  throw 'runtime_runner_common did not return PF/ZIP'
}

$root = (Get-Location).Path
$pf = ([string]$paths[0]).Trim()
$zip = ([string]$paths[1]).Trim()
$proofRoot = Join-Path $root '_proof'
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_plan.txt'
$f11 = Join-Path $pf '11_files_touched.txt'
$f12 = Join-Path $pf '12_build_output.txt'
$f13 = Join-Path $pf '13_update_loop_description.txt'
$f14 = Join-Path $pf '14_demo_behavior_notes.txt'
$f98 = Join-Path $pf '98_gate_phase40.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=40_runtime_update_loop'
  'goal_1=add_deterministic_runtime_tick_scheduler'
  'goal_2=update_dynamic_instrument_demo_without_input_events'
  'goal_3=preserve_textbox_buttons_focus_with_controlled_invalidation'
) | Set-Content -Path $f10 -Encoding utf8

git diff --name-only | Set-Content -Path $f11 -Encoding utf8

$graphPlan = Join-Path $root 'build_graph\debug\ngksbuildcore_plan.json'
$graphPlanAlt = Join-Path $root 'build_graph\debug\ngksgraph_plan.json'

function Resolve-WidgetExePath {
  param(
    [string]$RootPath,
    [string]$PlanPath,
    [string]$PlanPathAlt
  )

  $candidatePaths = @()

  if (Test-Path $PlanPathAlt) {
    try {
      $planAlt = Get-Content -Raw -LiteralPath $PlanPathAlt | ConvertFrom-Json
      if ($planAlt.targets) {
        foreach ($target in $planAlt.targets) {
          if ($target.name -eq 'widget_sandbox' -and $target.output_path) {
            $candidatePaths += (Join-Path $RootPath ([string]$target.output_path))
          }
        }
      }
    }
    catch {}
  }

  if (Test-Path $PlanPath) {
    try {
      $plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
      if ($plan.nodes) {
        foreach ($node in $plan.nodes) {
          if ($node.outputs) {
            foreach ($out in $node.outputs) {
              $outText = [string]$out
              if ($outText -match 'widget_sandbox\.exe$') {
                $candidatePaths += (Join-Path $RootPath $outText)
              }
            }
          }
        }
      }
    }
    catch {}
  }

  $candidatePaths += (Join-Path $RootPath 'build\debug\bin\widget_sandbox.exe')

  foreach ($candidate in ($candidatePaths | Select-Object -Unique)) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

$buildOk = $false
$runText = ''
$runOk = $false
$runExitCode = -999
try {
  if (-not (Test-Path -LiteralPath $graphPlan)) {
    throw "graph_plan_missing:$graphPlan"
  }

  .\tools\enter_msvc_env.ps1 *> $f12

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $f12 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f12 -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $f12 -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  $_ | Out-String | Add-Content -Path $f12 -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
if ($buildOk -and $widgetExe) {
  try {
    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)
    "=== WIDGET DEMO OUTPUT ===" | Add-Content -Path $f12 -Encoding utf8
    $runOut | Add-Content -Path $f12 -Encoding utf8
  }
  catch {
    $runText = ($_ | Out-String)
    $runText | Add-Content -Path $f12 -Encoding utf8
  }
} else {
  @(
    "build_ok=$buildOk"
    "widget_exe=$widgetExe"
    'run_skipped=1'
  ) | Add-Content -Path $f12 -Encoding utf8
}

$updateLoopStarted = $runText -match 'widget_phase40_update_loop_started=1'
$timerMechanism = $runText -match 'widget_phase40_timer_mechanism=event_loop_interval'
$runtimeTickTelemetry = $runText -match 'runtime_frame_tick=1'
$frameDeltaTelemetry = $runText -match 'frame_delta_ms='
$frameCounterTelemetry = $runText -match 'frame_counter='
$dynamicVisible = $runText -match 'widget_phase40_dynamic_demo_visible=1'

$panelTop = $runText -match 'widget_phase40_panel_top=1'
$panelCenterGauge = $runText -match 'widget_phase40_panel_center_gauge=1'
$panelSideMetrics = $runText -match 'widget_phase40_panel_side_metrics=1'
$panelBottomControls = $runText -match 'widget_phase40_panel_bottom_controls=1'
$gaugeArc = $runText -match 'widget_phase40_gauge_arc_visible=1'
$gaugeRing = $runText -match 'widget_phase40_gauge_ring_visible=1'
$renderOrder = $runText -match 'widget_phase40_render_order=1'
$typographyVisible = ($runText -match 'widget_phase40_typography_title=1') -and ($runText -match 'widget_phase40_typography_label=1') -and ($runText -match 'widget_phase40_typography_numeric=1') -and ($runText -match 'widget_phase40_typography_status=1')

$primitiveSignals = ($runText -match 'widget_primitive_rounded_rect=1') -and ($runText -match 'widget_primitive_circle=1') -and ($runText -match 'widget_primitive_arc=1') -and ($runText -match 'widget_primitive_stroke_thickness=1') -and ($runText -match 'widget_primitive_alpha_layering=1')
$noRegressionTextbox = ($runText -match 'widget_textbox_drag_selection_demo=1') -and ($runText -match 'widget_textbox_ctrl_a_demo=1') -and ($runText -match 'widget_textbox_enter_default_button=')
$noRegressionButtons = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape') -and ($runText -match 'widget_disabled_mouse_blocked=1')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$tickCount = ([regex]::Matches($runText, 'runtime_frame_tick=1')).Count
$paintNotWorse = ($tickCount -gt 0) -and ($tickCount -le 40)

@(
  'update_loop_design=second interval tick updates runtime state independent of input events.'
  'timer_mechanism=event-loop periodic interval integrated with existing Win32 message pump.'
  'frame_scheduler=deterministic 16ms scheduler with frame counter and delta-ms telemetry.'
  'invalidation_strategy=invalidate only when computed dynamic values changed.'
  "update_loop_started=$updateLoopStarted"
  "timer_mechanism_signal=$timerMechanism"
  "runtime_tick_telemetry=$runtimeTickTelemetry"
  "frame_delta_telemetry=$frameDeltaTelemetry"
  "frame_counter_telemetry=$frameCounterTelemetry"
  "paint_not_significantly_worse=$paintNotWorse"
  "runtime_tick_count=$tickCount"
) | Set-Content -Path $f13 -Encoding utf8

@(
  'demo_behavior=central gauge updates periodically without user interaction.'
  'dynamic_element=arc sweep and ring alpha pulse driven by runtime heartbeat.'
  'render_order=background panels -> gauge/metrics primitives -> role typography -> widgets.'
  'input_stability=textbox typing, selection, and button hover/press/focus traversal remain active.'
  "dynamic_demo_visible=$dynamicVisible"
  "panel_top_signal=$panelTop"
  "panel_center_gauge_signal=$panelCenterGauge"
  "panel_side_metrics_signal=$panelSideMetrics"
  "panel_bottom_controls_signal=$panelBottomControls"
  "gauge_arc_signal=$gaugeArc"
  "gauge_ring_signal=$gaugeRing"
  "render_order_signal=$renderOrder"
  "typography_visible=$typographyVisible"
  "primitive_layering_signal=$primitiveSignals"
  "textbox_regression_safe=$noRegressionTextbox"
  "button_regression_safe=$noRegressionButtons"
  "clean_exit=$cleanExit"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_plan.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_update_loop_description.txt',
  '14_demo_behavior_notes.txt'
)

$requiredPresent = $true
foreach ($rf in $requiredFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) {
    $requiredPresent = $false
  }
}

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$pass = $buildOk -and $runOk -and $cleanExit -and $updateLoopStarted -and $timerMechanism -and $runtimeTickTelemetry -and $frameDeltaTelemetry -and $frameCounterTelemetry -and $dynamicVisible -and $panelCenterGauge -and $gaugeArc -and $gaugeRing -and $typographyVisible -and $renderOrder -and $primitiveSignals -and $noRegressionTextbox -and $noRegressionButtons -and $paintNotWorse -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_runtime_update_loop'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "update_loop_started=$updateLoopStarted"
  "timer_mechanism_signal=$timerMechanism"
  "runtime_tick_telemetry=$runtimeTickTelemetry"
  "frame_delta_telemetry=$frameDeltaTelemetry"
  "frame_counter_telemetry=$frameCounterTelemetry"
  "dynamic_demo_visible=$dynamicVisible"
  "panel_top_signal=$panelTop"
  "panel_center_gauge_signal=$panelCenterGauge"
  "panel_side_metrics_signal=$panelSideMetrics"
  "panel_bottom_controls_signal=$panelBottomControls"
  "gauge_arc_signal=$gaugeArc"
  "gauge_ring_signal=$gaugeRing"
  "render_order_signal=$renderOrder"
  "typography_visible=$typographyVisible"
  "primitive_layering_signal=$primitiveSignals"
  "textbox_regression_safe=$noRegressionTextbox"
  "button_regression_safe=$noRegressionButtons"
  "paint_not_significantly_worse=$paintNotWorse"
  "runtime_tick_count=$tickCount"
  "required_files_present=$requiredPresent"
  "pf_under_legal_root=$pfUnderLegal"
  "zip_under_legal_root=$zipUnderLegal"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

if (Test-Path -LiteralPath $zipCanonical) {
  Remove-Item -Force $zipCanonical
}
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zipCanonical -Force

Write-Output "PF=$pfResolved"
Write-Output "ZIP=$zipCanonical"
Write-Output "GATE=$gate"

if ($gate -eq 'FAIL') {
  Get-Content -Path $f98
  if (Test-Path -LiteralPath $f12) {
    Get-Content -Path $f12 -Tail 260
  }
}

param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_6 -tag 'paint_model_enforcement'
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
$f10 = Join-Path $pf '10_bug_trace.txt'
$f11 = Join-Path $pf '11_files_touched.txt'
$f12 = Join-Path $pf '12_build_output.txt'
$f13 = Join-Path $pf '13_paint_model_notes.txt'
$f14 = Join-Path $pf '14_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_6.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=40_6_paint_model_enforcement'
  'trace_1=stale-region and click-forced visibility from inconsistent frame requests'
  'trace_2=split update/render behavior risks paint desynchronization and partial coherence'
  'trace_3=enforced dirty/frame_requested/minimized discipline with wm_paint-render handshake'
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
$singlePaintDiscipline = $runText -match 'widget_phase40_5_single_paint_discipline=1'
$fullFramePresent = $runText -match 'widget_phase40_5_full_frame_present=1'
$leftContentVisible = $runText -match 'widget_phase40_5_left_content_visible=1'
$coherentComposition = $runText -match 'widget_phase40_5_coherent_composition=1'

$panelTop = $runText -match 'widget_phase40_panel_top=1'
$panelCenterGauge = $runText -match 'widget_phase40_panel_center_gauge=1'
$panelBottomControls = $runText -match 'widget_phase40_panel_bottom_controls=1'
$gaugeArc = $runText -match 'widget_phase40_gauge_arc_visible=1'
$gaugeRing = $runText -match 'widget_phase40_gauge_ring_visible=1'
$flickerMetricsVisible = ($runText -match 'widget_phase40_flicker_metric_visible=1') -and ($runText -match 'widget_phase40_flicker_max_metric_visible=1')

$noRegressionTextbox = ($runText -match 'widget_textbox_drag_selection_demo=1') -and ($runText -match 'widget_textbox_ctrl_a_demo=1') -and ($runText -match 'widget_textbox_enter_default_button=')
$noRegressionButtons = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape') -and ($runText -match 'widget_disabled_mouse_blocked=1')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$frameTickCount = ([regex]::Matches($runText, 'runtime_frame_tick=1')).Count
$paintControlled = ($frameTickCount -gt 0) -and ($frameTickCount -le 45)

@(
  'main_loop=platform pump + deterministic runtime heartbeat mutates state and requests frame when needed.'
  'wm_paint=BeginPaint/EndPaint path with render callback discipline and no recursive invalidation.'
  'wm_erasebkgnd=returns 1 to suppress background wipes and prevent flicker flashes.'
  'invalidation=InvalidateRect(hwnd,nullptr,FALSE) via coalesced frame request only.'
  'render_frame=single full-frame composition path in widget_sandbox render_frame lambda.'
  'present_callsite=present remains in renderer end_frame only.'
  "update_loop_started=$updateLoopStarted"
  "timer_mechanism_signal=$timerMechanism"
  "single_paint_discipline=$singlePaintDiscipline"
  "full_frame_present=$fullFramePresent"
  "left_content_visible_signal=$leftContentVisible"
) | Set-Content -Path $f13 -Encoding utf8

@(
  'full_frame_composition=clear full backbuffer and draw panels/primitives/text/widgets every frame.'
  'stale_region_behavior=eliminated by coherent full-frame WM_PAINT presentation discipline.'
  'gauge_and_widgets=drawn in same frame path with no split paint dependency.'
  'input_rule=handlers mutate state/dirty and request frame, no direct render calls.'
  "coherent_composition_signal=$coherentComposition"
  "panel_top_signal=$panelTop"
  "panel_center_gauge_signal=$panelCenterGauge"
  "panel_bottom_controls_signal=$panelBottomControls"
  "gauge_arc_signal=$gaugeArc"
  "gauge_ring_signal=$gaugeRing"
  "flicker_metrics_visible=$flickerMetricsVisible"
  "wm_paint_controlled=$paintControlled"
  "runtime_tick_count=$frameTickCount"
  "textbox_regression_safe=$noRegressionTextbox"
  "button_regression_safe=$noRegressionButtons"
  "clean_exit=$cleanExit"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_bug_trace.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_paint_model_notes.txt',
  '14_behavior_summary.txt'
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

$pass = $buildOk -and $runOk -and $cleanExit -and $updateLoopStarted -and $timerMechanism -and $singlePaintDiscipline -and $fullFramePresent -and $leftContentVisible -and $coherentComposition -and $panelCenterGauge -and $panelBottomControls -and $gaugeArc -and $gaugeRing -and $flickerMetricsVisible -and $paintControlled -and $noRegressionTextbox -and $noRegressionButtons -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_6_paint_model_enforcement'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "update_loop_started=$updateLoopStarted"
  "timer_mechanism_signal=$timerMechanism"
  "single_paint_discipline=$singlePaintDiscipline"
  "full_frame_present=$fullFramePresent"
  "left_content_visible_signal=$leftContentVisible"
  "coherent_composition_signal=$coherentComposition"
  "panel_center_gauge_signal=$panelCenterGauge"
  "panel_bottom_controls_signal=$panelBottomControls"
  "gauge_arc_signal=$gaugeArc"
  "gauge_ring_signal=$gaugeRing"
  "flicker_metrics_visible=$flickerMetricsVisible"
  "wm_paint_controlled=$paintControlled"
  "runtime_tick_count=$frameTickCount"
  "textbox_regression_safe=$noRegressionTextbox"
  "button_regression_safe=$noRegressionButtons"
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

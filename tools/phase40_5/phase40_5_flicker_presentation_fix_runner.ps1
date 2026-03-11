param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40.5 -tag 'flicker_presentation_fix'
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
$f13 = Join-Path $pf '13_render_pipeline_notes.txt'
$f14 = Join-Path $pf '14_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_5.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=40_5_flicker_presentation_fix'
  'trace_1=stale_regions_and_partial_paint_seen_without_click_invalidation'
  'trace_2=split_update_render_paths_can_desynchronize_present_and_paint'
  'trace_3=fix_moves_to_wm_paint_full_frame_with_coalesced_invalidation'
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

$timerMechanism = $runText -match 'widget_phase40_timer_mechanism=event_loop_interval'
$singlePaintDiscipline = $runText -match 'widget_phase40_5_single_paint_discipline=1'
$fullFramePresent = $runText -match 'widget_phase40_5_full_frame_present=1'
$leftContentVisible = $runText -match 'widget_phase40_5_left_content_visible=1'
$coherentComposition = $runText -match 'widget_phase40_5_coherent_composition=1'

$dynamicVisible = $runText -match 'widget_phase40_dynamic_demo_visible=1'
$gaugeAndWidgets = ($runText -match 'widget_phase40_panel_center_gauge=1') -and ($runText -match 'widget_phase40_panel_bottom_controls=1')
$flickerMetricsVisible = ($runText -match 'widget_phase40_flicker_metric_visible=1') -and ($runText -match 'widget_phase40_flicker_max_metric_visible=1')

$noRegressionTextbox = ($runText -match 'widget_textbox_drag_selection_demo=1') -and ($runText -match 'widget_textbox_ctrl_a_demo=1') -and ($runText -match 'widget_textbox_enter_default_button=')
$noRegressionButtons = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape') -and ($runText -match 'widget_disabled_mouse_blocked=1')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'wm_erasebkgnd=handled as non-erasing to prevent background flash between frames.'
  'invalidation=coalesced request_repaint from update tick and ui-tree invalidation callbacks.'
  'paint_discipline=full-frame composition executes from WM_PAINT callback only.'
  'frame_schedule=33ms deterministic heartbeat updates runtime state then requests repaint.'
  "timer_mechanism_signal=$timerMechanism"
  "single_paint_discipline=$singlePaintDiscipline"
  "full_frame_present=$fullFramePresent"
  "left_content_visible_signal=$leftContentVisible"
  "coherent_composition_signal=$coherentComposition"
) | Set-Content -Path $f13 -Encoding utf8

@(
  'stale_region_behavior=eliminated by full-client frame composition under WM_PAINT.'
  'widget_and_instrumentation=share one paint discipline and present together.'
  'gauge_cluster=still dynamic with arc/ring updates and flicker metrics.'
  'input_stability=textbox/buttons/focus traversal maintained under new paint path.'
  "dynamic_demo_visible=$dynamicVisible"
  "gauge_and_widgets_coherent=$gaugeAndWidgets"
  "flicker_metrics_visible=$flickerMetricsVisible"
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
  '13_render_pipeline_notes.txt',
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

$pass = $buildOk -and $runOk -and $cleanExit -and $timerMechanism -and $singlePaintDiscipline -and $fullFramePresent -and $leftContentVisible -and $coherentComposition -and $dynamicVisible -and $gaugeAndWidgets -and $flickerMetricsVisible -and $noRegressionTextbox -and $noRegressionButtons -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_5_flicker_presentation_fix'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "timer_mechanism_signal=$timerMechanism"
  "single_paint_discipline=$singlePaintDiscipline"
  "full_frame_present=$fullFramePresent"
  "left_content_visible_signal=$leftContentVisible"
  "coherent_composition_signal=$coherentComposition"
  "dynamic_demo_visible=$dynamicVisible"
  "gauge_and_widgets_coherent=$gaugeAndWidgets"
  "flicker_metrics_visible=$flickerMetricsVisible"
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

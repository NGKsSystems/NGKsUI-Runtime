param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 39 -tag 'instrumentation_demo'
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
$f13 = Join-Path $pf '13_instrument_layout_notes.txt'
$f14 = Join-Path $pf '14_gauge_render_description.txt'
$f98 = Join-Path $pf '98_gate_phase39.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=39_instrumentation_demo'
  'goal_1=compose_central_gauge_cluster_with_primitives'
  'goal_2=add_side_metric_panels_with_typography_roles'
  'goal_3=keep_textbox_buttons_and_status_behavior_stable'
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

$panelTop = $runText -match 'widget_phase39_panel_top=1'
$panelCenterGauge = $runText -match 'widget_phase39_panel_center_gauge=1'
$panelSideMetrics = $runText -match 'widget_phase39_panel_side_metrics=1'
$panelBottomControls = $runText -match 'widget_phase39_panel_bottom_controls=1'
$gaugeArc = $runText -match 'widget_phase39_gauge_arc_visible=1'
$gaugeRing = $runText -match 'widget_phase39_gauge_ring_visible=1'
$roleTitle = $runText -match 'widget_phase39_typography_title=1'
$roleLabel = $runText -match 'widget_phase39_typography_label=1'
$roleNumeric = $runText -match 'widget_phase39_typography_numeric=1'
$roleStatus = $runText -match 'widget_phase39_typography_status=1'
$renderOrder = $runText -match 'widget_phase39_render_order=1'

$primitiveSignals = ($runText -match 'widget_primitive_rounded_rect=1') -and ($runText -match 'widget_primitive_circle=1') -and ($runText -match 'widget_primitive_arc=1') -and ($runText -match 'widget_primitive_stroke_thickness=1') -and ($runText -match 'widget_primitive_alpha_layering=1')
$noRegressionTextbox = ($runText -match 'widget_textbox_drag_selection_demo=1') -and ($runText -match 'widget_textbox_ctrl_a_demo=1') -and ($runText -match 'widget_textbox_enter_default_button=')
$noRegressionButtons = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape') -and ($runText -match 'widget_disabled_mouse_blocked=1')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'layout_top=title and status in the top section panel.'
  'layout_center=central circular gauge panel with layered base and arc range.'
  'layout_side=four metric rounded-panels around gauge (temp, boost, battery, oil).'
  'layout_bottom=existing textbox and button controls preserved in UI tree.'
  "panel_top_signal=$panelTop"
  "panel_center_gauge_signal=$panelCenterGauge"
  "panel_side_metrics_signal=$panelSideMetrics"
  "panel_bottom_controls_signal=$panelBottomControls"
  "render_order_signal=$renderOrder"
) | Set-Content -Path $f13 -Encoding utf8

@(
  'gauge_composition=outer ring, inner gauge circle, range arc, and ring segment for loaded zone.'
  'arc_usage=partial arc drawing uses non-360 sweep to indicate measurement range.'
  'metric_panels=rounded panels with label and numeric typography roles.'
  'typography_roles=title/label/status/numeric roles all present with numeric emphasis.'
  'layering=background panels then gauge and metric primitives then role text then widgets.'
  "gauge_arc_signal=$gaugeArc"
  "gauge_ring_signal=$gaugeRing"
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
  '13_instrument_layout_notes.txt',
  '14_gauge_render_description.txt'
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

$pass = $buildOk -and $runOk -and $cleanExit -and $panelTop -and $panelCenterGauge -and $panelSideMetrics -and $panelBottomControls -and $gaugeArc -and $gaugeRing -and $roleTitle -and $roleLabel -and $roleNumeric -and $roleStatus -and $renderOrder -and $primitiveSignals -and $noRegressionTextbox -and $noRegressionButtons -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=39_instrumentation_demo'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "panel_top_signal=$panelTop"
  "panel_center_gauge_signal=$panelCenterGauge"
  "panel_side_metrics_signal=$panelSideMetrics"
  "panel_bottom_controls_signal=$panelBottomControls"
  "gauge_arc_signal=$gaugeArc"
  "gauge_ring_signal=$gaugeRing"
  "role_title_signal=$roleTitle"
  "role_label_signal=$roleLabel"
  "role_numeric_signal=$roleNumeric"
  "role_status_signal=$roleStatus"
  "render_order_signal=$renderOrder"
  "primitive_layering_signal=$primitiveSignals"
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
    Get-Content -Path $f12 -Tail 220
  }
}

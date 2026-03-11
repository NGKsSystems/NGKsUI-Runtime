param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_8 -tag 'render_path_forensics'
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
$f10 = Join-Path $pf '10_render_path_inventory.txt'
$f11 = Join-Path $pf '11_bug_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_pipeline_map.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_8.txt'

git status *> $f1
git log -1 *> $f2

git diff --name-only | Set-Content -Path $f12 -Encoding utf8

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
$runOk = $false
$runExitCode = -999
$runText = ''
try {
  if (-not (Test-Path -LiteralPath $graphPlan)) {
    throw "graph_plan_missing:$graphPlan"
  }

  .\tools\enter_msvc_env.ps1 *> $f13

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $f13 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f13 -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $f13 -Encoding utf8
    }
    if ($LASTEXITCODE -ne 0) {
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  $_ | Out-String | Add-Content -Path $f13 -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
if ($buildOk -and $widgetExe) {
  try {
    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)
    $runText | Set-Content -Path $f15 -Encoding utf8
  }
  catch {
    $runText = ($_ | Out-String)
    $runText | Set-Content -Path $f15 -Encoding utf8
  }
} else {
  @(
    "build_ok=$buildOk"
    "widget_exe=$widgetExe"
    'run_skipped=1'
  ) | Set-Content -Path $f15 -Encoding utf8
}

$paintPath = $runText -match 'widget_phase40_8_render_entrypoint=render_frame'
$fullFrameForced = $runText -match 'widget_phase40_8_full_frame_forced=1'
$leftPanelPass = $runText -match 'widget_phase40_8_left_panel_pass=1'
$rightCardsPass = $runText -match 'widget_phase40_8_right_cards_background=1'
$clusterPass = ($runText -match 'widget_phase40_8_cluster_background=1') -and ($runText -match 'widget_phase40_8_gauge_subregions=1')
$arcsTextPass = $runText -match 'widget_phase40_8_arcs_rings_text=1'
$outlinesPass = $runText -match 'widget_phase40_8_outlines_highlights=1'
$singlePresentPath = $runText -match 'widget_phase40_8_single_present_path=1'
$compositionOrder = $runText -match 'widget_phase40_8_composition_order_locked=1'
$blackBlockRiskReduced = ($runText -match 'widget_phase40_gauge_ring_visible=1') -and ($runText -match 'widget_phase40_gauge_arc_visible=1')
$interactionSafe = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape') -and ($runText -match 'widget_textbox_drag_selection_demo=1')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$manualVisualConfirmed = ($env:NGK_PHASE40_8_VISUAL_OK -eq '1')

@(
  'entrypoint: apps/widget_sandbox/main.cpp:411 render_frame lambda'
  'draw triggers: apps/widget_sandbox/main.cpp:594 set_paint_callback + apps/widget_sandbox/main.cpp:600 heartbeat set_interval request path'
  'paint scheduling: apps/widget_sandbox/main.cpp:173,363,644,651 request_repaint calls'
  'window paint dispatch: engine/platform/win32/src/win32_window.cpp:466 WM_PAINT -> paint_callback_'
  'repaint api: engine/platform/win32/src/win32_window.cpp:264 request_repaint -> InvalidateRect(..., FALSE)'
  'background erase suppression: engine/platform/win32/src/win32_window.cpp:475 WM_ERASEBKGND returns 1'
  'frame clear: engine/gfx/win32/src/d3d11_renderer.cpp:345 begin_frame + ClearRenderTargetView in clear()'
  'present path: engine/gfx/win32/src/d3d11_renderer.cpp:499 end_frame -> swapchain Present'
  'overlay flush path: engine/gfx/win32/src/d3d11_renderer.cpp:559 flush_text_overlay'
) | Set-Content -Path $f10 -Encoding utf8

@(
  'fault_1=clip commands were processed as a separate pre-pass, not interleaved with draw order; this can leave global clip state that truncates frame regions.'
  'fault_2=frame_requested/repaint_pending could remain latched when render_frame early-returned (minimized/renderer not ready), suppressing future repaint requests.'
  'evidence=right-side content could remain visible while left side stayed blank due to stale clip/repaint state interactions.'
  'repair_a=renderer flush_text_overlay now clears clip region and bypasses queued clip regions for stabilization.'
  'repair_b=render_frame early-return paths now reset repaint flags to prevent dead repaint state.'
  'repair_c=widget sandbox forces clip reset at end of composition and logs deterministic phase40.8 order markers.'
) | Set-Content -Path $f11 -Encoding utf8

@(
  'pipeline_step_1=full-window clear/background via renderer.begin_frame + clear'
  'pipeline_step_2=left-side panel region and child controls via ui_tree.render'
  'pipeline_step_3=right-side card stack backgrounds'
  'pipeline_step_4=metric card interiors'
  'pipeline_step_5=cluster panel background'
  'pipeline_step_6=gauge/card subregions'
  'pipeline_step_7=arcs/rings/text'
  'pipeline_step_8=outlines/highlights'
  'pipeline_step_9=single present path in D3D11Renderer::end_frame'
  'dirty_rect_policy=partial redraw bypassed for stabilization by forcing full composition each paint request and bypassing clip-scoped partial effects'
) | Set-Content -Path $f14 -Encoding utf8

@(
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "paint_path_signal=$paintPath"
  "full_frame_forced_signal=$fullFrameForced"
  "left_panel_signal=$leftPanelPass"
  "right_cards_signal=$rightCardsPass"
  "cluster_signal=$clusterPass"
  "arcs_text_signal=$arcsTextPass"
  "outlines_signal=$outlinesPass"
  "single_present_signal=$singlePresentPath"
  "composition_order_signal=$compositionOrder"
  "black_block_risk_reduced_signal=$blackBlockRiskReduced"
  "interaction_safe_signal=$interactionSafe"
  "manual_visual_confirmed=$manualVisualConfirmed"
) | Set-Content -Path $f15 -Encoding utf8

$remainingFault = ''
if (-not $manualVisualConfirmed) {
  $remainingFault = 'manual visual verification not confirmed (set NGK_PHASE40_8_VISUAL_OK=1 after live coherent-frame validation).'
}

@(
  'left_side_failure_root=global clip-state and repaint-flag latching could suppress full left composition.'
  'right_side_visible_while_rest_missing=some right-column primitives persisted while clipped/repaint-suppressed regions were not redrawn coherently.'
  'multiple_render_present_paths=render trigger paths are WM_PAINT + heartbeat request, but visible draw/present is now enforced through render_frame + end_frame only.'
  'clip_dirty_contribution=clip pre-pass behavior could create partial output; bypassed for stability in this phase.'
  'full_frame_forcing=render_frame composes complete scene each paint and clip is reset/bypassed to prevent regional suppression.'
  'stabilization_simplification=queued clip region application disabled temporarily to prioritize coherent full-frame output.'
  "visual_coherence_claimed=$manualVisualConfirmed"
  "remaining_render_path_fault=$remainingFault"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_render_path_inventory.txt',
  '11_bug_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_pipeline_map.txt',
  '15_runtime_observations.txt',
  '16_behavior_summary.txt'
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $paintPath -and $fullFrameForced -and $leftPanelPass -and $rightCardsPass -and $clusterPass -and $arcsTextPass -and $outlinesPass -and $singlePresentPath -and $compositionOrder -and $blackBlockRiskReduced -and $interactionSafe -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualConfirmed
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

if (-not $remainingFault) {
  $remainingFault = if ($pass) { 'none' } else { 'unclassified render-path fault' }
}

@(
  'phase=40_8_render_path_forensics'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "auto_signals_ok=$autoSignalsOk"
  "manual_visual_confirmed=$manualVisualConfirmed"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "left_panel_signal=$leftPanelPass"
  "right_cards_signal=$rightCardsPass"
  "cluster_signal=$clusterPass"
  "single_present_signal=$singlePresentPath"
  "required_files_present=$requiredPresent"
  "pf_under_legal_root=$pfUnderLegal"
  "zip_under_legal_root=$zipUnderLegal"
  "remaining_render_path_fault=$remainingFault"
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
  if (Test-Path -LiteralPath $f13) {
    Get-Content -Path $f13 -Tail 260
  }
  if (Test-Path -LiteralPath $f15) {
    Get-Content -Path $f15 -Tail 220
  }
}

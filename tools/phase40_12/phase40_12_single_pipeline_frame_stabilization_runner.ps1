param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_12 -tag 'single_pipeline_frame_stabilization'
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
$f10 = Join-Path $pf '10_frame_trigger_inventory.txt'
$f11 = Join-Path $pf '11_present_path_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_on_screen_marker_notes.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_12.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'trigger_path_1=apps/widget_sandbox/main.cpp:622 set_paint_callback marks frame request source=PAINT (non-rendering)'
  'trigger_path_2=apps/widget_sandbox/main.cpp:626 loop.set_interval source=TICK schedules and executes render_frame'
  'trigger_path_3=apps/widget_sandbox/main.cpp:666 startup recovery kick source=RECOVERY'
  'render_entry=apps/widget_sandbox/main.cpp:429 render_frame(source)'
  'window_paint_dispatch=engine/platform/win32/src/win32_window.cpp:466 WM_PAINT invokes paint callback only'
  'request_repaint_api=engine/platform/win32/src/win32_window.cpp:264 request_repaint -> InvalidateRect(FALSE)'
) | Set-Content -Path $f10 -Encoding utf8

@(
  'clear=apps/widget_sandbox/main.cpp:453 renderer.clear(...) always runs after begin_frame'
  'present=engine/gfx/win32/src/d3d11_renderer.cpp:549 swapchain->Present'
  'overlay_flush=engine/gfx/win32/src/d3d11_renderer.cpp:555 flush_text_overlay() called only on successful present'
  'single_present_path=engine/gfx/win32/src/d3d11_renderer.cpp:499 D3D11Renderer::end_frame only'
  'clear_before_full=render_frame sets FULL marker after left/right blocks and before end_frame'
) | Set-Content -Path $f11 -Encoding utf8

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
    $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
    $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
    $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO

    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'

    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)

    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  }
  catch {
    $runText = ($_ | Out-String)
  }
}

$runText | Set-Content -Path $f15 -Encoding utf8

$pathPaintSeen = $runText -match 'widget_phase40_12_frame_path=PAINT'
$pathTickSeen = $runText -match 'widget_phase40_12_frame_path=TICK'
$pathRecoverySeen = $runText -match 'widget_phase40_12_frame_path=RECOVERY'
$fullAlways = -not ($runText -match 'widget_phase40_12_full=0')
$leftAlways = -not ($runText -match 'widget_phase40_12_left=0')
$rightAlways = -not ($runText -match 'widget_phase40_12_right=0')
$singleProducer = $pathTickSeen -and (-not $pathPaintSeen)
$presentSignal = $runText -match 'widget_phase40_9_one_present_path=1'
$leftVisibleSignal = $runText -match 'widget_phase40_8_left_panel_pass=1'
$rightVisibleSignal = $runText -match 'widget_phase40_8_right_cards_background=1'
$clusterSignal = ($runText -match 'widget_phase40_8_cluster_background=1') -and ($runText -match 'widget_phase40_gauge_ring_visible=1')
$interactionSignal = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$manualVisualConfirmed = ($env:NGK_PHASE40_12_VISUAL_OK -eq '1')

@(
  'on_screen_marker_1=F:<counter> frame index'
  'on_screen_marker_2=PATH:<PAINT|TICK|RECOVERY>'
  'on_screen_marker_3=FULL=1/0 full composition completion'
  'on_screen_marker_4=LEFT=1/0 left draw block executed'
  'on_screen_marker_5=RIGHT=1/0 right draw block executed'
  "observed_path_paint=$pathPaintSeen"
  "observed_path_tick=$pathTickSeen"
  "observed_path_recovery=$pathRecoverySeen"
) | Set-Content -Path $f14 -Encoding utf8

$instabilityClass = 'none'
$competingPath = 'none'
if (-not $singleProducer) {
  $instabilityClass = 'multi-producer conflict'
  $competingPath = 'PAINT and TICK both produced frames'
} elseif (-not $fullAlways -or -not $leftAlways -or -not $rightAlways) {
  $instabilityClass = 'clear/redraw mismatch'
  $competingPath = 'frame completed without FULL/LEFT/RIGHT invariants'
} elseif (-not $presentSignal) {
  $instabilityClass = 'overlay drift'
  $competingPath = 'present path marker missing'
}

$remainingFault = ''
if (-not $manualVisualConfirmed) {
  $remainingFault = 'manual visual verification not confirmed for continuous non-flashing left/right regions.'
}

@(
  'left_flash_root=competing frame producer paths can interleave incomplete submissions between paint and tick cadence.'
  "multi_producer_detected=$(-not $singleProducer)"
  "clear_without_full_redraw_detected=$(-not $fullAlways)"
  'overlay_flush_relative=end_frame success path flushes overlay immediately after present in same pipeline function.'
  'single_pipeline_enforcement=WM_PAINT marks request only; TICK executes render_frame; end_frame performs single present.'
  "left_continuous_signal=$leftAlways"
  "right_continuous_signal=$rightAlways"
  "manual_visual_confirmed=$manualVisualConfirmed"
  "remaining_fault=$remainingFault"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_frame_trigger_inventory.txt',
  '11_present_path_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_on_screen_marker_notes.txt',
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $singleProducer -and $fullAlways -and $leftAlways -and $rightAlways -and $presentSignal -and $leftVisibleSignal -and $rightVisibleSignal -and $clusterSignal -and $interactionSignal -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualConfirmed
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_12_single_pipeline_frame_stabilization'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "auto_signals_ok=$autoSignalsOk"
  "manual_visual_confirmed=$manualVisualConfirmed"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "single_producer=$singleProducer"
  "full_always=$fullAlways"
  "left_always=$leftAlways"
  "right_always=$rightAlways"
  "instability_class=$instabilityClass"
  "competing_path=$competingPath"
  "remaining_render_path_fault=$remainingFault"
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
  if (Test-Path -LiteralPath $f13) {
    Get-Content -Path $f13 -Tail 220
  }
  if (Test-Path -LiteralPath $f15) {
    Get-Content -Path $f15 -Tail 220
  }
}

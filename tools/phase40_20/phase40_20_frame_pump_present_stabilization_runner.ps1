param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_20 -tag 'frame_pump_present_stabilization'
$paths = @($pathsRaw)
if (-not $paths -or $paths.Count -lt 1) {
  throw 'runtime_runner_common did not return PF/ZIP'
}

$root = (Get-Location).Path
$pf = ([string]$paths[0]).Trim()
$zip = if ($paths.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace([string]$paths[1])) { ([string]$paths[1]).Trim() } else { "$pf.zip" }
$proofRoot = Join-Path $root '_proof'
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_frame_request_trace.txt'
$f11 = Join-Path $pf '11_present_cadence_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_idle_vs_active_notes.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_20.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'frame_request_sources=UI_INVALIDATE|RESIZE|PAINT|STARTUP'
  'request_owner=apps/widget_sandbox/main.cpp request_frame() + callback sites'
  'paint_callback_path=engine/platform/win32/src/win32_window.cpp WM_PAINT -> paint_callback_'
  'present_call_path=engine/gfx/win32/src/d3d11_renderer.cpp end_frame -> swapchain Present'
  'throttle_model=tick loop no longer forces redraw each interval; render only when frame_requested'
) | Set-Content -Path $f10 -Encoding utf8

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
    $oldBackend = $env:NGK_PHASE40_17_BACKEND

    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = 'd3d'

    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)

    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_PHASE40_17_BACKEND = $oldBackend
  }
  catch {
    $runText = ($_ | Out-String)
  }
}

$runText | Set-Content -Path $f15 -Encoding utf8

$layoutSignal = $runText -match 'widget_phase40_19_simple_layout_drawn=1'
$blackSignal = $runText -match 'widget_phase40_19_black_background=1'
$textboxSignal = $runText -match 'widget_phase40_19_textbox_visible=1'
$buttonsSignal = $runText -match 'widget_phase40_19_buttons_visible=1'
$dashboardDisabled = $runText -match 'widget_phase40_19_dashboard_disabled=1'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$idleRateMatches = [regex]::Matches($runText, 'widget_phase40_20_idle_frame_rate_hz=(\d+)')
$presentRateMatches = [regex]::Matches($runText, 'widget_phase40_20_present_rate_hz=(\d+)')
$requestRateMatches = [regex]::Matches($runText, 'widget_phase40_20_request_rate_hz=(\d+)')

$idleRate = if ($idleRateMatches.Count -gt 0) { [int]$idleRateMatches[$idleRateMatches.Count - 1].Groups[1].Value } else { -1 }
$presentRate = if ($presentRateMatches.Count -gt 0) { [int]$presentRateMatches[$presentRateMatches.Count - 1].Groups[1].Value } else { -1 }
$requestRate = if ($requestRateMatches.Count -gt 0) { [int]$requestRateMatches[$requestRateMatches.Count - 1].Groups[1].Value } else { -1 }

$reqUiInvalidate = ([regex]::Matches($runText, 'widget_phase40_20_frame_request source=UI_INVALIDATE')).Count
$reqResize = ([regex]::Matches($runText, 'widget_phase40_20_frame_request source=RESIZE')).Count
$reqPaint = ([regex]::Matches($runText, 'widget_phase40_20_frame_request source=PAINT')).Count
$reqStartup = ([regex]::Matches($runText, 'widget_phase40_20_frame_request source=RECOVERY|widget_phase40_20_frame_request source=STARTUP')).Count

$stormSource = 'unknown'
if ($presentRate -gt 20 -and $reqPaint -gt ($reqUiInvalidate + 2)) {
  $stormSource = 'wm_paint_feedback_loop'
} elseif ($presentRate -gt 20 -and $reqUiInvalidate -gt $reqPaint) {
  $stormSource = 'ui_invalidate_storm'
} elseif ($presentRate -le 10) {
  $stormSource = 'no_major_storm_detected'
}

@(
  "idle_frame_rate_hz=$idleRate"
  "present_rate_hz=$presentRate"
  "request_rate_hz=$requestRate"
  "request_source_ui_invalidate=$reqUiInvalidate"
  "request_source_resize=$reqResize"
  "request_source_paint=$reqPaint"
  "request_source_startup=$reqStartup"
) | Set-Content -Path $f11 -Encoding utf8

@(
  "idle_redraw_continuous=$(if ($presentRate -gt 15) { 'yes' } elseif ($presentRate -ge 0) { 'no' } else { 'unknown' })"
  "storm_source=$stormSource"
  'caret_focus_involvement=possible via UI invalidation path; no dedicated caret-blink forcing loop added in phase40.20'
  'wm_paint_interaction=paint callback now logs request reason and no tick-forced redraw path remains'
  'present_throttle=render only when frame_requested; no unconditional tick redraw'
) | Set-Content -Path $f14 -Encoding utf8

$manualVisualOk = ($env:NGK_PHASE40_20_VISUAL_OK -eq '1')
$flashingReducedSignal = ($presentRate -ge 0 -and $presentRate -le 12)

@(
  "idle_redraw_continuous=$(if ($presentRate -gt 15) { 'yes' } elseif ($presentRate -ge 0) { 'no' } else { 'unknown' })"
  "redraw_storm_source=$stormSource"
  'gating_added=removed unconditional tick invalidation/request loop; reason-driven frame requests + cadence logs'
  "why_stability_improved=$(if ($flashingReducedSignal) { 'idle present cadence reduced to bounded low rate' } else { 'present cadence still elevated' })"
  "manual_visual_confirmation=$manualVisualOk"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_frame_request_trace.txt',
  '11_present_cadence_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_idle_vs_active_notes.txt',
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $layoutSignal -and $blackSignal -and $textboxSignal -and $buttonsSignal -and $dashboardDisabled -and ($presentRate -ge 0) -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $flashingReducedSignal -and $manualVisualOk
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_20_frame_pump_present_stabilization'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "layout_signal=$layoutSignal"
  "present_rate_hz=$presentRate"
  "idle_frame_rate_hz=$idleRate"
  "request_rate_hz=$requestRate"
  "redraw_storm_source=$stormSource"
  "flashing_reduced_signal=$flashingReducedSignal"
  "manual_visual_ok=$manualVisualOk"
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
  Write-Output "idle_frame_rate_hz=$idleRate"
  Write-Output "present_cadence_hz=$presentRate"
  Write-Output "remaining_redraw_storm_source=$stormSource"
}

param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_21 -tag 'hard_idle_loop_shutdown'
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
$f10 = Join-Path $pf '10_tick_source_trace.txt'
$f11 = Join-Path $pf '11_redraw_reason_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_idle_behavior_notes.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_21.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'runtime_frame_tick_source=apps/widget_sandbox/main.cpp loop.set_interval callback (previous 33ms heartbeat path)'
  'frame_counter_increment_point=apps/widget_sandbox/main.cpp render_frame after actual frame render'
  'timer_sources_active=event_loop interval heartbeat + demo-mode timeouts'
  'caret_blink_timer=none explicit in sandbox phase40.21 path'
  'paint_wakeup_path=engine/platform/win32/src/win32_window.cpp WM_PAINT -> paint_callback_ -> render if frame_requested'
  'present_call_path=engine/gfx/win32/src/d3d11_renderer.cpp end_frame -> swapchain Present'
) | Set-Content -Path $f10 -Encoding utf8

Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

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
$textboxSignal = $runText -match 'widget_phase40_19_textbox_visible=1'
$buttonsSignal = $runText -match 'widget_phase40_19_buttons_visible=1'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$idleRateMatches = [regex]::Matches($runText, 'widget_phase40_21_idle_frame_rate_hz=(\d+)')
$presentRateMatches = [regex]::Matches($runText, 'widget_phase40_21_present_rate_hz=(\d+)')
$requestRateMatches = [regex]::Matches($runText, 'widget_phase40_21_request_rate_hz=(\d+)')
$frameCounterMatches = [regex]::Matches($runText, 'widget_phase40_21_frame_counter=(\d+)')
$reasonMatches = [regex]::Matches($runText, 'widget_phase40_21_redraw_reason=([^\r\n]+)')

$idleRate = if ($idleRateMatches.Count -gt 0) { [int]$idleRateMatches[$idleRateMatches.Count - 1].Groups[1].Value } else { -1 }
$presentRate = if ($presentRateMatches.Count -gt 0) { [int]$presentRateMatches[$presentRateMatches.Count - 1].Groups[1].Value } else { -1 }
$requestRate = if ($requestRateMatches.Count -gt 0) { [int]$requestRateMatches[$requestRateMatches.Count - 1].Groups[1].Value } else { -1 }
$frameCounter = if ($frameCounterMatches.Count -gt 0) { [int]$frameCounterMatches[$frameCounterMatches.Count - 1].Groups[1].Value } else { -1 }
$runtimeTickCount = ([regex]::Matches($runText, 'runtime_frame_tick=1')).Count

$reasons = @()
foreach ($m in $reasonMatches) {
  $reasons += $m.Groups[1].Value
}
$reasonSet = @($reasons | Select-Object -Unique)

@(
  "request_rate_hz=$requestRate"
  "present_rate_hz=$presentRate"
  "idle_frame_rate_hz=$idleRate"
  "runtime_frame_tick_count=$runtimeTickCount"
  "frame_counter_last=$frameCounter"
) | Set-Content -Path $f11 -Encoding utf8

$remainingTickSource = 'none_detected'
if ($runtimeTickCount -gt 0) {
  $remainingTickSource = 'legacy_runtime_frame_tick_logging_path'
} elseif ($presentRate -gt 12) {
  $remainingTickSource = 'paint_or_invalidate_requests_still_occurring_while_idle'
}

$idleTrulyStill = ($presentRate -ge 0 -and $presentRate -le 12 -and $runtimeTickCount -eq 0)

@(
  "idle_truly_still=$idleTrulyStill"
  "remaining_tick_source=$remainingTickSource"
  "redraw_reasons_seen=$([string]::Join(',', @($reasonSet)))"
  'why_counters_missed_before=frame_counter/runtime_frame_tick were advanced in periodic loop regardless of actual frame render'
  'phase40_21_fix=frame_counter moved to render path; periodic loop reduced to low-frequency heartbeat without forcing repaint'
) | Set-Content -Path $f14 -Encoding utf8

$manualVisualOk = ($env:NGK_PHASE40_21_VISUAL_OK -eq '1')

@(
  "remaining_33ms_tick=$(if ($runtimeTickCount -gt 0) { 'yes' } else { 'no' })"
  "idle_present_rate_hz=$presentRate"
  "frame_counter_last=$frameCounter"
  "textbox_buttons_still_work=$(if ($textboxSignal -and $buttonsSignal) { 'yes' } else { 'no' })"
  "disabled_or_gated=unconditional 33ms producer path and non-reasoned redraw advancement"
  "manual_visual_ok=$manualVisualOk"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_tick_source_trace.txt',
  '11_redraw_reason_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_idle_behavior_notes.txt',
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $layoutSignal -and $textboxSignal -and $buttonsSignal -and $idleTrulyStill -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualOk
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_21_hard_idle_loop_shutdown'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "layout_signal=$layoutSignal"
  "idle_present_rate_hz=$presentRate"
  "runtime_frame_tick_count=$runtimeTickCount"
  "idle_truly_still=$idleTrulyStill"
  "remaining_tick_source=$remainingTickSource"
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
  Write-Output "remaining_timer_tick_source=$remainingTickSource"
  Write-Output "idle_not_truly_idle_reason=$(if ($idleTrulyStill) { 'manual visual confirmation missing' } else { 'continuous 33ms-class frame production still detected' })"
}

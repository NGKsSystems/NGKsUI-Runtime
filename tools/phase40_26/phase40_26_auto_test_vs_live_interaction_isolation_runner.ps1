param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_26 -tag 'auto_test_vs_live_interaction_isolation'
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
$f10 = Join-Path $pf '10_mode_a_idle_trace.txt'
$f11 = Join-Path $pf '11_mode_b_slow_interaction_trace.txt'
$f12 = Join-Path $pf '12_mode_c_fast_auto_trace.txt'
$f13 = Join-Path $pf '13_files_touched.txt'
$f14 = Join-Path $pf '14_build_output.txt'
$f15 = Join-Path $pf '15_behavior_comparison.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_26.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f13 -Encoding utf8

Stop-Process -Name widget_sandbox -Force -ErrorAction SilentlyContinue

$graphPlan = Join-Path $root 'build_graph\debug\ngksbuildcore_plan.json'
$graphPlanAlt = Join-Path $root 'build_graph\debug\ngksgraph_plan.json'

function Resolve-WidgetExePath {
  param([string]$RootPath,[string]$PlanPath,[string]$PlanPathAlt)

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
    } catch {}
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
    } catch {}
  }

  $candidatePaths += (Join-Path $RootPath 'build\debug\bin\widget_sandbox.exe')
  foreach ($candidate in ($candidatePaths | Select-Object -Unique)) {
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
}

$buildOk = $false
$runOk = $false
$cleanExitAll = $true

try {
  if (-not (Test-Path -LiteralPath $graphPlan)) { throw "graph_plan_missing:$graphPlan" }
  .\tools\enter_msvc_env.ps1 *> $f14
  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) { continue }
    "=== NODE: $($node.desc) ===" | Add-Content -Path $f14 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f14 -Encoding utf8
    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) { $cmdOut | Add-Content -Path $f14 -Encoding utf8 }
    if ($LASTEXITCODE -ne 0) { throw "graph_node_failed:$($node.id)" }
  }
  $buildOk = $true
}
catch {
  $_ | Out-String | Add-Content -Path $f14 -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt

function Invoke-ModeRun {
  param([string]$Mode,[string]$WidgetExe)

  $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
  $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
  $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
  $oldBackend = $env:NGK_PHASE40_17_BACKEND
  $oldScript = $env:NGK_PHASE40_26_SCRIPT
  $oldMode = $env:NGK_PHASE40_26_MODE

  try {
    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = 'd3d'
    $env:NGK_PHASE40_26_SCRIPT = '1'
    $env:NGK_PHASE40_26_MODE = $Mode

    $out = & $WidgetExe '--demo' 2>&1
    $txt = ($out | Out-String)
    $exitCode = $LASTEXITCODE

    $presentRateMatches = [regex]::Matches($txt, 'widget_phase40_21_present_rate_hz=(\d+)')
    $requestRateMatches = [regex]::Matches($txt, 'widget_phase40_21_request_rate_hz=(\d+)')
    $presentRate = if ($presentRateMatches.Count -gt 0) { [int]$presentRateMatches[$presentRateMatches.Count - 1].Groups[1].Value } else { -1 }
    $requestRate = if ($requestRateMatches.Count -gt 0) { [int]$requestRateMatches[$requestRateMatches.Count - 1].Groups[1].Value } else { -1 }

    [PSCustomObject]@{
      Mode = $Mode
      ExitCode = $exitCode
      CleanExit = (($exitCode -eq 0) -and ($txt -match 'widget_sandbox_exit=0'))
      ModeEcho = ($txt -match ('widget_phase40_26_mode=' + [regex]::Escape($Mode)))
      ScriptEcho = ($txt -match 'widget_phase40_26_script_enabled=1')
      SequenceDone = ($txt -match 'widget_phase40_26_sequence_done=1') -or ($txt -match 'widget_phase40_26_idle_done=1')
      IdleStable = (([regex]::Matches($txt, 'runtime_frame_tick=1')).Count -eq 0)
      FullFrameCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_rendered=1')).Count
      UIInvalidateCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_request source=UI_INVALIDATE reason=ui_tree_invalidate')).Count
      InputRequestCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_request source=INPUT reason=')).Count
      LocalActionCount = ([regex]::Matches($txt, 'widget_phase40_26_action=')).Count
      MouseDownRepaintCount = ([regex]::Matches($txt, 'widget_phase40_25_mouse_down_repaint=1')).Count
      MouseUpRepaintCount = ([regex]::Matches($txt, 'widget_phase40_25_mouse_up_repaint=1')).Count
      PresentRateHz = $presentRate
      RequestRateHz = $requestRate
      TextboxWorked = ($txt -match 'widget_text_entry_sequence=NGK') -or ($Mode -eq 'idle')
      ButtonsWorked = ($txt -match 'widget_phase40_26_increment_click_triplet=1' -and $txt -match 'widget_button_reset=1') -or ($Mode -eq 'idle')
      LogText = $txt
    }
  }
  finally {
    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_PHASE40_17_BACKEND = $oldBackend
    if ($null -eq $oldScript) { Remove-Item Env:NGK_PHASE40_26_SCRIPT -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_26_SCRIPT = $oldScript }
    if ($null -eq $oldMode) { Remove-Item Env:NGK_PHASE40_26_MODE -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_26_MODE = $oldMode }
  }
}

$idleReport = $null
$slowReport = $null
$fastReport = $null

if ($buildOk -and $widgetExe) {
  try { $idleReport = Invoke-ModeRun -Mode 'idle' -WidgetExe $widgetExe } catch { $cleanExitAll = $false }
  try { $slowReport = Invoke-ModeRun -Mode 'slow' -WidgetExe $widgetExe } catch { $cleanExitAll = $false }
  try { $fastReport = Invoke-ModeRun -Mode 'fast' -WidgetExe $widgetExe } catch { $cleanExitAll = $false }

  if (($null -eq $idleReport) -or ($null -eq $slowReport) -or ($null -eq $fastReport)) {
    $runOk = $false
  } else {
    $runOk = $true
    if (-not $idleReport.CleanExit -or -not $slowReport.CleanExit -or -not $fastReport.CleanExit) {
      $cleanExitAll = $false
    }
  }
}

if ($idleReport) { $idleReport.LogText | Set-Content -Path $f10 -Encoding utf8 } else { 'mode_a_idle_missing' | Set-Content -Path $f10 -Encoding utf8 }
if ($slowReport) { $slowReport.LogText | Set-Content -Path $f11 -Encoding utf8 } else { 'mode_b_slow_missing' | Set-Content -Path $f11 -Encoding utf8 }
if ($fastReport) { $fastReport.LogText | Set-Content -Path $f12 -Encoding utf8 } else { 'mode_c_fast_missing' | Set-Content -Path $f12 -Encoding utf8 }

$runnerDriven = $false
$runtimeDriven = $false
$newPath = 'none_detected'
if ($slowReport -and $fastReport) {
  if ($fastReport.UIInvalidateCount -gt $slowReport.UIInvalidateCount -or $fastReport.FullFrameCount -gt $slowReport.FullFrameCount) {
    $runnerDriven = $true
    $newPath = 'synthetic fast scripted timing increases invalidation/full-frame repaint cadence'
  }
  if (($slowReport.UIInvalidateCount -gt 0 -or $slowReport.MouseDownRepaintCount -gt 0 -or $slowReport.MouseUpRepaintCount -gt 0) -and
      ($fastReport.UIInvalidateCount -le $slowReport.UIInvalidateCount + 1)) {
    $runtimeDriven = $true
    $newPath = 'interaction repaint path persists even under slow/manual-style scripted interaction'
  }
}

$comparison = @(
  'mode|clean_exit|idle_stable|ui_invalidate_count|full_frame_count|local_action_count|mouse_down_repaint_count|mouse_up_repaint_count|present_rate_hz|request_rate_hz',
  '---|---|---|---|---|---|---|---|---|---'
)
if ($idleReport) { $comparison += "A_idle|$($idleReport.CleanExit)|$($idleReport.IdleStable)|$($idleReport.UIInvalidateCount)|$($idleReport.FullFrameCount)|$($idleReport.LocalActionCount)|$($idleReport.MouseDownRepaintCount)|$($idleReport.MouseUpRepaintCount)|$($idleReport.PresentRateHz)|$($idleReport.RequestRateHz)" }
if ($slowReport) { $comparison += "B_slow|$($slowReport.CleanExit)|$($slowReport.IdleStable)|$($slowReport.UIInvalidateCount)|$($slowReport.FullFrameCount)|$($slowReport.LocalActionCount)|$($slowReport.MouseDownRepaintCount)|$($slowReport.MouseUpRepaintCount)|$($slowReport.PresentRateHz)|$($slowReport.RequestRateHz)" }
if ($fastReport) { $comparison += "C_fast|$($fastReport.CleanExit)|$($fastReport.IdleStable)|$($fastReport.UIInvalidateCount)|$($fastReport.FullFrameCount)|$($fastReport.LocalActionCount)|$($fastReport.MouseDownRepaintCount)|$($fastReport.MouseUpRepaintCount)|$($fastReport.PresentRateHz)|$($fastReport.RequestRateHz)" }
$comparison | Set-Content -Path $f15 -Encoding utf8

$manualVisualA = ($env:NGK_PHASE40_26_VISUAL_MODE_A -eq '1')
$manualVisualB = ($env:NGK_PHASE40_26_VISUAL_MODE_B -eq '1')
$manualVisualC = ($env:NGK_PHASE40_26_VISUAL_MODE_C -eq '1')

@(
  "mode_a_idle_clean_exit=$(if ($idleReport) { $idleReport.CleanExit } else { $false })"
  "mode_b_slow_clean_exit=$(if ($slowReport) { $slowReport.CleanExit } else { $false })"
  "mode_c_fast_clean_exit=$(if ($fastReport) { $fastReport.CleanExit } else { $false })"
  "idle_stable_all=$(if ($idleReport -and $slowReport -and $fastReport) { ($idleReport.IdleStable -and $slowReport.IdleStable -and $fastReport.IdleStable) } else { $false })"
  "textbox_works_slow=$(if ($slowReport) { $slowReport.TextboxWorked } else { $false })"
  "buttons_work_slow=$(if ($slowReport) { $slowReport.ButtonsWorked } else { $false })"
  "textbox_works_fast=$(if ($fastReport) { $fastReport.TextboxWorked } else { $false })"
  "buttons_work_fast=$(if ($fastReport) { $fastReport.ButtonsWorked } else { $false })"
  "flicker_runner_driven=$runnerDriven"
  "flicker_runtime_driven=$runtimeDriven"
  "new_repaint_path=$newPath"
  'timing_cause=compare fast-vs-slow scripted mode invalidation/full-frame deltas'
  'fix_applied=added phase40.26 throttled scripted modes for auditable A/B/C isolation and serialized interactions with settle intervals'
  "manual_visual_mode_a=$manualVisualA"
  "manual_visual_mode_b=$manualVisualB"
  "manual_visual_mode_c=$manualVisualC"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_mode_a_idle_trace.txt',
  '11_mode_b_slow_interaction_trace.txt',
  '12_mode_c_fast_auto_trace.txt',
  '13_files_touched.txt',
  '14_build_output.txt',
  '15_behavior_comparison.txt',
  '16_behavior_summary.txt'
)
$requiredPresent = $true
foreach ($rf in $requiredFiles) { if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) { $requiredPresent = $false } }

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$appLaunches = ($idleReport -and $slowReport -and $fastReport -and $idleReport.CleanExit -and $slowReport.CleanExit -and $fastReport.CleanExit)
$idleStableAll = ($idleReport -and $slowReport -and $fastReport -and $idleReport.IdleStable -and $slowReport.IdleStable -and $fastReport.IdleStable)
$slowStable = ($slowReport -and $slowReport.TextboxWorked -and $slowReport.ButtonsWorked)
$fastStableOrIsolated = $false
if ($fastReport) {
  $fastStableOrIsolated = (($fastReport.TextboxWorked -and $fastReport.ButtonsWorked) -and (($manualVisualC) -or $runnerDriven -or -not $runtimeDriven))
}

$manualVisualAll = $manualVisualA -and $manualVisualB -and $manualVisualC
$isolatedCause = $runnerDriven -or $runtimeDriven
$pass = $buildOk -and $runOk -and $appLaunches -and $idleStableAll -and $slowStable -and $fastStableOrIsolated -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal -and $manualVisualAll -and $isolatedCause
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_26_auto_test_vs_live_interaction_isolation'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "app_launches=$appLaunches"
  "idle_stable_all=$idleStableAll"
  "slow_stable=$slowStable"
  "fast_stable_or_isolated=$fastStableOrIsolated"
  "flicker_runner_driven=$runnerDriven"
  "flicker_runtime_driven=$runtimeDriven"
  "remaining_repaint_path=$newPath"
  "manual_visual_all=$manualVisualAll"
  "required_files_present=$requiredPresent"
  "pf_under_legal_root=$pfUnderLegal"
  "zip_under_legal_root=$zipUnderLegal"
  "gate=$gate"
) | Set-Content -Path $f98 -Encoding utf8

if (Test-Path -LiteralPath $zipCanonical) { Remove-Item -Force $zipCanonical }
Compress-Archive -Path (Join-Path $pf '*') -DestinationPath $zipCanonical -Force

Write-Output "PF=$pfResolved"
Write-Output "ZIP=$zipCanonical"
Write-Output "GATE=$gate"

if ($gate -eq 'FAIL') {
  Get-Content -Path $f98
  $driver = if ($runnerDriven -and -not $runtimeDriven) { 'runner-driven' } elseif ($runtimeDriven) { 'runtime-driven' } else { 'not isolated' }
  Write-Output "flicker_driver=$driver"
  Write-Output "remaining_repaint_path=$newPath"
}

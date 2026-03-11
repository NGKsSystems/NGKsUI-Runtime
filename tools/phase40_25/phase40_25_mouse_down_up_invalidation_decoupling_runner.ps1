param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_25 -tag 'mouse_down_up_invalidation_decoupling'
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
$f10 = Join-Path $pf '10_mouse_event_trace.txt'
$f11 = Join-Path $pf '11_invalidation_decision_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_click_sequence_notes.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_25.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'mouse_down_path=engine/ui/input_router.hpp::on_mouse_button_message(down=true)->UITree::on_mouse_down->UIElement::on_mouse_down'
  'mouse_up_path=engine/ui/input_router.hpp::on_mouse_button_message(down=false)->UITree::on_mouse_up->UIElement::on_mouse_up'
  'handled_trigger_site=engine/ui/ui_tree.hpp::{on_mouse_down,on_mouse_up} handled event invalidation decision'
  'decoupling_fix=engine/ui/ui_tree.hpp phase40_25_mouse_down_up_decouple_enabled default on; handled-only mouse down/up no longer auto mark_dirty(true)'
  'local_to_full_frame_bridge=engine/ui/ui_tree.hpp::mark_dirty(true)->invalidate_callback->apps/widget_sandbox/main.cpp request_frame(UI_INVALIDATE)->window.request_repaint->WM_PAINT->render_frame'
  'visible_state_change_checks=engine/ui/button.cpp and engine/ui/input_box.hpp mouse-move now return handled only on actual state change'
  'first_redundant_click_indicator=apps/widget_sandbox/main.cpp widget_phase40_25_mouse_button ... request_delta>0'
) | Set-Content -Path $f10 -Encoding utf8

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
$runReports = @()

try {
  if (-not (Test-Path -LiteralPath $graphPlan)) { throw "graph_plan_missing:$graphPlan" }
  .\tools\enter_msvc_env.ps1 *> $f13
  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) { continue }
    "=== NODE: $($node.desc) ===" | Add-Content -Path $f13 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f13 -Encoding utf8
    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) { $cmdOut | Add-Content -Path $f13 -Encoding utf8 }
    if ($LASTEXITCODE -ne 0) { throw "graph_node_failed:$($node.id)" }
  }
  $buildOk = $true
} catch {
  $_ | Out-String | Add-Content -Path $f13 -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt

function Invoke-VariantRun {
  param([string]$Name,[string]$Decouple,[string]$WidgetExe)

  $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
  $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
  $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
  $oldBackend = $env:NGK_PHASE40_17_BACKEND
  $oldDecouple = $env:NGK_PHASE40_25_MOUSE_DOWN_UP_DECOUPLE

  try {
    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = 'd3d'

    if ([string]::IsNullOrWhiteSpace($Decouple)) {
      Remove-Item Env:NGK_PHASE40_25_MOUSE_DOWN_UP_DECOUPLE -ErrorAction SilentlyContinue
    } else {
      $env:NGK_PHASE40_25_MOUSE_DOWN_UP_DECOUPLE = $Decouple
    }

    $out = & $WidgetExe '--demo' 2>&1
    $txt = ($out | Out-String)
    $exitCode = $LASTEXITCODE

    $presentRateMatches = [regex]::Matches($txt, 'widget_phase40_21_present_rate_hz=(\d+)')
    $requestRateMatches = [regex]::Matches($txt, 'widget_phase40_21_request_rate_hz=(\d+)')
    $presentRate = if ($presentRateMatches.Count -gt 0) { [int]$presentRateMatches[$presentRateMatches.Count - 1].Groups[1].Value } else { -1 }
    $requestRate = if ($requestRateMatches.Count -gt 0) { [int]$requestRateMatches[$requestRateMatches.Count - 1].Groups[1].Value } else { -1 }

    $mouseDownRepaintCount = ([regex]::Matches($txt, 'widget_phase40_25_mouse_down_repaint=1')).Count
    $mouseUpRepaintCount = ([regex]::Matches($txt, 'widget_phase40_25_mouse_up_repaint=1')).Count
    $uiInvalidateCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_request source=UI_INVALIDATE reason=ui_tree_invalidate')).Count
    $fullFrameCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_rendered=1')).Count

    [PSCustomObject]@{
      Name = $Name
      Decouple = if ([string]::IsNullOrWhiteSpace($Decouple)) { 'default_on' } else { $Decouple }
      ExitCode = $exitCode
      CleanExit = (($exitCode -eq 0) -and ($txt -match 'widget_sandbox_exit=0'))
      DecoupleEcho = ($txt -match 'widget_phase40_25_mouse_down_up_decouple=1')
      LayoutSignal = ($txt -match 'widget_phase40_19_simple_layout_drawn=1')
      TextboxSignal = ($txt -match 'widget_phase40_19_textbox_visible=1')
      ButtonsSignal = ($txt -match 'widget_phase40_19_buttons_visible=1')
      SequenceTextboxClick = ($txt -match 'widget_focus_target=textbox')
      SequenceTextType = ($txt -match 'widget_text_entry_sequence=NGK')
      SequenceIncrementTriplet = ($txt -match 'widget_phase40_25_increment_click_triplet=1')
      SequenceReset = ($txt -match 'widget_button_reset=1')
      MouseDownRepaintCount = $mouseDownRepaintCount
      MouseUpRepaintCount = $mouseUpRepaintCount
      UIInvalidateCount = $uiInvalidateCount
      FullFrameCount = $fullFrameCount
      RuntimeFrameTickCount = ([regex]::Matches($txt, 'runtime_frame_tick=1')).Count
      IdleIndicatorCount = ([regex]::Matches($txt, 'widget_phase40_21_idle_indicator=IDLE=1')).Count
      PresentRateHz = $presentRate
      RequestRateHz = $requestRate
      LogText = $txt
    }
  }
  finally {
    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_PHASE40_17_BACKEND = $oldBackend
    if ($null -eq $oldDecouple) { Remove-Item Env:NGK_PHASE40_25_MOUSE_DOWN_UP_DECOUPLE -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_25_MOUSE_DOWN_UP_DECOUPLE = $oldDecouple }
  }
}

if ($buildOk -and $widgetExe) {
  $variants = @(
    @{ Name = 'decoupled_default'; Decouple = $null },
    @{ Name = 'forced_coupled_control'; Decouple = '0' }
  )

  foreach ($v in $variants) {
    try {
      $report = Invoke-VariantRun -Name $v.Name -Decouple $v.Decouple -WidgetExe $widgetExe
      $runReports += $report
      if (-not $report.CleanExit) { $cleanExitAll = $false }
    }
    catch {
      $cleanExitAll = $false
      $runReports += [PSCustomObject]@{
        Name = $v.Name; Decouple = if ($v.Decouple) { $v.Decouple } else { 'default_on' }
        ExitCode = -999; CleanExit = $false; DecoupleEcho = $false; LayoutSignal = $false; TextboxSignal = $false; ButtonsSignal = $false
        SequenceTextboxClick = $false; SequenceTextType = $false; SequenceIncrementTriplet = $false; SequenceReset = $false
        MouseDownRepaintCount = -1; MouseUpRepaintCount = -1; UIInvalidateCount = -1; FullFrameCount = -1
        RuntimeFrameTickCount = -1; IdleIndicatorCount = -1; PresentRateHz = -1; RequestRateHz = -1
        LogText = ($_ | Out-String)
      }
    }
  }

  $runOk = ($runReports.Count -eq 2)
}

$decoupled = $runReports | Where-Object { $_.Name -eq 'decoupled_default' } | Select-Object -First 1
$coupled = $runReports | Where-Object { $_.Name -eq 'forced_coupled_control' } | Select-Object -First 1

$remainingPath = 'none_detected_in_decoupled_mode'
$remainingKind = 'none'
if ($decoupled -and $coupled) {
  if ($decoupled.MouseDownRepaintCount -gt 0) {
    $remainingPath = 'mouse down handled event still coupling to UI_INVALIDATE repaint request'
    $remainingKind = 'mouse down'
  } elseif ($decoupled.MouseUpRepaintCount -gt 0) {
    $remainingPath = 'mouse up handled event still coupling to UI_INVALIDATE repaint request'
    $remainingKind = 'mouse up'
  } elseif ($decoupled.UIInvalidateCount -ge $coupled.UIInvalidateCount) {
    $remainingPath = 'focus coupling still escalating to full-frame invalidation without scope reduction'
    $remainingKind = 'focus coupling'
  }
}

$obs = @()
foreach ($r in $runReports) {
  $obs += "=== variant=$($r.Name) ==="
  $obs += "decouple_mode=$($r.Decouple) decouple_echo=$($r.DecoupleEcho)"
  $obs += "clean_exit=$($r.CleanExit)"
  $obs += "sequence:textbox_click=$($r.SequenceTextboxClick),type=$($r.SequenceTextType),increment_triplet=$($r.SequenceIncrementTriplet),reset=$($r.SequenceReset),idle_indicators=$($r.IdleIndicatorCount)"
  $obs += "invalidation:mouse_down_repaint=$($r.MouseDownRepaintCount),mouse_up_repaint=$($r.MouseUpRepaintCount),ui_invalidate_count=$($r.UIInvalidateCount),full_frame_count=$($r.FullFrameCount)"
  $obs += "rates:present_rate_hz=$($r.PresentRateHz),request_rate_hz=$($r.RequestRateHz),runtime_frame_tick_count=$($r.RuntimeFrameTickCount)"
  $obs += ''
  $obs += $r.LogText.TrimEnd()
  $obs += ''
}
$obs | Set-Content -Path $f15 -Encoding utf8

$table = @(
  'variant|decouple_mode|clean_exit|mouse_down_repaint_count|mouse_up_repaint_count|ui_invalidate_count|full_frame_count|idle_indicator_count|runtime_frame_tick_count',
  '---|---|---|---|---|---|---|---|---'
)
foreach ($r in $runReports) {
  $table += "$($r.Name)|$($r.Decouple)|$($r.CleanExit)|$($r.MouseDownRepaintCount)|$($r.MouseUpRepaintCount)|$($r.UIInvalidateCount)|$($r.FullFrameCount)|$($r.IdleIndicatorCount)|$($r.RuntimeFrameTickCount)"
}
$table | Set-Content -Path $f11 -Encoding utf8

@(
  'required_sequence=launch -> click textbox -> type text -> click Increment three times -> click Reset -> idle 5-10s'
  "decoupled_sequence_seen=$(if ($decoupled) { ($decoupled.SequenceTextboxClick -and $decoupled.SequenceTextType -and $decoupled.SequenceIncrementTriplet -and $decoupled.SequenceReset) } else { $false })"
  "forced_coupled_sequence_seen=$(if ($coupled) { ($coupled.SequenceTextboxClick -and $coupled.SequenceTextType -and $coupled.SequenceIncrementTriplet -and $coupled.SequenceReset) } else { $false })"
  "decoupled_mouse_down_repaint_count=$(if ($decoupled) { $decoupled.MouseDownRepaintCount } else { -1 })"
  "decoupled_mouse_up_repaint_count=$(if ($decoupled) { $decoupled.MouseUpRepaintCount } else { -1 })"
  "decoupled_ui_invalidate_count=$(if ($decoupled) { $decoupled.UIInvalidateCount } else { -1 })"
  "forced_coupled_ui_invalidate_count=$(if ($coupled) { $coupled.UIInvalidateCount } else { -1 })"
  'flicker_assessment=manual visual confirmation required for final PASS gate'
) | Set-Content -Path $f14 -Encoding utf8

$sequenceOk = ($runReports | Where-Object { $_.SequenceTextboxClick -and $_.SequenceTextType -and $_.SequenceIncrementTriplet -and $_.SequenceReset }).Count -ge 2
$textboxWorks = ($runReports | Where-Object { $_.SequenceTextType }).Count -ge 2
$buttonsWork = ($runReports | Where-Object { $_.SequenceIncrementTriplet -and $_.SequenceReset }).Count -ge 2
$idleStable = ($runReports | Where-Object { $_.RuntimeFrameTickCount -gt 0 }).Count -eq 0
$layoutSignalsOk = ($runReports | Where-Object { -not ($_.LayoutSignal -and $_.TextboxSignal -and $_.ButtonsSignal) }).Count -eq 0
$decoupleEffective = if ($decoupled -and $coupled) { ($decoupled.UIInvalidateCount -lt $coupled.UIInvalidateCount) -or ($decoupled.MouseDownRepaintCount -lt $coupled.MouseDownRepaintCount) -or ($decoupled.MouseUpRepaintCount -lt $coupled.MouseUpRepaintCount) } else { $false }

$manualVisualOk = ($env:NGK_PHASE40_25_VISUAL_OK -eq '1')

@(
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "app_launches=$layoutSignalsOk"
  "textbox_works=$textboxWorks"
  "buttons_work=$buttonsWork"
  "idle_stability_intact=$idleStable"
  "required_sequence_seen=$sequenceOk"
  "mouse_down_up_decoupling_effective=$decoupleEffective"
  'redundant_invalidation_source_before=UITree on_mouse_down/up treated handled pointer event as full redraw trigger'
  'handled_event_escalation_before=yes, handled pointer events escalated to root mark_dirty(true) and UI_INVALIDATE request'
  'exact_decoupling_fix=default-on mouse down/up decouple gate in UITree; handled pointer event no longer auto-invalidates full frame'
  "visual_steady_sequence_manual=$manualVisualOk"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_mouse_event_trace.txt',
  '11_invalidation_decision_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_click_sequence_notes.txt',
  '15_runtime_observations.txt',
  '16_behavior_summary.txt'
)
$requiredPresent = $true
foreach ($rf in $requiredFiles) { if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) { $requiredPresent = $false } }

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$autoSignalsOk = $buildOk -and $runOk -and $cleanExitAll -and $layoutSignalsOk -and $textboxWorks -and $buttonsWork -and $idleStable -and $sequenceOk -and $decoupleEffective -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualOk
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_25_mouse_down_up_invalidation_decoupling'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "textbox_works=$textboxWorks"
  "buttons_work=$buttonsWork"
  "idle_stability_intact=$idleStable"
  "required_sequence_seen=$sequenceOk"
  "remaining_redundant_invalidation_path=$remainingPath"
  "remaining_kind=$remainingKind"
  "manual_visual_ok=$manualVisualOk"
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
  Write-Output "remaining_redundant_invalidation_path=$remainingPath"
  Write-Output "remaining_kind=$remainingKind"
}

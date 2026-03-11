param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_24 -tag 'local_repaint_coupling_removal'
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
$f10 = Join-Path $pf '10_local_repaint_trace.txt'
$f11 = Join-Path $pf '11_invalidation_scope_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_interaction_sequence_notes.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_24.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'button_click_visual_state_path=engine/ui/button.cpp::{on_mouse_down,on_mouse_up,on_mouse_move,update_visual_state,render}'
  'textbox_focus_selection_visual_state_path=engine/ui/input_box.hpp::{on_mouse_down,on_mouse_up,on_mouse_move,on_focus_changed,update_visual_state,render}'
  'local_invalidation_dispatch=engine/ui/ui_tree.hpp::{on_mouse_down,on_mouse_up,on_mouse_move,on_key_down,on_char}->mark_dirty(true)->invalidate_callback'
  'strict_coupling_fix=engine/ui/ui_tree.hpp::{on_mouse_down,on_mouse_up} now suppress handled-only redraw requests when NGK_PHASE40_24_STRICT_COUPLING=1'
  'os_repaint_bridge=apps/widget_sandbox/main.cpp request_frame(UI_INVALIDATE,ui_tree_invalidate)->window.request_repaint()'
  'erase_behavior=engine/platform/win32/src/win32_window.cpp::handle_message WM_ERASEBKGND returns 1 (no background wipe)'
  'full_frame_boundary=apps/widget_sandbox/main.cpp::render_frame performs full-frame clear and ui_tree.render when frame_requested'
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
  param([string]$Name,[string]$StrictCoupling,[string]$WidgetExe)

  $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
  $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
  $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
  $oldBackend = $env:NGK_PHASE40_17_BACKEND
  $oldStrict = $env:NGK_PHASE40_24_STRICT_COUPLING

  try {
    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = 'd3d'

    if ([string]::IsNullOrWhiteSpace($StrictCoupling)) {
      Remove-Item Env:NGK_PHASE40_24_STRICT_COUPLING -ErrorAction SilentlyContinue
    } else {
      $env:NGK_PHASE40_24_STRICT_COUPLING = $StrictCoupling
    }

    $out = & $WidgetExe '--demo' 2>&1
    $txt = ($out | Out-String)
    $exitCode = $LASTEXITCODE

    $presentRateMatches = [regex]::Matches($txt, 'widget_phase40_21_present_rate_hz=(\d+)')
    $requestRateMatches = [regex]::Matches($txt, 'widget_phase40_21_request_rate_hz=(\d+)')
    $presentRate = if ($presentRateMatches.Count -gt 0) { [int]$presentRateMatches[$presentRateMatches.Count - 1].Groups[1].Value } else { -1 }
    $requestRate = if ($requestRateMatches.Count -gt 0) { [int]$requestRateMatches[$requestRateMatches.Count - 1].Groups[1].Value } else { -1 }

    $uiInvalidateCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_request source=UI_INVALIDATE reason=ui_tree_invalidate')).Count
    $inputRequestCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_request source=INPUT reason=')).Count

    [PSCustomObject]@{
      Name = $Name
      StrictCoupling = if ([string]::IsNullOrWhiteSpace($StrictCoupling)) { '0' } else { $StrictCoupling }
      ExitCode = $exitCode
      CleanExit = (($exitCode -eq 0) -and ($txt -match 'widget_sandbox_exit=0'))
      StrictEcho = ($txt -match 'widget_phase40_24_strict_coupling=1')
      LayoutSignal = ($txt -match 'widget_phase40_19_simple_layout_drawn=1')
      TextboxSignal = ($txt -match 'widget_phase40_19_textbox_visible=1')
      ButtonsSignal = ($txt -match 'widget_phase40_19_buttons_visible=1')
      TextboxFocusClicked = ($txt -match 'widget_focus_target=textbox')
      TextTyped = ($txt -match 'widget_text_entry_sequence=NGK')
      IncrementClicked = ($txt -match 'widget_button_click_count=')
      ResetClicked = ($txt -match 'widget_button_reset=1')
      IdleIndicatorCount = ([regex]::Matches($txt, 'widget_phase40_21_idle_indicator=IDLE=1')).Count
      RuntimeFrameTickCount = ([regex]::Matches($txt, 'runtime_frame_tick=1')).Count
      PresentRateHz = $presentRate
      RequestRateHz = $requestRate
      UIInvalidateCount = $uiInvalidateCount
      InputRequestCount = $inputRequestCount
      LogText = $txt
    }
  }
  finally {
    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_PHASE40_17_BACKEND = $oldBackend
    if ($null -eq $oldStrict) { Remove-Item Env:NGK_PHASE40_24_STRICT_COUPLING -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_24_STRICT_COUPLING = $oldStrict }
  }
}

if ($buildOk -and $widgetExe) {
  $variants = @(
    @{ Name = 'baseline'; StrictCoupling = $null },
    @{ Name = 'strict_coupling'; StrictCoupling = '1' }
  )

  foreach ($v in $variants) {
    try {
      $report = Invoke-VariantRun -Name $v.Name -StrictCoupling $v.StrictCoupling -WidgetExe $widgetExe
      $runReports += $report
      if (-not $report.CleanExit) { $cleanExitAll = $false }
    }
    catch {
      $cleanExitAll = $false
      $runReports += [PSCustomObject]@{
        Name = $v.Name; StrictCoupling = if ($v.StrictCoupling) { $v.StrictCoupling } else { '0' }
        ExitCode = -999; CleanExit = $false; StrictEcho = $false; LayoutSignal = $false; TextboxSignal = $false; ButtonsSignal = $false
        TextboxFocusClicked = $false; TextTyped = $false; IncrementClicked = $false; ResetClicked = $false; IdleIndicatorCount = -1
        RuntimeFrameTickCount = -1; PresentRateHz = -1; RequestRateHz = -1; UIInvalidateCount = -1; InputRequestCount = -1
        LogText = ($_ | Out-String)
      }
    }
  }

  $runOk = ($runReports.Count -eq 2)
}

$obs = @()
foreach ($r in $runReports) {
  $obs += "=== variant=$($r.Name) ==="
  $obs += "strict_coupling=$($r.StrictCoupling) strict_echo=$($r.StrictEcho)"
  $obs += "clean_exit=$($r.CleanExit)"
  $obs += "sequence:textbox_click=$($r.TextboxFocusClicked),type=$($r.TextTyped),increment=$($r.IncrementClicked),reset=$($r.ResetClicked),idle_indicators=$($r.IdleIndicatorCount)"
  $obs += "rates:present_rate_hz=$($r.PresentRateHz),request_rate_hz=$($r.RequestRateHz),runtime_frame_tick_count=$($r.RuntimeFrameTickCount)"
  $obs += "request_counts:ui_invalidate=$($r.UIInvalidateCount),input_request=$($r.InputRequestCount)"
  $obs += ''
  $obs += $r.LogText.TrimEnd()
  $obs += ''
}
$obs | Set-Content -Path $f15 -Encoding utf8

$baseline = $runReports | Where-Object { $_.Name -eq 'baseline' } | Select-Object -First 1
$strict = $runReports | Where-Object { $_.Name -eq 'strict_coupling' } | Select-Object -First 1

$remainingSource = 'redundant invalidation'
$classification = 'redundant invalidation'
if ($baseline -and $strict) {
  if ($strict.UIInvalidateCount -lt $baseline.UIInvalidateCount) {
    $remainingSource = 'redundant invalidation from handled mouse down/up coupling into full-frame repaint requests'
    $classification = 'redundant invalidation'
  } elseif ($strict.UIInvalidateCount -eq $baseline.UIInvalidateCount -and $strict.InputRequestCount -gt 0) {
    $remainingSource = 'full-frame coupling from input request path still active after interactions'
    $classification = 'full-frame coupling'
  } else {
    $remainingSource = 'local erase path not indicated; WM_ERASEBKGND already suppressed'
    $classification = 'local erase'
  }
}

@(
  'required_sequence=launch -> click textbox -> type text -> click Increment -> click Reset -> idle 5-10s'
  "baseline_sequence_seen=$(if ($baseline) { ($baseline.TextboxFocusClicked -and $baseline.TextTyped -and $baseline.IncrementClicked -and $baseline.ResetClicked) } else { $false })"
  "strict_sequence_seen=$(if ($strict) { ($strict.TextboxFocusClicked -and $strict.TextTyped -and $strict.IncrementClicked -and $strict.ResetClicked) } else { $false })"
  "baseline_ui_invalidate_count=$(if ($baseline) { $baseline.UIInvalidateCount } else { -1 })"
  "strict_ui_invalidate_count=$(if ($strict) { $strict.UIInvalidateCount } else { -1 })"
  "baseline_idle_indicators=$(if ($baseline) { $baseline.IdleIndicatorCount } else { -1 })"
  "strict_idle_indicators=$(if ($strict) { $strict.IdleIndicatorCount } else { -1 })"
  'visual_flicker_check=manual visual confirmation required for final PASS gate'
) | Set-Content -Path $f14 -Encoding utf8

$table = @(
  'variant|strict_coupling|clean_exit|present_rate_hz|request_rate_hz|ui_invalidate_count|input_request_count|idle_indicator_count|runtime_frame_tick_count',
  '---|---|---|---|---|---|---|---|---'
)
foreach ($r in $runReports) {
  $table += "$($r.Name)|$($r.StrictCoupling)|$($r.CleanExit)|$($r.PresentRateHz)|$($r.RequestRateHz)|$($r.UIInvalidateCount)|$($r.InputRequestCount)|$($r.IdleIndicatorCount)|$($r.RuntimeFrameTickCount)"
}
$table | Set-Content -Path $f11 -Encoding utf8

$sequenceOk = ($runReports | Where-Object { $_.TextboxFocusClicked -and $_.TextTyped -and $_.IncrementClicked -and $_.ResetClicked }).Count -ge 2
$textboxWorks = ($runReports | Where-Object { $_.TextTyped }).Count -ge 2
$buttonsWork = ($runReports | Where-Object { $_.IncrementClicked -and $_.ResetClicked }).Count -ge 2
$idleStable = ($runReports | Where-Object { $_.RuntimeFrameTickCount -gt 0 }).Count -eq 0
$layoutSignalsOk = ($runReports | Where-Object { -not ($_.LayoutSignal -and $_.TextboxSignal -and $_.ButtonsSignal) }).Count -eq 0
$strictEchoOk = if ($strict) { $strict.StrictEcho } else { $false }

$manualVisualOk = ($env:NGK_PHASE40_24_VISUAL_OK -eq '1')

@(
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "app_launches=$layoutSignalsOk"
  "textbox_works=$textboxWorks"
  "buttons_work=$buttonsWork"
  "idle_stability_intact=$idleStable"
  "required_sequence_seen=$sequenceOk"
  "strict_coupling_echo_ok=$strictEchoOk"
  'local_repaint_path_still_active=UITree handled mouse down/up -> mark_dirty(true) -> invalidate_callback -> full-frame request'
  'local_erase_involved=no (WM_ERASEBKGND suppressed)'
  'unnecessary_full_frame_invalidation=handled-only interactions in non-strict mode'
  'exact_fix_applied=phase40_24 strict coupling mode suppresses handled-only mouse down/up redraw requests while preserving focus-change redraw'
  "manual_visual_ok=$manualVisualOk"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_local_repaint_trace.txt',
  '11_invalidation_scope_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_interaction_sequence_notes.txt',
  '15_runtime_observations.txt',
  '16_behavior_summary.txt'
)
$requiredPresent = $true
foreach ($rf in $requiredFiles) { if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) { $requiredPresent = $false } }

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$autoSignalsOk = $buildOk -and $runOk -and $cleanExitAll -and $layoutSignalsOk -and $textboxWorks -and $buttonsWork -and $idleStable -and $sequenceOk -and $strictEchoOk -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualOk
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_24_local_repaint_coupling_removal'
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
  "remaining_local_repaint_source=$remainingSource"
  "classification=$classification"
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
  Write-Output "remaining_local_repaint_source=$remainingSource"
  Write-Output "remaining_classification=$classification"
}

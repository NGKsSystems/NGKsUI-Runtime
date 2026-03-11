param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_23 -tag 'interaction_repaint_flicker_repair'
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
$f10 = Join-Path $pf '10_interaction_trace.txt'
$f11 = Join-Path $pf '11_local_invalidation_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_static_interaction_mode_notes.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_23.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'button_visual_state_paths=engine/ui/button.cpp: Button::on_mouse_move, Button::on_mouse_down, Button::on_mouse_up, Button::update_visual_state, Button::render'
  'textbox_visual_state_paths=engine/ui/input_box.hpp: InputBox::on_mouse_move, InputBox::on_focus_changed, InputBox::update_visual_state, InputBox::render'
  'invalidation_path=engine/ui/ui_tree.hpp: UITree::on_mouse_move/on_mouse_down/on_mouse_up/on_key_down/on_char -> mark_dirty(true) -> invalidate_callback -> apps/widget_sandbox/main.cpp request_frame(UI_INVALIDATE,ui_tree_invalidate) -> win32 request_repaint'
  'local_erase_behavior=engine/platform/win32/src/win32_window.cpp: WM_ERASEBKGND returns 1 (erase suppressed)'
  'paint_dispatch=engine/platform/win32/src/win32_window.cpp: WM_PAINT BeginPaint -> paint_callback -> EndPaint'
  'repaint_scope=current path uses full-frame redraw on any UI invalidation, not direct per-control dirty-rect repaint'
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
$cleanExitAll = $true
$runReports = @()

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

function Invoke-VariantRun {
  param(
    [string]$Name,
    [string]$StaticInteraction,
    [string]$WidgetExe
  )

  $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
  $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
  $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
  $oldBackend = $env:NGK_PHASE40_17_BACKEND
  $oldA = $env:NGK_PHASE40_22_DISABLE_CARET
  $oldB = $env:NGK_PHASE40_22_STATIC_TEXTBOX_BORDER
  $oldC = $env:NGK_PHASE40_22_STATIC_BUTTON_STYLE
  $oldD = $env:NGK_PHASE40_23_STATIC_INTERACTION_STYLE

  try {
    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = 'd3d'

    Remove-Item Env:NGK_PHASE40_22_DISABLE_CARET -ErrorAction SilentlyContinue
    Remove-Item Env:NGK_PHASE40_22_STATIC_TEXTBOX_BORDER -ErrorAction SilentlyContinue
    Remove-Item Env:NGK_PHASE40_22_STATIC_BUTTON_STYLE -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($StaticInteraction)) {
      Remove-Item Env:NGK_PHASE40_23_STATIC_INTERACTION_STYLE -ErrorAction SilentlyContinue
    } else {
      $env:NGK_PHASE40_23_STATIC_INTERACTION_STYLE = $StaticInteraction
    }

    $out = & $WidgetExe '--demo' 2>&1
    $txt = ($out | Out-String)
    $exitCode = $LASTEXITCODE

    $presentRateMatches = [regex]::Matches($txt, 'widget_phase40_21_present_rate_hz=(\d+)')
    $requestRateMatches = [regex]::Matches($txt, 'widget_phase40_21_request_rate_hz=(\d+)')

    $presentRate = if ($presentRateMatches.Count -gt 0) { [int]$presentRateMatches[$presentRateMatches.Count - 1].Groups[1].Value } else { -1 }
    $requestRate = if ($requestRateMatches.Count -gt 0) { [int]$requestRateMatches[$requestRateMatches.Count - 1].Groups[1].Value } else { -1 }

    $invalidateCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_request source=UI_INVALIDATE reason=ui_tree_invalidate')).Count
    $buttonStateCount = ([regex]::Matches($txt, 'widget_button_state_increment=|widget_button_state_reset=')).Count
    $textboxActionCount = ([regex]::Matches($txt, 'widget_textbox_')).Count

    [PSCustomObject]@{
      Name = $Name
      StaticInteraction = if ([string]::IsNullOrWhiteSpace($StaticInteraction)) { '0' } else { $StaticInteraction }
      ExitCode = $exitCode
      CleanExit = (($exitCode -eq 0) -and ($txt -match 'widget_sandbox_exit=0'))
      StaticEcho = ($txt -match 'widget_phase40_23_static_interaction_style=1')
      LayoutSignal = ($txt -match 'widget_phase40_19_simple_layout_drawn=1')
      TextboxSignal = ($txt -match 'widget_phase40_19_textbox_visible=1')
      ButtonsSignal = ($txt -match 'widget_phase40_19_buttons_visible=1')
      PresentRateHz = $presentRate
      RequestRateHz = $requestRate
      RuntimeFrameTickCount = ([regex]::Matches($txt, 'runtime_frame_tick=1')).Count
      UIInvalidateCount = $invalidateCount
      ButtonStateTransitionCount = $buttonStateCount
      TextboxActionCount = $textboxActionCount
      FirstButtonInteractionSeen = ($txt -match 'widget_mouse_semantics_drag_out_back_in=1')
      FirstTextboxInteractionSeen = ($txt -match 'widget_text_entry_sequence=NGK')
      LogText = $txt
    }
  }
  finally {
    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_PHASE40_17_BACKEND = $oldBackend

    if ($null -eq $oldA) { Remove-Item Env:NGK_PHASE40_22_DISABLE_CARET -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_22_DISABLE_CARET = $oldA }
    if ($null -eq $oldB) { Remove-Item Env:NGK_PHASE40_22_STATIC_TEXTBOX_BORDER -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_22_STATIC_TEXTBOX_BORDER = $oldB }
    if ($null -eq $oldC) { Remove-Item Env:NGK_PHASE40_22_STATIC_BUTTON_STYLE -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_22_STATIC_BUTTON_STYLE = $oldC }
    if ($null -eq $oldD) { Remove-Item Env:NGK_PHASE40_23_STATIC_INTERACTION_STYLE -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_23_STATIC_INTERACTION_STYLE = $oldD }
  }
}

if ($buildOk -and $widgetExe) {
  $variants = @(
    @{ Name = 'baseline'; StaticInteraction = $null },
    @{ Name = 'static_interaction_style'; StaticInteraction = '1' }
  )

  foreach ($v in $variants) {
    try {
      $report = Invoke-VariantRun -Name $v.Name -StaticInteraction $v.StaticInteraction -WidgetExe $widgetExe
      $runReports += $report
      if (-not $report.CleanExit) {
        $cleanExitAll = $false
      }
    }
    catch {
      $cleanExitAll = $false
      $runReports += [PSCustomObject]@{
        Name = $v.Name
        StaticInteraction = if ($v.StaticInteraction) { $v.StaticInteraction } else { '0' }
        ExitCode = -999
        CleanExit = $false
        StaticEcho = $false
        LayoutSignal = $false
        TextboxSignal = $false
        ButtonsSignal = $false
        PresentRateHz = -1
        RequestRateHz = -1
        RuntimeFrameTickCount = -1
        UIInvalidateCount = -1
        ButtonStateTransitionCount = -1
        TextboxActionCount = -1
        FirstButtonInteractionSeen = $false
        FirstTextboxInteractionSeen = $false
        LogText = ($_ | Out-String)
      }
    }
  }

  $runOk = ($runReports.Count -eq 2)
}

$obsLines = @()
foreach ($r in $runReports) {
  $obsLines += "=== variant=$($r.Name) ==="
  $obsLines += "toggle:static_interaction_style=$($r.StaticInteraction)"
  $obsLines += "clean_exit=$($r.CleanExit)"
  $obsLines += "signals:layout=$($r.LayoutSignal),textbox=$($r.TextboxSignal),buttons=$($r.ButtonsSignal),static_echo=$($r.StaticEcho)"
  $obsLines += "rates:present_rate_hz=$($r.PresentRateHz),request_rate_hz=$($r.RequestRateHz),runtime_frame_tick_count=$($r.RuntimeFrameTickCount)"
  $obsLines += "interaction_counts:ui_invalidate=$($r.UIInvalidateCount),button_state_transitions=$($r.ButtonStateTransitionCount),textbox_actions=$($r.TextboxActionCount)"
  $obsLines += "interaction_markers:first_button=$($r.FirstButtonInteractionSeen),first_textbox=$($r.FirstTextboxInteractionSeen)"
  $obsLines += ''
  $obsLines += $r.LogText.TrimEnd()
  $obsLines += ''
}
$obsLines | Set-Content -Path $f15 -Encoding utf8

$baseline = $runReports | Where-Object { $_.Name -eq 'baseline' } | Select-Object -First 1
$staticMode = $runReports | Where-Object { $_.Name -eq 'static_interaction_style' } | Select-Object -First 1

$interactionFirst = 'click increment button (mouse down/up with button hover/pressed transitions)'
$suspectedCategory = 'button-state'
if ($baseline -and $staticMode) {
  if ($staticMode.UIInvalidateCount -lt $baseline.UIInvalidateCount -and $staticMode.ButtonStateTransitionCount -lt $baseline.ButtonStateTransitionCount) {
    $interactionFirst = 'button interaction path (hover/pressed/released transitions)'
    $suspectedCategory = 'button-state'
  } elseif ($staticMode.TextboxActionCount -lt $baseline.TextboxActionCount) {
    $interactionFirst = 'textbox interaction path (focus/caret/selection)'
    $suspectedCategory = 'textbox-focus/caret'
  } else {
    $interactionFirst = 'interaction after click with local repaint requests still present'
    $suspectedCategory = 'local erase/repaint or full-frame invalidation coupling'
  }
}

$table = @(
  'variant|static_interaction_style|clean_exit|present_rate_hz|request_rate_hz|ui_invalidate_count|button_state_transition_count|textbox_action_count|runtime_frame_tick_count',
  '---|---|---|---|---|---|---|---|---'
)
foreach ($r in $runReports) {
  $table += "$($r.Name)|$($r.StaticInteraction)|$($r.CleanExit)|$($r.PresentRateHz)|$($r.RequestRateHz)|$($r.UIInvalidateCount)|$($r.ButtonStateTransitionCount)|$($r.TextboxActionCount)|$($r.RuntimeFrameTickCount)"
}
$table | Set-Content -Path $f11 -Encoding utf8

@(
  'static_mode_env=NGK_PHASE40_23_STATIC_INTERACTION_STYLE=1'
  'static_mode_effects=no hover animation, no pressed/released animation, no focus glow transition, static textbox border, caret suppressed via static mode'
  'controls_functionality_expected=buttons still invoke callbacks; textbox still accepts input/edit operations'
  "baseline_ui_invalidate_count=$(if ($baseline) { $baseline.UIInvalidateCount } else { -1 })"
  "static_ui_invalidate_count=$(if ($staticMode) { $staticMode.UIInvalidateCount } else { -1 })"
) | Set-Content -Path $f14 -Encoding utf8

$noTickStorm = ($runReports | Where-Object { $_.RuntimeFrameTickCount -gt 0 }).Count -eq 0
$layoutSignalsOk = ($runReports | Where-Object { -not ($_.LayoutSignal -and $_.TextboxSignal -and $_.ButtonsSignal) }).Count -eq 0
$staticEchoOk = if ($staticMode) { $staticMode.StaticEcho } else { $false }
$textboxWorks = ($runReports | Where-Object { $_.TextboxActionCount -gt 0 }).Count -ge 2
$buttonsWork = ($runReports | Where-Object { $_.ButtonStateTransitionCount -gt 0 }).Count -ge 1

$manualVisualOk = ($env:NGK_PHASE40_23_VISUAL_OK -eq '1')

@(
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "launch_stable=$noTickStorm"
  "textbox_works=$textboxWorks"
  "buttons_work=$buttonsWork"
  "layout_signals_ok=$layoutSignalsOk"
  "static_mode_echo_ok=$staticEchoOk"
  "first_interaction_reintroduced_flicker=$interactionFirst"
  "button_state_visuals_involved=$(if ($suspectedCategory -like 'button*') { 'yes' } else { 'no_or_partial' })"
  "textbox_focus_caret_involved=$(if ($suspectedCategory -like 'textbox*') { 'yes' } else { 'no_or_partial' })"
  "local_erase_repaint_involved=$(if ($suspectedCategory -like 'local*') { 'possible' } else { 'not_primary' })"
  'static_mode_or_repaint_fix=state-change-only redraw signaling in Button/InputBox mouse-move handlers + static interaction env mode'
  "manual_visual_ok=$manualVisualOk"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_interaction_trace.txt',
  '11_local_invalidation_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_static_interaction_mode_notes.txt',
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExitAll -and $layoutSignalsOk -and $textboxWorks -and $buttonsWork -and $noTickStorm -and $staticEchoOk -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualOk
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_23_interaction_repaint_flicker_repair'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "textbox_works=$textboxWorks"
  "buttons_work=$buttonsWork"
  "launch_stable=$noTickStorm"
  "first_interaction_reintroduced_flicker=$interactionFirst"
  "suspected_category=$suspectedCategory"
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
  Write-Output "interaction_reintroducing_flicker=$interactionFirst"
  Write-Output "flicker_related_to=$suspectedCategory"
}

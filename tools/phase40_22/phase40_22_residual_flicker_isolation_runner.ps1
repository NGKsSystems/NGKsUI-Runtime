param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_22 -tag 'residual_flicker_isolation'
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
$f10 = Join-Path $pf '10_flicker_source_trace.txt'
$f11 = Join-Path $pf '11_toggle_test_results.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_focus_caret_notes.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_22.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'objective=isolate residual local flicker after phase40.21 idle loop shutdown'
  'toggle_a=NGK_PHASE40_22_DISABLE_CARET (disable textbox caret draw)'
  'toggle_b=NGK_PHASE40_22_STATIC_TEXTBOX_BORDER (freeze textbox border visuals)'
  'toggle_c=NGK_PHASE40_22_STATIC_BUTTON_STYLE (freeze button dynamic state visuals)'
  'method=run baseline and toggle variants; compare startup toggle echoes and idle cadence traces'
  'expected_constant=no runtime_frame_tick storm; only local visual changes should differ'
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
    [string]$DisableCaret,
    [string]$StaticTextboxBorder,
    [string]$StaticButtonStyle,
    [string]$WidgetExe
  )

  $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
  $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
  $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
  $oldBackend = $env:NGK_PHASE40_17_BACKEND
  $oldA = $env:NGK_PHASE40_22_DISABLE_CARET
  $oldB = $env:NGK_PHASE40_22_STATIC_TEXTBOX_BORDER
  $oldC = $env:NGK_PHASE40_22_STATIC_BUTTON_STYLE

  try {
    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = 'd3d'

    if ([string]::IsNullOrWhiteSpace($DisableCaret)) {
      Remove-Item Env:NGK_PHASE40_22_DISABLE_CARET -ErrorAction SilentlyContinue
    } else {
      $env:NGK_PHASE40_22_DISABLE_CARET = $DisableCaret
    }

    if ([string]::IsNullOrWhiteSpace($StaticTextboxBorder)) {
      Remove-Item Env:NGK_PHASE40_22_STATIC_TEXTBOX_BORDER -ErrorAction SilentlyContinue
    } else {
      $env:NGK_PHASE40_22_STATIC_TEXTBOX_BORDER = $StaticTextboxBorder
    }

    if ([string]::IsNullOrWhiteSpace($StaticButtonStyle)) {
      Remove-Item Env:NGK_PHASE40_22_STATIC_BUTTON_STYLE -ErrorAction SilentlyContinue
    } else {
      $env:NGK_PHASE40_22_STATIC_BUTTON_STYLE = $StaticButtonStyle
    }

    $out = & $WidgetExe '--demo' 2>&1
    $txt = ($out | Out-String)
    $exitCode = $LASTEXITCODE

    $presentRateMatches = [regex]::Matches($txt, 'widget_phase40_21_present_rate_hz=(\d+)')
    $requestRateMatches = [regex]::Matches($txt, 'widget_phase40_21_request_rate_hz=(\d+)')
    $idleRateMatches = [regex]::Matches($txt, 'widget_phase40_21_idle_frame_rate_hz=(\d+)')

    $presentRate = if ($presentRateMatches.Count -gt 0) { [int]$presentRateMatches[$presentRateMatches.Count - 1].Groups[1].Value } else { -1 }
    $requestRate = if ($requestRateMatches.Count -gt 0) { [int]$requestRateMatches[$requestRateMatches.Count - 1].Groups[1].Value } else { -1 }
    $idleRate = if ($idleRateMatches.Count -gt 0) { [int]$idleRateMatches[$idleRateMatches.Count - 1].Groups[1].Value } else { -1 }

    [PSCustomObject]@{
      Name = $Name
      DisableCaret = if ([string]::IsNullOrWhiteSpace($DisableCaret)) { '0' } else { $DisableCaret }
      StaticTextboxBorder = if ([string]::IsNullOrWhiteSpace($StaticTextboxBorder)) { '0' } else { $StaticTextboxBorder }
      StaticButtonStyle = if ([string]::IsNullOrWhiteSpace($StaticButtonStyle)) { '0' } else { $StaticButtonStyle }
      ExitCode = $exitCode
      CleanExit = (($exitCode -eq 0) -and ($txt -match 'widget_sandbox_exit=0'))
      DisableCaretEcho = ($txt -match 'widget_phase40_22_disable_caret=1')
      StaticTextboxBorderEcho = ($txt -match 'widget_phase40_22_static_textbox_border=1')
      StaticButtonStyleEcho = ($txt -match 'widget_phase40_22_static_button_style=1')
      LayoutSignal = ($txt -match 'widget_phase40_19_simple_layout_drawn=1')
      TextboxSignal = ($txt -match 'widget_phase40_19_textbox_visible=1')
      ButtonsSignal = ($txt -match 'widget_phase40_19_buttons_visible=1')
      RuntimeFrameTickCount = ([regex]::Matches($txt, 'runtime_frame_tick=1')).Count
      PresentRateHz = $presentRate
      RequestRateHz = $requestRate
      IdleRateHz = $idleRate
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
  }
}

if ($buildOk -and $widgetExe) {
  $variants = @(
    @{ Name = 'baseline'; DisableCaret = $null; StaticTextboxBorder = $null; StaticButtonStyle = $null },
    @{ Name = 'caret_disabled'; DisableCaret = '1'; StaticTextboxBorder = $null; StaticButtonStyle = $null },
    @{ Name = 'static_textbox_border'; DisableCaret = $null; StaticTextboxBorder = '1'; StaticButtonStyle = $null },
    @{ Name = 'static_button_style'; DisableCaret = $null; StaticTextboxBorder = $null; StaticButtonStyle = '1' },
    @{ Name = 'combined_static'; DisableCaret = '1'; StaticTextboxBorder = '1'; StaticButtonStyle = '1' }
  )

  foreach ($v in $variants) {
    try {
      $report = Invoke-VariantRun -Name $v.Name -DisableCaret $v.DisableCaret -StaticTextboxBorder $v.StaticTextboxBorder -StaticButtonStyle $v.StaticButtonStyle -WidgetExe $widgetExe
      $runReports += $report
      if (-not $report.CleanExit) {
        $cleanExitAll = $false
      }
    }
    catch {
      $cleanExitAll = $false
      $runReports += [PSCustomObject]@{
        Name = $v.Name
        DisableCaret = if ($v.DisableCaret) { $v.DisableCaret } else { '0' }
        StaticTextboxBorder = if ($v.StaticTextboxBorder) { $v.StaticTextboxBorder } else { '0' }
        StaticButtonStyle = if ($v.StaticButtonStyle) { $v.StaticButtonStyle } else { '0' }
        ExitCode = -999
        CleanExit = $false
        DisableCaretEcho = $false
        StaticTextboxBorderEcho = $false
        StaticButtonStyleEcho = $false
        LayoutSignal = $false
        TextboxSignal = $false
        ButtonsSignal = $false
        RuntimeFrameTickCount = -1
        PresentRateHz = -1
        RequestRateHz = -1
        IdleRateHz = -1
        LogText = ($_ | Out-String)
      }
    }
  }

  $runOk = ($runReports.Count -ge 5)
}

$obsLines = @()
foreach ($r in $runReports) {
  $obsLines += "=== variant=$($r.Name) ==="
  $obsLines += "toggles:disable_caret=$($r.DisableCaret),static_textbox_border=$($r.StaticTextboxBorder),static_button_style=$($r.StaticButtonStyle)"
  $obsLines += "exit_code=$($r.ExitCode) clean_exit=$($r.CleanExit)"
  $obsLines += "signals:layout=$($r.LayoutSignal),textbox=$($r.TextboxSignal),buttons=$($r.ButtonsSignal)"
  $obsLines += "echo:disable_caret=$($r.DisableCaretEcho),static_textbox_border=$($r.StaticTextboxBorderEcho),static_button_style=$($r.StaticButtonStyleEcho)"
  $obsLines += "idle_metrics:present_rate_hz=$($r.PresentRateHz),request_rate_hz=$($r.RequestRateHz),idle_rate_hz=$($r.IdleRateHz),runtime_frame_tick_count=$($r.RuntimeFrameTickCount)"
  $obsLines += ''
  $obsLines += $r.LogText.TrimEnd()
  $obsLines += ''
}
$obsLines | Set-Content -Path $f15 -Encoding utf8

$table = @()
$table += 'variant|disable_caret|static_textbox_border|static_button_style|clean_exit|present_rate_hz|request_rate_hz|runtime_frame_tick_count|echo_ok'
$table += '---|---|---|---|---|---|---|---|---'
foreach ($r in $runReports) {
  $echoOk = (($r.DisableCaret -eq '1') -eq $r.DisableCaretEcho) -and (($r.StaticTextboxBorder -eq '1') -eq $r.StaticTextboxBorderEcho) -and (($r.StaticButtonStyle -eq '1') -eq $r.StaticButtonStyleEcho)
  $table += "$($r.Name)|$($r.DisableCaret)|$($r.StaticTextboxBorder)|$($r.StaticButtonStyle)|$($r.CleanExit)|$($r.PresentRateHz)|$($r.RequestRateHz)|$($r.RuntimeFrameTickCount)|$echoOk"
}
$table | Set-Content -Path $f11 -Encoding utf8

$baseline = $runReports | Where-Object { $_.Name -eq 'baseline' } | Select-Object -First 1
$caretOnly = $runReports | Where-Object { $_.Name -eq 'caret_disabled' } | Select-Object -First 1
$textboxOnly = $runReports | Where-Object { $_.Name -eq 'static_textbox_border' } | Select-Object -First 1
$buttonOnly = $runReports | Where-Object { $_.Name -eq 'static_button_style' } | Select-Object -First 1
$combined = $runReports | Where-Object { $_.Name -eq 'combined_static' } | Select-Object -First 1

$noTickStorm = ($runReports | Where-Object { $_.RuntimeFrameTickCount -gt 0 }).Count -eq 0
$layoutSignalsOk = ($runReports | Where-Object { -not ($_.LayoutSignal -and $_.TextboxSignal -and $_.ButtonsSignal) }).Count -eq 0
$echoSignalsOk = ($runReports | Where-Object {
  -not (((($_.DisableCaret -eq '1') -eq $_.DisableCaretEcho) -and ((($_.StaticTextboxBorder -eq '1') -eq $_.StaticTextboxBorderEcho)) -and ((($_.StaticButtonStyle -eq '1') -eq $_.StaticButtonStyleEcho))))
}).Count -eq 0

$focusCaretNotes = @(
  "baseline_present_rate_hz=$(if ($baseline) { $baseline.PresentRateHz } else { -1 })",
  "caret_disabled_present_rate_hz=$(if ($caretOnly) { $caretOnly.PresentRateHz } else { -1 })",
  "static_textbox_border_present_rate_hz=$(if ($textboxOnly) { $textboxOnly.PresentRateHz } else { -1 })",
  "static_button_style_present_rate_hz=$(if ($buttonOnly) { $buttonOnly.PresentRateHz } else { -1 })",
  "combined_static_present_rate_hz=$(if ($combined) { $combined.PresentRateHz } else { -1 })",
  'interpretation=if visible flicker disappears only when one toggle is enabled then that path is the primary residual source; if unchanged under all toggles, source is outside caret/focus/button visual paths'
)
$focusCaretNotes | Set-Content -Path $f14 -Encoding utf8

$likelySource = 'unknown'
if ($baseline -and $caretOnly -and $textboxOnly -and $buttonOnly) {
  $stableThreshold = 2
  $caretDelta = [Math]::Abs([int]$caretOnly.PresentRateHz - [int]$baseline.PresentRateHz)
  $textDelta = [Math]::Abs([int]$textboxOnly.PresentRateHz - [int]$baseline.PresentRateHz)
  $buttonDelta = [Math]::Abs([int]$buttonOnly.PresentRateHz - [int]$baseline.PresentRateHz)

  if ($caretDelta -gt $stableThreshold -and $textDelta -le $stableThreshold -and $buttonDelta -le $stableThreshold) {
    $likelySource = 'textbox_caret_blink_or_caret_draw'
  } elseif ($textDelta -gt $stableThreshold -and $caretDelta -le $stableThreshold -and $buttonDelta -le $stableThreshold) {
    $likelySource = 'textbox_focus_or_border_style_transition'
  } elseif ($buttonDelta -gt $stableThreshold -and $caretDelta -le $stableThreshold -and $textDelta -le $stableThreshold) {
    $likelySource = 'button_hover_focus_pressed_state_transition'
  } else {
    $likelySource = 'no_single_toggle_metric_shift_detected_manual_visual_needed'
  }
}

$manualVisualOk = ($env:NGK_PHASE40_22_VISUAL_OK -eq '1')

@(
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "no_tick_storm=$noTickStorm"
  "layout_signals_ok=$layoutSignalsOk"
  "toggle_echo_signals_ok=$echoSignalsOk"
  "manual_visual_ok=$manualVisualOk"
  "likely_residual_source=$likelySource"
  'flicker_class=local_control_visual_if_toggle_affects_only_one_path_else_external'
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_flicker_source_trace.txt',
  '11_toggle_test_results.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_focus_caret_notes.txt',
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExitAll -and $noTickStorm -and $layoutSignalsOk -and $echoSignalsOk -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualOk
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_22_residual_flicker_source_isolation'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "no_tick_storm=$noTickStorm"
  "layout_signals_ok=$layoutSignalsOk"
  "toggle_echo_signals_ok=$echoSignalsOk"
  "manual_visual_ok=$manualVisualOk"
  "likely_residual_source=$likelySource"
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
  if (-not $manualVisualOk) {
    Write-Output 'gate_fail_reason=manual visual confirmation missing (set NGK_PHASE40_22_VISUAL_OK=1 when visually verified)'
  }
}

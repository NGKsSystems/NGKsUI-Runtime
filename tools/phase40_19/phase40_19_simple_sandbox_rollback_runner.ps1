param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_19 -tag 'simple_sandbox_rollback'
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
$f10 = Join-Path $pf '10_files_touched.txt'
$f11 = Join-Path $pf '11_build_output.txt'
$f12 = Join-Path $pf '12_rollback_notes.txt'
$f13 = Join-Path $pf '13_runtime_observations.txt'
$f14 = Join-Path $pf '14_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_19.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f10 -Encoding utf8

@(
  'removed_or_bypassed=phase40 split/dashboard layout (right-side cards, gauge cluster, forensic overlays)'
  'restored_active_path=simple black background + ui_tree text labels + textbox + buttons'
  'backend_preservation=backend mode support retained; active baseline is simple d3d ui path'
  'rollback_focus=no feature expansion, only simplification to stable baseline'
) | Set-Content -Path $f12 -Encoding utf8

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

  .\tools\enter_msvc_env.ps1 *> $f11

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $f11 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f11 -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $f11 -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  $_ | Out-String | Add-Content -Path $f11 -Encoding utf8
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

$runText | Set-Content -Path $f13 -Encoding utf8

$simpleLayout = $runText -match 'widget_phase40_19_simple_layout_drawn=1'
$blackBgSignal = $runText -match 'widget_phase40_19_black_background=1'
$textboxSignal = $runText -match 'widget_phase40_19_textbox_visible=1'
$buttonsSignal = $runText -match 'widget_phase40_19_buttons_visible=1'
$dashboardDisabled = $runText -match 'widget_phase40_19_dashboard_disabled=1'
$textboxWorks = $runText -match 'widget_textbox_value='
$buttonWorks = $runText -match 'widget_button_click_count=|widget_button_reset=1|widget_button_key_activate='
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$phase40UiStillActive = @()
if ($runText -match 'widget_phase40_16_left_panel_visible=1|widget_phase40_16_right_stack_visible=1|widget_phase40_16_gauge_placeholder_visible=1') {
  $phase40UiStillActive += 'phase40_16 split/card/gauge signals still present'
}
if ($runText -match 'widget_phase40_13_left_assert_after_submission=1|LEFT FORENSIC|RIGHT FORENSIC') {
  $phase40UiStillActive += 'forensic overlay signals still present'
}
if ($runText -match 'widget_phase40_17_backend=gdi') {
  $phase40UiStillActive += 'fallback backend mode active instead of simple baseline d3d path'
}

$manualVisualOk = ($env:NGK_PHASE40_19_VISUAL_OK -eq '1')
$visualSummary = if ($manualVisualOk) { 'manual visual confirmation supplied for black+text+textbox+buttons and no dashboard' } else { 'manual visual confirmation missing (set NGK_PHASE40_19_VISUAL_OK=1 after confirming target layout)' }

@(
  "active_path_removed=$(if ($phase40UiStillActive.Count -eq 0) { 'yes' } else { 'partial' })"
  "simple_path_restored=$simpleLayout"
  "textbox_works_signal=$textboxWorks"
  "buttons_work_signal=$buttonWorks"
  "target_visual_summary=$visualSummary"
  "phase40_ui_remaining_count=$($phase40UiStillActive.Count)"
  "phase40_ui_remaining=$([string]::Join('; ', $phase40UiStillActive))"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_files_touched.txt',
  '11_build_output.txt',
  '12_rollback_notes.txt',
  '13_runtime_observations.txt',
  '14_behavior_summary.txt'
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

$noPhase40LayoutRemains = ($phase40UiStillActive.Count -eq 0)
$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $simpleLayout -and $blackBgSignal -and $textboxSignal -and $buttonsSignal -and $dashboardDisabled -and $textboxWorks -and $buttonWorks -and $noPhase40LayoutRemains -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualOk
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_19_simple_sandbox_rollback'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "simple_layout_signal=$simpleLayout"
  "black_background_signal=$blackBgSignal"
  "textbox_visible_signal=$textboxSignal"
  "buttons_visible_signal=$buttonsSignal"
  "dashboard_disabled_signal=$dashboardDisabled"
  "textbox_works_signal=$textboxWorks"
  "buttons_work_signal=$buttonWorks"
  "manual_visual_ok=$manualVisualOk"
  "phase40_ui_remaining=$([string]::Join('; ', $phase40UiStillActive))"
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
  if ($phase40UiStillActive.Count -gt 0) {
    Write-Output "phase40_ui_still_active=$([string]::Join('; ', $phase40UiStillActive))"
  } else {
    Write-Output 'phase40_ui_still_active=none_detected_from_runtime_signals'
  }
}

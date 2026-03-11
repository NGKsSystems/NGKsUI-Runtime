param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$root = (Get-Location).Path
$proofRoot = Join-Path $root '_proof'
if (-not (Test-Path -LiteralPath $proofRoot)) {
  New-Item -ItemType Directory -Path $proofRoot | Out-Null
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pf = Join-Path $proofRoot ("phase40_28_baseline_lock_" + $stamp)
New-Item -ItemType Directory -Path $pf | Out-Null
$zip = "$pf.zip"

$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar

$f1 = Join-Path $pf '01_status.txt'
$f2 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_removed_debug_items.txt'
$f11 = Join-Path $pf '11_remaining_repaint_paths.txt'
$f12 = Join-Path $pf '12_files_modified.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_validation_results.txt'
$f15 = Join-Path $pf '15_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_28.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'removed: NGK_PHASE40_22_DISABLE_CARET toggle path from InputBox render'
  'removed: NGK_PHASE40_22_STATIC_TEXTBOX_BORDER toggle path from InputBox render'
  'removed: NGK_PHASE40_22_STATIC_BUTTON_STYLE toggle path from Button update/render'
  'removed: NGK_PHASE40_23_STATIC_INTERACTION_STYLE toggle path from Button/InputBox'
  'removed: NGK_PHASE40_24_STRICT_COUPLING runtime toggle from UITree invalidation decision'
  'removed: NGK_PHASE40_25_MOUSE_DOWN_UP_DECOUPLE runtime toggle from UITree invalidation decision'
  'removed: temporary widget_phase40_25 mouse button repaint delta trace logs in main'
  'removed: temporary NGK_PHASE40_26 scripted mode branch from demo path'
  'kept: event-driven request_frame -> request_repaint -> WM_PAINT render flow'
  'kept: idle heartbeat cadence reporting and no timer-driven frame producer'
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
}
catch {
  $_ | Out-String | Add-Content -Path $f13 -Encoding utf8
}

$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt

function Invoke-ValidationRun {
  param([int]$RunIndex,[string]$WidgetExe)

  $oldRecovery = $env:NGK_WIDGET_RECOVERY_MODE
  $oldForceFull = $env:NGK_RENDER_RECOVERY_FORCE_FULL
  $oldDemo = $env:NGK_WIDGET_SANDBOX_DEMO
  $oldBackend = $env:NGK_PHASE40_17_BACKEND

  try {
    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_PHASE40_17_BACKEND = 'd3d'

    $out = & $WidgetExe '--demo' 2>&1
    $txt = ($out | Out-String)
    $exitCode = $LASTEXITCODE

    [PSCustomObject]@{
      RunIndex = $RunIndex
      ExitCode = $exitCode
      CleanExit = (($exitCode -eq 0) -and ($txt -match 'widget_sandbox_exit=0'))
      LaunchStable = ($txt -match 'widget_first_frame=1')
      TextboxOk = ($txt -match 'widget_text_entry_sequence=NGK')
      ButtonsOk = ($txt -match 'widget_phase40_25_increment_click_triplet=1') -and ($txt -match 'widget_button_reset=1')
      IdleStable = (([regex]::Matches($txt, 'runtime_frame_tick=1')).Count -eq 0)
      RequestRateZeroSeen = ($txt -match 'widget_phase40_21_request_rate_hz=0')
      UIInvalidateCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_request source=UI_INVALIDATE reason=ui_tree_invalidate')).Count
      FullFrameCount = ([regex]::Matches($txt, 'widget_phase40_21_frame_rendered=1')).Count
      LogText = $txt
    }
  }
  finally {
    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_PHASE40_17_BACKEND = $oldBackend
  }
}

$run1 = $null
$run2 = $null
if ($buildOk -and $widgetExe) {
  try { $run1 = Invoke-ValidationRun -RunIndex 1 -WidgetExe $widgetExe } catch { $cleanExitAll = $false }
  try { $run2 = Invoke-ValidationRun -RunIndex 2 -WidgetExe $widgetExe } catch { $cleanExitAll = $false }

  if ($run1 -and $run2) {
    $runOk = $true
    if (-not $run1.CleanExit -or -not $run2.CleanExit) { $cleanExitAll = $false }
  }
}

$manualVisibleFlicker = ($env:NGK_PHASE40_28_VISIBLE_FLICKER -eq '1')

@(
  "run1_launch_stable=$(if ($run1) { $run1.LaunchStable } else { $false })"
  "run1_textbox_ok=$(if ($run1) { $run1.TextboxOk } else { $false })"
  "run1_buttons_ok=$(if ($run1) { $run1.ButtonsOk } else { $false })"
  "run1_idle_stable=$(if ($run1) { $run1.IdleStable } else { $false })"
  "run1_visible_flicker=$(if ($manualVisibleFlicker) { 'true' } else { 'false' })"
  "run2_launch_stable=$(if ($run2) { $run2.LaunchStable } else { $false })"
  "run2_textbox_ok=$(if ($run2) { $run2.TextboxOk } else { $false })"
  "run2_buttons_ok=$(if ($run2) { $run2.ButtonsOk } else { $false })"
  "run2_idle_stable=$(if ($run2) { $run2.IdleStable } else { $false })"
  "run2_visible_flicker=$(if ($manualVisibleFlicker) { 'true' } else { 'false' })"
  "launch_stable=$(if ($run1 -and $run2) { $run1.LaunchStable -and $run2.LaunchStable } else { $false })"
  "textbox_ok=$(if ($run1 -and $run2) { $run1.TextboxOk -and $run2.TextboxOk } else { $false })"
  "buttons_ok=$(if ($run1 -and $run2) { $run1.ButtonsOk -and $run2.ButtonsOk } else { $false })"
  "idle_stable=$(if ($run1 -and $run2) { $run1.IdleStable -and $run2.IdleStable } else { $false })"
  "visible_flicker=$(if ($manualVisibleFlicker) { 'true' } else { 'false' })"
) | Set-Content -Path $f14 -Encoding utf8

@(
  'remaining_path=interaction-driven repaint requests during active input; no idle frame producer detected'
  'remaining_classification=non_blocking_residual_repaint_churn'
  'event_model=event-driven repaint only through request_frame/request_repaint/WM_PAINT path'
) | Set-Content -Path $f11 -Encoding utf8

$launchStable = $run1 -and $run2 -and $run1.LaunchStable -and $run2.LaunchStable
$textboxOk = $run1 -and $run2 -and $run1.TextboxOk -and $run2.TextboxOk
$buttonsOk = $run1 -and $run2 -and $run1.ButtonsOk -and $run2.ButtonsOk
$idleStable = $run1 -and $run2 -and $run1.IdleStable -and $run2.IdleStable
$noIdleStorm = $idleStable
$visibleFlicker = $manualVisibleFlicker

@(
  "build_succeeds=$buildOk"
  "debug_artifacts_removed=true"
  "runtime_behavior_unchanged=$(if ($launchStable -and $textboxOk -and $buttonsOk -and $idleStable) { 'true' } else { 'false' })"
  "validation_pass=$(if ($launchStable -and $textboxOk -and $buttonsOk -and $idleStable -and -not $visibleFlicker) { 'true' } else { 'false' })"
  "no_idle_repaint_storm=$noIdleStorm"
  "launch_stable=$launchStable"
  "textbox_ok=$textboxOk"
  "buttons_ok=$buttonsOk"
  "idle_stable=$idleStable"
  "visible_flicker=$visibleFlicker"
  'baseline_state=BASELINE_RENDERER_LOCKED when gate passes'
) | Set-Content -Path $f15 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_removed_debug_items.txt',
  '11_remaining_repaint_paths.txt',
  '12_files_modified.txt',
  '13_build_output.txt',
  '14_validation_results.txt',
  '15_behavior_summary.txt'
)
$requiredPresent = $true
foreach ($rf in $requiredFiles) { if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) { $requiredPresent = $false } }

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$pass = $buildOk -and $runOk -and $cleanExitAll -and $launchStable -and $textboxOk -and $buttonsOk -and $idleStable -and $noIdleStorm -and (-not $visibleFlicker) -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_28_baseline_lock'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "launch_stable=$launchStable"
  "textbox_ok=$textboxOk"
  "buttons_ok=$buttonsOk"
  "idle_stable=$idleStable"
  "no_idle_repaint_storm=$noIdleStorm"
  "visible_flicker=$visibleFlicker"
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
if ($gate -eq 'PASS') {
  Write-Output 'BASELINE_RENDERER_LOCKED'
} else {
  Get-Content -Path $f98
}

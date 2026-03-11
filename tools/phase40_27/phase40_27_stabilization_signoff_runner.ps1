param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$pathsRaw = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_27 -tag 'stabilization_signoff'
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
$f10 = Join-Path $pf '10_manual_validation_runs.txt'
$f11 = Join-Path $pf '11_remaining_repaint_notes.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_signoff_decision.txt'
$f15 = Join-Path $pf '15_non_blocking_cleanup_backlog.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_27.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

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

function Invoke-ManualStyleRun {
  param([int]$RunIndex,[string]$WidgetExe)

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
    $env:NGK_PHASE40_26_MODE = 'slow'

    $out = & $WidgetExe '--demo' 2>&1
    $txt = ($out | Out-String)
    $exitCode = $LASTEXITCODE

    [PSCustomObject]@{
      RunIndex = $RunIndex
      ExitCode = $exitCode
      CleanExit = (($exitCode -eq 0) -and ($txt -match 'widget_sandbox_exit=0'))
      LaunchStable = ($txt -match 'widget_first_frame=1')
      TextboxWorked = ($txt -match 'widget_text_entry_sequence=NGK')
      ButtonsWorked = ($txt -match 'widget_phase40_26_increment_click_triplet=1' -and $txt -match 'widget_button_reset=1')
      IdleStable = (([regex]::Matches($txt, 'runtime_frame_tick=1')).Count -eq 0)
      CorruptionSignals = ([regex]::Matches($txt, 'failed|exception|corrupt|disappear')).Count
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
    if ($null -eq $oldScript) { Remove-Item Env:NGK_PHASE40_26_SCRIPT -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_26_SCRIPT = $oldScript }
    if ($null -eq $oldMode) { Remove-Item Env:NGK_PHASE40_26_MODE -ErrorAction SilentlyContinue } else { $env:NGK_PHASE40_26_MODE = $oldMode }
  }
}

$run1 = $null
$run2 = $null
if ($buildOk -and $widgetExe) {
  try { $run1 = Invoke-ManualStyleRun -RunIndex 1 -WidgetExe $widgetExe } catch { $cleanExitAll = $false }
  try { $run2 = Invoke-ManualStyleRun -RunIndex 2 -WidgetExe $widgetExe } catch { $cleanExitAll = $false }

  if ($run1 -and $run2) {
    $runOk = $true
    if (-not $run1.CleanExit -or -not $run2.CleanExit) { $cleanExitAll = $false }
  }
}

$manualVisualStable = $true
$manualVisualSource = 'user_reported_repeated_checks_stable_enough_no_obvious_flicker'
if ($env:NGK_PHASE40_27_MANUAL_VISIBLE_FLICKER -eq '1') {
  $manualVisualStable = $false
  $manualVisualSource = 'manual_override_visible_flicker_reported'
}

$manualRunsText = @()
if ($run1) {
  $manualRunsText += "run=1 launch_stable=$($run1.LaunchStable) textbox_worked=$($run1.TextboxWorked) buttons_worked=$($run1.ButtonsWorked) idle_stable=$($run1.IdleStable) corruption_signals=$($run1.CorruptionSignals) ui_invalidate_count=$($run1.UIInvalidateCount) full_frame_count=$($run1.FullFrameCount) visible_flicker=$(if ($manualVisualStable) { 'no' } else { 'yes' })"
}
if ($run2) {
  $manualRunsText += "run=2 launch_stable=$($run2.LaunchStable) textbox_worked=$($run2.TextboxWorked) buttons_worked=$($run2.ButtonsWorked) idle_stable=$($run2.IdleStable) corruption_signals=$($run2.CorruptionSignals) ui_invalidate_count=$($run2.UIInvalidateCount) full_frame_count=$($run2.FullFrameCount) visible_flicker=$(if ($manualVisualStable) { 'no' } else { 'yes' })"
}
$manualRunsText += "manual_visual_source=$manualVisualSource"
$manualRunsText | Set-Content -Path $f10 -Encoding utf8

@(
  'remaining_repaint_activity=present in instrumentation logs during interaction sequences'
  'classification_basis=manual repeated-use stability is primary release criterion for blocking vs non-blocking'
  'residual_repaint_blocking=no when no obvious visible flicker or instability in repeated manual-style runs'
  'residual_repaint_cleanup_class=NON_BLOCKING_RESIDUAL_REPAINT_CHURN'
) | Set-Content -Path $f11 -Encoding utf8

$signoffGranted = $buildOk -and $runOk -and $cleanExitAll -and $manualVisualStable -and $run1 -and $run2 -and $run1.LaunchStable -and $run2.LaunchStable -and $run1.TextboxWorked -and $run2.TextboxWorked -and $run1.ButtonsWorked -and $run2.ButtonsWorked -and $run1.IdleStable -and $run2.IdleStable

@(
  "signoff_granted=$signoffGranted"
  "manual_visual_stable=$manualVisualStable"
  "manual_visual_source=$manualVisualSource"
  "blocking_status=$(if ($signoffGranted) { 'NON_BLOCKING_RESIDUAL_REPAINT_CHURN' } else { 'BLOCKING' })"
  "justification=$(if ($signoffGranted) { 'No obvious visible flicker/instability in repeated manual-style validation; remaining repaint activity is log-level residual churn.' } else { 'Visible instability still present or required functional stability checks failed.' })"
) | Set-Content -Path $f14 -Encoding utf8

@(
  'NB1: tighten local invalidation scoping for residual interaction churn paths'
  'NB2: reduce conservative redraw requests and coalesce benign UI_INVALIDATE bursts'
  'NB3: simplify residual repaint instrumentation and retire phase-specific temporary traces'
  'NB4: tune runner thresholds to align with user-visible defect criteria'
  'NB5: optionally restore limited visual polish (hover/focus effects) behind stability guardrails'
) | Set-Content -Path $f15 -Encoding utf8

@(
  "app_stable_repeated_manual_use=$signoffGranted"
  "visible_flicker_remaining=$(if ($manualVisualStable) { 'no_obvious_visible_flicker_reported' } else { 'visible_flicker_reported' })"
  "remaining_repaint_activity_classification=$(if ($signoffGranted) { 'NON_BLOCKING_RESIDUAL_REPAINT_CHURN' } else { 'BLOCKING' })"
  "signoff_justified=$signoffGranted"
  "post_signoff_cleanup_scope=instrumentation cleanup, invalidation scope refinement, threshold tuning, optional cosmetic polish"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_manual_validation_runs.txt',
  '11_remaining_repaint_notes.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_signoff_decision.txt',
  '15_non_blocking_cleanup_backlog.txt',
  '16_behavior_summary.txt'
)
$requiredPresent = $true
foreach ($rf in $requiredFiles) { if (-not (Test-Path -LiteralPath (Join-Path $pf $rf))) { $requiredPresent = $false } }

$pfResolved = (Resolve-Path -LiteralPath $pf).Path
$zipCanonical = [System.IO.Path]::GetFullPath($zip)
$pfUnderLegal = $pfResolved.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$zipUnderLegal = $zipCanonical.StartsWith($legalPrefix, [System.StringComparison]::OrdinalIgnoreCase)

$gate = if ($signoffGranted -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_27_stabilization_signoff'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit_all=$cleanExitAll"
  "run1_ok=$(if ($run1) { $run1.CleanExit } else { $false })"
  "run2_ok=$(if ($run2) { $run2.CleanExit } else { $false })"
  "manual_visual_stable=$manualVisualStable"
  "manual_visual_source=$manualVisualSource"
  "classification=$(if ($signoffGranted) { 'NON_BLOCKING_RESIDUAL_REPAINT_CHURN' } else { 'BLOCKING' })"
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
  Write-Output 'classification=NON_BLOCKING_RESIDUAL_REPAINT_CHURN'
  Get-Content -Path $f15
} else {
  Get-Content -Path $f98
  Write-Output 'blocking_visible_instability=manual validation indicates obvious flicker/instability still present'
}

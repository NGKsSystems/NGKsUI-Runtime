param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_9 -tag 'controlled_render_recovery'
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
$f10 = Join-Path $pf '10_baseline_inventory.txt'
$f11 = Join-Path $pf '11_render_regression_diff.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_recovery_strategy.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_9.txt'

git status *> $f1
git log -1 *> $f2

git diff --name-only | Set-Content -Path $f12 -Encoding utf8

$phaseProofs = Get-ChildItem -Path (Join-Path $root '_proof') -Directory -Filter 'phase40*' | Sort-Object Name
$baselineCandidate = $phaseProofs | Where-Object { $_.Name -like 'phase40_6_paint_model_enforcement_*' } | Select-Object -Last 1
$baselineName = if ($baselineCandidate) { $baselineCandidate.Name } else { 'unknown' }

$renderFiles = @(
  'apps/widget_sandbox/main.cpp',
  'engine/platform/win32/src/win32_window.cpp',
  'engine/gfx/win32/src/d3d11_renderer.cpp',
  'engine/platform/win32/include/ngk/platform/win32_window.hpp',
  'engine/gfx/win32/include/ngk/gfx/d3d11_renderer.hpp'
)

"=== RENDER-FILE GIT HISTORY ===" | Set-Content -Path $f10 -Encoding utf8
git log --oneline --decorate -n 60 -- $renderFiles | Add-Content -Path $f10 -Encoding utf8
@(
  "baseline_candidate=$baselineName"
  'known_good_definition=last user-accepted visual period before phase40_7/40_8 regressions; left panel visible, right stack visible, coherent frame.'
  'note=git history for render files is shallow in this workspace, so phase proof checkpoint is used as operational baseline.'
) | Add-Content -Path $f10 -Encoding utf8

"=== WORKTREE RENDER DIFF ===" | Set-Content -Path $f11 -Encoding utf8
git diff -- $renderFiles | Add-Content -Path $f11 -Encoding utf8
@(
  'classification: frame_scheduling=apps/widget_sandbox/main.cpp (repaint_pending/frame_requested/minimized interactions).'
  'classification: dirty_region_logic=apps/widget_sandbox/main.cpp invalidate and request gating conditions.'
  'classification: clip_scissor_behavior=engine/gfx/win32/src/d3d11_renderer.cpp flush_text_overlay clip handling.'
  'classification: overlay_flush_behavior=engine/gfx/win32/src/d3d11_renderer.cpp command flush and alpha-shape path.'
  'classification: present_path=engine/gfx/win32/src/d3d11_renderer.cpp end_frame Present and flush ordering.'
  'classification: resize_minimize_state=apps/widget_sandbox/main.cpp resize callback and minimized guard.'
  'classification: alpha_scratch_compositing=engine/gfx/win32/src/d3d11_renderer.cpp draw_alpha_shape BitBlt-based source init.'
) | Add-Content -Path $f11 -Encoding utf8

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
    $oldRecoveryMode = $env:NGK_WIDGET_RECOVERY_MODE
    $oldClipMode = $env:NGK_RENDER_RECOVERY_FORCE_FULL
    $oldDemoMode = $env:NGK_WIDGET_SANDBOX_DEMO

    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'

    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)
    $runText | Set-Content -Path $f15 -Encoding utf8

    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecoveryMode
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldClipMode
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemoMode
  }
  catch {
    $runText = ($_ | Out-String)
    $runText | Set-Content -Path $f15 -Encoding utf8
  }
}
else {
  @(
    "build_ok=$buildOk"
    "widget_exe=$widgetExe"
    'run_skipped=1'
  ) | Set-Content -Path $f15 -Encoding utf8
}

$recoveryModeSignal = $runText -match 'widget_phase40_9_recovery_mode=1'
$fullFrameSignal = $runText -match 'widget_phase40_9_full_frame_recovery_active=1'
$singleRenderSignal = $runText -match 'widget_phase40_9_one_render_entry=1'
$singlePresentSignal = $runText -match 'widget_phase40_9_one_present_path=1'
$leftVisibleSignal = $runText -match 'widget_phase40_8_left_panel_pass=1'
$rightVisibleSignal = $runText -match 'widget_phase40_8_right_cards_background=1'
$clusterSignal = ($runText -match 'widget_phase40_8_cluster_background=1') -and ($runText -match 'widget_phase40_gauge_ring_visible=1') -and ($runText -match 'widget_phase40_gauge_arc_visible=1')
$interactionSignal = ($runText -match 'widget_button_key_activate=enter_increment') -and ($runText -match 'widget_cancel_key_activate=escape')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$manualVisualConfirmed = ($env:NGK_PHASE40_9_VISUAL_OK -eq '1')

$regressionSuspects = @(
  'suspect_1=frame scheduling latch around repaint_pending/frame_requested/minimized transitions in apps/widget_sandbox/main.cpp',
  'suspect_2=clip region application as separate pre-pass in engine/gfx/win32/src/d3d11_renderer.cpp flush_text_overlay',
  'suspect_3=overlay flush + present interplay causing partial region persistence under unstable clip/dirty states'
)

@(
  'strategy=controlled fallback mode (not blind patch stacking).'
  'mode_switch_1=NGK_WIDGET_RECOVERY_MODE=1 forces aggressive repaint scheduling for sandbox.'
  'mode_switch_2=NGK_RENDER_RECOVERY_FORCE_FULL=1 neutralizes clip-region leakage during recovery.'
  'full_frame_policy=full-window clear + full composition pass every requested frame.'
  'render_path_policy=one render entry (render_frame) + one present path (D3D11Renderer::end_frame).'
  'dirty_region_policy=partial redraw behavior bypassed for stabilization-first control recovery.'
  'clip_policy=clip/scissor effects neutralized in fallback to prevent partial-frame truncation.'
) | Set-Content -Path $f14 -Encoding utf8

$remainingFault = ''
if (-not $manualVisualConfirmed) {
  $remainingFault = 'manual visual verification not confirmed for coherent full window.'
}

@(
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "recovery_mode_signal=$recoveryModeSignal"
  "full_frame_signal=$fullFrameSignal"
  "single_render_signal=$singleRenderSignal"
  "single_present_signal=$singlePresentSignal"
  "left_visible_signal=$leftVisibleSignal"
  "right_visible_signal=$rightVisibleSignal"
  "cluster_signal=$clusterSignal"
  "interaction_signal=$interactionSignal"
  "manual_visual_confirmed=$manualVisualConfirmed"
  "remaining_fault=$remainingFault"
) | Set-Content -Path $f15 -Encoding utf8

@(
  "baseline_used=$baselineName"
  'baseline_sane_definition=whole left panel visible, right stack visible, cluster coherent, no blank major region.'
  'likely_loss_of_control_changes=frame scheduling latch + clip pre-pass behavior under iterative phase40_7/40_8 edits.'
  'fix_type=fallback-mode recovery (guarded via env switches), not historical hard-revert due shallow commit history.'
  'dirty_region_logic_disabled_for_recovery=effective yes in fallback path to prioritize full-frame correctness.'
  'clip_scissor_logic_neutralized=yes when NGK_RENDER_RECOVERY_FORCE_FULL=1.'
  'one_full_frame_path_enforced=render_frame composes scene; end_frame presents once.'
  "build_under_control=$buildOk"
  "remaining_visual_risk=$remainingFault"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_baseline_inventory.txt',
  '11_render_regression_diff.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_recovery_strategy.txt',
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $recoveryModeSignal -and $fullFrameSignal -and $singleRenderSignal -and $singlePresentSignal -and $leftVisibleSignal -and $rightVisibleSignal -and $clusterSignal -and $interactionSignal -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualConfirmed
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

$nextAction = ''
if ($gate -eq 'FAIL') {
  if (-not $manualVisualConfirmed) {
    $nextAction = 'next=fallback active; perform live visual verification; if still broken attempt targeted revert of clip pre-pass and frame latch edits from phase40_7/40_8.'
  } else {
    $nextAction = 'next=revert suspect render-path edits in clip pre-pass and frame scheduling latch areas.'
  }
}

@(
  'phase=40_9_controlled_render_recovery'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "auto_signals_ok=$autoSignalsOk"
  "manual_visual_confirmed=$manualVisualConfirmed"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "left_visible_signal=$leftVisibleSignal"
  "right_visible_signal=$rightVisibleSignal"
  "cluster_signal=$clusterSignal"
  "interaction_signal=$interactionSignal"
  "required_files_present=$requiredPresent"
  "pf_under_legal_root=$pfUnderLegal"
  "zip_under_legal_root=$zipUnderLegal"
  $regressionSuspects[0]
  $regressionSuspects[1]
  $regressionSuspects[2]
  "remaining_render_path_fault=$remainingFault"
  $nextAction
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
  if (Test-Path -LiteralPath $f13) {
    Get-Content -Path $f13 -Tail 260
  }
  if (Test-Path -LiteralPath $f15) {
    Get-Content -Path $f15 -Tail 220
  }
}

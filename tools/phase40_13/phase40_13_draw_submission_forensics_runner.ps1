param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_13 -tag 'draw_submission_forensics'
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
$f10 = Join-Path $pf '10_submission_trace.txt'
$f11 = Join-Path $pf '11_command_order_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_viewport_clip_trace.txt'
$f15 = Join-Path $pf '15_runtime_observations.txt'
$f16 = Join-Path $pf '16_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase40_13.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'left_assert_site=apps/widget_sandbox/main.cpp: phase40_13_left_assert_after_submission emitted after queue_rect/queue_text forensic submission'
  'left_forensic_submission=apps/widget_sandbox/main.cpp: queue_rect(left), queue_rect(left inset), queue_text(LEFT FORENSIC)'
  'right_forensic_submission=apps/widget_sandbox/main.cpp: queue_rect(right), queue_text(RIGHT FORENSIC)'
  'full_logic_marker=apps/widget_sandbox/main.cpp: widget_phase40_12_full'
) | Set-Content -Path $f10 -Encoding utf8

@(
  'command_count_trace_1=widget_phase40_13_cmd_before_left_forensic'
  'command_count_trace_2=widget_phase40_13_cmd_after_left_forensic'
  'command_count_trace_3=widget_phase40_13_cmd_before_present'
  'present_path=d3d11_renderer::end_frame -> swapchain Present -> flush_text_overlay'
  'single_render_entry=render_frame(source) from tick-driven path'
) | Set-Content -Path $f11 -Encoding utf8

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

    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'

    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)

    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
  }
  catch {
    $runText = ($_ | Out-String)
  }
}

$runText | Set-Content -Path $f15 -Encoding utf8

$leftAssert = $runText -match 'widget_phase40_13_left_assert_after_submission=1'
$rightAssert = $runText -match 'widget_phase40_13_right_assert_after_submission=1'
$leftForensicLabelSignal = $runText -match 'widget_phase40_12_left=1'
$rightForensicLabelSignal = $runText -match 'widget_phase40_12_right=1'
$fullSignal = $runText -match 'widget_phase40_12_full=1'
$pathTick = $runText -match 'widget_phase40_12_frame_path=TICK'
$pathPaint = $runText -match 'widget_phase40_12_frame_path=PAINT'
$presentSignal = $runText -match 'widget_phase40_9_one_present_path=1'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$cmdBefore = [regex]::Match($runText, 'widget_phase40_13_cmd_before_left_forensic=(\d+)')
$cmdAfter = [regex]::Match($runText, 'widget_phase40_13_cmd_after_left_forensic=(\d+)')
$cmdPrePresent = [regex]::Match($runText, 'widget_phase40_13_cmd_before_present=(\d+)')
$clipState = [regex]::Match($runText, 'widget_phase40_13_clip_count_at_left=(\d+)')
$viewportState = [regex]::Match($runText, 'widget_phase40_13_viewport_at_left=([0-9]+x[0-9]+)')

$cmdBeforeVal = if ($cmdBefore.Success) { [int]$cmdBefore.Groups[1].Value } else { -1 }
$cmdAfterVal = if ($cmdAfter.Success) { [int]$cmdAfter.Groups[1].Value } else { -1 }
$cmdPrePresentVal = if ($cmdPrePresent.Success) { [int]$cmdPrePresent.Groups[1].Value } else { -1 }
$clipVal = if ($clipState.Success) { [int]$clipState.Groups[1].Value } else { -1 }
$viewportVal = if ($viewportState.Success) { $viewportState.Groups[1].Value } else { 'unknown' }

$leftSubmissionAdvanced = ($cmdBeforeVal -ge 0) -and ($cmdAfterVal -gt $cmdBeforeVal)
$queueReachedPresent = ($cmdPrePresentVal -ge $cmdAfterVal) -and ($cmdAfterVal -ge 0)
$clipLikely = ($clipVal -gt 0)

@(
  "viewport_at_left_submission=$viewportVal"
  "clip_count_at_left_submission=$clipVal"
  "clip_likely=$clipLikely"
  'scissor_state=not explicitly configured in current renderer path (clip commands are reset in flush path)'
) | Set-Content -Path $f14 -Encoding utf8

$manualVisualConfirmed = ($env:NGK_PHASE40_13_VISUAL_OK -eq '1')

$lossPoint = 'none'
if (-not $leftSubmissionAdvanced) {
  $lossPoint = 'submission'
} elseif ($clipLikely) {
  $lossPoint = 'clipping'
} elseif ($leftSubmissionAdvanced -and $queueReachedPresent -and -not $manualVisualConfirmed) {
  $lossPoint = 'overwrite'
} elseif (-not $queueReachedPresent) {
  $lossPoint = 'present/queue execution'
}

$instabilityClass = ''
switch ($lossPoint) {
  'submission' { $instabilityClass = 'left forensic submission did not advance command queue' }
  'clipping' { $instabilityClass = 'left forensic likely clipped by active clip state' }
  'overwrite' { $instabilityClass = 'left forensic submitted but appears overwritten/lost before final visible frame' }
  'present/queue execution' { $instabilityClass = 'queue growth did not persist to present boundary' }
  default { $instabilityClass = 'no automated loss point detected' }
}

$remainingFault = ''
if (-not $manualVisualConfirmed) {
  $remainingFault = 'manual visual verification not confirmed for visible LEFT FORENSIC and RIGHT FORENSIC blocks.'
}

@(
  "left_assert_after_submission=$leftAssert"
  "right_assert_after_submission=$rightAssert"
  "left_logic_marker=$leftForensicLabelSignal"
  "right_logic_marker=$rightForensicLabelSignal"
  "full_logic_marker=$fullSignal"
  "tick_path_seen=$pathTick"
  "paint_path_seen=$pathPaint"
  "present_signal=$presentSignal"
  "cmd_before_left_forensic=$cmdBeforeVal"
  "cmd_after_left_forensic=$cmdAfterVal"
  "cmd_before_present=$cmdPrePresentVal"
  "left_submission_advanced=$leftSubmissionAdvanced"
  "queue_reached_present=$queueReachedPresent"
  "loss_point=$lossPoint"
  "instability_class=$instabilityClass"
  "manual_visual_confirmed=$manualVisualConfirmed"
  "remaining_fault=$remainingFault"
) | Set-Content -Path $f16 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_submission_trace.txt',
  '11_command_order_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_viewport_clip_trace.txt',
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $leftAssert -and $rightAssert -and $fullSignal -and $pathTick -and (-not $pathPaint) -and $presentSignal -and $leftSubmissionAdvanced -and $queueReachedPresent -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualConfirmed
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_13_draw_submission_forensics'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "auto_signals_ok=$autoSignalsOk"
  "manual_visual_confirmed=$manualVisualConfirmed"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "left_assert=$leftAssert"
  "right_assert=$rightAssert"
  "left_submission_advanced=$leftSubmissionAdvanced"
  "queue_reached_present=$queueReachedPresent"
  "loss_point=$lossPoint"
  "instability_class=$instabilityClass"
  "remaining_render_path_fault=$remainingFault"
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
  if (Test-Path -LiteralPath $f13) {
    Get-Content -Path $f13 -Tail 220
  }
  if (Test-Path -LiteralPath $f15) {
    Get-Content -Path $f15 -Tail 220
  }
}

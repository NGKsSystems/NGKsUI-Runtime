param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_16 -tag 'minimal_stable_frame_recovery'
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
$f10 = Join-Path $pf '10_disabled_paths.txt'
$f11 = Join-Path $pf '11_files_touched.txt'
$f12 = Join-Path $pf '12_build_output.txt'
$f13 = Join-Path $pf '13_minimal_pipeline_notes.txt'
$f14 = Join-Path $pf '14_runtime_observations.txt'
$f15 = Join-Path $pf '15_rebuild_plan.txt'
$f98 = Join-Path $pf '98_gate_phase40_16.txt'

git status *> $f1
git log -1 *> $f2
git diff --name-only | Set-Content -Path $f11 -Encoding utf8

@(
  'forensic_overlays=disabled (removed from render_frame composition)'
  'overlay_text_path=disabled in phase40_16 composition (no queue_text/text_painter usage)'
  'dirty_region_partial_redraw=disabled (full-frame clear + full panel/card redraw each frame)'
  'clip_scissor_specialization=disabled in phase40_16 composition (no clip commands enqueued)'
  'secondary_command_lists_rotation=disabled by simplification (single static command pattern per frame)'
  'advanced_telemetry_and_gauge_animation=disabled (replaced by static gauge placeholder rect)'
  'forensic_stage_markers=disabled (no left/right forensic submission path)'
) | Set-Content -Path $f10 -Encoding utf8

@(
  'minimal_pipeline='
  '1 begin_frame'
  '2 clear full window'
  '3 draw left panel solid rect'
  '4 draw right card stack solid rects'
  '5 draw static gauge placeholder rect'
  '6 end_frame'
  '7 present'
  'frame_path=tick-driven full redraw'
  'command_scope=single simple static composition (rect-dominant)'
) | Set-Content -Path $f13 -Encoding utf8

@(
  'reintroduce_order_1=static text labels (non-animated)'
  'reintroduce_order_2=ui tree interactions without forensic overlays'
  'reintroduce_order_3=clip/scissor behavior with explicit replay tests'
  'reintroduce_order_4=gauge arcs/circles (static first, then animated)'
  'reintroduce_order_5=telemetry updates and advanced diagnostics'
  'reintroduce_order_6=forensics tooling only behind explicit debug flags'
) | Set-Content -Path $f15 -Encoding utf8

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

  .\tools\enter_msvc_env.ps1 *> $f12

  $plan = Get-Content -Raw -LiteralPath $graphPlan | ConvertFrom-Json
  foreach ($node in $plan.nodes) {
    if ($null -eq $node.cmd -or [string]::IsNullOrWhiteSpace([string]$node.cmd)) {
      continue
    }

    "=== NODE: $($node.desc) ===" | Add-Content -Path $f12 -Encoding utf8
    "CMD: $($node.cmd)" | Add-Content -Path $f12 -Encoding utf8

    $cmdOut = cmd.exe /d /c $node.cmd 2>&1
    if ($cmdOut) {
      $cmdOut | Add-Content -Path $f12 -Encoding utf8
    }

    if ($LASTEXITCODE -ne 0) {
      throw "graph_node_failed:$($node.id)"
    }
  }

  $buildOk = $true
}
catch {
  $_ | Out-String | Add-Content -Path $f12 -Encoding utf8
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

$runText | Set-Content -Path $f14 -Encoding utf8

$leftVisible = $runText -match 'widget_phase40_12_left=1'
$rightVisible = $runText -match 'widget_phase40_12_right=1'
$fullSignal = $runText -match 'widget_phase40_12_full=1'
$tickPath = $runText -match 'widget_phase40_12_frame_path=TICK'
$paintPath = $runText -match 'widget_phase40_12_frame_path=PAINT'
$minimalPipeline = $runText -match 'widget_phase40_16_minimal_pipeline=1'
$textDisabledSignal = $runText -match 'widget_phase40_16_text_overlay_disabled=1'
$clipDisabledSignal = $runText -match 'widget_phase40_16_clip_path_disabled=1'
$forensicsDisabledSignal = $runText -match 'widget_phase40_16_forensics_disabled=1'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

$manualVisualStable = ($env:NGK_PHASE40_16_VISUAL_OK -eq '1')
$majorFlashingPersists = -not $manualVisualStable
$blackCorruptionPersists = -not $manualVisualStable

$disabledPathStillActive = ''
if ($runText -match 'widget_phase40_13_left_assert_after_submission=1') {
  $disabledPathStillActive = 'forensic overlays still active (phase40_13 forensic assertions present)'
} elseif ($runText -match 'widget_phase40_typography_title=1|widget_phase40_typography_numeric=1') {
  $disabledPathStillActive = 'text/typography overlay still active'
}

$remainingInstability = ''
if (-not $manualVisualStable) {
  $remainingInstability = 'manual visual stability confirmation missing (set NGK_PHASE40_16_VISUAL_OK=1 after confirming no flashing/corruption).'
}

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_disabled_paths.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_minimal_pipeline_notes.txt',
  '14_runtime_observations.txt',
  '15_rebuild_plan.txt'
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

$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $leftVisible -and $rightVisible -and $fullSignal -and $tickPath -and (-not $paintPath) -and $minimalPipeline -and $textDisabledSignal -and $clipDisabledSignal -and $forensicsDisabledSignal -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$pass = $autoSignalsOk -and $manualVisualStable -and (-not $majorFlashingPersists) -and (-not $blackCorruptionPersists)
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=40_16_minimal_stable_frame_recovery'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "left_region_continuous_signal=$leftVisible"
  "right_region_continuous_signal=$rightVisible"
  "full_composition_signal=$fullSignal"
  "minimal_pipeline_signal=$minimalPipeline"
  "text_overlay_disabled_signal=$textDisabledSignal"
  "clip_path_disabled_signal=$clipDisabledSignal"
  "forensics_disabled_signal=$forensicsDisabledSignal"
  "manual_visual_stable=$manualVisualStable"
  "major_flashing_persists=$majorFlashingPersists"
  "black_corruption_persists=$blackCorruptionPersists"
  "disabled_path_still_active=$disabledPathStillActive"
  "remaining_instability_symptom=$remainingInstability"
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
  if ([string]::IsNullOrWhiteSpace($disabledPathStillActive)) {
    Write-Output 'disabled_path_still_active=none_detected_from_runtime_signals'
  } else {
    Write-Output "disabled_path_still_active=$disabledPathStillActive"
  }
  if ([string]::IsNullOrWhiteSpace($remainingInstability)) {
    Write-Output 'remaining_instability_symptom=unknown'
  } else {
    Write-Output "remaining_instability_symptom=$remainingInstability"
  }
}

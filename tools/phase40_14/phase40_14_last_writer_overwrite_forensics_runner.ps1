param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 40_14 -tag 'last_writer_overwrite_forensics'
if (-not $paths -or $paths.Count -lt 2) {
  throw 'runtime_runner_common did not return PF/ZIP'
}

$root = (Get-Location).Path
$pf = ([string]$paths[0]).Trim()
$zip = ([string]$paths[1]).Trim()
$proofRoot = Join-Path $root '_proof'
$proofResolved = (Resolve-Path -LiteralPath $proofRoot).Path
$legalPrefix = $proofResolved + [System.IO.Path]::DirectorySeparatorChar

$f00 = Join-Path $pf '00_env.txt'
$f01 = Join-Path $pf '01_status.txt'
$f02 = Join-Path $pf '02_head.txt'
$f10 = Join-Path $pf '10_submission_trace.txt'
$f11 = Join-Path $pf '11_execution_trace.txt'
$f12 = Join-Path $pf '12_files_touched.txt'
$f13 = Join-Path $pf '13_build_output.txt'
$f14 = Join-Path $pf '14_runtime_observations.txt'
$f15 = Join-Path $pf '15_behavior_summary.txt'
$f20 = Join-Path $pf '20_post_submission_command_log.jsonl'
$f21 = Join-Path $pf '21_first_intersector_after_left.txt'
$f22 = Join-Path $pf '22_first_covering_writer_after_left.txt'
$f23 = Join-Path $pf '23_last_command_before_present.txt'
$f24 = Join-Path $pf '24_present_events.txt'
$f25 = Join-Path $pf '25_classification.txt'
$f98 = Join-Path $pf '98_gate_phase40_14.txt'

@(
  "timestamp=$(Get-Date -Format o)"
  "cwd=$root"
  "phase=40_14_last_writer_overwrite_forensics"
) | Set-Content -Path $f00 -Encoding utf8

git status *> $f01
git log -1 *> $f02
git diff --name-only | Set-Content -Path $f12 -Encoding utf8

@(
  'forensic_log_sink=20_post_submission_command_log.jsonl'
  'left_forensic_submission=apps/widget_sandbox/main.cpp uses debug_set_left_forensic_region + debug_mark_left_forensic_submitted'
  'renderer_submit_execute_logs=engine/gfx/win32/src/d3d11_renderer.cpp forensic_log_command submit/execute paths'
  'present_logs=engine/gfx/win32/src/d3d11_renderer.cpp forensic_log_present pre_present/present_ok/present_failed'
) | Set-Content -Path $f10 -Encoding utf8

@(
  'execution_order_key=exec_index'
  'left_anchor_key=left_forensic_seq'
  'first_overwriter=first execute command after left_forensic_seq that intersects/covers left region'
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
    $oldForensics = $env:NGK_FORENSICS_LOG

    $env:NGK_WIDGET_RECOVERY_MODE = '1'
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = '1'
    $env:NGK_WIDGET_SANDBOX_DEMO = '1'
    $env:NGK_FORENSICS_LOG = $f20

    if (Test-Path -LiteralPath $f20) {
      Remove-Item -Force -LiteralPath $f20
    }

    $runOut = & $widgetExe '--demo' 2>&1
    $runText = ($runOut | Out-String)
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)

    $env:NGK_WIDGET_RECOVERY_MODE = $oldRecovery
    $env:NGK_RENDER_RECOVERY_FORCE_FULL = $oldForceFull
    $env:NGK_WIDGET_SANDBOX_DEMO = $oldDemo
    $env:NGK_FORENSICS_LOG = $oldForensics
  }
  catch {
    $runText = ($_ | Out-String)
  }
}

$runText | Set-Content -Path $f14 -Encoding utf8

$entries = @()
if (Test-Path -LiteralPath $f20) {
  $rawLines = Get-Content -LiteralPath $f20
  foreach ($line in $rawLines) {
    if (-not [string]::IsNullOrWhiteSpace($line)) {
      try {
        $entries += ($line | ConvertFrom-Json)
      }
      catch {}
    }
  }
}

$leftForensicSeq = 0
foreach ($entry in $entries) {
  if ($entry.PSObject.Properties.Name -contains 'left_forensic_seq') {
    $seqVal = 0
    [void][int64]::TryParse([string]$entry.left_forensic_seq, [ref]$seqVal)
    if ($seqVal -gt $leftForensicSeq) {
      $leftForensicSeq = $seqVal
    }
  }
}

$executeCommands = @($entries | Where-Object { $_.event -eq 'command' -and $_.phase -eq 'execute' })
$postSubmitCommands = @($executeCommands | Where-Object { [int64]$_.seq -gt [int64]$leftForensicSeq })
$intersectors = @($postSubmitCommands | Where-Object { $_.intersects_left -eq $true } | Sort-Object {[int64]$_.exec_index}, {[int64]$_.seq})
$coverers = @($postSubmitCommands | Where-Object { $_.covers_left -eq $true } | Sort-Object {[int64]$_.exec_index}, {[int64]$_.seq})
$firstIntersector = if ($intersectors.Count -gt 0) { $intersectors[0] } else { $null }
$firstCoverer = if ($coverers.Count -gt 0) { $coverers[0] } else { $null }
$lastBeforePresent = if ($executeCommands.Count -gt 0) { ($executeCommands | Sort-Object {[int64]$_.exec_index} -Descending | Select-Object -First 1) } else { $null }
$presentEvents = @($entries | Where-Object { $_.phase -eq 'present' })

if ($firstIntersector) {
  @(
    "exec_index=$($firstIntersector.exec_index)"
    "seq=$($firstIntersector.seq)"
    "type=$($firstIntersector.type)"
    "stage=$($firstIntersector.stage)"
    "full_screen=$($firstIntersector.full_screen)"
    "intersects_left=$($firstIntersector.intersects_left)"
    "covers_left=$($firstIntersector.covers_left)"
  ) | Set-Content -Path $f21 -Encoding utf8
} else {
  'none' | Set-Content -Path $f21 -Encoding utf8
}

if ($firstCoverer) {
  @(
    "exec_index=$($firstCoverer.exec_index)"
    "seq=$($firstCoverer.seq)"
    "type=$($firstCoverer.type)"
    "stage=$($firstCoverer.stage)"
    "full_screen=$($firstCoverer.full_screen)"
    "intersects_left=$($firstCoverer.intersects_left)"
    "covers_left=$($firstCoverer.covers_left)"
    "x=$($firstCoverer.x)"
    "y=$($firstCoverer.y)"
    "w=$($firstCoverer.w)"
    "h=$($firstCoverer.h)"
  ) | Set-Content -Path $f22 -Encoding utf8
} else {
  'none' | Set-Content -Path $f22 -Encoding utf8
}

if ($lastBeforePresent) {
  @(
    "exec_index=$($lastBeforePresent.exec_index)"
    "seq=$($lastBeforePresent.seq)"
    "type=$($lastBeforePresent.type)"
    "stage=$($lastBeforePresent.stage)"
  ) | Set-Content -Path $f23 -Encoding utf8
} else {
  'none' | Set-Content -Path $f23 -Encoding utf8
}

if ($presentEvents.Count -gt 0) {
  ($presentEvents | ConvertTo-Json -Depth 6) | Set-Content -Path $f24 -Encoding utf8
} else {
  '[]' | Set-Content -Path $f24 -Encoding utf8
}

$presentOk = $false
$presentFailed = $false
foreach ($evt in $presentEvents) {
  if ($evt.event -eq 'present_ok') { $presentOk = $true }
  if ($evt.event -eq 'present_failed') { $presentFailed = $true }
}

$classification = 'unknown_overwrite_source'
if ($leftForensicSeq -le 0) {
  $classification = 'unknown_overwrite_source'
} elseif ($postSubmitCommands.Count -eq 0) {
  $classification = 'wrong_command_list_presented'
} elseif ((-not $firstIntersector) -and $presentOk) {
  $classification = 'wrong_command_list_presented'
} elseif ($firstCoverer -and $firstCoverer.type -eq 'clear') {
  $classification = 'post_submit_clear'
} elseif ($firstCoverer -and $firstCoverer.full_screen -eq $true -and $firstCoverer.type -eq 'rect_fill') {
  if ($firstCoverer.stage -eq 'frame_clear') {
    $classification = 'duplicate_background_pass'
  } else {
    $classification = 'full_frame_overpaint'
  }
} elseif ($firstCoverer -and ($firstCoverer.stage -match 'left|ui_tree|panel')) {
  $classification = 'late_left_panel_fill'
} elseif (-not $presentOk -and $presentFailed) {
  $classification = 'stale_composition_rebuild'
} elseif ($firstIntersector) {
  $classification = 'full_frame_overpaint'
}

@(
  "left_forensic_seq=$leftForensicSeq"
  "execute_command_count=$($executeCommands.Count)"
  "post_submit_command_count=$($postSubmitCommands.Count)"
  "present_ok=$presentOk"
  "present_failed=$presentFailed"
  "classification=$classification"
) | Set-Content -Path $f25 -Encoding utf8

$leftAssert = $runText -match 'widget_phase40_13_left_assert_after_submission=1'
$rightAssert = $runText -match 'widget_phase40_13_right_assert_after_submission=1'
$fullSignal = $runText -match 'widget_phase40_12_full=1'
$pathTick = $runText -match 'widget_phase40_12_frame_path=TICK'
$pathPaint = $runText -match 'widget_phase40_12_frame_path=PAINT'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "run_exit_code=$runExitCode"
  "clean_exit=$cleanExit"
  "left_assert=$leftAssert"
  "right_assert=$rightAssert"
  "full_logic_marker=$fullSignal"
  "tick_path_seen=$pathTick"
  "paint_path_seen=$pathPaint"
  "left_forensic_seq=$leftForensicSeq"
  "execute_command_count=$($executeCommands.Count)"
  "post_submit_command_count=$($postSubmitCommands.Count)"
  "present_event_count=$($presentEvents.Count)"
  "classification=$classification"
) | Set-Content -Path $f15 -Encoding utf8

$requiredFiles = @(
  '00_env.txt',
  '01_status.txt',
  '02_head.txt',
  '10_submission_trace.txt',
  '11_execution_trace.txt',
  '12_files_touched.txt',
  '13_build_output.txt',
  '14_runtime_observations.txt',
  '15_behavior_summary.txt',
  '20_post_submission_command_log.jsonl',
  '21_first_intersector_after_left.txt',
  '22_first_covering_writer_after_left.txt',
  '23_last_command_before_present.txt',
  '24_present_events.txt',
  '25_classification.txt'
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

$knownBuckets = @(
  'duplicate_background_pass',
  'late_left_panel_fill',
  'full_frame_overpaint',
  'stale_composition_rebuild',
  'wrong_command_list_presented',
  'post_submit_clear',
  'unknown_overwrite_source'
)
$classificationKnown = $knownBuckets -contains $classification
$autoSignalsOk = $buildOk -and $runOk -and $cleanExit -and $leftAssert -and $rightAssert -and $fullSignal -and $pathTick -and (-not $pathPaint) -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal -and $classificationKnown -and ($leftForensicSeq -gt 0)
$gate = if ($autoSignalsOk -and $classification -ne 'unknown_overwrite_source') { 'PASS' } else { 'FAIL' }

@(
  'phase=40_14_last_writer_overwrite_forensics'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "left_assert=$leftAssert"
  "right_assert=$rightAssert"
  "full_logic_marker=$fullSignal"
  "tick_path_seen=$pathTick"
  "paint_path_seen=$pathPaint"
  "left_forensic_seq=$leftForensicSeq"
  "classification=$classification"
  "auto_signals_ok=$autoSignalsOk"
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
  if (Test-Path -LiteralPath $f14) {
    Get-Content -Path $f14 -Tail 220
  }
  if (Test-Path -LiteralPath $f25) {
    Get-Content -Path $f25
  }
}

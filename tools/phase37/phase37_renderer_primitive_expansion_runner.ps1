param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 37 -tag 'renderer_primitive_expansion'
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
$f10 = Join-Path $pf '10_plan.txt'
$f11 = Join-Path $pf '11_files_touched.txt'
$f12 = Join-Path $pf '12_build_output.txt'
$f13 = Join-Path $pf '13_demo_run.txt'
$f14 = Join-Path $pf '14_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase37.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=37_renderer_primitive_expansion'
  'goal_1=add_rounded_rect_circle_arc_ring_primitives'
  'goal_2=add_stroke_thickness_and_alpha_layering_path'
  'goal_3=prove_primitives_in_widget_sandbox_surface'
) | Set-Content -Path $f10 -Encoding utf8

git diff --name-only | Set-Content -Path $f11 -Encoding utf8

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

$runOk = $false
$runExitCode = -999
$widgetExe = Resolve-WidgetExePath -RootPath $root -PlanPath $graphPlan -PlanPathAlt $graphPlanAlt
if ($buildOk -and $widgetExe) {
  try {
    $runOut = & $widgetExe '--demo' 2>&1
    $runOut | Set-Content -Path $f13 -Encoding utf8
    $runExitCode = $LASTEXITCODE
    $runOk = ($runExitCode -eq 0)
  }
  catch {
    $_ | Out-String | Set-Content -Path $f13 -Encoding utf8
  }
} else {
  @(
    "build_ok=$buildOk"
    "widget_exe=$widgetExe"
    'run_skipped=1'
  ) | Set-Content -Path $f13 -Encoding utf8
}

$runText = if (Test-Path -LiteralPath $f13) { Get-Content -Raw -LiteralPath $f13 } else { '' }

$roundedRect = $runText -match 'widget_primitive_rounded_rect=1'
$roundedOutline = $runText -match 'widget_primitive_rounded_rect_outline=1'
$circle = $runText -match 'widget_primitive_circle=1'
$circleOutline = $runText -match 'widget_primitive_circle_outline=1'
$arcOrRing = ($runText -match 'widget_primitive_arc=1') -or ($runText -match 'widget_primitive_ring_segment=1')
$strokeVisible = $runText -match 'widget_primitive_stroke_thickness=1'
$alphaVisible = $runText -match 'widget_primitive_alpha_layering=1'
$clipGroundwork = $runText -match 'widget_primitive_clip_groundwork=1'
$existingRectText = ($runText -match 'widget_text_shared_path=1') -and ($runText -match 'widget_first_frame=1')
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'Added primitives: rounded rect fill/outline, circle fill/outline, arc stroke, and ring-segment fill with reusable queue APIs.'
  'Rounded rectangles are rendered with RoundRect using queued radius and fill/outline variants.'
  'Circles are generated via ellipse geometry around center/radius and support stroke thickness via pen width.'
  'Arcs/ring segments are generated from deterministic angle math; ring segments are tessellated into polygon strips.'
  'Stroke thickness is handled on outline primitives through pen width parameters.'
  'Alpha layering is handled by ordered overlay replay with per-command alpha blending through dynamic AlphaBlend path.'
  'Demo surface in widget_sandbox renders a rounded metric panel, circular elements, partial arc/ring, clip-groundwork, and layered alpha composition.'
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "run_exit_code=$runExitCode"
  "rounded_rect_signal=$roundedRect"
  "rounded_outline_signal=$roundedOutline"
  "circle_signal=$circle"
  "circle_outline_signal=$circleOutline"
  "arc_or_ring_signal=$arcOrRing"
  "stroke_signal=$strokeVisible"
  "alpha_signal=$alphaVisible"
  "clip_groundwork_signal=$clipGroundwork"
  "existing_rect_text_signal=$existingRectText"
  "clean_exit=$cleanExit"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_plan.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_demo_run.txt',
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

$pass = $buildOk -and $runOk -and $cleanExit -and $roundedRect -and $roundedOutline -and $circle -and $circleOutline -and $arcOrRing -and $strokeVisible -and $alphaVisible -and $existingRectText -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=37_renderer_primitive_expansion'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "clean_exit=$cleanExit"
  "rounded_rect_signal=$roundedRect"
  "rounded_outline_signal=$roundedOutline"
  "circle_signal=$circle"
  "circle_outline_signal=$circleOutline"
  "arc_or_ring_signal=$arcOrRing"
  "stroke_signal=$strokeVisible"
  "alpha_signal=$alphaVisible"
  "clip_groundwork_signal=$clipGroundwork"
  "existing_rect_text_signal=$existingRectText"
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
  if (Test-Path -LiteralPath $f12) {
    Get-Content -Path $f12 -Tail 120
  }
  if (Test-Path -LiteralPath $f13) {
    Get-Content -Path $f13 -Tail 220
  }
}

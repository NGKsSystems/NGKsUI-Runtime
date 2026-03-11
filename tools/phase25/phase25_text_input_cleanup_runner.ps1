param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 25 -tag 'text_input_cleanup'
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
$f13 = Join-Path $pf '13_widget_sandbox_run.txt'
$f14 = Join-Path $pf '14_behavior_summary.txt'
$f98 = Join-Path $pf '98_gate_phase25.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=25_text_rendering_input_cleanup'
  'goal_1=shared_label_button_text_path'
  'goal_2=centralized_input_routing_via_ui_router'
  'goal_3=button_state_transitions_normal_hover_pressed_released'
  'goal_4=click_updates_visible_status_through_retained_tree'
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
    $runOut = & $widgetExe 2>&1
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

$treeExists = $runText -match 'widget_tree_exists=1'
$layoutVertical = $runText -match 'widget_layout_vertical=1'
$textSharedPath = $runText -match 'widget_text_shared_path=1'
$routerPath = $runText -match 'widget_input_routed_via_router=1'
$titleShown = $runText -match 'widget_label_title='
$statusShown = $runText -match 'widget_label_status='
$buttonShown = $runText -match 'widget_button_text='
$buttonHover = $runText -match 'widget_button_state=hover'
$buttonPressed = $runText -match 'widget_button_state=pressed'
$buttonReleased = $runText -match 'widget_button_state=released'
$clickSignal = $runText -match 'widget_button_click_count=1'
$statusChanged = $runText -match 'widget_status_text=status: clicks=1'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'Text rendering is shared through engine/ui/text_painter.hpp and both Label::render and Button::render route text to renderer.queue_text.'
  'Input routing is centralized through engine/ui/input_router.hpp, where mouse move/button messages are converted and dispatched into UITree once.'
  'Button visual states include normal, hover, pressed, and released; transitions are driven by centralized pointer routing and hit-testing through UI tree dispatch.'
  'Click dispatch originates from centralized release-over-hit logic in Button::on_mouse_up, which invokes callback and updates status text.'
  'Sandbox visible state changes on click via status label text update and window title update with incremented click counter, followed by UITree invalidation.'
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "run_exit_code=$runExitCode"
  "tree_exists=$treeExists"
  "layout_vertical=$layoutVertical"
  "text_shared_path_signal=$textSharedPath"
  "input_router_signal=$routerPath"
  "title_label_signal=$titleShown"
  "status_label_signal=$statusShown"
  "button_label_signal=$buttonShown"
  "button_hover_signal=$buttonHover"
  "button_pressed_signal=$buttonPressed"
  "button_released_signal=$buttonReleased"
  "click_signal=$clickSignal"
  "status_changed_signal=$statusChanged"
  "clean_exit=$cleanExit"
) | Set-Content -Path $f14 -Encoding utf8

$requiredFiles = @(
  '01_status.txt',
  '02_head.txt',
  '10_plan.txt',
  '11_files_touched.txt',
  '12_build_output.txt',
  '13_widget_sandbox_run.txt',
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

$pass = $buildOk -and $cleanExit -and $treeExists -and $layoutVertical -and $textSharedPath -and $routerPath -and $titleShown -and $statusShown -and $buttonShown -and $buttonHover -and $buttonPressed -and $buttonReleased -and $clickSignal -and $statusChanged -and $pfUnderLegal -and $zipUnderLegal -and $requiredPresent
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=25_text_input_cleanup'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "clean_exit=$cleanExit"
  "tree_exists=$treeExists"
  "layout_vertical=$layoutVertical"
  "text_shared_path_signal=$textSharedPath"
  "input_router_signal=$routerPath"
  "title_label_signal=$titleShown"
  "status_label_signal=$statusShown"
  "button_label_signal=$buttonShown"
  "button_hover_signal=$buttonHover"
  "button_pressed_signal=$buttonPressed"
  "button_released_signal=$buttonReleased"
  "click_signal=$clickSignal"
  "status_changed_signal=$statusChanged"
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
    Get-Content -Path $f13 -Tail 120
  }
}

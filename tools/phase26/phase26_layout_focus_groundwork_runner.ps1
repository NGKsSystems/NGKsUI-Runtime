param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 26 -tag 'layout_focus_groundwork'
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
$f98 = Join-Path $pf '98_gate_phase26.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=26_layout_focus_groundwork'
  'goal_1=vertical_layout_spacing_and_padding'
  'goal_2=horizontal_layout_container_support'
  'goal_3=preferred_size_measurement_flow'
  'goal_4=focus_state_tracking_with_keyboard_hook'
  'goal_5=nested_widget_sandbox_composition'
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
$layoutVerticalSpacing = $runText -match 'widget_layout_vertical_spacing='
$layoutVerticalPadding = $runText -match 'widget_layout_vertical_padding='
$layoutHorizontal = $runText -match 'widget_layout_horizontal=1'
$layoutHorizontalSpacing = $runText -match 'widget_layout_horizontal_spacing='
$layoutHorizontalPadding = $runText -match 'widget_layout_horizontal_padding='
$layoutNested = $runText -match 'widget_layout_nested=1'
$measureFlow = $runText -match 'widget_measure_flow=1'
$textSharedPath = $runText -match 'widget_text_shared_path=1'
$routerPath = $runText -match 'widget_input_routed_via_router=1'
$titleShown = $runText -match 'widget_label_title='
$statusShown = $runText -match 'widget_label_status='
$primaryButtonShown = $runText -match 'widget_button_primary_text='
$secondaryButtonShown = $runText -match 'widget_button_secondary_text='
$buttonHover = $runText -match 'widget_button_state=hover'
$buttonPressed = $runText -match 'widget_button_state=pressed'
$buttonReleased = $runText -match 'widget_button_state=released'
$clickSignal = $runText -match 'widget_button_click_count=1'
$statusChanged = $runText -match 'widget_status_text=status: clicks=1'
$focusIncrement = $runText -match 'widget_focus_target=increment'
$focusReset = $runText -match 'widget_focus_target=reset'
$keyRouted = ($runText -match 'widget_key_routed=9') -or ($runText -match 'widget_focus_navigation_tab=1')
$keyTabNavigation = $runText -match 'widget_focus_navigation_tab=1'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'Padding/spacing are applied by VerticalLayout and HorizontalLayout using explicit container padding fields and spacing deltas between visible children.'
  'Horizontal layout places children deterministically left-to-right, using preferred widths and vertical centering within padded content bounds.'
  'Preferred size is computed in a minimal measure pass: UIElement tracks desired size and containers aggregate child desired sizes plus spacing/padding.'
  'Focus state is stored in UITree as the focused element pointer and mirrored on each widget through UIElement::set_focused.'
  'Click-to-focus routing is centralized: InputRouter forwards pointer messages to UITree, which resolves the topmost focus target and sets focus.'
  'Sandbox demonstrates nested composition with root vertical layout containing labels and a horizontal controls row with two buttons.'
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "run_exit_code=$runExitCode"
  "tree_exists=$treeExists"
  "layout_vertical=$layoutVertical"
  "layout_vertical_spacing_signal=$layoutVerticalSpacing"
  "layout_vertical_padding_signal=$layoutVerticalPadding"
  "layout_horizontal=$layoutHorizontal"
  "layout_horizontal_spacing_signal=$layoutHorizontalSpacing"
  "layout_horizontal_padding_signal=$layoutHorizontalPadding"
  "layout_nested=$layoutNested"
  "measure_flow_signal=$measureFlow"
  "text_shared_path_signal=$textSharedPath"
  "input_router_signal=$routerPath"
  "title_label_signal=$titleShown"
  "status_label_signal=$statusShown"
  "primary_button_label_signal=$primaryButtonShown"
  "secondary_button_label_signal=$secondaryButtonShown"
  "button_hover_signal=$buttonHover"
  "button_pressed_signal=$buttonPressed"
  "button_released_signal=$buttonReleased"
  "click_signal=$clickSignal"
  "status_changed_signal=$statusChanged"
  "focus_increment_signal=$focusIncrement"
  "focus_reset_signal=$focusReset"
  "key_routed_signal=$keyRouted"
  "key_tab_navigation_signal=$keyTabNavigation"
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

$pass = $buildOk -and $cleanExit -and $treeExists -and $layoutVertical -and $layoutVerticalSpacing -and $layoutVerticalPadding -and $layoutHorizontal -and $layoutHorizontalSpacing -and $layoutHorizontalPadding -and $layoutNested -and $measureFlow -and $textSharedPath -and $routerPath -and $titleShown -and $statusShown -and $primaryButtonShown -and $secondaryButtonShown -and $buttonHover -and $buttonPressed -and $buttonReleased -and $clickSignal -and $statusChanged -and $focusIncrement -and $focusReset -and $keyRouted -and $keyTabNavigation -and $pfUnderLegal -and $zipUnderLegal -and $requiredPresent
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=26_layout_focus_groundwork'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "clean_exit=$cleanExit"
  "tree_exists=$treeExists"
  "layout_vertical=$layoutVertical"
  "layout_vertical_spacing_signal=$layoutVerticalSpacing"
  "layout_vertical_padding_signal=$layoutVerticalPadding"
  "layout_horizontal=$layoutHorizontal"
  "layout_horizontal_spacing_signal=$layoutHorizontalSpacing"
  "layout_horizontal_padding_signal=$layoutHorizontalPadding"
  "layout_nested=$layoutNested"
  "measure_flow_signal=$measureFlow"
  "text_shared_path_signal=$textSharedPath"
  "input_router_signal=$routerPath"
  "title_label_signal=$titleShown"
  "status_label_signal=$statusShown"
  "primary_button_label_signal=$primaryButtonShown"
  "secondary_button_label_signal=$secondaryButtonShown"
  "button_hover_signal=$buttonHover"
  "button_pressed_signal=$buttonPressed"
  "button_released_signal=$buttonReleased"
  "click_signal=$clickSignal"
  "status_changed_signal=$statusChanged"
  "focus_increment_signal=$focusIncrement"
  "focus_reset_signal=$focusReset"
  "key_routed_signal=$keyRouted"
  "key_tab_navigation_signal=$keyTabNavigation"
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

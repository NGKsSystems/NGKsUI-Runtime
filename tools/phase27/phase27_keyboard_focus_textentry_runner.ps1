param()

$ErrorActionPreference = 'Stop'

$expectedRoot = 'C:\Users\suppo\Desktop\NGKsSystems\NGKsUI Runtime'
Set-Location $expectedRoot
if ((Get-Location).Path -ne $expectedRoot) {
  Write-Output 'hey stupid Fucker, wrong window again'
  exit 1
}

$paths = pwsh -NoProfile -ExecutionPolicy Bypass -File '.\tools\runtime_runner_common.ps1' -phase 27 -tag 'keyboard_focus_textentry'
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
$f98 = Join-Path $pf '98_gate_phase27.txt'

git status *> $f1
git log -1 *> $f2

@(
  'phase=27_keyboard_focus_textentry'
  'goal_1=centralized_keyboard_routing'
  'goal_2=focus_traversal_tab_and_shift_tab'
  'goal_3=focused_button_activation_enter_space'
  'goal_4=minimal_textbox_char_and_backspace'
  'goal_5=widget_sandbox_keyboard_only_demonstration'
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

$treeExists = $runText -match 'widget_tree_exists=1'
$keyboardRouted = $runText -match 'widget_keyboard_routed_central=1'
$focusTabForward = ($runText -match 'widget_focus_navigation_tab=1') -and ($runText -match 'widget_focus_navigation_tab=2')
$focusShiftTabBackward = $runText -match 'widget_focus_navigation_shift_tab=1'
$focusIncrement = $runText -match 'widget_focus_target=increment'
$focusReset = $runText -match 'widget_focus_target=reset'
$focusTextbox = $runText -match 'widget_focus_target=textbox'
$buttonActivateEnter = $runText -match 'widget_button_key_activate=enter'
$buttonActivateSpace = $runText -match 'widget_button_key_activate=space'
$textboxPresent = $runText -match 'widget_textbox_present=1'
$textEntrySignal = $runText -match 'widget_text_entry_sequence=NGK'
$textboxValueSignal = $runText -match 'widget_textbox_value=NGK'
$backspaceSignal = ($runText -match 'widget_text_backspace=1') -and ($runText -match 'widget_textbox_value=NG')
$statusChanged = ($runText -match 'widget_status_after_key=') -or ($runText -match 'widget_status_text=status:')
$keyboardOnlyDemo = $runText -match 'widget_keyboard_only_demo=1'
$cleanExit = ($runExitCode -eq 0) -and ($runText -match 'widget_sandbox_exit=0')

@(
  'Keyboard input is routed through InputRouter into UITree using key down/up and character events on a single central path.'
  'Focus order is deterministic by retained tree traversal order of focusable elements.'
  'Tab advances focus and Shift+Tab reverses focus using UITree focus_next/focus_previous.'
  'Focused button activation is handled by Button key handlers for Enter and Space.'
  'Text entry is handled by InputBox on_char for printable characters and on_key_down for Backspace.'
  'Sandbox demonstrates keyboard-only interaction via scripted Tab traversal, key activation, character input, and backspace updates.'
  "build_ok=$buildOk"
  "run_ok=$runOk"
  "run_exit_code=$runExitCode"
  "tree_exists=$treeExists"
  "keyboard_routed_signal=$keyboardRouted"
  "focus_tab_forward_signal=$focusTabForward"
  "focus_shift_tab_backward_signal=$focusShiftTabBackward"
  "focus_increment_signal=$focusIncrement"
  "focus_reset_signal=$focusReset"
  "focus_textbox_signal=$focusTextbox"
  "button_activate_enter_signal=$buttonActivateEnter"
  "button_activate_space_signal=$buttonActivateSpace"
  "textbox_present_signal=$textboxPresent"
  "text_entry_signal=$textEntrySignal"
  "textbox_value_signal=$textboxValueSignal"
  "backspace_signal=$backspaceSignal"
  "status_changed_signal=$statusChanged"
  "keyboard_only_demo_signal=$keyboardOnlyDemo"
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

$pass = $buildOk -and $cleanExit -and $treeExists -and $keyboardRouted -and $focusTabForward -and $focusShiftTabBackward -and $focusIncrement -and $focusReset -and $focusTextbox -and $buttonActivateEnter -and $buttonActivateSpace -and $textboxPresent -and $textEntrySignal -and $textboxValueSignal -and $backspaceSignal -and $statusChanged -and $keyboardOnlyDemo -and $requiredPresent -and $pfUnderLegal -and $zipUnderLegal
$gate = if ($pass) { 'PASS' } else { 'FAIL' }

@(
  'phase=27_keyboard_focus_textentry'
  "timestamp=$(Get-Date -Format o)"
  "pf=$pfResolved"
  "zip=$zipCanonical"
  "build_ok=$buildOk"
  "clean_exit=$cleanExit"
  "tree_exists=$treeExists"
  "keyboard_routed_signal=$keyboardRouted"
  "focus_tab_forward_signal=$focusTabForward"
  "focus_shift_tab_backward_signal=$focusShiftTabBackward"
  "focus_increment_signal=$focusIncrement"
  "focus_reset_signal=$focusReset"
  "focus_textbox_signal=$focusTextbox"
  "button_activate_enter_signal=$buttonActivateEnter"
  "button_activate_space_signal=$buttonActivateSpace"
  "textbox_present_signal=$textboxPresent"
  "text_entry_signal=$textEntrySignal"
  "textbox_value_signal=$textboxValueSignal"
  "backspace_signal=$backspaceSignal"
  "status_changed_signal=$statusChanged"
  "keyboard_only_demo_signal=$keyboardOnlyDemo"
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
